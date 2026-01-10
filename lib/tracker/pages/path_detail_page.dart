import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/tracker_models.dart';
import '../services/path_recording_service.dart';
import '../services/path_share_service.dart';
import '../services/tracker_service.dart';
import '../utils/speed_utils.dart';
import '../dialogs/edit_path_dialog.dart';
import 'add_expense_page.dart';
import 'path_map_fullscreen_page.dart';
import '../../services/i18n_service.dart';
import '../../services/map_tile_service.dart' show MapLayerType, MapTileService;
import '../../services/log_service.dart';
import '../../services/location_provider_service.dart';
import '../../services/location_service.dart';

/// Detail page showing a recorded path with stats and a speed heatmap.
class PathDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final TrackerPath path;
  final int year;
  final PathRecordingService? recordingService;

  const PathDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.path,
    required this.year,
    this.recordingService,
  });

  @override
  State<PathDetailPage> createState() => _PathDetailPageState();
}

class _PathDetailPageState extends State<PathDetailPage> {
  final MapTileService _mapTileService = MapTileService();
  final MapController _mapController = MapController();

  TrackerPath? _path;
  TrackerPathPoints? _points;
  TrackerExpenses? _expenses;
  List<Polyline> _speedSegments = [];
  bool _loading = true;
  bool _tilesAvailable = true;

  Timer? _refreshTimer;
  LockedPosition? _lastLivePosition;
  int? _lastPointCount;
  bool? _lastPausedState;
  double? _computedPathMaxSpeed;

  double _totalDistanceMeters = 0;
  Duration _duration = Duration.zero;
  double? _avgSpeedMps;
  double? _maxSpeedMps;
  double? _elevationGainMeters;
  double? _elevationLossMeters;
  double? _elevationDifferenceMeters;
  String? _startCity;
  String? _endCity;

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

      await _hydrateSegmentMaxSpeeds();
      _calculateStats();
      _buildSpeedSegments();
      await _lookupCityNames();
      final points = _points?.points ?? const <TrackerPoint>[];
      final fallback = widget.recordingService?.lastPosition;
      final lat = points.isNotEmpty ? points.last.lat : fallback?.latitude;
      final lon = points.isNotEmpty ? points.last.lon : fallback?.longitude;
      if (lat != null && lon != null) {
        unawaited(_mapTileService.ensureOfflineTiles(lat: lat, lng: lon));
      }
    } catch (e) {
      LogService().log('PathDetailPage: Failed to load path details: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
      // Note: Map bounds are now set via initialCameraFit in _buildMapCard
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

    final elevationTotals = _calculateElevation(points);
    _elevationGainMeters = elevationTotals.$1;
    _elevationLossMeters = elevationTotals.$2;
    if (_elevationGainMeters == null && _elevationLossMeters == null) {
      _elevationDifferenceMeters = null;
    } else {
      _elevationDifferenceMeters =
          (_elevationGainMeters ?? 0) - (_elevationLossMeters ?? 0);
    }

    _maxSpeedMps = _computedPathMaxSpeed ?? path?.maxSpeedMps;
  }

  /// Look up city names for start and end points (only for trips >= 30km).
  /// Uses cached values from path if available, otherwise calculates and
  /// persists to disk for completed activities.
  Future<void> _lookupCityNames() async {
    _startCity = null;
    _endCity = null;

    final path = _path;
    if (path == null) return;

    // Use cached values if available
    if (path.startCity != null && path.endCity != null) {
      _startCity = path.startCity;
      _endCity = path.endCity;
      return;
    }

    // Only look up cities for trips longer than 30km
    if (_totalDistanceMeters < 30000) return;

    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.length < 2) return;

    final locationService = LocationService();
    await locationService.init();

    final startPoint = points.first;
    final endPoint = points.last;

    final startResult = await locationService.findNearestCity(
      startPoint.lat,
      startPoint.lon,
    );
    final endResult = await locationService.findNearestCity(
      endPoint.lat,
      endPoint.lon,
    );

    _startCity = startResult?.city;
    _endCity = endResult?.city;

    // Persist only for completed activities (not ongoing recordings)
    if (path.status == TrackerPathStatus.completed &&
        _startCity != null &&
        _endCity != null) {
      final updated = path.copyWith(
        startCity: _startCity,
        endCity: _endCity,
      );
      await widget.service.updatePath(updated, year: widget.year);
      _path = updated;
    }
  }

  void _buildSpeedSegments() {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.length < 2) {
      _speedSegments = [];
      _maxSpeedMps ??= null;
      return;
    }

    final segmentSpeeds = <double>[];
    for (var i = 1; i < points.length; i++) {
      final speed = _resolveSegmentSpeed(points[i - 1], points[i]);
      segmentSpeeds.add(speed);
    }

    final computedMax = segmentSpeeds.isNotEmpty
        ? segmentSpeeds.reduce(math.max)
        : null;
    if (computedMax != null) {
      _maxSpeedMps = _maxSpeedMps != null
          ? math.max(_maxSpeedMps!, computedMax)
          : computedMax;
    }

    final maxSpeed = computedMax ?? _maxSpeedMps ?? 1;
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
    final seconds = millis / 1000.0;
    final speed = distance / seconds;

    // Cap unreasonable speeds (GPS errors)
    return speed > maxSpeed ? 0 : speed;
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
    if (metersPerSecond == null) return '-';
    final kmh = metersPerSecond * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  @override
  Widget build(BuildContext context) {
    final path = _path ?? widget.path;

    return Scaffold(
      appBar: AppBar(
        title: Text(path.title ?? path.id),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _editPath(path),
            icon: const Icon(Icons.edit),
            tooltip: widget.i18n.t('tracker_edit_path'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(path),
    );
  }

  Widget _buildContent(TrackerPath path) {
    final points = _points?.points ?? const <TrackerPoint>[];
    final isActive = widget.recordingService?.activePathId == path.id;
    if (points.isEmpty && !isActive) {
      return Center(
        child: Text(widget.i18n.t('tracker_no_path_points')),
      );
    }

    final pathType = TrackerPathType.fromTags(path.tags);
    final hasSegments = path.segments.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildMapCard(points),
        const SizedBox(height: 8),
        _buildShareButton(path),
        const SizedBox(height: 16),
        _buildHighlightsCard(pathType),
        if (isActive || hasSegments) ...[
          const SizedBox(height: 16),
          _buildSegmentCard(path, isActive: isActive),
        ],
        const SizedBox(height: 16),
        _buildExpensesCard(path),
        const SizedBox(height: 16),
        _buildMetadataCard(path),
      ],
    );
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

  Widget _buildMapCard(List<TrackerPoint> points) {
    final start = points.isNotEmpty ? points.first : null;
    final end = points.isNotEmpty ? points.last : null;
    final fallbackPosition = widget.recordingService?.lastPosition;
    final fallbackCenter = fallbackPosition != null
        ? LatLng(fallbackPosition.latitude, fallbackPosition.longitude)
        : const LatLng(0, 0);
    final centerLat = end?.lat ?? start?.lat ?? fallbackPosition?.latitude;
    final centerLon = end?.lon ?? start?.lon ?? fallbackPosition?.longitude;

    // Calculate bounds upfront for initialCameraFit
    final pathBounds = _calculatePathBounds(points);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 260,
        child: Stack(
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
                initialCenter: pathBounds == null && centerLat != null && centerLon != null
                    ? LatLng(centerLat, centerLon)
                    : fallbackCenter,
                initialZoom: pathBounds == null ? 14 : 10,
                minZoom: 1,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (_, __) => _openFullscreenMap(_path ?? widget.path),
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
                    if (centerLat != null && centerLon != null) {
                      unawaited(
                        _mapTileService.ensureOfflineTiles(
                          lat: centerLat,
                          lng: centerLon,
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
                TileLayer(
                  urlTemplate: _mapTileService.getLabelsUrl(),
                  userAgentPackageName: 'dev.geogram',
                  subdomains: const [],
                  tileProvider: _mapTileService.getLabelsProvider(),
                  evictErrorTileStrategy: EvictErrorTileStrategy.none,
                ),
                // Only show transport labels for trips under 100km
                if (_totalDistanceMeters < 100000)
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
            // Show city-to-city label only for trips >= 30km
            if (_startCity != null && _endCity != null)
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
                    '$_startCity → $_endCity',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.open_in_full, color: Colors.white),
                onPressed: () => _openFullscreenMap(_path ?? widget.path),
                tooltip: widget.i18n.t('tracker_fullscreen_map'),
              ),
            ),
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
                  child: Text(
                    widget.i18n.t('tracker_offline_tiles'),
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
                  icon: Icons.emoji_events_outlined,
                ),
                if (_elevationDifferenceMeters != null)
                  _buildStatChip(
                    widget.i18n.t('tracker_elevation_difference'),
                    '${_elevationDifferenceMeters!.toStringAsFixed(0)} m',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesCard(TrackerPath path) {
    final theme = Theme.of(context);
    final expenses = _expenses?.expenses ?? [];
    final fuelExpenses = _expenses?.fuelExpenses ?? [];
    final hasFuel = fuelExpenses.isNotEmpty;

    // Calculate fuel metrics if we have fuel expenses
    FuelMetrics? fuelMetrics;
    if (hasFuel) {
      fuelMetrics = FuelMetrics.fromExpenses(
        fuelExpenses,
        _totalDistanceMeters / 1000,
      );
    }

    // Calculate total (only meaningful if single currency)
    final singleCurrency = _expenses?.hasSingleCurrency ?? true;
    final totalCost = _expenses?.totalAllCost ?? 0;
    final commonCurrency = _expenses?.commonCurrency;

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.receipt_long),
        title: Text(widget.i18n.t('tracker_expenses')),
        subtitle: expenses.isEmpty
            ? Text(widget.i18n.t('tracker_no_expenses'))
            : singleCurrency && commonCurrency != null
                ? Text(
                    '${supportedCurrencies[commonCurrency] ?? commonCurrency}${totalCost.toStringAsFixed(2)}',
                  )
                : Text('${expenses.length} ${widget.i18n.t('tracker_items')}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fuel summary section
                if (hasFuel && fuelMetrics != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_gas_station, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              widget.i18n.t('tracker_fuel_summary'),
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (fuelMetrics.currency != null)
                              _buildStatChip(
                                widget.i18n.t('tracker_total_cost'),
                                '${supportedCurrencies[fuelMetrics.currency] ?? fuelMetrics.currency}${fuelMetrics.totalCost.toStringAsFixed(2)}',
                              ),
                            _buildStatChip(
                              widget.i18n.t('tracker_total_liters'),
                              '${fuelMetrics.totalLiters.toStringAsFixed(1)} L',
                            ),
                            if (fuelMetrics.costPerKm != null)
                              _buildStatChip(
                                widget.i18n.t('tracker_cost_per_km'),
                                fuelMetrics.formattedCostPerKm ?? '',
                              ),
                            if (fuelMetrics.litersPerHundredKm != null)
                              _buildStatChip(
                                widget.i18n.t('tracker_consumption'),
                                fuelMetrics.formattedLitersPerHundredKm ?? '',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Expenses list
                if (expenses.isNotEmpty) ...[
                  ...(_expenses?.sortedByTime ?? []).map((expense) => ListTile(
                        leading: Icon(_getExpenseIcon(expense.type)),
                        title: Text(widget.i18n.t('tracker_expense_${expense.type.name}')),
                        subtitle: Text(
                          DateFormat.yMMMd().add_Hm().format(expense.timestampDateTime),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              expense.formattedAmount,
                              style: theme.textTheme.titleMedium,
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _showExpenseOptions(expense),
                              tooltip: widget.i18n.t('menu'),
                            ),
                          ],
                        ),
                      )),
                  const Divider(),
                ],

                // Add expense button
                TextButton.icon(
                  onPressed: () => _addExpense(path),
                  icon: const Icon(Icons.add),
                  label: Text(widget.i18n.t('tracker_add_expense')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  Future<void> _addExpense(TrackerPath path) async {
    final expense = await AddExpensePage.show(
      context,
      i18n: widget.i18n,
      path: path,
      points: _points,
    );

    if (expense != null && mounted) {
      final added = await widget.service.addPathExpense(
        path.id,
        expense,
        year: widget.year,
      );
      if (added != null) {
        await _loadData();
      }
    }
  }

  Future<void> _showExpenseOptions(TrackerExpense expense) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(widget.i18n.t('edit')),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                widget.i18n.t('delete'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result == 'edit') {
      final updated = await AddExpensePage.show(
        context,
        i18n: widget.i18n,
        path: _path!,
        points: _points,
        existing: expense,
      );

      if (updated != null && mounted) {
        await widget.service.updatePathExpense(
          _path!.id,
          updated,
          year: widget.year,
        );
        await _loadData();
      }
    } else if (result == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.i18n.t('tracker_delete_expense')),
          content: Text(widget.i18n.t('tracker_delete_expense_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.i18n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(widget.i18n.t('delete')),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await widget.service.deletePathExpense(
          _path!.id,
          expense.id,
          year: widget.year,
        );
        await _loadData();
      }
    }
  }

  Widget _buildShareButton(TrackerPath path) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: _isSharing ? null : () => _shareActivity(path),
        icon: _isSharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.share),
        label: Text(widget.i18n.t('tracker_share_activity')),
      ),
    );
  }

  bool _isSharing = false;

  Future<void> _shareActivity(TrackerPath path) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      final imageBytes = await PathShareService.generateShareImage(
        context: context,
        path: path,
        points: _points,
        totalDistanceMeters: _totalDistanceMeters,
        duration: _duration,
        avgSpeedMps: _avgSpeedMps,
        maxSpeedMps: _maxSpeedMps,
        elevationDifference: _elevationDifferenceMeters,
        startCity: _startCity,
        endCity: _endCity,
        i18n: widget.i18n,
        expenses: _expenses,
      );

      if (!mounted) return;

      if (imageBytes != null) {
        final success = await PathShareService.shareImage(
          imageBytes,
          context: context,
          i18n: widget.i18n,
        );

        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.i18n.t('error'))),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('error'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('error'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
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
              DateFormat.yMMMd().add_Hm().format(path.startedAtDateTime.toLocal()),
            ),
            if (path.endedAtDateTime != null)
              _buildMetaRow(
                widget.i18n.t('tracker_ended'),
                DateFormat.yMMMd().add_Hm().format(path.endedAtDateTime!.toLocal()),
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

  Widget _buildSegmentCard(TrackerPath path, {required bool isActive}) {
    final theme = Theme.of(context);
    final currentSegment = path.segments.isNotEmpty ? path.segments.last : null;
    final currentType = currentSegment != null
        ? TrackerPathType.fromId(currentSegment.typeId)
        : TrackerPathType.fromTags(path.tags) ?? TrackerPathType.travel;
    final segments = _buildSegmentSummaries(path);
    final isPaused = widget.recordingService?.isPaused ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_transport_segments'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TrackerPathType>(
              value: currentType,
              decoration: InputDecoration(
                labelText: widget.i18n.t('tracker_current_transport'),
                border: const OutlineInputBorder(),
              ),
              items: TrackerPathType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            Icon(type.icon, size: 18),
                            const SizedBox(width: 8),
                            Text(widget.i18n.t(type.translationKey)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: isActive
                  ? (value) async {
                      if (value == null) return;
                      final updated =
                          await widget.recordingService?.updatePathType(value);
                      if (updated == true) {
                        _loadData();
                      }
                    }
                  : null,
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isPaused
                        ? () async {
                            final resumed =
                                await widget.recordingService?.resumeRecording();
                            if (resumed == true) {
                              _loadData();
                            }
                          }
                        : () async {
                            final paused =
                                await widget.recordingService?.pauseRecording();
                            if (paused == true) {
                              _loadData();
                            }
                          },
                    icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(
                      widget.i18n.t(
                        isPaused ? 'tracker_resume_path' : 'tracker_pause_path',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _confirmStopRecording,
                    icon: const Icon(Icons.stop),
                    label: Text(widget.i18n.t('tracker_stop_path')),
                  ),
                ],
              ),
            ],
            if (segments.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                children: _buildSegmentWidgets(segments, path, isActive),
              ),
            ),
          ],
        ],
      ),
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

  List<_SegmentSummary> _buildSegmentSummaries(TrackerPath path) {
    final points = _points?.points ?? const <TrackerPoint>[];
    final rawSegments = path.segments.isNotEmpty
        ? path.segments
        : [
            TrackerPathSegment(
              typeId: (TrackerPathType.fromTags(path.tags) ??
                      TrackerPathType.travel)
                  .id,
              startedAt: path.startedAt,
              endedAt: path.endedAt,
              startPointIndex: points.isNotEmpty ? 0 : null,
              endPointIndex:
                  points.isNotEmpty ? points.length - 1 : null,
            ),
          ];

    final summaries = <_SegmentSummary>[];
    for (var i = 0; i < rawSegments.length; i++) {
      final segment = rawSegments[i];
      final startIndex = segment.startPointIndex ?? 0;
      final endIndex =
          segment.endPointIndex ?? (points.isNotEmpty ? points.length - 1 : 0);
      final boundedStart = points.isNotEmpty
          ? startIndex.clamp(0, points.length - 1)
          : 0;
      final boundedEnd = points.isNotEmpty
          ? endIndex.clamp(0, points.length - 1)
          : 0;

      var distance = 0.0;
      if (points.length > 1 && boundedEnd > boundedStart) {
        for (var i = boundedStart + 1; i <= boundedEnd; i++) {
          distance += _haversineDistance(
            points[i - 1].lat,
            points[i - 1].lon,
            points[i].lat,
            points[i].lon,
          );
        }
      }

      final startTime = points.isNotEmpty && boundedStart < points.length
          ? points[boundedStart].timestampDateTime
          : DateTime.tryParse(segment.startedAt) ?? DateTime.now();
      final endTime = points.isNotEmpty && boundedEnd < points.length
          ? points[boundedEnd].timestampDateTime
          : (segment.endedAt != null
                  ? DateTime.tryParse(segment.endedAt!)
                  : DateTime.now()) ??
              DateTime.now();
      final duration = endTime.difference(startTime);

      summaries.add(
        _SegmentSummary(
          type: TrackerPathType.fromId(segment.typeId),
          duration: duration,
          distanceMeters: distance,
          segmentIndex: path.segments.isNotEmpty ? i : null,
          rawSegment: path.segments.isNotEmpty ? segment : null,
          startTime: startTime,
          endTime: endTime,
          startIndex: boundedStart,
          endIndex: boundedEnd,
          maxSpeedMps: segment.maxSpeedMps,
        ),
      );
    }

    return summaries;
  }

  List<Widget> _buildSegmentWidgets(
    List<_SegmentSummary> segments,
    TrackerPath path,
    bool isActive,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      widgets.add(
        _buildSegmentFlowItem(
          segment,
          isFirst: i == 0,
          onLongPress: segment.segmentIndex != null
              ? () => _showSegmentOptions(path, segment, isActive)
              : null,
          onTap: () => _showSegmentDetails(segment),
        ),
      );
      if (i < segments.length - 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildSegmentFlowItem(
    _SegmentSummary segment, {
    required bool isFirst,
    VoidCallback? onLongPress,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final label = widget.i18n.t(segment.type.translationKey);
    final duration = _formatDuration(segment.duration);
    final distance = _formatDistance(segment.distanceMeters);
    final text = '$label ($duration, $distance)';
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              segment.type.icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: theme.textTheme.labelMedium,
          ),
          if (isFirst) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.circle,
              size: 6,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );

    if (onLongPress == null && onTap == null) {
      return child;
    }

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: child,
    );
  }

  Future<void> _showSegmentDetails(_SegmentSummary summary) async {
    final theme = Theme.of(context);
    final duration = summary.duration;
    final distance = summary.distanceMeters;
    final avgSpeed = duration.inSeconds > 0
        ? distance / duration.inSeconds
        : 0.0;
    final maxSpeed = summary.maxSpeedMps ?? _resolveMaxSegmentSpeed(summary);
    final startTime = summary.startTime;
    final endTime = summary.endTime;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(summary.type.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    widget.i18n.t(summary.type.translationKey),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                widget.i18n.t('tracker_duration'),
                _formatDuration(summary.duration),
              ),
              _buildStatRow(
                widget.i18n.t('tracker_distance'),
                _formatDistance(summary.distanceMeters),
              ),
              _buildStatRow(
                widget.i18n.t('tracker_avg_speed'),
                _formatSpeed(avgSpeed),
              ),
              _buildStatRow(
                widget.i18n.t('tracker_max_speed'),
                _formatSpeed(maxSpeed),
              ),
              const Divider(height: 24),
              if (startTime != null)
                _buildStatRow(
                  widget.i18n.t('tracker_started'),
                  DateFormat.yMMMd().add_Hm().format(startTime.toLocal()),
                ),
              if (endTime != null)
                _buildStatRow(
                  widget.i18n.t('tracker_ended'),
                  DateFormat.yMMMd().add_Hm().format(endTime.toLocal()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double? _resolveMaxSegmentSpeed(_SegmentSummary summary) {
    final points = _points?.points ?? const <TrackerPoint>[];
    if (points.length < 2) return null;
    var start = summary.startIndex ?? 0;
    var end = summary.endIndex ?? (points.length - 1);
    if (start < 0) start = 0;
    if (end >= points.length) end = points.length - 1;

    List<TrackerPoint> windowPoints;
    if (end > start) {
      windowPoints = points.sublist(start, end + 1);
    } else if (summary.startTime != null) {
      windowPoints = points
          .where((point) {
            final ts = point.timestampDateTime;
            if (summary.endTime == null) {
              return !ts.isBefore(summary.startTime!);
            }
            return !ts.isBefore(summary.startTime!) &&
                !ts.isAfter(summary.endTime!);
          })
          .toList();
    } else {
      return null;
    }

    if (windowPoints.length < 2) return null;

    double? maxSpeed;
    for (var i = 1; i < windowPoints.length; i++) {
      final speed =
          _resolveSegmentSpeed(windowPoints[i - 1], windowPoints[i]);
      if (maxSpeed == null || speed > maxSpeed) {
        maxSpeed = speed;
      }
    }
    return maxSpeed;
  }

  Future<void> _hydrateSegmentMaxSpeeds() async {
    if (_path == null || _points == null || _points!.points.length < 2) {
      return;
    }

    final points = _points!.points;
    final segments = List<TrackerPathSegment>.from(_path!.segments);
    bool needsSave = false;
    double? pathMax = _path!.maxSpeedMps;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isClosed = segment.endedAt != null;

      // Skip if closed segment already has max speed (already persisted)
      if (isClosed && segment.maxSpeedMps != null) {
        if (pathMax == null || segment.maxSpeedMps! > pathMax) {
          pathMax = segment.maxSpeedMps;
        }
        continue;
      }

      // Calculate filtered max speed for this segment
      final startIdx = segment.startPointIndex ?? 0;
      final endIdx = segment.endPointIndex ?? (points.length - 1);

      final segMax = SpeedUtils.calculateFilteredMaxSpeed(
        points,
        startIndex: startIdx,
        endIndex: endIdx,
      );

      if (segMax != null) {
        segments[i] = segment.copyWith(maxSpeedMps: segMax);
        if (isClosed) needsSave = true; // Persist closed segments
        if (pathMax == null || segMax > pathMax) {
          pathMax = segMax;
        }
      }
    }

    // Update path max speed if changed
    if (pathMax != _path!.maxSpeedMps) {
      needsSave = true;
    }

    // Persist to disk if any closed segment was updated
    if (needsSave) {
      final updatedPath = _path!.copyWith(
        segments: segments,
        maxSpeedMps: pathMax,
      );
      final saved =
          await widget.service.updatePath(updatedPath, year: widget.year);
      _path = saved ?? updatedPath;
    } else {
      _path = _path!.copyWith(segments: segments, maxSpeedMps: pathMax);
    }

    _computedPathMaxSpeed = pathMax;
    _maxSpeedMps = pathMax;
  }

  double? _computeSegmentMaxSpeedFromPoints(
    TrackerPathSegment segment,
    List<TrackerPoint> points,
    List<double> speeds,
  ) {
    if (points.length < 2) return null;
    var start = segment.startPointIndex ?? 0;
    var end = segment.endPointIndex ?? (points.length - 1);
    if (start < 0) start = 0;
    if (end >= points.length) end = points.length - 1;

    List<int> indexes;
    if (end > start) {
      indexes = List<int>.generate(end - start, (idx) => start + idx + 1);
    } else {
      final startTime = DateTime.tryParse(segment.startedAt);
      final endTime = segment.endedAt != null
          ? DateTime.tryParse(segment.endedAt!)
          : null;
      if (startTime != null) {
        indexes = [];
        for (var i = 1; i < points.length; i++) {
          final ts = points[i].timestampDateTime;
          if (endTime == null) {
            if (!ts.isBefore(startTime)) {
              indexes.add(i);
            }
          } else {
            if (!ts.isBefore(startTime) && !ts.isAfter(endTime)) {
              indexes.add(i);
            }
          }
        }
      } else {
        return null;
      }
    }

    if (indexes.isEmpty) return null;

    double? maxSpeed;
    for (final idx in indexes) {
      if (idx - 1 < 0 || idx - 1 >= speeds.length) continue;
      final speed = speeds[idx - 1];
      if (maxSpeed == null || speed > maxSpeed) {
        maxSpeed = speed;
      }
    }
    return maxSpeed;
  }

  List<double> _computeSpeeds(List<TrackerPoint> points) {
    final speeds = <double>[];
    for (var i = 1; i < points.length; i++) {
      final speed = _resolveSegmentSpeed(points[i - 1], points[i]);
      speeds.add(speed);
    }
    return speeds;
  }

  Future<void> _maybePersistSegmentMaxSpeeds(
    TrackerPath path,
    List<TrackerPoint> points,
  ) async {
    if (points.length < 2) {
      return;
    }

    var updated = false;
    var pathMax = path.maxSpeedMps;

    List<TrackerPathSegment> segments = path.segments;
    if (segments.isNotEmpty) {
      final nextSegments = <TrackerPathSegment>[];
      for (final segment in segments) {
        final computed = _computeSegmentMaxSpeed(segment, points);
        if (computed != null) {
          if (pathMax == null || computed > pathMax) {
            pathMax = computed;
          }
        }
        if (computed != null && computed > 0) {
          final current = segment.maxSpeedMps;
          if (current == null || computed > current) {
            nextSegments.add(segment.copyWith(maxSpeedMps: computed));
            updated = true;
          } else {
            nextSegments.add(segment);
          }
        } else {
          nextSegments.add(segment);
        }
      }
      segments = nextSegments;
    } else if (pathMax == null) {
      pathMax = _computeSegmentMaxSpeed(
        TrackerPathSegment(
          typeId: TrackerPathType.fromTags(path.tags)?.id ??
              TrackerPathType.travel.id,
          startedAt: path.startedAt,
          endedAt: path.endedAt,
        ),
        points,
      );
    }

    if ((pathMax != null && pathMax != path.maxSpeedMps) || updated) {
      final updatedPath = path.copyWith(
        segments: segments,
        maxSpeedMps: pathMax,
      );
      final saved = await widget.service.updatePath(
        updatedPath,
        year: widget.year,
      );
      if (saved != null && mounted) {
        setState(() {
          _path = saved;
          _maxSpeedMps = saved.maxSpeedMps ?? _maxSpeedMps;
        });
      }
    } else if (pathMax != null && _maxSpeedMps == null) {
      setState(() {
        _maxSpeedMps = pathMax;
      });
    }
  }

  double? _computeSegmentMaxSpeed(
    TrackerPathSegment segment,
    List<TrackerPoint> points,
  ) {
    if (points.length < 2) return null;
    var start = segment.startPointIndex ?? 0;
    var end = segment.endPointIndex ?? (points.length - 1);
    if (start < 0) start = 0;
    if (end >= points.length) end = points.length - 1;

    List<TrackerPoint> windowPoints;
    if (end > start) {
      windowPoints = points.sublist(start, end + 1);
    } else {
      final startTime = DateTime.tryParse(segment.startedAt);
      final endTime = segment.endedAt != null
          ? DateTime.tryParse(segment.endedAt!)
          : null;
      if (startTime != null) {
        windowPoints = points.where((point) {
          final ts = point.timestampDateTime;
          if (endTime == null) {
            return !ts.isBefore(startTime);
          }
          return !ts.isBefore(startTime) && !ts.isAfter(endTime);
        }).toList();
      } else {
        return null;
      }
    }

    if (windowPoints.length < 2) return null;
    double? maxSpeed;
    for (var i = 1; i < windowPoints.length; i++) {
      final speed =
          _resolveSegmentSpeed(windowPoints[i - 1], windowPoints[i]);
      if (maxSpeed == null || speed > maxSpeed) {
        maxSpeed = speed;
      }
    }
    return maxSpeed;
  }

  Widget _buildStatRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _showSegmentOptions(
    TrackerPath path,
    _SegmentSummary summary,
    bool isActive,
  ) async {
    final segmentIndex = summary.segmentIndex;
    if (segmentIndex == null) return;
    final lastIndex = path.segments.length - 1;
    final canDelete =
        segmentIndex > 0 && (!isActive || segmentIndex < lastIndex);

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(widget.i18n.t('delete')),
              enabled: canDelete,
              onTap: canDelete
                  ? () => Navigator.of(context).pop('delete')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: Text(widget.i18n.t('merge_with_previous')),
              enabled: canDelete,
              onTap: canDelete
                  ? () => Navigator.of(context).pop('merge_prev')
                  : null,
            ),
          ],
        ),
      ),
    );

    if (selected == 'delete') {
      await _deleteSegment(path, segmentIndex);
    } else if (selected == 'merge_prev') {
      await _mergeWithPreviousSegment(path, segmentIndex);
    }
  }

  Future<void> _deleteSegment(TrackerPath path, int segmentIndex) async {
    if (segmentIndex <= 0 || segmentIndex >= path.segments.length) {
      return;
    }

    final segments = List<TrackerPathSegment>.from(path.segments);
    final removed = segments.removeAt(segmentIndex);
    final previousIndex = segmentIndex - 1;
    final previous = segments[previousIndex];

    segments[previousIndex] = previous.copyWith(
      endedAt: removed.endedAt,
      endPointIndex: removed.endPointIndex,
    );

    var updatedTags = path.tags;
    if (segmentIndex == path.segments.length - 1) {
      final typeTag = TrackerPathType.fromId(previous.typeId).toTag();
      updatedTags = [
        typeTag,
        ...path.tags.where((tag) => !tag.startsWith('type:')),
      ];
    }

    final updatedPath = path.copyWith(
      segments: segments,
      tags: updatedTags,
    );

    final saved = await widget.service.updatePath(
      updatedPath,
      year: widget.year,
    );
    if (saved != null && mounted) {
      setState(() => _path = saved);
    }
  }

  Future<void> _mergeWithPreviousSegment(
    TrackerPath path,
    int segmentIndex,
  ) async {
    if (segmentIndex <= 0 || segmentIndex >= path.segments.length) {
      return;
    }

    final segments = List<TrackerPathSegment>.from(path.segments);
    final current = segments.removeAt(segmentIndex);
    final previousIndex = segmentIndex - 1;
    final previous = segments[previousIndex];

    // Merge times and indexes
    final merged = previous.copyWith(
      endedAt: current.endedAt ?? previous.endedAt,
      endPointIndex: current.endPointIndex ?? previous.endPointIndex,
      maxSpeedMps: _maxOf(previous.maxSpeedMps, current.maxSpeedMps),
    );
    segments[previousIndex] = merged;

    // Update tags if we merged the last segment type
    var updatedTags = path.tags;
    if (segmentIndex == path.segments.length - 1) {
      final typeTag = TrackerPathType.fromId(merged.typeId).toTag();
      updatedTags = [
        typeTag,
        ...path.tags.where((tag) => !tag.startsWith('type:')),
      ];
    }

    final updatedPath = path.copyWith(
      segments: segments,
      tags: updatedTags,
    );

    final saved = await widget.service.updatePath(
      updatedPath,
      year: widget.year,
    );
    if (saved != null && mounted) {
      setState(() => _path = saved);
    }
  }

  double? _maxOf(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  Widget _buildStatChip(String label, String value, {IconData? icon}) {
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
          if (icon != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            )
          else
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall,
            ),
        ],
      ),
    );
  }

  Future<void> _editPath(TrackerPath path) async {
    final result = await EditPathDialog.show(
      context,
      path: path,
      i18n: widget.i18n,
    );
    if (result == null) return;

    final updated = path.copyWith(
      title: result.title,
      description: result.description,
    );

    final saved = await widget.service.updatePath(
      updated,
      year: widget.year,
    );
    if (saved != null && mounted) {
      setState(() => _path = saved);
      // Force recalculate max speeds with new filtering algorithm
      await _forceRecalculateMaxSpeeds();
    }
  }

  /// Force recalculate all segment max speeds using the filtered algorithm.
  /// This ignores existing values and recalculates everything.
  Future<void> _forceRecalculateMaxSpeeds() async {
    if (_path == null || _points == null || _points!.points.length < 2) {
      return;
    }

    final points = _points!.points;
    final segments = List<TrackerPathSegment>.from(_path!.segments);
    double? pathMax;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final startIdx = segment.startPointIndex ?? 0;
      final endIdx = segment.endPointIndex ?? (points.length - 1);

      // Force recalculate using filtered algorithm
      final segMax = SpeedUtils.calculateFilteredMaxSpeed(
        points,
        startIndex: startIdx,
        endIndex: endIdx,
      );

      if (segMax != null) {
        segments[i] = segment.copyWith(maxSpeedMps: segMax);
        if (pathMax == null || segMax > pathMax) {
          pathMax = segMax;
        }
      } else {
        // Clear invalid max speed
        segments[i] = TrackerPathSegment(
          typeId: segment.typeId,
          startedAt: segment.startedAt,
          endedAt: segment.endedAt,
          startPointIndex: segment.startPointIndex,
          endPointIndex: segment.endPointIndex,
          maxSpeedMps: null,
        );
      }
    }

    // Save the recalculated values
    final updatedPath = _path!.copyWith(
      segments: segments,
      maxSpeedMps: pathMax,
    );
    final saved =
        await widget.service.updatePath(updatedPath, year: widget.year);
    if (saved != null && mounted) {
      setState(() {
        _path = saved;
        _computedPathMaxSpeed = pathMax;
        _maxSpeedMps = pathMax;
      });
      _buildSpeedSegments();
    }
  }

  void _openFullscreenMap(TrackerPath path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PathMapFullscreenPage(
          service: widget.service,
          i18n: widget.i18n,
          path: path,
          year: widget.year,
          recordingService: widget.recordingService,
        ),
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

  bool _hasPositionChanged(LockedPosition? latest) {
    if (latest == null || _lastLivePosition == null) {
      return latest != null;
    }
    final latDiff = (latest.latitude - _lastLivePosition!.latitude).abs();
    final lonDiff = (latest.longitude - _lastLivePosition!.longitude).abs();
    return latDiff > 0.000001 || lonDiff > 0.000001;
  }
}

class _SegmentSummary {
  final TrackerPathType type;
  final Duration duration;
  final double distanceMeters;
  final int? segmentIndex;
  final TrackerPathSegment? rawSegment;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? startIndex;
  final int? endIndex;
  final double? maxSpeedMps;

  const _SegmentSummary({
    required this.type,
    required this.duration,
    required this.distanceMeters,
    this.segmentIndex,
    this.rawSegment,
    this.startTime,
    this.endTime,
    this.startIndex,
    this.endIndex,
    this.maxSpeedMps,
  });
}
