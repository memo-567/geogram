import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../services/log_service.dart';

/// Linux BLE peripheral using BlueZ over D-Bus.
/// Advertises FFE0 and exposes GATT chars FFF1 (write), FFF2 (notify), FFF3 (status).
class BleLinuxPeripheral {
  BleLinuxPeripheral({LogService? log}) : _log = log ?? LogService();

  static const _adapterPath = '/org/bluez/hci0';
  // Custom Geogram service UUID (0xFFE0 - avoids conflict with Android's PKOC at 0xFFF0)
  static const _serviceUUID = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const _writeUUID = '0000fff1-0000-1000-8000-00805f9b34fb';
  static const _notifyUUID = '0000fff2-0000-1000-8000-00805f9b34fb';
  static const _statusUUID = '0000fff3-0000-1000-8000-00805f9b34fb';

  final LogService _log;
  DBusClient? _client;
  bool _initialized = false;
  bool _running = false;

  // Track registration success for graceful degradation
  bool _advertisingRegistered = false;
  bool _gattRegistered = false;

  // Connected client tracking: deviceId -> callsign
  final Map<String, String> _connectedClients = {};
  // Reverse lookup: callsign -> deviceId
  final Map<String, String> _callsignToDevice = {};

  /// Check if peripheral is fully operational (both advertising and GATT registered)
  bool get isFullyOperational =>
      _running && _advertisingRegistered && _gattRegistered;

  /// Check if peripheral is in partial mode (initialized but not fully operational)
  bool get isPartialMode => _initialized && !isFullyOperational;

  late _BlueZAdvertisement _advert;
  late _GattApplication _app;
  late _GattService _service;
  late _GattCharacteristicWrite _writeChar;
  late _GattCharacteristicNotify _notifyChar;
  late _GattCharacteristicStatus _statusChar;

  Future<void> initialize({
    required String callsign,
    required int deviceId,
    required Future<Map<String, dynamic>?> Function(
      String deviceIdParam,
      Map<String, dynamic> message,
    )
    onMessage,
  }) async {
    if (!Platform.isLinux) return;
    if (_initialized) return;

    await _logDiagnostics();
    _client = DBusClient.system();

    _notifyChar = _GattCharacteristicNotify(uuid: _notifyUUID, log: _log);
    _writeChar = _GattCharacteristicWrite(
      uuid: _writeUUID,
      log: _log,
      onWrite: (Uint8List data, String deviceId) async {
        try {
          final message =
              json.decode(utf8.decode(data)) as Map<String, dynamic>;
          final response = await onMessage(deviceId, message);
          if (response != null) {
            // Response goes back to the same device that sent the request
            await sendNotification(response, deviceId: deviceId);
          }
        } catch (e) {
          _log.log('BleLinuxPeripheral: failed to handle write: $e');
        }
      },
    );
    _statusChar = _GattCharacteristicStatus(
      uuid: _statusUUID,
      clientCount: () => _notifyChar.subscriberCount,
    );

    _service = _GattService(
      uuid: _serviceUUID,
      characteristics: [_writeChar, _notifyChar, _statusChar],
    );
    _app = _GattApplication(children: [_service]);
    _advert = _BlueZAdvertisement(
      serviceUUID: _serviceUUID,
      callsign: callsign,
      deviceId: deviceId,
    );

    // Export objects
    await _client!.registerObject(_advert);
    await _client!.registerObject(_app);
    await _client!.registerObject(_service);
    await _client!.registerObject(_writeChar);
    await _client!.registerObject(_notifyChar);
    await _client!.registerObject(_statusChar);

    _initialized = true;
    _log.log('BleLinuxPeripheral: initialized BlueZ objects');
  }

  Future<void> start(String callsign) async {
    if (!Platform.isLinux) return;
    if (!_initialized || _client == null) return;

    final client = _client!;
    final adapter = DBusRemoteObject(
      client,
      name: 'org.bluez',
      path: DBusObjectPath(_adapterPath),
    );

    // Check and attempt to power on adapter
    await _ensureAdapterPowered(adapter);

    // Set adapter alias to callsign for device name visibility
    try {
      await adapter.setProperty(
        'org.bluez.Adapter1',
        'Alias',
        DBusString(callsign),
      );
      _log.log('BleLinuxPeripheral: Set adapter alias to $callsign');
    } catch (e) {
      _log.log('BleLinuxPeripheral: Could not set adapter alias: $e');
    }

    // Try advertisement registration
    try {
      await adapter.callMethod(
        'org.bluez.LEAdvertisingManager1',
        'RegisterAdvertisement',
        [DBusObjectPath(_advert.path.value), DBusDict.stringVariant({})],
      );
      _advertisingRegistered = true;
      _log.log('BleLinuxPeripheral: advertisement registered');
    } on DBusMethodResponseException catch (e) {
      _advertisingRegistered = _logRegistrationError('advertisement', e);
    } catch (e) {
      _log.log('BleLinuxPeripheral: advertisement registration failed: $e');
    }

    // Try GATT registration
    try {
      await adapter.callMethod(
        'org.bluez.GattManager1',
        'RegisterApplication',
        [DBusObjectPath(_app.path.value), DBusDict.stringVariant({})],
      );
      _gattRegistered = true;
      _log.log('BleLinuxPeripheral: GATT application registered');
    } on DBusMethodResponseException catch (e) {
      _gattRegistered = _logRegistrationError('GATT', e);
    } catch (e) {
      _log.log('BleLinuxPeripheral: GATT registration failed: $e');
    }

    _running = _advertisingRegistered || _gattRegistered;

    if (!_running) {
      _log.log(
        'BleLinuxPeripheral: Both registrations failed. Continuing in scan-only mode.',
      );
      _log.log(
        '  BLE scanning will work, but this device cannot be discovered by others.',
      );
      _logGenericHints();
    } else if (!isFullyOperational) {
      _log.log(
        'BleLinuxPeripheral: Running in partial mode '
        '(advert: $_advertisingRegistered, gatt: $_gattRegistered)',
      );
    }
  }

  Future<void> stop() async {
    if (!Platform.isLinux) return;
    if (_client == null) return;
    final client = _client!;
    final adapter = DBusRemoteObject(
      client,
      name: 'org.bluez',
      path: DBusObjectPath(_adapterPath),
    );
    try {
      await adapter.callMethod(
        'org.bluez.GattManager1',
        'UnregisterApplication',
        [DBusObjectPath(_app.path.value)],
      );
    } catch (_) {}
    try {
      await adapter.callMethod(
        'org.bluez.LEAdvertisingManager1',
        'UnregisterAdvertisement',
        [DBusObjectPath(_advert.path.value)],
      );
    } catch (_) {}
    _running = false;
  }

  /// Register a client's callsign for this BLE device ID
  void registerClientCallsign(String deviceId, String callsign) {
    final normalizedCallsign = callsign.toUpperCase();
    _connectedClients[deviceId] = normalizedCallsign;
    _callsignToDevice[normalizedCallsign] = deviceId;
    _log.log(
      'BleLinuxPeripheral: Registered client $normalizedCallsign -> $deviceId',
    );
  }

  /// Get the BLE device ID for a callsign
  String? getDeviceIdForCallsign(String callsign) {
    return _callsignToDevice[callsign.toUpperCase()];
  }

  /// Get the callsign for a BLE device ID
  String? getCallsignForDeviceId(String deviceId) {
    return _connectedClients[deviceId];
  }

  /// Send notification to connected clients
  /// If deviceId is specified, log it for debugging (BlueZ broadcasts to all subscribers)
  Future<void> sendNotification(
    Map<String, dynamic> message, {
    String? deviceId,
  }) async {
    if (!Platform.isLinux) return;
    if (!_running) return;
    if (deviceId != null) {
      _log.log('BleLinuxPeripheral: Sending notification to $deviceId');
    }
    await _notifyChar.notify(message);
  }

  Future<void> _logDiagnostics() async {
    try {
      final bluetoothCtl = await Process.run('bash', [
        '-lc',
        'systemctl is-active bluetooth 2>/dev/null',
      ]);
      final state = (bluetoothCtl.stdout as String?)?.trim();
      _log.log(
        'BleLinuxPeripheral: bluetooth service state: ${state ?? 'unknown'}',
      );
    } catch (_) {}

    try {
      final scan = await Process.run('bash', [
        '-lc',
        'hciconfig 2>/dev/null | grep -E \"^hci\"',
      ]);
      final adapters = (scan.stdout as String?)?.trim();
      if (adapters != null && adapters.isNotEmpty) {
        _log.log('BleLinuxPeripheral: adapters detected:\n$adapters');
      }
    } catch (_) {}
  }

  /// Ensure adapter is powered on before registration
  Future<void> _ensureAdapterPowered(DBusRemoteObject adapter) async {
    try {
      final powered = await adapter.getProperty(
        'org.bluez.Adapter1',
        'Powered',
        signature: DBusSignature.boolean,
      );
      if (powered is DBusBoolean && !powered.value) {
        _log.log(
          'BleLinuxPeripheral: Adapter powered off, attempting to power on...',
        );
        await adapter.setProperty(
          'org.bluez.Adapter1',
          'Powered',
          DBusBoolean(true),
        );
        _log.log('BleLinuxPeripheral: Adapter power-on requested');
        // Small delay to let adapter initialize
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      _log.log('BleLinuxPeripheral: Could not check/set adapter power: $e');
    }
  }

  /// Log registration error with actionable hints, returns true if should treat as success
  bool _logRegistrationError(String component, DBusMethodResponseException e) {
    final errorName = e.response.errorName ?? '';
    final errorMessage =
        e.response.values.isNotEmpty ? e.response.values.first.toString() : '';

    _log.log(
      'BleLinuxPeripheral: $component registration failed: $errorName - $errorMessage',
    );

    if (errorName.contains('NotReady') || errorMessage.contains('not ready')) {
      _log.log(
        '  HINT: bluetoothd may not be running. Check: systemctl status bluetooth',
      );
      return false;
    } else if (errorName.contains('NotPermitted') ||
        errorMessage.contains('permission') ||
        errorName.contains('AccessDenied')) {
      _log.log(
        '  HINT: User may need bluetooth group membership: sudo usermod -aG bluetooth \$USER',
      );
      _log.log('  HINT: Then log out and back in for the change to take effect');
      return false;
    } else if (errorName.contains('AlreadyExists')) {
      _log.log('  HINT: Already registered (this is usually OK)');
      return true; // Treat as success
    } else if (errorName.contains('DoesNotExist') ||
        errorMessage.contains('adapter')) {
      _log.log('  HINT: No Bluetooth adapter found. Check: hciconfig');
      return false;
    } else if (errorName.contains('InvalidLength') ||
        errorMessage.contains('length')) {
      _log.log('  HINT: Advertisement data too long. Try shorter callsign.');
      return false;
    }
    return false;
  }

  /// Log generic troubleshooting hints
  void _logGenericHints() {
    _log.log('  Troubleshooting checklist:');
    _log.log('    1. Check bluetooth service: systemctl status bluetooth');
    _log.log('    2. Check adapter: hciconfig hci0');
    _log.log('    3. Check user permissions: groups \$USER | grep bluetooth');
    _log.log('    4. Restart bluetooth: sudo systemctl restart bluetooth');
  }
}

// ===== DBus objects =====

class _BlueZAdvertisement extends DBusObject {
  _BlueZAdvertisement({
    required this.serviceUUID,
    required this.callsign,
    required this.deviceId,
  }) : super(DBusObjectPath('/org/geogram/ble/advertisement0'));

  final String serviceUUID;
  final String callsign;
  final int deviceId;

  /// Geogram marker byte ('>') used to identify Geogram devices
  static const int _geogramMarker = 0x3E;

  /// Build manufacturer data: [0x3E marker][deviceId: 1 byte (1-15)][callsign bytes]
  List<int> get _manufacturerData {
    final data = <int>[
      _geogramMarker,
      // Use 1-byte device_id (1-15) to match BLEIdentityService.parseAdvertisingData format
      // Values > 15 are clamped to 15
      (deviceId > 15 ? 15 : deviceId) & 0xFF,
    ];
    // Add callsign (up to 17 bytes to fit in advertisement)
    final callsignBytes = callsign.codeUnits.take(17).toList();
    data.addAll(callsignBytes);
    return data;
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.bluez.LEAdvertisement1',
      methods: [DBusIntrospectMethod('Release')],
      properties: [
        DBusIntrospectProperty(
          'Type',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'ServiceUUIDs',
          DBusSignature.array(DBusSignature.string),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'LocalName',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'ServiceData',
          DBusSignature('a{sv}'), // dict of string (UUID) to variant
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface('org.freedesktop.DBus.Properties'),
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
  ];

  /// Build ServiceData DBus value: dict of string (UUID) -> variant(byte array)
  /// BlueZ expects a{sv} format for ServiceData
  DBusValue get _serviceDataDBus {
    return DBusDict(
      DBusSignature.string,
      DBusSignature.variant,
      {
        // Service UUID -> Geogram marker data
        DBusString(serviceUUID): DBusVariant(DBusArray.byte(_manufacturerData)),
      },
    );
  }

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.LEAdvertisement1': {
      'Type': DBusString('peripheral'),
      'ServiceUUIDs': DBusArray.string([serviceUUID]),
      'LocalName': DBusString(callsign),
      'ServiceData': _serviceDataDBus,
    },
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.bluez.LEAdvertisement1' &&
        call.name == 'Release') {
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.bluez.LEAdvertisement1') {
      switch (name) {
        case 'Type':
          return DBusGetPropertyResponse(DBusString('peripheral'));
        case 'ServiceUUIDs':
          return DBusGetPropertyResponse(DBusArray.string([serviceUUID]));
        case 'LocalName':
          return DBusGetPropertyResponse(DBusString(callsign));
        case 'ServiceData':
          return DBusGetPropertyResponse(_serviceDataDBus);
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == 'org.bluez.LEAdvertisement1') {
      return DBusGetAllPropertiesResponse({
        'Type': DBusString('peripheral'),
        'ServiceUUIDs': DBusArray.string([serviceUUID]),
        'LocalName': DBusString(callsign),
        'ServiceData': _serviceDataDBus,
      });
    }
    return DBusGetAllPropertiesResponse({});
  }
}

class _GattApplication extends DBusObject {
  _GattApplication({required this.children})
    : super(DBusObjectPath('/org/geogram/gatt'), isObjectManager: true);

  final List<DBusObject> children;

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
    DBusIntrospectInterface('org.freedesktop.DBus.ObjectManager'),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.freedesktop.DBus.ObjectManager' &&
        call.name == 'GetManagedObjects') {
      final managed = <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};

      for (final child in children) {
        managed[child.path] = child.interfacesAndProperties;
        if (child is _GattService) {
          for (final characteristic in child.characteristics) {
            managed[characteristic.path] =
                characteristic.interfacesAndProperties;
          }
        }
      }

      return DBusMethodSuccessResponse([
        DBusDict(
          DBusSignature.objectPath,
          DBusSignature.dict(
            DBusSignature.string,
            DBusSignature.dict(DBusSignature.string, DBusSignature.variant),
          ),
          managed.map(
            (path, ifaces) => MapEntry(
              DBusObjectPath(path.value),
              DBusDict.stringVariant(
                ifaces.map(
                  (iface, props) =>
                      MapEntry(iface, DBusDict.stringVariant(props)),
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _GattService extends DBusObject {
  _GattService({required this.uuid, required List<DBusObject> characteristics})
    : super(DBusObjectPath('/org/geogram/gatt/service0')) {
    _characteristics = characteristics;
  }

  final String uuid;
  late final List<DBusObject> _characteristics;
  List<DBusObject> get characteristics => _characteristics;

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.bluez.GattService1',
      properties: [
        DBusIntrospectProperty(
          'UUID',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Primary',
          DBusSignature.boolean,
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
    DBusIntrospectInterface('org.freedesktop.DBus.Properties'),
  ];

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.GattService1': {
      'UUID': DBusString(uuid),
      'Primary': DBusBoolean(true),
    },
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.bluez.GattService1') {
      switch (name) {
        case 'UUID':
          return DBusGetPropertyResponse(DBusString(uuid));
        case 'Primary':
          return DBusGetPropertyResponse(DBusBoolean(true));
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    // Provide ObjectManager results for child characteristics
    if (call.interface == 'org.freedesktop.DBus.ObjectManager' &&
        call.name == 'GetManagedObjects') {
      final managed = <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
      for (final c in _characteristics) {
        managed[c.path] = c.interfacesAndProperties;
      }
      return DBusMethodSuccessResponse([
        DBusDict(
          DBusSignature.objectPath,
          DBusSignature.dict(
            DBusSignature.string,
            DBusSignature.dict(DBusSignature.string, DBusSignature.variant),
          ),
          managed.map(
            (path, ifaces) => MapEntry(
              DBusObjectPath(path.value),
              DBusDict.stringVariant(
                ifaces.map((k, v) => MapEntry(k, DBusDict.stringVariant(v))),
              ),
            ),
          ),
        ),
      ]);
    }
    return DBusMethodErrorResponse.unknownInterface();
  }
}

class _GattCharacteristicNotify extends DBusObject {
  _GattCharacteristicNotify({required this.uuid, required this.log})
    : super(DBusObjectPath('/org/geogram/gatt/service0/char_notify'));

  final String uuid;
  final LogService log;
  bool _notifying = false;
  int subscriberCount = 0;

  // Maximum chunk size for notifications (matches Android/iOS pattern)
  static const int _maxChunkSize = 480;

  /// Notify connected clients with message, chunking if needed
  Future<void> notify(Map<String, dynamic> message) async {
    if (!_notifying) return;
    try {
      final jsonStr = json.encode(message);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      if (bytes.length <= _maxChunkSize) {
        // Single notification
        emitPropertiesChanged(
          'org.bluez.GattCharacteristic1',
          changedProperties: {'Value': DBusArray.byte(bytes)},
        );
      } else {
        // Chunked notifications
        final totalChunks = (bytes.length / _maxChunkSize).ceil();
        log.log(
          'BleLinuxPeripheral: Sending ${bytes.length} bytes in $totalChunks chunks',
        );

        for (int i = 0; i < bytes.length; i += _maxChunkSize) {
          final end =
              (i + _maxChunkSize < bytes.length) ? i + _maxChunkSize : bytes.length;
          final chunk = bytes.sublist(i, end);

          emitPropertiesChanged(
            'org.bluez.GattCharacteristic1',
            changedProperties: {'Value': DBusArray.byte(chunk)},
          );

          // Delay between chunks to allow receiver to process
          if (end < bytes.length) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      }
    } catch (e) {
      log.log('BleLinuxPeripheral: notify failed: $e');
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.bluez.GattCharacteristic1',
      methods: [
        DBusIntrospectMethod('StartNotify'),
        DBusIntrospectMethod('StopNotify'),
      ],
      properties: [
        DBusIntrospectProperty(
          'UUID',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Service',
          DBusSignature.objectPath,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Flags',
          DBusSignature.array(DBusSignature.string),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Notifying',
          DBusSignature.boolean,
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
    DBusIntrospectInterface('org.freedesktop.DBus.Properties'),
  ];

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.GattCharacteristic1': {
      'UUID': DBusString(uuid),
      'Service': DBusObjectPath('/org/geogram/gatt/service0'),
      'Flags': DBusArray.string(['notify']),
      'Notifying': DBusBoolean(_notifying),
    },
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.bluez.GattCharacteristic1') {
      if (call.name == 'StartNotify') {
        _notifying = true;
        subscriberCount++;
        emitPropertiesChanged(
          'org.bluez.GattCharacteristic1',
          changedProperties: {'Notifying': DBusBoolean(_notifying)},
        );
        return DBusMethodSuccessResponse();
      } else if (call.name == 'StopNotify') {
        _notifying = false;
        subscriberCount = (subscriberCount - 1).clamp(0, 999);
        emitPropertiesChanged(
          'org.bluez.GattCharacteristic1',
          changedProperties: {'Notifying': DBusBoolean(_notifying)},
        );
        return DBusMethodSuccessResponse();
      }
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.bluez.GattCharacteristic1') {
      switch (name) {
        case 'UUID':
          return DBusGetPropertyResponse(DBusString(uuid));
        case 'Service':
          return DBusGetPropertyResponse(
            DBusObjectPath('/org/geogram/gatt/service0'),
          );
        case 'Flags':
          return DBusGetPropertyResponse(DBusArray.string(['notify']));
        case 'Notifying':
          return DBusGetPropertyResponse(DBusBoolean(_notifying));
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}

class _GattCharacteristicWrite extends DBusObject {
  _GattCharacteristicWrite({
    required this.uuid,
    required this.onWrite,
    required this.log,
  }) : super(DBusObjectPath('/org/geogram/gatt/service0/char_write'));

  final String uuid;
  final Future<void> Function(Uint8List data, String deviceId) onWrite;
  final LogService log;

  // Receive buffer per device for chunked writes
  final Map<String, List<int>> _receiveBuffers = {};
  final Map<String, DateTime> _lastReceiveTime = {};
  static const Duration _bufferTimeout = Duration(seconds: 10);

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.bluez.GattCharacteristic1',
      methods: [
        DBusIntrospectMethod(
          'WriteValue',
          args: [
            DBusIntrospectArgument(
              DBusSignature.array(DBusSignature.byte),
              DBusArgumentDirection.in_,
            ),
            DBusIntrospectArgument(
              DBusSignature.dict(DBusSignature.string, DBusSignature.variant),
              DBusArgumentDirection.in_,
            ),
          ],
        ),
      ],
      properties: [
        DBusIntrospectProperty(
          'UUID',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Service',
          DBusSignature.objectPath,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Flags',
          DBusSignature.array(DBusSignature.string),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
    DBusIntrospectInterface('org.freedesktop.DBus.Properties'),
  ];

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.GattCharacteristic1': {
      'UUID': DBusString(uuid),
      'Service': DBusObjectPath('/org/geogram/gatt/service0'),
      'Flags': DBusArray.string(['write', 'write-without-response']),
    },
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.bluez.GattCharacteristic1' &&
        call.name == 'WriteValue') {
      try {
        final bytes = (call.values.first as DBusArray)
            .children
            .cast<DBusByte>()
            .map((b) => b.value)
            .toList();

        // Extract device ID from D-Bus options (second argument)
        String deviceId = 'linux-peer';
        if (call.values.length > 1 && call.values[1] is DBusDict) {
          final options = call.values[1] as DBusDict;
          for (final entry in options.children.entries) {
            if (entry.key is DBusString &&
                (entry.key as DBusString).value == 'device') {
              final devicePath = entry.value;
              if (devicePath is DBusVariant &&
                  devicePath.value is DBusObjectPath) {
                final pathStr = (devicePath.value as DBusObjectPath).value;
                // Extract MAC from path: /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF
                final match =
                    RegExp(r'dev_([0-9A-Fa-f_]+)$').firstMatch(pathStr);
                if (match != null) {
                  deviceId = match.group(1)!.replaceAll('_', ':');
                }
              }
              break;
            }
          }
        }

        // Clean up stale buffers
        _cleanupStaleBuffers();

        // Add to buffer
        _receiveBuffers.putIfAbsent(deviceId, () => []);
        _receiveBuffers[deviceId]!.addAll(bytes);
        _lastReceiveTime[deviceId] = DateTime.now();

        // Try to parse as complete JSON
        try {
          final jsonStr = utf8.decode(_receiveBuffers[deviceId]!);
          json.decode(jsonStr) as Map<String, dynamic>;

          // Success - clear buffer and process
          final completeData =
              Uint8List.fromList(_receiveBuffers[deviceId]!);
          _receiveBuffers.remove(deviceId);
          _lastReceiveTime.remove(deviceId);

          log.log(
            'BleLinuxPeripheral: Complete message (${completeData.length} bytes) from $deviceId',
          );
          await onWrite(completeData, deviceId);
        } on FormatException {
          // JSON not complete yet, wait for more chunks
          log.log(
            'BleLinuxPeripheral: Buffering chunks (${_receiveBuffers[deviceId]!.length} bytes) from $deviceId',
          );
        }
      } catch (e) {
        log.log('BleLinuxPeripheral: WriteValue error: $e');
      }
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  void _cleanupStaleBuffers() {
    final now = DateTime.now();
    final staleDevices = <String>[];

    for (final entry in _lastReceiveTime.entries) {
      if (now.difference(entry.value) > _bufferTimeout) {
        staleDevices.add(entry.key);
      }
    }

    for (final deviceId in staleDevices) {
      log.log('BleLinuxPeripheral: Clearing stale buffer for $deviceId');
      _receiveBuffers.remove(deviceId);
      _lastReceiveTime.remove(deviceId);
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.bluez.GattCharacteristic1') {
      switch (name) {
        case 'UUID':
          return DBusGetPropertyResponse(DBusString(uuid));
        case 'Service':
          return DBusGetPropertyResponse(
            DBusObjectPath('/org/geogram/gatt/service0'),
          );
        case 'Flags':
          return DBusGetPropertyResponse(
            DBusArray.string(['write', 'write-without-response']),
          );
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}

class _GattCharacteristicStatus extends DBusObject {
  _GattCharacteristicStatus({required this.uuid, required this.clientCount})
    : super(DBusObjectPath('/org/geogram/gatt/service0/char_status'));

  final String uuid;
  final int Function() clientCount;

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.bluez.GattCharacteristic1',
      methods: [
        DBusIntrospectMethod(
          'ReadValue',
          args: [
            DBusIntrospectArgument(
              DBusSignature.dict(DBusSignature.string, DBusSignature.variant),
              DBusArgumentDirection.in_,
            ),
          ],
        ),
      ],
      properties: [
        DBusIntrospectProperty(
          'UUID',
          DBusSignature.string,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Service',
          DBusSignature.objectPath,
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Flags',
          DBusSignature.array(DBusSignature.string),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface('org.freedesktop.DBus.Introspectable'),
    DBusIntrospectInterface('org.freedesktop.DBus.Properties'),
  ];

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.GattCharacteristic1': {
      'UUID': DBusString(uuid),
      'Service': DBusObjectPath('/org/geogram/gatt/service0'),
      'Flags': DBusArray.string(['read']),
    },
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == 'org.bluez.GattCharacteristic1' &&
        call.name == 'ReadValue') {
      final status = json.encode({'status': 'ready', 'clients': clientCount()});
      return DBusMethodSuccessResponse([
        DBusArray.byte(Uint8List.fromList(utf8.encode(status))),
      ]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.bluez.GattCharacteristic1') {
      switch (name) {
        case 'UUID':
          return DBusGetPropertyResponse(DBusString(uuid));
        case 'Service':
          return DBusGetPropertyResponse(
            DBusObjectPath('/org/geogram/gatt/service0'),
          );
        case 'Flags':
          return DBusGetPropertyResponse(DBusArray.string(['read']));
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}
