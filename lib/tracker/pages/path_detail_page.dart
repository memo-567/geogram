import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';
import '../../services/map_tile_service.dart' show MapLayerType, MapTileService;
import '../../services/log_service.dart';

/// Detail page showing a recorded path with stats and a speed heatmap.
class PathDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final TrackerPath path;
  final int year;

  const PathDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.path,
    required this.year,
  });

  @override
  State<PathDetailPage> createState() => _PathDetailPageState();
}

class _PathDetailPageState extends State<PathDetailPage> {
  final MapTileService _mapTileService = MapTileService();
  final MapController _mapController = MapController();

  TrackerPath? _path;
  TrackerPathPoints? _points;
  List<Polyline> _speedSegments = [];
  bool _loading = true;

  double _totalDistanceMeters = 0;
  Duration _duration = Duration.zero;
  double? _avgSpeedMps;
  double? _maxSpeedMps;
  double? _elevationGainMeters;
  double? _elevationLossMeters;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      await _mapTileService.initialize();

      _path = await widget.service.getPath(
        widget.path.id,
        year: widget.year,
      );
      _path ??= widget.path;

      _points = await widget.service.getPathPoints(
        widget.path.id,
        year: widget.year,
      );

      _calculateStats();
      _buildSpeedSegments();
    } catch (e) {
      LogService().log('PathDetailPage: Failed to load path details: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      if (_points != null && _points!.points.length > 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fitBoundsToPath();
        });
      }
    }
  }

  void _calculateStats() {
    final path = _path;
    final points = _points?.points ?? const <TrackerPoint>[];

    _totalDistanceMeters = path?.totalDistanceMeters ?? 0;
    if (_totalDistanceMeters <= 0 && points.length > 1) {
      _totalDistanceMeters = _points!.calculateTotalDistance();
    }

    final start = path?.startedAtDateTime;
    final end = path?.endedAtDateTime ?? DateTime.now();
    if (start != null) {
      _duration = end.difference(start);
    }

    final durationSeconds = _duration.inSeconds;
    _avgSpeedMps = durationSeconds > 0
        ? _totalDistanceMeters / durationSeconds
        : null;

    final elevationTotals = _calculateElevation(points);
    _elevationGainMeters = elevationTotals.$1;
    _elevationLossMeters = elevationTotals.$2;
  }

  void _buildSpeedSegments() {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.length < 2) {
      _speedSegments = [];
      _maxSpeedMps = null;
      return;
    }

    final segmentSpeeds = <double>[];
    for (var i = 1; i < points.length; i++) {
      final speed = _resolveSegmentSpeed(points[i - 1], points[i]);
      segmentSpeeds.add(speed);
    }

    _maxSpeedMps = segmentSpeeds.isNotEmpty
        ? segmentSpeeds.reduce(math.max)
        : null;

    final maxSpeed = _maxSpeedMps ?? 1;
    final segments = <Polyline>[];
    for (var i = 1; i < points.length; i++) {
      final p1 = points[i - 1];
      final p2 = points[i];
      final speed = segmentSpeeds[i - 1];
      final color = _speedColor(speed, maxSpeed);

      segments.add(
        Polyline(
          points: [
            LatLng(p1.lat, p1.lon),
            LatLng(p2.lat, p2.lon),
          ],
          strokeWidth: 5,
          color: color,
        ),
      );
    }

    _speedSegments = segments;
  }

  double _resolveSegmentSpeed(TrackerPoint start, TrackerPoint end) {
    if (end.speed != null) return end.speed!;
    if (start.speed != null) return start.speed!;

    final distance = _haversineDistance(
      start.lat,
      start.lon,
      end.lat,
      end.lon,
    );
    final startTime = start.timestampDateTime;
    final endTime = end.timestampDateTime;
    final seconds = endTime.difference(startTime).inSeconds;
    if (seconds <= 0) return 0;
    return distance / seconds;
  }

  (double?, double?) _calculateElevation(List<TrackerPoint> points) {
    double gain = 0;
    double loss = 0;
    double? previous;

    for (final point in points) {
      final altitude = point.altitude;
      if (altitude == null) continue;
      if (previous != null) {
        final delta = altitude - previous;
        if (delta > 0) {
          gain += delta;
        } else if (delta < 0) {
          loss += -delta;
        }
      }
      previous = altitude;
    }

    return (gain > 0 ? gain : null, loss > 0 ? loss : null);
  }

  void _fitBoundsToPath() {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.isEmpty) return;

    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLon = points.first.lon;
    var maxLon = points.first.lon;

    for (final point in points) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }

    final latPadding = math.max((maxLat - minLat) * 0.15, 0.002);
    final lonPadding = math.max((maxLon - minLon) * 0.15, 0.002);

    final bounds = LatLngBounds(
      LatLng(minLat - latPadding, minLon - lonPadding),
      LatLng(maxLat + latPadding, maxLon + lonPadding),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(32),
      ),
    );
  }

  Color _speedColor(double speed, double maxSpeed) {
    if (maxSpeed <= 0) return Colors.blue;
    final ratio = (speed / maxSpeed).clamp(0.0, 1.0);
    if (ratio <= 0.5) {
      return Color.lerp(Colors.blue, Colors.green, ratio / 0.5) ?? Colors.blue;
    }
    return Color.lerp(Colors.green, Colors.red, (ratio - 0.5) / 0.5) ?? Colors.red;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
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

  double _toRadians(double degrees) => degrees * math.pi / 180;

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds <= 0) return '-';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${seconds}s';
  }

  String _formatSpeed(double? metersPerSecond) {
    if (metersPerSecond == null || metersPerSecond <= 0) return '-';
    final kmh = metersPerSecond * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  @override
  Widget build(BuildContext context) {
    final path = _path ?? widget.path;

    return Scaffold(
      appBar: AppBar(
        title: Text(path.title ?? path.id),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(path),
    );
  }

  Widget _buildContent(TrackerPath path) {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.isEmpty) {
      return Center(
        child: Text(widget.i18n.t('tracker_no_path_points')),
      );
    }

    final pathType = TrackerPathType.fromTags(path.tags);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildMapCard(points),
        const SizedBox(height: 16),
        _buildHighlightsCard(pathType),
        const SizedBox(height: 16),
        _buildMetadataCard(path),
      ],
    );
  }

  Widget _buildMapCard(List<TrackerPoint> points) {
    final start = points.first;
    final end = points.last;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(start.lat, start.lon),
                initialZoom: 14,
                minZoom: 1,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _mapTileService.getTileUrl(MapLayerType.satellite),
                  userAgentPackageName: 'dev.geogram',
                  subdomains: const [],
                  tileProvider: _mapTileService.getTileProvider(MapLayerType.satellite),
                ),
                TileLayer(
                  urlTemplate: _mapTileService.getLabelsUrl(),
                  userAgentPackageName: 'dev.geogram',
                  subdomains: const [],
                  tileProvider: _mapTileService.getLabelsProvider(),
                ),
                Opacity(
                  opacity: 0.6,
                  child: TileLayer(
                    urlTemplate: _mapTileService.getTransportLabelsUrl(),
                    userAgentPackageName: 'dev.geogram',
                    subdomains: const [],
                    tileProvider: _mapTileService.getTransportLabelsProvider(),
                  ),
                ),
                if (_speedSegments.isNotEmpty)
                  PolylineLayer(
                    polylines: _speedSegments,
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(start.lat, start.lon),
                      width: 28,
                      height: 28,
                      child: const Icon(Icons.trip_origin, color: Colors.green),
                    ),
                    Marker(
                      point: LatLng(end.lat, end.lon),
                      width: 28,
                      height: 28,
                      child: const Icon(Icons.flag, color: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.i18n.t('tracker_speed_heatmap'),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightsCard(TrackerPathType? pathType) {
    final pointsCount = _points?.points.length ?? 0;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(pathType?.icon ?? Icons.route),
                const SizedBox(width: 8),
                Text(
                  widget.i18n.t('tracker_highlights'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatChip(
                  widget.i18n.t('tracker_distance'),
                  _formatDistance(_totalDistanceMeters),
                ),
                _buildStatChip(
                  widget.i18n.t('tracker_duration'),
                  _formatDuration(_duration),
                ),
                _buildStatChip(
                  widget.i18n.t('tracker_avg_speed'),
                  _formatSpeed(_avgSpeedMps),
                ),
                _buildStatChip(
                  widget.i18n.t('tracker_max_speed'),
                  _formatSpeed(_maxSpeedMps),
                ),
                _buildStatChip(
                  widget.i18n.t('tracker_points'),
                  pointsCount.toString(),
                ),
                if (_elevationGainMeters != null)
                  _buildStatChip(
                    widget.i18n.t('tracker_elevation_gain'),
                    '${_elevationGainMeters!.toStringAsFixed(0)} m',
                  ),
                if (_elevationLossMeters != null)
                  _buildStatChip(
                    widget.i18n.t('tracker_elevation_loss'),
                    '${_elevationLossMeters!.toStringAsFixed(0)} m',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataCard(TrackerPath path) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_activity_details'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildMetaRow(
              widget.i18n.t('tracker_started'),
              path.startedAtDateTime.toLocal().toString(),
            ),
            if (path.endedAtDateTime != null)
              _buildMetaRow(
                widget.i18n.t('tracker_ended'),
                path.endedAtDateTime!.toLocal().toString(),
              ),
            if (path.description != null && path.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(path.description!.trim()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
