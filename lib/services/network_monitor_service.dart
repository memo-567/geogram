/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Network Monitor Service - Monitors LAN and Internet connectivity
 * Fires ConnectionStateChangedEvent when network states change
 */

import 'dart:async';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'log_service.dart';
import '../util/event_bus.dart';

/// Service that monitors network connectivity and fires events on changes
class NetworkMonitorService {
  static final NetworkMonitorService _instance = NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final EventBus _eventBus = EventBus();

  /// Check interval for network state
  static const Duration _checkInterval = Duration(seconds: 10);

  /// Timeout for internet connectivity check
  static const Duration _internetCheckTimeout = Duration(seconds: 5);

  /// Timer for periodic checks
  Timer? _checkTimer;

  /// Last known states (to avoid duplicate events)
  bool _lastLanAvailable = false;
  bool _lastInternetAvailable = false;

  /// Whether the service has been initialized
  bool _initialized = false;

  /// Current network state getters
  bool get hasLan => _lastLanAvailable;
  bool get hasInternet => _lastInternetAvailable;

  /// Initialize the service and start monitoring
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      // On web, assume internet is available and LAN is not detectable
      _lastInternetAvailable = true;
      _lastLanAvailable = false;
      _fireInternetStateChanged(true);
      return;
    }

    LogService().log('NetworkMonitor: Initializing network monitoring');

    // Check initial state
    await _checkNetworkState();

    // Start periodic checks
    _checkTimer = Timer.periodic(_checkInterval, (_) => _checkNetworkState());
  }

  /// Stop monitoring and clean up
  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _initialized = false;
  }

  /// Force a network state check (can be called after network changes)
  Future<void> checkNow() async {
    await _checkNetworkState();
  }

  /// Check current network state and fire events if changed
  Future<void> _checkNetworkState() async {
    if (kIsWeb) return;

    try {
      // Check LAN availability (do we have a local network interface?)
      final hasLan = await _checkLanAvailable();
      if (hasLan != _lastLanAvailable) {
        _fireLanStateChanged(hasLan);
      }

      // Check Internet availability (can we reach external hosts?)
      final hasInternet = await _checkInternetAvailable();
      if (hasInternet != _lastInternetAvailable) {
        _fireInternetStateChanged(hasInternet);
      }
    } catch (e) {
      LogService().log('NetworkMonitor: Error checking network state: $e');
    }
  }

  /// Check if we have a local network interface with a private IP
  Future<bool> _checkLanAvailable() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          // Check for private network addresses
          if (_isPrivateIp(ip)) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      LogService().log('NetworkMonitor: Error checking LAN: $e');
      return false;
    }
  }

  /// Check if IP is a private network address
  bool _isPrivateIp(String ip) {
    // 10.0.0.0 - 10.255.255.255
    if (ip.startsWith('10.')) return true;
    // 172.16.0.0 - 172.31.255.255
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    // 192.168.0.0 - 192.168.255.255
    if (ip.startsWith('192.168.')) return true;
    return false;
  }

  /// Check if internet is reachable
  Future<bool> _checkInternetAvailable() async {
    // Try multiple endpoints for reliability
    final endpoints = [
      'https://www.google.com',
      'https://www.cloudflare.com',
      'https://www.apple.com',
    ];

    for (final url in endpoints) {
      try {
        final response = await http.head(Uri.parse(url))
            .timeout(_internetCheckTimeout);
        if (response.statusCode >= 200 && response.statusCode < 400) {
          return true;
        }
      } catch (e) {
        // Try next endpoint
        continue;
      }
    }
    return false;
  }

  /// Fire LAN state changed event
  void _fireLanStateChanged(bool isAvailable) {
    _lastLanAvailable = isAvailable;
    LogService().log('ConnectionStateChanged: lan ${isAvailable ? "available" : "unavailable"}');

    _eventBus.fire(ConnectionStateChangedEvent(
      connectionType: ConnectionType.lan,
      isConnected: isAvailable,
    ));
  }

  /// Fire Internet state changed event
  void _fireInternetStateChanged(bool isAvailable) {
    _lastInternetAvailable = isAvailable;
    LogService().log('ConnectionStateChanged: internet ${isAvailable ? "available" : "unavailable"}');

    _eventBus.fire(ConnectionStateChangedEvent(
      connectionType: ConnectionType.internet,
      isConnected: isAvailable,
    ));
  }
}
