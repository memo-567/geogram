import 'dart:math';

/// Internet station model
class Station {
  String url;
  String name;
  String? callsign; // Station's X3 callsign (from API)
  String? description; // Station description from API
  String status; // 'preferred', 'backup', 'available'
  bool isConnected;
  int? latency; // in milliseconds
  DateTime? lastChecked;
  double? latitude; // Station disclosed location
  double? longitude; // Station disclosed location
  String? location; // Human-readable location (e.g., "New York, USA")
  int? connectedDevices; // Number of connected devices (cached)

  Station({
    required this.url,
    required this.name,
    this.callsign,
    this.description,
    this.status = 'available',
    this.isConnected = false,
    this.latency,
    this.lastChecked,
    this.latitude,
    this.longitude,
    this.location,
    this.connectedDevices,
  });

  /// Create a Station from JSON map
  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      url: json['url'] as String,
      name: json['name'] as String,
      callsign: json['callsign'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'available',
      isConnected: json['isConnected'] as bool? ?? false,
      latency: json['latency'] as int?,
      lastChecked: json['lastChecked'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastChecked'] as int)
          : null,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      location: json['location'] as String?,
      connectedDevices: json['connectedDevices'] as int?,
    );
  }

  /// Convert Station to JSON map
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'name': name,
      if (callsign != null) 'callsign': callsign,
      if (description != null) 'description': description,
      'status': status,
      'isConnected': isConnected,
      if (latency != null) 'latency': latency,
      if (lastChecked != null) 'lastChecked': lastChecked!.millisecondsSinceEpoch,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (location != null) 'location': location,
      if (connectedDevices != null) 'connectedDevices': connectedDevices,
    };
  }

  /// Create a copy of this station
  Station copyWith({
    String? url,
    String? name,
    String? callsign,
    String? description,
    String? status,
    bool? isConnected,
    int? latency,
    DateTime? lastChecked,
    double? latitude,
    double? longitude,
    String? location,
    int? connectedDevices,
  }) {
    return Station(
      url: url ?? this.url,
      name: name ?? this.name,
      callsign: callsign ?? this.callsign,
      description: description ?? this.description,
      status: status ?? this.status,
      isConnected: isConnected ?? this.isConnected,
      latency: latency ?? this.latency,
      lastChecked: lastChecked ?? this.lastChecked,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      location: location ?? this.location,
      connectedDevices: connectedDevices ?? this.connectedDevices,
    );
  }

  /// Get status display text
  String get statusDisplay {
    switch (status) {
      case 'preferred':
        return 'Preferred';
      case 'backup':
        return 'Backup';
      default:
        return 'Available';
    }
  }

  /// Get connection status text
  String get connectionStatus {
    if (isConnected) {
      return latency != null ? 'Connected (${latency}ms)' : 'Connected';
    }
    return 'Disconnected';
  }

  /// Calculate distance from given coordinates using Haversine formula
  /// Returns distance in kilometers, or null if station or user location is unavailable
  double? calculateDistance(double? userLat, double? userLon) {
    if (latitude == null || longitude == null || userLat == null || userLon == null) {
      return null;
    }

    const double earthRadiusKm = 6371.0;

    final dLat = _degreesToRadians(userLat - latitude!);
    final dLon = _degreesToRadians(userLon - longitude!);

    final lat1 = _degreesToRadians(latitude!);
    final lat2 = _degreesToRadians(userLat);

    final a = (sin(dLat / 2) * sin(dLat / 2)) +
              (sin(dLon / 2) * sin(dLon / 2)) * cos(lat1) * cos(lat2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Get human-readable distance string
  String? getDistanceString(double? userLat, double? userLon) {
    final distance = calculateDistance(userLat, userLon);
    if (distance == null) return null;

    if (distance < 1) {
      return '${(distance * 1000).round()} meters away';
    } else {
      return '${distance.round()} kilometers away';
    }
  }
}
