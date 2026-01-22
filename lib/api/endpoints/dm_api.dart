/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Direct Messages (DM) API endpoints.
 */

import '../api.dart';

/// DM conversation summary
class DmConversation {
  final String callsign;
  final String? name;
  final int messageCount;
  final int unreadCount;
  final DateTime? lastActivity;
  final String? lastMessage;

  const DmConversation({
    required this.callsign,
    this.name,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.lastActivity,
    this.lastMessage,
  });

  factory DmConversation.fromJson(Map<String, dynamic> json) {
    return DmConversation(
      callsign: json['callsign'] as String? ?? '',
      name: json['name'] as String?,
      messageCount: json['messageCount'] as int? ?? json['message_count'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? json['unread_count'] as int? ?? 0,
      lastActivity: _parseDateTime(json['lastActivity'] ?? json['last_activity']),
      lastMessage: json['lastMessage'] as String? ?? json['last_message'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// DM message
class DmMessage {
  final String id;
  final String? content;
  final String fromCallsign;
  final String toCallsign;
  final DateTime timestamp;
  final bool isRead;
  final String? attachmentType;
  final String? attachmentPath;

  const DmMessage({
    required this.id,
    this.content,
    required this.fromCallsign,
    required this.toCallsign,
    required this.timestamp,
    this.isRead = false,
    this.attachmentType,
    this.attachmentPath,
  });

  factory DmMessage.fromJson(Map<String, dynamic> json) {
    return DmMessage(
      id: json['id'] as String? ?? json['timestamp']?.toString() ?? '',
      content: json['content'] as String?,
      fromCallsign: json['fromCallsign'] as String? ?? json['from'] as String? ?? '',
      toCallsign: json['toCallsign'] as String? ?? json['to'] as String? ?? '',
      timestamp: _parseDateTime(json['timestamp']) ?? DateTime.now(),
      isRead: json['isRead'] as bool? ?? json['read'] as bool? ?? false,
      attachmentType: json['attachmentType'] as String? ?? json['attachment_type'] as String?,
      attachmentPath: json['attachmentPath'] as String? ?? json['attachment_path'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool get hasAttachment => attachmentType != null && attachmentPath != null;
}

/// DM sync result
class DmSyncResult {
  final List<DmMessage> messages;
  final int syncedCount;
  final DateTime? lastSync;

  const DmSyncResult({
    this.messages = const [],
    this.syncedCount = 0,
    this.lastSync,
  });

  factory DmSyncResult.fromJson(Map<String, dynamic> json) {
    return DmSyncResult(
      messages: (json['messages'] as List?)
              ?.map((e) => DmMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      syncedCount: json['syncedCount'] as int? ?? json['synced_count'] as int? ?? 0,
      lastSync: json['lastSync'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['lastSync'] as num).toInt() * 1000)
          : null,
    );
  }
}

/// Direct Messages API endpoints
class DmApi {
  final GeogramApi _api;

  DmApi(this._api);

  /// List DM conversations
  Future<ApiListResponse<DmConversation>> conversations(String callsign) {
    return _api.list<DmConversation>(
      callsign,
      '/api/dm/conversations',
      itemFromJson: (json) => DmConversation.fromJson(json as Map<String, dynamic>),
      listKey: 'conversations',
    );
  }

  /// Get messages with a specific device
  ///
  /// [otherCallsign] - The callsign of the other device
  /// [limit] - Maximum number of messages
  /// [since] - Get messages after this timestamp (Unix seconds)
  Future<ApiListResponse<DmMessage>> messages(
    String callsign,
    String otherCallsign, {
    int? limit,
    int? since,
  }) {
    return _api.list<DmMessage>(
      callsign,
      '/api/dm/$otherCallsign/messages',
      queryParams: {
        if (limit != null) 'limit': limit,
        if (since != null) 'since': since,
      },
      itemFromJson: (json) => DmMessage.fromJson(json as Map<String, dynamic>),
      listKey: 'messages',
    );
  }

  /// Send a message to a device
  ///
  /// This uses the ConnectionManager's sendDM method for proper
  /// transport selection and queuing.
  Future<ApiResponse<void>> sendMessage(
    String callsign,
    Map<String, dynamic> signedEvent, {
    bool queueIfOffline = true,
    Duration? ttl,
  }) {
    return _api.sendDirectMessage(
      callsign,
      signedEvent,
      queueIfOffline: queueIfOffline,
      ttl: ttl,
    );
  }

  /// Send a message via HTTP API (fallback)
  Future<ApiResponse<DmMessage>> postMessage(
    String callsign,
    String otherCallsign,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<DmMessage>(
      callsign,
      '/api/dm/$otherCallsign/messages',
      body: {'event': signedEvent},
      fromJson: (json) => DmMessage.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Sync messages with a device
  ///
  /// [since] - Get messages since this timestamp (Unix seconds)
  Future<ApiResponse<DmSyncResult>> sync(
    String callsign,
    String otherCallsign, {
    int? since,
  }) {
    return _api.get<DmSyncResult>(
      callsign,
      '/api/dm/sync/$otherCallsign',
      queryParams: since != null ? {'since': since} : null,
      fromJson: (json) => DmSyncResult.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Push messages to a device for sync
  Future<ApiResponse<DmSyncResult>> pushSync(
    String callsign,
    String otherCallsign,
    List<Map<String, dynamic>> messages,
  ) {
    return _api.post<DmSyncResult>(
      callsign,
      '/api/dm/sync/$otherCallsign',
      body: {'messages': messages},
      fromJson: (json) => DmSyncResult.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get a DM file (voice message, image, etc.)
  Future<ApiResponse<dynamic>> getFile(
    String callsign,
    String otherCallsign,
    String filename,
  ) {
    return _api.get<dynamic>(
      callsign,
      '/api/dm/$otherCallsign/files/$filename',
    );
  }

  /// Upload a file for DM
  Future<ApiResponse<Map<String, dynamic>>> uploadFile(
    String callsign,
    String otherCallsign,
    String filename,
    List<int> fileData, {
    String? contentType,
  }) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/dm/$otherCallsign/files/$filename',
      body: fileData,
      headers: {
        if (contentType != null) 'Content-Type': contentType,
      },
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Path Utilities
  // ============================================================

  /// DM conversations path: /api/dm/conversations
  static String conversationsPath() => '/api/dm/conversations';

  /// DM messages path: /api/dm/{callsign}/messages
  static String messagesPath(String otherCallsign) => '/api/dm/$otherCallsign/messages';

  /// DM file path: /api/dm/{callsign}/files/{filename}
  static String filePath(String otherCallsign, String filename) =>
      '/api/dm/$otherCallsign/files/$filename';

  /// DM sync path: /api/dm/sync/{callsign}
  static String syncPath(String otherCallsign) => '/api/dm/sync/$otherCallsign';

  /// Remote DM messages path: /{targetCallsign}/api/dm/{myCallsign}/messages
  static String remoteMessagesPath(String targetCallsign, String myCallsign) =>
      '/$targetCallsign/api/dm/$myCallsign/messages';

  /// Remote DM file path: /{targetCallsign}/api/dm/{myCallsign}/files/{filename}
  static String remoteFilePath(String targetCallsign, String myCallsign, String filename) =>
      '/$targetCallsign/api/dm/$myCallsign/files/$filename';

  /// Remote DM sync path: /{myCallsign}/api/dm/sync/{targetCallsign}
  static String remoteSyncPath(String myCallsign, String targetCallsign) =>
      '/$myCallsign/api/dm/sync/$targetCallsign';

  // ============================================================
  // Pattern Matchers
  // ============================================================

  /// Check if path matches DM messages pattern
  static bool isMessagesPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/[^/]+/messages$').hasMatch(path);
  }

  /// Check if path matches DM files pattern
  static bool isFilePath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/[^/]+/files/.+$').hasMatch(path);
  }

  /// Check if path matches DM sync pattern
  static bool isSyncPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/sync/[^/]+$').hasMatch(path);
  }

  /// Extract callsign from a DM path
  static String? extractCallsign(String path) {
    final match = RegExp(r'/api/dm/([^/]+)/(?:messages|files)').firstMatch(path);
    return match?.group(1);
  }
}
