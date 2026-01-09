import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../models/tracker_plan.dart';
import '../models/trackable_type.dart';
import '../services/tracker_service.dart';
import '../dialogs/add_trackable_dialog.dart';
import '../../services/i18n_service.dart';

/// Detail page for viewing plan progress and managing goals
class PlanDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final String planId;

  const PlanDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.planId,
  });

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  TrackerPlan? _plan;
  PlanWeeklyProgress? _weekProgress;
  bool _loading = true;
  StreamSubscription? _changesSub;

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
    if (change.type == 'plan' || change.type == 'exercise') {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      _plan = await widget.service.getActivePlan(widget.planId);
      if (_plan != null) {
        _weekProgress = await widget.service.getPlanWeekProgress(widget.planId);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_plan?.title ?? widget.i18n.t('tracker_plans')),
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              if (_plan?.status == TrackerPlanStatus.active)
                PopupMenuItem(
                  value: 'pause',
                  child: Row(
                    children: [
                      const Icon(Icons.pause),
                      const SizedBox(width: 8),
                      Text(widget.i18n.t('tracker_pause_plan')),
                    ],
                  ),
                ),
              if (_plan?.status == TrackerPlanStatus.paused)
                PopupMenuItem(
                  value: 'resume',
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow),
                      const SizedBox(width: 8),
                      Text(widget.i18n.t('tracker_resume_plan')),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'complete',
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(widget.i18n.t('tracker_complete_plan')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    const Icon(Icons.archive, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(widget.i18n.t('tracker_archive_plan')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading ? _buildLoading() : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildContent() {
    final plan = _plan;
    if (plan == null) {
      return Center(
        child: Text(widget.i18n.t('tracker_no_plans')),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // Plan header with status and dates
          SliverToBoxAdapter(
            child: _buildPlanHeader(plan),
          ),

          // Overall progress card
          SliverToBoxAdapter(
            child: _buildOverallProgressCard(plan),
          ),

          // Catch-up banner if behind
          if (_shouldShowCatchUpBanner())
            SliverToBoxAdapter(
              child: _buildCatchUpBanner(),
            ),

          // Goals section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                widget.i18n.t('tracker_goals'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),

          // Goals list
          if (plan.goals.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  widget.i18n.t('tracker_no_goals'),
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildGoalCard(plan.goals[index]),
                childCount: plan.goals.length,
              ),
            ),

          // Weekly calendar
          SliverToBoxAdapter(
            child: _buildWeeklyCalendar(),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanHeader(TrackerPlan plan) {
    final statusColor = _getStatusColor(plan.status);
    final statusText = _getStatusText(plan.status);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plan.description!,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${widget.i18n.t('tracker_start_date')}: ${plan.startsAt}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (plan.endsAt != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    '${widget.i18n.t('tracker_end_date')}: ${plan.endsAt}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallProgressCard(TrackerPlan plan) {
    final progress = _weekProgress;
    final overallPercent = progress?.overallProgressPercent ?? 0;
    final goalsAchieved = progress?.goalsAchieved ?? 0;
    final goalsTotal = progress?.goalsTotal ?? plan.goals.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.i18n.t('tracker_current_week'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$goalsAchieved / $goalsTotal ${widget.i18n.t('tracker_goals')}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Circular progress
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: overallPercent / 100,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(
                          _getProgressColor(overallPercent),
                        ),
                      ),
                      Text(
                        '${overallPercent.toInt()}%',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Motivational message
                Expanded(
                  child: Text(
                    _getMotivationalMessage(overallPercent),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowCatchUpBanner() {
    final progress = _weekProgress;
    if (progress == null) return false;

    // Show banner if it's past mid-week and behind schedule
    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Monday, 7 = Sunday
    final weekProgress = weekday / 7;

    // Behind if actual progress is less than 70% of where we should be
    return progress.overallProgressPercent < (weekProgress * 100 * 0.7);
  }

  Widget _buildCatchUpBanner() {
    final progress = _weekProgress;
    if (progress == null || progress.goals.isEmpty) {
      return const SizedBox.shrink();
    }

    // Find the most behind goal
    GoalWeeklyProgress? mostBehind;
    for (final goal in progress.goals) {
      if (goal.status == GoalProgressStatus.behind ||
          goal.status == GoalProgressStatus.notStarted) {
        if (mostBehind == null || goal.progressPercent < mostBehind.progressPercent) {
          mostBehind = goal;
        }
      }
    }

    if (mostBehind == null) return const SizedBox.shrink();

    final remaining = mostBehind.weeklyTarget - mostBehind.weeklyActual;
    final daysLeft = 7 - DateTime.now().weekday + 1;
    final perDay = daysLeft > 0 ? (remaining / daysLeft).ceil() : remaining;
    final exerciseName = widget.i18n.t('tracker_exercise_${mostBehind.exerciseId}');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.i18n.t('tracker_catch_up_alert')
                        .replaceAll('{count}', remaining.toString())
                        .replaceAll('{exercise}', exerciseName),
                    style: TextStyle(color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.i18n.t('tracker_suggested_daily')
                  .replaceAll('{count}', perDay.toString()),
              style: TextStyle(color: Colors.orange[700], fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _quickLogExercise(mostBehind!.exerciseId),
              child: Text(widget.i18n.t('tracker_log_now')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(PlanGoal goal) {
    final progress = _weekProgress?.goals.firstWhere(
      (g) => g.goalId == goal.id,
      orElse: () => GoalWeeklyProgress(
        goalId: goal.id,
        exerciseId: goal.exerciseId,
        weeklyTarget: goal.weeklyTarget,
        weeklyActual: 0,
        progressPercent: 0,
        status: GoalProgressStatus.notStarted,
      ),
    );

    final progressPercent = progress?.progressPercent ?? 0;
    final actual = progress?.weeklyActual ?? 0;
    final target = goal.weeklyTarget;
    final exerciseName = widget.i18n.t('tracker_exercise_${goal.exerciseId}');
    final config = TrackableTypeConfig.exerciseTypes[goal.exerciseId];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _quickLogExercise(goal.exerciseId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getExerciseIcon(config?.category),
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      exerciseName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _buildStatusBadge(progress?.status ?? GoalProgressStatus.notStarted),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$actual / $target ${config?.unit ?? ''}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${progressPercent.toInt()}%',
                    style: TextStyle(
                      color: _getProgressColor(progressPercent),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (progressPercent / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(_getProgressColor(progressPercent)),
              ),
              if (goal.targetType == GoalTargetType.daily && goal.dailyTarget != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${widget.i18n.t('tracker_goal_daily')}: ${goal.dailyTarget} / ${widget.i18n.t('tracker_goal_weekly')}: ${goal.weeklyTarget}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(GoalProgressStatus status) {
    Color color;
    IconData icon;

    switch (status) {
      case GoalProgressStatus.achieved:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case GoalProgressStatus.onTrack:
        color = Colors.blue;
        icon = Icons.trending_up;
        break;
      case GoalProgressStatus.behind:
        color = Colors.orange;
        icon = Icons.trending_down;
        break;
      case GoalProgressStatus.notStarted:
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
    }

    return Icon(icon, color: color, size: 20);
  }

  Widget _buildWeeklyCalendar() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    final dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.i18n.t('tracker_current_week'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: days.asMap().entries.map((entry) {
                final index = entry.key;
                final day = entry.value;
                final isToday = day.day == now.day && day.month == now.month;
                final isPast = day.isBefore(DateTime(now.year, now.month, now.day));
                final dayProgress = _getDayProgress(day);

                return Column(
                  children: [
                    Text(
                      dayNames[index],
                      style: TextStyle(
                        color: isToday ? Theme.of(context).primaryColor : Colors.grey[600],
                        fontWeight: isToday ? FontWeight.bold : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getDayColor(dayProgress, isPast, isToday),
                        border: isToday
                            ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          day.day.toString(),
                          style: TextStyle(
                            color: _getDayTextColor(dayProgress, isPast, isToday),
                            fontSize: 12,
                            fontWeight: isToday ? FontWeight.bold : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  double _getDayProgress(DateTime day) {
    // Aggregate daily progress from all goals
    final progress = _weekProgress;
    if (progress == null) return 0;

    final dateKey = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    double totalProgress = 0;
    int goalCount = 0;

    for (final goal in progress.goals) {
      final dailyCount = goal.dailyBreakdown[dateKey] ?? 0;
      final plan = _plan;
      if (plan != null) {
        final planGoal = plan.goals.firstWhere(
          (g) => g.id == goal.goalId,
          orElse: () => PlanGoal(
            id: '',
            exerciseId: '',
            description: '',
            targetType: GoalTargetType.weekly,
            weeklyTarget: 1,
          ),
        );
        final dailyTarget = planGoal.dailyTarget ?? (planGoal.weeklyTarget / 7);
        if (dailyTarget > 0) {
          totalProgress += (dailyCount / dailyTarget).clamp(0.0, 1.0);
          goalCount++;
        }
      }
    }

    return goalCount > 0 ? totalProgress / goalCount : 0;
  }

  Color _getDayColor(double progress, bool isPast, bool isToday) {
    if (!isPast && !isToday) return Colors.grey[100]!;
    if (progress >= 1.0) return Colors.green[100]!;
    if (progress >= 0.5) return Colors.yellow[100]!;
    if (progress > 0) return Colors.orange[100]!;
    return isPast ? Colors.red[50]! : Colors.grey[100]!;
  }

  Color _getDayTextColor(double progress, bool isPast, bool isToday) {
    if (!isPast && !isToday) return Colors.grey[600]!;
    if (progress >= 1.0) return Colors.green[900]!;
    if (progress >= 0.5) return Colors.yellow[900]!;
    if (progress > 0) return Colors.orange[900]!;
    return isPast ? Colors.red[900]! : Colors.grey[600]!;
  }

  Color _getStatusColor(TrackerPlanStatus status) {
    switch (status) {
      case TrackerPlanStatus.active:
        return Colors.green;
      case TrackerPlanStatus.paused:
        return Colors.orange;
      case TrackerPlanStatus.completed:
        return Colors.blue;
      case TrackerPlanStatus.expired:
        return Colors.grey;
      case TrackerPlanStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusText(TrackerPlanStatus status) {
    switch (status) {
      case TrackerPlanStatus.active:
        return widget.i18n.t('tracker_active');
      case TrackerPlanStatus.paused:
        return widget.i18n.t('tracker_plan_paused');
      case TrackerPlanStatus.completed:
        return widget.i18n.t('tracker_plan_completed');
      case TrackerPlanStatus.expired:
        return widget.i18n.t('tracker_plan_expired');
      case TrackerPlanStatus.cancelled:
        return widget.i18n.t('cancel');
    }
  }

  Color _getProgressColor(double percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 70) return Colors.blue;
    if (percent >= 40) return Colors.orange;
    return Colors.red;
  }

  String _getMotivationalMessage(double percent) {
    if (percent >= 100) {
      return widget.i18n.t('tracker_all_goals_achieved');
    } else if (percent >= 70) {
      return widget.i18n.t('tracker_tip_on_track_1');
    } else if (percent >= 40) {
      return widget.i18n.t('tracker_tip_on_track_2');
    } else if (percent > 0) {
      return widget.i18n.t('tracker_tip_behind_3');
    } else {
      return widget.i18n.t('tracker_tip_behind_1').replaceAll('{exercise}', '');
    }
  }

  IconData _getExerciseIcon(TrackableCategory? category) {
    switch (category) {
      case TrackableCategory.strength:
        return Icons.fitness_center;
      case TrackableCategory.cardio:
        return Icons.directions_run;
      case TrackableCategory.flexibility:
        return Icons.self_improvement;
      case TrackableCategory.health:
        return Icons.favorite;
      default:
        return Icons.fitness_center;
    }
  }

  Future<void> _quickLogExercise(String exerciseId) async {
    final result = await AddTrackableDialog.showExercise(
      context,
      service: widget.service,
      i18n: widget.i18n,
      preselectedTypeId: exerciseId,
      year: DateTime.now().year,
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _onMenuAction(String action) async {
    switch (action) {
      case 'pause':
        await _pausePlan();
        break;
      case 'resume':
        await _resumePlan();
        break;
      case 'complete':
        await _completePlan();
        break;
      case 'archive':
        await _archivePlan();
        break;
    }
  }

  Future<void> _pausePlan() async {
    final success = await widget.service.pausePlan(widget.planId);
    if (success) {
      _loadData();
    }
  }

  Future<void> _resumePlan() async {
    final success = await widget.service.resumePlan(widget.planId);
    if (success) {
      _loadData();
    }
  }

  Future<void> _completePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('tracker_complete_plan')),
        content: Text(widget.i18n.t('tracker_confirm_stop_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.i18n.t('tracker_complete_plan')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.service.completePlan(widget.planId);
      if (success && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _archivePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('tracker_archive_plan')),
        content: Text(widget.i18n.t('tracker_confirm_stop_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.i18n.t('tracker_archive_plan')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.service.archivePlan(widget.planId);
      if (success && mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
