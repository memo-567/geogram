import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../models/trackable_type.dart';
import '../services/tracker_service.dart';
import '../services/path_recording_service.dart';
import '../dialogs/add_trackable_dialog.dart';
import '../dialogs/start_path_dialog.dart';
import '../widgets/active_recording_banner.dart';
import 'exercise_detail_page.dart';
import 'measurement_detail_page.dart';
import '../../services/i18n_service.dart';
import '../../services/config_service.dart';

/// Tab type for the tracker browser
enum TrackerTab {
  paths,
  exercises,
  measurements,
  plans,
  proximity,
  visits,
  sharing,
}

/// Main tracker browser page with tabbed layout
class TrackerBrowserPage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;
  final I18nService i18n;
  final String? ownerCallsign;

  const TrackerBrowserPage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
    required this.i18n,
    this.ownerCallsign,
  });

  @override
  State<TrackerBrowserPage> createState() => _TrackerBrowserPageState();
}

class _TrackerBrowserPageState extends State<TrackerBrowserPage>
    with SingleTickerProviderStateMixin {
  final TrackerService _service = TrackerService();
  final PathRecordingService _recordingService = PathRecordingService();
  final ConfigService _configService = ConfigService();

  late TabController _tabController;
  bool _loading = true;
  StreamSubscription? _changesSub;

  /// User-selected exercises to show in the exercises tab
  List<String> _visibleExercises = [];

  // Data for each tab
  List<TrackerPath> _paths = [];
  List<String> _exerciseTypes = [];
  Map<String, int> _weeklyTotals = {};
  List<String> _measurementTypes = [];
  List<TrackerPlan> _activePlans = [];
  List<DateTime> _proximityDates = [];
  List<DateTime> _visitDates = [];
  List<GroupShare> _groupShares = [];
  List<TemporaryShare> _temporaryShares = [];
  List<ReceivedLocation> _receivedLocations = [];

  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: TrackerTab.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadVisibleExercises();
    _initializeService();
  }

  void _loadVisibleExercises() {
    final saved = _configService.getNestedValue('tracker.visibleExercises');
    if (saved is List) {
      _visibleExercises = saved.cast<String>().toList();
    }
  }

  void _saveVisibleExercises() {
    _configService.setNestedValue('tracker.visibleExercises', _visibleExercises);
  }

  void _addExerciseToVisible(String exerciseId) {
    if (!_visibleExercises.contains(exerciseId)) {
      setState(() {
        _visibleExercises.add(exerciseId);
      });
      _saveVisibleExercises();
    }
  }

  void _removeExerciseFromVisible(String exerciseId) {
    setState(() {
      _visibleExercises.remove(exerciseId);
    });
    _saveVisibleExercises();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _changesSub?.cancel();
    _recordingService.removeListener(_onRecordingChanged);
    super.dispose();
  }

  Future<void> _initializeService() async {
    await _service.initializeCollection(
      widget.collectionPath,
      callsign: widget.ownerCallsign,
    );
    _changesSub = _service.changes.listen(_onTrackerChange);

    // Initialize recording service and check for any active recording
    _recordingService.initialize(_service);
    _recordingService.addListener(_onRecordingChanged);
    await _recordingService.checkAndResumeRecording();

    await _loadCurrentTab();
  }

  void _onTrackerChange(TrackerChange change) {
    _loadCurrentTab();
  }

  void _onRecordingChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _loadCurrentTab();
    }
  }

  TrackerTab get _currentTab => TrackerTab.values[_tabController.index];

  Future<void> _loadCurrentTab() async {
    setState(() => _loading = true);

    try {
      switch (_currentTab) {
        case TrackerTab.paths:
          _paths = await _service.listPaths(year: _selectedYear);
          break;
        case TrackerTab.exercises:
          _exerciseTypes = await _service.listExerciseTypes(year: _selectedYear);
          // Load weekly totals for all visible exercises
          _weeklyTotals = {};
          for (final exerciseId in _visibleExercises) {
            _weeklyTotals[exerciseId] = await _service.getExerciseWeekCount(
              exerciseId,
              year: _selectedYear,
            );
          }
          break;
        case TrackerTab.measurements:
          _measurementTypes = await _service.listMeasurementTypes(year: _selectedYear);
          break;
        case TrackerTab.plans:
          _activePlans = await _service.listActivePlans();
          break;
        case TrackerTab.proximity:
          _proximityDates = await _service.listProximityDates(year: _selectedYear);
          break;
        case TrackerTab.visits:
          _visitDates = await _service.listVisitDates(year: _selectedYear);
          break;
        case TrackerTab.sharing:
          _groupShares = await _service.listGroupShares();
          _temporaryShares = await _service.listTemporaryShares();
          _receivedLocations = await _service.listReceivedLocations();
          break;
      }
    } catch (e) {
      // Handle errors silently, data will be empty
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _getDisplayTitle() {
    if (widget.collectionTitle.startsWith('collection_type_')) {
      return widget.i18n.t(widget.collectionTitle);
    }
    return widget.collectionTitle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getDisplayTitle()),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.route), text: widget.i18n.t('tracker_paths')),
            Tab(icon: const Icon(Icons.fitness_center), text: widget.i18n.t('tracker_exercises')),
            Tab(icon: const Icon(Icons.monitor_weight), text: widget.i18n.t('tracker_measurements')),
            Tab(icon: const Icon(Icons.flag), text: widget.i18n.t('tracker_plans')),
            Tab(icon: const Icon(Icons.people), text: widget.i18n.t('tracker_proximity')),
            Tab(icon: const Icon(Icons.place), text: widget.i18n.t('tracker_visits')),
            Tab(icon: const Icon(Icons.share_location), text: widget.i18n.t('tracker_sharing')),
          ],
        ),
        actions: [
          if (_showYearSelector)
            PopupMenuButton<int>(
              initialValue: _selectedYear,
              onSelected: (year) {
                setState(() => _selectedYear = year);
                _loadCurrentTab();
              },
              itemBuilder: (context) {
                final currentYear = DateTime.now().year;
                return List.generate(5, (i) => currentYear - i)
                    .map((year) => PopupMenuItem(
                          value: year,
                          child: Text(year.toString()),
                        ))
                    .toList();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedYear.toString()),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPathsTab(),
          _buildExercisesTab(),
          _buildMeasurementsTab(),
          _buildPlansTab(),
          _buildProximityTab(),
          _buildVisitsTab(),
          _buildSharingTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  bool get _showYearSelector {
    // Note: paths tab has its own recording flow, no year selector needed
    // Note: exercises tab now uses user-selected list, no year filter needed
    return _currentTab == TrackerTab.measurements ||
        _currentTab == TrackerTab.proximity ||
        _currentTab == TrackerTab.visits;
  }

  Widget? _buildFab() {
    IconData icon;
    VoidCallback? onPressed;

    switch (_currentTab) {
      case TrackerTab.paths:
        icon = Icons.add_location_alt;
        onPressed = _onAddPath;
        break;
      case TrackerTab.exercises:
        icon = Icons.add;
        onPressed = _showAddExerciseToListDialog;
        break;
      case TrackerTab.measurements:
        icon = Icons.add;
        onPressed = _onAddMeasurement;
        break;
      case TrackerTab.plans:
        icon = Icons.add;
        onPressed = _onAddPlan;
        break;
      case TrackerTab.sharing:
        icon = Icons.share;
        onPressed = _onAddShare;
        break;
      default:
        return null;
    }

    return FloatingActionButton(
      onPressed: onPressed,
      child: Icon(icon),
    );
  }

  // ============ Tab Content Builders ============

  Widget _buildPathsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Active recording banner
        if (_recordingService.hasActiveRecording)
          ActiveRecordingBanner(
            recordingService: _recordingService,
            i18n: widget.i18n,
            onStop: _loadCurrentTab,
          ),

        // Path list
        Expanded(
          child: _paths.isEmpty && !_recordingService.hasActiveRecording
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.route, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        widget.i18n.t('tracker_no_paths'),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _paths.length,
                  itemBuilder: (context, index) {
                    final path = _paths[index];
                    final pathType = TrackerPathType.fromTags(path.tags);

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          pathType?.icon ?? Icons.route,
                          color: path.status == TrackerPathStatus.recording
                              ? Colors.red
                              : null,
                        ),
                        title: Text(path.title ?? path.id),
                        subtitle: Text(
                          '${path.totalPoints} ${widget.i18n.t('tracker_points')} - '
                          '${_formatDistance(path.totalDistanceMeters)}',
                        ),
                        trailing: path.status == TrackerPathStatus.recording
                            ? const Icon(Icons.fiber_manual_record, color: Colors.red)
                            : null,
                        onTap: () => _onPathTapped(path),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExercisesTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show only user-selected exercises (clean slate by default)
    if (_visibleExercises.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('tracker_no_visible_exercises'),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddExerciseToListDialog,
              icon: const Icon(Icons.add),
              label: Text(widget.i18n.t('tracker_add_exercise_to_list')),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _visibleExercises.length,
      itemBuilder: (context, index) {
        final exerciseId = _visibleExercises[index];
        final config = TrackableTypeConfig.exerciseTypes[exerciseId];
        if (config == null) return const SizedBox.shrink();

        final hasData = _exerciseTypes.contains(exerciseId);

        return Card(
          child: ListTile(
            leading: Icon(
              _getExerciseIcon(config.category),
              color: hasData ? Theme.of(context).primaryColor : Colors.grey,
            ),
            title: Text(widget.i18n.t('tracker_exercise_$exerciseId')),
            subtitle: Text('${_weeklyTotals[exerciseId] ?? 0} ${widget.i18n.t('tracker_this_week')}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: widget.i18n.t('tracker_log_entry'),
                  onPressed: () => _onAddExerciseEntry(exerciseId),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'remove') {
                      _removeExerciseFromVisible(exerciseId);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_off),
                          const SizedBox(width: 8),
                          Text(widget.i18n.t('tracker_hide_exercise')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () => _onExerciseTapped(exerciseId),
          ),
        );
      },
    );
  }

  void _showAddExerciseToListDialog() {
    // Get exercises not yet in the visible list
    final availableExercises = TrackableTypeConfig.exerciseTypes.keys
        .where((id) => !_visibleExercises.contains(id))
        .toList();

    if (availableExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('tracker_all_exercises_added'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('tracker_add_exercise_to_list')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableExercises.length,
            itemBuilder: (context, index) {
              final exerciseId = availableExercises[index];
              final config = TrackableTypeConfig.exerciseTypes[exerciseId]!;

              return ListTile(
                leading: Icon(_getExerciseIcon(config.category)),
                title: Text(widget.i18n.t('tracker_exercise_$exerciseId')),
                onTap: () {
                  _addExerciseToVisible(exerciseId);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.i18n.t('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show all built-in measurement types, mark those with data
    final allTypes = TrackableTypeConfig.measurementTypes.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: allTypes.length,
      itemBuilder: (context, index) {
        final typeId = allTypes[index];
        final config = TrackableTypeConfig.measurementTypes[typeId]!;
        final hasData = _measurementTypes.contains(typeId);

        return Card(
          child: ListTile(
            leading: Icon(
              _getMeasurementIcon(typeId),
              color: hasData ? Theme.of(context).primaryColor : Colors.grey,
            ),
            title: Text(widget.i18n.t('tracker_measurement_$typeId')),
            subtitle: Text(config.unit),
            trailing: hasData
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            onTap: () => _onMeasurementTapped(typeId),
          ),
        );
      },
    );
  }

  Widget _buildPlansTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activePlans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('tracker_no_plans'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _activePlans.length,
      itemBuilder: (context, index) {
        final plan = _activePlans[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.flag),
            title: Text(plan.title),
            subtitle: Text('${plan.goals.length} ${widget.i18n.t('tracker_goals')}'),
            trailing: plan.status == TrackerPlanStatus.active
                ? const Icon(Icons.play_circle, color: Colors.green)
                : null,
            onTap: () => _onPlanTapped(plan),
          ),
        );
      },
    );
  }

  Widget _buildProximityTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_proximityDates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('tracker_no_proximity'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _proximityDates.length,
      itemBuilder: (context, index) {
        final date = _proximityDates[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.people),
            title: Text(_formatDate(date)),
            onTap: () => _onProximityDateTapped(date),
          ),
        );
      },
    );
  }

  Widget _buildVisitsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_visitDates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.place, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('tracker_no_visits'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _visitDates.length,
      itemBuilder: (context, index) {
        final date = _visitDates[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.place),
            title: Text(_formatDate(date)),
            onTap: () => _onVisitDateTapped(date),
          ),
        );
      },
    );
  }

  Widget _buildSharingTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Shares
          _buildSectionHeader(widget.i18n.t('tracker_group_shares')),
          if (_groupShares.isEmpty)
            _buildEmptySection(widget.i18n.t('tracker_no_group_shares'))
          else
            ..._groupShares.map((share) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.group),
                    title: Text(share.groupName),
                    subtitle: Text(
                      '${share.members.length} ${widget.i18n.t('tracker_members')} - '
                      '${share.active ? widget.i18n.t('tracker_active') : widget.i18n.t('tracker_inactive')}',
                    ),
                    trailing: Switch(
                      value: share.active,
                      onChanged: (value) => _onShareToggle(share, value),
                    ),
                  ),
                )),

          const SizedBox(height: 24),

          // Temporary Shares
          _buildSectionHeader(widget.i18n.t('tracker_temporary_shares')),
          if (_temporaryShares.isEmpty)
            _buildEmptySection(widget.i18n.t('tracker_no_temporary_shares'))
          else
            ..._temporaryShares.map((share) => Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.timer,
                      color: share.hasExpired ? Colors.grey : Colors.orange,
                    ),
                    title: Text(share.reason ?? widget.i18n.t('tracker_temporary_share')),
                    subtitle: Text(
                      share.hasExpired
                          ? widget.i18n.t('tracker_expired')
                          : '${widget.i18n.t('tracker_expires')}: ${_formatDateTime(share.expiresAtDateTime)}',
                    ),
                  ),
                )),

          const SizedBox(height: 24),

          // Received Locations
          _buildSectionHeader(widget.i18n.t('tracker_received_locations')),
          if (_receivedLocations.isEmpty)
            _buildEmptySection(widget.i18n.t('tracker_no_received_locations'))
          else
            ..._receivedLocations.map((location) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_pin_circle),
                    title: Text(location.displayName ?? location.callsign),
                    subtitle: Text(
                      '${widget.i18n.t('tracker_last_update')}: ${location.lastUpdate}',
                    ),
                    onTap: () => _onReceivedLocationTapped(location),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildEmptySection(String message) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  // ============ Helper Methods ============

  IconData _getExerciseIcon(TrackableCategory category) {
    switch (category) {
      case TrackableCategory.strength:
        return Icons.fitness_center;
      case TrackableCategory.cardio:
        return Icons.directions_run;
      case TrackableCategory.flexibility:
        return Icons.self_improvement;
      case TrackableCategory.health:
        return Icons.favorite;
    }
  }

  IconData _getMeasurementIcon(String typeId) {
    switch (typeId) {
      case 'weight':
        return Icons.monitor_weight;
      case 'height':
        return Icons.height;
      case 'blood_pressure':
        return Icons.favorite;
      case 'heart_rate':
        return Icons.monitor_heart;
      case 'blood_glucose':
        return Icons.water_drop;
      case 'body_fat':
        return Icons.percent;
      case 'body_temperature':
        return Icons.thermostat;
      default:
        return Icons.straighten;
    }
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toInt()} m';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // ============ Action Handlers ============

  Future<void> _onAddPath() async {
    // Don't allow starting a new recording if one is already active
    if (_recordingService.hasActiveRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('tracker_recording_in_progress'))),
      );
      return;
    }

    final path = await StartPathDialog.show(
      context,
      recordingService: _recordingService,
      i18n: widget.i18n,
    );

    if (path != null) {
      // Recording started successfully
      _loadCurrentTab();
    }
  }

  Future<void> _onAddExerciseEntry(String exerciseId) async {
    final result = await AddTrackableDialog.showExercise(
      context,
      service: _service,
      i18n: widget.i18n,
      preselectedTypeId: exerciseId,
      year: _selectedYear,
    );

    if (result == true) {
      _loadCurrentTab();
    }
  }

  Future<void> _onAddMeasurement() async {
    final result = await AddTrackableDialog.showMeasurement(
      context,
      service: _service,
      i18n: widget.i18n,
      year: _selectedYear,
    );

    if (result == true) {
      _loadCurrentTab();
    }
  }

  void _onAddPlan() {
    // TODO: Show dialog to create new plan
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.i18n.t('tracker_add_plan_coming_soon'))),
    );
  }

  void _onAddShare() {
    // TODO: Show dialog to create new share
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.i18n.t('tracker_add_share_coming_soon'))),
    );
  }

  void _onPathTapped(TrackerPath path) {
    // TODO: Navigate to path detail page
  }

  void _onExerciseTapped(String exerciseId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExerciseDetailPage(
          service: _service,
          i18n: widget.i18n,
          exerciseId: exerciseId,
          year: _selectedYear,
        ),
      ),
    );
  }

  void _onMeasurementTapped(String typeId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MeasurementDetailPage(
          service: _service,
          i18n: widget.i18n,
          typeId: typeId,
          year: _selectedYear,
        ),
      ),
    );
  }

  void _onPlanTapped(TrackerPlan plan) {
    // TODO: Navigate to plan detail page
  }

  void _onProximityDateTapped(DateTime date) {
    // TODO: Navigate to proximity detail page
  }

  void _onVisitDateTapped(DateTime date) {
    // TODO: Navigate to visit detail page
  }

  void _onReceivedLocationTapped(ReceivedLocation location) {
    // TODO: Navigate to location detail or show on map
  }

  void _onShareToggle(GroupShare share, bool active) {
    // TODO: Toggle share active state
  }
}
