import 'dart:math';

import '../models/tracker_plan.dart';
import '../models/tracker_models.dart';
import 'tracker_service.dart';
import '../../services/i18n_service.dart';

/// Service providing motivational tips and personalized insights
class MotivationService {
  final TrackerService _trackerService;
  final I18nService _i18n;
  final Random _random = Random();

  MotivationService({
    required TrackerService trackerService,
    required I18nService i18n,
  })  : _trackerService = trackerService,
        _i18n = i18n;

  /// Get a contextual tip based on progress status
  String getTipForProgress({
    required GoalProgressStatus status,
    required double progressPercent,
    String? exerciseName,
    int? remainingCount,
    int? suggestedDaily,
  }) {
    final exercise = exerciseName ?? '';

    switch (status) {
      case GoalProgressStatus.achieved:
        return _i18n.t('tracker_goal_achieved').replaceAll('{exercise}', exercise);

      case GoalProgressStatus.onTrack:
        final tips = [
          _i18n.t('tracker_tip_on_track_1'),
          _i18n.t('tracker_tip_on_track_2'),
        ];
        return tips[_random.nextInt(tips.length)];

      case GoalProgressStatus.behind:
        if (progressPercent > 0) {
          final tips = [
            _i18n.t('tracker_tip_behind_1').replaceAll('{exercise}', exercise),
            if (suggestedDaily != null)
              _i18n
                  .t('tracker_tip_behind_2')
                  .replaceAll('{count}', suggestedDaily.toString()),
            _i18n.t('tracker_tip_behind_3'),
          ];
          return tips[_random.nextInt(tips.length)];
        }
        return _i18n.t('tracker_tip_behind_1').replaceAll('{exercise}', exercise);

      case GoalProgressStatus.notStarted:
        return _i18n.t('tracker_tip_behind_1').replaceAll('{exercise}', exercise);
    }
  }

  /// Get tip when user is ahead of schedule
  String getAheadTip(double progressPercent) {
    final tips = [
      _i18n.t('tracker_tip_ahead_1'),
      _i18n
          .t('tracker_tip_ahead_2')
          .replaceAll('{progress}', progressPercent.toStringAsFixed(0)),
    ];
    return tips[_random.nextInt(tips.length)];
  }

  /// Get rest day suggestion tip
  String getRestTip() {
    return _i18n.t('tracker_tip_rest');
  }

  /// Check if rest day should be suggested based on consecutive exercise days
  Future<bool> shouldSuggestRestDay(String exerciseId) async {
    try {
      final data = await _trackerService.getExercise(
        exerciseId,
        year: DateTime.now().year,
      );
      if (data == null) return false;

      // Check if user has exercised 5+ consecutive days
      final now = DateTime.now();
      int consecutiveDays = 0;

      for (int i = 0; i < 7; i++) {
        final day = now.subtract(Duration(days: i));
        final count = data.getTotalForDate(day);
        if (count > 0) {
          consecutiveDays++;
        } else {
          break;
        }
      }

      return consecutiveDays >= 5;
    } catch (e) {
      return false;
    }
  }

  /// Get personalized insight based on exercise history
  Future<PersonalizedInsight?> getInsight(String exerciseId) async {
    try {
      final data = await _trackerService.getExercise(
        exerciseId,
        year: DateTime.now().year,
      );
      if (data == null || data.entries.length < 14) return null;

      // Find best performing day of week
      final dayTotals = <int, int>{}; // weekday -> total count
      final dayCounts = <int, int>{}; // weekday -> number of entries

      for (final entry in data.entries) {
        final date = entry.timestampDateTime;
        dayTotals[date.weekday] = (dayTotals[date.weekday] ?? 0) + entry.count;
        dayCounts[date.weekday] = (dayCounts[date.weekday] ?? 0) + 1;
      }

      // Find day with highest average
      int? bestDay;
      double bestAvg = 0;
      for (final weekday in dayTotals.keys) {
        final avg = dayTotals[weekday]! / (dayCounts[weekday] ?? 1);
        if (avg > bestAvg) {
          bestAvg = avg;
          bestDay = weekday;
        }
      }

      if (bestDay != null) {
        final dayName = _getDayName(bestDay);
        return PersonalizedInsight(
          type: InsightType.bestDay,
          message: _i18n.t('tracker_insight_best_day').replaceAll('{day}', dayName),
          data: {'weekday': bestDay, 'averageCount': bestAvg},
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Calculate improvement compared to last month
  Future<double?> getImprovementPercent(String exerciseId) async {
    try {
      final data = await _trackerService.getExercise(
        exerciseId,
        year: DateTime.now().year,
      );
      if (data == null) return null;

      final now = DateTime.now();
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final lastMonthStart = DateTime(now.year, now.month - 1, 1);
      final lastMonthEnd = thisMonthStart.subtract(const Duration(days: 1));

      int thisMonthTotal = 0;
      int lastMonthTotal = 0;

      for (final entry in data.entries) {
        final date = entry.timestampDateTime;
        if (date.isAfter(thisMonthStart) ||
            (date.year == thisMonthStart.year &&
                date.month == thisMonthStart.month &&
                date.day == thisMonthStart.day)) {
          thisMonthTotal += entry.count;
        } else if (date.isAfter(lastMonthStart) && date.isBefore(thisMonthStart)) {
          lastMonthTotal += entry.count;
        }
      }

      if (lastMonthTotal == 0) return null;

      return ((thisMonthTotal - lastMonthTotal) / lastMonthTotal) * 100;
    } catch (e) {
      return null;
    }
  }

  /// Get consistency streak (weeks with any activity)
  Future<int> getConsistencyStreak(String exerciseId) async {
    try {
      final data = await _trackerService.getExercise(
        exerciseId,
        year: DateTime.now().year,
      );
      if (data == null) return 0;

      final now = DateTime.now();
      int streakWeeks = 0;

      // Check each week going backwards
      for (int weekOffset = 0; weekOffset < 52; weekOffset++) {
        final weekStart = now.subtract(Duration(days: now.weekday - 1 + (weekOffset * 7)));
        final weekEnd = weekStart.add(const Duration(days: 6));

        bool hasActivity = false;
        for (final entry in data.entries) {
          final date = entry.timestampDateTime;
          if (date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
              date.isBefore(weekEnd.add(const Duration(days: 1)))) {
            hasActivity = true;
            break;
          }
        }

        if (hasActivity) {
          streakWeeks++;
        } else {
          break;
        }
      }

      return streakWeeks;
    } catch (e) {
      return 0;
    }
  }

  String _getDayName(int weekday) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday];
  }
}

/// Types of personalized insights
enum InsightType {
  bestDay,
  bestTime,
  streak,
  improvement,
  consistency,
}

/// A personalized insight about user's exercise patterns
class PersonalizedInsight {
  final InsightType type;
  final String message;
  final Map<String, dynamic> data;

  const PersonalizedInsight({
    required this.type,
    required this.message,
    this.data = const {},
  });
}
