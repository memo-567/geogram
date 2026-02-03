/// Transport-agnostic message types and data structures
library;

/// Types of messages that can be sent through the connection manager
enum TransportMessageType {
  /// HTTP-style API request
  apiRequest,

  /// HTTP-style API response
  apiResponse,

  /// Direct message (1-to-1 chat)
  directMessage,

  /// Chat room message
  chatMessage,

  /// Synchronization request
  sync,

  /// Connection handshake
  hello,

  /// Heartbeat/keepalive
  ping,
}

/// Transport-agnostic message format
class TransportMessage {
  /// Unique message ID for tracking
  final String id;

  /// Target device callsign
  final String targetCallsign;

  /// Message type
  final TransportMessageType type;

  /// HTTP method for API requests (GET, POST, PUT, DELETE)
  final String? method;

  /// API path for API requests (e.g., "/api/status")
  final String? path;

  /// Headers for API requests
  final Map<String, String>? headers;

  /// Message payload (JSON-serializable)
  final dynamic payload;

  /// NOSTR-signed event (for authenticated messages)
  final Map<String, dynamic>? signedEvent;

  /// Whether to queue the message if device is offline (default: false)
  final bool queueIfOffline;

  /// Time-to-live for queued messages (null = no expiry)
  final Duration? ttl;

  /// Creation timestamp
  final DateTime createdAt;

  /// Priority (higher values = more urgent, default: 0)
  final int priority;

  /// Transport ID that this message arrived on (set by receiving transport)
  final String? sourceTransportId;

  TransportMessage({
    required this.id,
    required this.targetCallsign,
    required this.type,
    this.method,
    this.path,
    this.headers,
    this.payload,
    this.signedEvent,
    this.queueIfOffline = false,
    this.ttl,
    DateTime? createdAt,
    this.priority = 0,
    this.sourceTransportId,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create an API request message
  factory TransportMessage.apiRequest({
    required String targetCallsign,
    required String method,
    required String path,
    Map<String, String>? headers,
    dynamic body,
    bool queueIfOffline = false,
  }) {
    return TransportMessage(
      id: _generateId(),
      targetCallsign: targetCallsign,
      type: TransportMessageType.apiRequest,
      method: method,
      path: path,
      headers: headers,
      payload: body,
      queueIfOffline: queueIfOffline,
    );
  }

  /// Create a direct message
  factory TransportMessage.directMessage({
    required String targetCallsign,
    required Map<String, dynamic> signedEvent,
    bool queueIfOffline = false,
    Duration? ttl,
  }) {
    return TransportMessage(
      id: _generateId(),
      targetCallsign: targetCallsign,
      type: TransportMessageType.directMessage,
      signedEvent: signedEvent,
      queueIfOffline: queueIfOffline,
      ttl: ttl,
    );
  }

  /// Create a chat message
  factory TransportMessage.chatMessage({
    required String targetCallsign,
    required String roomId,
    required Map<String, dynamic> signedEvent,
    bool queueIfOffline = false,
  }) {
    return TransportMessage(
      id: _generateId(),
      targetCallsign: targetCallsign,
      type: TransportMessageType.chatMessage,
      path: roomId,
      signedEvent: signedEvent,
      queueIfOffline: queueIfOffline,
    );
  }

  static int _idCounter = 0;
  static String _generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}-$_idCounter';
  }

  /// Copy with modifications
  TransportMessage copyWith({
    String? id,
    String? targetCallsign,
    TransportMessageType? type,
    String? method,
    String? path,
    Map<String, String>? headers,
    dynamic payload,
    Map<String, dynamic>? signedEvent,
    bool? queueIfOffline,
    Duration? ttl,
    DateTime? createdAt,
    int? priority,
    String? sourceTransportId,
  }) {
    return TransportMessage(
      id: id ?? this.id,
      targetCallsign: targetCallsign ?? this.targetCallsign,
      type: type ?? this.type,
      method: method ?? this.method,
      path: path ?? this.path,
      headers: headers ?? this.headers,
      payload: payload ?? this.payload,
      signedEvent: signedEvent ?? this.signedEvent,
      queueIfOffline: queueIfOffline ?? this.queueIfOffline,
      ttl: ttl ?? this.ttl,
      createdAt: createdAt ?? this.createdAt,
      priority: priority ?? this.priority,
      sourceTransportId: sourceTransportId ?? this.sourceTransportId,
    );
  }

  /// Check if message has expired (based on TTL)
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(createdAt) > ttl!;
  }

  @override
  String toString() {
    return 'TransportMessage(id: $id, target: $targetCallsign, type: $type, '
        'method: $method, path: $path, queue: $queueIfOffline)';
  }
}

/// Result of a transport send operation
class TransportResult {
  /// Whether the send was successful
  final bool success;

  /// Error message if failed
  final String? error;

  /// HTTP status code (for API requests)
  final int? statusCode;

  /// Response data
  final dynamic responseData;

  /// Which transport delivered the message
  final String? transportUsed;

  /// How long the send took
  final Duration? latency;

  /// Whether the message was queued for later delivery
  final bool wasQueued;

  const TransportResult({
    required this.success,
    this.error,
    this.statusCode,
    this.responseData,
    this.transportUsed,
    this.latency,
    this.wasQueued = false,
  });

  /// Create a successful result
  factory TransportResult.success({
    int? statusCode,
    dynamic responseData,
    required String transportUsed,
    Duration? latency,
  }) {
    return TransportResult(
      success: true,
      statusCode: statusCode,
      responseData: responseData,
      transportUsed: transportUsed,
      latency: latency,
    );
  }

  /// Create a failure result
  factory TransportResult.failure({
    required String error,
    int? statusCode,
    String? transportUsed,
  }) {
    return TransportResult(
      success: false,
      error: error,
      statusCode: statusCode,
      transportUsed: transportUsed,
    );
  }

  /// Create a queued result (message will be delivered later)
  factory TransportResult.queued({
    required String transportUsed,
  }) {
    return TransportResult(
      success: true,
      wasQueued: true,
      transportUsed: transportUsed,
    );
  }

  @override
  String toString() {
    if (success) {
      if (wasQueued) {
        return 'TransportResult(queued via $transportUsed)';
      }
      return 'TransportResult(success via $transportUsed, '
          'status: $statusCode, latency: ${latency?.inMilliseconds}ms)';
    }
    return 'TransportResult(failed: $error)';
  }
}
