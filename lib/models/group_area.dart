/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Model representing a geographic area of responsibility
class GroupArea {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String priority;
  final String? notes;

  GroupArea({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    this.priority = 'medium',
    this.notes,
  });

  /// Get coordinates as string
  String get coordinatesString => '$latitude,$longitude';

  /// Check if priority is high
  bool get isHighPriority => priority.toLowerCase() == 'high';

  /// Check if priority is medium
  bool get isMediumPriority => priority.toLowerCase() == 'medium';

  /// Check if priority is low
  bool get isLowPriority => priority.toLowerCase() == 'low';

  /// Parse area from areas.json
  static GroupArea fromJson(Map<String, dynamic> json) {
    final center = json['center'] as Map<String, dynamic>;

    return GroupArea(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      latitude: (center['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (center['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 1.0,
      priority: json['priority'] as String? ?? 'medium',
      notes: json['notes'] as String?,
    );
  }

  /// Export area as JSON
  Map<String, dynamic> toJson() {
    final json = {
      'id': id,
      'name': name,
      'center': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'radius_km': radiusKm,
      'priority': priority,
    };

    if (notes != null && notes!.isNotEmpty) {
      json['notes'] = notes!;
    }

    return json;
  }

  /// Create copy with updated fields
  GroupArea copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? priority,
    String? notes,
  }) {
    return GroupArea(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'GroupArea(id: $id, name: $name, radius: ${radiusKm}km, priority: $priority)';
  }
}
