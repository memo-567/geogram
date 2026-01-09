import '../models/tracker_plan.dart';
import 'tracker_service.dart';
import '../../services/i18n_service.dart';

/// Types of plan reminders
enum PlanReminderType {
  midWeekBehind,
  catchUp,
  almostThere,
  goalAchieved,
  allGoalsAchieved,
  dailyReminder,
}

/// A reminder generated for a plan
class PlanReminder {
  final String planId;
  final String? goalId;
  final PlanReminderType type;
  final String message;
  final String? exerciseId;
  final int? remainingCount;
  final int? suggestedDaily;

  const PlanReminder({
    required this.planId,
    this.goalId,
    required this.type,
    required this.message,
    this.exerciseId,
    this.remainingCount,
    this.suggestedDaily,
  });
}

/// Mid-week status for a plan
class MidWeekStatus {
  final double weekProgress; // 0.0 - 1.0 (where in the week we are)
  final Map<String, double> goalProgress; // goalId -> progress %
  final List<String> behindGoals; // goals that are behind schedule
  final bool isMidWeek; // true if Wednesday-Thursday

  const MidWeekStatus({
    required this.weekProgress,
    required this.goalProgress,
    required this.behindGoals,
    required this.isMidWeek,
  });
}

/// Catch-up suggestion for a goal
class CatchUpSuggestion {
  final String goalId;
  final String exerciseId;
  final int remainingTarget;
  final int daysLeft;
  final int suggestedDailyAmount;
  final String motivationalTip;

  const CatchUpSuggestion({
    required this.goalId,
    required this.exerciseId,
    required this.remainingTarget,
    required this.daysLeft,
    required this.suggestedDailyAmount,
    required this.motivationalTip,
  });
}

/// Service for generating smart plan reminders
class PlanReminderService {
  final TrackerService _trackerService;
  final I18nService _i18n;

  PlanReminderService({
    required TrackerService trackerService,
    required I18nService i18n,
  })  : _trackerService = trackerService,
        _i18n = i18n;

  /// Check all active plans and generate reminders
  Future<List<PlanReminder>> checkPlansForReminders() async {
    final reminders = <PlanReminder>[];

    try {
      final plans = await _trackerService.listActivePlans();

      for (final plan in plans) {
        if (plan.status != TrackerPlanStatus.active) continue;

        final planReminders = await _checkPlanForReminders(plan);
        reminders.addAll(planReminders);
      }
    } catch (e) {
      // Handle errors silently
    }

    return reminders;
  }

  /// Check a single plan for reminders
  Future<List<PlanReminder>> _checkPlanForReminders(TrackerPlan plan) async {
    final reminders = <PlanReminder>[];

    final progress = await _trackerService.getPlanWeekProgress(plan.id);
    if (progress == null) return reminders;

    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Monday, 7 = Sunday
    final weekProgress = weekday / 7;
    final daysLeft = 7 - weekday + 1;

    // Check for all goals achieved
    if (progress.goalsAchieved == progress.goalsTotal && progress.goalsTotal > 0) {
      reminders.add(PlanReminder(
        planId: plan.id,
        type: PlanReminderType.allGoalsAchieved,
        message: _i18n.t('tracker_all_goals_achieved'),
      ));
      return reminders; // No other reminders needed if all goals achieved
    }

    // Check each goal
    for (final goalProgress in progress.goals) {
      final goal = plan.goals.firstWhere(
        (g) => g.id == goalProgress.goalId,
        orElse: () => PlanGoal(
          id: '',
          exerciseId: '',
          description: '',
          targetType: GoalTargetType.weekly,
          weeklyTarget: 1,
        ),
      );

      if (goal.id.isEmpty) continue;

      final exerciseName = _i18n.t('tracker_exercise_${goal.exerciseId}');
      final remaining = goalProgress.weeklyTarget - goalProgress.weeklyActual;
      final suggestedDaily = daysLeft > 0 ? (remaining / daysLeft).ceil() : remaining;

      // Goal achieved
      if (goalProgress.status == GoalProgressStatus.achieved) {
        reminders.add(PlanReminder(
          planId: plan.id,
          goalId: goal.id,
          type: PlanReminderType.goalAchieved,
          message: _i18n
              .t('tracker_goal_achieved')
              .replaceAll('{exercise}', exerciseName),
          exerciseId: goal.exerciseId,
        ));
        continue;
      }

      // Almost there (90%+)
      if (goalProgress.progressPercent >= 90 && goalProgress.progressPercent < 100) {
        reminders.add(PlanReminder(
          planId: plan.id,
          goalId: goal.id,
          type: PlanReminderType.almostThere,
          message: _i18n
              .t('tracker_almost_there')
              .replaceAll('{count}', remaining.toString())
              .replaceAll('{exercise}', exerciseName),
          exerciseId: goal.exerciseId,
          remainingCount: remaining,
        ));
        continue;
      }

      // Mid-week check (Wednesday-Thursday) - behind schedule
      if (weekday >= 3 && weekday <= 4) {
        final expectedProgress = weekProgress * 100;
        if (goalProgress.progressPercent < expectedProgress * 0.7) {
          reminders.add(PlanReminder(
            planId: plan.id,
            goalId: goal.id,
            type: PlanReminderType.midWeekBehind,
            message: _i18n
                .t('tracker_mid_week_behind')
                .replaceAll('{progress}', goalProgress.progressPercent.toStringAsFixed(0))
                .replaceAll('{exercise}', exerciseName),
            exerciseId: goal.exerciseId,
            remainingCount: remaining,
            suggestedDaily: suggestedDaily,
          ));
          continue;
        }
      }

      // Catch-up alert (significantly behind by Thursday)
      if (weekday >= 4 && goalProgress.progressPercent < 30) {
        reminders.add(PlanReminder(
          planId: plan.id,
          goalId: goal.id,
          type: PlanReminderType.catchUp,
          message: _i18n
              .t('tracker_catch_up_alert')
              .replaceAll('{count}', remaining.toString())
              .replaceAll('{exercise}', exerciseName),
          exerciseId: goal.exerciseId,
          remainingCount: remaining,
          suggestedDaily: suggestedDaily,
        ));
      }
    }

    return reminders;
  }

  /// Get mid-week status for a plan
  Future<MidWeekStatus> getMidWeekStatus(String planId) async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final weekProgress = weekday / 7;
    final isMidWeek = weekday >= 3 && weekday <= 4;

    final goalProgress = <String, double>{};
    final behindGoals = <String>[];

    final progress = await _trackerService.getPlanWeekProgress(planId);
    if (progress != null) {
      for (final goal in progress.goals) {
        goalProgress[goal.goalId] = goal.progressPercent;

        // Consider behind if progress is less than 70% of where we should be
        final expectedProgress = weekProgress * 100;
        if (goal.progressPercent < expectedProgress * 0.7) {
          behindGoals.add(goal.goalId);
        }
      }
    }

    return MidWeekStatus(
      weekProgress: weekProgress,
      goalProgress: goalProgress,
      behindGoals: behindGoals,
      isMidWeek: isMidWeek,
    );
  }

  /// Calculate what's needed to catch up for a goal
  Future<CatchUpSuggestion?> getCatchUpSuggestion(
    String planId,
    String goalId,
  ) async {
    final plan = await _trackerService.getActivePlan(planId);
    if (plan == null) return null;

    final goal = plan.goals.firstWhere(
      (g) => g.id == goalId,
      orElse: () => PlanGoal(
        id: '',
        exerciseId: '',
        description: '',
        targetType: GoalTargetType.weekly,
        weeklyTarget: 1,
      ),
    );

    if (goal.id.isEmpty) return null;

    final progress = await _trackerService.getPlanWeekProgress(planId);
    if (progress == null) return null;

    final goalProgress = progress.goals.firstWhere(
      (g) => g.goalId == goalId,
      orElse: () => GoalWeeklyProgress(
        goalId: goalId,
        exerciseId: goal.exerciseId,
        weeklyTarget: goal.weeklyTarget,
        weeklyActual: 0,
        progressPercent: 0,
        status: GoalProgressStatus.notStarted,
      ),
    );

    final now = DateTime.now();
    final daysLeft = 7 - now.weekday + 1;
    final remaining = goalProgress.weeklyTarget - goalProgress.weeklyActual;
    final suggestedDaily = daysLeft > 0 ? (remaining / daysLeft).ceil() : remaining;

    String tip;
    if (goalProgress.progressPercent == 0) {
      tip = _i18n.t('tracker_tip_behind_1').replaceAll(
            '{exercise}',
            _i18n.t('tracker_exercise_${goal.exerciseId}'),
          );
    } else if (daysLeft <= 2) {
      tip = _i18n.t('tracker_tip_behind_3');
    } else {
      tip = _i18n
          .t('tracker_tip_behind_2')
          .replaceAll('{count}', suggestedDaily.toString());
    }

    return CatchUpSuggestion(
      goalId: goalId,
      exerciseId: goal.exerciseId,
      remainingTarget: remaining,
      daysLeft: daysLeft,
      suggestedDailyAmount: suggestedDaily,
      motivationalTip: tip,
    );
  }

  /// Get streak count (consecutive weeks with all goals achieved)
  Future<int> getPlanStreak(String planId) async {
    // This would need historical data storage to track properly
    // For now, return 0 as a placeholder
    return 0;
  }
}
