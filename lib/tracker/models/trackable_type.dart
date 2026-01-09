// Unified trackable type system for exercises and measurements.
// Both are fundamentally the same: tracking numeric values over time.

/// Kind of trackable (exercise or measurement)
enum TrackableKind {
  exercise,
  measurement,
}

/// Category for exercise types
enum TrackableCategory {
  strength,
  cardio,
  flexibility,
  health, // For measurements
}

/// Unified configuration for any trackable type (exercise or measurement)
class TrackableTypeConfig {
  final String id;
  final String displayName;
  final String unit;
  final TrackableKind kind;
  final TrackableCategory category;
  final int decimalPlaces; // 0 for integers (exercises), 1+ for decimals (measurements)
  final double? minValue;
  final double? maxValue;
  final int? maxCount; // Max value for dropdown (e.g., 100 for exercises)

  const TrackableTypeConfig({
    required this.id,
    required this.displayName,
    required this.unit,
    required this.kind,
    required this.category,
    this.decimalPlaces = 0,
    this.minValue,
    this.maxValue,
    this.maxCount,
  });

  bool get isExercise => kind == TrackableKind.exercise;
  bool get isMeasurement => kind == TrackableKind.measurement;
  bool get isInteger => decimalPlaces == 0;
  bool get isCardio => category == TrackableCategory.cardio;

  /// All built-in trackable types (exercises + measurements)
  static const Map<String, TrackableTypeConfig> builtInTypes = {
    // === EXERCISES ===
    'pushups': TrackableTypeConfig(
      id: 'pushups',
      displayName: 'Push-ups',
      unit: 'reps',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 100,
    ),
    'abdominals': TrackableTypeConfig(
      id: 'abdominals',
      displayName: 'Abdominals',
      unit: 'reps',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 100,
    ),
    'squats': TrackableTypeConfig(
      id: 'squats',
      displayName: 'Squats',
      unit: 'reps',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 100,
    ),
    'pullups': TrackableTypeConfig(
      id: 'pullups',
      displayName: 'Pull-ups',
      unit: 'reps',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 100,
    ),
    'lunges': TrackableTypeConfig(
      id: 'lunges',
      displayName: 'Lunges',
      unit: 'reps',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 100,
    ),
    'planks': TrackableTypeConfig(
      id: 'planks',
      displayName: 'Planks',
      unit: 'seconds',
      kind: TrackableKind.exercise,
      category: TrackableCategory.strength,
      maxCount: 300,
    ),
    'running': TrackableTypeConfig(
      id: 'running',
      displayName: 'Running',
      unit: 'meters',
      kind: TrackableKind.exercise,
      category: TrackableCategory.cardio,
      maxCount: 50000,
    ),
    'walking': TrackableTypeConfig(
      id: 'walking',
      displayName: 'Walking',
      unit: 'meters',
      kind: TrackableKind.exercise,
      category: TrackableCategory.cardio,
      maxCount: 50000,
    ),
    'cycling': TrackableTypeConfig(
      id: 'cycling',
      displayName: 'Cycling',
      unit: 'meters',
      kind: TrackableKind.exercise,
      category: TrackableCategory.cardio,
      maxCount: 100000,
    ),
    'swimming': TrackableTypeConfig(
      id: 'swimming',
      displayName: 'Swimming',
      unit: 'meters',
      kind: TrackableKind.exercise,
      category: TrackableCategory.cardio,
      maxCount: 10000,
    ),

    // === MEASUREMENTS ===
    'weight': TrackableTypeConfig(
      id: 'weight',
      displayName: 'Weight',
      unit: 'kg',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 0,
      maxValue: 500,
    ),
    'height': TrackableTypeConfig(
      id: 'height',
      displayName: 'Height',
      unit: 'cm',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 0,
      maxValue: 300,
    ),
    'heart_rate': TrackableTypeConfig(
      id: 'heart_rate',
      displayName: 'Heart Rate',
      unit: 'bpm',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 0,
      minValue: 0,
      maxValue: 300,
    ),
    'blood_glucose': TrackableTypeConfig(
      id: 'blood_glucose',
      displayName: 'Blood Glucose',
      unit: 'mg/dL',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 0,
      minValue: 0,
      maxValue: 600,
    ),
    'body_fat': TrackableTypeConfig(
      id: 'body_fat',
      displayName: 'Body Fat',
      unit: '%',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 0,
      maxValue: 100,
    ),
    'body_temperature': TrackableTypeConfig(
      id: 'body_temperature',
      displayName: 'Temperature',
      unit: '\u00B0C',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 30,
      maxValue: 45,
    ),
    'body_water': TrackableTypeConfig(
      id: 'body_water',
      displayName: 'Body Water',
      unit: '%',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 0,
      maxValue: 100,
    ),
    'muscle_mass': TrackableTypeConfig(
      id: 'muscle_mass',
      displayName: 'Muscle Mass',
      unit: 'kg',
      kind: TrackableKind.measurement,
      category: TrackableCategory.health,
      decimalPlaces: 1,
      minValue: 0,
      maxValue: 200,
    ),
  };

  /// Get only exercise types
  static Map<String, TrackableTypeConfig> get exerciseTypes =>
      Map.fromEntries(builtInTypes.entries.where((e) => e.value.isExercise));

  /// Get only measurement types
  static Map<String, TrackableTypeConfig> get measurementTypes =>
      Map.fromEntries(builtInTypes.entries.where((e) => e.value.isMeasurement));

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'unit': unit,
        'kind': kind.name,
        'category': category.name,
        'decimal_places': decimalPlaces,
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        if (maxCount != null) 'max_count': maxCount,
      };

  factory TrackableTypeConfig.fromJson(Map<String, dynamic> json) {
    return TrackableTypeConfig(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      kind: TrackableKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => TrackableKind.exercise,
      ),
      category: TrackableCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => TrackableCategory.health,
      ),
      decimalPlaces: json['decimal_places'] as int? ?? 0,
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      maxCount: json['max_count'] as int?,
    );
  }
}
