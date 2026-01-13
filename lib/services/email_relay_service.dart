/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Email Relay Service - Handles email routing between connected clients
 * Works on both CLI (pure_station) and Android (station_server_service)
 *
 * ## Email Routing Architecture
 *
 * This service handles two types of email routing:
 *
 * ### 1. Internal Emails (Geogram-to-Geogram)
 * - Recipient address ends with station domain (e.g., bob@p2p.radio)
 * - Routed directly via WebSocket if recipient is connected
 * - Queued in `_pendingEmails` if recipient is offline
 * - No approval needed - these are trusted internal communications
 *
 * ### 2. External Emails (to non-Geogram addresses)
 * - Recipient address is external (e.g., someone@gmail.com)
 * - ALWAYS queued in `_externalApprovalQueue` for moderation
 * - Station operator must approve before SMTP delivery
 * - This prevents spam and protects domain reputation
 *
 * ## Why External Email Approval is Critical
 *
 * Sending unmoderated emails to external addresses poses serious risks:
 * - Domain blacklisting by major email providers
 * - IP reputation damage
 * - Legal liability for spam
 * - Abuse of station resources
 *
 * ## Approval Workflow (Future Implementation)
 *
 * 1. Client sends email to external address
 * 2. Email is queued in `_externalApprovalQueue` with status `pending`
 * 3. Station operator reviews via admin interface (TODO: implement UI)
 * 4. Operator can:
 *    - `approve`: Email is sent via SMTP, sender notified
 *    - `reject`: Email is discarded, sender notified with reason
 *    - `ban_sender`: Reject + add sender to blocklist
 * 5. Approved senders can optionally be added to allowlist for auto-approval
 *
 * ## Future Enhancements (TODO)
 *
 * - [ ] Admin UI for reviewing pending external emails
 * - [ ] Allowlist for trusted senders (auto-approve)
 * - [ ] Blocklist for known spammers (auto-reject)
 * - [ ] Rate limiting per sender (e.g., max 10 external emails/day)
 * - [ ] Content filtering (keywords, links, attachments)
 * - [ ] SMTP delivery integration (when approved)
 * - [ ] Webhook notifications for new pending emails
 * - [ ] Email templates for rejection notices
 */

import 'dart:convert';

import '../util/nostr_event.dart';
import 'log_service.dart';
import 'nip05_registry_service.dart';
import 'smtp_client.dart';

/// Callback type for sending messages to clients
typedef SendToClientCallback = bool Function(String clientId, String message);

/// Callback type for finding a client by callsign
typedef FindClientByCallsignCallback = String? Function(String callsign);

/// Callback type for getting station domain
typedef GetStationDomainCallback = String Function();

/// Pending email entry
class PendingEmail {
  final Map<String, dynamic> message;
  final String senderCallsign;
  final String senderId;
  final String recipient;
  final DateTime timestamp;
  final DateTime retryUntil;

  PendingEmail({
    required this.message,
    required this.senderCallsign,
    required this.senderId,
    required this.recipient,
    required this.timestamp,
    required this.retryUntil,
  });

  bool get isExpired => DateTime.now().isAfter(retryUntil);
}

/// Approval status for external emails
enum ExternalEmailStatus {
  /// Awaiting station operator review
  pending,

  /// Approved by operator, ready for SMTP delivery
  approved,

  /// Rejected by operator, will not be sent
  rejected,

  /// Successfully sent via SMTP
  sent,

  /// SMTP delivery failed
  failed,
}

/// External email awaiting approval before SMTP delivery
///
/// External emails (to non-Geogram addresses) require station operator
/// approval to prevent spam and protect domain reputation.
class ExternalEmailEntry {
  final String id;
  final Map<String, dynamic> message;
  final String senderCallsign;
  final String senderId;
  final String senderNpub;
  final List<String> externalRecipients;
  final DateTime timestamp;
  ExternalEmailStatus status;
  String? rejectionReason;
  String? reviewedBy;
  DateTime? reviewedAt;

  /// Callback to send DSN back to the client after SMTP delivery
  final SendToClientCallback? sendToClientCallback;

  ExternalEmailEntry({
    required this.id,
    required this.message,
    required this.senderCallsign,
    required this.senderId,
    required this.senderNpub,
    required this.externalRecipients,
    required this.timestamp,
    this.status = ExternalEmailStatus.pending,
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    this.sendToClientCallback,
  });

  String get threadId => message['thread_id'] as String? ?? id;
  String get subject => message['subject'] as String? ?? '(No Subject)';
  String get content => message['content'] as String? ?? '';

  /// Check if this entry has been waiting too long (default: 7 days)
  bool isExpired([Duration maxAge = const Duration(days: 7)]) {
    return DateTime.now().isAfter(timestamp.add(maxAge));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'thread_id': threadId,
    'sender_callsign': senderCallsign,
    'sender_npub': senderNpub,
    'external_recipients': externalRecipients,
    'subject': subject,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'rejection_reason': rejectionReason,
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt?.toIso8601String(),
  };
}

/// Email relay service for routing emails between connected clients
class EmailRelayService {
  static final EmailRelayService _instance = EmailRelayService._internal();
  factory EmailRelayService() => _instance;
  EmailRelayService._internal();

  /// Pending email deliveries for offline internal recipients (key: threadId_recipient)
  final Map<String, PendingEmail> _pendingEmails = {};

  /// External emails awaiting approval before SMTP delivery (key: entry.id)
  /// These are emails to non-Geogram addresses that require moderation.
  final Map<String, ExternalEmailEntry> _externalApprovalQueue = {};

  /// Allowlist of sender callsigns that can send external emails without approval
  /// TODO: Persist this to disk and provide admin UI to manage
  final Set<String> _externalEmailAllowlist = {};

  /// Blocklist of sender callsigns that are banned from sending external emails
  /// TODO: Persist this to disk and provide admin UI to manage
  final Set<String> _externalEmailBlocklist = {};

  /// Email relay settings
  EmailRelaySettings settings = EmailRelaySettings();

  // ============================================================
  // External Email Approval Queue Methods
  // ============================================================

  /// Get all pending external emails awaiting approval
  List<ExternalEmailEntry> getPendingExternalEmails() {
    return _externalApprovalQueue.values
        .where((e) => e.status == ExternalEmailStatus.pending)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Get external email entry by ID
  ExternalEmailEntry? getExternalEmailById(String id) {
    return _externalApprovalQueue[id];
  }

  /// Approve an external email for SMTP delivery
  ///
  /// Returns true if approved successfully.
  /// After approval, the email should be sent via SMTP (TODO: implement).
  bool approveExternalEmail({
    required String emailId,
    required String reviewerCallsign,
    bool addToAllowlist = false,
  }) {
    final entry = _externalApprovalQueue[emailId];
    if (entry == null || entry.status != ExternalEmailStatus.pending) {
      return false;
    }

    entry.status = ExternalEmailStatus.approved;
    entry.reviewedBy = reviewerCallsign;
    entry.reviewedAt = DateTime.now();

    // Optionally add sender to allowlist for future auto-approval
    if (addToAllowlist) {
      _externalEmailAllowlist.add(entry.senderCallsign.toUpperCase());
    }

    LogService().log('External email approved: ${entry.id} by $reviewerCallsign');

    // Trigger SMTP delivery
    _sendExternalEmailViaSMTP(entry);

    return true;
  }

  /// Send approved external email via SMTP
  ///
  /// This is called automatically when an external email is approved.
  /// Runs asynchronously and updates the entry status based on result.
  Future<void> _sendExternalEmailViaSMTP(ExternalEmailEntry entry) async {
    if (settings.stationDomain == 'localhost') {
      LogService().log('SMTP: Station domain not configured, skipping delivery');
      entry.status = ExternalEmailStatus.failed;
      return;
    }

    // Create DKIM config if private key is available
    DkimConfig? dkimConfig;
    if (settings.dkimPrivateKey != null && settings.dkimPrivateKey!.isNotEmpty) {
      dkimConfig = DkimConfig(
        privateKeyPem: settings.dkimPrivateKey!,
        selector: settings.dkimSelector,
      );
    }

    final client = SMTPClient(
      localDomain: settings.stationDomain,
      defaultPort: settings.smtpPort,
      dkimConfig: dkimConfig,
    );

    // Build sender email from callsign
    final fromEmail = '${entry.senderCallsign.toLowerCase()}@${settings.stationDomain}';

    // Extract email body from content (base64 decoded thread.md content)
    String body;
    try {
      body = utf8.decode(base64Decode(entry.content));
    } catch (_) {
      body = entry.content; // Already plain text
    }

    LogService().log('SMTP: Sending external email from $fromEmail to ${entry.externalRecipients.join(", ")}');

    try {
      final result = await client.send(
        from: fromEmail,
        to: entry.externalRecipients,
        subject: entry.subject,
        body: body,
        extraHeaders: {
          'X-Geogram-Thread-ID': entry.threadId,
          'X-Geogram-Sender-Npub': entry.senderNpub,
        },
      );

      if (result.success) {
        entry.status = ExternalEmailStatus.sent;
        LogService().log('SMTP: Successfully sent external email: ${entry.id} (${result.message})');

        // Send DSN to notify sender of successful delivery
        if (entry.sendToClientCallback != null) {
          final dsn = _createDsn(
            action: 'delivered',
            threadId: entry.threadId,
            recipient: entry.externalRecipients.join(', '),
          );
          entry.sendToClientCallback!(entry.senderId, jsonEncode(dsn));
          LogService().log('SMTP: Sent delivery confirmation DSN to ${entry.senderCallsign}');
        }
      } else {
        entry.status = ExternalEmailStatus.failed;
        LogService().log('SMTP: Failed to send external email: ${entry.id} - ${result.error}');

        // Send DSN to notify sender of failed delivery
        if (entry.sendToClientCallback != null) {
          final dsn = _createDsn(
            action: 'failed',
            threadId: entry.threadId,
            recipient: entry.externalRecipients.join(', '),
            reason: result.error ?? 'SMTP delivery failed',
          );
          entry.sendToClientCallback!(entry.senderId, jsonEncode(dsn));
        }
      }
    } catch (e) {
      entry.status = ExternalEmailStatus.failed;
      LogService().log('SMTP: Exception sending external email: ${entry.id} - $e');

      // Send DSN to notify sender of exception
      if (entry.sendToClientCallback != null) {
        final dsn = _createDsn(
          action: 'failed',
          threadId: entry.threadId,
          recipient: entry.externalRecipients.join(', '),
          reason: 'SMTP error: $e',
        );
        entry.sendToClientCallback!(entry.senderId, jsonEncode(dsn));
      }
    }
  }

  /// Reject an external email
  ///
  /// Returns true if rejected successfully.
  /// Optionally notifies the sender of the rejection.
  bool rejectExternalEmail({
    required String emailId,
    required String reviewerCallsign,
    String? reason,
    bool banSender = false,
    SendToClientCallback? sendToClient,
  }) {
    final entry = _externalApprovalQueue[emailId];
    if (entry == null || entry.status != ExternalEmailStatus.pending) {
      return false;
    }

    entry.status = ExternalEmailStatus.rejected;
    entry.rejectionReason = reason ?? 'Email rejected by station operator';
    entry.reviewedBy = reviewerCallsign;
    entry.reviewedAt = DateTime.now();

    // Optionally ban the sender
    if (banSender) {
      _externalEmailBlocklist.add(entry.senderCallsign.toUpperCase());
      LogService().log('Sender banned from external emails: ${entry.senderCallsign}');
    }

    LogService().log('External email rejected: ${entry.id} by $reviewerCallsign - ${entry.rejectionReason}');

    // Notify sender if callback provided
    if (sendToClient != null) {
      final dsn = _createDsn(
        action: 'failed',
        threadId: entry.threadId,
        recipient: entry.externalRecipients.join(', '),
        reason: 'External email rejected: ${entry.rejectionReason}',
      );
      sendToClient(entry.senderId, jsonEncode(dsn));
    }

    return true;
  }

  /// Check if a sender is allowed to send external emails without approval
  bool isSenderAllowlisted(String callsign) {
    return _externalEmailAllowlist.contains(callsign.toUpperCase());
  }

  /// Check if a sender is blocked from sending external emails
  bool isSenderBlocklisted(String callsign) {
    return _externalEmailBlocklist.contains(callsign.toUpperCase());
  }

  /// Add sender to allowlist
  void addToAllowlist(String callsign) {
    _externalEmailAllowlist.add(callsign.toUpperCase());
    _externalEmailBlocklist.remove(callsign.toUpperCase());
  }

  /// Remove sender from allowlist
  void removeFromAllowlist(String callsign) {
    _externalEmailAllowlist.remove(callsign.toUpperCase());
  }

  /// Add sender to blocklist
  void addToBlocklist(String callsign) {
    _externalEmailBlocklist.add(callsign.toUpperCase());
    _externalEmailAllowlist.remove(callsign.toUpperCase());
  }

  /// Remove sender from blocklist
  void removeFromBlocklist(String callsign) {
    _externalEmailBlocklist.remove(callsign.toUpperCase());
  }

  /// Get count of pending external emails
  int get pendingExternalEmailCount =>
      _externalApprovalQueue.values.where((e) => e.status == ExternalEmailStatus.pending).length;

  /// Clean up old external email entries (approved, rejected, or expired)
  void cleanupExternalEmailQueue([Duration maxAge = const Duration(days: 30)]) {
    final toRemove = <String>[];
    for (final entry in _externalApprovalQueue.entries) {
      if (entry.value.status != ExternalEmailStatus.pending ||
          entry.value.isExpired(maxAge)) {
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _externalApprovalQueue.remove(key);
    }
    if (toRemove.isNotEmpty) {
      LogService().log('Cleaned up ${toRemove.length} external email queue entries');
    }
  }

  // ============================================================
  // Email Routing
  // ============================================================

  /// Check if an email address is internal (Geogram-to-Geogram)
  bool _isInternalAddress(String email, String stationDomain) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return true; // No @ means local callsign

    final domain = email.substring(atIndex + 1).toLowerCase();
    return domain == stationDomain.toLowerCase() ||
           domain == 'local' ||
           domain.isEmpty;
  }

  /// Handle email send request
  /// Returns a map of recipient -> delivery status
  Map<String, String> handleEmailSend({
    required Map<String, dynamic> message,
    required String senderCallsign,
    required String senderId,
    required SendToClientCallback sendToClient,
    required FindClientByCallsignCallback findClientByCallsign,
    required GetStationDomainCallback getStationDomain,
  }) {
    final threadId = message['thread_id'] as String?;
    final recipients = message['to'] as List<dynamic>?;
    final subject = message['subject'] as String?;
    final content = message['content'] as String?;
    final event = message['event'] as Map<String, dynamic>?;

    final deliveryResults = <String, String>{};

    // Validate required fields
    if (threadId == null || recipients == null || recipients.isEmpty || content == null) {
      // Send failure DSN back to sender
      final dsn = _createDsn(
        action: 'failed',
        threadId: threadId,
        recipient: recipients?.firstOrNull?.toString(),
        reason: 'Missing required fields (thread_id, to, content)',
      );
      sendToClient(senderId, jsonEncode(dsn));
      return {'error': 'missing_fields'};
    }

    // Verify NOSTR signature if present
    if (event != null) {
      try {
        final nostrEvent = NostrEvent.fromJson(event);
        if (!nostrEvent.verify()) {
          final dsn = _createDsn(
            action: 'failed',
            threadId: threadId,
            reason: 'Invalid NOSTR signature',
          );
          sendToClient(senderId, jsonEncode(dsn));
          return {'error': 'invalid_signature'};
        }
      } catch (e) {
        LogService().log('Email relay: failed to verify NOSTR event: $e');
      }

      // Validate sender owns the email identity (NIP-05)
      final senderNpub = event['pubkey'] as String?;
      if (senderNpub != null && senderNpub.isNotEmpty) {
        final registry = Nip05RegistryService();
        final collision = registry.checkCollision(senderCallsign, senderNpub);
        if (collision != null) {
          final dsn = _createDsn(
            action: 'failed',
            threadId: threadId,
            reason: 'Email address "$senderCallsign" belongs to another identity',
          );
          sendToClient(senderId, jsonEncode(dsn));
          LogService().log(
            'Email rejected: NIP-05 validation failed - $senderCallsign belongs to different npub',
          );
          return {'error': 'nip05_mismatch'};
        }
      }
    }

    LogService().log('Email send: $senderCallsign -> ${recipients.join(", ")} (thread: $threadId)');

    final stationDomain = getStationDomain();

    // Separate internal vs external recipients
    final internalRecipients = <String>[];
    final externalRecipients = <String>[];

    for (final recipient in recipients) {
      final recipientStr = recipient.toString();
      if (_isInternalAddress(recipientStr, stationDomain)) {
        internalRecipients.add(recipientStr);
      } else {
        externalRecipients.add(recipientStr);
      }
    }

    // Process internal recipients (Geogram-to-Geogram)
    for (final recipientStr in internalRecipients) {
      final targetCallsign = _extractCallsign(recipientStr);

      // Find recipient client
      final targetClientId = findClientByCallsign(targetCallsign);

      if (targetClientId != null) {
        // Recipient is connected - deliver immediately
        final deliveryMessage = {
          'type': 'email_receive',
          'from': '${senderCallsign.toLowerCase()}@$stationDomain',
          'thread_id': threadId,
          'subject': subject,
          'content': content,
          'event': event,
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
        };

        if (sendToClient(targetClientId, jsonEncode(deliveryMessage))) {
          deliveryResults[recipientStr] = 'delivered';
          LogService().log('Email delivered: $senderCallsign -> $targetCallsign (thread: $threadId)');
        } else {
          deliveryResults[recipientStr] = 'failed';
        }
      } else {
        // Recipient not connected - queue for later delivery
        final pendingKey = '${threadId}_$recipientStr';
        _pendingEmails[pendingKey] = PendingEmail(
          message: message,
          senderCallsign: senderCallsign,
          senderId: senderId,
          recipient: recipientStr,
          timestamp: DateTime.now(),
          retryUntil: DateTime.now().add(Duration(hours: settings.retryHours)),
        );

        deliveryResults[recipientStr] = 'delayed';
        LogService().log('Email queued: $senderCallsign -> $recipientStr (thread: $threadId)');
      }
    }

    // Process external recipients (requires approval before SMTP delivery)
    if (externalRecipients.isNotEmpty) {
      // Check if sender is blocked
      if (isSenderBlocklisted(senderCallsign)) {
        for (final recipientStr in externalRecipients) {
          deliveryResults[recipientStr] = 'blocked';
        }
        LogService().log('External email blocked: $senderCallsign is on blocklist');

        final dsn = _createDsn(
          action: 'failed',
          threadId: threadId,
          recipient: externalRecipients.join(', '),
          reason: 'You are not permitted to send external emails from this station',
        );
        sendToClient(senderId, jsonEncode(dsn));
      }
      // Check if sender is on allowlist (auto-approve)
      else if (isSenderAllowlisted(senderCallsign)) {
        final entryId = '${threadId}_external_${DateTime.now().millisecondsSinceEpoch}';
        final senderNpub = event?['pubkey'] as String? ?? '';

        final entry = ExternalEmailEntry(
          id: entryId,
          message: message,
          senderCallsign: senderCallsign,
          senderId: senderId,
          senderNpub: senderNpub,
          externalRecipients: externalRecipients,
          timestamp: DateTime.now(),
          status: ExternalEmailStatus.approved, // Auto-approved
          reviewedBy: 'allowlist',
          reviewedAt: DateTime.now(),
          sendToClientCallback: sendToClient, // Store callback for DSN
        );
        _externalApprovalQueue[entryId] = entry;

        for (final recipientStr in externalRecipients) {
          deliveryResults[recipientStr] = 'queued_approved';
        }
        LogService().log('External email auto-approved (allowlisted sender): $senderCallsign -> ${externalRecipients.join(", ")}');

        // Trigger SMTP delivery
        _sendExternalEmailViaSMTP(entry);
      }
      // Queue for manual approval
      else {
        final entryId = '${threadId}_external_${DateTime.now().millisecondsSinceEpoch}';
        final senderNpub = event?['pubkey'] as String? ?? '';

        _externalApprovalQueue[entryId] = ExternalEmailEntry(
          id: entryId,
          message: message,
          senderCallsign: senderCallsign,
          senderId: senderId,
          senderNpub: senderNpub,
          externalRecipients: externalRecipients,
          timestamp: DateTime.now(),
          status: ExternalEmailStatus.pending,
          sendToClientCallback: sendToClient, // Store callback for DSN
        );

        for (final recipientStr in externalRecipients) {
          deliveryResults[recipientStr] = 'pending_approval';
        }
        LogService().log('External email queued for approval: $senderCallsign -> ${externalRecipients.join(", ")} (id: $entryId)');

        // Notify sender that email is pending approval
        final dsn = _createDsn(
          action: 'pending_approval',
          threadId: threadId,
          recipient: externalRecipients.join(', '),
          reason: 'External emails require station operator approval before delivery',
        );
        sendToClient(senderId, jsonEncode(dsn));
      }
    }

    // Send DSN for each recipient
    for (final entry in deliveryResults.entries) {
      final dsn = _createDsn(
        action: entry.value,
        threadId: threadId,
        recipient: entry.key,
        reason: entry.value == 'delayed'
            ? 'Recipient device offline'
            : entry.value == 'failed'
                ? 'Failed to deliver message'
                : null,
        retryUntil: entry.value == 'delayed'
            ? DateTime.now().add(Duration(hours: settings.retryHours))
            : null,
      );
      sendToClient(senderId, jsonEncode(dsn));
    }

    return deliveryResults;
  }

  /// Deliver pending emails when a client connects
  void deliverPendingEmails({
    required String clientId,
    required String callsign,
    required SendToClientCallback sendToClient,
    required GetStationDomainCallback getStationDomain,
  }) {
    final toDeliver = <String>[];
    final toRemove = <String>[];

    // Find pending emails for this recipient
    for (final entry in _pendingEmails.entries) {
      final pending = entry.value;

      // Check if expired
      if (pending.isExpired) {
        toRemove.add(entry.key);
        continue;
      }

      // Check if this is for our client
      final targetCallsign = _extractCallsign(pending.recipient);
      if (targetCallsign.toUpperCase() == callsign.toUpperCase()) {
        toDeliver.add(entry.key);
      }
    }

    // Deliver pending emails
    for (final key in toDeliver) {
      final pending = _pendingEmails[key];
      if (pending == null) continue;

      final message = pending.message;
      final threadId = message['thread_id'] as String?;
      final subject = message['subject'] as String?;
      final content = message['content'] as String?;
      final event = message['event'] as Map<String, dynamic>?;

      final deliveryMessage = {
        'type': 'email_receive',
        'from': '${pending.senderCallsign.toLowerCase()}@${getStationDomain()}',
        'thread_id': threadId,
        'subject': subject,
        'content': content,
        'event': event,
        'delivered_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (sendToClient(clientId, jsonEncode(deliveryMessage))) {
        LogService().log('Email delivered (queued): ${pending.senderCallsign} -> $callsign (thread: $threadId)');

        // Notify original sender
        final dsn = _createDsn(
          action: 'delivered',
          threadId: threadId,
          recipient: pending.recipient,
        );
        sendToClient(pending.senderId, jsonEncode(dsn));

        toRemove.add(key);
      }
    }

    // Remove delivered/expired emails
    for (final key in toRemove) {
      _pendingEmails.remove(key);
    }

    if (toDeliver.isNotEmpty) {
      LogService().log('Delivered ${toDeliver.length} pending email(s) to $callsign');
    }
  }

  /// Clean up expired pending emails
  void cleanupExpiredEmails() {
    final toRemove = <String>[];
    for (final entry in _pendingEmails.entries) {
      if (entry.value.isExpired) {
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _pendingEmails.remove(key);
    }
    if (toRemove.isNotEmpty) {
      LogService().log('Cleaned up ${toRemove.length} expired pending email(s)');
    }
  }

  /// Get pending email count
  int get pendingEmailCount => _pendingEmails.length;

  /// Extract callsign from email address
  String _extractCallsign(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex > 0) {
      return email.substring(0, atIndex).toUpperCase();
    }
    return email.toUpperCase();
  }

  /// Create DSN (Delivery Status Notification) message
  Map<String, dynamic> _createDsn({
    required String action,
    String? threadId,
    String? recipient,
    String? reason,
    DateTime? retryUntil,
  }) {
    final dsn = <String, dynamic>{
      'type': 'email_dsn',
      'action': action,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    if (threadId != null) dsn['thread_id'] = threadId;
    if (recipient != null) dsn['recipient'] = recipient;
    if (reason != null) dsn['reason'] = reason;
    if (retryUntil != null) {
      dsn['will_retry_until'] = retryUntil.toIso8601String();
      dsn['retry_after'] = settings.retryIntervalSeconds;
    }

    return dsn;
  }
}

/// Email relay settings
class EmailRelaySettings {
  /// Hours to keep pending emails before expiring
  int retryHours;

  /// Seconds between retry attempts (for DSN info)
  int retryIntervalSeconds;

  /// SMTP port for external email (use higher port on non-root devices)
  int smtpPort;

  /// Whether SMTP server is enabled
  bool smtpEnabled;

  /// Station domain for SMTP client (e.g., p2p.radio)
  String stationDomain;

  /// DKIM private key in PEM format for signing outgoing emails
  String? dkimPrivateKey;

  /// DKIM selector (default: geogram)
  String dkimSelector;

  EmailRelaySettings({
    this.retryHours = 24,
    this.retryIntervalSeconds = 300,
    this.smtpPort = 2525, // Default to non-privileged port
    this.smtpEnabled = false,
    this.stationDomain = 'localhost',
    this.dkimPrivateKey,
    this.dkimSelector = 'geogram',
  });

  /// Get appropriate SMTP port based on environment
  /// On non-root devices (Android), returns configured high port
  /// On root/CLI, can use standard port 25 if configured
  static int getDefaultSmtpPort({bool isPrivileged = false}) {
    return isPrivileged ? 25 : 2525;
  }

  factory EmailRelaySettings.fromJson(Map<String, dynamic> json) {
    return EmailRelaySettings(
      retryHours: json['retryHours'] as int? ?? 24,
      retryIntervalSeconds: json['retryIntervalSeconds'] as int? ?? 300,
      smtpPort: json['smtpPort'] as int? ?? 2525,
      smtpEnabled: json['smtpEnabled'] as bool? ?? false,
      stationDomain: json['stationDomain'] as String? ?? 'localhost',
    );
  }

  Map<String, dynamic> toJson() => {
    'retryHours': retryHours,
    'retryIntervalSeconds': retryIntervalSeconds,
    'smtpPort': smtpPort,
    'smtpEnabled': smtpEnabled,
    'stationDomain': stationDomain,
  };
}
