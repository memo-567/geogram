import 'dart:async';
import 'dart:math';

import '../models/tracker_models.dart';
import '../utils/tracker_path_utils.dart';
import 'tracker_storage_service.dart';
import '../../services/log_service.dart';

/// Represents a change in the tracker
class TrackerChange {
  final String type; // 'path', 'measurement', 'exercise', 'plan', 'share', etc.
  final String action; // 'created', 'updated', 'deleted'
  final String? id;
  final dynamic data;

  const TrackerChange({
    required this.type,
    required this.action,
    this.id,
    this.data,
  });
}

/// Main service for managing tracker operations
class TrackerService {
  static final TrackerService _instance = TrackerService._internal();
  factory TrackerService() => _instance;
  TrackerService._internal();

  TrackerStorageService? _storage;
  String? _currentPath;
  String? _ownerCallsign;

  /// Stream controller for tracker changes
  final _changesController = StreamController<TrackerChange>.broadcast();

  /// Stream of tracker changes
  Stream<TrackerChange> get changes => _changesController.stream;

  /// Check if the service is initialized
  bool get isInitialized => _storage != null;

  /// Get the current collection path
  String? get currentPath => _currentPath;

  /// Get the owner callsign
  String? get ownerCallsign => _ownerCallsign;

  /// Initialize the service with a collection path
  Future<void> initializeCollection(String path, {String? callsign}) async {
    _currentPath = path;
    _storage = TrackerStorageService(path);
    _ownerCallsign = callsign;
    await _storage!.initialize();
    LogService().log('TrackerService: Initialized with path $path');
  }

  /// Reset the service (for switching collections)
  void reset() {
    _storage = null;
    _currentPath = null;
    _ownerCallsign = null;
  }

  // ============ Metadata Operations ============

  /// Get collection metadata
  Future<TrackerCollectionMetadata?> getMetadata() async {
    if (_storage == null) return null;
    return _storage!.readMetadata();
  }

  /// Create or update collection metadata
  Future<bool> saveMetadata(TrackerCollectionMetadata metadata) async {
    if (_storage == null) return false;
    final success = await _storage!.writeMetadata(metadata);
    if (success) {
      _notifyChange('metadata', 'updated');
    }
    return success;
  }

  // ============ Path Operations ============

  /// List paths for a year
  Future<List<TrackerPath>> listPaths({int? year}) async {
    if (_storage == null) return [];
    return _storage!.listPaths(year ?? DateTime.now().year);
  }

  /// List available years for paths
  Future<List<int>> listPathYears() async {
    if (_storage == null) return [];
    return _storage!.listYears('paths');
  }

  /// Get a specific path
  Future<TrackerPath?> getPath(String pathId, {int? year}) async {
    if (_storage == null) return null;
    return _storage!.readPath(year ?? DateTime.now().year, pathId);
  }

  /// Get path points
  Future<TrackerPathPoints?> getPathPoints(String pathId, {int? year}) async {
    if (_storage == null) return null;
    return _storage!.readPathPoints(year ?? DateTime.now().year, pathId);
  }

  /// Create a new path
  Future<TrackerPath?> createPath({
    required String title,
    String? description,
    int intervalSeconds = 60,
    List<String>? tags,
  }) async {
    if (_storage == null || _ownerCallsign == null) return null;

    final now = DateTime.now();
    final pathId = 'path_${TrackerPathUtils.formatDateYYYYMMDD(now)}_${_generateId()}';

    final path = TrackerPath(
      id: pathId,
      title: title,
      description: description,
      startedAt: now.toIso8601String(),
      status: TrackerPathStatus.recording,
      intervalSeconds: intervalSeconds,
      totalPoints: 0,
      tags: tags ?? const [],
      ownerCallsign: _ownerCallsign!,
    );

    // Also create empty points file
    final points = TrackerPathPoints(
      pathId: pathId,
      points: const [],
    );

    final success = await _storage!.writePath(now.year, path);
    if (success) {
      await _storage!.writePathPoints(now.year, pathId, points);
      _notifyChange('path', 'created', id: pathId, data: path);
      return path;
    }
    return null;
  }

  /// Add a point to a path
  Future<bool> addPathPoint(String pathId, TrackerPoint point, {int? year}) async {
    if (_storage == null) return false;

    final yr = year ?? DateTime.now().year;
    final existingPoints = await _storage!.readPathPoints(yr, pathId);
    if (existingPoints == null) return false;

    final newPoints = existingPoints.addPoint(point);
    final success = await _storage!.writePathPoints(yr, pathId, newPoints);

    if (success) {
      // Update path metadata with new point count
      final path = await _storage!.readPath(yr, pathId);
      if (path != null) {
        final updatedPath = path.copyWith(totalPoints: newPoints.points.length);
        await _storage!.writePath(yr, updatedPath);
      }
      _notifyChange('path_point', 'created', id: pathId);
    }
    return success;
  }

  /// Complete a path recording
  Future<TrackerPath?> completePath(String pathId, {int? year}) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    final path = await _storage!.readPath(yr, pathId);
    if (path == null) return null;

    final points = await _storage!.readPathPoints(yr, pathId);
    final totalDistance = points?.calculateTotalDistance() ?? 0;

    final completedPath = path.copyWith(
      status: TrackerPathStatus.completed,
      endedAt: DateTime.now().toIso8601String(),
      totalDistanceMeters: totalDistance,
    );

    final success = await _storage!.writePath(yr, completedPath);
    if (success) {
      _notifyChange('path', 'updated', id: pathId, data: completedPath);
      return completedPath;
    }
    return null;
  }

  /// Delete a path
  Future<bool> deletePath(String pathId, {int? year}) async {
    if (_storage == null) return false;

    final success = await _storage!.deletePath(year ?? DateTime.now().year, pathId);
    if (success) {
      _notifyChange('path', 'deleted', id: pathId);
    }
    return success;
  }

  /// Pause a path recording
  Future<TrackerPath?> pausePath(String pathId, {int? year}) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    final path = await _storage!.readPath(yr, pathId);
    if (path == null) return null;

    final pausedPath = path.copyWith(status: TrackerPathStatus.paused);
    final success = await _storage!.writePath(yr, pausedPath);
    if (success) {
      _notifyChange('path', 'updated', id: pathId, data: pausedPath);
      return pausedPath;
    }
    return null;
  }

  /// Resume a paused path recording
  Future<TrackerPath?> resumePath(String pathId, {int? year}) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    final path = await _storage!.readPath(yr, pathId);
    if (path == null) return null;

    final resumedPath = path.copyWith(status: TrackerPathStatus.recording);
    final success = await _storage!.writePath(yr, resumedPath);
    if (success) {
      _notifyChange('path', 'updated', id: pathId, data: resumedPath);
      return resumedPath;
    }
    return null;
  }

  // ============ Recording State Operations ============

  /// Get the current recording state (for crash recovery)
  Future<TrackerRecordingState?> getRecordingState() async {
    if (_storage == null) return null;
    return _storage!.readRecordingState();
  }

  /// Save the current recording state
  Future<bool> saveRecordingState(TrackerRecordingState state) async {
    if (_storage == null) return false;
    return _storage!.writeRecordingState(state);
  }

  /// Clear the recording state (after recording completes)
  Future<bool> clearRecordingState() async {
    if (_storage == null) return false;
    return _storage!.deleteRecordingState();
  }

  // ============ Measurement Operations ============

  /// List measurement types for a year
  Future<List<String>> listMeasurementTypes({int? year}) async {
    if (_storage == null) return [];
    return _storage!.listMeasurementTypes(year ?? DateTime.now().year);
  }

  /// Get measurement data for a type
  Future<MeasurementData?> getMeasurement(String typeId, {int? year}) async {
    if (_storage == null) return null;
    return _storage!.readMeasurement(year ?? DateTime.now().year, typeId);
  }

  /// Add a measurement entry
  Future<MeasurementEntry?> addMeasurementEntry({
    required String typeId,
    required double value,
    String? notes,
    List<String>? tags,
    int? year,
  }) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    var data = await _storage!.readMeasurement(yr, typeId);

    // Create new data file if it doesn't exist
    if (data == null) {
      final config = MeasurementTypeConfig.builtInTypes[typeId];
      if (config == null) return null;

      data = MeasurementData(
        typeId: typeId,
        year: yr,
        displayName: config.displayName,
        unit: config.unit,
      );
    }

    final entry = MeasurementEntry(
      id: 'm_${TrackerPathUtils.formatDateYYYYMMDD(DateTime.now())}_${_generateId()}',
      timestamp: DateTime.now().toIso8601String(),
      value: value,
      notes: notes,
      tags: tags ?? const [],
    );

    final updatedData = data.addEntry(entry);
    final success = await _storage!.writeMeasurement(yr, updatedData);

    if (success) {
      _notifyChange('measurement', 'created', id: typeId, data: entry);
      return entry;
    }
    return null;
  }

  /// Get blood pressure data
  Future<BloodPressureData?> getBloodPressure({int? year}) async {
    if (_storage == null) return null;
    return _storage!.readBloodPressure(year ?? DateTime.now().year);
  }

  /// Delete a measurement entry
  Future<bool> deleteMeasurementEntry(
    String typeId,
    String entryId, {
    int? year,
  }) async {
    if (_storage == null) return false;

    final yr = year ?? DateTime.now().year;
    final data = await _storage!.readMeasurement(yr, typeId);
    if (data == null) return false;

    final updatedData = data.removeEntry(entryId);
    final success = await _storage!.writeMeasurement(yr, updatedData);

    if (success) {
      _notifyChange('measurement', 'deleted', id: typeId);
    }
    return success;
  }

  /// Delete a blood pressure entry
  Future<bool> deleteBloodPressureEntry(String entryId, {int? year}) async {
    if (_storage == null) return false;

    final yr = year ?? DateTime.now().year;
    final data = await _storage!.readBloodPressure(yr);
    if (data == null) return false;

    final updatedData = data.removeEntry(entryId);
    final success = await _storage!.writeBloodPressure(yr, updatedData);

    if (success) {
      _notifyChange('blood_pressure', 'deleted');
    }
    return success;
  }

  /// Add a blood pressure entry
  Future<BloodPressureEntry?> addBloodPressureEntry({
    required int systolic,
    required int diastolic,
    int? heartRate,
    String? notes,
    List<String>? tags,
    int? year,
  }) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    var data = await _storage!.readBloodPressure(yr);

    // Create new data file if it doesn't exist
    data ??= BloodPressureData(year: yr);

    final entry = BloodPressureEntry(
      id: 'bp_${TrackerPathUtils.formatDateYYYYMMDD(DateTime.now())}_${_generateId()}',
      timestamp: DateTime.now().toIso8601String(),
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      notes: notes,
      tags: tags ?? const [],
    );

    final updatedData = data.addEntry(entry);
    final success = await _storage!.writeBloodPressure(yr, updatedData);

    if (success) {
      _notifyChange('blood_pressure', 'created', data: entry);
      return entry;
    }
    return null;
  }

  // ============ Exercise Operations ============

  /// List exercise types for a year
  Future<List<String>> listExerciseTypes({int? year}) async {
    if (_storage == null) return [];
    return _storage!.listExerciseTypes(year ?? DateTime.now().year);
  }

  /// Get exercise data for a type
  Future<ExerciseData?> getExercise(String exerciseId, {int? year}) async {
    if (_storage == null) return null;
    return _storage!.readExercise(year ?? DateTime.now().year, exerciseId);
  }

  /// Add an exercise entry
  Future<ExerciseEntry?> addExerciseEntry({
    required String exerciseId,
    required int count,
    int? durationSeconds,
    String? pathId,
    String? notes,
    List<String>? tags,
    int? year,
  }) async {
    if (_storage == null) return null;

    final yr = year ?? DateTime.now().year;
    var data = await _storage!.readExercise(yr, exerciseId);

    // Create new data file if it doesn't exist
    data ??= ExerciseData.fromType(exerciseId, yr);

    final entry = ExerciseEntry(
      id: 'e_${TrackerPathUtils.formatDateYYYYMMDD(DateTime.now())}_${_generateId()}',
      timestamp: DateTime.now().toIso8601String(),
      count: count,
      durationSeconds: durationSeconds,
      pathId: pathId,
      notes: notes,
      tags: tags ?? const [],
    );

    final updatedData = data.addEntry(entry);
    final success = await _storage!.writeExercise(yr, updatedData);

    if (success) {
      _notifyChange('exercise', 'created', id: exerciseId, data: entry);
      return entry;
    }
    return null;
  }

  /// Get today's count for an exercise
  Future<int> getExerciseTodayCount(String exerciseId, {int? year}) async {
    final data = await getExercise(exerciseId, year: year);
    if (data == null) return 0;
    return data.getTotalForDate(DateTime.now());
  }

  /// Get this week's count for an exercise
  Future<int> getExerciseWeekCount(String exerciseId, {int? year}) async {
    final data = await getExercise(exerciseId, year: year);
    if (data == null) return 0;
    return data.getTotalForCurrentWeek();
  }

  /// Delete an exercise entry
  Future<bool> deleteExerciseEntry(
    String exerciseId,
    String entryId, {
    int? year,
  }) async {
    if (_storage == null) return false;

    final yr = year ?? DateTime.now().year;
    final data = await _storage!.readExercise(yr, exerciseId);
    if (data == null) return false;

    final updatedData = data.removeEntry(entryId);
    final success = await _storage!.writeExercise(yr, updatedData);

    if (success) {
      _notifyChange('exercise', 'deleted', id: exerciseId);
    }
    return success;
  }

  // ============ Plan Operations ============

  /// List active plans
  Future<List<TrackerPlan>> listActivePlans() async {
    if (_storage == null) return [];
    return _storage!.listActivePlans();
  }

  /// List archived plans
  Future<List<ArchivedPlan>> listArchivedPlans() async {
    if (_storage == null) return [];
    return _storage!.listArchivedPlans();
  }

  /// Get an active plan
  Future<TrackerPlan?> getActivePlan(String planId) async {
    if (_storage == null) return null;
    return _storage!.readActivePlan(planId);
  }

  /// Create a new plan
  Future<TrackerPlan?> createPlan({
    required String title,
    String? description,
    required String startsAt,
    String? endsAt,
    List<PlanGoal>? goals,
  }) async {
    if (_storage == null) return null;

    final planId = _generateId();
    final plan = TrackerPlan(
      id: planId,
      title: title,
      description: description,
      status: TrackerPlanStatus.active,
      startsAt: startsAt,
      endsAt: endsAt,
      goals: goals ?? const [],
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    final success = await _storage!.writeActivePlan(plan);
    if (success) {
      _notifyChange('plan', 'created', id: planId, data: plan);
      return plan;
    }
    return null;
  }

  /// Update a plan
  Future<bool> updatePlan(TrackerPlan plan) async {
    if (_storage == null) return false;

    final updatedPlan = plan.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );

    final success = await _storage!.writeActivePlan(updatedPlan);
    if (success) {
      _notifyChange('plan', 'updated', id: plan.id, data: updatedPlan);
    }
    return success;
  }

  /// Archive a plan
  Future<bool> archivePlan(String planId, {PlanSummary? summary}) async {
    if (_storage == null) return false;

    final plan = await _storage!.readActivePlan(planId);
    if (plan == null) return false;

    final archivedPlan = ArchivedPlan.fromPlan(plan, summary);

    final archiveSuccess = await _storage!.writeArchivedPlan(archivedPlan);
    if (archiveSuccess) {
      await _storage!.deleteActivePlan(planId);
      _notifyChange('plan', 'archived', id: planId);
      return true;
    }
    return false;
  }

  // ============ Share Operations ============

  /// List group shares
  Future<List<GroupShare>> listGroupShares() async {
    if (_storage == null) return [];
    return _storage!.listGroupShares();
  }

  /// List temporary shares
  Future<List<TemporaryShare>> listTemporaryShares() async {
    if (_storage == null) return [];
    return _storage!.listTemporaryShares();
  }

  /// Create a group share
  Future<GroupShare?> createGroupShare({
    required String groupId,
    required String groupName,
    int updateIntervalSeconds = 300,
    ShareAccuracy accuracy = ShareAccuracy.approximate,
    List<ShareMember>? members,
  }) async {
    if (_storage == null || _ownerCallsign == null) return null;

    final now = DateTime.now();
    final shareId = groupId;

    final share = GroupShare(
      id: shareId,
      groupId: groupId,
      groupName: groupName,
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
      updateIntervalSeconds: updateIntervalSeconds,
      shareAccuracy: accuracy,
      members: members ?? const [],
      ownerCallsign: _ownerCallsign!,
    );

    final success = await _storage!.writeGroupShare(share);
    if (success) {
      _notifyChange('share', 'created', id: shareId, data: share);
      return share;
    }
    return null;
  }

  /// Create a temporary share
  Future<TemporaryShare?> createTemporaryShare({
    required int durationMinutes,
    required List<ShareRecipient> recipients,
    String? reason,
    int updateIntervalSeconds = 60,
    ShareAccuracy accuracy = ShareAccuracy.precise,
  }) async {
    if (_storage == null || _ownerCallsign == null) return null;

    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: durationMinutes));
    final shareId = '${TrackerPathUtils.formatDateYYYYMMDD(now)}_${_generateId()}';

    final share = TemporaryShare(
      id: shareId,
      recipients: recipients,
      createdAt: now.toIso8601String(),
      expiresAt: expiresAt.toIso8601String(),
      durationMinutes: durationMinutes,
      reason: reason,
      updateIntervalSeconds: updateIntervalSeconds,
      shareAccuracy: accuracy,
      ownerCallsign: _ownerCallsign!,
    );

    final success = await _storage!.writeTemporaryShare(share);
    if (success) {
      _notifyChange('temporary_share', 'created', id: shareId, data: share);
      return share;
    }
    return null;
  }

  // ============ Received Location Operations ============

  /// List received locations
  Future<List<ReceivedLocation>> listReceivedLocations() async {
    if (_storage == null) return [];
    return _storage!.listReceivedLocations();
  }

  /// Get received location for a callsign
  Future<ReceivedLocation?> getReceivedLocation(String callsign) async {
    if (_storage == null) return null;
    return _storage!.readReceivedLocation(callsign);
  }

  /// Update received location
  Future<bool> updateReceivedLocation(ReceivedLocation location) async {
    if (_storage == null) return false;

    final success = await _storage!.writeReceivedLocation(location);
    if (success) {
      _notifyChange('received_location', 'updated', id: location.callsign, data: location);
    }
    return success;
  }

  // ============ Proximity Operations ============

  /// Get today's proximity data
  Future<DailyProximityData?> getTodayProximity() async {
    if (_storage == null) return null;
    return _storage!.readProximity(DateTime.now());
  }

  /// Get proximity for a specific date
  Future<DailyProximityData?> getProximity(DateTime date) async {
    if (_storage == null) return null;
    return _storage!.readProximity(date);
  }

  /// List proximity dates for a year
  Future<List<DateTime>> listProximityDates({int? year}) async {
    if (_storage == null) return [];
    return _storage!.listProximityDates(year ?? DateTime.now().year);
  }

  /// Update proximity data
  Future<bool> updateProximity(DailyProximityData data) async {
    if (_storage == null) return false;

    final success = await _storage!.writeProximity(data);
    if (success) {
      _notifyChange('proximity', 'updated', data: data);
    }
    return success;
  }

  // ============ Visit Operations ============

  /// Get today's visits
  Future<DailyVisitsData?> getTodayVisits() async {
    if (_storage == null) return null;
    return _storage!.readVisits(DateTime.now());
  }

  /// Get visits for a specific date
  Future<DailyVisitsData?> getVisits(DateTime date) async {
    if (_storage == null) return null;
    return _storage!.readVisits(date);
  }

  /// List visit dates for a year
  Future<List<DateTime>> listVisitDates({int? year}) async {
    if (_storage == null) return [];
    return _storage!.listVisitDates(year ?? DateTime.now().year);
  }

  /// Get place statistics
  Future<PlaceStatsData?> getPlaceStats() async {
    if (_storage == null) return null;
    return _storage!.readPlaceStats();
  }

  /// Update visits
  Future<bool> updateVisits(DailyVisitsData data) async {
    if (_storage == null) return false;

    final success = await _storage!.writeVisits(data);
    if (success) {
      _notifyChange('visits', 'updated', data: data);
    }
    return success;
  }

  /// Add a visit
  Future<TrackerVisit?> addVisit({
    required String placeId,
    required String placeName,
    required double lat,
    required double lon,
    String? placeCategory,
    bool autoDetected = true,
    double? detectionAccuracyMeters,
  }) async {
    if (_storage == null || _ownerCallsign == null) return null;

    final now = DateTime.now();
    var data = await _storage!.readVisits(now);

    // Create new data file if it doesn't exist
    data ??= DailyVisitsData(
      date: TrackerPathUtils.formatDateISO(now),
      ownerCallsign: _ownerCallsign!,
    );

    final visit = TrackerVisit(
      id: 'visit_${TrackerPathUtils.formatDateYYYYMMDD(now)}_${_generateId()}',
      placeId: placeId,
      placeName: placeName,
      placeCategory: placeCategory,
      placeCoordinates: PlaceCoordinates(lat: lat, lon: lon),
      checkedInAt: now.toIso8601String(),
      autoDetected: autoDetected,
      detectionAccuracyMeters: detectionAccuracyMeters,
      status: 'checked_in',
    );

    final updatedData = data.addVisit(visit);
    final success = await _storage!.writeVisits(updatedData);

    if (success) {
      _notifyChange('visit', 'created', data: visit);
      return visit;
    }
    return null;
  }

  // ============ Helper Methods ============

  /// Notify listeners of a change
  void _notifyChange(String type, String action, {String? id, dynamic data}) {
    _changesController.add(TrackerChange(
      type: type,
      action: action,
      id: id,
      data: data,
    ));
  }

  /// Generate a short random ID
  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// Dispose resources
  void dispose() {
    _changesController.close();
  }
}
