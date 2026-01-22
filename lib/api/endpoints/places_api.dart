/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Places API endpoints.
 */

import '../api.dart';

/// Place summary (from list)
class PlaceSummary {
  final String id;
  final String? callsign;
  final String? name;
  final String? type;
  final double? latitude;
  final double? longitude;
  final String? location;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hasPhotos;

  const PlaceSummary({
    required this.id,
    this.callsign,
    this.name,
    this.type,
    this.latitude,
    this.longitude,
    this.location,
    this.createdAt,
    this.updatedAt,
    this.hasPhotos = false,
  });

  factory PlaceSummary.fromJson(Map<String, dynamic> json) {
    return PlaceSummary(
      id: json['id'] as String? ?? json['folder'] as String? ?? '',
      callsign: json['callsign'] as String?,
      name: json['name'] as String?,
      type: json['type'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lon'] as num?)?.toDouble(),
      location: json['location'] as String?,
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDateTime(json['updatedAt'] ?? json['updated_at']),
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
  String toString() => 'PlaceSummary($id, $name)';
}

/// Full place details
class PlaceDetails extends PlaceSummary {
  final String? description;
  final String? author;
  final List<String> photos;
  final Map<String, dynamic>? metadata;
  final String? address;
  final String? phone;
  final String? website;
  final Map<String, String>? hours;

  const PlaceDetails({
    required super.id,
    super.callsign,
    super.name,
    super.type,
    super.latitude,
    super.longitude,
    super.location,
    super.createdAt,
    super.updatedAt,
    super.hasPhotos,
    this.description,
    this.author,
    this.photos = const [],
    this.metadata,
    this.address,
    this.phone,
    this.website,
    this.hours,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final summary = PlaceSummary.fromJson(json);
    return PlaceDetails(
      id: summary.id,
      callsign: summary.callsign,
      name: summary.name,
      type: summary.type,
      latitude: summary.latitude,
      longitude: summary.longitude,
      location: summary.location,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      hasPhotos: summary.hasPhotos,
      description: json['description'] as String?,
      author: json['author'] as String?,
      photos: (json['photos'] as List?)?.cast<String>() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      hours: (json['hours'] as Map?)?.cast<String, String>(),
    );
  }
}

/// Places API endpoints
class PlacesApi {
  final GeogramApi _api;

  PlacesApi(this._api);

  /// List places with optional filtering
  ///
  /// [lat], [lon], [radius] - Filter by location (radius in km)
  /// [type] - Filter by place type
  /// [limit] - Maximum number of results
  Future<ApiListResponse<PlaceSummary>> list(
    String callsign, {
    double? lat,
    double? lon,
    double? radius,
    String? type,
    int? limit,
  }) {
    return _api.list<PlaceSummary>(
      callsign,
      '/api/places',
      queryParams: {
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (radius != null) 'radius': radius,
        if (type != null) 'type': type,
        if (limit != null) 'limit': limit,
      },
      itemFromJson: (json) => PlaceSummary.fromJson(json as Map<String, dynamic>),
      listKey: 'places',
    );
  }

  /// Get place details
  ///
  /// [callsign] - The device callsign
  /// [folderName] - The place folder name/ID
  Future<ApiResponse<PlaceDetails>> get(String callsign, String folderName) {
    return _api.get<PlaceDetails>(
      callsign,
      '/api/places/$callsign/$folderName',
      fromJson: (json) => PlaceDetails.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get place file (photo)
  Future<ApiResponse<String>> getFile(
    String callsign,
    String folderName,
    String filePath,
  ) {
    return _api.get<String>(
      callsign,
      '/$callsign/api/places/$folderName/files/$filePath',
      fromJson: (json) {
        if (json is Map) return json['path'] as String? ?? '';
        return json.toString();
      },
    );
  }

  /// Upload a file to a place
  Future<ApiResponse<Map<String, dynamic>>> uploadFile(
    String callsign,
    String folderName,
    String filename,
    List<int> fileData, {
    String? contentType,
  }) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/$callsign/api/places/$folderName/files/$filename',
      body: fileData,
      headers: {
        if (contentType != null) 'Content-Type': contentType,
      },
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }
}
