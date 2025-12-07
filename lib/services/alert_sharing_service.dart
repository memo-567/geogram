/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Service for sharing alerts to relays using signed NOSTR events.
 * Uses NIP-78 (kind 30078) for application-specific data.
 */

import 'dart:async';
import '../models/report.dart';
import '../util/nostr_event.dart';
import '../util/nostr_crypto.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'signing_service.dart';
import 'websocket_service.dart';
import 'station_service.dart';

/// Result of sending an alert to a station
class AlertSendResult {
  final String stationUrl;
  final bool success;
  final String? eventId;
  final String? message;

  AlertSendResult({
    required this.stationUrl,
    required this.success,
    this.eventId,
    this.message,
  });

  @override
  String toString() =>
      'AlertSendResult($stationUrl, success: $success, eventId: ${eventId?.substring(0, 8)}...)';
}

/// Summary of multi-station alert sharing
class AlertShareSummary {
  final int confirmed;
  final int failed;
  final int skipped;
  final String? eventId;
  final List<AlertSendResult> results;

  AlertShareSummary({
    required this.confirmed,
    required this.failed,
    required this.skipped,
    this.eventId,
    required this.results,
  });

  bool get anySuccess => confirmed > 0;
  bool get allSuccess => failed == 0 && skipped == 0;

  @override
  String toString() =>
      'AlertShareSummary(confirmed: $confirmed, failed: $failed, skipped: $skipped)';
}

/// Service for sharing alerts to relays using signed NOSTR events
class AlertSharingService {
  static final AlertSharingService _instance = AlertSharingService._internal();
  factory AlertSharingService() => _instance;
  AlertSharingService._internal();

  final ProfileService _profileService = ProfileService();
  final SigningService _signingService = SigningService();
  final WebSocketService _webSocketService = WebSocketService();
  final StationService _stationService = StationService();

  /// Sign a report and create a NOSTR alert event
  ///
  /// Returns a tuple of (signedReport, nostrEvent) where:
  /// - signedReport has npub and signature in metadata
  /// - nostrEvent is the signed NOSTR event ready to send
  ///
  /// Returns null if signing fails.
  Future<({Report report, NostrEvent event})?> signReportAndCreateEvent(Report report) async {
    try {
      // Get profile
      final profile = _profileService.getProfile();
      if (profile.npub.isEmpty) {
        LogService().log('AlertSharingService: No npub in profile');
        return null;
      }

      // Initialize signing service
      await _signingService.initialize();
      if (!_signingService.canSign(profile)) {
        LogService().log('AlertSharingService: Cannot sign (no nsec or extension)');
        return null;
      }

      // Get current Unix timestamp for signing
      final signedAtUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // First, add npub and signed_at to the report metadata (before creating event)
      final updatedMetadata = Map<String, String>.from(report.metadata);
      updatedMetadata['npub'] = profile.npub;
      updatedMetadata['signed_at'] = signedAtUnix.toString();
      var signedReport = report.copyWith(metadata: updatedMetadata);

      // Create the NOSTR alert event with the report content
      final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);
      final event = NostrEvent.alert(
        pubkeyHex: pubkeyHex,
        report: signedReport,
        createdAt: signedAtUnix,  // Use same timestamp for NOSTR event
      );

      // Calculate ID and sign the event
      event.calculateId();
      final signedEvent = await _signingService.signEvent(event, profile);

      if (signedEvent == null || signedEvent.sig == null) {
        LogService().log('AlertSharingService: Failed to sign NOSTR event');
        return null;
      }

      // Add the event signature to report metadata
      updatedMetadata['signature'] = signedEvent.sig!;
      signedReport = signedReport.copyWith(metadata: updatedMetadata);

      LogService().log('AlertSharingService: Report signed with npub ${profile.npub.substring(0, 16)}...');

      return (report: signedReport, event: signedEvent);
    } catch (e) {
      LogService().log('AlertSharingService: Error signing report: $e');
      return null;
    }
  }

  /// Share alert to all configured relays
  ///
  /// Returns a summary with confirmed/failed/skipped counts.
  /// Confirmed relays are skipped on subsequent calls.
  Future<AlertShareSummary> shareAlert(Report report) async {
    final stationUrls = getRelayUrls();
    if (stationUrls.isEmpty) {
      LogService().log('AlertSharingService: No stations configured');
      return AlertShareSummary(
        confirmed: 0,
        failed: 0,
        skipped: 0,
        results: [],
      );
    }

    return await shareAlertToRelays(report, stationUrls);
  }

  /// Share alert to specific relays
  ///
  /// Creates one signed NOSTR event and sends it to all relays.
  /// Tracks status per station in the report.
  Future<AlertShareSummary> shareAlertToRelays(
    Report report,
    List<String> stationUrls,
  ) async {
    if (stationUrls.isEmpty) {
      return AlertShareSummary(
        confirmed: 0,
        failed: 0,
        skipped: 0,
        results: [],
      );
    }

    // Create signed event once (same event for all relays)
    final event = await createAlertEvent(report);
    if (event == null) {
      LogService().log('AlertSharingService: Failed to create alert event');
      return AlertShareSummary(
        confirmed: 0,
        failed: stationUrls.length,
        skipped: 0,
        results: stationUrls
            .map((url) => AlertSendResult(
                  stationUrl: url,
                  success: false,
                  message: 'Failed to create event',
                ))
            .toList(),
      );
    }

    final results = <AlertSendResult>[];
    int confirmed = 0;
    int failed = 0;
    int skipped = 0;

    // Send to each station
    for (final stationUrl in stationUrls) {
      // Check if already confirmed for this station
      if (!report.needsSharingToRelay(stationUrl)) {
        LogService().log('AlertSharingService: Skipping $stationUrl (already confirmed)');
        skipped++;
        results.add(AlertSendResult(
          stationUrl: stationUrl,
          success: true,
          eventId: event.id,
          message: 'Already confirmed',
        ));
        continue;
      }

      // Send to station
      final result = await sendEventToRelay(event, stationUrl);
      results.add(result);

      if (result.success) {
        confirmed++;
      } else {
        failed++;
      }
    }

    LogService().log(
        'AlertSharingService: Shared alert to stations - confirmed: $confirmed, failed: $failed, skipped: $skipped');

    return AlertShareSummary(
      confirmed: confirmed,
      failed: failed,
      skipped: skipped,
      eventId: event.id,
      results: results,
    );
  }

  /// Create a signed NOSTR alert event from a report
  ///
  /// Returns null if signing fails.
  Future<NostrEvent?> createAlertEvent(Report report) async {
    try {
      // Get profile
      final profile = _profileService.getProfile();
      if (profile.npub.isEmpty) {
        LogService().log('AlertSharingService: No npub in profile');
        return null;
      }

      // Initialize signing service
      await _signingService.initialize();
      if (!_signingService.canSign(profile)) {
        LogService().log('AlertSharingService: Cannot sign (no nsec or extension)');
        return null;
      }

      // Decode npub to hex public key
      final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);

      // Create alert event
      final event = NostrEvent.alert(
        pubkeyHex: pubkeyHex,
        report: report,
      );

      // Calculate ID and sign
      event.calculateId();
      final signedEvent = await _signingService.signEvent(event, profile);

      if (signedEvent == null || signedEvent.sig == null) {
        LogService().log('AlertSharingService: Signing failed');
        return null;
      }

      LogService().log(
          'AlertSharingService: Created alert event ${signedEvent.id?.substring(0, 16)}...');

      return signedEvent;
    } catch (e) {
      LogService().log('AlertSharingService: Error creating alert event: $e');
      return null;
    }
  }

  /// Send a NOSTR event to a specific station and wait for acknowledgment
  Future<AlertSendResult> sendEventToRelay(
    NostrEvent event,
    String stationUrl, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      LogService().log('═══════════════════════════════════════════════════════');
      LogService().log('ALERT SEND: Attempting to send alert to $stationUrl');
      LogService().log('  Event ID: ${event.id}');
      LogService().log('  Event Kind: ${event.kind}');
      LogService().log('═══════════════════════════════════════════════════════');

      final eventId = event.id;
      if (eventId == null) {
        LogService().log('ALERT SEND FAILED: Event has no ID');
        return AlertSendResult(
          stationUrl: stationUrl,
          success: false,
          eventId: null,
          message: 'Event has no ID',
        );
      }

      // Create the NOSTR EVENT message in the format the station expects
      // Format: {"nostr_event": ["EVENT", {...event object...}]}
      final eventMessage = {
        'nostr_event': ['EVENT', event.toJson()],
      };

      // Send via WebSocket and wait for OK response
      final result = await _webSocketService.sendEventAndWaitForOk(
        eventMessage,
        eventId,
        timeout: timeout,
      );

      if (result.success) {
        LogService().log('ALERT SEND SUCCESS: Station confirmed receipt');
        LogService().log('  Event ID: $eventId');
        return AlertSendResult(
          stationUrl: stationUrl,
          success: true,
          eventId: eventId,
          message: result.message ?? 'Confirmed by station',
        );
      } else {
        LogService().log('ALERT SEND FAILED: Station rejected or no response');
        LogService().log('  Reason: ${result.message}');
        return AlertSendResult(
          stationUrl: stationUrl,
          success: false,
          eventId: eventId,
          message: result.message ?? 'Station rejected event',
        );
      }
    } catch (e) {
      LogService().log('ALERT SEND ERROR: Failed to send to $stationUrl');
      LogService().log('  Error: $e');
      return AlertSendResult(
        stationUrl: stationUrl,
        success: false,
        eventId: event.id,
        message: e.toString(),
      );
    }
  }

  /// Get configured station URLs
  List<String> getRelayUrls() {
    // Get the preferred station from StationService
    final preferredStation = _stationService.getPreferredStation();

    if (preferredStation != null && preferredStation.url.isNotEmpty) {
      LogService().log('AlertSharingService: Using preferred station: ${preferredStation.url}');
      return [preferredStation.url];
    }

    // Fall back to default station
    LogService().log('AlertSharingService: No preferred station, using default wss://p2p.radio');
    return ['wss://p2p.radio'];
  }

  /// Update station share status in a report
  ///
  /// Returns a new Report with updated stationShares list.
  Report updateStationShareStatus(
    Report report,
    String stationUrl,
    StationShareStatusType status, {
    String? nostrEventId,
  }) {
    final now = DateTime.now();
    final shares = List<StationShareStatus>.from(report.stationShares);

    // Find existing share for this station
    final existingIndex = shares.indexWhere((s) => s.stationUrl == stationUrl);

    if (existingIndex >= 0) {
      // Update existing
      shares[existingIndex] = shares[existingIndex].copyWith(
        sentAt: now,
        status: status,
      );
    } else {
      // Add new
      shares.add(StationShareStatus(
        stationUrl: stationUrl,
        sentAt: now,
        status: status,
      ));
    }

    return report.copyWith(
      stationShares: shares,
      nostrEventId: nostrEventId ?? report.nostrEventId,
    );
  }
}
