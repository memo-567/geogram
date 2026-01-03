/*
 * Shared Chat API definitions
 * Used by both station server and client
 *
 * UNIFIED API PATH FORMAT:
 * - Chat: /api/chat/{roomId}/messages, /api/chat/{roomId}/files
 * - DM: /api/dm/{callsign}/messages, /api/dm/{callsign}/files/{filename}
 * - Remote (with callsign prefix): /{callsign}/api/chat/{roomId}/messages
 *
 * Note: For backwards compatibility, patterns also accept /api/chat/rooms/{roomId}/...
 */

/// Chat API path utilities - single source of truth for all chat/DM paths
class ChatApi {
  // ============================================================
  // UNIFIED PATH BUILDERS (without callsign prefix - for local/LAN use)
  // ============================================================

  /// Chat rooms list endpoint
  /// Returns: /api/chat/rooms
  static String chatRoomsPath() => '/api/chat/rooms';

  /// Chat messages endpoint for a room
  /// Returns: /api/chat/{roomId}/messages
  static String chatMessagesPath(String roomId) => '/api/chat/$roomId/messages';

  /// Chat files list endpoint for a room
  /// Returns: /api/chat/{roomId}/files
  static String chatFilesPath(String roomId) => '/api/chat/$roomId/files';

  /// Chat file download endpoint
  /// Returns: /api/chat/{roomId}/files/{filename}
  static String chatFileDownloadPath(String roomId, String filename) =>
      '/api/chat/$roomId/files/$filename';

  /// Chat message reactions endpoint
  /// Returns: /api/chat/{roomId}/messages/{timestamp}/reactions
  static String chatReactionsPath(String roomId, String timestamp) =>
      '/api/chat/$roomId/messages/$timestamp/reactions';

  // ============================================================
  // REMOTE PATH BUILDERS (with callsign prefix - for station proxy use)
  // ============================================================

  /// Remote chat rooms list endpoint
  /// Returns: /{callsign}/api/chat/rooms
  static String remoteChatRoomsPath(String callsign) => '/$callsign/api/chat/rooms';

  /// Remote chat messages endpoint
  /// Returns: /{callsign}/api/chat/{roomId}/messages
  static String remoteChatMessagesPath(String callsign, String roomId) =>
      '/$callsign/api/chat/$roomId/messages';

  /// Remote chat files list endpoint
  /// Returns: /{callsign}/api/chat/{roomId}/files
  static String remoteChatFilesPath(String callsign, String roomId) =>
      '/$callsign/api/chat/$roomId/files';

  /// Remote chat file download endpoint
  /// Returns: /{callsign}/api/chat/{roomId}/files/{filename}
  static String remoteChatFileDownloadPath(String callsign, String roomId, String filename) =>
      '/$callsign/api/chat/$roomId/files/$filename';

  // ============================================================
  // DM PATH BUILDERS
  // ============================================================

  /// DM conversations list endpoint
  /// Returns: /api/dm/conversations
  static String dmConversationsPath() => '/api/dm/conversations';

  /// DM messages endpoint for a conversation
  /// Returns: /api/dm/{callsign}/messages
  static String dmMessagesPath(String callsign) => '/api/dm/$callsign/messages';

  /// DM file endpoint
  /// Returns: /api/dm/{callsign}/files/{filename}
  static String dmFilePath(String callsign, String filename) =>
      '/api/dm/$callsign/files/$filename';

  /// DM sync endpoint
  /// Returns: /api/dm/sync/{callsign}
  static String dmSyncPath(String callsign) => '/api/dm/sync/$callsign';

  /// Remote DM messages endpoint (with callsign prefix)
  /// Returns: /{targetCallsign}/api/dm/{myCallsign}/messages
  static String remoteDmMessagesPath(String targetCallsign, String myCallsign) =>
      '/$targetCallsign/api/dm/$myCallsign/messages';

  /// Remote DM file endpoint (with callsign prefix)
  /// Returns: /{targetCallsign}/api/dm/{myCallsign}/files/{filename}
  static String remoteDmFilePath(String targetCallsign, String myCallsign, String filename) =>
      '/$targetCallsign/api/dm/$myCallsign/files/$filename';

  /// Remote DM sync endpoint (with callsign prefix)
  /// Returns: /{myCallsign}/api/dm/sync/{targetCallsign}
  static String remoteDmSyncPath(String myCallsign, String targetCallsign) =>
      '/$myCallsign/api/dm/sync/$targetCallsign';

  // ============================================================
  // URL BUILDERS (combine base URL with path)
  // ============================================================

  /// Build full URL for chat rooms endpoint
  static String chatRoomsUrl(String baseUrl) {
    final base = _normalizeBaseUrl(baseUrl);
    return '$base${chatRoomsPath()}';
  }

  /// Build full URL for chat messages endpoint
  static String chatMessagesUrl(String baseUrl, String roomId, {int? limit}) {
    final base = _normalizeBaseUrl(baseUrl);
    final path = '$base${chatMessagesPath(roomId)}';
    return limit != null ? '$path?limit=$limit' : path;
  }

  /// Build full URL for chat files endpoint
  static String chatFilesUrl(String baseUrl, String roomId) {
    final base = _normalizeBaseUrl(baseUrl);
    return '$base${chatFilesPath(roomId)}';
  }

  /// Build full URL for remote chat rooms endpoint
  static String remoteChatRoomsUrl(String baseUrl, String callsign) {
    final base = _normalizeBaseUrl(baseUrl);
    return '$base${remoteChatRoomsPath(callsign)}';
  }

  /// Build full URL for remote chat messages endpoint
  static String remoteChatMessagesUrl(String baseUrl, String callsign, String roomId, {int? limit}) {
    final base = _normalizeBaseUrl(baseUrl);
    final path = '$base${remoteChatMessagesPath(callsign, roomId)}';
    return limit != null ? '$path?limit=$limit' : path;
  }

  // ============================================================
  // PATTERN MATCHERS (accept both formats for backwards compatibility)
  // ============================================================

  /// Check if path matches chat rooms list pattern
  /// Matches: /api/chat/rooms, /{callsign}/api/chat/rooms
  static bool isChatRoomsPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/chat/rooms/?$').hasMatch(path);
  }

  /// Check if path matches chat messages pattern
  /// Matches: /api/chat/{roomId}/messages, /api/chat/rooms/{roomId}/messages,
  ///          /{callsign}/api/chat/{roomId}/messages, /{callsign}/api/chat/rooms/{roomId}/messages
  static bool isChatMessagesPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/chat/(rooms/)?[^/]+/messages$').hasMatch(path);
  }

  /// Check if path matches chat files list pattern
  /// Matches: /api/chat/{roomId}/files, /api/chat/rooms/{roomId}/files (with optional callsign prefix)
  static bool isChatFilesListPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/chat/(rooms/)?[^/]+/files$').hasMatch(path);
  }

  /// Check if path matches chat file download pattern
  /// Matches: /api/chat/{roomId}/files/{filename} (with optional callsign prefix and rooms/)
  static bool isChatFileDownloadPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/chat/(rooms/)?[^/]+/files/.+$').hasMatch(path);
  }

  /// Check if path matches chat reactions pattern
  /// Matches: /api/chat/{roomId}/messages/{timestamp}/reactions (with optional callsign prefix)
  static bool isChatReactionsPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/chat/(rooms/)?[^/]+/messages/.+/reactions$').hasMatch(path);
  }

  /// Check if path matches DM messages pattern
  /// Matches: /api/dm/{callsign}/messages, /{callsign}/api/dm/{callsign}/messages
  static bool isDmMessagesPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/[^/]+/messages$').hasMatch(path);
  }

  /// Check if path matches DM files pattern
  /// Matches: /api/dm/{callsign}/files/{filename}
  static bool isDmFilePath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/[^/]+/files/.+$').hasMatch(path);
  }

  /// Check if path matches DM sync pattern
  /// Matches: /api/dm/sync/{callsign}
  static bool isDmSyncPath(String path) {
    return RegExp(r'^(/[A-Z0-9]+)?/api/dm/sync/[^/]+$').hasMatch(path);
  }

  // ============================================================
  // EXTRACTORS (handle both formats)
  // ============================================================

  /// Extract callsign from a chat/DM API path with callsign prefix
  /// Returns null if path doesn't have callsign prefix
  static String? extractCallsign(String path) {
    final match = RegExp(r'^/([A-Z0-9]+)/api/').firstMatch(path);
    return match?.group(1);
  }

  /// Extract room ID from a chat messages or files path
  /// Handles both formats: /api/chat/{roomId}/... and /api/chat/rooms/{roomId}/...
  static String? extractRoomIdFromPath(String path) {
    // First try format without 'rooms/': /api/chat/{roomId}/messages or /api/chat/{roomId}/files
    var match = RegExp(r'/api/chat/([^/]+)/(?:messages|files)').firstMatch(path);
    if (match != null) {
      final roomId = match.group(1);
      // Make sure we didn't match 'rooms' itself
      if (roomId != 'rooms') {
        return roomId;
      }
    }
    // Fallback to format with 'rooms/': /api/chat/rooms/{roomId}/messages
    match = RegExp(r'/api/chat/rooms/([^/]+)/(?:messages|files)').firstMatch(path);
    return match?.group(1);
  }

  /// Extract callsign from a DM path
  /// Returns null if path doesn't match DM pattern
  static String? extractDmCallsign(String path) {
    final match = RegExp(r'/api/dm/([^/]+)/(?:messages|files)').firstMatch(path);
    return match?.group(1);
  }

  /// Extract filename from a file download path
  static String? extractFilename(String path) {
    final match = RegExp(r'/files/(.+)$').firstMatch(path);
    return match?.group(1);
  }

  /// Extract timestamp from a reactions path
  static String? extractTimestamp(String path) {
    final match = RegExp(r'/messages/([^/]+)/reactions$').firstMatch(path);
    return match?.group(1);
  }

  // ============================================================
  // LEGACY METHODS (kept for backwards compatibility)
  // ============================================================

  /// @deprecated Use remoteChatRoomsPath instead
  static String roomsPath(String callsign) => remoteChatRoomsPath(callsign);

  /// @deprecated Use remoteChatMessagesPath instead
  static String messagesPath(String callsign, String roomId) =>
      remoteChatMessagesPath(callsign, roomId);

  /// @deprecated Use remoteChatRoomsUrl instead
  static String roomsUrl(String baseUrl, String callsign) =>
      remoteChatRoomsUrl(baseUrl, callsign);

  /// @deprecated Use remoteChatMessagesUrl instead
  static String messagesUrl(String baseUrl, String callsign, String roomId, {int? limit}) =>
      remoteChatMessagesUrl(baseUrl, callsign, roomId, limit: limit);

  /// @deprecated Use isChatRoomsPath instead
  static bool isRoomsPath(String path) => isChatRoomsPath(path);

  /// @deprecated Use isChatMessagesPath instead
  static bool isMessagesPath(String path) => isChatMessagesPath(path);

  /// @deprecated Use extractRoomIdFromPath instead
  static String? extractRoomId(String path) => extractRoomIdFromPath(path);

  // ============================================================
  // PRIVATE HELPERS
  // ============================================================

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  }
}
