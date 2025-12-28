/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import '../models/update_notification.dart';
import '../services/dm_notification_service.dart';
import 'station_cache_service.dart';
import 'station_service.dart';
import 'log_service.dart';

/// Service for tracking unread chat message notifications
class ChatNotificationService {
  static final ChatNotificationService _instance = ChatNotificationService._internal();
  factory ChatNotificationService() => _instance;
  ChatNotificationService._internal();

  final StationService _stationService = StationService();
  final RelayCacheService _cacheService = RelayCacheService();

  // Unread counts per room (roomId -> count)
  final Map<String, int> _unreadCounts = {};

  // Currently viewed room (messages here are marked as read)
  String? _currentRoomId;

  // Stream controller for notifying UI of changes
  final _notificationController = StreamController<Map<String, int>>.broadcast();

  // Subscription to update notifications
  StreamSubscription<UpdateNotification>? _updateSubscription;

  /// Stream of unread counts (roomId -> count)
  Stream<Map<String, int>> get unreadCountsStream => _notificationController.stream;

  /// Get current unread counts
  Map<String, int> get unreadCounts => Map.unmodifiable(_unreadCounts);

  /// Get total unread count across all rooms
  int get totalUnreadCount => _unreadCounts.values.fold(0, (sum, count) => sum + count);

  /// Get unread count for a specific room
  int getUnreadCount(String roomId) => _unreadCounts[roomId] ?? 0;

  /// Initialize the service and start listening
  void initialize() {
    _setupUpdateListener();
    LogService().log('ChatNotificationService initialized');
  }

  /// Set up listener for UPDATE notifications
  void _setupUpdateListener() {
    _updateSubscription?.cancel();

    final updates = _stationService.updates;
    if (updates != null) {
      _updateSubscription = updates.listen(_handleUpdateNotification);
      LogService().log('ChatNotificationService: Listening for update notifications');
    }
  }

  /// Handle incoming UPDATE notification
  void _handleUpdateNotification(UpdateNotification update) {
    // Only handle chat updates
    if (update.collectionType != 'chat') {
      return;
    }

    final roomId = update.path;

    // If user is currently viewing this room, don't increment
    if (_currentRoomId == roomId) {
      LogService().log('ChatNotificationService: Update for current room $roomId (ignored)');
      return;
    }

    // Increment unread count for this room
    _unreadCounts[roomId] = (_unreadCounts[roomId] ?? 0) + 1;
    LogService().log('ChatNotificationService: New message in $roomId (unread: ${_unreadCounts[roomId]})');

    unawaited(_notifyChatUpdate(update));

    // Notify listeners
    _notificationController.add(Map.from(_unreadCounts));
  }

  Future<void> _notifyChatUpdate(UpdateNotification update) async {
    final roomId = update.path;
    if (roomId.isEmpty) return;

    final resolved = await _resolveChatMessage(update);
    if (resolved == null) {
      LogService().log('ChatNotificationService: Unable to resolve message for $roomId');
      return;
    }

    await DMNotificationService().showChatRoomMessage(
      roomId: roomId,
      fromCallsign: resolved.callsign,
      content: resolved.content,
      verified: resolved.verified,
    );
  }

  Future<({String callsign, String content, bool verified})?> _resolveChatMessage(
    UpdateNotification update,
  ) async {
    final roomId = update.path;
    if (roomId.isEmpty) return null;

    final station = _stationService.getPreferredStation();
    if (station != null && station.url.isNotEmpty) {
      try {
        final messages = await _stationService.fetchRoomMessages(
          station.url,
          roomId,
          limit: 1,
          stationCallsign: station.callsign,
        );
        if (messages.isNotEmpty) {
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final latest = messages.last;
          return (
            callsign: latest.callsign,
            content: latest.content,
            verified: latest.verified,
          );
        }
      } catch (e) {
        LogService().log('ChatNotificationService: Failed to fetch latest message: $e');
      }
    }

    try {
      await _cacheService.initialize();
      final candidateKeys = <String?>[
        update.callsign,
        station?.callsign,
        station?.name,
      ];
      for (final cacheKey in candidateKeys) {
        if (cacheKey == null || cacheKey.isEmpty) continue;
        final cached = await _cacheService.loadLatestMessage(cacheKey, roomId);
        if (cached != null) {
          return (
            callsign: cached.author,
            content: cached.content,
            verified: cached.isVerified,
          );
        }
      }
    } catch (e) {
      LogService().log('ChatNotificationService: Failed to load cached message: $e');
    }

    return null;
  }

  /// Set the currently viewed room (clears its unread count)
  void setCurrentRoom(String? roomId) {
    _currentRoomId = roomId;

    if (roomId != null && _unreadCounts.containsKey(roomId)) {
      _unreadCounts.remove(roomId);
      LogService().log('ChatNotificationService: Marked $roomId as read');
      _notificationController.add(Map.from(_unreadCounts));
    }
  }

  /// Mark a specific room as read
  void markAsRead(String roomId) {
    if (_unreadCounts.containsKey(roomId)) {
      _unreadCounts.remove(roomId);
      LogService().log('ChatNotificationService: Marked $roomId as read');
      _notificationController.add(Map.from(_unreadCounts));
    }
  }

  /// Mark all rooms as read
  void markAllAsRead() {
    if (_unreadCounts.isNotEmpty) {
      _unreadCounts.clear();
      LogService().log('ChatNotificationService: Marked all rooms as read');
      _notificationController.add(Map.from(_unreadCounts));
    }
  }

  /// Re-connect to station updates (call after station reconnection)
  void reconnect() {
    _setupUpdateListener();
  }

  /// Dispose resources
  void dispose() {
    _updateSubscription?.cancel();
    _notificationController.close();
  }
}
