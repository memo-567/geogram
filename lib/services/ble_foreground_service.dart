/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service to manage BLE foreground service on Android.
/// This keeps BLE connections active when app goes to background.
class BLEForegroundService {
  static final BLEForegroundService _instance = BLEForegroundService._internal();
  factory BLEForegroundService() => _instance;
  BLEForegroundService._internal();

  static const _channel = MethodChannel('dev.geogram/ble_service');
  bool _isRunning = false;

  /// Whether the foreground service is currently running
  bool get isRunning => _isRunning;

  /// Start the BLE foreground service (Android only)
  /// This shows a persistent notification and keeps BLE active in background
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

  /// Stop the BLE foreground service
  Future<bool> stop() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    if (!_isRunning) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('stopBLEService');
      _isRunning = !(result ?? true);
      LogService().log('BLEForegroundService: Stopped');
      return !_isRunning;
    } catch (e) {
      LogService().log('BLEForegroundService: Error stopping: $e');
      return false;
    }
  }
}
