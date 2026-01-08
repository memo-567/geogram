import 'tracker_metadata.dart';
import 'tracker_visibility.dart';

/// Exercise category
enum ExerciseCategory {
  strength,
  cardio,
  flexibility,
}

/// Built-in exercise type configuration
class ExerciseTypeConfig {
  final String id;
  final String displayName;
  final String unit; // reps, meters, seconds
  final ExerciseCategory category;

  const ExerciseTypeConfig({
    required this.id,
    required this.displayName,
    required this.unit,
    required this.category,
  });

  /// Built-in exercise types
  static const Map<String, ExerciseTypeConfig> builtInTypes = {
    'pushups': ExerciseTypeConfig(
      id: 'pushups',
      displayName: 'Push-ups',
      unit: 'reps',
      category: ExerciseCategory.strength,
    ),
    'abdominals': ExerciseTypeConfig(
      id: 'abdominals',
      displayName: 'Abdominals',
      unit: 'reps',
      category: ExerciseCategory.strength,
    ),
    'squats': ExerciseTypeConfig(
      id: 'squats',
      displayName: 'Squats',
      unit: 'reps',
      category: ExerciseCategory.strength,
    ),
    'pullups': ExerciseTypeConfig(
      id: 'pullups',
      displayName: 'Pull-ups',
      unit: 'reps',
      category: ExerciseCategory.strength,
    ),
    'lunges': ExerciseTypeConfig(
      id: 'lunges',
      displayName: 'Lunges',
      unit: 'reps',
      category: ExerciseCategory.strength,
    ),
    'planks': ExerciseTypeConfig(
      id: 'planks',
      displayName: 'Planks',
      unit: 'seconds',
      category: ExerciseCategory.strength,
    ),
    'running': ExerciseTypeConfig(
      id: 'running',
      displayName: 'Running',
      unit: 'meters',
      category: ExerciseCategory.cardio,
    ),
    'walking': ExerciseTypeConfig(
      id: 'walking',
      displayName: 'Walking',
      unit: 'meters',
      category: ExerciseCategory.cardio,
    ),
    'cycling': ExerciseTypeConfig(
      id: 'cycling',
      displayName: 'Cycling',
      unit: 'meters',
      category: ExerciseCategory.cardio,
    ),
    'swimming': ExerciseTypeConfig(
      id: 'swimming',
      displayName: 'Swimming',
      unit: 'meters',
      category: ExerciseCategory.cardio,
    ),
  };

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'unit': unit,
        'category': category.name,
      };

  factory ExerciseTypeConfig.fromJson(Map<String, dynamic> json) {
    final categoryStr = json['category'] as String? ?? 'strength';
    final category = ExerciseCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => ExerciseCategory.strength,
    );
    return ExerciseTypeConfig(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      category: category,
    );
  }
}

/// Goal for an exercise type
class ExerciseGoal {
  final int? dailyTarget;
  final int? weeklyTarget;

  const ExerciseGoal({
    this.dailyTarget,
    this.weeklyTarget,
  });

  Map<String, dynamic> toJson() => {
        if (dailyTarget != null) 'daily_target': dailyTarget,
        if (weeklyTarget != null) 'weekly_target': weeklyTarget,
      };

  factory ExerciseGoal.fromJson(Map<String, dynamic> json) {
    return ExerciseGoal(
      dailyTarget: json['daily_target'] as int?,
      weeklyTarget: json['weekly_target'] as int?,
    );
  }
}

/// A single exercise entry
class ExerciseEntry {
  final String id;
  final String timestamp;
  final int count; // reps, meters, or seconds
  final int? durationSeconds; // for cardio exercises
  final String? pathId; // link to GPS path for cardio
  final String? notes;
  final List<String> tags;
  final TrackerNostrMetadata? metadata;

  const ExerciseEntry({
    required this.id,
    required this.timestamp,
    required this.count,
    this.durationSeconds,
    this.pathId,
    this.notes,
    this.tags = const [],
    this.metadata,
  });

  DateTime get timestampDateTime {
    try {
      return DateTime.parse(timestamp);
    } catch (e) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'count': count,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (pathId != null) 'path_id': pathId,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory ExerciseEntry.fromJson(Map<String, dynamic> json) {
    return ExerciseEntry(
      id: json['id'] as String,
      timestamp: json['timestamp'] as String,
      count: json['count'] as int,
      durationSeconds: json['duration_seconds'] as int?,
      pathId: json['path_id'] as String?,
      notes: json['notes'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t as String)
              .toList() ??
          const [],
      metadata: json['metadata'] != null
          ? TrackerNostrMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  ExerciseEntry copyWith({
    String? id,
    String? timestamp,
    int? count,
    int? durationSeconds,
    String? pathId,
    String? notes,
    List<String>? tags,
    TrackerNostrMetadata? metadata,
  }) {
    return ExerciseEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      count: count ?? this.count,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      pathId: pathId ?? this.pathId,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Statistics for an exercise type
class ExerciseStatistics {
  final int totalCount;
  final int totalEntries;
  final String? firstEntry;
  final String? lastEntry;

  const ExerciseStatistics({
    this.totalCount = 0,
    this.totalEntries = 0,
    this.firstEntry,
    this.lastEntry,
  });

  factory ExerciseStatistics.calculate(List<ExerciseEntry> entries) {
    if (entries.isEmpty) {
      return const ExerciseStatistics();
    }

    final totalCount = entries.fold<int>(0, (sum, e) => sum + e.count);

    // Sort by timestamp to find first and last
    final sorted = List<ExerciseEntry>.from(entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return ExerciseStatistics(
      totalCount: totalCount,
      totalEntries: entries.length,
      firstEntry: sorted.first.timestamp,
      lastEntry: sorted.last.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'total_count': totalCount,
        'total_entries': totalEntries,
        if (firstEntry != null) 'first_entry': firstEntry,
        if (lastEntry != null) 'last_entry': lastEntry,
      };

  factory ExerciseStatistics.fromJson(Map<String, dynamic> json) {
    return ExerciseStatistics(
      totalCount: json['total_count'] as int? ?? 0,
      totalEntries: json['total_entries'] as int? ?? 0,
      firstEntry: json['first_entry'] as String?,
      lastEntry: json['last_entry'] as String?,
    );
  }
}

/// Exercise data file (e.g., pushups.json)
class ExerciseData {
  final String exerciseId;
  final int year;
  final String displayName;
  final String unit;
  final ExerciseCategory category;
  final ExerciseGoal? goal;
  final List<ExerciseEntry> entries;
  final ExerciseStatistics? statistics;
  final TrackerVisibility? visibility;

  const ExerciseData({
    required this.exerciseId,
    required this.year,
    required this.displayName,
    required this.unit,
    this.category = ExerciseCategory.strength,
    this.goal,
    this.entries = const [],
    this.statistics,
    this.visibility,
  });

  /// Create from a built-in type
  factory ExerciseData.fromType(String exerciseId, int year) {
    final config = ExerciseTypeConfig.builtInTypes[exerciseId];
    if (config == null) {
      return ExerciseData(
        exerciseId: exerciseId,
        year: year,
        displayName: exerciseId,
        unit: 'reps',
      );
    }
    return ExerciseData(
      exerciseId: config.id,
      year: year,
      displayName: config.displayName,
      unit: config.unit,
      category: config.category,
    );
  }

  /// Check if this is a cardio exercise
  bool get isCardio => category == ExerciseCategory.cardio;

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'year': year,
        'display_name': displayName,
        'unit': unit,
        'category': category.name,
        if (goal != null) 'goal': goal!.toJson(),
        'entries': entries.map((e) => e.toJson()).toList(),
        if (statistics != null) 'statistics': statistics!.toJson(),
        if (visibility != null) 'visibility': visibility!.toJson(),
      };

  factory ExerciseData.fromJson(Map<String, dynamic> json) {
    final categoryStr = json['category'] as String? ?? 'strength';
    final category = ExerciseCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => ExerciseCategory.strength,
    );

    return ExerciseData(
      exerciseId: json['exercise_id'] as String,
      year: json['year'] as int,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      category: category,
      goal: json['goal'] != null
          ? ExerciseGoal.fromJson(json['goal'] as Map<String, dynamic>)
          : null,
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => ExerciseEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      statistics: json['statistics'] != null
          ? ExerciseStatistics.fromJson(
              json['statistics'] as Map<String, dynamic>)
          : null,
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
    );
  }

  ExerciseData copyWith({
    String? exerciseId,
    int? year,
    String? displayName,
    String? unit,
    ExerciseCategory? category,
    ExerciseGoal? goal,
    List<ExerciseEntry>? entries,
    ExerciseStatistics? statistics,
    TrackerVisibility? visibility,
  }) {
    return ExerciseData(
      exerciseId: exerciseId ?? this.exerciseId,
      year: year ?? this.year,
      displayName: displayName ?? this.displayName,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      goal: goal ?? this.goal,
      entries: entries ?? this.entries,
      statistics: statistics ?? this.statistics,
      visibility: visibility ?? this.visibility,
    );
  }

  /// Add a new entry and recalculate statistics
  ExerciseData addEntry(ExerciseEntry entry) {
    final newEntries = [...entries, entry];
    return copyWith(
      entries: newEntries,
      statistics: ExerciseStatistics.calculate(newEntries),
    );
  }

  /// Remove an entry and recalculate statistics
  ExerciseData removeEntry(String entryId) {
    final newEntries = entries.where((e) => e.id != entryId).toList();
    return copyWith(
      entries: newEntries,
      statistics: ExerciseStatistics.calculate(newEntries),
    );
  }

  /// Get entries for a specific date
  List<ExerciseEntry> getEntriesForDate(DateTime date) {
    return entries.where((e) {
      final entryDate = e.timestampDateTime;
      return entryDate.year == date.year &&
          entryDate.month == date.month &&
          entryDate.day == date.day;
    }).toList();
  }

  /// Get total count for a specific date
  int getTotalForDate(DateTime date) {
    return getEntriesForDate(date).fold<int>(0, (sum, e) => sum + e.count);
  }

  /// Get total count for current week
  int getTotalForCurrentWeek() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    return entries.where((e) {
      final entryDate = e.timestampDateTime;
      return entryDate.isAfter(startDate) ||
             (entryDate.year == startDate.year &&
              entryDate.month == startDate.month &&
              entryDate.day == startDate.day);
    }).fold<int>(0, (sum, e) => sum + e.count);
  }
}

/// Custom exercise type definition
class CustomExerciseType {
  final String id;
  final String displayName;
  final String unit;
  final ExerciseCategory category;

  const CustomExerciseType({
    required this.id,
    required this.displayName,
    required this.unit,
    this.category = ExerciseCategory.strength,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'unit': unit,
        'category': category.name,
      };

  factory CustomExerciseType.fromJson(Map<String, dynamic> json) {
    final categoryStr = json['category'] as String? ?? 'strength';
    final category = ExerciseCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => ExerciseCategory.strength,
    );
    return CustomExerciseType(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      category: category,
    );
  }
}

/// Custom exercise entry (includes exercise_id reference)
class CustomExerciseEntry {
  final String id;
  final String exerciseId;
  final String timestamp;
  final int count;
  final String? notes;

  const CustomExerciseEntry({
    required this.id,
    required this.exerciseId,
    required this.timestamp,
    required this.count,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'exercise_id': exerciseId,
        'timestamp': timestamp,
        'count': count,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory CustomExerciseEntry.fromJson(Map<String, dynamic> json) {
    return CustomExerciseEntry(
      id: json['id'] as String,
      exerciseId: json['exercise_id'] as String,
      timestamp: json['timestamp'] as String,
      count: json['count'] as int,
      notes: json['notes'] as String?,
    );
  }
}

/// Custom exercises data file (custom.json)
class CustomExercisesData {
  final int year;
  final List<CustomExerciseType> customTypes;
  final List<CustomExerciseEntry> entries;
  final TrackerVisibility? visibility;

  const CustomExercisesData({
    required this.year,
    this.customTypes = const [],
    this.entries = const [],
    this.visibility,
  });

  Map<String, dynamic> toJson() => {
        'year': year,
        'custom_types': customTypes.map((t) => t.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        if (visibility != null) 'visibility': visibility!.toJson(),
      };

  factory CustomExercisesData.fromJson(Map<String, dynamic> json) {
    return CustomExercisesData(
      year: json['year'] as int,
      customTypes: (json['custom_types'] as List<dynamic>?)
              ?.map((t) =>
                  CustomExerciseType.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) =>
                  CustomExerciseEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
    );
  }

  CustomExercisesData copyWith({
    int? year,
    List<CustomExerciseType>? customTypes,
    List<CustomExerciseEntry>? entries,
    TrackerVisibility? visibility,
  }) {
    return CustomExercisesData(
      year: year ?? this.year,
      customTypes: customTypes ?? this.customTypes,
      entries: entries ?? this.entries,
      visibility: visibility ?? this.visibility,
    );
  }
}
