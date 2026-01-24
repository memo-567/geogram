import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Android USB Serial implementation using Android USB Host API
///
/// Uses the native UsbSerialPlugin.kt which implements CDC-ACM protocol
/// via the built-in Android USB Host API (android.hardware.usb.*).
/// No external libraries or system installations required.
class NativeSerialAndroid {
  static const _channel = MethodChannel('dev.geogram/usb_serial');
  static bool _initialized = false;

  /// Initialize the Android USB serial plugin
  static Future<void> initialize() async {
    if (_initialized) return;

    // Set up method call handler for callbacks from native
    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
  }

  /// Handle method calls from native side
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPermissionChanged':
        final deviceName = call.arguments['deviceName'] as String;
        final granted = call.arguments['granted'] as bool;
        _permissionController.add((deviceName, granted));
        break;
    }
    return null;
  }

  // Stream for permission changes
  static final _permissionController =
      StreamController<(String deviceName, bool granted)>.broadcast();

  /// Stream of permission change events
  static Stream<(String, bool)> get permissionChanges =>
      _permissionController.stream;

  /// List available USB serial devices
  ///
  /// Returns a list of device info maps containing:
  /// - deviceName: Unique device identifier (use this for open/close)
  /// - vendorId: USB VID
  /// - productId: USB PID
  /// - manufacturerName: Manufacturer string (nullable)
  /// - productName: Product string (nullable)
  /// - serialNumber: Serial number (nullable)
  /// - isEsp32: True if device matches known ESP32 identifiers
  /// - hasPermission: True if we have permission to access
  static Future<List<Map<String, dynamic>>> listDevices() async {
    await initialize();
    final result = await _channel.invokeMethod<List<dynamic>>('listDevices');
    return result?.cast<Map<dynamic, dynamic>>().map((m) {
          return Map<String, dynamic>.from(m);
        }).toList() ??
        [];
  }

  /// Check if we have permission for a device
  static Future<bool> hasPermission(String deviceName) async {
    await initialize();
    return await _channel
            .invokeMethod<bool>('hasPermission', {'deviceName': deviceName}) ??
        false;
  }

  /// Request permission for a USB device
  ///
  /// Shows the Android USB permission dialog if needed.
  /// Returns true if permission was granted.
  static Future<bool> requestPermission(String deviceName) async {
    await initialize();
    return await _channel.invokeMethod<bool>(
            'requestPermission', {'deviceName': deviceName}) ??
        false;
  }

  /// Open a USB serial device
  ///
  /// [deviceName] is the unique device identifier from listDevices()
  /// [baudRate] is the initial baud rate (default 115200)
  static Future<bool> open(String deviceName, {int baudRate = 115200}) async {
    await initialize();
    return await _channel.invokeMethod<bool>('open', {
          'deviceName': deviceName,
          'baudRate': baudRate,
        }) ??
        false;
  }

  /// Close a USB serial device
  static Future<void> close(String deviceName) async {
    await initialize();
    await _channel.invokeMethod('close', {'deviceName': deviceName});
  }

  /// Read data from device
  ///
  /// Returns empty list if timeout or no data available.
  static Future<Uint8List> read(String deviceName,
      {int maxBytes = 4096, int timeoutMs = 1000}) async {
    await initialize();
    final result = await _channel.invokeMethod<Uint8List>('read', {
      'deviceName': deviceName,
      'maxBytes': maxBytes,
      'timeoutMs': timeoutMs,
    });
    return result ?? Uint8List(0);
  }

  /// Write data to device
  ///
  /// Returns number of bytes written.
  static Future<int> write(String deviceName, Uint8List data) async {
    await initialize();
    return await _channel.invokeMethod<int>('write', {
          'deviceName': deviceName,
          'data': data,
        }) ??
        0;
  }

  /// Set DTR (Data Terminal Ready) signal
  static Future<bool> setDTR(String deviceName, bool value) async {
    await initialize();
    return await _channel.invokeMethod<bool>('setDTR', {
          'deviceName': deviceName,
          'value': value,
        }) ??
        false;
  }

  /// Set RTS (Request To Send) signal
  static Future<bool> setRTS(String deviceName, bool value) async {
    await initialize();
    return await _channel.invokeMethod<bool>('setRTS', {
          'deviceName': deviceName,
          'value': value,
        }) ??
        false;
  }

  /// Set baud rate
  static Future<bool> setBaudRate(String deviceName, int baudRate) async {
    await initialize();
    return await _channel.invokeMethod<bool>('setBaudRate', {
          'deviceName': deviceName,
          'baudRate': baudRate,
        }) ??
        false;
  }

  /// Flush buffers
  static Future<void> flush(String deviceName) async {
    await initialize();
    await _channel.invokeMethod('flush', {'deviceName': deviceName});
  }
}
