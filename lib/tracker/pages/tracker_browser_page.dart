import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../models/trackable_type.dart';
import '../services/tracker_service.dart';
import '../services/path_recording_service.dart';
import '../dialogs/add_trackable_dialog.dart';
import '../dialogs/create_plan_dialog.dart';
import '../dialogs/start_path_dialog.dart';
import '../widgets/active_recording_banner.dart';
import 'path_detail_page.dart';
import 'exercise_detail_page.dart';
import 'measurement_detail_page.dart';
import 'plan_detail_page.dart';
import '../../services/i18n_service.dart';
import '../../services/config_service.dart';
import '../../services/profile_service.dart';

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

  /// Tabs sorted by most recently used
  List<TrackerTab> _sortedTabs = TrackerTab.values.toList();
  Map<String, int> _tabLastUsed = {}; // tab name -> timestamp

  /// User-selected trackables to show in each tab
  List<String> _visibleExercises = [];
  List<String> _visibleMeasurements = [];

  // Data for each tab
  List<TrackerPath> _paths = [];
  List<String> _exerciseTypes = [];
  List<String> _measurementTypes = [];
  Map<String, int> _weeklyTotals = {}; // Used for both exercises and measurements
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
    _loadTabUsage();
    _tabController = TabController(length: TrackerTab.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadVisibleTrackables();
    _initializeService();
  }

  // ============ Tab Usage Tracking (sort by most recently used) ============

  void _loadTabUsage() {
    final saved = _configService.getNestedValue('tracker.tabLastUsed');
    if (saved is Map) {
      _tabLastUsed = Map<String, int>.from(saved.map((k, v) => MapEntry(k.toString(), v as int)));
    }
    _sortTabs();
  }

  void _sortTabs() {
    _sortedTabs = TrackerTab.values.toList();
    _sortedTabs.sort((a, b) {
      final aTime = _tabLastUsed[a.name] ?? 0;
      final bTime = _tabLastUsed[b.name] ?? 0;
      return bTime.compareTo(aTime); // Most recent first
    });
  }

  void _recordTabUsage(TrackerTab tab) {
    _tabLastUsed[tab.name] = DateTime.now().millisecondsSinceEpoch;
    _configService.setNestedValue('tracker.tabLastUsed', _tabLastUsed);
    // Re-sort tabs for next time (don't reorder while user is viewing)
  }

  // ============ Visibility Management (unified for exercises & measurements) ============

  void _loadVisibleTrackables() {
    final savedExercises = _configService.getNestedValue('tracker.visibleExercises');
    if (savedExercises is List) {
      _visibleExercises = savedExercises.cast<String>().toList();
    }
    final savedMeasurements = _configService.getNestedValue('tracker.visibleMeasurements');
    if (savedMeasurements is List) {
      _visibleMeasurements = savedMeasurements.cast<String>().toList();
    }
  }

  List<String> _getVisibleList(TrackableKind kind) =>
      kind == TrackableKind.exercise ? _visibleExercises : _visibleMeasurements;

  void _saveVisibleList(TrackableKind kind) {
    final key = kind == TrackableKind.exercise
        ? 'tracker.visibleExercises'
        : 'tracker.visibleMeasurements';
    final list = _getVisibleList(kind);
    _configService.setNestedValue(key, list);
  }

  void _addToVisibleList(TrackableKind kind, String typeId) {
    final list = _getVisibleList(kind);
    if (!list.contains(typeId)) {
      setState(() => list.add(typeId));
      _saveVisibleList(kind);
      _loadCurrentTab(); // Reload to get weekly totals
    }
  }

  void _removeFromVisibleList(TrackableKind kind, String typeId) {
    final list = _getVisibleList(kind);
    setState(() => list.remove(typeId));
    _saveVisibleList(kind);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _changesSub?.cancel();
    _recordingService.removeListener(_onRecordingChanged);
    super.dispose();
  }

  Future<void> _initializeService() async {
    final profileCallsign = ProfileService().getProfile().callsign;
    final ownerCallsign =
        widget.ownerCallsign != null && widget.ownerCallsign!.isNotEmpty
            ? widget.ownerCallsign!
            : profileCallsign;

    await _service.initializeCollection(
      widget.collectionPath,
      callsign: ownerCallsign,
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
      _recordTabUsage(_currentTab);
      _loadCurrentTab();
    }
  }

  TrackerTab get _currentTab => _sortedTabs[_tabController.index];

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
          for (final typeId in _visibleExercises) {
            _weeklyTotals[typeId] = await _service.getExerciseWeekCount(
              typeId,
              year: _selectedYear,
            );
          }
          break;
        case TrackerTab.measurements:
          _measurementTypes = await _service.listMeasurementTypes(year: _selectedYear);
          // Load weekly totals for all visible measurements
          for (final typeId in _visibleMeasurements) {
            _weeklyTotals[typeId] = await _service.getMeasurementWeekCount(
              typeId,
              year: _selectedYear,
            );
          }
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
          tabs: _sortedTabs.map((tab) => _buildTab(tab)).toList(),
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
        children: _sortedTabs.map((tab) => _buildTabContent(tab)).toList(),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  bool get _showYearSelector {
    // Note: paths tab has its own recording flow, no year selector needed
    // Note: exercises/measurements tabs now use user-selected lists, no year filter needed
    return _currentTab == TrackerTab.proximity ||
        _currentTab == TrackerTab.visits;
  }

  Tab _buildTab(TrackerTab tab) {
    switch (tab) {
      case TrackerTab.paths:
        return Tab(icon: const Icon(Icons.route), text: widget.i18n.t('tracker_paths'));
      case TrackerTab.exercises:
        return Tab(icon: const Icon(Icons.fitness_center), text: widget.i18n.t('tracker_exercises'));
      case TrackerTab.measurements:
        return Tab(icon: const Icon(Icons.monitor_weight), text: widget.i18n.t('tracker_measurements'));
      case TrackerTab.plans:
        return Tab(icon: const Icon(Icons.flag), text: widget.i18n.t('tracker_plans'));
      case TrackerTab.proximity:
        return Tab(icon: const Icon(Icons.people), text: widget.i18n.t('tracker_proximity'));
      case TrackerTab.visits:
        return Tab(icon: const Icon(Icons.place), text: widget.i18n.t('tracker_visits'));
      case TrackerTab.sharing:
        return Tab(icon: const Icon(Icons.share_location), text: widget.i18n.t('tracker_sharing'));
    }
  }

  Widget _buildTabContent(TrackerTab tab) {
    switch (tab) {
      case TrackerTab.paths:
        return _buildPathsTab();
      case TrackerTab.exercises:
        return _buildTrackableTab(TrackableKind.exercise);
      case TrackerTab.measurements:
        return _buildTrackableTab(TrackableKind.measurement);
      case TrackerTab.plans:
        return _buildPlansTab();
      case TrackerTab.proximity:
        return _buildProximityTab();
      case TrackerTab.visits:
        return _buildVisitsTab();
      case TrackerTab.sharing:
        return _buildSharingTab();
    }
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
        onPressed = () => _showAddToListDialog(TrackableKind.exercise);
        break;
      case TrackerTab.measurements:
        icon = Icons.add;
        onPressed = () => _showAddToListDialog(TrackableKind.measurement);
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

  /// Unified tab builder for exercises and measurements
  Widget _buildTrackableTab(TrackableKind kind) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isExercise = kind == TrackableKind.exercise;
    final visibleList = _getVisibleList(kind);
    final typesWithData = isExercise ? _exerciseTypes : _measurementTypes;
    final availableTypes = isExercise
        ? TrackableTypeConfig.exerciseTypes
        : TrackableTypeConfig.measurementTypes;

    // Empty state
    final emptyMessage = isExercise
        ? 'tracker_no_visible_exercises'
        : 'tracker_no_visible_measurements';
    final addButtonLabel = isExercise
        ? 'tracker_add_exercise_to_list'
        : 'tracker_add_measurement_to_list';
    final emptyIcon = isExercise ? Icons.fitness_center : Icons.monitor_weight;

    if (visibleList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t(emptyMessage),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddToListDialog(kind),
              icon: const Icon(Icons.add),
              label: Text(widget.i18n.t(addButtonLabel)),
            ),
          ],
        ),
      );
    }

    final hideLabel = isExercise ? 'tracker_hide_exercise' : 'tracker_hide_measurement';
    final typePrefix = isExercise ? 'tracker_exercise_' : 'tracker_measurement_';

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: visibleList.length,
      itemBuilder: (context, index) {
        final typeId = visibleList[index];
        final config = availableTypes[typeId];
        if (config == null) return const SizedBox.shrink();

        final hasData = typesWithData.contains(typeId);

        return Card(
          child: ListTile(
            leading: Icon(
              _getTrackableIcon(kind, typeId, config.category),
              color: hasData ? Theme.of(context).primaryColor : Colors.grey,
            ),
            title: Text(widget.i18n.t('$typePrefix$typeId')),
            subtitle: Text('${_weeklyTotals[typeId] ?? 0} ${widget.i18n.t('tracker_this_week')}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: widget.i18n.t('tracker_log_entry'),
                  onPressed: () => _onAddEntry(kind, typeId),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'remove') {
                      _removeFromVisibleList(kind, typeId);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_off),
                          const SizedBox(width: 8),
                          Text(widget.i18n.t(hideLabel)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () => _onTrackableTapped(kind, typeId),
          ),
        );
      },
    );
  }

  /// Unified add-to-list dialog for exercises and measurements
  void _showAddToListDialog(TrackableKind kind) {
    final isExercise = kind == TrackableKind.exercise;
    final visibleList = _getVisibleList(kind);
    final availableTypes = isExercise
        ? TrackableTypeConfig.exerciseTypes
        : TrackableTypeConfig.measurementTypes;

    // Get types not yet in the visible list
    final availableIds = availableTypes.keys
        .where((id) => !visibleList.contains(id))
        .toList();

    final allAddedMessage = isExercise
        ? 'tracker_all_exercises_added'
        : 'tracker_all_measurements_added';
    final dialogTitle = isExercise
        ? 'tracker_add_exercise_to_list'
        : 'tracker_add_measurement_to_list';
    final typePrefix = isExercise ? 'tracker_exercise_' : 'tracker_measurement_';

    if (availableIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t(allAddedMessage))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t(dialogTitle)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableIds.length,
            itemBuilder: (context, index) {
              final typeId = availableIds[index];
              final config = availableTypes[typeId]!;

              return ListTile(
                leading: Icon(_getTrackableIcon(kind, typeId, config.category)),
                title: Text(widget.i18n.t('$typePrefix$typeId')),
                onTap: () {
                  _addToVisibleList(kind, typeId);
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

  /// Get icon for a trackable type
  IconData _getTrackableIcon(TrackableKind kind, String typeId, TrackableCategory category) {
    if (kind == TrackableKind.measurement) {
      // Measurements have type-specific icons
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
        case 'body_water':
          return Icons.water;
        case 'muscle_mass':
          return Icons.fitness_center;
        default:
          return Icons.straighten;
      }
    }
    // Exercises use category-based icons
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

  /// Unified add entry handler for exercises and measurements
  Future<void> _onAddEntry(TrackableKind kind, String typeId) async {
    final result = kind == TrackableKind.exercise
        ? await AddTrackableDialog.showExercise(
            context,
            service: _service,
            i18n: widget.i18n,
            preselectedTypeId: typeId,
            year: _selectedYear,
          )
        : await AddTrackableDialog.showMeasurement(
            context,
            service: _service,
            i18n: widget.i18n,
            preselectedTypeId: typeId,
            year: _selectedYear,
          );

    if (result == true) {
      _loadCurrentTab();
    }
  }

  /// Unified tap handler for exercises and measurements
  void _onTrackableTapped(TrackableKind kind, String typeId) {
    if (kind == TrackableKind.exercise) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ExerciseDetailPage(
            service: _service,
            i18n: widget.i18n,
            exerciseId: typeId,
            year: _selectedYear,
          ),
        ),
      );
    } else {
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
  }

  Future<void> _onAddPlan() async {
    final result = await CreatePlanDialog.show(
      context,
      service: _service,
      i18n: widget.i18n,
    );

    if (result == true) {
      _loadCurrentTab();
    }
  }

  void _onAddShare() {
    // TODO: Show dialog to create new share
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.i18n.t('tracker_add_share_coming_soon'))),
    );
  }

  void _onPathTapped(TrackerPath path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PathDetailPage(
          service: _service,
          i18n: widget.i18n,
          path: path,
          year: _selectedYear,
        ),
      ),
    );
  }

  void _onPlanTapped(TrackerPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PlanDetailPage(
          service: _service,
          i18n: widget.i18n,
          planId: plan.id,
        ),
      ),
    );
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
