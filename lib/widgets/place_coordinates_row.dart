/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/place.dart';

/// A reusable widget for displaying place coordinates with action buttons.
/// Used in place_detail_page.dart and places_browser_page.dart.
class PlaceCoordinatesRow extends StatelessWidget {
  final Place place;
  final LatLng? userLocation;
  final bool showNavigateButton;
  final VoidCallback onCopy;
  final VoidCallback onViewMap;
  final VoidCallback? onNavigate;
  final String Function(String) t;

  const PlaceCoordinatesRow({
    super.key,
    required this.place,
    this.userLocation,
    this.showNavigateButton = false,
    required this.onCopy,
    required this.onViewMap,
    this.onNavigate,
    required this.t,
  });

  String _formatDistance(double distanceKm) {
    return distanceKm < 1
        ? '${(distanceKm * 1000).toStringAsFixed(0)} m'
        : '${distanceKm.toStringAsFixed(1)} km';
  }

  double? _calculateDistance() {
    if (userLocation == null) return null;
    const Distance distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      userLocation!,
      LatLng(place.latitude, place.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final distance = _calculateDistance();
    String coordsText = place.coordinatesString;
    if (distance != null) {
      coordsText = '${place.coordinatesString} (${_formatDistance(distance)})';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t('coordinates'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
                tooltip: t('copy_coordinates'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.map, size: 18),
                onPressed: onViewMap,
                tooltip: t('see_in_map'),
                visualDensity: VisualDensity.compact,
              ),
              if (showNavigateButton && onNavigate != null)
                IconButton(
                  icon: const Icon(Icons.navigation, size: 18),
                  onPressed: onNavigate,
                  tooltip: t('open_in_navigator'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          SelectableText(
            coordsText,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
