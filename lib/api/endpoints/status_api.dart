/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Status and device info API endpoints.
 */

import '../api.dart';

/// Device status information
class DeviceStatus {
  final String? callsign;
  final String? name;
  final String? service;
  final String? version;
  final String? description;
  final String? location;
  final double? latitude;
  final double? longitude;
  final int? connectedDevices;

  const DeviceStatus({
    this.callsign,
    this.name,
    this.service,
    this.version,
    this.description,
    this.location,
    this.latitude,
    this.longitude,
    this.connectedDevices,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    String? location;
    double? lat;
    double? lon;

    if (json['location'] is Map) {
      final loc = json['location'] as Map<String, dynamic>;
      final city = loc['city'] as String?;
      final country = loc['country'] as String?;
      if (city != null && country != null) {
        location = '$city, $country';
      }
      lat = (loc['latitude'] as num?)?.toDouble();
      lon = (loc['longitude'] as num?)?.toDouble();
    }

    return DeviceStatus(
      callsign: json['callsign'] as String? ?? json['stationCallsign'] as String?,
      name: json['name'] as String?,
      service: json['service'] as String?,
      version: json['version'] as String?,
      description: json['description'] as String?,
      location: location,
      latitude: lat,
      longitude: lon,
      connectedDevices: json['connected_devices'] as int?,
    );
  }

  bool get isStation => service == 'Geogram Station Server' ||
                        (callsign?.toUpperCase().startsWith('X3') ?? false);

  @override
  String toString() => 'DeviceStatus($callsign, $service)';
}

/// GeoIP location information
class GeoIpInfo {
  final String? ip;
  final String? country;
  final String? countryCode;
  final String? city;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String? timezone;

  const GeoIpInfo({
    this.ip,
    this.country,
    this.countryCode,
    this.city,
    this.region,
    this.latitude,
    this.longitude,
    this.timezone,
  });

  factory GeoIpInfo.fromJson(Map<String, dynamic> json) {
    return GeoIpInfo(
      ip: json['ip'] as String?,
      country: json['country'] as String?,
      countryCode: json['country_code'] as String? ?? json['countryCode'] as String?,
      city: json['city'] as String?,
      region: json['region'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lon'] as num?)?.toDouble(),
      timezone: json['timezone'] as String?,
    );
  }

  String get displayLocation {
    final parts = <String>[];
    if (city != null) parts.add(city!);
    if (country != null) parts.add(country!);
    return parts.join(', ');
  }

  @override
  String toString() => 'GeoIpInfo($displayLocation)';
}

/// Status API endpoints
class StatusApi {
  final GeogramApi _api;

  StatusApi(this._api);

  /// Get device status
  ///
  /// Returns status information including callsign, version, location, etc.
  Future<ApiResponse<DeviceStatus>> get(String callsign) {
    return _api.get<DeviceStatus>(
      callsign,
      '/api/status',
      fromJson: (json) => DeviceStatus.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get GeoIP location for the requesting client
  ///
  /// The station uses its local MMDB database to resolve the client's IP.
  Future<ApiResponse<GeoIpInfo>> geoip(String callsign) {
    return _api.get<GeoIpInfo>(
      callsign,
      '/api/geoip',
      fromJson: (json) => GeoIpInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get list of connected clients (station only)
  Future<ApiResponse<List<Map<String, dynamic>>>> clients(String callsign) {
    return _api.get<List<Map<String, dynamic>>>(
      callsign,
      '/api/clients',
      fromJson: (json) => (json as List).cast<Map<String, dynamic>>(),
    );
  }
}
