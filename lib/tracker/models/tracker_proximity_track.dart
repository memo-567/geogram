/// Unified proximity tracking model for both devices and places.
/// Stores detection entries organized by year/week with individual track files.

/// Type of proximity target
enum ProximityTargetType { device, place }

/// Source of place data
enum PlaceSource { internal, station, connect }

/// A single proximity detection entry
class ProximityEntry {
  final String timestamp;
  final double lat;
  final double lon;
  final String? endedAt;
  final int? durationSeconds;

  const ProximityEntry({
    required this.timestamp,
    required this.lat,
    required this.lon,
    this.endedAt,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'lat': lat,
        'lon': lon,
        if (endedAt != null) 'ended_at': endedAt,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
      };

  factory ProximityEntry.fromJson(Map<String, dynamic> json) => ProximityEntry(
        timestamp: json['timestamp'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        endedAt: json['ended_at'] as String?,
        durationSeconds: json['duration_seconds'] as int?,
      );

  /// Create a copy with updated fields
  ProximityEntry copyWith({
    String? timestamp,
    double? lat,
    double? lon,
    String? endedAt,
    int? durationSeconds,
  }) =>
      ProximityEntry(
        timestamp: timestamp ?? this.timestamp,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );

  /// Check if this entry is still open (no ended_at)
  bool get isOpen => endedAt == null;

  /// Parse timestamp to DateTime
  DateTime get timestampDateTime => DateTime.parse(timestamp);

  /// Parse endedAt to DateTime (if set)
  DateTime? get endedAtDateTime =>
      endedAt != null ? DateTime.parse(endedAt!) : null;
}

/// Weekly summary statistics for a track
class ProximityWeekSummary {
  final int totalSeconds;
  final int totalEntries;
  final String? firstDetection;
  final String? lastDetection;

  const ProximityWeekSummary({
    required this.totalSeconds,
    required this.totalEntries,
    this.firstDetection,
    this.lastDetection,
  });

  Map<String, dynamic> toJson() => {
        'total_seconds': totalSeconds,
        'total_entries': totalEntries,
        if (firstDetection != null) 'first_detection': firstDetection,
        if (lastDetection != null) 'last_detection': lastDetection,
      };

  factory ProximityWeekSummary.fromJson(Map<String, dynamic> json) =>
      ProximityWeekSummary(
        totalSeconds: json['total_seconds'] as int? ?? 0,
        totalEntries: json['total_entries'] as int? ?? 0,
        firstDetection: json['first_detection'] as String?,
        lastDetection: json['last_detection'] as String?,
      );

  static const empty = ProximityWeekSummary(
    totalSeconds: 0,
    totalEntries: 0,
  );
}

/// Coordinates for a place
class ProximityPlaceCoordinates {
  final double lat;
  final double lon;

  const ProximityPlaceCoordinates({
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
      };

  factory ProximityPlaceCoordinates.fromJson(Map<String, dynamic> json) =>
      ProximityPlaceCoordinates(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );
}

/// A proximity track file for a single device or place.
/// Stored as `{id}-track.json` in the week folder.
class ProximityTrack {
  final String id;
  final ProximityTargetType type;
  final String displayName;

  // Device-specific fields
  final String? npub;
  final String? callsign;

  // Place-specific fields
  final PlaceSource? source;
  final String? placeId;
  final ProximityPlaceCoordinates? coordinates;

  final List<ProximityEntry> entries;
  final ProximityWeekSummary weekSummary;

  const ProximityTrack({
    required this.id,
    required this.type,
    required this.displayName,
    this.npub,
    this.callsign,
    this.source,
    this.placeId,
    this.coordinates,
    this.entries = const [],
    this.weekSummary = ProximityWeekSummary.empty,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'display_name': displayName,
        if (npub != null) 'npub': npub,
        if (callsign != null) 'callsign': callsign,
        if (source != null) 'source': source!.name,
        if (placeId != null) 'place_id': placeId,
        if (coordinates != null) 'coordinates': coordinates!.toJson(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'week_summary': weekSummary.toJson(),
      };

  factory ProximityTrack.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'device';
    final type = ProximityTargetType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ProximityTargetType.device,
    );

    PlaceSource? source;
    if (json['source'] != null) {
      final sourceStr = json['source'] as String;
      source = PlaceSource.values.firstWhere(
        (s) => s.name == sourceStr,
        orElse: () => PlaceSource.internal,
      );
    }

    return ProximityTrack(
      id: json['id'] as String,
      type: type,
      displayName: json['display_name'] as String? ?? json['id'] as String,
      npub: json['npub'] as String?,
      callsign: json['callsign'] as String?,
      source: source,
      placeId: json['place_id'] as String?,
      coordinates: json['coordinates'] != null
          ? ProximityPlaceCoordinates.fromJson(
              json['coordinates'] as Map<String, dynamic>)
          : null,
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => ProximityEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      weekSummary: json['week_summary'] != null
          ? ProximityWeekSummary.fromJson(
              json['week_summary'] as Map<String, dynamic>)
          : ProximityWeekSummary.empty,
    );
  }

  /// Create a copy with updated fields
  ProximityTrack copyWith({
    String? id,
    ProximityTargetType? type,
    String? displayName,
    String? npub,
    String? callsign,
    PlaceSource? source,
    String? placeId,
    ProximityPlaceCoordinates? coordinates,
    List<ProximityEntry>? entries,
    ProximityWeekSummary? weekSummary,
  }) =>
      ProximityTrack(
        id: id ?? this.id,
        type: type ?? this.type,
        displayName: displayName ?? this.displayName,
        npub: npub ?? this.npub,
        callsign: callsign ?? this.callsign,
        source: source ?? this.source,
        placeId: placeId ?? this.placeId,
        coordinates: coordinates ?? this.coordinates,
        entries: entries ?? this.entries,
        weekSummary: weekSummary ?? this.weekSummary,
      );

  /// Generate filename for this track
  String get filename => '$id-track.json';

  /// Create a device track
  factory ProximityTrack.forDevice({
    required String callsign,
    required String displayName,
    String? npub,
  }) =>
      ProximityTrack(
        id: callsign,
        type: ProximityTargetType.device,
        displayName: displayName,
        callsign: callsign,
        npub: npub,
      );

  /// Generate a consistent ID for a place track.
  /// This should be used when looking up or creating place tracks to ensure consistency.
  static String generatePlaceId(String displayName, double lat, double lon) {
    final sanitizedName = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final latStr = lat.toStringAsFixed(2).replaceAll('.', '_');
    final lonStr = lon.toStringAsFixed(2).replaceAll('.', '_').replaceAll('-', 'n');
    return 'place_${sanitizedName}_${latStr}_$lonStr';
  }

  /// Create a place track
  factory ProximityTrack.forPlace({
    required String placeId,
    required String displayName,
    required double lat,
    required double lon,
    required PlaceSource source,
  }) {
    final id = generatePlaceId(displayName, lat, lon);

    return ProximityTrack(
      id: id,
      type: ProximityTargetType.place,
      displayName: displayName,
      source: source,
      placeId: placeId,
      coordinates: ProximityPlaceCoordinates(lat: lat, lon: lon),
    );
  }

  /// Recalculate week summary from entries
  ProximityTrack recalculateSummary() {
    if (entries.isEmpty) {
      return copyWith(weekSummary: ProximityWeekSummary.empty);
    }

    int totalSeconds = 0;
    String? firstDetection;
    String? lastDetection;

    for (final entry in entries) {
      totalSeconds += entry.durationSeconds ?? 0;

      if (firstDetection == null || entry.timestamp.compareTo(firstDetection) < 0) {
        firstDetection = entry.timestamp;
      }

      final endTime = entry.endedAt ?? entry.timestamp;
      if (lastDetection == null || endTime.compareTo(lastDetection) > 0) {
        lastDetection = endTime;
      }
    }

    return copyWith(
      weekSummary: ProximityWeekSummary(
        totalSeconds: totalSeconds,
        totalEntries: entries.length,
        firstDetection: firstDetection,
        lastDetection: lastDetection,
      ),
    );
  }
}

/// Utility to get week number from a date
int getWeekNumber(DateTime date) {
  // ISO week number calculation
  final firstDayOfYear = DateTime(date.year, 1, 1);
  final dayOfYear = date.difference(firstDayOfYear).inDays + 1;
  final weekday = date.weekday;
  final weekNumber = ((dayOfYear - weekday + 10) / 7).floor();

  if (weekNumber < 1) {
    // Last week of previous year
    return getWeekNumber(DateTime(date.year - 1, 12, 31));
  } else if (weekNumber > 52) {
    // Check if it's week 1 of next year
    final dec28 = DateTime(date.year, 12, 28);
    if (date.isAfter(dec28)) {
      return 1;
    }
  }
  return weekNumber;
}

/// Format week folder name (e.g., "W02")
String formatWeekFolder(int week) => 'W${week.toString().padLeft(2, '0')}';
