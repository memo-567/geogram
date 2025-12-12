/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Service for syncing alert feedback (likes, verifications, comments) to station.
 * Uses best-effort pattern: local changes are saved first, station sync is fire-and-forget.
 */

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'station_service.dart';
import 'log_service.dart';

/// Service for syncing alert feedback to station
class AlertFeedbackService {
  static final AlertFeedbackService _instance = AlertFeedbackService._internal();
  factory AlertFeedbackService() => _instance;
  AlertFeedbackService._internal();

  final StationService _stationService = StationService();

  /// Get the station base URL (converts wss:// to https://)
  String? _getStationHttpUrl() {
    final station = _stationService.getPreferredStation();
    if (station == null || station.url.isEmpty) return null;

    var baseUrl = station.url;
    if (baseUrl.startsWith('wss://')) {
      baseUrl = baseUrl.replaceFirst('wss://', 'https://');
    } else if (baseUrl.startsWith('ws://')) {
      baseUrl = baseUrl.replaceFirst('ws://', 'http://');
    }

    return baseUrl;
  }

  /// Like an alert on the station (best-effort)
  ///
  /// Returns true if successful, false otherwise.
  /// Failures are logged but do not throw.
  Future<bool> likeAlertOnStation(String alertId, String npub) async {
    try {
      final baseUrl = _getStationHttpUrl();
      if (baseUrl == null) {
        LogService().log('AlertFeedbackService: No station configured');
        return false;
      }

      final uri = Uri.parse('$baseUrl/api/alerts/$alertId/like');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'npub': npub}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          LogService().log('AlertFeedbackService: Liked alert $alertId on station');
          return true;
        }
      }

      LogService().log('AlertFeedbackService: Failed to like alert: ${response.statusCode}');
      return false;
    } catch (e) {
      LogService().log('AlertFeedbackService: Error liking alert on station: $e');
      return false;
    }
  }

  /// Unlike an alert on the station (best-effort)
  Future<bool> unlikeAlertOnStation(String alertId, String npub) async {
    try {
      final baseUrl = _getStationHttpUrl();
      if (baseUrl == null) {
        LogService().log('AlertFeedbackService: No station configured');
        return false;
      }

      final uri = Uri.parse('$baseUrl/api/alerts/$alertId/unlike');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'npub': npub}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          LogService().log('AlertFeedbackService: Unliked alert $alertId on station');
          return true;
        }
      }

      LogService().log('AlertFeedbackService: Failed to unlike alert: ${response.statusCode}');
      return false;
    } catch (e) {
      LogService().log('AlertFeedbackService: Error unliking alert on station: $e');
      return false;
    }
  }

  /// Verify an alert on the station (best-effort)
  Future<bool> verifyAlertOnStation(String alertId, String npub) async {
    try {
      final baseUrl = _getStationHttpUrl();
      if (baseUrl == null) {
        LogService().log('AlertFeedbackService: No station configured');
        return false;
      }

      final uri = Uri.parse('$baseUrl/api/alerts/$alertId/verify');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'npub': npub}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          LogService().log('AlertFeedbackService: Verified alert $alertId on station');
          return true;
        }
      }

      LogService().log('AlertFeedbackService: Failed to verify alert: ${response.statusCode}');
      return false;
    } catch (e) {
      LogService().log('AlertFeedbackService: Error verifying alert on station: $e');
      return false;
    }
  }

  /// Add a signed comment to an alert on the station (best-effort)
  Future<bool> commentOnStation(
    String alertId,
    String author,
    String content, {
    String? npub,
    String? signature,
  }) async {
    try {
      final baseUrl = _getStationHttpUrl();
      if (baseUrl == null) {
        LogService().log('AlertFeedbackService: No station configured');
        return false;
      }

      final uri = Uri.parse('$baseUrl/api/alerts/$alertId/comment');
      final body = <String, dynamic>{
        'author': author,
        'content': content,
      };
      if (npub != null && npub.isNotEmpty) {
        body['npub'] = npub;
      }
      if (signature != null && signature.isNotEmpty) {
        body['signature'] = signature;
      }

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          LogService().log('AlertFeedbackService: Added comment to alert $alertId on station');
          return true;
        }
      }

      LogService().log('AlertFeedbackService: Failed to add comment: ${response.statusCode}');
      return false;
    } catch (e) {
      LogService().log('AlertFeedbackService: Error adding comment on station: $e');
      return false;
    }
  }
}
