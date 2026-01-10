import 'dart:async';
import 'dart:math' as math;

import '../models/tracker_proximity_track.dart';
import 'tracker_service.dart';
import '../../services/log_service.dart';
import '../../services/location_service.dart';
import '../../services/devices_service.dart';
import '../../util/event_bus.dart';

/// Service for detecting nearby devices (via Bluetooth) and places (via GPS).
/// Subscribes to PositionUpdatedEvent and checks for proximity matches.
class ProximityDetectionService {
  static final ProximityDetectionService _instance =
      ProximityDetectionService._internal();
  factory ProximityDetectionService() => _instance;
  ProximityDetectionService._internal();

  TrackerService? _trackerService;
  EventSubscription<PositionUpdatedEvent>? _positionSubscription;
  Timer? _scanTimer;
  bool _isRunning = false;

  /// Cached places list (refreshed every 5 minutes)
  List<_CachedPlace> _cachedPlaces = [];
  DateTime? _placesLastRefreshed;
  static const _placesRefreshInterval = Duration(minutes: 5);

  /// Active proximity sessions (id -> last detection time)
  final Map<String, DateTime> _activeSessions = {};
  static const _sessionTimeout = Duration(minutes: 2);

  /// Radius in meters for place detection
  static const double placeRadiusMeters = 50;

  bool get isRunning => _isRunning;

  /// Start the proximity detection service
  Future<void> start(TrackerService trackerService) async {
    if (_isRunning) {
      LogService().log('ProximityDetectionService: Already running, skipping start');
      return;
    }

    _trackerService = trackerService;
    _isRunning = true;

    // Subscribe to position updates for place detection
    _positionSubscription = EventBus().on<PositionUpdatedEvent>(_onPositionUpdate);

    // Timer for device scanning every 60 seconds
    _scanTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      LogService().log('ProximityDetectionService: Timer fired');
      _scanDevices();
    });

    // Run initial scan immediately
    LogService().log('ProximityDetectionService: Running initial scan');
    _scanDevices();

    LogService().log('ProximityDetectionService: Started with 60s timer');
  }

  /// Stop the proximity detection service
  void stop() {
    if (!_isRunning) {
      LogService().log('ProximityDetectionService: Not running, skipping stop');
      return;
    }

    LogService().log('ProximityDetectionService: Stopping...');
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _isRunning = false;
    _activeSessions.clear();

    LogService().log('ProximityDetectionService: Stopped');
  }

  /// Handle position update from EventBus
  Future<void> _onPositionUpdate(PositionUpdatedEvent event) async {
    if (!_isRunning || _trackerService == null) return;

    try {
      // Refresh cached places if needed
      await _refreshPlacesIfNeeded();

      // Check for nearby places
      await _checkNearbyPlaces(event.latitude, event.longitude);

      // Check for devices with Bluetooth connection via DevicesService
      await _checkNearbyDevices(event.latitude, event.longitude);

      // Clean up stale sessions
      _cleanupStaleSessions(DateTime.now());

    } catch (e) {
      LogService().log('ProximityDetectionService: Error in position update: $e');
    }
  }

  /// Check for devices with active Bluetooth connection
  Future<void> _checkNearbyDevices(double lat, double lon) async {
    final now = DateTime.now();
    final year = now.year;
    final week = getWeekNumber(now);
    final timestamp = now.toUtc().toIso8601String();

    // Get all devices from DevicesService
    final allDevices = DevicesService().getAllDevices();

    // Filter for devices with Bluetooth connection
    final bluetoothDevices = allDevices.where((device) =>
      device.connectionMethods.contains('bluetooth') ||
      device.connectionMethods.contains('bluetooth_plus')
    );

    for (final device in bluetoothDevices) {
      await _recordProximity(
        id: device.callsign,
        type: ProximityTargetType.device,
        displayName: device.name.isNotEmpty ? device.name : device.callsign,
        lat: lat,
        lon: lon,
        timestamp: timestamp,
        year: year,
        week: week,
        callsign: device.callsign,
        npub: device.npub,
      );
    }
  }

  /// Scan for Bluetooth-connected devices (called every 60 seconds by timer)
  Future<void> _scanDevices() async {
    if (!_isRunning) {
      LogService().log('ProximityDetectionService: _scanDevices skipped - not running');
      return;
    }
    if (_trackerService == null) {
      LogService().log('ProximityDetectionService: _scanDevices skipped - no tracker service');
      return;
    }

    try {
      final now = DateTime.now();
      final year = now.year;
      final week = getWeekNumber(now);
      final timestamp = now.toUtc().toIso8601String();

      // Get all devices from DevicesService
      final allDevices = DevicesService().getAllDevices();

      LogService().log('ProximityDetectionService: Scanning ${allDevices.length} devices');

      // Filter for devices with Bluetooth connection
      final bluetoothDevices = allDevices.where((device) =>
        device.connectionMethods.contains('bluetooth') ||
        device.connectionMethods.contains('bluetooth_plus')
      ).toList();

      LogService().log('ProximityDetectionService: Found ${bluetoothDevices.length} Bluetooth devices');

      for (final device in bluetoothDevices) {
        LogService().log('ProximityDetectionService: Recording device ${device.callsign}');
        await _recordProximity(
          id: device.callsign,
          type: ProximityTargetType.device,
          displayName: device.name.isNotEmpty ? device.name : device.callsign,
          lat: 0.0,  // No GPS needed for device proximity
          lon: 0.0,
          timestamp: timestamp,
          year: year,
          week: week,
          callsign: device.callsign,
          npub: device.npub,
        );
      }

      LogService().log('ProximityDetectionService: Scan complete');
      // Clean up stale sessions
      _cleanupStaleSessions(now);

    } catch (e) {
      LogService().log('ProximityDetectionService: Error scanning devices: $e');
    }
  }

  /// Refresh cached places list if stale
  Future<void> _refreshPlacesIfNeeded() async {
    final now = DateTime.now();
    if (_placesLastRefreshed != null &&
        now.difference(_placesLastRefreshed!) < _placesRefreshInterval) {
      return; // Cache is still fresh
    }

    await _refreshPlaces();
    _placesLastRefreshed = now;
  }

  /// Refresh the cached places list from all sources
  Future<void> _refreshPlaces() async {
    final places = <_CachedPlace>[];

    try {
      final locationService = LocationService();
      await locationService.init();

      // Load internal places from all collections
      // This would need to be implemented based on how places are stored
      // For now, we'll use a placeholder that can be expanded

      // TODO: Load places from:
      // 1. Internal Places collections
      // 2. Station server places (cached)
      // 3. Connect places (from other devices)

      _cachedPlaces = places;
      LogService().log('ProximityDetectionService: Refreshed ${places.length} places');
    } catch (e) {
      LogService().log('ProximityDetectionService: Error refreshing places: $e');
    }
  }

  /// Check for nearby places within the radius
  Future<void> _checkNearbyPlaces(double lat, double lon) async {
    final now = DateTime.now();
    final year = now.year;
    final week = getWeekNumber(now);
    final timestamp = now.toUtc().toIso8601String();

    for (final place in _cachedPlaces) {
      final distance = _calculateDistance(lat, lon, place.lat, place.lon);

      if (distance <= placeRadiusMeters) {
        await _recordProximity(
          id: place.trackId,
          type: ProximityTargetType.place,
          displayName: place.name,
          lat: lat,
          lon: lon,
          timestamp: timestamp,
          year: year,
          week: week,
          placeId: place.placeId,
          placeSource: place.source,
          placeLat: place.lat,
          placeLon: place.lon,
        );
      }
    }
  }

  /// Record a proximity detection
  Future<void> _recordProximity({
    required String id,
    required ProximityTargetType type,
    required String displayName,
    required double lat,
    required double lon,
    required String timestamp,
    required int year,
    required int week,
    String? npub,
    String? callsign,
    String? placeId,
    PlaceSource? placeSource,
    double? placeLat,
    double? placeLon,
  }) async {
    if (_trackerService == null) return;

    final now = DateTime.now();
    final lastSeen = _activeSessions[id];

    // Get or create track
    var track = await _trackerService!.getProximityTrack(
      id: id,
      year: year,
      week: week,
    );

    if (track == null) {
      // Create new track
      if (type == ProximityTargetType.device) {
        track = ProximityTrack.forDevice(
          callsign: callsign ?? id,
          displayName: displayName,
          npub: npub,
        );
      } else {
        track = ProximityTrack.forPlace(
          placeId: placeId ?? id,
          displayName: displayName,
          lat: placeLat ?? lat,
          lon: placeLon ?? lon,
          source: placeSource ?? PlaceSource.internal,
        );
      }
    }

    // Check if we should extend existing entry or create new one
    if (lastSeen != null && now.difference(lastSeen) < _sessionTimeout) {
      // Extend the most recent entry
      if (track.entries.isNotEmpty) {
        final lastEntry = track.entries.last;
        if (lastEntry.isOpen) {
          // Update ended_at and duration
          final startTime = lastEntry.timestampDateTime;
          final duration = now.difference(startTime).inSeconds;

          final updatedEntry = lastEntry.copyWith(
            endedAt: timestamp,
            durationSeconds: duration,
          );

          final updatedEntries = List<ProximityEntry>.from(track.entries);
          updatedEntries[updatedEntries.length - 1] = updatedEntry;

          track = track.copyWith(entries: updatedEntries);
        }
      }
    } else {
      // Create new entry
      final entry = ProximityEntry(
        timestamp: timestamp,
        lat: lat,
        lon: lon,
      );

      track = track.copyWith(
        entries: [...track.entries, entry],
      );
    }

    // Update active session
    _activeSessions[id] = now;

    // Recalculate summary and save
    track = track.recalculateSummary();
    await _trackerService!.updateProximityTrack(track, year: year, week: week);
  }

  /// Clean up sessions that have timed out
  void _cleanupStaleSessions(DateTime now) {
    final staleIds = <String>[];
    for (final entry in _activeSessions.entries) {
      if (now.difference(entry.value) > _sessionTimeout) {
        staleIds.add(entry.key);
      }
    }
    for (final id in staleIds) {
      _activeSessions.remove(id);
    }
  }

  /// Calculate distance between two coordinates in meters (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Record a device proximity detection (called from BLE service)
  Future<void> recordDeviceProximity({
    required String callsign,
    required String displayName,
    required double lat,
    required double lon,
    String? npub,
  }) async {
    if (!_isRunning || _trackerService == null) return;

    final now = DateTime.now();
    final year = now.year;
    final week = getWeekNumber(now);
    final timestamp = now.toUtc().toIso8601String();

    await _recordProximity(
      id: callsign,
      type: ProximityTargetType.device,
      displayName: displayName,
      lat: lat,
      lon: lon,
      timestamp: timestamp,
      year: year,
      week: week,
      callsign: callsign,
      npub: npub,
    );
  }
}

/// Cached place data for quick proximity checks
class _CachedPlace {
  final String trackId;
  final String placeId;
  final String name;
  final double lat;
  final double lon;
  final PlaceSource source;

  const _CachedPlace({
    required this.trackId,
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.source,
  });
}
