/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Callback type for when the foreground service triggers a keep-alive ping.
/// This allows the WebSocketService to receive periodic ping triggers from the
/// Android foreground service, which runs even when the display is off.
typedef KeepAlivePingCallback = void Function();

/// Callback type for when the foreground service restarts after Android 15+ timeout.
/// This allows the WebSocketService to check and reconnect if needed.
typedef ServiceRestartedCallback = void Function();

/// Callback type for when the foreground service triggers a BLE advertising ping.
/// This allows the BLEIdentityService to receive periodic ping triggers from the
/// Android foreground service, which runs even when the display is off.
typedef BleAdvertisePingCallback = void Function();

/// Callback type for when the foreground service triggers a BLE scan ping.
/// This allows the ProximityDetectionService to receive periodic ping triggers from the
/// Android foreground service, which runs even when the display is off.
typedef BleScanPingCallback = void Function();

/// Service to manage the foreground service on Android.
/// This keeps BLE and WebSocket connections active when app goes to background.
///
/// On Android, when the display is off, the Flutter engine can be throttled,
/// causing timers to not fire reliably. This service uses a native Android
/// Handler that continues to run in the foreground service, triggering callbacks
/// to Dart to send WebSocket keep-alive pings.
class BLEForegroundService {
  static final BLEForegroundService _instance = BLEForegroundService._internal();
  factory BLEForegroundService() => _instance;
  BLEForegroundService._internal() {
    // Set up method call handler for callbacks from Android
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channel = MethodChannel('dev.geogram/ble_service');
  bool _isRunning = false;
  bool _keepAliveEnabled = false;
  bool _bleKeepAliveEnabled = false;
  bool _bleScanKeepAliveEnabled = false;

  /// Callback to invoke when the foreground service triggers a keep-alive ping
  KeepAlivePingCallback? onKeepAlivePing;

  /// Callback to invoke when the foreground service restarts after Android 15+ timeout
  ServiceRestartedCallback? onServiceRestarted;

  /// Callback to invoke when the foreground service triggers a BLE advertising ping
  BleAdvertisePingCallback? onBleAdvertisePing;

  /// Callback to invoke when the foreground service triggers a BLE scan ping
  BleScanPingCallback? onBleScanPing;

  /// Whether the foreground service is currently running
  bool get isRunning => _isRunning;

  /// Whether WebSocket keep-alive is enabled in the foreground service
  bool get keepAliveEnabled => _keepAliveEnabled;

  /// Whether BLE advertising keep-alive is enabled in the foreground service
  bool get bleKeepAliveEnabled => _bleKeepAliveEnabled;

  /// Whether BLE scan keep-alive is enabled in the foreground service
  bool get bleScanKeepAliveEnabled => _bleScanKeepAliveEnabled;

  /// Handle method calls from Android native code
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onKeepAlivePing':
        LogService().log('BLEForegroundService: Keep-alive ping received from Android');
        onKeepAlivePing?.call();
        break;
      case 'onServiceRestarted':
        LogService().log('BLEForegroundService: Service restarted after dataSync timeout');
        onServiceRestarted?.call();
        break;
      case 'onBleAdvertisePing':
        LogService().log('BLEForegroundService: BLE advertising ping received from Android');
        onBleAdvertisePing?.call();
        break;
      case 'onBleScanPing':
        LogService().log('BLEForegroundService: BLE scan ping received from Android');
        onBleScanPing?.call();
        break;
      default:
        LogService().log('BLEForegroundService: Unknown method ${call.method}');
    }
  }

  /// Start the foreground service (Android only)
  /// This shows a persistent notification and keeps connections active in background
  Future<bool> start() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false; // Only needed on Android
    }

    if (_isRunning) {
      LogService().log('BLEForegroundService: Already running');
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('startBLEService');
      _isRunning = result ?? false;
      if (_isRunning) {
        LogService().log('BLEForegroundService: Started successfully');
      } else {
        LogService().log('BLEForegroundService: Failed to start');
      }
      return _isRunning;
    } catch (e) {
      LogService().log('BLEForegroundService: Error starting: $e');
      return false;
    }
  }

  /// Stop the foreground service
  Future<bool> stop() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    if (!_isRunning) {
      return true;
    }

    try {
      // Disable keep-alive first
      await disableKeepAlive();

      final result = await _channel.invokeMethod<bool>('stopBLEService');
      _isRunning = !(result ?? true);
      LogService().log('BLEForegroundService: Stopped');
      return !_isRunning;
    } catch (e) {
      LogService().log('BLEForegroundService: Error stopping: $e');
      return false;
    }
  }

  /// Enable WebSocket keep-alive in the foreground service.
  /// This should be called after WebSocket connects to the station.
  /// The foreground service will periodically trigger [onKeepAlivePing] even
  /// when the display is off, allowing the WebSocket connection to stay alive.
  ///
  /// [callsign] - The user's callsign (e.g., "X1ABCD")
  /// [stationName] - Optional friendly name for the station (e.g., "P2P Radio")
  /// [stationUrl] - The station URL/hostname (e.g., "p2p.radio")
  Future<bool> enableKeepAlive({String? callsign, String? stationName, String? stationUrl}) async {
    if (kIsWeb || !Platform.isAndroid) {
      return false; // Only needed on Android
    }

    if (_keepAliveEnabled) {
      LogService().log('BLEForegroundService: Keep-alive already enabled');
      return true;
    }

    // Start the service if not running
    if (!_isRunning) {
      await start();
    }

    try {
      final result = await _channel.invokeMethod<bool>('enableKeepAlive', {
        'callsign': callsign,
        'stationName': stationName,
        'stationUrl': stationUrl,
      });
      _keepAliveEnabled = result ?? false;
      if (_keepAliveEnabled) {
        LogService().log('BLEForegroundService: WebSocket keep-alive enabled for ${stationName ?? stationUrl ?? "station"}');
      } else {
        LogService().log('BLEForegroundService: Failed to enable keep-alive');
      }
      return _keepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error enabling keep-alive: $e');
      return false;
    }
  }

  /// Disable WebSocket keep-alive in the foreground service.
  /// This should be called when WebSocket disconnects from the station.
  Future<bool> disableKeepAlive() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    if (!_keepAliveEnabled) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('disableKeepAlive');
      _keepAliveEnabled = !(result ?? true);
      LogService().log('BLEForegroundService: WebSocket keep-alive disabled');
      return !_keepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error disabling keep-alive: $e');
      return false;
    }
  }

  /// Enable BLE advertising keep-alive in the foreground service.
  /// This should be called after BLE advertising is started.
  /// The foreground service will periodically trigger [onBleAdvertisePing] even
  /// when the display is off, allowing BLE advertising to stay active.
  Future<bool> enableBleKeepAlive() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false; // Only needed on Android
    }

    if (_bleKeepAliveEnabled) {
      LogService().log('BLEForegroundService: BLE keep-alive already enabled');
      return true;
    }

    // Start the service if not running
    if (!_isRunning) {
      await start();
    }

    try {
      final result = await _channel.invokeMethod<bool>('enableBleKeepAlive');
      _bleKeepAliveEnabled = result ?? false;
      if (_bleKeepAliveEnabled) {
        LogService().log('BLEForegroundService: BLE advertising keep-alive enabled');
      } else {
        LogService().log('BLEForegroundService: Failed to enable BLE keep-alive');
      }
      return _bleKeepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error enabling BLE keep-alive: $e');
      return false;
    }
  }

  /// Disable BLE advertising keep-alive in the foreground service.
  /// This should be called when BLE advertising is stopped.
  Future<bool> disableBleKeepAlive() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    if (!_bleKeepAliveEnabled) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('disableBleKeepAlive');
      _bleKeepAliveEnabled = !(result ?? true);
      LogService().log('BLEForegroundService: BLE advertising keep-alive disabled');
      return !_bleKeepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error disabling BLE keep-alive: $e');
      return false;
    }
  }

  /// Enable BLE scan keep-alive in the foreground service.
  /// This should be called after proximity detection is started.
  /// The foreground service will periodically trigger [onBleScanPing] even
  /// when the display is off, allowing proximity detection to stay active.
  Future<bool> enableBleScanKeepAlive() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false; // Only needed on Android
    }

    if (_bleScanKeepAliveEnabled) {
      LogService().log('BLEForegroundService: BLE scan keep-alive already enabled');
      return true;
    }

    // Start the service if not running
    if (!_isRunning) {
      await start();
    }

    try {
      final result = await _channel.invokeMethod<bool>('enableBleScanKeepAlive');
      _bleScanKeepAliveEnabled = result ?? false;
      if (_bleScanKeepAliveEnabled) {
        LogService().log('BLEForegroundService: BLE scan keep-alive enabled');
      } else {
        LogService().log('BLEForegroundService: Failed to enable BLE scan keep-alive');
      }
      return _bleScanKeepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error enabling BLE scan keep-alive: $e');
      return false;
    }
  }

  /// Disable BLE scan keep-alive in the foreground service.
  /// This should be called when proximity detection is stopped.
  Future<bool> disableBleScanKeepAlive() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    if (!_bleScanKeepAliveEnabled) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('disableBleScanKeepAlive');
      _bleScanKeepAliveEnabled = !(result ?? true);
      LogService().log('BLEForegroundService: BLE scan keep-alive disabled');
      return !_bleScanKeepAliveEnabled;
    } catch (e) {
      LogService().log('BLEForegroundService: Error disabling BLE scan keep-alive: $e');
      return false;
    }
  }

  /// Verify that the native channel is ready and responsive.
  /// This can be used after app resume to ensure the Flutter-Native communication
  /// is working correctly after the app was backgrounded.
  Future<bool> verifyChannelReady() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('verifyChannel');
      return result ?? false;
    } catch (e) {
      LogService().log('BLEForegroundService: Channel verification failed: $e');
      return false;
    }
  }
}
