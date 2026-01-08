import 'tracker_metadata.dart';
import 'tracker_visibility.dart';

/// Plan status
enum TrackerPlanStatus {
  active,
  paused,
  completed,
  expired,
  cancelled,
}

/// Goal target type
enum GoalTargetType {
  daily,
  weekly,
}

/// A goal within a plan
class PlanGoal {
  final String id;
  final String exerciseId;
  final String description;
  final GoalTargetType targetType;
  final int? dailyTarget;
  final int weeklyTarget;

  const PlanGoal({
    required this.id,
    required this.exerciseId,
    required this.description,
    required this.targetType,
    this.dailyTarget,
    required this.weeklyTarget,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'exercise_id': exerciseId,
        'description': description,
        'target_type': targetType.name,
        if (dailyTarget != null) 'daily_target': dailyTarget,
        'weekly_target': weeklyTarget,
      };

  factory PlanGoal.fromJson(Map<String, dynamic> json) {
    final targetTypeStr = json['target_type'] as String? ?? 'weekly';
    final targetType = GoalTargetType.values.firstWhere(
      (t) => t.name == targetTypeStr,
      orElse: () => GoalTargetType.weekly,
    );

    return PlanGoal(
      id: json['id'] as String,
      exerciseId: json['exercise_id'] as String,
      description: json['description'] as String,
      targetType: targetType,
      dailyTarget: json['daily_target'] as int?,
      weeklyTarget: json['weekly_target'] as int,
    );
  }

  PlanGoal copyWith({
    String? id,
    String? exerciseId,
    String? description,
    GoalTargetType? targetType,
    int? dailyTarget,
    int? weeklyTarget,
  }) {
    return PlanGoal(
      id: id ?? this.id,
      exerciseId: exerciseId ?? this.exerciseId,
      description: description ?? this.description,
      targetType: targetType ?? this.targetType,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
    );
  }

  /// Create a daily goal (auto-calculates weekly from daily * 7)
  factory PlanGoal.daily({
    required String id,
    required String exerciseId,
    required String description,
    required int dailyTarget,
  }) {
    return PlanGoal(
      id: id,
      exerciseId: exerciseId,
      description: description,
      targetType: GoalTargetType.daily,
      dailyTarget: dailyTarget,
      weeklyTarget: dailyTarget * 7,
    );
  }

  /// Create a weekly goal
  factory PlanGoal.weekly({
    required String id,
    required String exerciseId,
    required String description,
    required int weeklyTarget,
  }) {
    return PlanGoal(
      id: id,
      exerciseId: exerciseId,
      description: description,
      targetType: GoalTargetType.weekly,
      weeklyTarget: weeklyTarget,
    );
  }
}

/// Reminder settings for a plan
class PlanReminders {
  final bool enabled;
  final String time; // HH:MM format
  final List<String> days;

  const PlanReminders({
    this.enabled = false,
    this.time = '07:00',
    this.days = const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday'
    ],
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'time': time,
        'days': days,
      };

  factory PlanReminders.fromJson(Map<String, dynamic> json) {
    return PlanReminders(
      enabled: json['enabled'] as bool? ?? false,
      time: json['time'] as String? ?? '07:00',
      days: (json['days'] as List<dynamic>?)
              ?.map((d) => d as String)
              .toList() ??
          const [
            'monday',
            'tuesday',
            'wednesday',
            'thursday',
            'friday',
            'saturday',
            'sunday'
          ],
    );
  }
}

/// A fitness plan
class TrackerPlan {
  final String id;
  final String title;
  final String? description;
  final TrackerPlanStatus status;
  final String createdAt;
  final String updatedAt;
  final String startsAt; // YYYY-MM-DD
  final String? endsAt; // YYYY-MM-DD
  final List<PlanGoal> goals;
  final PlanReminders? reminders;
  final String? ownerCallsign;
  final TrackerVisibility? visibility;
  final TrackerNostrMetadata? metadata;

  const TrackerPlan({
    required this.id,
    required this.title,
    this.description,
    this.status = TrackerPlanStatus.active,
    required this.createdAt,
    required this.updatedAt,
    required this.startsAt,
    this.endsAt,
    this.goals = const [],
    this.reminders,
    this.ownerCallsign,
    this.visibility,
    this.metadata,
  });

  DateTime get startsAtDate => DateTime.parse(startsAt);
  DateTime? get endsAtDate => endsAt != null ? DateTime.parse(endsAt!) : null;

  /// Check if plan is currently active (date-wise)
  bool get isCurrentlyActive {
    if (status != TrackerPlanStatus.active) return false;
    final now = DateTime.now();
    final start = startsAtDate;
    final end = endsAtDate;
    if (end == null) return now.isAfter(start.subtract(const Duration(days: 1)));
    return now.isAfter(start.subtract(const Duration(days: 1))) &&
        now.isBefore(end.add(const Duration(days: 1)));
  }

  /// Check if plan has expired
  bool get hasExpired {
    final end = endsAtDate;
    if (end == null) return false;
    final now = DateTime.now();
    return now.isAfter(end);
  }

  /// Get total duration in weeks
  int get totalWeeks {
    final end = endsAtDate;
    if (end == null) return 0;
    return end.difference(startsAtDate).inDays ~/ 7;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        'status': status.name,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'starts_at': startsAt,
        if (endsAt != null) 'ends_at': endsAt,
        'goals': goals.map((g) => g.toJson()).toList(),
        if (reminders != null) 'reminders': reminders!.toJson(),
        if (ownerCallsign != null) 'owner_callsign': ownerCallsign,
        if (visibility != null) 'visibility': visibility!.toJson(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory TrackerPlan.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'active';
    final status = TrackerPlanStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => TrackerPlanStatus.active,
    );

    return TrackerPlan(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: status,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String? ?? json['created_at'] as String,
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String?,
      goals: (json['goals'] as List<dynamic>?)
              ?.map((g) => PlanGoal.fromJson(g as Map<String, dynamic>))
              .toList() ??
          const [],
      reminders: json['reminders'] != null
          ? PlanReminders.fromJson(json['reminders'] as Map<String, dynamic>)
          : null,
      ownerCallsign: json['owner_callsign'] as String?,
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] != null
          ? TrackerNostrMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  TrackerPlan copyWith({
    String? id,
    String? title,
    String? description,
    TrackerPlanStatus? status,
    String? createdAt,
    String? updatedAt,
    String? startsAt,
    String? endsAt,
    List<PlanGoal>? goals,
    PlanReminders? reminders,
    String? ownerCallsign,
    TrackerVisibility? visibility,
    TrackerNostrMetadata? metadata,
  }) {
    return TrackerPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      goals: goals ?? this.goals,
      reminders: reminders ?? this.reminders,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      visibility: visibility ?? this.visibility,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Progress status for a goal
enum GoalProgressStatus {
  achieved,
  onTrack,
  behind,
  notStarted,
}

/// Weekly progress for a single goal
class GoalWeeklyProgress {
  final String goalId;
  final String exerciseId;
  final int weeklyTarget;
  final int weeklyActual;
  final double progressPercent;
  final Map<String, int> dailyBreakdown; // date -> count
  final GoalProgressStatus status;

  const GoalWeeklyProgress({
    required this.goalId,
    required this.exerciseId,
    required this.weeklyTarget,
    required this.weeklyActual,
    required this.progressPercent,
    this.dailyBreakdown = const {},
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'goal_id': goalId,
        'exercise_id': exerciseId,
        'weekly_target': weeklyTarget,
        'weekly_actual': weeklyActual,
        'progress_percent': progressPercent,
        'daily_breakdown': dailyBreakdown,
        'status': status.name,
      };

  factory GoalWeeklyProgress.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'not_started';
    final status = GoalProgressStatus.values.firstWhere(
      (s) => s.name == statusStr || s.name == statusStr.replaceAll('_', ''),
      orElse: () => GoalProgressStatus.notStarted,
    );

    return GoalWeeklyProgress(
      goalId: json['goal_id'] as String,
      exerciseId: json['exercise_id'] as String,
      weeklyTarget: json['weekly_target'] as int,
      weeklyActual: json['weekly_actual'] as int,
      progressPercent: (json['progress_percent'] as num).toDouble(),
      dailyBreakdown: (json['daily_breakdown'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          const {},
      status: status,
    );
  }

  /// Calculate progress for a goal based on exercise entries
  factory GoalWeeklyProgress.calculate({
    required PlanGoal goal,
    required Map<String, int> dailyTotals, // date (YYYY-MM-DD) -> count
    required bool weekEnded,
  }) {
    final weeklyActual =
        dailyTotals.values.fold<int>(0, (sum, count) => sum + count);
    final progressPercent = goal.weeklyTarget > 0
        ? (weeklyActual / goal.weeklyTarget) * 100
        : 0.0;

    GoalProgressStatus status;
    if (weeklyActual >= goal.weeklyTarget) {
      status = GoalProgressStatus.achieved;
    } else if (weeklyActual == 0) {
      status = GoalProgressStatus.notStarted;
    } else if (weekEnded) {
      status = GoalProgressStatus.behind;
    } else if (progressPercent >= 70) {
      status = GoalProgressStatus.onTrack;
    } else {
      status = GoalProgressStatus.behind;
    }

    return GoalWeeklyProgress(
      goalId: goal.id,
      exerciseId: goal.exerciseId,
      weeklyTarget: goal.weeklyTarget,
      weeklyActual: weeklyActual,
      progressPercent: progressPercent,
      dailyBreakdown: dailyTotals,
      status: status,
    );
  }
}

/// Weekly progress for an entire plan (computed, not stored)
class PlanWeeklyProgress {
  final String planId;
  final String week; // ISO week format: YYYY-Www
  final String weekStart; // YYYY-MM-DD
  final String weekEnd; // YYYY-MM-DD
  final List<GoalWeeklyProgress> goals;
  final double overallProgressPercent;
  final int goalsAchieved;
  final int goalsTotal;

  const PlanWeeklyProgress({
    required this.planId,
    required this.week,
    required this.weekStart,
    required this.weekEnd,
    this.goals = const [],
    this.overallProgressPercent = 0,
    this.goalsAchieved = 0,
    this.goalsTotal = 0,
  });

  Map<String, dynamic> toJson() => {
        'plan_id': planId,
        'week': week,
        'week_start': weekStart,
        'week_end': weekEnd,
        'goals': goals.map((g) => g.toJson()).toList(),
        'overall_progress_percent': overallProgressPercent,
        'goals_achieved': goalsAchieved,
        'goals_total': goalsTotal,
      };

  factory PlanWeeklyProgress.fromJson(Map<String, dynamic> json) {
    return PlanWeeklyProgress(
      planId: json['plan_id'] as String,
      week: json['week'] as String,
      weekStart: json['week_start'] as String,
      weekEnd: json['week_end'] as String,
      goals: (json['goals'] as List<dynamic>?)
              ?.map(
                  (g) => GoalWeeklyProgress.fromJson(g as Map<String, dynamic>))
              .toList() ??
          const [],
      overallProgressPercent:
          (json['overall_progress_percent'] as num?)?.toDouble() ?? 0,
      goalsAchieved: json['goals_achieved'] as int? ?? 0,
      goalsTotal: json['goals_total'] as int? ?? 0,
    );
  }
}

/// Summary of a goal for archived plans
class GoalSummary {
  final String goalId;
  final String exerciseId;
  final int totalTarget;
  final int totalActual;
  final double achievementPercent;

  const GoalSummary({
    required this.goalId,
    required this.exerciseId,
    required this.totalTarget,
    required this.totalActual,
    required this.achievementPercent,
  });

  Map<String, dynamic> toJson() => {
        'goal_id': goalId,
        'exercise_id': exerciseId,
        'total_target': totalTarget,
        'total_actual': totalActual,
        'achievement_percent': achievementPercent,
      };

  factory GoalSummary.fromJson(Map<String, dynamic> json) {
    return GoalSummary(
      goalId: json['goal_id'] as String,
      exerciseId: json['exercise_id'] as String,
      totalTarget: json['total_target'] as int,
      totalActual: json['total_actual'] as int,
      achievementPercent: (json['achievement_percent'] as num).toDouble(),
    );
  }
}

/// Summary for an archived plan
class PlanSummary {
  final int totalWeeks;
  final int weeksAllGoalsAchieved;
  final int weeksPartial;
  final int weeksMissed;
  final double achievementRatePercent;
  final List<GoalSummary> goalsSummary;

  const PlanSummary({
    required this.totalWeeks,
    required this.weeksAllGoalsAchieved,
    required this.weeksPartial,
    required this.weeksMissed,
    required this.achievementRatePercent,
    this.goalsSummary = const [],
  });

  Map<String, dynamic> toJson() => {
        'total_weeks': totalWeeks,
        'weeks_all_goals_achieved': weeksAllGoalsAchieved,
        'weeks_partial': weeksPartial,
        'weeks_missed': weeksMissed,
        'achievement_rate_percent': achievementRatePercent,
        'goals_summary': goalsSummary.map((g) => g.toJson()).toList(),
      };

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    return PlanSummary(
      totalWeeks: json['total_weeks'] as int,
      weeksAllGoalsAchieved: json['weeks_all_goals_achieved'] as int,
      weeksPartial: json['weeks_partial'] as int,
      weeksMissed: json['weeks_missed'] as int,
      achievementRatePercent:
          (json['achievement_rate_percent'] as num).toDouble(),
      goalsSummary: (json['goals_summary'] as List<dynamic>?)
              ?.map((g) => GoalSummary.fromJson(g as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Archived plan (includes summary)
class ArchivedPlan extends TrackerPlan {
  final String archivedAt;
  final PlanSummary? summary;

  const ArchivedPlan({
    required super.id,
    required super.title,
    super.description,
    super.status,
    required super.createdAt,
    required super.updatedAt,
    required super.startsAt,
    super.endsAt,
    super.goals,
    super.reminders,
    super.ownerCallsign,
    super.visibility,
    super.metadata,
    required this.archivedAt,
    this.summary,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['archived_at'] = archivedAt;
    if (summary != null) json['summary'] = summary!.toJson();
    return json;
  }

  factory ArchivedPlan.fromJson(Map<String, dynamic> json) {
    final plan = TrackerPlan.fromJson(json);
    return ArchivedPlan(
      id: plan.id,
      title: plan.title,
      description: plan.description,
      status: plan.status,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt,
      startsAt: plan.startsAt,
      endsAt: plan.endsAt,
      goals: plan.goals,
      reminders: plan.reminders,
      ownerCallsign: plan.ownerCallsign,
      visibility: plan.visibility,
      metadata: plan.metadata,
      archivedAt: json['archived_at'] as String,
      summary: json['summary'] != null
          ? PlanSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Create an archived plan from a regular plan with summary
  factory ArchivedPlan.fromPlan(TrackerPlan plan, PlanSummary? summary) {
    return ArchivedPlan(
      id: plan.id,
      title: plan.title,
      description: plan.description,
      status: plan.status,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt,
      startsAt: plan.startsAt,
      endsAt: plan.endsAt,
      goals: plan.goals,
      reminders: plan.reminders,
      ownerCallsign: plan.ownerCallsign,
      visibility: plan.visibility,
      metadata: plan.metadata,
      archivedAt: DateTime.now().toIso8601String(),
      summary: summary,
    );
  }
}
