/// BLE Transport - Bluetooth Low Energy communication
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../../services/log_service.dart';
import '../../services/app_args.dart';
import '../../services/ble_discovery_service.dart';
import '../../services/ble_message_service.dart';
import '../transport.dart';
import '../transport_message.dart';

/// BLE Transport for Bluetooth Low Energy communication
///
/// This transport has the lowest priority (40) as it:
/// - Is slow and has limited bandwidth
/// - Has limited range (~10-100 meters)
/// - Higher latency than LAN or internet
/// - Best used as offline fallback when no other transport is available
///
/// Platform Support:
/// - Android/iOS: Full support (GATT server + client)
/// - Linux/macOS/Windows: Client only
/// - Web: Not supported
class BleTransport extends Transport with TransportMixin {
  @override
  String get id => 'ble';

  @override
  String get name => 'Bluetooth';

  @override
  int get priority => 40; // Lowest priority - slow, use as last resort

  @override
  bool get isAvailable {
    // Not available on web or in internet-only mode
    if (kIsWeb) return false;
    if (AppArgs().internetOnly) return false;
    return true;
  }

  final BLEDiscoveryService _discoveryService = BLEDiscoveryService();
  final BLEMessageService _messageService = BLEMessageService();

  /// Timeout for BLE operations
  final Duration timeout;

  /// Stream subscription for incoming messages
  StreamSubscription<BLEChatMessage>? _incomingSubscription;

  BleTransport({
    this.timeout = const Duration(seconds: 30),
  });

  @override
  Future<void> initialize() async {
    if (!isAvailable) {
      LogService().log('BleTransport: Not available on this platform');
      return;
    }

    LogService().log('BleTransport: Initializing...');

    // Subscribe to incoming BLE messages
    _incomingSubscription = _messageService.incomingChats.listen(_handleIncomingMessage);

    markInitialized();
    LogService().log('BleTransport: Initialized (server=${BLEMessageService.canBeServer}, client=${BLEMessageService.canBeClient})');
  }

  @override
  Future<void> dispose() async {
    LogService().log('BleTransport: Disposing...');
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await disposeMixin();
    LogService().log('BleTransport: Disposed');
  }

  @override
  Future<bool> canReach(String callsign) async {
    if (!isInitialized) return false;

    // Check if device is in BLE discovery list
    final devices = _discoveryService.getAllDevices();
    return devices.any(
      (d) => d.callsign?.toUpperCase() == callsign.toUpperCase(),
    );
  }

  @override
  Future<int> getQuality(String callsign) async {
    if (!isInitialized) return 0;

    // Find device and use RSSI for quality estimation
    final devices = _discoveryService.getAllDevices();
    final device = devices.where(
      (d) => d.callsign?.toUpperCase() == callsign.toUpperCase(),
    ).firstOrNull;

    if (device == null) return 0;

    // Convert RSSI to quality (0-100)
    // RSSI typically ranges from -30 (excellent) to -100 (poor)
    // -30 dBm = 100 quality
    // -100 dBm = 0 quality
    final rssi = device.rssi;
    final quality = ((rssi + 100) / 70 * 100).clamp(0, 100).toInt();

    return quality;
  }

  @override
  Future<TransportResult> send(
    TransportMessage message, {
    Duration? timeout,
  }) async {
    if (!isInitialized) {
      return TransportResult.failure(
        error: 'BLE transport not initialized',
        transportUsed: id,
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Check if device is reachable via BLE
      final canReachDevice = await canReach(message.targetCallsign);
      if (!canReachDevice) {
        return TransportResult.failure(
          error: 'Device ${message.targetCallsign} not in BLE range',
          transportUsed: id,
        );
      }

      // Handle based on message type
      switch (message.type) {
        case TransportMessageType.apiRequest:
          return await _handleApiRequest(message, stopwatch);

        case TransportMessageType.directMessage:
          return await _handleDirectMessage(message, stopwatch);

        case TransportMessageType.chatMessage:
          return await _handleChatMessage(message, stopwatch);

        case TransportMessageType.hello:
        case TransportMessageType.ping:
          return await _handleHelloOrPing(message, stopwatch);

        default:
          return TransportResult.failure(
            error: 'Unsupported message type for BLE: ${message.type}',
            transportUsed: id,
          );
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

  /// Handle API request messages
  ///
  /// BLE doesn't natively support HTTP-style requests, so we encode
  /// the request as a JSON message and send via BLE chat channel.
  Future<TransportResult> _handleApiRequest(
    TransportMessage message,
    Stopwatch stopwatch,
  ) async {
    // Encode API request as JSON payload
    final requestPayload = jsonEncode({
      'type': 'api_request',
      'id': message.id,
      'method': message.method,
      'path': message.path,
      'headers': message.headers,
      'body': message.payload,
    });

    LogService().log('BleTransport: API request ${message.method} ${message.path} to ${message.targetCallsign}');

    // Send via BLE using a special channel for API requests
    final success = await _messageService.sendChatToCallsign(
      targetCallsign: message.targetCallsign,
      content: requestPayload,
      channel: '_api', // Special channel for API messages
    );

    stopwatch.stop();

    if (success) {
      // Note: BLE API requests are fire-and-forget by nature
      // The response would come back as a separate incoming message
      final result = TransportResult.success(
        transportUsed: id,
        latency: stopwatch.elapsed,
        // No response data for BLE API requests (async)
      );
      recordMetrics(result);
      return result;
    } else {
      final result = TransportResult.failure(
        error: 'BLE send failed',
        transportUsed: id,
      );
      recordMetrics(result);
      return result;
    }
  }

  /// Handle direct message
  Future<TransportResult> _handleDirectMessage(
    TransportMessage message,
    Stopwatch stopwatch,
  ) async {
    if (message.signedEvent == null) {
      return TransportResult.failure(
        error: 'No signed event for BLE DM',
        transportUsed: id,
      );
    }

    LogService().log('BleTransport: DM to ${message.targetCallsign}');

    // Send the signed event via BLE
    final success = await _messageService.sendChatToCallsign(
      targetCallsign: message.targetCallsign,
      content: jsonEncode(message.signedEvent),
      channel: '_dm', // Special channel for DMs
      signature: message.signedEvent!['sig'] as String?,
      npub: message.signedEvent!['pubkey'] as String?,
    );

    stopwatch.stop();

    if (success) {
      final result = TransportResult.success(
        transportUsed: id,
        latency: stopwatch.elapsed,
      );
      recordMetrics(result);
      return result;
    } else {
      final result = TransportResult.failure(
        error: 'BLE DM send failed',
        transportUsed: id,
      );
      recordMetrics(result);
      return result;
    }
  }

  /// Handle chat message
  Future<TransportResult> _handleChatMessage(
    TransportMessage message,
    Stopwatch stopwatch,
  ) async {
    final roomId = message.path ?? 'general';

    LogService().log('BleTransport: Chat to ${message.targetCallsign} room=$roomId');

    // Send chat via BLE
    final content = message.signedEvent != null
        ? jsonEncode(message.signedEvent)
        : jsonEncode(message.payload);

    final success = await _messageService.sendChatToCallsign(
      targetCallsign: message.targetCallsign,
      content: content,
      channel: roomId,
      signature: message.signedEvent?['sig'] as String?,
      npub: message.signedEvent?['pubkey'] as String?,
    );

    stopwatch.stop();

    if (success) {
      final result = TransportResult.success(
        transportUsed: id,
        latency: stopwatch.elapsed,
      );
      recordMetrics(result);
      return result;
    } else {
      final result = TransportResult.failure(
        error: 'BLE chat send failed',
        transportUsed: id,
      );
      recordMetrics(result);
      return result;
    }
  }

  /// Handle hello/ping messages
  Future<TransportResult> _handleHelloOrPing(
    TransportMessage message,
    Stopwatch stopwatch,
  ) async {
    final content = jsonEncode({
      'type': message.type == TransportMessageType.hello ? 'hello' : 'ping',
      'timestamp': DateTime.now().toIso8601String(),
    });

    final success = await _messageService.sendChatToCallsign(
      targetCallsign: message.targetCallsign,
      content: content,
      channel: '_system',
    );

    stopwatch.stop();

    if (success) {
      final result = TransportResult.success(
        transportUsed: id,
        latency: stopwatch.elapsed,
      );
      recordMetrics(result);
      return result;
    } else {
      final result = TransportResult.failure(
        error: 'BLE ${message.type} failed',
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

  /// Handle incoming BLE messages and convert to TransportMessages
  void _handleIncomingMessage(BLEChatMessage bleMessage) {
    try {
      // Determine message type from channel
      TransportMessageType type;
      switch (bleMessage.channel) {
        case '_dm':
          type = TransportMessageType.directMessage;
          break;
        case '_api':
          type = TransportMessageType.apiRequest;
          break;
        case '_system':
          type = TransportMessageType.ping;
          break;
        default:
          type = TransportMessageType.chatMessage;
      }

      // Try to parse content as JSON for signed events
      Map<String, dynamic>? signedEvent;
      dynamic payload = bleMessage.content;
      try {
        final parsed = jsonDecode(bleMessage.content);
        if (parsed is Map<String, dynamic>) {
          if (parsed.containsKey('sig') && parsed.containsKey('pubkey')) {
            signedEvent = parsed;
          } else {
            payload = parsed;
          }
        }
      } catch (_) {
        // Not JSON, use raw content
      }

      final message = TransportMessage(
        id: 'ble-${bleMessage.timestamp.millisecondsSinceEpoch}-${bleMessage.deviceId}',
        targetCallsign: bleMessage.author,
        type: type,
        path: bleMessage.channel,
        payload: payload,
        signedEvent: signedEvent,
      );

      emitIncomingMessage(message);

      // Also register the device
      registerDevice(
        bleMessage.author,
        metadata: {
          'deviceId': bleMessage.deviceId,
          'npub': bleMessage.npub,
          'source': 'ble',
        },
      );
    } catch (e) {
      LogService().log('BleTransport: Error handling incoming message: $e');
    }
  }

  /// Get all discovered BLE devices
  List<BLEDevice> get discoveredDevices => _discoveryService.getAllDevices();

  /// Get device by callsign
  BLEDevice? getDevice(String callsign) {
    final devices = _discoveryService.getAllDevices();
    return devices.where(
      (d) => d.callsign?.toUpperCase() == callsign.toUpperCase(),
    ).firstOrNull;
  }

  /// Check if BLE is scanning
  bool get isScanning => _discoveryService.isScanning;

  /// Start BLE scanning
  Future<void> startScanning() async {
    if (_discoveryService.isScanning) return;
    await _discoveryService.startScanning();
    LogService().log('BleTransport: Started scanning');
  }

  /// Stop BLE scanning
  Future<void> stopScanning() async {
    await _discoveryService.stopScanning();
    LogService().log('BleTransport: Stopped scanning');
  }

  /// Check if platform supports GATT server (Android/iOS)
  static bool get supportsGattServer {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if platform supports GATT client (all non-web)
  static bool get supportsGattClient {
    return !kIsWeb;
  }
}
