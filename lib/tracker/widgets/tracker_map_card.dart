import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/map_tile_service.dart' show MapLayerType, MapTileService;

/// A reusable map card widget for the Tracker feature.
///
/// Displays a satellite map with optional markers, polylines, and overlays.
/// Supports auto-fitting to bounds and fullscreen expansion.
///
/// ## Usage
/// ```dart
/// TrackerMapCard(
///   points: [LatLng(40.7128, -74.0060), LatLng(40.7580, -73.9855)],
///   markers: [
///     Marker(
///       point: LatLng(40.7128, -74.0060),
///       child: Icon(Icons.location_on),
///     ),
///   ],
///   onMarkerTap: (index) => showBottomSheet(...),
///   onFullscreen: () => Navigator.push(...),
/// )
/// ```
///
/// See also: /docs/reusable.md for full documentation
class TrackerMapCard extends StatefulWidget {
  /// Points used to calculate map bounds (auto-fit camera to show all points)
  final List<LatLng> points;

  /// Markers to display on the map
  final List<Marker> markers;

  /// Optional polylines to draw on the map (e.g., paths, routes)
  final List<Polyline>? polylines;

  /// Height of the card (default: 260)
  final double height;

  /// Callback when map is tapped (not on a marker)
  final VoidCallback? onTap;

  /// Callback for fullscreen button press
  final VoidCallback? onFullscreen;

  /// Optional overlay widget shown at bottom-left (e.g., city label)
  final Widget? bottomLeftOverlay;

  /// Whether to show transport labels (road names) - useful for short trips
  final bool showTransportLabels;

  /// Padding around bounds when fitting camera
  final EdgeInsets boundsPadding;

  /// Fallback center when no points provided
  final LatLng fallbackCenter;

  /// Fallback zoom when no points provided
  final double fallbackZoom;

  const TrackerMapCard({
    super.key,
    required this.points,
    this.markers = const [],
    this.polylines,
    this.height = 260,
    this.onTap,
    this.onFullscreen,
    this.bottomLeftOverlay,
    this.showTransportLabels = false,
    this.boundsPadding = const EdgeInsets.all(32),
    this.fallbackCenter = const LatLng(0, 0),
    this.fallbackZoom = 14,
  });

  @override
  State<TrackerMapCard> createState() => _TrackerMapCardState();
}

class _TrackerMapCardState extends State<TrackerMapCard> {
  final MapTileService _mapTileService = MapTileService();
  final MapController _mapController = MapController();
  bool _tilesAvailable = true;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Calculate bounding box for all points with padding
  LatLngBounds? _calculateBounds() {
    if (widget.points.isEmpty) return null;
    if (widget.points.length == 1) {
      // Single point: create small bounds around it
      final p = widget.points.first;
      const padding = 0.002; // ~200m
      return LatLngBounds(
        LatLng(p.latitude - padding, p.longitude - padding),
        LatLng(p.latitude + padding, p.longitude + padding),
      );
    }

    double minLat = widget.points.first.latitude;
    double maxLat = widget.points.first.latitude;
    double minLon = widget.points.first.longitude;
    double maxLon = widget.points.first.longitude;

    for (final point in widget.points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    // Add padding
    final latPadding = (maxLat - minLat) * 0.1;
    final lonPadding = (maxLon - minLon) * 0.1;

    return LatLngBounds(
      LatLng(minLat - latPadding, minLon - lonPadding),
      LatLng(maxLat + latPadding, maxLon + lonPadding),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _calculateBounds();
    final center = widget.points.isNotEmpty
        ? widget.points.first
        : widget.fallbackCenter;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: bounds != null
                    ? CameraFit.bounds(
                        bounds: bounds,
                        padding: widget.boundsPadding,
                      )
                    : null,
                initialCenter: bounds == null ? center : widget.fallbackCenter,
                initialZoom: bounds == null ? widget.fallbackZoom : 10,
                minZoom: 1,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: widget.onTap != null ? (_, __) => widget.onTap!() : null,
              ),
              children: [
                // Satellite base layer
                TileLayer(
                  urlTemplate: _mapTileService.getTileUrl(MapLayerType.satellite),
                  userAgentPackageName: 'dev.geogram',
                  subdomains: const [],
                  tileBuilder: (context, tileWidget, tile) => tileWidget,
                  tileProvider: _mapTileService.getTileProvider(MapLayerType.satellite),
                  errorTileCallback: (_, __, ___) {
                    if (_tilesAvailable) {
                      setState(() => _tilesAvailable = false);
                    }
                    if (widget.points.isNotEmpty) {
                      unawaited(
                        _mapTileService.ensureOfflineTiles(
                          lat: widget.points.first.latitude,
                          lng: widget.points.first.longitude,
                        ),
                      );
                    }
                  },
                ),
                // Borders overlay for satellite view
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    1.2, 0, 0, 0, 0,
                    0, 1.2, 0, 0, 0,
                    0, 0, 1.2, 0, 0,
                    0, 0, 0, 0.7, 0,
                  ]),
                  child: TileLayer(
                    urlTemplate: _mapTileService.getBordersUrl(),
                    userAgentPackageName: 'dev.geogram',
                    subdomains: const [],
                    tileProvider: _mapTileService.getBordersProvider(),
                    evictErrorTileStrategy: EvictErrorTileStrategy.none,
                  ),
                ),
                // Labels layer
                TileLayer(
                  urlTemplate: _mapTileService.getLabelsUrl(),
                  userAgentPackageName: 'dev.geogram',
                  subdomains: const [],
                  tileProvider: _mapTileService.getLabelsProvider(),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                ),
                // Transport labels (optional, for short trips)
                if (widget.showTransportLabels)
                  ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.3, 0.3, 0.3, 0, 30,
                      0.3, 0.3, 0.3, 0, 30,
                      0.3, 0.3, 0.3, 0, 30,
                      0, 0, 0, 1.0, 0,
                    ]),
                    child: TileLayer(
                      urlTemplate: _mapTileService.getTransportLabelsUrl(),
                      userAgentPackageName: 'dev.geogram',
                      subdomains: const [],
                      tileProvider: _mapTileService.getTransportLabelsProvider(),
                      evictErrorTileStrategy: EvictErrorTileStrategy.none,
                    ),
                  ),
                // Polylines (paths, routes)
                if (widget.polylines != null && widget.polylines!.isNotEmpty)
                  PolylineLayer(polylines: widget.polylines!),
                // Markers
                if (widget.markers.isNotEmpty)
                  MarkerLayer(markers: widget.markers),
              ],
            ),
            // Bottom-left overlay (e.g., city label)
            if (widget.bottomLeftOverlay != null)
              Positioned(
                bottom: 12,
                left: 12,
                child: widget.bottomLeftOverlay!,
              ),
            // Fullscreen button
            if (widget.onFullscreen != null)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.open_in_full, color: Colors.white),
                  onPressed: widget.onFullscreen,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
              ),
            // Offline tiles warning
            if (!_tilesAvailable)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Offline tiles unavailable',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Helper widget for creating a label overlay on the map
class MapLabelOverlay extends StatelessWidget {
  final String text;

  const MapLabelOverlay({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
