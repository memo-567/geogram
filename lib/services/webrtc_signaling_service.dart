/// WebRTC Signaling Service
///
/// Handles offer/answer/ICE candidate exchange via the station WebSocket.
/// Uses the existing WebSocketService for transport.
library;

import 'dart:async';
import 'dart:math';
import 'webrtc_config.dart';
import 'websocket_service.dart';
import 'profile_service.dart';
import 'log_service.dart';

/// Callback for received WebRTC signals
typedef WebRTCSignalCallback = void Function(WebRTCSignal signal);

/// WebRTC Signaling Service (Singleton)
///
/// Responsible for:
/// - Sending WebRTC offers, answers, and ICE candidates via WebSocket
/// - Receiving and dispatching incoming signals to the peer manager
/// - Managing session IDs for connection correlation
class WebRTCSignalingService {
  static final WebRTCSignalingService _instance =
      WebRTCSignalingService._internal();
  factory WebRTCSignalingService() => _instance;
  WebRTCSignalingService._internal();

  final WebSocketService _wsService = WebSocketService();
  final _random = Random();

  /// Stream controller for incoming WebRTC signals
  final _signalController = StreamController<WebRTCSignal>.broadcast();

  /// Pending offers waiting for answers (sessionId -> completer)
  final Map<String, Completer<WebRTCSignal>> _pendingOffers = {};

  /// Subscription to WebSocket messages
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  /// Whether the service is initialized
  bool _initialized = false;

  /// Stream of incoming WebRTC signals
  Stream<WebRTCSignal> get signals => _signalController.stream;

  /// Initialize the signaling service
  void initialize() {
    if (_initialized) return;

    LogService().log('WebRTCSignalingService: Initializing...');

    // Listen for WebRTC messages from WebSocket
    _wsSubscription = _wsService.messages.listen(_handleWebSocketMessage);

    _initialized = true;
    LogService().log('WebRTCSignalingService: Initialized');
  }

  /// Dispose resources
  void dispose() {
    _wsSubscription?.cancel();
    _signalController.close();

    // Cancel any pending offers
    for (final completer in _pendingOffers.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('Signaling service disposed while waiting for answer'));
      }
    }
    _pendingOffers.clear();

    _initialized = false;
    LogService().log('WebRTCSignalingService: Disposed');
  }

  /// Generate a new session ID for a WebRTC connection
  String generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '$timestamp-$randomPart';
  }

  /// Get our callsign from ProfileService
  String get _myCallsign {
    final profile = ProfileService().getProfile();
    return profile.callsign.isNotEmpty ? profile.callsign : 'UNKNOWN';
  }

  /// Send a WebRTC offer and wait for answer
  ///
  /// Returns the answer signal, or throws on timeout/error.
  Future<WebRTCSignal> sendOfferAndWaitForAnswer({
    required String toCallsign,
    required String sessionId,
    required Map<String, dynamic> sdp,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final offer = WebRTCSignal.offer(
      fromCallsign: _myCallsign,
      toCallsign: toCallsign,
      sessionId: sessionId,
      sdp: sdp,
    );

    // Create completer for the answer
    final completer = Completer<WebRTCSignal>();
    _pendingOffers[sessionId] = completer;

    try {
      // Send the offer
      await _sendSignal(offer);
      LogService().log(
          'WebRTCSignaling: Sent offer to $toCallsign (session: $sessionId)');

      // Wait for answer with timeout
      final answer = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingOffers.remove(sessionId);
          throw TimeoutException(
              'No answer received for offer to $toCallsign', timeout);
        },
      );

      return answer;
    } catch (e) {
      _pendingOffers.remove(sessionId);
      rethrow;
    }
  }

  /// Send a WebRTC answer (response to an offer)
  Future<void> sendAnswer({
    required String toCallsign,
    required String sessionId,
    required Map<String, dynamic> sdp,
  }) async {
    final answer = WebRTCSignal.answer(
      fromCallsign: _myCallsign,
      toCallsign: toCallsign,
      sessionId: sessionId,
      sdp: sdp,
    );

    await _sendSignal(answer);
    LogService()
        .log('WebRTCSignaling: Sent answer to $toCallsign (session: $sessionId)');
  }

  /// Send an ICE candidate
  Future<void> sendIceCandidate({
    required String toCallsign,
    required String sessionId,
    required Map<String, dynamic> candidate,
  }) async {
    final signal = WebRTCSignal.iceCandidate(
      fromCallsign: _myCallsign,
      toCallsign: toCallsign,
      sessionId: sessionId,
      candidate: candidate,
    );

    await _sendSignal(signal);
    LogService().log(
        'WebRTCSignaling: Sent ICE candidate to $toCallsign (session: $sessionId)');
  }

  /// Send a bye signal to close connection
  Future<void> sendBye({
    required String toCallsign,
    required String sessionId,
  }) async {
    final signal = WebRTCSignal.bye(
      fromCallsign: _myCallsign,
      toCallsign: toCallsign,
      sessionId: sessionId,
    );

    await _sendSignal(signal);
    LogService()
        .log('WebRTCSignaling: Sent bye to $toCallsign (session: $sessionId)');
  }

  /// Send a signal via WebSocket
  Future<void> _sendSignal(WebRTCSignal signal) async {
    if (!_wsService.isConnected) {
      LogService().log(
        'WebRTCSignaling: Dropping ${signal.type.name} to ${signal.toCallsign} (WebSocket not connected)',
      );
      return;
    }

    // Use WebSocketService to send the signaling message
    _wsService.sendWebRTCSignal(signal.toJson());
  }

  /// Handle incoming WebSocket messages
  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    if (type == null) return;

    // Check if it's a WebRTC signaling message
    if (!type.startsWith('webrtc_')) return;

    try {
      final signal = WebRTCSignal.fromJson(message);

      // Check if this is an answer to a pending offer
      if (signal.type == WebRTCSignalType.answer) {
        final completer = _pendingOffers.remove(signal.sessionId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(signal);
          LogService().log(
              'WebRTCSignaling: Received answer from ${signal.fromCallsign} (session: ${signal.sessionId})');
          return;
        }
      }

      // Emit to stream for peer manager to handle
      _signalController.add(signal);

      LogService().log(
          'WebRTCSignaling: Received ${signal.type.name} from ${signal.fromCallsign} (session: ${signal.sessionId})');
    } catch (e) {
      LogService().log('WebRTCSignaling: Error parsing signal: $e');
    }
  }

  /// Check if we're connected to the station (can send signals)
  bool get isConnected => _wsService.isConnected;
}
