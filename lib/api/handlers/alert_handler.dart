/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Shared Alert API handlers for station servers.
 * This module provides the core logic for alert-related API endpoints,
 * used by both PureStationServer (CLI) and StationServerService (GUI).
 */

import 'dart:typed_data';

import '../../models/report.dart';
import '../../services/profile_storage.dart';
import '../../util/alert_folder_utils.dart';
import '../../util/feedback_comment_utils.dart';
import '../common/file_tree_builder.dart';
import '../common/geometry_utils.dart';
import '../common/station_info.dart';

export '../common/station_info.dart' show StationInfo;

/// Shared Alert API handlers for station servers
class AlertHandler {
  final ProfileStorage storage;
  final StationInfo stationInfo;
  final void Function(String level, String message)? log;

  AlertHandler({
    required this.storage,
    required this.stationInfo,
    this.log,
  });

  void _log(String level, String message) {
    log?.call(level, message);
  }

  // ============================================================
  // GET /api/alerts - List all alerts
  // ============================================================

  /// Handle GET /api/alerts - returns list of alerts with optional filtering
  Future<Map<String, dynamic>> getAlerts({
    int? sinceTimestamp,
    double? lat,
    double? lon,
    double? radiusKm,
    String? statusFilter,
  }) async {
    try {
      // Load all alerts
      var alerts = await _loadAllAlerts(includeAllStatuses: statusFilter != null);

      // Filter by status if specified
      if (statusFilter != null) {
        alerts = alerts.where((a) => a['status'] == statusFilter).toList();
      }

      // Filter by since timestamp
      if (sinceTimestamp != null) {
        final sinceDate = DateTime.fromMillisecondsSinceEpoch(sinceTimestamp * 1000);
        alerts = alerts.where((alert) {
          final lastModifiedStr = alert['last_modified'] as String?;
          final createdStr = alert['created'] as String?;

          try {
            if (lastModifiedStr != null && lastModifiedStr.isNotEmpty) {
              final lastModified = DateTime.parse(lastModifiedStr);
              return lastModified.isAfter(sinceDate);
            }
            if (createdStr != null && createdStr.isNotEmpty) {
              final created = _parseAlertDateTime(createdStr);
              return created.isAfter(sinceDate);
            }
            return true;
          } catch (_) {
            return true;
          }
        }).toList();
      }

      // Filter by distance
      if (lat != null && lon != null && radiusKm != null && radiusKm > 0) {
        alerts = alerts.where((alert) {
          final alertLat = alert['latitude'] as double?;
          final alertLon = alert['longitude'] as double?;
          if (alertLat == null || alertLon == null) return false;
          if (alertLat == 0.0 && alertLon == 0.0) return false;

          final distance = GeometryUtils.calculateDistanceKm(lat, lon, alertLat, alertLon);
          return distance <= radiusKm;
        }).toList();
      }

      return {
        'success': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'station': stationInfo.toJson(),
        'filters': {
          if (sinceTimestamp != null) 'since': sinceTimestamp,
          if (lat != null) 'lat': lat,
          if (lon != null) 'lon': lon,
          if (radiusKm != null) 'radius_km': radiusKm,
          if (statusFilter != null) 'status': statusFilter,
        },
        'count': alerts.length,
        'alerts': alerts,
      };
    } catch (e) {
      _log('ERROR', 'Error in alerts API: $e');
      return {
        'success': false,
        'error': 'Internal server error',
        'message': e.toString(),
      };
    }
  }

  // ============================================================
  // GET /{callsign}/api/alerts/{alertId} - Alert details
  // ============================================================

  /// Handle GET /{callsign}/api/alerts/{alertId} - returns alert details with photos list
  Future<Map<String, dynamic>> getAlertDetails(String callsign, String alertId) async {
    try {
      // Search recursively for the alert folder
      final alertPath = await AlertFolderUtils.findAlertPath(
        'alerts',
        alertId,
        storage: storage,
      );

      _log('INFO', 'getAlertDetails: looking for alert $alertId under callsign $callsign');

      if (alertPath == null) {
        _log('WARN', 'getAlertDetails: alert not found: $alertId');
        return {'error': 'Alert not found', 'http_status': 404};
      }

      final reportContent = await storage.readString('$alertPath/report.txt');
      if (reportContent == null) {
        return {'error': 'Alert report not found', 'http_status': 404};
      }

      // Try to parse the report, but don't fail if parsing fails
      // The raw report_content will still be returned for clients to download
      Report? report;
      try {
        report = Report.fromText(reportContent, alertId);
      } catch (e) {
        _log('WARN', 'getAlertDetails: failed to parse report, returning raw content: $e');
      }

      // Find all photos (check both root and images/ subfolder)
      final photoExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
      final photos = <String>[];

      // Check images/ subfolder first (new structure)
      final imagesEntries = await storage.listDirectory('$alertPath/images');
      for (final entry in imagesEntries) {
        if (!entry.isDirectory) {
          final ext = entry.name.toLowerCase();
          if (photoExtensions.any((e) => ext.endsWith(e))) {
            photos.add('images/${entry.name}');
          }
        }
      }

      // Also check root folder for backwards compatibility
      final rootEntries = await storage.listDirectory(alertPath);
      for (final entry in rootEntries) {
        if (!entry.isDirectory) {
          final ext = entry.name.toLowerCase();
          if (photoExtensions.any((e) => ext.endsWith(e))) {
            photos.add(entry.name);
          }
        }
      }

      // Find all comments (feedback/comments)
      final comments = <Map<String, dynamic>>[];
      final feedbackComments = await FeedbackCommentUtils.loadComments(alertPath, storage: storage);
      for (final comment in feedbackComments) {
        comments.add({
          'filename': '${comment.id}.txt',
          'author': comment.author,
          'created': comment.created,
          'content': comment.content,
          if (comment.npub != null && comment.npub!.isNotEmpty) 'npub': comment.npub,
          if (comment.signature != null && comment.signature!.isNotEmpty) 'signature': comment.signature,
        });
      }

      // Sort comments by created time (oldest first)
      comments.sort((a, b) => (a['created'] as String).compareTo(b['created'] as String));

      // Read points from feedback/points.txt
      final pointedBy = await AlertFolderUtils.readPointsFile(alertPath, storage: storage);
      final verifiedByFeedback = await AlertFolderUtils.readVerificationsFile(alertPath, storage: storage);
      final mergedVerifiedBy = {
        ...?report?.verifiedBy,
        ...verifiedByFeedback,
      }.toList();

      // Build file tree for sync (requires absolute path)
      final absoluteAlertPath = storage.getAbsolutePath(alertPath);
      final fileTree = await FileTreeBuilder.build(absoluteAlertPath);

      _log('INFO', 'Alert details: found ${photos.length} photos, ${comments.length} comments, ${pointedBy.length} points');

      return {
        'id': alertId,
        'folder_name': report?.folderName ?? alertId,
        'title': report?.titles['EN'] ?? alertId,
        'description': report?.descriptions['EN'] ?? '',
        'latitude': report?.latitude ?? 0.0,
        'longitude': report?.longitude ?? 0.0,
        'severity': report?.severity.name ?? 'info',
        'status': report?.status.name ?? 'open',
        'type': report?.type ?? 'other',
        'point_count': pointedBy.length,
        'verification_count': mergedVerifiedBy.length,
        'pointed_by': pointedBy,
        'verified_by': mergedVerifiedBy,
        'last_modified': report?.lastModified,
        'files': fileTree,
        'photos': photos,
        'comments': comments,
        'comment_count': comments.length,
        'callsign': callsign,
        'report_content': reportContent,
      };
    } catch (e) {
      _log('ERROR', 'Error handling alert details: $e');
      return {
        'error': 'Internal server error',
        'message': e.toString(),
        'http_status': 500,
      };
    }
  }

  // ============================================================
  // POST /api/alerts/{alertId}/point - Point/unpoint alert
  // ============================================================

  /// Handle POST /api/alerts/{alertId}/point
  Future<Map<String, dynamic>> pointAlert(String alertId, String npub, {bool isPoint = true}) async {
    return {
      'error': 'Legacy alert feedback endpoint is deprecated',
      'message': 'Use /api/feedback/alert/{alertId}/{action}',
      'http_status': 410,
    };
  }

  // ============================================================
  // POST /api/alerts/{alertId}/verify - Verify alert
  // ============================================================

  /// Handle POST /api/alerts/{alertId}/verify
  Future<Map<String, dynamic>> verifyAlert(String alertId, String npub) async {
    return {
      'error': 'Legacy alert feedback endpoint is deprecated',
      'message': 'Use /api/feedback/alert/{alertId}/{action}',
      'http_status': 410,
    };
  }

  // ============================================================
  // POST /api/alerts/{alertId}/comment - Add comment
  // ============================================================

  /// Handle POST /api/alerts/{alertId}/comment
  Future<Map<String, dynamic>> addComment(
    String alertId,
    String author,
    String content, {
    String? npub,
    String? signature,
  }) async {
    return {
      'error': 'Legacy alert feedback endpoint is deprecated',
      'message': 'Use /api/feedback/alert/{alertId}/comment',
      'http_status': 410,
    };
  }

  // ============================================================
  // File handling: Upload and serve photos
  // ============================================================

  /// Handle alert photo upload
  Future<Map<String, dynamic>> uploadAlertPhoto(
    String callsign,
    String alertId,
    String filename,
    List<int> bytes, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Validate filename (allow images/ prefix)
      final cleanFilename = filename.replaceFirst('images/', '');
      if (cleanFilename.contains('..') || cleanFilename.contains('/')) {
        return {'error': 'Invalid filename', 'http_status': 400};
      }

      // Try to find existing alert folder
      var alertPath = await AlertFolderUtils.findAlertPath(
        'alerts',
        alertId,
        storage: storage,
      );

      if (alertPath == null) {
        // Create new alert directory with proper structure
        // If coordinates provided, use region folder; otherwise use flat structure
        if (latitude != null && longitude != null) {
          final regionFolder = AlertFolderUtils.getRegionFolder(latitude, longitude);
          alertPath = 'alerts/active/$regionFolder/$alertId';
        } else {
          // Fallback: flat structure without region folder
          alertPath = 'alerts/active/$alertId';
        }
        await storage.createDirectory(alertPath);
      }

      // Create images subfolder and use sequential naming
      final imagesPath = '$alertPath/images';
      await storage.createDirectory(imagesPath);

      // Get next sequential photo number
      final nextPhotoNum = await _getNextPhotoNumber(alertPath);

      // Determine file extension from provided filename
      final ext = cleanFilename.contains('.')
          ? cleanFilename.substring(cleanFilename.lastIndexOf('.'))
          : '.png';

      // Use sequential naming: photo{number}.{ext}
      final sequentialFilename = 'photo$nextPhotoNum$ext';
      await storage.writeBytes('$imagesPath/$sequentialFilename', Uint8List.fromList(bytes));

      _log('INFO', 'Uploaded alert photo: images/$sequentialFilename (${bytes.length} bytes)');

      return {
        'success': true,
        'filename': 'images/$sequentialFilename',
        'size': bytes.length,
        'path': '/api/alerts/$alertId/files/images/$sequentialFilename',
      };
    } catch (e) {
      _log('ERROR', 'Error uploading alert photo: $e');
      return {
        'error': 'Internal server error',
        'message': e.toString(),
        'http_status': 500,
      };
    }
  }

  /// Get the next sequential photo number in an alert's images folder
  Future<int> _getNextPhotoNumber(String alertPath) async {
    int maxNumber = 0;
    final imagesPath = '$alertPath/images';
    final entries = await storage.listDirectory(imagesPath);
    for (final entry in entries) {
      if (!entry.isDirectory) {
        final baseName = entry.name.contains('.')
            ? entry.name.substring(0, entry.name.lastIndexOf('.'))
            : entry.name;
        final match = RegExp(r'^photo(\d+)$').firstMatch(baseName);
        if (match != null) {
          final num = int.tryParse(match.group(1)!) ?? 0;
          if (num > maxNumber) maxNumber = num;
        }
      }
    }
    return maxNumber + 1;
  }

  /// Get alert photo file path (returns null if not found)
  /// Supports both new structure (images/filename) and legacy (filename in root)
  Future<String?> getAlertPhotoPath(String callsign, String alertId, String filename) async {
    // Handle images/ prefix
    final isInImagesFolder = filename.startsWith('images/');
    final cleanFilename = isInImagesFolder ? filename.substring(7) : filename;

    // Validate filename
    if (cleanFilename.contains('..') || cleanFilename.contains('/')) {
      return null;
    }

    // Find the alert folder first
    final alertPath = await AlertFolderUtils.findAlertPath(
      'alerts',
      alertId,
      storage: storage,
    );
    if (alertPath == null) return null;

    // Check images/ subfolder first (new structure)
    final imagesPhotoPath = '$alertPath/images/$cleanFilename';
    if (await storage.exists(imagesPhotoPath)) {
      return storage.getAbsolutePath(imagesPhotoPath);
    }

    // Check root folder for backwards compatibility
    final rootPhotoPath = '$alertPath/$cleanFilename';
    if (await storage.exists(rootPhotoPath)) {
      return storage.getAbsolutePath(rootPhotoPath);
    }

    return null;
  }

  // ============================================================
  // Internal helper methods
  // ============================================================

  /// Load all alerts from alerts directory
  Future<List<Map<String, dynamic>>> _loadAllAlerts({bool includeAllStatuses = false}) async {
    final alerts = <Map<String, dynamic>>[];

    if (!await storage.directoryExists('alerts')) {
      return alerts;
    }

    // Search recursively for report.txt files within alerts/
    final entries = await storage.listDirectory('alerts', recursive: true);
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (!entry.name.endsWith('report.txt')) continue;

      try {
        final content = await storage.readString(entry.path);
        if (content == null) continue;

        // Extract the folder name from the entry path
        // entry.path is like: alerts/active/region/folderName/report.txt
        final alertDirPath = entry.path.replaceFirst('/report.txt', '').replaceFirst('\\report.txt', '');
        final folderName = alertDirPath.split('/').last.split('\\').last;

        final alert = _parseAlertContent(content, stationInfo.callsign ?? 'unknown', folderName);

        // Include based on status filter
        if (includeAllStatuses ||
            alert['status'] == 'open' ||
            alert['status'] == 'in-progress') {
          alerts.add(alert);
        }
      } catch (e) {
        _log('WARN', 'Failed to parse alert: ${entry.path}');
      }
    }

    // Sort by severity then by date
    alerts.sort((a, b) {
      final severityOrder = {'emergency': 0, 'urgent': 1, 'attention': 2, 'info': 3};
      final severityCompare = (severityOrder[a['severity']] ?? 3).compareTo(severityOrder[b['severity']] ?? 3);
      if (severityCompare != 0) return severityCompare;
      return (b['created'] as String).compareTo(a['created'] as String);
    });

    return alerts;
  }

  /// Find alert by ID (folder name or API ID)
  Future<String?> _findAlertById(String alertId) async {
    if (!await storage.directoryExists('alerts')) return null;

    // Search recursively within alerts/
    final entries = await storage.listDirectory('alerts', recursive: true);
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      if (!entry.name.endsWith('report.txt')) continue;

      final alertDirPath = entry.path.replaceFirst('/report.txt', '').replaceFirst('\\report.txt', '');
      final folderName = alertDirPath.split('/').last.split('\\').last;

      // Match by folder name
      if (folderName == alertId) {
        return alertDirPath;
      }

      // Also match by API_ID in report.txt
      try {
        final content = await storage.readString(entry.path);
        if (content == null) continue;
        final apiIdMatch = RegExp(r'--> apiId: (.+)').firstMatch(content);
        if (apiIdMatch != null && apiIdMatch.group(1)?.trim() == alertId) {
          return alertDirPath;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Parse alert content from report.txt
  Map<String, dynamic> _parseAlertContent(String content, String callsign, String folderName) {
    final lines = content.split('\n');
    final alert = <String, dynamic>{
      'callsign': callsign,
      'folderName': folderName,
      'title': folderName,
      'severity': 'info',
      'status': 'open',
      'type': 'other',
      'created': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'description': '',
    };

    final descLines = <String>[];
    bool inDescription = false;

    for (final line in lines) {
      if (line.startsWith('# REPORT: ')) {
        alert['title'] = line.substring(10).trim();
      } else if (line.startsWith('# REPORT_EN: ')) {
        alert['title'] = line.substring(13).trim();
      } else if (line.startsWith('CREATED: ')) {
        alert['created'] = line.substring(9).trim();
      } else if (line.startsWith('AUTHOR: ')) {
        alert['author'] = line.substring(8).trim();
      } else if (line.startsWith('COORDINATES: ')) {
        final coords = line.substring(13).split(',');
        if (coords.length == 2) {
          alert['latitude'] = double.tryParse(coords[0].trim()) ?? 0.0;
          alert['longitude'] = double.tryParse(coords[1].trim()) ?? 0.0;
        }
      } else if (line.startsWith('SEVERITY: ')) {
        alert['severity'] = line.substring(10).trim().toLowerCase();
      } else if (line.startsWith('STATUS: ')) {
        alert['status'] = line.substring(8).trim().toLowerCase();
      } else if (line.startsWith('TYPE: ')) {
        alert['type'] = line.substring(6).trim();
      } else if (line.startsWith('ADDRESS: ')) {
        alert['address'] = line.substring(9).trim();
      // Note: POINTED_BY and POINT_COUNT are derived from feedback/points.txt
      } else if (line.startsWith('VERIFIED_BY: ')) {
        final verifiedByStr = line.substring(13).trim();
        alert['verified_by'] = verifiedByStr.isEmpty ? <String>[] : verifiedByStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        alert['verification_count'] = (alert['verified_by'] as List).length;
      } else if (line.startsWith('VERIFICATION_COUNT: ')) {
        alert['verification_count'] = int.tryParse(line.substring(20).trim()) ?? 0;
      } else if (line.startsWith('LAST_MODIFIED: ')) {
        alert['last_modified'] = line.substring(15).trim();
      } else if (line.startsWith('-->')) {
        inDescription = false;
      } else if (line.trim().isEmpty && !inDescription && alert['created'] != '') {
        inDescription = true;
      } else if (inDescription && !line.startsWith('[')) {
        descLines.add(line);
      }
    }

    alert['description'] = descLines.join('\n').trim();
    if ((alert['description'] as String).length > 300) {
      alert['description'] = (alert['description'] as String).substring(0, 300) + '...';
    }

    return alert;
  }

  /// Update alert feedback fields in report.txt content
  /// Note: pointedBy is derived from feedback/points.txt, not from report.txt
  String _updateAlertFeedback(
    String content, {
    List<String>? verifiedBy,
    String? lastModified,
  }) {
    final lines = content.split('\n');
    final newLines = <String>[];

    bool hasVerifiedBy = false;
    bool hasVerificationCount = false;
    bool hasLastModified = false;

    for (final line in lines) {
      // Skip old POINTED_BY and POINT_COUNT fields (derived from feedback/points.txt)
      if (line.startsWith('POINTED_BY: ') || line.startsWith('POINT_COUNT: ')) {
        continue;
      } else if (verifiedBy != null && line.startsWith('VERIFIED_BY: ')) {
        newLines.add('VERIFIED_BY: ${verifiedBy.join(', ')}');
        hasVerifiedBy = true;
      } else if (verifiedBy != null && line.startsWith('VERIFICATION_COUNT: ')) {
        newLines.add('VERIFICATION_COUNT: ${verifiedBy.length}');
        hasVerificationCount = true;
      } else if (lastModified != null && line.startsWith('LAST_MODIFIED: ')) {
        newLines.add('LAST_MODIFIED: $lastModified');
        hasLastModified = true;
      } else {
        newLines.add(line);
      }
    }

    // Find insertion point - should be after header fields, before description
    // Report format: Title, empty line, header fields, empty line, description
    // We want to insert just before the SECOND empty line (the one before description)
    int insertIndex = newLines.length;
    int emptyLineCount = 0;
    for (int i = 0; i < newLines.length; i++) {
      if (newLines[i].trim().isEmpty && i > 0 && !newLines[i - 1].startsWith('-->')) {
        emptyLineCount++;
        if (emptyLineCount == 2) {
          // Found the empty line before description - insert before it
          insertIndex = i;
          break;
        }
      }
    }

    // Add missing fields
    final toInsert = <String>[];
    if (verifiedBy != null && !hasVerifiedBy && verifiedBy.isNotEmpty) {
      toInsert.add('VERIFIED_BY: ${verifiedBy.join(', ')}');
    }
    if (verifiedBy != null && !hasVerificationCount && verifiedBy.isNotEmpty) {
      toInsert.add('VERIFICATION_COUNT: ${verifiedBy.length}');
    }
    if (lastModified != null && !hasLastModified) {
      toInsert.add('LAST_MODIFIED: $lastModified');
    }

    if (toInsert.isNotEmpty) {
      newLines.insertAll(insertIndex, toInsert);
    }

    return newLines.join('\n');
  }

  /// Parse alert datetime from CREATED field
  DateTime _parseAlertDateTime(String dateStr) {
    // Format: "YYYY-MM-DD HH:MM_ss" or "YYYY-MM-DD HH:MM:ss"
    try {
      final normalized = dateStr.replaceFirst('_', ':');
      final parts = normalized.split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].split('-');
        final timeParts = parts[1].split(':');
        if (dateParts.length >= 3 && timeParts.length >= 2) {
          return DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
            timeParts.length > 2 ? int.parse(timeParts[2]) : 0,
          );
        }
      }
    } catch (_) {}
    return DateTime(2000);
  }

}
