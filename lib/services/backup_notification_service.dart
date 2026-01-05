/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/event_bus.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';

/// Local notifications for backup events (invites, completion, failures)
class BackupNotificationService {
  static final BackupNotificationService _instance = BackupNotificationService._internal();
  factory BackupNotificationService() => _instance;
  BackupNotificationService._internal();

  static const String _channelId = 'geogram_backup';
  static const String _channelName = 'Backup Activity';

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  EventSubscription<BackupEvent>? _backupEventSubscription;
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Initialize notification handling for backup events
  Future<void> initialize({bool skipPermissionRequest = false}) async {
    if (_initialized) return;
    if (!_isMobilePlatform()) {
      _initialized = true;
      LogService().log('BackupNotificationService: Skipping init on non-mobile platform');
      return;
    }

    try {
      await _initializeNotifications(skipPermissionRequest: skipPermissionRequest);
      _subscribeToEvents();
      _initialized = true;
      LogService().log('BackupNotificationService initialized');
    } catch (e) {
      LogService().log('BackupNotificationService init error: $e');
    }
  }

  bool _isMobilePlatform() {
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _initializeNotifications({bool skipPermissionRequest = false}) async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: !skipPermissionRequest,
      requestBadgePermission: !skipPermissionRequest,
      requestSoundPermission: !skipPermissionRequest,
    );
    final initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notificationsPlugin.initialize(initSettings);

    if (!skipPermissionRequest && defaultTargetPlatform == TargetPlatform.iOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      _permissionRequested = true;
    }

    if (!skipPermissionRequest && defaultTargetPlatform == TargetPlatform.android) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _permissionRequested = true;
    }
  }

  void _subscribeToEvents() {
    _backupEventSubscription = EventBus().on<BackupEvent>((event) {
      unawaited(_handleEvent(event));
    });
  }

  Future<void> _handleEvent(BackupEvent event) async {
    if (!_initialized || !_isMobilePlatform()) return;

    final settings = NotificationService().getSettings();
    if (!settings.enableNotifications || !settings.notifySystemAlerts) {
      return;
    }

    // Avoid notifying for actions we originated if possible
    final myCallsign = ProfileService().getProfile().callsign;
    if (myCallsign.isEmpty) return;

    String? title;
    String? body;

    switch (event.type) {
      case BackupEventType.inviteReceived:
        title = 'Backup request received';
        body = '${event.counterpartCallsign ?? ''} wants to back up to you';
        break;
      case BackupEventType.inviteAccepted:
        title = 'Backup invite accepted';
        body = '${event.counterpartCallsign ?? ''} approved your backup request';
        break;
      case BackupEventType.inviteDeclined:
        title = 'Backup invite declined';
        body = '${event.counterpartCallsign ?? ''} declined your backup request';
        break;
      case BackupEventType.backupStarted:
        if (event.role == 'provider') {
          title = 'Backup started';
          body = '${event.counterpartCallsign ?? 'Client'} is backing up now';
        }
        break;
      case BackupEventType.backupCompleted:
        title = 'Backup completed';
        body = _formatCompletion(
          event.counterpartCallsign,
          event.totalFiles,
          event.totalBytes,
          isRestore: false,
        );
        break;
      case BackupEventType.backupFailed:
        title = 'Backup failed';
        body = _formatFailure(event.counterpartCallsign, event.message, isRestore: false);
        break;
      case BackupEventType.restoreCompleted:
        title = 'Restore completed';
        body = _formatCompletion(
          event.counterpartCallsign,
          event.totalFiles,
          event.totalBytes,
          isRestore: true,
        );
        break;
      case BackupEventType.restoreFailed:
        title = 'Restore failed';
        body = _formatFailure(event.counterpartCallsign, event.message, isRestore: true);
        break;
      case BackupEventType.restoreStarted:
      case BackupEventType.snapshotNoteUpdated:
        // No notification needed
        break;
    }

    if (title == null || body == null) return;
    await _showNotification(title: title, body: body);
  }

  String _formatCompletion(String? callsign, int? files, int? bytes, {required bool isRestore}) {
    final action = isRestore ? 'restored from' : 'backed up with';
    final fileLabel = files != null ? '$files files' : 'files';
    final sizeLabel = bytes != null ? _formatBytes(bytes) : '';
    final sizePart = sizeLabel.isNotEmpty ? ' ($sizeLabel)' : '';
    return '${callsign ?? 'Device'} $action $fileLabel$sizePart';
  }

  String _formatFailure(String? callsign, String? error, {required bool isRestore}) {
    final action = isRestore ? 'restore' : 'backup';
    final reason = (error ?? '').trim();
    final reasonText = reason.isEmpty ? '' : ': $reason';
    return '${action[0].toUpperCase()}${action.substring(1)} with ${callsign ?? 'device'} failed$reasonText';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _showNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      channelShowBadge: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  void dispose() {
    _backupEventSubscription?.cancel();
  }
}
