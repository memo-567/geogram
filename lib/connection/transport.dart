/// Abstract transport interface for device-to-device communication
library;

import 'dart:async';
import 'transport_message.dart';

/// Metrics for a transport's performance
class TransportMetrics {
  /// Average latency in milliseconds
  final double averageLatencyMs;

  /// Success rate (0.0 to 1.0)
  final double successRate;

  /// Total messages sent
  final int totalMessagesSent;

  /// Total messages failed
  final int totalMessagesFailed;

  /// Last successful send timestamp
  final DateTime? lastSuccessTime;

  /// Last failure timestamp
  final DateTime? lastFailureTime;

  const TransportMetrics({
    this.averageLatencyMs = 0,
    this.successRate = 1.0,
    this.totalMessagesSent = 0,
    this.totalMessagesFailed = 0,
    this.lastSuccessTime,
    this.lastFailureTime,
  });

  /// Create empty metrics
  factory TransportMetrics.empty() => const TransportMetrics();

  /// Update metrics with a new result
  TransportMetrics recordResult(TransportResult result) {
    final newTotal = totalMessagesSent + 1;
    final newFailed = result.success ? totalMessagesFailed : totalMessagesFailed + 1;
    final newSuccessRate = (newTotal - newFailed) / newTotal;

    double newAvgLatency = averageLatencyMs;
    if (result.success && result.latency != null) {
      // Rolling average
      newAvgLatency = (averageLatencyMs * totalMessagesSent +
          result.latency!.inMilliseconds) / newTotal;
    }

    return TransportMetrics(
      averageLatencyMs: newAvgLatency,
      successRate: newSuccessRate,
      totalMessagesSent: newTotal,
      totalMessagesFailed: newFailed,
      lastSuccessTime: result.success ? DateTime.now() : lastSuccessTime,
      lastFailureTime: result.success ? lastFailureTime : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'TransportMetrics(avgLatency: ${averageLatencyMs.toStringAsFixed(1)}ms, '
        'success: ${(successRate * 100).toStringAsFixed(1)}%, '
        'total: $totalMessagesSent)';
  }
}

/// Abstract transport provider interface
///
/// Transports are responsible for delivering messages to devices via
/// a specific communication channel (LAN, BLE, Station relay, etc.)
abstract class Transport {
  /// Unique transport identifier (e.g., 'lan', 'ble', 'station')
  String get id;

  /// Human-readable name (e.g., 'Local Network', 'Bluetooth')
  String get name;

  /// Priority for routing (lower values = preferred)
  ///
  /// Suggested values:
  /// - LAN: 10 (fastest, most reliable)
  /// - BLE: 20 (works offline, short range)
  /// - Station: 30 (longest range, requires internet)
  int get priority;

  /// Whether this transport is available on the current platform
  bool get isAvailable;

  /// Whether this transport is currently initialized and ready
  bool get isInitialized;

  /// Check if this transport can reach a specific device
  ///
  /// Returns true if the device is known to be reachable via this transport.
  /// This should be a quick check (cached data preferred).
  Future<bool> canReach(String callsign);

  /// Get estimated quality score for reaching a device (0-100)
  ///
  /// Higher values indicate better quality. Factors may include:
  /// - RSSI for BLE
  /// - Latency history
  /// - Success rate
  Future<int> getQuality(String callsign);

  /// Send a message and wait for response
  ///
  /// Returns a [TransportResult] indicating success/failure and response data.
  Future<TransportResult> send(
    TransportMessage message, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Send a message without waiting for response (fire-and-forget)
  ///
  /// Useful for notifications or messages that don't need acknowledgment.
  Future<void> sendAsync(TransportMessage message);

  /// Stream of incoming messages from this transport
  Stream<TransportMessage> get incomingMessages;

  /// Initialize the transport
  ///
  /// Called once when the transport is registered with ConnectionManager.
  Future<void> initialize();

  /// Dispose resources
  ///
  /// Called when the transport is being shut down.
  Future<void> dispose();

  /// Get current metrics for this transport
  TransportMetrics get metrics;

  /// Update the device registry with a known device URL/address
  ///
  /// Transports can call this to register devices they discover.
  void registerDevice(String callsign, {String? url, Map<String, dynamic>? metadata});

  /// Called when a device's reachability changes
  ///
  /// Override to handle device online/offline events.
  void onDeviceReachabilityChanged(String callsign, bool isReachable) {}
}

/// Mixin providing common transport functionality
mixin TransportMixin on Transport {
  final _incomingController = StreamController<TransportMessage>.broadcast();
  TransportMetrics _metrics = TransportMetrics.empty();
  bool _initialized = false;

  @override
  Stream<TransportMessage> get incomingMessages => _incomingController.stream;

  @override
  TransportMetrics get metrics => _metrics;

  @override
  bool get isInitialized => _initialized;

  /// Record a send result in metrics
  void recordMetrics(TransportResult result) {
    _metrics = _metrics.recordResult(result);
  }

  /// Emit an incoming message
  void emitIncomingMessage(TransportMessage message) {
    if (!_incomingController.isClosed) {
      _incomingController.add(message);
    }
  }

  /// Mark as initialized
  void markInitialized() {
    _initialized = true;
  }

  /// Dispose the mixin resources
  Future<void> disposeMixin() async {
    await _incomingController.close();
    _initialized = false;
  }

  // Device registry (transport-local)
  final Map<String, DeviceInfo> _deviceRegistry = {};

  @override
  void registerDevice(String callsign, {String? url, Map<String, dynamic>? metadata}) {
    _deviceRegistry[callsign.toUpperCase()] = DeviceInfo(
      callsign: callsign.toUpperCase(),
      url: url,
      metadata: metadata ?? {},
      lastSeen: DateTime.now(),
    );
  }

  /// Get device info from local registry
  DeviceInfo? getDeviceInfo(String callsign) {
    return _deviceRegistry[callsign.toUpperCase()];
  }

  /// Get all known devices for this transport
  List<DeviceInfo> get knownDevices => _deviceRegistry.values.toList();
}

/// Information about a device known to a transport
class DeviceInfo {
  final String callsign;
  final String? url;
  final Map<String, dynamic> metadata;
  final DateTime lastSeen;

  const DeviceInfo({
    required this.callsign,
    this.url,
    required this.metadata,
    required this.lastSeen,
  });

  @override
  String toString() => 'DeviceInfo($callsign, url: $url)';
}
