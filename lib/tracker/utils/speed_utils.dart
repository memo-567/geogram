import 'dart:math' as math;

import '../models/tracker_path.dart';

/// Utilities for calculating filtered speed values
class SpeedUtils {
  /// Maximum reasonable speed in m/s (432 km/h - fastest trains)
  static const double maxReasonableSpeedMps = 120.0;

  /// Maximum GPS accuracy to consider point valid (meters)
  static const double maxAccuracyMeters = 50.0;

  /// Percentile to use for max speed (0.0 - 1.0)
  static const double maxSpeedPercentile = 0.95;

  /// Calculate filtered max speed from a list of points
  /// Returns null if not enough valid data
  static double? calculateFilteredMaxSpeed(
    List<TrackerPoint> points, {
    int? startIndex,
    int? endIndex,
  }) {
    if (points.length < 2) return null;

    final start = startIndex ?? 0;
    final end = endIndex ?? points.length - 1;
    if (end <= start) return null;

    final speeds = <double>[];

    for (var i = start + 1; i <= end && i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // Skip if either point has poor accuracy
      if ((prev.accuracy ?? 0) > maxAccuracyMeters ||
          (curr.accuracy ?? 0) > maxAccuracyMeters) {
        continue;
      }

      final speed = calculateSpeed(prev, curr);
      if (speed != null && speed > 0 && speed <= maxReasonableSpeedMps) {
        speeds.add(speed);
      }
    }

    if (speeds.isEmpty) return null;

    // Return 95th percentile
    return _percentile(speeds, maxSpeedPercentile);
  }

  /// Calculate speed between two points in m/s
  /// Returns capped speed or null if invalid
  static double? calculateSpeed(TrackerPoint start, TrackerPoint end) {
    // Prefer GPS-reported speed if available and reasonable
    if (end.speed != null &&
        end.speed! > 0 &&
        end.speed! <= maxReasonableSpeedMps) {
      return end.speed;
    }

    final distance = haversineDistance(
      start.lat,
      start.lon,
      end.lat,
      end.lon,
    );

    final startTime = start.timestampDateTime;
    final endTime = end.timestampDateTime;
    final seconds = endTime.difference(startTime).inMilliseconds / 1000.0;

    if (seconds <= 0) return null;

    final speed = distance / seconds;

    // Cap unreasonable speeds
    if (speed > maxReasonableSpeedMps) return null;

    return speed;
  }

  /// Haversine distance between two points in meters
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Calculate percentile value from a list of values
  static double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    if (values.length == 1) return values[0];

    final sorted = List<double>.from(values)..sort();
    final index = (sorted.length - 1) * percentile;
    final lower = index.floor();
    final upper = index.ceil();

    if (lower == upper) return sorted[lower];

    // Linear interpolation
    final fraction = index - lower;
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
  }
}
