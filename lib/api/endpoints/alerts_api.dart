/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Alerts API endpoints.
 */

import '../api.dart';

/// Alert status types
enum AlertStatus {
  active,
  resolved,
  expired,
  archived,
}

/// Alert summary (from list)
class AlertSummary {
  final String id;
  final String? callsign;
  final String? title;
  final String? type;
  final String? status;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int points;
  final int verifications;
  final int comments;
  final bool hasPhotos;

  const AlertSummary({
    required this.id,
    this.callsign,
    this.title,
    this.type,
    this.status,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.updatedAt,
    this.points = 0,
    this.verifications = 0,
    this.comments = 0,
    this.hasPhotos = false,
  });

  factory AlertSummary.fromJson(Map<String, dynamic> json) {
    return AlertSummary(
      id: json['id'] as String? ?? json['folder'] as String? ?? '',
      callsign: json['callsign'] as String?,
      title: json['title'] as String?,
      type: json['type'] as String?,
      status: json['status'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lon'] as num?)?.toDouble(),
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDateTime(json['updatedAt'] ?? json['updated_at']),
      points: json['points'] as int? ?? 0,
      verifications: json['verifications'] as int? ?? 0,
      comments: json['comments'] as int? ?? 0,
      hasPhotos: json['hasPhotos'] as bool? ?? json['has_photos'] as bool? ?? false,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  String toString() => 'AlertSummary($id, $title)';
}

/// Full alert details
class AlertDetails extends AlertSummary {
  final String? description;
  final String? author;
  final List<String> photos;
  final Map<String, dynamic>? metadata;

  const AlertDetails({
    required super.id,
    super.callsign,
    super.title,
    super.type,
    super.status,
    super.latitude,
    super.longitude,
    super.createdAt,
    super.updatedAt,
    super.points,
    super.verifications,
    super.comments,
    super.hasPhotos,
    this.description,
    this.author,
    this.photos = const [],
    this.metadata,
  });

  factory AlertDetails.fromJson(Map<String, dynamic> json) {
    final summary = AlertSummary.fromJson(json);
    return AlertDetails(
      id: summary.id,
      callsign: summary.callsign,
      title: summary.title,
      type: summary.type,
      status: summary.status,
      latitude: summary.latitude,
      longitude: summary.longitude,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      points: summary.points,
      verifications: summary.verifications,
      comments: summary.comments,
      hasPhotos: summary.hasPhotos,
      description: json['description'] as String?,
      author: json['author'] as String?,
      photos: (json['photos'] as List?)?.cast<String>() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Alerts API endpoints
class AlertsApi {
  final GeogramApi _api;

  AlertsApi(this._api);

  /// List alerts with optional filtering
  ///
  /// [status] - Filter by status (active, resolved, expired)
  /// [lat], [lon], [radius] - Filter by location (radius in km)
  /// [type] - Filter by alert type
  /// [limit] - Maximum number of results
  Future<ApiListResponse<AlertSummary>> list(
    String callsign, {
    String? status,
    double? lat,
    double? lon,
    double? radius,
    String? type,
    int? limit,
  }) {
    return _api.list<AlertSummary>(
      callsign,
      '/api/alerts',
      queryParams: {
        if (status != null) 'status': status,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radius != null) 'radius': radius,
        if (type != null) 'type': type,
        if (limit != null) 'limit': limit,
      },
      itemFromJson: (json) => AlertSummary.fromJson(json as Map<String, dynamic>),
      listKey: 'alerts',
    );
  }

  /// Get alert details
  ///
  /// [callsign] - The device callsign
  /// [alertId] - The alert folder name/ID
  Future<ApiResponse<AlertDetails>> get(String callsign, String alertId) {
    return _api.get<AlertDetails>(
      callsign,
      '/$callsign/api/alerts/$alertId',
      fromJson: (json) => AlertDetails.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get alert file (photo)
  ///
  /// Returns the file path on success.
  Future<ApiResponse<String>> getFile(
    String callsign,
    String alertId,
    String filePath,
  ) {
    return _api.get<String>(
      callsign,
      '/$callsign/api/alerts/$alertId/files/$filePath',
      fromJson: (json) {
        if (json is Map) return json['path'] as String? ?? '';
        return json.toString();
      },
    );
  }

  /// Upload a file to an alert
  Future<ApiResponse<Map<String, dynamic>>> uploadFile(
    String callsign,
    String alertId,
    String filename,
    List<int> fileData, {
    String? contentType,
  }) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/$callsign/api/alerts/$alertId/files/$filename',
      body: fileData,
      headers: {
        if (contentType != null) 'Content-Type': contentType,
      },
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }
}
