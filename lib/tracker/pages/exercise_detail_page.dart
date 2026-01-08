import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../dialogs/add_exercise_dialog.dart';
import '../../services/i18n_service.dart';

/// Detail page for viewing exercise entries and statistics
class ExerciseDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final String exerciseId;
  final int year;

  const ExerciseDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.exerciseId,
    required this.year,
  });

  @override
  State<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends State<ExerciseDetailPage> {
  ExerciseData? _data;
  bool _loading = true;
  StreamSubscription? _changesSub;

  ExerciseTypeConfig? get _config =>
      ExerciseTypeConfig.builtInTypes[widget.exerciseId];

  @override
  void initState() {
    super.initState();
    _changesSub = widget.service.changes.listen(_onTrackerChange);
    _loadData();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  void _onTrackerChange(TrackerChange change) {
    if (change.type == 'exercise') {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      _data = await widget.service.getExercise(
        widget.exerciseId,
        year: widget.year,
      );
    } catch (e) {
      // Handle errors silently
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('tracker_exercise_${widget.exerciseId}')),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectYear,
            tooltip: widget.i18n.t('tracker_select_year'),
          ),
        ],
      ),
      body: _loading ? _buildLoading() : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildContent() {
    final data = _data;
    final config = _config;

    if (data == null || data.entries.isEmpty) {
      return _buildEmptyState();
    }

    // Sort entries by timestamp, newest first
    final sortedEntries = List<ExerciseEntry>.from(data.entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return CustomScrollView(
      slivers: [
        // Statistics header
        SliverToBoxAdapter(
          child: _buildStatisticsCard(data, config),
        ),

        // Goal progress (if set)
        if (data.goal != null)
          SliverToBoxAdapter(
            child: _buildGoalCard(data),
          ),

        // Entries list header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              widget.i18n.t('tracker_entries'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),

        // Entries list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildEntryTile(sortedEntries[index], config),
            childCount: sortedEntries.length,
          ),
        ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 80),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getExerciseIcon(_config?.category ?? ExerciseCategory.strength),
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            widget.i18n.t('tracker_no_exercise_entries'),
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addEntry,
            icon: const Icon(Icons.add),
            label: Text(widget.i18n.t('tracker_add_first_entry')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(ExerciseData data, ExerciseTypeConfig? config) {
    final stats = data.statistics ?? ExerciseStatistics.calculate(data.entries);
    final todayTotal = data.getTotalForDate(DateTime.now());
    final weekTotal = data.getTotalForCurrentWeek();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_statistics'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_today'),
                    _formatCount(todayTotal, config),
                    Icons.today,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_this_week'),
                    _formatCount(weekTotal, config),
                    Icons.date_range,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_year_total'),
                    _formatCount(stats.totalCount, config),
                    Icons.calendar_month,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_sessions'),
                    stats.totalEntries.toString(),
                    Icons.fitness_center,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildGoalCard(ExerciseData data) {
    final goal = data.goal!;
    final todayTotal = data.getTotalForDate(DateTime.now());
    final weekTotal = data.getTotalForCurrentWeek();

    final dailyProgress = goal.dailyTarget != null
        ? (todayTotal / goal.dailyTarget!).clamp(0.0, 1.0)
        : null;
    final weeklyProgress = goal.weeklyTarget != null
        ? (weekTotal / goal.weeklyTarget!).clamp(0.0, 1.0)
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_goals'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (dailyProgress != null) ...[
              _buildGoalProgress(
                widget.i18n.t('tracker_daily_goal'),
                '$todayTotal / ${goal.dailyTarget}',
                dailyProgress,
              ),
              const SizedBox(height: 12),
            ],
            if (weeklyProgress != null)
              _buildGoalProgress(
                widget.i18n.t('tracker_weekly_goal'),
                '$weekTotal / ${goal.weeklyTarget}',
                weeklyProgress,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalProgress(String label, String valueText, double progress) {
    final isComplete = progress >= 1.0;
    final color = isComplete ? Colors.green : Theme.of(context).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valueText),
                if (isComplete) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ],
    );
  }

  Widget _buildEntryTile(ExerciseEntry entry, ExerciseTypeConfig? config) {
    final dateTime = entry.timestampDateTime;
    final dateStr = _formatDate(dateTime);
    final timeStr = _formatTime(dateTime);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) => _confirmDelete(entry),
      onDismissed: (direction) => _deleteEntry(entry),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: Icon(
            _getExerciseIcon(config?.category ?? ExerciseCategory.strength),
            color: Theme.of(context).primaryColor,
          ),
        ),
        title: Text(_formatCount(entry.count, config)),
        subtitle: Text('$dateStr $timeStr'),
        trailing: entry.durationSeconds != null
            ? Text(_formatDuration(entry.durationSeconds!))
            : null,
        onTap: () => _showEntryDetails(entry),
      ),
    );
  }

  Future<bool?> _confirmDelete(ExerciseEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('tracker_delete_entry')),
        content: Text(widget.i18n.t('tracker_delete_entry_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.i18n.t('delete')),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(ExerciseEntry entry) async {
    try {
      await widget.service.deleteExerciseEntry(
        widget.exerciseId,
        entry.id,
        year: widget.year,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showEntryDetails(ExerciseEntry entry) {
    final config = _config;
    final dateTime = entry.timestampDateTime;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_exercise_${widget.exerciseId}'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              widget.i18n.t('tracker_count'),
              _formatCount(entry.count, config),
            ),
            _buildDetailRow(
              widget.i18n.t('tracker_date'),
              _formatDate(dateTime),
            ),
            _buildDetailRow(
              widget.i18n.t('tracker_time'),
              _formatTime(dateTime),
            ),
            if (entry.durationSeconds != null)
              _buildDetailRow(
                widget.i18n.t('tracker_duration'),
                _formatDuration(entry.durationSeconds!),
              ),
            if (entry.notes != null && entry.notes!.isNotEmpty)
              _buildDetailRow(
                widget.i18n.t('tracker_notes'),
                entry.notes!,
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _addEntry() async {
    final result = await AddExerciseDialog.show(
      context,
      service: widget.service,
      i18n: widget.i18n,
      preselectedExerciseId: widget.exerciseId,
      year: widget.year,
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _selectYear() async {
    final currentYear = DateTime.now().year;
    final years = List.generate(10, (i) => currentYear - i);

    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(widget.i18n.t('tracker_select_year')),
        children: years
            .map((year) => SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(year),
                  child: Text(
                    year.toString(),
                    style: TextStyle(
                      fontWeight:
                          year == widget.year ? FontWeight.bold : null,
                    ),
                  ),
                ))
            .toList(),
      ),
    );

    if (selected != null && selected != widget.year && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ExerciseDetailPage(
            service: widget.service,
            i18n: widget.i18n,
            exerciseId: widget.exerciseId,
            year: selected,
          ),
        ),
      );
    }
  }

  IconData _getExerciseIcon(ExerciseCategory category) {
    switch (category) {
      case ExerciseCategory.strength:
        return Icons.fitness_center;
      case ExerciseCategory.cardio:
        return Icons.directions_run;
      case ExerciseCategory.flexibility:
        return Icons.self_improvement;
    }
  }

  String _formatCount(int count, ExerciseTypeConfig? config) {
    if (config == null) return count.toString();

    switch (config.unit) {
      case 'meters':
        if (count >= 1000) {
          return '${(count / 1000).toStringAsFixed(1)} km';
        }
        return '$count m';
      case 'seconds':
        return _formatDuration(count);
      default:
        return '$count ${config.unit}';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (secs == 0) return '${minutes}m';
    return '${minutes}m ${secs}s';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
