/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Events API endpoints.
 */

import '../api.dart';

/// Event summary (from list)
class EventSummary {
  final String id;
  final String? name;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? organizer;
  final int mediaCount;

  const EventSummary({
    required this.id,
    this.name,
    this.description,
    this.startDate,
    this.endDate,
    this.location,
    this.latitude,
    this.longitude,
    this.organizer,
    this.mediaCount = 0,
  });

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    return EventSummary(
      id: json['id'] as String? ?? json['folder'] as String? ?? '',
      name: json['name'] as String?,
      description: json['description'] as String?,
      startDate: _parseDateTime(json['startDate'] ?? json['start_date']),
      endDate: _parseDateTime(json['endDate'] ?? json['end_date']),
      location: json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      organizer: json['organizer'] as String?,
      mediaCount: json['mediaCount'] as int? ?? json['media_count'] as int? ?? 0,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool get isActive {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  @override
  String toString() => 'EventSummary($id, $name)';
}

/// Event file/folder item
class EventItem {
  final String name;
  final String type; // 'file' or 'folder'
  final String? path;
  final int? size;
  final DateTime? modified;

  const EventItem({
    required this.name,
    required this.type,
    this.path,
    this.size,
    this.modified,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      path: json['path'] as String?,
      size: json['size'] as int?,
      modified: json['modified'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['modified'] as num).toInt() * 1000)
          : null,
    );
  }

  bool get isFolder => type == 'folder';
  bool get isFile => type == 'file';
}

/// Media contributor info
class MediaContributor {
  final String callsign;
  final String? name;
  final int fileCount;
  final String status; // 'approved', 'pending', 'suspended', 'banned'
  final List<MediaFile> files;

  const MediaContributor({
    required this.callsign,
    this.name,
    this.fileCount = 0,
    this.status = 'approved',
    this.files = const [],
  });

  factory MediaContributor.fromJson(Map<String, dynamic> json) {
    return MediaContributor(
      callsign: json['callsign'] as String? ?? '',
      name: json['name'] as String?,
      fileCount: json['fileCount'] as int? ?? json['file_count'] as int? ?? 0,
      status: json['status'] as String? ?? 'approved',
      files: (json['files'] as List?)
              ?.map((e) => MediaFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Media file info
class MediaFile {
  final String name;
  final String path;
  final int? size;
  final String? contentType;
  final DateTime? uploaded;

  const MediaFile({
    required this.name,
    required this.path,
    this.size,
    this.contentType,
    this.uploaded,
  });

  factory MediaFile.fromJson(Map<String, dynamic> json) {
    return MediaFile(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      size: json['size'] as int?,
      contentType: json['contentType'] as String? ?? json['content_type'] as String?,
      uploaded: json['uploaded'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['uploaded'] as num).toInt() * 1000)
          : null,
    );
  }
}

/// Events API endpoints
class EventsApi {
  final GeogramApi _api;

  EventsApi(this._api);

  /// List events with optional year filter
  Future<ApiListResponse<EventSummary>> list(
    String callsign, {
    int? year,
  }) {
    return _api.list<EventSummary>(
      callsign,
      '/api/events',
      queryParams: {
        if (year != null) 'year': year,
      },
      itemFromJson: (json) => EventSummary.fromJson(json as Map<String, dynamic>),
      listKey: 'events',
    );
  }

  /// Get event details
  Future<ApiResponse<EventSummary>> get(String callsign, String eventId) {
    return _api.get<EventSummary>(
      callsign,
      '/api/events/$eventId',
      fromJson: (json) => EventSummary.fromJson(json as Map<String, dynamic>),
    );
  }

  /// List event files and folders
  ///
  /// [path] - Optional path within the event folder
  Future<ApiListResponse<EventItem>> items(
    String callsign,
    String eventId, {
    String? path,
  }) {
    return _api.list<EventItem>(
      callsign,
      '/api/events/$eventId/items',
      queryParams: {
        if (path != null) 'path': path,
      },
      itemFromJson: (json) => EventItem.fromJson(json as Map<String, dynamic>),
      listKey: 'items',
    );
  }

  /// Get event file content
  Future<ApiResponse<dynamic>> getFile(
    String callsign,
    String eventId,
    String filePath,
  ) {
    return _api.get<dynamic>(
      callsign,
      '/api/events/$eventId/files/$filePath',
    );
  }

  /// List media contributors for an event
  Future<ApiListResponse<MediaContributor>> mediaContributors(
    String callsign,
    String eventId,
  ) {
    return _api.list<MediaContributor>(
      callsign,
      '/api/events/$eventId/media',
      itemFromJson: (json) => MediaContributor.fromJson(json as Map<String, dynamic>),
      listKey: 'contributors',
    );
  }

  /// Upload media file to event
  Future<ApiResponse<MediaFile>> uploadMedia(
    String callsign,
    String eventId,
    String contributorCallsign,
    String filename,
    List<int> fileData, {
    String? contentType,
  }) {
    return _api.post<MediaFile>(
      callsign,
      '/api/events/$eventId/media/$contributorCallsign/files/$filename',
      body: fileData,
      headers: {
        if (contentType != null) 'Content-Type': contentType,
      },
      fromJson: (json) => MediaFile.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Approve a media contributor
  Future<ApiResponse<void>> approveContributor(
    String callsign,
    String eventId,
    String contributorCallsign,
  ) {
    return _api.post<void>(
      callsign,
      '/api/events/$eventId/media/$contributorCallsign/approve',
    );
  }

  /// Suspend a media contributor
  Future<ApiResponse<void>> suspendContributor(
    String callsign,
    String eventId,
    String contributorCallsign,
  ) {
    return _api.post<void>(
      callsign,
      '/api/events/$eventId/media/$contributorCallsign/suspend',
    );
  }

  /// Ban a media contributor
  Future<ApiResponse<void>> banContributor(
    String callsign,
    String eventId,
    String contributorCallsign,
  ) {
    return _api.post<void>(
      callsign,
      '/api/events/$eventId/media/$contributorCallsign/ban',
    );
  }
}
