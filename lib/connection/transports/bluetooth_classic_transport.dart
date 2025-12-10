/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Bluetooth Classic Transport - SPP/RFCOMM for fast data transfer
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../../services/log_service.dart';
import '../../services/app_args.dart';
import '../../services/bluetooth_classic_service.dart';
import '../../services/bluetooth_classic_pairing_service.dart';
import '../transport.dart';
import '../transport_message.dart';
import '../transfer_session.dart';

/// Bluetooth Classic Transport for fast SPP/RFCOMM data transfer
///
/// This transport is used for BLE+ connections - devices that have been
/// paired via Bluetooth Classic in addition to BLE discovery.
///
/// Priority: 35 (between Station at 30 and BLE at 40)
///
/// Use cases:
/// - Large data transfers (>10KB) where BLE would be too slow
/// - Desktop-to-Android connections where BLE server isn't available
/// - Batch operations declared via TransferSession
///
/// Platform Support:
/// - Android: Full support (server + client)
/// - Linux/macOS/Windows: Client only (connects to Android servers)
/// - iOS: Not supported (Apple doesn't allow SPP)
/// - Web: Not supported
class BluetoothClassicTransport extends Transport with TransportMixin {
  @override
  String get id => 'bluetooth_classic';

  @override
  String get name => 'Bluetooth Classic';

  @override
  int get priority => 35; // Between Station (30) and BLE (40)

  @override
  bool get isAvailable {
    // Not available on web or in internet-only mode
    if (kIsWeb) return false;
    if (AppArgs().internetOnly) return false;
    // Check platform-level availability
    return BluetoothClassicService.isAvailable;
  }

  final BluetoothClassicService _btService = BluetoothClassicService();
  final BluetoothClassicPairingService _pairingService = BluetoothClassicPairingService();

  /// Timeout for Bluetooth Classic operations
  final Duration timeout;

  /// Data size threshold for automatic BLE+ usage
  final int autoUpgradeThreshold;

  /// Stream subscriptions
  StreamSubscription<BluetoothClassicConnection>? _connectionSubscription;
  StreamSubscription<({String macAddress, Uint8List data})>? _dataSubscription;

  BluetoothClassicTransport({
    this.timeout = const Duration(seconds: 30),
    this.autoUpgradeThreshold = 10 * 1024, // 10KB default
  });

  @override
  Future<void> initialize() async {
    if (!isAvailable) {
      LogService().log('BluetoothClassicTransport: Not available on this platform');
      return;
    }

    LogService().log('BluetoothClassicTransport: Initializing...');

    // Initialize services
    await _btService.initialize();
    await _pairingService.initialize();

    // Subscribe to connection state changes
    _connectionSubscription = _btService.connectionStateStream.listen(
      _handleConnectionStateChange,
    );

    // Subscribe to incoming data
    _dataSubscription = _btService.dataStream.listen(
      _handleIncomingData,
    );

    // Start server if we can be a server (Android)
    if (BluetoothClassicService.canBeServer) {
      await _btService.startServer();
    }

    markInitialized();
    LogService().log(
      'BluetoothClassicTransport: Initialized '
      '(server=${BluetoothClassicService.canBeServer}, '
      'client=${BluetoothClassicService.canBeClient})',
    );
  }

  @override
  Future<void> dispose() async {
    LogService().log('BluetoothClassicTransport: Disposing...');

    await _connectionSubscription?.cancel();
    await _dataSubscription?.cancel();
    _connectionSubscription = null;
    _dataSubscription = null;

    // End all transfer sessions
    await TransferSession.endAllSessions();

    await disposeMixin();
    LogService().log('BluetoothClassicTransport: Disposed');
  }

  @override
  Future<bool> canReach(String callsign) async {
    if (!isInitialized) return false;

    // Check if device is BLE+ paired
    if (!_pairingService.isBLEPlus(callsign)) {
      return false;
    }

    // Get the Classic MAC address
    final classicMac = _pairingService.getClassicMac(callsign);
    if (classicMac == null) {
      return false;
    }

    // Verify we can connect (device is paired at system level)
    return await _btService.canConnect(classicMac);
  }

  @override
  Future<int> getQuality(String callsign) async {
    if (!isInitialized) return 0;
    if (!_pairingService.isBLEPlus(callsign)) return 0;

    // Bluetooth Classic has consistent quality when paired
    // Return 75 as baseline (better than BLE's RSSI-based quality)
    final classicMac = _pairingService.getClassicMac(callsign);
    if (classicMac == null) return 0;

    // If currently connected, return higher quality
    if (_btService.isConnected(classicMac)) {
      return 90;
    }

    // Can reach but not connected
    return 75;
  }

  @override
  Future<TransportResult> send(
    TransportMessage message, {
    Duration? timeout,
  }) async {
    if (!isInitialized) {
      return TransportResult.failure(
        error: 'Bluetooth Classic transport not initialized',
        transportUsed: id,
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Check if device is reachable via Bluetooth Classic
      final canReachDevice = await canReach(message.targetCallsign);
      if (!canReachDevice) {
        return TransportResult.failure(
          error: 'Device ${message.targetCallsign} not paired for BLE+',
          transportUsed: id,
        );
      }

      // Get the Classic MAC
      final classicMac = _pairingService.getClassicMac(message.targetCallsign);
      if (classicMac == null) {
        return TransportResult.failure(
          error: 'No Classic MAC for ${message.targetCallsign}',
          transportUsed: id,
        );
      }

      // Check if we should use an existing session or establish new connection
      final hasSession = TransferSession.hasActiveSession(message.targetCallsign);
      final sessionMac = TransferSession.getClassicMac(message.targetCallsign);

      bool needsConnect = !_btService.isConnected(classicMac);

      // If there's an active session using BLE+, connection should already be open
      if (hasSession && sessionMac != null) {
        needsConnect = false;
      }

      // Connect if needed
      if (needsConnect) {
        final connected = await _btService.connect(classicMac);
        if (!connected) {
          stopwatch.stop();
          return TransportResult.failure(
            error: 'Failed to connect to $classicMac',
            transportUsed: id,
          );
        }
      }

      // Encode the message
      final data = _encodeMessage(message);

      // Send the data
      final success = await _btService.sendData(classicMac, data);

      // Disconnect if not in a session
      if (!hasSession && _btService.isConnected(classicMac)) {
        await _btService.disconnect(classicMac);
      }

      stopwatch.stop();

      if (success) {
        // Update last connected time
        _pairingService.updateLastConnected(message.targetCallsign);

        final result = TransportResult.success(
          transportUsed: id,
          latency: stopwatch.elapsed,
        );
        recordMetrics(result);
        return result;
      } else {
        final result = TransportResult.failure(
          error: 'Bluetooth Classic send failed',
          transportUsed: id,
        );
        recordMetrics(result);
        return result;
      }
    } catch (e) {
      stopwatch.stop();
      final result = TransportResult.failure(
        error: e.toString(),
        transportUsed: id,
      );
      recordMetrics(result);
      return result;
    }
  }

  @override
  Future<void> sendAsync(TransportMessage message) async {
    // Fire and forget
    send(message);
  }

  /// Encode a transport message for Bluetooth Classic transmission
  Uint8List _encodeMessage(TransportMessage message) {
    // Create JSON envelope
    final envelope = <String, dynamic>{
      'id': message.id,
      'type': message.type.name,
      'callsign': message.targetCallsign,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Add message-specific fields
    if (message.method != null) envelope['method'] = message.method;
    if (message.path != null) envelope['path'] = message.path;
    if (message.headers != null) envelope['headers'] = message.headers;
    if (message.payload != null) envelope['payload'] = message.payload;
    if (message.signedEvent != null) envelope['signedEvent'] = message.signedEvent;

    final jsonStr = jsonEncode(envelope);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// Decode incoming data into a transport message
  TransportMessage? _decodeMessage(Uint8List data, String fromMac) {
    try {
      final jsonStr = utf8.decode(data);
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;

      final typeStr = envelope['type'] as String?;
      final type = TransportMessageType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => TransportMessageType.directMessage,
      );

      return TransportMessage(
        id: envelope['id'] as String? ?? 'btc-${DateTime.now().millisecondsSinceEpoch}',
        targetCallsign: envelope['callsign'] as String? ?? '',
        type: type,
        method: envelope['method'] as String?,
        path: envelope['path'] as String?,
        headers: (envelope['headers'] as Map<String, dynamic>?)?.cast<String, String>(),
        payload: envelope['payload'],
        signedEvent: envelope['signedEvent'] as Map<String, dynamic>?,
      );
    } catch (e) {
      LogService().log('BluetoothClassicTransport: Failed to decode message: $e');
      return null;
    }
  }

  /// Handle connection state changes
  void _handleConnectionStateChange(BluetoothClassicConnection connection) {
    LogService().log(
      'BluetoothClassicTransport: Connection ${connection.macAddress} '
      'state: ${connection.state.name}',
    );

    // If disconnected unexpectedly, clean up
    if (connection.state == BluetoothClassicConnectionState.disconnected) {
      // Find the callsign for this MAC
      final pairedDevices = _pairingService.getAllPairedDevices();
      final device = pairedDevices.where(
        (d) => d.classicMac == connection.macAddress,
      ).firstOrNull;

      if (device != null) {
        onDeviceReachabilityChanged(device.callsign, false);
      }
    }
  }

  /// Handle incoming data from Bluetooth Classic connections
  void _handleIncomingData(({String macAddress, Uint8List data}) incoming) {
    final message = _decodeMessage(incoming.data, incoming.macAddress);
    if (message == null) return;

    LogService().log(
      'BluetoothClassicTransport: Received ${message.type.name} from ${incoming.macAddress}',
    );

    emitIncomingMessage(message);

    // Find and register the device
    final pairedDevices = _pairingService.getAllPairedDevices();
    final device = pairedDevices.where(
      (d) => d.classicMac == incoming.macAddress,
    ).firstOrNull;

    if (device != null) {
      registerDevice(
        device.callsign,
        metadata: {
          'classicMac': incoming.macAddress,
          'source': 'bluetooth_classic',
        },
      );
    }
  }

  /// Check if a data size warrants using Bluetooth Classic over BLE
  bool shouldUseForSize(int dataSize) {
    return dataSize >= autoUpgradeThreshold;
  }

  /// Check if this transport should be preferred for a given message
  ///
  /// Returns true if:
  /// 1. Device is BLE+ paired AND
  /// 2. Either data size exceeds threshold OR there's an active transfer session
  Future<bool> shouldPrefer(String callsign, {int? dataSize}) async {
    if (!await canReach(callsign)) return false;

    // Check for active session
    if (TransferSession.shouldUseBLEPlus(callsign)) {
      return true;
    }

    // Check data size
    if (dataSize != null && shouldUseForSize(dataSize)) {
      return true;
    }

    // Check session expected bytes
    final sessionExpected = TransferSession.getExpectedBytes(callsign);
    if (sessionExpected != null && sessionExpected >= autoUpgradeThreshold) {
      return true;
    }

    return false;
  }

  /// Get all BLE+ paired devices
  List<String> getBLEPlusDevices() {
    return _pairingService.getAllPairedDevices().map((d) => d.callsign).toList();
  }

  /// Initiate BLE+ pairing for a device
  ///
  /// This should be called when a user wants to upgrade a BLE device to BLE+.
  /// The classicMac should be obtained from the BLE HELLO_ACK message.
  Future<bool> initiatePairing({
    required String callsign,
    required String classicMac,
    String? bleMac,
  }) async {
    return await _pairingService.initiatePairingFromBLE(
      callsign: callsign,
      classicMac: classicMac,
      bleMac: bleMac,
    );
  }

  /// Check if a device supports BLE+ (is paired)
  bool isBLEPlus(String callsign) {
    return _pairingService.isBLEPlus(callsign);
  }

  /// Remove BLE+ pairing for a device
  Future<void> removePairing(String callsign) async {
    await _pairingService.removePairing(callsign);
  }
}
