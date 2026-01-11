import 'dart:io';

import 'package:flutter/services.dart';

/// Service for managing Wi-Fi Direct hotspot functionality (Android only)
/// Uses Wi-Fi P2P Group Owner mode to create a hotspot without a router
class WifiDirectService {
  static const _channel = MethodChannel('dev.geogram/wifi_direct');

  bool _enabled = false;
  String? _ssid;
  String? _passphrase;
  int _clientCount = 0;

  bool get isEnabled => _enabled;
  String? get ssid => _ssid;
  String? get passphrase => _passphrase;
  int get clientCount => _clientCount;

  /// Check if Wi-Fi Direct is supported on this device
  static bool get isSupported => Platform.isAndroid;

  WifiDirectService() {
    if (isSupported) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStateChanged':
        final enabled = call.arguments['enabled'] as bool;
        _enabled = enabled;
        break;
    }
  }

  /// Enable Wi-Fi Direct hotspot (Group Owner mode)
  /// [stationName] is used to create a custom SSID like "DIRECT-XX-stationName"
  /// Returns hotspot info on success, null on failure
  Future<Map<String, dynamic>?> enableHotspot(String stationName) async {
    if (!isSupported) return null;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'enableHotspot',
        {'stationName': stationName},
      );
      if (result != null) {
        _enabled = true;
        _ssid = result['ssid'] as String?;
        _passphrase = result['passphrase'] as String?;
        _clientCount = (result['clientCount'] as int?) ?? 0;
        return {
          'ssid': _ssid,
          'passphrase': _passphrase,
          'clientCount': _clientCount,
        };
      }
    } on PlatformException catch (e) {
      print('WifiDirectService: Failed to enable hotspot: ${e.message}');
    }
    return null;
  }

  /// Disable Wi-Fi Direct hotspot
  Future<bool> disableHotspot() async {
    if (!isSupported) return true;

    try {
      final result = await _channel.invokeMethod<bool>('disableHotspot');
      if (result == true) {
        _enabled = false;
        _ssid = null;
        _passphrase = null;
        _clientCount = 0;
      }
      return result ?? false;
    } on PlatformException catch (e) {
      print('WifiDirectService: Failed to disable hotspot: ${e.message}');
      return false;
    }
  }

  /// Check if hotspot is currently enabled
  Future<bool> isHotspotEnabled() async {
    if (!isSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isHotspotEnabled');
      _enabled = result ?? false;
      return _enabled;
    } on PlatformException {
      return false;
    }
  }

  /// Get current hotspot info
  Future<Map<String, dynamic>?> getHotspotInfo() async {
    if (!isSupported) return null;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getHotspotInfo');
      if (result != null) {
        _ssid = result['ssid'] as String?;
        _passphrase = result['passphrase'] as String?;
        _clientCount = (result['clientCount'] as int?) ?? 0;
        return {
          'ssid': _ssid,
          'passphrase': _passphrase,
          'clientCount': _clientCount,
        };
      }
    } on PlatformException {
      // Ignore
    }
    return null;
  }
}
