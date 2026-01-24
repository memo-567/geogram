/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Geometry utilities for distance calculations.
 * Uses the Haversine formula for accurate earth distance calculations.
 */

import 'dart:math' as math;

/// Geometry utilities for distance calculations between coordinates.
class GeometryUtils {
  /// Calculate the distance between two coordinates in kilometers
  /// using the Haversine formula.
  ///
  /// [lat1], [lon1] - First coordinate (latitude, longitude in degrees)
  /// [lat2], [lon2] - Second coordinate (latitude, longitude in degrees)
  ///
  /// Returns the distance in kilometers.
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
