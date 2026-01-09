import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/tracker_models.dart';
import 'tracker_service.dart';
import '../../services/log_service.dart';
import '../../services/location_provider_service.dart';

/// Service for managing GPS path recording.
/// Uses [LocationProviderService] for GPS positioning.
class PathRecordingService extends ChangeNotifier {
  static final PathRecordingService _instance = PathRecordingService._internal();
  factory PathRecordingService() => _instance;
  PathRecordingService._internal();

  TrackerService? _trackerService;
  TrackerRecordingState? _recordingState;
  VoidCallback? _locationConsumerDispose;
  DateTime? _startTime;
  int _pointCount = 0;
  double _totalDistance = 0;
  LockedPosition? _lastPosition;

  // Getters
  bool get isRecording => _recordingState?.isRecording ?? false;
  bool get isPaused => _recordingState?.isPaused ?? false;
  bool get hasActiveRecording => _recordingState != null;
  String? get activePathId => _recordingState?.activePathId;
  int get pointCount => _pointCount;
  double get totalDistance => _totalDistance;
  Duration get elapsedTime => _startTime != null
      ? DateTime.now().difference(_startTime!)
      : Duration.zero;
  TrackerRecordingState? get recordingState => _recordingState;

  /// Initialize the service with a TrackerService
  void initialize(TrackerService trackerService) {
    _trackerService = trackerService;
  }

  /// Check and resume any active recording from crash recovery
  Future<bool> checkAndResumeRecording() async {
    if (_trackerService == null) return false;

    try {
      final state = await _trackerService!.getRecordingState();
      if (state != null) {
        _recordingState = state;
        _startTime = DateTime.parse(state.startedAt);
        _pointCount = state.pointCount;

        // Load existing points to calculate distance
        final points = await _trackerService!.getPathPoints(
          state.activePathId,
          year: state.activePathYear,
        );
        if (points != null && points.points.isNotEmpty) {
          _totalDistance = points.calculateTotalDistance();
          final lastPoint = points.points.last;
          _lastPosition = LockedPosition(
            latitude: lastPoint.lat,
            longitude: lastPoint.lon,
            altitude: lastPoint.altitude ?? 0,
            accuracy: lastPoint.accuracy ?? 0,
            speed: lastPoint.speed ?? 0,
            heading: lastPoint.bearing ?? 0,
            timestamp: DateTime.parse(lastPoint.timestamp),
            source: 'stored',
          );
        }

        if (state.isRecording) {
          await _startGPSUpdates(state.intervalSeconds);
        }

        notifyListeners();
        return true;
      }
    } catch (e) {
      LogService().log('PathRecordingService: Error resuming recording: $e');
    }
    return false;
  }

  /// Start a new path recording
  ///
  /// [notificationTitle] and [notificationText] are used for the Android
  /// foreground service notification.
  Future<TrackerPath?> startRecording({
    required TrackerPathType pathType,
    required String title,
    String? description,
    int intervalSeconds = 60,
    String? notificationTitle,
    String? notificationText,
  }) async {
    if (_trackerService == null) {
      LogService().log('PathRecordingService: TrackerService not initialized');
      return null;
    }

    if (_recordingState != null) {
      LogService().log('PathRecordingService: Recording already in progress');
      return null;
    }

    try {
      // Start location provider first to validate GPS availability
      final started = await _startGPSUpdates(
        intervalSeconds,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      );
      if (!started) {
        LogService().log('PathRecordingService: Could not start GPS');
        return null;
      }
      final now = DateTime.now();
      final year = now.year;

      // Create tags with path type
      final tags = <String>[pathType.toTag()];

      // Create the path
      final path = await _trackerService!.createPath(
        title: title,
        description: description,
        intervalSeconds: intervalSeconds,
        tags: tags,
      );

      if (path == null) {
        _stopGPSUpdates();
        LogService().log('PathRecordingService: Failed to create path');
        return null;
      }

      // Save recording state
      _recordingState = TrackerRecordingState(
        activePathId: path.id,
        activePathYear: year,
        status: RecordingStatus.recording,
        intervalSeconds: intervalSeconds,
        startedAt: now.toIso8601String(),
        pointCount: 0,
      );

      await _trackerService!.saveRecordingState(_recordingState!);

      _startTime = now;
      _pointCount = 0;
      _totalDistance = 0;
      _lastPosition = null;

      // GPS already started above
      notifyListeners();
      return path;
    } catch (e) {
      _stopGPSUpdates();
      LogService().log('PathRecordingService: Error starting recording: $e');
      return null;
    }
  }

  /// Pause the current recording
  Future<bool> pauseRecording() async {
    if (_recordingState == null || !_recordingState!.isRecording) {
      return false;
    }

    try {
      _stopGPSUpdates();

      _recordingState = _recordingState!.copyWith(
        status: RecordingStatus.paused,
        pausedAt: DateTime.now().toIso8601String(),
      );

      await _trackerService?.saveRecordingState(_recordingState!);

      // Update path status
      await _trackerService?.pausePath(
        _recordingState!.activePathId,
        year: _recordingState!.activePathYear,
      );

      notifyListeners();
      return true;
    } catch (e) {
      LogService().log('PathRecordingService: Error pausing recording: $e');
      return false;
    }
  }

  /// Resume a paused recording
  Future<bool> resumeRecording() async {
    if (_recordingState == null || !_recordingState!.isPaused) {
      return false;
    }

    try {
      _recordingState = _recordingState!.copyWith(
        status: RecordingStatus.recording,
        pausedAt: null,
      );

      await _trackerService?.saveRecordingState(_recordingState!);

      // Update path status
      await _trackerService?.resumePath(
        _recordingState!.activePathId,
        year: _recordingState!.activePathYear,
      );

      // Resume GPS updates
      await _startGPSUpdates(_recordingState!.intervalSeconds);

      notifyListeners();
      return true;
    } catch (e) {
      LogService().log('PathRecordingService: Error resuming recording: $e');
      return false;
    }
  }

  /// Stop and complete the current recording
  Future<TrackerPath?> stopRecording() async {
    if (_recordingState == null) {
      return null;
    }

    try {
      _stopGPSUpdates();

      final path = await _trackerService?.completePath(
        _recordingState!.activePathId,
        year: _recordingState!.activePathYear,
      );

      await _trackerService?.clearRecordingState();

      _recordingState = null;
      _startTime = null;
      _pointCount = 0;
      _totalDistance = 0;
      _lastPosition = null;

      notifyListeners();
      return path;
    } catch (e) {
      LogService().log('PathRecordingService: Error stopping recording: $e');
      return null;
    }
  }

  /// Cancel and discard the current recording
  Future<bool> cancelRecording() async {
    if (_recordingState == null) {
      return false;
    }

    try {
      _stopGPSUpdates();

      await _trackerService?.deletePath(
        _recordingState!.activePathId,
        year: _recordingState!.activePathYear,
      );

      await _trackerService?.clearRecordingState();

      _recordingState = null;
      _startTime = null;
      _pointCount = 0;
      _totalDistance = 0;
      _lastPosition = null;

      notifyListeners();
      return true;
    } catch (e) {
      LogService().log('PathRecordingService: Error cancelling recording: $e');
      return false;
    }
  }

  /// Start GPS position updates via LocationProviderService
  Future<bool> _startGPSUpdates(
    int intervalSeconds, {
    String? notificationTitle,
    String? notificationText,
  }) async {
    _stopGPSUpdates();

    try {
      _locationConsumerDispose = await LocationProviderService().registerConsumer(
        intervalSeconds: intervalSeconds,
        onPosition: _onPositionUpdate,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      );
      return true;
    } catch (e) {
      LogService().log('PathRecordingService: Failed to start GPS: $e');
      return false;
    }
  }

  /// Stop GPS position updates
  void _stopGPSUpdates() {
    _locationConsumerDispose?.call();
    _locationConsumerDispose = null;
  }

  /// Handle a position update from LocationProviderService
  void _onPositionUpdate(LockedPosition position) {
    if (_recordingState == null || !_recordingState!.isRecording) {
      return;
    }

    _addPoint(position);
  }

  /// Add a point to the current path
  Future<void> _addPoint(LockedPosition position) async {
    if (_recordingState == null || _trackerService == null) return;

    try {
      final point = TrackerPoint(
        index: _pointCount,
        timestamp: position.timestamp.toIso8601String(),
        lat: position.latitude,
        lon: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        bearing: position.heading,
      );

      final success = await _trackerService!.addPathPoint(
        _recordingState!.activePathId,
        point,
        year: _recordingState!.activePathYear,
      );

      if (success) {
        // Calculate distance from last point
        if (_lastPosition != null) {
          final distance = _calculateDistance(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          _totalDistance += distance;
        }

        _lastPosition = position;
        _pointCount++;

        // Update recording state
        _recordingState = _recordingState!.copyWith(
          lastPointTimestamp: position.timestamp.toIso8601String(),
          pointCount: _pointCount,
        );

        await _trackerService!.saveRecordingState(_recordingState!);

        notifyListeners();
      }
    } catch (e) {
      LogService().log('PathRecordingService: Error adding point: $e');
    }
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Clean up resources
  @override
  void dispose() {
    _stopGPSUpdates();
    super.dispose();
  }
}
