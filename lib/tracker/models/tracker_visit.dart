import 'tracker_visibility.dart';

/// A single visit to a place
class TrackerVisit {
  final String id;
  final String placeId;
  final String placeName;
  final String? placeCategory;
  final PlaceCoordinates placeCoordinates;
  final String checkedInAt;
  final String? checkedOutAt;
  final int? durationSeconds;
  final bool autoDetected;
  final double? detectionAccuracyMeters;
  final String? notes;
  final String? status; // 'checked_in' if currently at place

  const TrackerVisit({
    required this.id,
    required this.placeId,
    required this.placeName,
    this.placeCategory,
    required this.placeCoordinates,
    required this.checkedInAt,
    this.checkedOutAt,
    this.durationSeconds,
    this.autoDetected = true,
    this.detectionAccuracyMeters,
    this.notes,
    this.status,
  });

  DateTime get checkedInAtDateTime {
    try {
      return DateTime.parse(checkedInAt);
    } catch (e) {
      return DateTime.now();
    }
  }

  DateTime? get checkedOutAtDateTime {
    if (checkedOutAt == null) return null;
    try {
      return DateTime.parse(checkedOutAt!);
    } catch (e) {
      return null;
    }
  }

  bool get isCurrentlyCheckedIn => status == 'checked_in' || checkedOutAt == null;

  String get durationFormatted {
    final seconds = durationSeconds ?? 0;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'place_id': placeId,
        'place_name': placeName,
        if (placeCategory != null) 'place_category': placeCategory,
        'place_coordinates': placeCoordinates.toJson(),
        'checked_in_at': checkedInAt,
        if (checkedOutAt != null) 'checked_out_at': checkedOutAt,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        'auto_detected': autoDetected,
        if (detectionAccuracyMeters != null)
          'detection_accuracy_meters': detectionAccuracyMeters,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
      };

  factory TrackerVisit.fromJson(Map<String, dynamic> json) {
    return TrackerVisit(
      id: json['id'] as String,
      placeId: json['place_id'] as String,
      placeName: json['place_name'] as String,
      placeCategory: json['place_category'] as String?,
      placeCoordinates: PlaceCoordinates.fromJson(
          json['place_coordinates'] as Map<String, dynamic>),
      checkedInAt: json['checked_in_at'] as String,
      checkedOutAt: json['checked_out_at'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
      autoDetected: json['auto_detected'] as bool? ?? true,
      detectionAccuracyMeters:
          (json['detection_accuracy_meters'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      status: json['status'] as String?,
    );
  }

  TrackerVisit copyWith({
    String? id,
    String? placeId,
    String? placeName,
    String? placeCategory,
    PlaceCoordinates? placeCoordinates,
    String? checkedInAt,
    String? checkedOutAt,
    int? durationSeconds,
    bool? autoDetected,
    double? detectionAccuracyMeters,
    String? notes,
    String? status,
  }) {
    return TrackerVisit(
      id: id ?? this.id,
      placeId: placeId ?? this.placeId,
      placeName: placeName ?? this.placeName,
      placeCategory: placeCategory ?? this.placeCategory,
      placeCoordinates: placeCoordinates ?? this.placeCoordinates,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      checkedOutAt: checkedOutAt ?? this.checkedOutAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      autoDetected: autoDetected ?? this.autoDetected,
      detectionAccuracyMeters:
          detectionAccuracyMeters ?? this.detectionAccuracyMeters,
      notes: notes ?? this.notes,
      status: status ?? this.status,
    );
  }
}

/// Coordinates for a place
class PlaceCoordinates {
  final double lat;
  final double lon;

  const PlaceCoordinates({
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
      };

  factory PlaceCoordinates.fromJson(Map<String, dynamic> json) {
    return PlaceCoordinates(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}

/// Daily summary of visits
class DailyVisitSummary {
  final int totalVisits;
  final int totalTrackedSeconds;
  final int placesVisited;
  final String? mostTimeAt;

  const DailyVisitSummary({
    this.totalVisits = 0,
    this.totalTrackedSeconds = 0,
    this.placesVisited = 0,
    this.mostTimeAt,
  });

  Map<String, dynamic> toJson() => {
        'total_visits': totalVisits,
        'total_tracked_seconds': totalTrackedSeconds,
        'places_visited': placesVisited,
        if (mostTimeAt != null) 'most_time_at': mostTimeAt,
      };

  factory DailyVisitSummary.fromJson(Map<String, dynamic> json) {
    return DailyVisitSummary(
      totalVisits: json['total_visits'] as int? ?? 0,
      totalTrackedSeconds: json['total_tracked_seconds'] as int? ?? 0,
      placesVisited: json['places_visited'] as int? ?? 0,
      mostTimeAt: json['most_time_at'] as String?,
    );
  }

  factory DailyVisitSummary.calculate(List<TrackerVisit> visits) {
    if (visits.isEmpty) {
      return const DailyVisitSummary();
    }

    final placeTotals = <String, int>{};
    int totalSeconds = 0;

    for (final visit in visits) {
      final seconds = visit.durationSeconds ?? 0;
      totalSeconds += seconds;
      placeTotals[visit.placeId] =
          (placeTotals[visit.placeId] ?? 0) + seconds;
    }

    String? mostTimeAt;
    int maxTime = 0;
    for (final entry in placeTotals.entries) {
      if (entry.value > maxTime) {
        maxTime = entry.value;
        mostTimeAt = entry.key;
      }
    }

    return DailyVisitSummary(
      totalVisits: visits.length,
      totalTrackedSeconds: totalSeconds,
      placesVisited: placeTotals.keys.length,
      mostTimeAt: mostTimeAt,
    );
  }
}

/// Daily visits data file (visits_YYYYMMDD.json)
class DailyVisitsData {
  final String date; // YYYY-MM-DD
  final String ownerCallsign;
  final List<TrackerVisit> visits;
  final DailyVisitSummary? dailySummary;

  const DailyVisitsData({
    required this.date,
    required this.ownerCallsign,
    this.visits = const [],
    this.dailySummary,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'owner_callsign': ownerCallsign,
        'visits': visits.map((v) => v.toJson()).toList(),
        if (dailySummary != null) 'daily_summary': dailySummary!.toJson(),
      };

  factory DailyVisitsData.fromJson(Map<String, dynamic> json) {
    return DailyVisitsData(
      date: json['date'] as String,
      ownerCallsign: json['owner_callsign'] as String,
      visits: (json['visits'] as List<dynamic>?)
              ?.map((v) => TrackerVisit.fromJson(v as Map<String, dynamic>))
              .toList() ??
          const [],
      dailySummary: json['daily_summary'] != null
          ? DailyVisitSummary.fromJson(
              json['daily_summary'] as Map<String, dynamic>)
          : null,
    );
  }

  DailyVisitsData copyWith({
    String? date,
    String? ownerCallsign,
    List<TrackerVisit>? visits,
    DailyVisitSummary? dailySummary,
  }) {
    return DailyVisitsData(
      date: date ?? this.date,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      visits: visits ?? this.visits,
      dailySummary: dailySummary ?? this.dailySummary,
    );
  }

  /// Add a visit and recalculate summary
  DailyVisitsData addVisit(TrackerVisit visit) {
    final newVisits = [...visits, visit];
    return copyWith(
      visits: newVisits,
      dailySummary: DailyVisitSummary.calculate(newVisits),
    );
  }
}

/// Monthly statistics for a place
class MonthlyPlaceStats {
  final int visits;
  final int seconds;
  final int avgSecondsPerVisit;

  const MonthlyPlaceStats({
    this.visits = 0,
    this.seconds = 0,
    this.avgSecondsPerVisit = 0,
  });

  Map<String, dynamic> toJson() => {
        'visits': visits,
        'seconds': seconds,
        'avg_seconds_per_visit': avgSecondsPerVisit,
      };

  factory MonthlyPlaceStats.fromJson(Map<String, dynamic> json) {
    return MonthlyPlaceStats(
      visits: json['visits'] as int? ?? 0,
      seconds: json['seconds'] as int? ?? 0,
      avgSecondsPerVisit: json['avg_seconds_per_visit'] as int? ?? 0,
    );
  }
}

/// Statistics for a single place
class PlaceStats {
  final String placeId;
  final String placeName;
  final String? placeCategory;
  final int totalVisits;
  final int totalSeconds;
  final int avgSecondsPerVisit;
  final double avgVisitsPerWeek;
  final String? firstVisit;
  final String? lastVisit;
  final int? longestVisitSeconds;
  final int? shortestVisitSeconds;
  final Map<String, MonthlyPlaceStats> monthly;
  final Map<String, MonthlyPlaceStats> weekly;

  const PlaceStats({
    required this.placeId,
    required this.placeName,
    this.placeCategory,
    this.totalVisits = 0,
    this.totalSeconds = 0,
    this.avgSecondsPerVisit = 0,
    this.avgVisitsPerWeek = 0,
    this.firstVisit,
    this.lastVisit,
    this.longestVisitSeconds,
    this.shortestVisitSeconds,
    this.monthly = const {},
    this.weekly = const {},
  });

  Map<String, dynamic> toJson() => {
        'place_id': placeId,
        'place_name': placeName,
        if (placeCategory != null) 'place_category': placeCategory,
        'stats': {
          'total_visits': totalVisits,
          'total_seconds': totalSeconds,
          'avg_seconds_per_visit': avgSecondsPerVisit,
          'avg_visits_per_week': avgVisitsPerWeek,
          if (firstVisit != null) 'first_visit': firstVisit,
          if (lastVisit != null) 'last_visit': lastVisit,
          if (longestVisitSeconds != null)
            'longest_visit_seconds': longestVisitSeconds,
          if (shortestVisitSeconds != null)
            'shortest_visit_seconds': shortestVisitSeconds,
        },
        'monthly': monthly.map((k, v) => MapEntry(k, v.toJson())),
        'weekly': weekly.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory PlaceStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    return PlaceStats(
      placeId: json['place_id'] as String,
      placeName: json['place_name'] as String,
      placeCategory: json['place_category'] as String?,
      totalVisits: stats['total_visits'] as int? ?? 0,
      totalSeconds: stats['total_seconds'] as int? ?? 0,
      avgSecondsPerVisit: stats['avg_seconds_per_visit'] as int? ?? 0,
      avgVisitsPerWeek: (stats['avg_visits_per_week'] as num?)?.toDouble() ?? 0,
      firstVisit: stats['first_visit'] as String?,
      lastVisit: stats['last_visit'] as String?,
      longestVisitSeconds: stats['longest_visit_seconds'] as int?,
      shortestVisitSeconds: stats['shortest_visit_seconds'] as int?,
      monthly: (json['monthly'] as Map<String, dynamic>?)?.map((k, v) =>
              MapEntry(
                  k, MonthlyPlaceStats.fromJson(v as Map<String, dynamic>))) ??
          const {},
      weekly: (json['weekly'] as Map<String, dynamic>?)?.map((k, v) =>
              MapEntry(
                  k, MonthlyPlaceStats.fromJson(v as Map<String, dynamic>))) ??
          const {},
    );
  }
}

/// Overall place statistics (stats.json)
class PlaceStatsData {
  final List<PlaceStats> places;
  final String updatedAt;
  final int totalPlacesTracked;
  final String? trackingSince;
  final TrackerVisibility? visibility;

  const PlaceStatsData({
    this.places = const [],
    required this.updatedAt,
    this.totalPlacesTracked = 0,
    this.trackingSince,
    this.visibility,
  });

  Map<String, dynamic> toJson() => {
        'places': places.map((p) => p.toJson()).toList(),
        'updated_at': updatedAt,
        'total_places_tracked': totalPlacesTracked,
        if (trackingSince != null) 'tracking_since': trackingSince,
        if (visibility != null) 'visibility': visibility!.toJson(),
      };

  factory PlaceStatsData.fromJson(Map<String, dynamic> json) {
    return PlaceStatsData(
      places: (json['places'] as List<dynamic>?)
              ?.map((p) => PlaceStats.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      updatedAt: json['updated_at'] as String,
      totalPlacesTracked: json['total_places_tracked'] as int? ?? 0,
      trackingSince: json['tracking_since'] as String?,
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
    );
  }
}
