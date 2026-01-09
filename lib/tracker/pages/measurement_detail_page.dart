import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../dialogs/add_trackable_dialog.dart';
import '../../services/i18n_service.dart';

/// Detail page for viewing measurement entries and statistics
class MeasurementDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final String typeId;
  final int year;

  const MeasurementDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.typeId,
    required this.year,
  });

  @override
  State<MeasurementDetailPage> createState() => _MeasurementDetailPageState();
}

class _MeasurementDetailPageState extends State<MeasurementDetailPage> {
  MeasurementData? _data;
  BloodPressureData? _bpData;
  bool _loading = true;
  StreamSubscription? _changesSub;

  bool get _isBloodPressure => widget.typeId == 'blood_pressure';

  MeasurementTypeConfig? get _config =>
      MeasurementTypeConfig.builtInTypes[widget.typeId];

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
    if (change.type == 'measurement' || change.type == 'blood_pressure') {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      if (_isBloodPressure) {
        _bpData = await widget.service.getBloodPressure(year: widget.year);
      } else {
        _data = await widget.service.getMeasurement(
          widget.typeId,
          year: widget.year,
        );
      }
    } catch (e) {
      // Handle errors silently
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isBloodPressure
        ? widget.i18n.t('tracker_blood_pressure')
        : widget.i18n.t('tracker_measurement_${widget.typeId}');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
    if (_isBloodPressure) {
      return _buildBloodPressureContent();
    }
    return _buildMeasurementContent();
  }

  Widget _buildMeasurementContent() {
    final data = _data;

    if (data == null || data.entries.isEmpty) {
      return _buildEmptyState();
    }

    // Sort entries by timestamp, newest first
    final sortedEntries = List<MeasurementEntry>.from(data.entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return CustomScrollView(
      slivers: [
        // Statistics header
        SliverToBoxAdapter(
          child: _buildMeasurementStatisticsCard(data),
        ),

        // Goal progress (if set)
        if (data.goal != null)
          SliverToBoxAdapter(
            child: _buildMeasurementGoalCard(data),
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
            (context, index) => _buildMeasurementEntryTile(sortedEntries[index]),
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

  Widget _buildBloodPressureContent() {
    final data = _bpData;

    if (data == null || data.entries.isEmpty) {
      return _buildEmptyState();
    }

    // Sort entries by timestamp, newest first
    final sortedEntries = List<BloodPressureEntry>.from(data.entries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return CustomScrollView(
      slivers: [
        // Statistics header
        SliverToBoxAdapter(
          child: _buildBloodPressureStatisticsCard(sortedEntries),
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
            (context, index) => _buildBloodPressureEntryTile(sortedEntries[index]),
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
            _getMeasurementIcon(widget.typeId),
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            widget.i18n.t('tracker_no_measurement_entries'),
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

  Widget _buildMeasurementStatisticsCard(MeasurementData data) {
    final stats = data.statistics ?? MeasurementStatistics.calculate(data.entries);
    final unit = _config?.unit ?? data.unit;
    final decimalPlaces = _config?.decimalPlaces ?? data.decimalPlaces;

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
                    widget.i18n.t('tracker_latest'),
                    data.entries.isNotEmpty
                        ? '${data.entries.last.value.toStringAsFixed(decimalPlaces)} $unit'
                        : '-',
                    Icons.schedule,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_average'),
                    '${stats.avg.toStringAsFixed(decimalPlaces)} $unit',
                    Icons.analytics,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_min'),
                    '${stats.min.toStringAsFixed(decimalPlaces)} $unit',
                    Icons.arrow_downward,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_max'),
                    '${stats.max.toStringAsFixed(decimalPlaces)} $unit',
                    Icons.arrow_upward,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${stats.count} ${widget.i18n.t('tracker_entries').toLowerCase()}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodPressureStatisticsCard(List<BloodPressureEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final systolicValues = entries.map((e) => e.systolic).toList()..sort();
    final diastolicValues = entries.map((e) => e.diastolic).toList()..sort();

    final avgSystolic = systolicValues.fold<int>(0, (a, b) => a + b) / entries.length;
    final avgDiastolic = diastolicValues.fold<int>(0, (a, b) => a + b) / entries.length;

    final latest = entries.first;

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
                    widget.i18n.t('tracker_latest'),
                    latest.displayValue,
                    Icons.schedule,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_average'),
                    '${avgSystolic.round()}/${avgDiastolic.round()}',
                    Icons.analytics,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_systolic_range'),
                    '${systolicValues.first}-${systolicValues.last}',
                    Icons.favorite,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    widget.i18n.t('tracker_diastolic_range'),
                    '${diastolicValues.first}-${diastolicValues.last}',
                    Icons.favorite_border,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${entries.length} ${widget.i18n.t('tracker_entries').toLowerCase()}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementGoalCard(MeasurementData data) {
    final goal = data.goal!;
    final latestValue = data.entries.isNotEmpty ? data.entries.last.value : 0.0;
    final unit = _config?.unit ?? data.unit;

    // Calculate progress based on direction
    double progress;
    bool isComplete;
    if (goal.direction == 'decrease') {
      progress = latestValue <= goal.targetValue
          ? 1.0
          : (data.entries.first.value - latestValue) /
              (data.entries.first.value - goal.targetValue);
      isComplete = latestValue <= goal.targetValue;
    } else if (goal.direction == 'increase') {
      progress = latestValue >= goal.targetValue
          ? 1.0
          : latestValue / goal.targetValue;
      isComplete = latestValue >= goal.targetValue;
    } else {
      // maintain
      final diff = (latestValue - goal.targetValue).abs();
      final tolerance = goal.targetValue * 0.05; // 5% tolerance
      progress = diff <= tolerance ? 1.0 : 1.0 - (diff / goal.targetValue);
      isComplete = diff <= tolerance;
    }
    progress = progress.clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_goal'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildGoalProgress(
              '${widget.i18n.t('tracker_target')}: ${goal.targetValue} $unit',
              '${widget.i18n.t('tracker_current')}: ${latestValue.toStringAsFixed(1)} $unit',
              progress,
              isComplete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalProgress(
    String label,
    String valueText,
    double progress,
    bool isComplete,
  ) {
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

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

  Widget _buildMeasurementEntryTile(MeasurementEntry entry) {
    final dateTime = entry.timestampDateTime;
    final dateStr = _formatDate(dateTime);
    final timeStr = _formatTime(dateTime);
    final unit = _config?.unit ?? _data?.unit ?? '';
    final decimalPlaces = _config?.decimalPlaces ?? _data?.decimalPlaces ?? 1;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        child: Icon(
          _getMeasurementIcon(widget.typeId),
          color: Theme.of(context).primaryColor,
        ),
      ),
      title: Text('${entry.value.toStringAsFixed(decimalPlaces)} $unit'),
      subtitle: Text('$dateStr $timeStr'),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'edit') {
            _showMeasurementEntryDetails(entry);
          } else if (action == 'delete') {
            final confirmed = await _confirmDelete(entry.id);
            if (confirmed == true) {
              _deleteMeasurementEntry(entry.id);
            }
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit),
                const SizedBox(width: 8),
                Text(widget.i18n.t('edit')),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, color: Colors.red),
                const SizedBox(width: 8),
                Text(widget.i18n.t('delete'), style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      onTap: () => _showMeasurementEntryDetails(entry),
    );
  }

  Widget _buildBloodPressureEntryTile(BloodPressureEntry entry) {
    final dateTime = entry.timestampDateTime;
    final dateStr = _formatDate(dateTime);
    final timeStr = _formatTime(dateTime);

    // Determine blood pressure category for color coding
    final color = _getBloodPressureColor(entry.systolic, entry.diastolic);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(Icons.favorite, color: color),
      ),
      title: Text(
        entry.displayValue,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('$dateStr $timeStr${entry.heartRate != null ? ' • ${entry.heartRate} bpm' : ''}'),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'edit') {
            _showBloodPressureEntryDetails(entry);
          } else if (action == 'delete') {
            final confirmed = await _confirmDelete(entry.id);
            if (confirmed == true) {
              _deleteBloodPressureEntry(entry.id);
            }
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit),
                const SizedBox(width: 8),
                Text(widget.i18n.t('edit')),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, color: Colors.red),
                const SizedBox(width: 8),
                Text(widget.i18n.t('delete'), style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      onTap: () => _showBloodPressureEntryDetails(entry),
    );
  }

  Color _getBloodPressureColor(int systolic, int diastolic) {
    if (systolic < 120 && diastolic < 80) return Colors.green;
    if (systolic < 130 && diastolic < 80) return Colors.lightGreen;
    if (systolic < 140 || diastolic < 90) return Colors.orange;
    return Colors.red;
  }

  Future<bool?> _confirmDelete(String entryId) {
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

  Future<void> _deleteMeasurementEntry(String entryId) async {
    try {
      await widget.service.deleteMeasurementEntry(
        widget.typeId,
        entryId,
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

  Future<void> _deleteBloodPressureEntry(String entryId) async {
    try {
      await widget.service.deleteBloodPressureEntry(
        entryId,
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

  void _showMeasurementEntryDetails(MeasurementEntry entry) {
    final dateTime = entry.timestampDateTime;
    final unit = _config?.unit ?? _data?.unit ?? '';
    final decimalPlaces = _config?.decimalPlaces ?? _data?.decimalPlaces ?? 1;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_measurement_${widget.typeId}'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              widget.i18n.t('tracker_value'),
              '${entry.value.toStringAsFixed(decimalPlaces)} $unit',
            ),
            _buildDetailRow(
              widget.i18n.t('tracker_date'),
              _formatDate(dateTime),
            ),
            _buildDetailRow(
              widget.i18n.t('tracker_time'),
              _formatTime(dateTime),
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

  void _showBloodPressureEntryDetails(BloodPressureEntry entry) {
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
              widget.i18n.t('tracker_blood_pressure'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              widget.i18n.t('tracker_reading'),
              '${entry.systolic}/${entry.diastolic} mmHg',
            ),
            if (entry.heartRate != null)
              _buildDetailRow(
                widget.i18n.t('tracker_heart_rate'),
                '${entry.heartRate} bpm',
              ),
            _buildDetailRow(
              widget.i18n.t('tracker_date'),
              _formatDate(dateTime),
            ),
            _buildDetailRow(
              widget.i18n.t('tracker_time'),
              _formatTime(dateTime),
            ),
            if (entry.arm != null)
              _buildDetailRow(
                widget.i18n.t('tracker_arm'),
                entry.arm!,
              ),
            if (entry.position != null)
              _buildDetailRow(
                widget.i18n.t('tracker_position'),
                entry.position!,
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
    final result = await AddTrackableDialog.showMeasurement(
      context,
      service: widget.service,
      i18n: widget.i18n,
      preselectedTypeId: widget.typeId,
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
          builder: (context) => MeasurementDetailPage(
            service: widget.service,
            i18n: widget.i18n,
            typeId: widget.typeId,
            year: selected,
          ),
        ),
      );
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
