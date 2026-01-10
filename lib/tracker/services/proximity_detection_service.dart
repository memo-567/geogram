import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show VoidCallback;

import '../models/tracker_proximity_track.dart';
import 'tracker_service.dart';
import '../../services/log_service.dart';
import '../../services/location_service.dart';
import '../../services/location_provider_service.dart';
import '../../services/devices_service.dart';

/// Service for detecting nearby devices (via Bluetooth) and places (via GPS).
/// Registers as a LocationProviderService consumer for reliable background execution.
class ProximityDetectionService {
  static final ProximityDetectionService _instance =
      ProximityDetectionService._internal();
  factory ProximityDetectionService() => _instance;
  ProximityDetectionService._internal();

  TrackerService? _trackerService;
  VoidCallback? _disposeConsumer;
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
      LogService().log('ProximityDetectionService: Already running');
      return;
    }

    _trackerService = trackerService;
    _isRunning = true;

    // Register as LocationProviderService consumer - fires every 60 seconds
    _disposeConsumer = await LocationProviderService().registerConsumer(
      intervalSeconds: 60,
      onPosition: (pos) => _onPositionUpdate(pos),
    );

    // Run initial scan immediately
    final currentPos = LocationProviderService().currentPosition;
    if (currentPos != null) {
      _scanDevices(currentPos.latitude, currentPos.longitude);
    } else {
      _scanDevices(0.0, 0.0);
    }

    LogService().log('ProximityDetectionService: Started as LocationProvider consumer');
  }

  /// Stop the proximity detection service
  void stop() {
    if (!_isRunning) {
      return;
    }

    _disposeConsumer?.call();
    _disposeConsumer = null;
    _isRunning = false;
    _activeSessions.clear();

    LogService().log('ProximityDetectionService: Stopped');
  }

  /// Handle position update from LocationProviderService
  void _onPositionUpdate(LockedPosition pos) {
    if (!_isRunning || _trackerService == null) return;

    // Scan for devices and places
    _scanDevices(pos.latitude, pos.longitude);
    _checkNearbyPlaces(pos.latitude, pos.longitude);
    _refreshPlacesIfNeeded();
  }

  /// Scan for Bluetooth-connected devices
  Future<void> _scanDevices(double lat, double lon) async {
    if (!_isRunning || _trackerService == null) return;

    try {
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
      ).toList();

      LogService().log('ProximityDetectionService: Found ${bluetoothDevices.length} Bluetooth devices');

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

      // TODO: Load places from:
      // 1. Internal Places collections
      // 2. Station server places (cached)
      // 3. Connect places (from other devices)

      _cachedPlaces = places;
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
      // Extend the most recent entry - update duration regardless of isOpen
      // since we're within the session timeout window
      if (track.entries.isNotEmpty) {
        final lastEntry = track.entries.last;
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
