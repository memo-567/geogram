/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Email Service - Manages email threads across multiple stations
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/email_thread.dart';
import '../platform/file_system_service.dart';
import '../util/email_format.dart';
import '../util/event_bus.dart';
import '../util/nostr_crypto.dart';
import '../util/nostr_event.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'signing_service.dart';
import 'station_service.dart';
import 'websocket_service.dart';

/// Event for email changes
class EmailChangeEvent {
  final String station;
  final String threadId;
  final EmailChangeType type;

  EmailChangeEvent(this.station, this.threadId, this.type);
}

enum EmailChangeType {
  created,
  updated,
  deleted,
  statusChanged,
  received,
}

/// Service for managing emails across multiple stations
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  /// Base path for email storage
  String? _emailBasePath;

  /// Connected email accounts (station -> account)
  final Map<String, EmailAccount> _accounts = {};

  /// Cached threads by station and folder
  final Map<String, Map<String, List<EmailThread>>> _threadCache = {};

  /// Stream controller for email events
  final StreamController<EmailChangeEvent> _eventController =
      StreamController<EmailChangeEvent>.broadcast();

  /// Stream of email change events
  Stream<EmailChangeEvent> get onEmailChange => _eventController.stream;

  /// Whether the service is initialized
  bool _initialized = false;

  /// Initialize email service
  Future<void> initialize() async {
    if (_initialized) return;

    _emailBasePath = await _getEmailBasePath();
    await _ensureDirectoryStructure();
    _initialized = true;
  }

  /// Get base path for email storage
  Future<String> _getEmailBasePath() async {
    if (kIsWeb) {
      return '/email';
    }

    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'geogram', 'email');
  }

  /// Ensure base directory structure exists (unified folders)
  Future<void> _ensureDirectoryStructure() async {
    if (_emailBasePath == null) return;

    final dirs = [
      _emailBasePath!,
      '$_emailBasePath/inbox',
      '$_emailBasePath/outbox',
      '$_emailBasePath/sent',
      '$_emailBasePath/spam',
      '$_emailBasePath/drafts',
      '$_emailBasePath/garbage',
      '$_emailBasePath/archive',
      '$_emailBasePath/labels',
    ];

    for (final dir in dirs) {
      await _ensureDirectory(dir);
    }
  }

  /// Ensure directory exists
  Future<void> _ensureDirectory(String path) async {
    if (kIsWeb) {
      final fs = FileSystemService.instance;
      if (!await fs.exists(path)) {
        await fs.createDirectory(path, recursive: true);
      }
    } else {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Register an email account for a station
  Future<void> registerAccount(EmailAccount account) async {
    _accounts[account.station] = account;
    // Unified folders are created in _ensureDirectoryStructure()
  }

  /// Unregister an email account
  void unregisterAccount(String station) {
    final account = _accounts[station];
    if (account != null) {
      account.isConnected = false;
    }
  }

  /// Get all registered accounts
  List<EmailAccount> get accounts => _accounts.values.toList();

  /// Get account for a specific station
  EmailAccount? getAccount(String station) => _accounts[station];

  /// Get connected accounts only
  List<EmailAccount> get connectedAccounts =>
      _accounts.values.where((a) => a.isConnected).toList();

  /// Set account connection status
  void setAccountConnected(String station, bool connected) {
    final account = _accounts[station];
    if (account != null) {
      account.isConnected = connected;
    }
  }

  // ============================================================
  // Thread Operations
  // ============================================================

  /// Create a new draft thread
  Future<EmailThread> createDraft({
    required String from,
    required List<String> to,
    required String subject,
    List<String>? cc,
    List<String>? bcc,
    String? station,
  }) async {
    final thread = EmailThread.draft(
      from: from,
      to: to,
      subject: subject,
      cc: cc,
      bcc: bcc,
      station: station,
    );

    await saveThread(thread);
    return thread;
  }

  /// Save a thread to disk
  Future<void> saveThread(EmailThread thread) async {
    if (_emailBasePath == null) await initialize();

    final relativePath = EmailFormat.getThreadPath(thread);
    final threadPath = '$_emailBasePath/$relativePath';

    // Ensure all parent directories exist (including year subdirectories)
    if (kIsWeb) {
      await FileSystemService.instance.createDirectory(threadPath, recursive: true);
    } else {
      final dir = Directory(threadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    // Write thread.md
    final content = EmailFormat.export(thread);
    final filePath = '$threadPath/thread.md';

    if (kIsWeb) {
      await FileSystemService.instance.writeAsString(filePath, content);
    } else {
      await File(filePath).writeAsString(content);
    }

    thread.folderPath = relativePath;

    // Notify listeners
    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.updated,
    ));
  }

  /// Get the full folder path for a thread (for attachments)
  Future<String?> getThreadFolderPath(EmailThread thread) async {
    if (_emailBasePath == null) await initialize();
    final relativePath =
        thread.folderPath ?? EmailFormat.getThreadPath(thread);
    return '$_emailBasePath/$relativePath';
  }

  /// Load a thread from disk
  Future<EmailThread?> loadThread(String threadPath) async {
    if (_emailBasePath == null) await initialize();

    final filePath = '$_emailBasePath/$threadPath/thread.md';

    try {
      String content;
      if (kIsWeb) {
        if (!await FileSystemService.instance.exists(filePath)) return null;
        content = await FileSystemService.instance.readAsString(filePath);
      } else {
        final file = File(filePath);
        if (!await file.exists()) return null;
        content = await file.readAsString();
      }

      final thread = EmailFormat.parse(content);
      if (thread != null) {
        thread.folderPath = threadPath;
      }
      return thread;
    } catch (e) {
      print('Error loading thread: $e');
      return null;
    }
  }

  /// List threads in a folder (unified folder structure)
  Future<List<EmailThread>> listThreads(String folder) async {
    if (_emailBasePath == null) await initialize();

    final threads = <EmailThread>[];
    final basePath = '$_emailBasePath/$folder';

    try {
      if (kIsWeb) {
        final fs = FileSystemService.instance;
        if (!await fs.exists(basePath)) return threads;
        // Web implementation would need directory listing
        return threads;
      }

      final dir = Directory(basePath);
      if (!await dir.exists()) return threads;

      // Handle year subdirectories for inbox/sent/spam/garbage
      if (folder == 'inbox' ||
          folder == 'sent' ||
          folder == 'spam' ||
          folder == 'garbage') {
        await for (final yearEntity in dir.list()) {
          if (yearEntity is Directory) {
            await for (final threadEntity in yearEntity.list()) {
              if (threadEntity is Directory) {
                final thread = await _loadThreadFromDir(threadEntity.path);
                if (thread != null) threads.add(thread);
              }
            }
          }
        }
      } else {
        // Outbox and drafts don't have year subdirectories
        await for (final threadEntity in dir.list()) {
          if (threadEntity is Directory) {
            final thread = await _loadThreadFromDir(threadEntity.path);
            if (thread != null) threads.add(thread);
          }
        }
      }

      // Sort by last message time (newest first)
      threads.sort();
    } catch (e) {
      print('Error listing threads: $e');
    }

    return threads;
  }

  /// Load thread from directory path
  Future<EmailThread?> _loadThreadFromDir(String dirPath) async {
    final filePath = '$dirPath/thread.md';
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final thread = EmailFormat.parse(content);
      if (thread != null) {
        // Extract relative path
        final relativePath = dirPath.substring(_emailBasePath!.length + 1);
        thread.folderPath = relativePath;
      }
      return thread;
    } catch (e) {
      return null;
    }
  }

  /// Get inbox threads (unified)
  Future<List<EmailThread>> getInbox() => listThreads('inbox');

  /// Get sent threads (unified)
  Future<List<EmailThread>> getSent() => listThreads('sent');

  /// Get outbox threads (unified)
  Future<List<EmailThread>> getOutbox() => listThreads('outbox');

  /// Get draft threads
  Future<List<EmailThread>> getDrafts() => listThreads('drafts');

  /// Get spam threads (unified)
  Future<List<EmailThread>> getSpam() => listThreads('spam');

  /// Get deleted threads
  Future<List<EmailThread>> getGarbage() => listThreads('garbage');

  /// Get archived threads
  Future<List<EmailThread>> getArchive() => listThreads('archive');

  // ============================================================
  // Message Operations
  // ============================================================

  /// Add a message to a thread
  Future<void> addMessage(EmailThread thread, EmailMessage message) async {
    thread.addMessage(message);
    await saveThread(thread);
  }

  /// Create and add a signed message
  Future<EmailMessage> createSignedMessage({
    required EmailThread thread,
    required String content,
    Map<String, String>? metadata,
  }) async {
    final profile = ProfileService().getProfile();

    final message = EmailMessage.now(
      author: profile.callsign,
      content: content,
      metadata: metadata,
    );

    // Add NOSTR identity to metadata
    if (profile.npub != null) {
      message.metadata['npub'] = profile.npub!;
    }

    // Sign the message content using NOSTR event signing
    final signingService = SigningService();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Create a NOSTR event for the message
    final event = NostrEvent(
      pubkey: profile.npub != null ? NostrCrypto.decodeNpub(profile.npub!) : '',
      createdAt: now,
      kind: 1, // Text note
      tags: [
        ['t', 'email'],
        ['thread_id', thread.threadId],
        ['callsign', profile.callsign],
      ],
      content: content,
    );

    // Sign the event
    final signedEvent = await signingService.signEvent(event, profile);
    if (signedEvent != null && signedEvent.sig != null) {
      message.metadata['signature'] = signedEvent.sig!;
      if (signedEvent.id != null) {
        message.metadata['event_id'] = signedEvent.id!;
      }
      message.metadata['created_at'] = now.toString();
    }

    thread.addMessage(message);
    await saveThread(thread);

    return message;
  }

  // ============================================================
  // Status Operations
  // ============================================================

  /// Move thread to sent (after successful delivery)
  Future<void> markAsSent(EmailThread thread) async {
    if (thread.status == EmailStatus.sent) return;

    // Delete from current location
    await _deleteThreadFiles(thread);

    // Update status and save to new location
    thread.status = EmailStatus.sent;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Move thread to outbox (pending delivery)
  Future<void> markAsPending(EmailThread thread) async {
    if (thread.status == EmailStatus.pending) return;

    await _deleteThreadFiles(thread);
    thread.status = EmailStatus.pending;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Move thread to spam
  Future<void> markAsSpam(EmailThread thread) async {
    if (thread.status == EmailStatus.spam) return;

    await _deleteThreadFiles(thread);
    thread.status = EmailStatus.spam;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Move thread to garbage
  Future<void> deleteThread(EmailThread thread) async {
    if (thread.status == EmailStatus.deleted) return;

    await _deleteThreadFiles(thread);
    thread.status = EmailStatus.deleted;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.deleted,
    ));
  }

  /// Permanently delete thread
  Future<void> permanentlyDelete(EmailThread thread) async {
    await _deleteThreadFiles(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.deleted,
    ));
  }

  /// Move thread to archive
  Future<void> archiveThread(EmailThread thread) async {
    if (thread.status == EmailStatus.archived) return;

    await _deleteThreadFiles(thread);
    thread.status = EmailStatus.archived;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Move thread to a specific status/folder
  Future<void> moveThread(EmailThread thread, EmailStatus targetStatus) async {
    if (thread.status == targetStatus) return;

    await _deleteThreadFiles(thread);
    thread.status = targetStatus;
    await saveThread(thread);

    _eventController.add(EmailChangeEvent(
      thread.station,
      thread.threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Restore thread from trash/spam back to inbox
  Future<void> restoreThread(EmailThread thread) async {
    await moveThread(thread, EmailStatus.received);
  }

  /// Delete thread files from current location
  Future<void> _deleteThreadFiles(EmailThread thread) async {
    if (thread.folderPath == null) return;

    final threadPath = '$_emailBasePath/${thread.folderPath}';

    try {
      if (kIsWeb) {
        // Web implementation would need recursive delete
      } else {
        final dir = Directory(threadPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      print('Error deleting thread files: $e');
    }
  }

  // ============================================================
  // Labels
  // ============================================================

  /// Add label to thread
  Future<void> addLabel(EmailThread thread, String label) async {
    if (thread.labels.contains(label)) return;

    thread.labels = [...thread.labels, label];
    await saveThread(thread);
    await _updateLabelRefs(label, thread, add: true);
  }

  /// Remove label from thread
  Future<void> removeLabel(EmailThread thread, String label) async {
    if (!thread.labels.contains(label)) return;

    thread.labels = thread.labels.where((l) => l != label).toList();
    await saveThread(thread);
    await _updateLabelRefs(label, thread, add: false);
  }

  /// Update label refs.json
  Future<void> _updateLabelRefs(String label, EmailThread thread, {required bool add}) async {
    final labelPath = '$_emailBasePath/labels/$label';
    final refsPath = '$labelPath/refs.json';

    await _ensureDirectory(labelPath);

    Map<String, dynamic> refs;

    try {
      if (kIsWeb) {
        if (await FileSystemService.instance.exists(refsPath)) {
          final content = await FileSystemService.instance.readAsString(refsPath);
          refs = jsonDecode(content) as Map<String, dynamic>;
        } else {
          refs = {'label': label, 'threads': []};
        }
      } else {
        final file = File(refsPath);
        if (await file.exists()) {
          refs = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        } else {
          refs = {'label': label, 'threads': []};
        }
      }
    } catch (e) {
      refs = {'label': label, 'threads': []};
    }

    final threads = (refs['threads'] as List).cast<String>();

    if (add) {
      if (!threads.contains(thread.folderPath)) {
        threads.add(thread.folderPath!);
      }
    } else {
      threads.remove(thread.folderPath);
    }

    refs['threads'] = threads;

    final content = const JsonEncoder.withIndent('  ').convert(refs);

    if (kIsWeb) {
      await FileSystemService.instance.writeAsString(refsPath, content);
    } else {
      await File(refsPath).writeAsString(content);
    }
  }

  /// Get all labels
  Future<List<String>> getLabels() async {
    if (_emailBasePath == null) await initialize();

    final labels = <String>[];
    final labelsPath = '$_emailBasePath/labels';

    try {
      if (kIsWeb) {
        // Web implementation would need directory listing
        return labels;
      }

      final dir = Directory(labelsPath);
      if (!await dir.exists()) return labels;

      await for (final entity in dir.list()) {
        if (entity is Directory) {
          labels.add(p.basename(entity.path));
        }
      }

      labels.sort();
    } catch (e) {
      print('Error getting labels: $e');
    }

    return labels;
  }

  /// Create a new label
  Future<void> createLabel(String label) async {
    if (_emailBasePath == null) await initialize();

    final labelPath = '$_emailBasePath/labels/$label';
    await _ensureDirectory(labelPath);

    // Create empty refs.json
    final refsPath = '$labelPath/refs.json';
    final content = '{"label": "$label", "threads": []}';

    if (kIsWeb) {
      await FileSystemService.instance.writeAsString(refsPath, content);
    } else {
      await File(refsPath).writeAsString(content);
    }
  }

  /// Delete a label
  Future<void> deleteLabel(String label) async {
    if (_emailBasePath == null) await initialize();

    final labelPath = '$_emailBasePath/labels/$label';

    try {
      if (kIsWeb) {
        // Web implementation would need recursive delete
      } else {
        final dir = Directory(labelPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      print('Error deleting label: $e');
    }
  }

  /// Get threads with a specific label
  Future<List<EmailThread>> getThreadsByLabel(String label) async {
    final threads = <EmailThread>[];
    final refsPath = '$_emailBasePath/labels/$label/refs.json';

    try {
      String content;
      if (kIsWeb) {
        if (!await FileSystemService.instance.exists(refsPath)) return threads;
        content = await FileSystemService.instance.readAsString(refsPath);
      } else {
        final file = File(refsPath);
        if (!await file.exists()) return threads;
        content = await file.readAsString();
      }

      final refs = jsonDecode(content) as Map<String, dynamic>;
      final threadPaths = (refs['threads'] as List).cast<String>();

      for (final path in threadPaths) {
        final thread = await loadThread(path);
        if (thread != null) {
          threads.add(thread);
        }
      }

      threads.sort();
    } catch (e) {
      print('Error getting threads by label: $e');
    }

    return threads;
  }

  // ============================================================
  // Config
  // ============================================================

  /// Save email config
  Future<void> saveConfig(Map<String, dynamic> config) async {
    if (_emailBasePath == null) await initialize();

    final configPath = '$_emailBasePath/config.json';
    final content = const JsonEncoder.withIndent('  ').convert(config);

    if (kIsWeb) {
      await FileSystemService.instance.writeAsString(configPath, content);
    } else {
      await File(configPath).writeAsString(content);
    }
  }

  /// Load email config
  Future<Map<String, dynamic>> loadConfig() async {
    if (_emailBasePath == null) await initialize();

    final configPath = '$_emailBasePath/config.json';

    try {
      String content;
      if (kIsWeb) {
        if (!await FileSystemService.instance.exists(configPath)) return {};
        content = await FileSystemService.instance.readAsString(configPath);
      } else {
        final file = File(configPath);
        if (!await file.exists()) return {};
        content = await file.readAsString();
      }

      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  // ============================================================
  // WebSocket Send Operations
  // ============================================================

  /// Send a thread via WebSocket to the station relay
  Future<bool> sendViaWebSocket(EmailThread thread) async {
    final ws = WebSocketService();

    if (!ws.isConnected) {
      LogService().log('WebSocket not connected, cannot send email');
      EventBus().fire(EmailNotificationEvent(
        message: 'Cannot send: Not connected to station',
        action: 'failed',
        threadId: thread.threadId,
        recipient: thread.to.isNotEmpty ? thread.to.first : null,
      ));
      return false;
    }

    try {
      final profile = ProfileService().getProfile();
      final content = EmailFormat.export(thread);

      // Create NOSTR event for the email
      final event = NostrEvent(
        pubkey: profile.npub != null ? NostrCrypto.decodeNpub(profile.npub!) : '',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 30078, // Private direct message / email
        tags: [
          ['t', 'email'],
          ['thread_id', thread.threadId],
          ['subject', thread.subject],
        ],
        content: content,
      );

      // Sign the event
      final signedEvent = await SigningService().signEvent(event, profile);

      // Build the message
      final message = <String, dynamic>{
        'type': 'email_send',
        'thread_id': thread.threadId,
        'to': thread.to,
        'cc': thread.cc,
        'subject': thread.subject,
        'content': base64Encode(utf8.encode(content)),
        'event': signedEvent?.toJson(),
      };

      // Send via WebSocket
      ws.send(message);

      // Fire pending notification - actual delivery confirmed via DSN
      EventBus().fire(EmailNotificationEvent(
        message: 'Email queued, awaiting delivery...',
        action: 'pending',
        threadId: thread.threadId,
        recipient: thread.to.isNotEmpty ? thread.to.first : null,
      ));

      return true;
    } catch (e) {
      LogService().log('Error sending email via WebSocket: $e');
      EventBus().fire(EmailNotificationEvent(
        message: 'Failed to send: $e',
        action: 'failed',
        threadId: thread.threadId,
        recipient: thread.to.isNotEmpty ? thread.to.first : null,
      ));
      return false;
    }
  }

  /// Process outbox - attempt to send all pending emails
  /// Note: Emails stay in outbox until DSN confirmation from station
  Future<void> processOutbox() async {
    final pending = await getOutbox();
    for (final thread in pending) {
      if (thread.status == EmailStatus.pending) {
        // Check if the station for this thread is connected
        final account = _accounts[thread.station];
        if (account == null || !account.isConnected) continue;

        // Send via WebSocket - email stays in outbox until DSN confirms delivery
        await sendViaWebSocket(thread);
        // Don't mark as sent here - wait for DSN confirmation
      }
    }
  }

  /// Handle delivery status notification from station
  Future<void> handleDSN(Map<String, dynamic> dsn) async {
    final threadId = dsn['thread_id'] as String?;
    final action = dsn['action'] as String?;
    final recipient = dsn['recipient'] as String?;
    final reason = dsn['reason'] as String?;

    if (threadId == null || action == null) return;

    LogService().log('DSN received: action=$action, threadId=$threadId, recipient=$recipient');

    // Find the thread in unified outbox
    final outbox = await getOutbox();
    final thread = outbox.firstWhere(
      (t) => t.threadId == threadId,
      orElse: () => EmailThread(
        station: '',
        from: '',
        to: [],
        subject: '',
        created: '',
        threadId: '',
      ),
    );

    String? notificationMessage;

    if (thread.threadId.isNotEmpty) {
      switch (action) {
        case 'delivered':
          await markAsSent(thread);
          notificationMessage = 'Email delivered to ${recipient ?? thread.to.join(", ")}';
          break;
        case 'failed':
          thread.status = EmailStatus.failed;
          await saveThread(thread);
          notificationMessage = 'Email delivery failed${reason != null ? ": $reason" : ""}';
          break;
        case 'pending_approval':
          // Email is waiting for station operator approval
          notificationMessage = 'Email to $recipient awaiting station approval';
          break;
        case 'delayed':
          // Keep in outbox, maybe add retry info to metadata
          notificationMessage = 'Email to $recipient delayed - recipient offline';
          break;
      }
    }

    // Fire notification event for UI to display
    if (notificationMessage != null) {
      EventBus().fire(EmailNotificationEvent(
        message: notificationMessage,
        action: action!,
        threadId: threadId,
        recipient: recipient,
      ));
    }

    _eventController.add(EmailChangeEvent(
      '',
      threadId,
      EmailChangeType.statusChanged,
    ));
  }

  /// Receive an email from the station (via WebSocket)
  ///
  /// This is called when the station forwards an email to this client.
  /// The email can be from:
  /// - Another Geogram user (internal)
  /// - An external sender via SMTP
  Future<bool> receiveEmail(Map<String, dynamic> message) async {
    try {
      await initialize();

      final from = message['from'] as String?;
      final threadId = message['thread_id'] as String?;
      final subject = message['subject'] as String?;
      final contentB64 = message['content'] as String?;
      final event = message['event'] as Map<String, dynamic>?;

      if (from == null || threadId == null || contentB64 == null) {
        LogService().log('EmailService: Invalid email_receive message - missing fields');
        return false;
      }

      // Decode content (base64-encoded thread.md)
      String content;
      try {
        content = utf8.decode(base64Decode(contentB64));
      } catch (_) {
        content = contentB64; // Already plain text
      }

      // Parse the thread content
      EmailThread? thread = EmailFormat.parse(content);

      if (thread == null) {
        // Content might just be the message body, not full thread.md
        // Create a new thread for this received email
        final timestamp = DateTime.now();
        final created = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
            '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}_'
            '${timestamp.second.toString().padLeft(2, '0')}';

        // Extract station from recipient address
        final profile = ProfileService().getProfile();
        final stationService = StationService();
        final preferredStation = stationService.getPreferredStation();
        final station = preferredStation?.name ?? 'p2p.radio';

        thread = EmailThread(
          station: station,
          from: from,
          to: ['${profile.callsign.toLowerCase()}@$station'],
          subject: subject ?? '(No Subject)',
          created: created,
          status: EmailStatus.received,
          threadId: threadId,
          messages: [],
        );

        // Extract sender callsign for message author
        final senderCallsign = from.contains('@')
            ? from.split('@').first.toUpperCase()
            : from.toUpperCase();

        // Create the message
        final emailMessage = EmailMessage(
          author: senderCallsign,
          timestamp: created,
          content: content,
          metadata: {},
        );

        // Add NOSTR metadata if event provided
        if (event != null) {
          emailMessage.metadata['event_id'] = event['id'] as String? ?? '';
          emailMessage.metadata['npub'] = event['pubkey'] as String? ?? '';
          emailMessage.metadata['signature'] = event['sig'] as String? ?? '';
        }

        thread.messages.add(emailMessage);
      } else {
        // Thread was parsed from content, mark as received
        thread.status = EmailStatus.received;
      }

      // Save to inbox
      await saveThread(thread);

      LogService().log('EmailService: Received email from $from (thread: $threadId)');

      // Notify listeners
      _eventController.add(EmailChangeEvent(
        thread.station,
        threadId,
        EmailChangeType.received,
      ));

      return true;
    } catch (e, stack) {
      LogService().log('EmailService: Error receiving email: $e\n$stack');
      return false;
    }
  }

  // ============================================
  // Frequent Contacts Management
  // ============================================

  /// Cached frequent contacts
  List<FrequentContact>? _frequentContacts;

  /// Get the path to frequent.json
  String get _frequentJsonPath => '$_emailBasePath/frequent.json';

  /// Load frequent contacts from disk
  Future<List<FrequentContact>> loadFrequentContacts() async {
    if (_emailBasePath == null) await initialize();

    if (_frequentContacts != null) return _frequentContacts!;

    try {
      String content;
      if (kIsWeb) {
        if (!await FileSystemService.instance.exists(_frequentJsonPath)) {
          _frequentContacts = [];
          return _frequentContacts!;
        }
        content = await FileSystemService.instance.readAsString(_frequentJsonPath);
      } else {
        final file = File(_frequentJsonPath);
        if (!await file.exists()) {
          _frequentContacts = [];
          return _frequentContacts!;
        }
        content = await file.readAsString();
      }

      final List<dynamic> jsonList = jsonDecode(content);
      _frequentContacts = jsonList
          .map((json) => FrequentContact.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by count descending
      _frequentContacts!.sort((a, b) => b.count.compareTo(a.count));
      return _frequentContacts!;
    } catch (e) {
      print('Error loading frequent contacts: $e');
      _frequentContacts = [];
      return _frequentContacts!;
    }
  }

  /// Save frequent contacts to disk
  Future<void> _saveFrequentContacts() async {
    if (_emailBasePath == null) await initialize();
    if (_frequentContacts == null) return;

    try {
      final content = jsonEncode(
          _frequentContacts!.map((c) => c.toJson()).toList());

      if (kIsWeb) {
        await FileSystemService.instance.writeAsString(_frequentJsonPath, content);
      } else {
        await File(_frequentJsonPath).writeAsString(content);
      }
    } catch (e) {
      print('Error saving frequent contacts: $e');
    }
  }

  /// Update frequent contacts when sending to recipients
  /// Call this when sending an email to track usage
  Future<void> trackRecipients(List<String> recipients, {String? senderName}) async {
    if (recipients.isEmpty) return;

    await loadFrequentContacts();

    for (final recipient in recipients) {
      // Parse email to extract name and address
      final parsed = _parseEmailAddress(recipient);
      final email = parsed['email']!.toLowerCase();
      final name = parsed['name'] ?? senderName ?? '';

      // Find existing or create new
      final existingIndex =
          _frequentContacts!.indexWhere((c) => c.email.toLowerCase() == email);

      if (existingIndex >= 0) {
        // Update existing
        final existing = _frequentContacts![existingIndex];
        _frequentContacts![existingIndex] = FrequentContact(
          name: name.isNotEmpty ? name : existing.name,
          email: existing.email,
          count: existing.count + 1,
        );
      } else {
        // Add new
        _frequentContacts!.add(FrequentContact(
          name: name,
          email: email,
          count: 1,
        ));
      }
    }

    // Re-sort by count
    _frequentContacts!.sort((a, b) => b.count.compareTo(a.count));

    await _saveFrequentContacts();
  }

  /// Parse an email address string to extract name and email
  /// Handles formats like: "John Doe <john@example.com>" or "john@example.com"
  Map<String, String> _parseEmailAddress(String input) {
    final trimmed = input.trim();

    // Check for "Name <email>" format
    final match = RegExp(r'^(.+?)\s*<(.+?)>$').firstMatch(trimmed);
    if (match != null) {
      return {
        'name': match.group(1)!.trim(),
        'email': match.group(2)!.trim(),
      };
    }

    // Just email address
    return {
      'name': '',
      'email': trimmed,
    };
  }

  /// Get top frequent contacts (for dropdown suggestions)
  Future<List<FrequentContact>> getTopFrequentContacts({int limit = 10}) async {
    final contacts = await loadFrequentContacts();
    return contacts.take(limit).toList();
  }

  /// Search frequent contacts by name or email
  Future<List<FrequentContact>> searchFrequentContacts(String query) async {
    if (query.isEmpty) return [];

    final contacts = await loadFrequentContacts();
    final lowerQuery = query.toLowerCase();

    return contacts.where((c) {
      return c.name.toLowerCase().contains(lowerQuery) ||
          c.email.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Clear the frequent contacts cache (call after external modification)
  void clearFrequentContactsCache() {
    _frequentContacts = null;
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
}

/// Model for a frequently used contact
class FrequentContact {
  final String name;
  final String email;
  final int count;

  FrequentContact({
    required this.name,
    required this.email,
    required this.count,
  });

  factory FrequentContact.fromJson(Map<String, dynamic> json) {
    return FrequentContact(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'count': count,
      };

  /// Display string for autocomplete
  String get displayString {
    if (name.isNotEmpty) {
      return '$name <$email>';
    }
    return email;
  }
}
