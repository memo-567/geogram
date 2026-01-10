import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/tracker_models.dart';
import '../services/path_recording_service.dart';
import '../services/tracker_service.dart';
import '../utils/speed_utils.dart';
import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../../services/map_tile_service.dart' show MapLayerType, MapTileService;
import '../../services/location_provider_service.dart';

/// Fullscreen map view for a path, with live updates when recording.
class PathMapFullscreenPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final TrackerPath path;
  final int year;
  final PathRecordingService? recordingService;

  const PathMapFullscreenPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.path,
    required this.year,
    this.recordingService,
  });

  @override
  State<PathMapFullscreenPage> createState() => _PathMapFullscreenPageState();
}

class _PathMapFullscreenPageState extends State<PathMapFullscreenPage> {
  final MapTileService _mapTileService = MapTileService();
  final MapController _mapController = MapController();

  TrackerPath? _path;
  TrackerPathPoints? _points;
  TrackerExpenses? _expenses;
  List<Polyline> _speedSegments = [];
  bool _loading = true;
  bool _tilesAvailable = true;

  double _totalDistanceMeters = 0;
  Duration _duration = Duration.zero;
  double? _avgSpeedMps;
  double _currentZoom = 10;

  Timer? _refreshTimer;
  LockedPosition? _lastLivePosition;
  int? _lastPointCount;
  bool? _lastPausedState;

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.recordingService?.addListener(_onRecordingChanged);
  }

  @override
  void dispose() {
    widget.recordingService?.removeListener(_onRecordingChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onRecordingChanged() {
    final activeId = widget.recordingService?.activePathId;
    if (activeId == null || activeId != (_path ?? widget.path).id) {
      return;
    }
    final pointCount = widget.recordingService?.pointCount;
    final isPaused = widget.recordingService?.isPaused;
    final latestPosition = widget.recordingService?.lastPosition;
    final positionChanged = _hasPositionChanged(latestPosition);
    final stateChanged =
        pointCount != _lastPointCount || isPaused != _lastPausedState;
    if (!positionChanged && !stateChanged) {
      return;
    }
    _lastPointCount = pointCount;
    _lastPausedState = isPaused;
    _lastLivePosition = latestPosition;
    if (_refreshTimer?.isActive ?? false) return;
    _refreshTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _loadData();
      }
    });
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

      _expenses = await widget.service.getPathExpenses(
        widget.path.id,
        year: widget.year,
      );

      _calculateStats();
      _buildSpeedSegments();
    } catch (e) {
      LogService().log('PathMapFullscreenPage: Failed to load path details: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      // Note: Map bounds are now set via initialCameraFit in build method
      // so no need to call _fitBoundsToPath here
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
  }

  void _buildSpeedSegments() {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.length < 2) {
      _speedSegments = [];
      return;
    }

    final segmentSpeeds = <double>[];
    for (var i = 1; i < points.length; i++) {
      final speed = _resolveSegmentSpeed(points[i - 1], points[i]);
      segmentSpeeds.add(speed);
    }

    final maxSpeed = segmentSpeeds.isNotEmpty
        ? segmentSpeeds.reduce(math.max).toDouble()
        : 1.0;
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
          strokeWidth: 3,
          color: color.withValues(alpha: 0.85),
          borderStrokeWidth: 1,
          borderColor: Colors.black38,
        ),
      );
    }

    _speedSegments = segments;
  }

  double _resolveSegmentSpeed(TrackerPoint start, TrackerPoint end) {
    const maxSpeed = SpeedUtils.maxReasonableSpeedMps;

    // Prefer GPS-reported speed if available and reasonable
    if (end.speed != null && end.speed! <= maxSpeed) return end.speed!;
    if (start.speed != null && start.speed! <= maxSpeed) return start.speed!;

    final distance = _haversineDistance(
      start.lat,
      start.lon,
      end.lat,
      end.lon,
    );
    final startTime = start.timestampDateTime;
    final endTime = end.timestampDateTime;
    final millis = endTime.difference(startTime).inMilliseconds;
    if (millis <= 0) return 0;
    final speed = distance / (millis / 1000.0);

    // Cap unreasonable speeds (GPS errors)
    return speed > maxSpeed ? 0 : speed;
  }

  /// Calculate bounds for the path with padding
  LatLngBounds? _calculatePathBounds(List<TrackerPoint> points) {
    if (points.isEmpty) return null;

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

    return LatLngBounds(
      LatLng(minLat - latPadding, minLon - lonPadding),
      LatLng(maxLat + latPadding, maxLon + lonPadding),
    );
  }

  void _fitBoundsToPath() {
    final points = _points?.points ?? const <TrackerPoint>[];
    final bounds = _calculatePathBounds(points);
    if (bounds == null) return;

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
          : _buildMapContent(),
    );
  }

  Widget _buildMapContent() {
    final points = _points?.points ?? const <TrackerPoint>[];
    final isActive =
        widget.recordingService?.activePathId == (_path ?? widget.path).id;
    final isPaused = widget.recordingService?.isPaused ?? false;
    if (points.isEmpty && !isActive) {
      return Center(
        child: Text(widget.i18n.t('tracker_no_path_points')),
      );
    }

    final start = points.isNotEmpty ? points.first : null;
    final end = points.isNotEmpty ? points.last : null;
    final fallbackPosition = widget.recordingService?.lastPosition;
    final fallbackCenter = fallbackPosition != null
        ? LatLng(fallbackPosition.latitude, fallbackPosition.longitude)
        : const LatLng(0, 0);

    // Calculate bounds upfront for initialCameraFit
    final pathBounds = _calculatePathBounds(points);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            // Use initialCameraFit if we have bounds, otherwise fall back to center/zoom
            initialCameraFit: pathBounds != null
                ? CameraFit.bounds(
                    bounds: pathBounds,
                    padding: const EdgeInsets.all(32),
                  )
                : null,
            initialCenter: pathBounds == null && start != null
                ? LatLng(start.lat, start.lon)
                : fallbackCenter,
            initialZoom: pathBounds == null ? 14 : 10,
            minZoom: 1,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onPositionChanged: (position, hasGesture) {
              if (position.zoom != null && position.zoom != _currentZoom) {
                setState(() => _currentZoom = position.zoom!);
              }
            },
          ),
          children: [
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
              ),
            ),
            TileLayer(
              urlTemplate: _mapTileService.getLabelsUrl(),
              userAgentPackageName: 'dev.geogram',
              subdomains: const [],
              tileProvider: _mapTileService.getLabelsProvider(),
            ),
            // Only show roads/transport when zoomed in (< 30km radius visible)
            // Zoom 12+ shows roughly 30km or less
            if (_currentZoom >= 12)
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
                ),
              ),
            if (_speedSegments.isNotEmpty)
              PolylineLayer(
                polylines: _speedSegments,
              ),
            MarkerLayer(
              markers: [
                if (start != null)
                  Marker(
                    point: LatLng(start.lat, start.lon),
                    width: 28,
                    height: 28,
                    child: const Icon(Icons.trip_origin, color: Colors.green),
                  ),
                if (end != null)
                  Marker(
                    point: LatLng(end.lat, end.lon),
                    width: 28,
                    height: 28,
                    child: const Icon(Icons.flag, color: Colors.red),
                  ),
                // Expense markers
                ...(_expenses?.expenses ?? [])
                    .where((e) => e.lat != null && e.lon != null)
                    .map((expense) => Marker(
                          point: LatLng(expense.lat!, expense.lon!),
                          width: 32,
                          height: 32,
                          child: _buildExpenseMarker(expense.type),
                        )),
              ],
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _buildBottomBar(),
        ),
        if (isActive)
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: _buildRecordingControls(isPaused),
          ),
        if (!_tilesAvailable)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.i18n.t('tracker_offline_tiles'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingControls(bool isPaused) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: isPaused
                ? () async {
                    final resumed =
                        await widget.recordingService?.resumeRecording();
                    if (resumed == true && mounted) {
                      _loadData();
                    }
                  }
                : () async {
                    final paused =
                        await widget.recordingService?.pauseRecording();
                    if (paused == true && mounted) {
                      _loadData();
                    }
                  },
            icon: Icon(
              isPaused ? Icons.play_arrow : Icons.pause,
              color: Colors.white,
            ),
            label: Text(
              widget.i18n.t(
                isPaused ? 'tracker_resume_path' : 'tracker_pause_path',
              ),
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          FilledButton.icon(
            onPressed: _confirmStopRecording,
            icon: const Icon(Icons.stop),
            label: Text(
              widget.i18n.t('tracker_stop_path'),
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStopRecording() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('tracker_confirm_stop')),
        content: Text(widget.i18n.t('tracker_confirm_stop_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.i18n.t('tracker_stop_path')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.recordingService?.stopRecording();
      if (mounted) {
        _loadData();
      }
    }
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBottomStat(
              widget.i18n.t('tracker_distance'),
              _formatDistance(_totalDistanceMeters),
            ),
            _buildBottomStat(
              widget.i18n.t('tracker_duration'),
              _formatDuration(_duration),
            ),
            _buildBottomStat(
              widget.i18n.t('tracker_avg_speed'),
              _formatSpeed(_avgSpeedMps),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  bool _hasPositionChanged(LockedPosition? latest) {
    if (latest == null || _lastLivePosition == null) {
      return latest != null;
    }
    final latDiff = (latest.latitude - _lastLivePosition!.latitude).abs();
    final lonDiff = (latest.longitude - _lastLivePosition!.longitude).abs();
    return latDiff > 0.000001 || lonDiff > 0.000001;
  }

  IconData _getExpenseIcon(ExpenseType type) {
    return switch (type) {
      ExpenseType.fuel => Icons.local_gas_station,
      ExpenseType.toll => Icons.toll,
      ExpenseType.food => Icons.restaurant,
      ExpenseType.drink => Icons.local_cafe,
      ExpenseType.sleep => Icons.hotel,
      ExpenseType.ticket => Icons.confirmation_number,
      ExpenseType.fine => Icons.gavel,
    };
  }

  Color _getExpenseColor(ExpenseType type) {
    return switch (type) {
      ExpenseType.fuel => Colors.orange,
      ExpenseType.toll => Colors.blue,
      ExpenseType.food => Colors.green,
      ExpenseType.drink => Colors.brown,
      ExpenseType.sleep => Colors.purple,
      ExpenseType.ticket => Colors.teal,
      ExpenseType.fine => Colors.red,
    };
  }

  Widget _buildExpenseMarker(ExpenseType type) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          _getExpenseIcon(type),
          size: 20,
          color: _getExpenseColor(type),
        ),
      ),
    );
  }
}
