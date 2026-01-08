import 'tracker_metadata.dart';
import 'tracker_visibility.dart';

/// Built-in measurement types
enum MeasurementType {
  weight,
  height,
  bloodPressure,
  heartRate,
  bloodGlucose,
  bodyFat,
  bodyTemperature,
  bodyWater,
  muscleMass,
  custom,
}

/// Configuration for a measurement type
class MeasurementTypeConfig {
  final String typeId;
  final String displayName;
  final String unit;
  final double? minValue;
  final double? maxValue;
  final int decimalPlaces;

  const MeasurementTypeConfig({
    required this.typeId,
    required this.displayName,
    required this.unit,
    this.minValue,
    this.maxValue,
    this.decimalPlaces = 1,
  });

  /// Built-in measurement type configurations
  static const Map<String, MeasurementTypeConfig> builtInTypes = {
    'weight': MeasurementTypeConfig(
      typeId: 'weight',
      displayName: 'Weight',
      unit: 'kg',
      minValue: 0,
      maxValue: 500,
      decimalPlaces: 1,
    ),
    'height': MeasurementTypeConfig(
      typeId: 'height',
      displayName: 'Height',
      unit: 'cm',
      minValue: 0,
      maxValue: 300,
      decimalPlaces: 1,
    ),
    'heart_rate': MeasurementTypeConfig(
      typeId: 'heart_rate',
      displayName: 'Heart Rate',
      unit: 'bpm',
      minValue: 0,
      maxValue: 300,
      decimalPlaces: 0,
    ),
    'blood_glucose': MeasurementTypeConfig(
      typeId: 'blood_glucose',
      displayName: 'Blood Glucose',
      unit: 'mg/dL',
      minValue: 0,
      maxValue: 600,
      decimalPlaces: 0,
    ),
    'body_fat': MeasurementTypeConfig(
      typeId: 'body_fat',
      displayName: 'Body Fat',
      unit: '%',
      minValue: 0,
      maxValue: 100,
      decimalPlaces: 1,
    ),
    'body_temperature': MeasurementTypeConfig(
      typeId: 'body_temperature',
      displayName: 'Temperature',
      unit: '\u00B0C',
      minValue: 30,
      maxValue: 45,
      decimalPlaces: 1,
    ),
    'body_water': MeasurementTypeConfig(
      typeId: 'body_water',
      displayName: 'Body Water',
      unit: '%',
      minValue: 0,
      maxValue: 100,
      decimalPlaces: 1,
    ),
    'muscle_mass': MeasurementTypeConfig(
      typeId: 'muscle_mass',
      displayName: 'Muscle Mass',
      unit: 'kg',
      minValue: 0,
      maxValue: 200,
      decimalPlaces: 1,
    ),
  };

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'display_name': displayName,
        'unit': unit,
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        'decimal_places': decimalPlaces,
      };

  factory MeasurementTypeConfig.fromJson(Map<String, dynamic> json) {
    return MeasurementTypeConfig(
      typeId: json['type_id'] as String,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      decimalPlaces: json['decimal_places'] as int? ?? 1,
    );
  }
}

/// Goal for a measurement type
class MeasurementGoal {
  final double targetValue;
  final String? targetDate;
  final String direction; // increase, decrease, maintain

  const MeasurementGoal({
    required this.targetValue,
    this.targetDate,
    this.direction = 'maintain',
  });

  Map<String, dynamic> toJson() => {
        'target_value': targetValue,
        if (targetDate != null) 'target_date': targetDate,
        'direction': direction,
      };

  factory MeasurementGoal.fromJson(Map<String, dynamic> json) {
    return MeasurementGoal(
      targetValue: (json['target_value'] as num).toDouble(),
      targetDate: json['target_date'] as String?,
      direction: json['direction'] as String? ?? 'maintain',
    );
  }
}

/// A single measurement entry
class MeasurementEntry {
  final String id;
  final String timestamp;
  final double value;
  final String? notes;
  final List<String> tags;
  final TrackerNostrMetadata? metadata;

  const MeasurementEntry({
    required this.id,
    required this.timestamp,
    required this.value,
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
        'value': value,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory MeasurementEntry.fromJson(Map<String, dynamic> json) {
    return MeasurementEntry(
      id: json['id'] as String,
      timestamp: json['timestamp'] as String,
      value: (json['value'] as num).toDouble(),
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

  MeasurementEntry copyWith({
    String? id,
    String? timestamp,
    double? value,
    String? notes,
    List<String>? tags,
    TrackerNostrMetadata? metadata,
  }) {
    return MeasurementEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      value: value ?? this.value,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Blood pressure entry (special case with systolic/diastolic)
class BloodPressureEntry {
  final String id;
  final String timestamp;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final String? arm; // left, right
  final String? position; // sitting, standing, lying
  final String? notes;
  final List<String> tags;
  final TrackerNostrMetadata? metadata;

  const BloodPressureEntry({
    required this.id,
    required this.timestamp,
    required this.systolic,
    required this.diastolic,
    this.heartRate,
    this.arm,
    this.position,
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

  String get displayValue => '$systolic/$diastolic';

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'systolic': systolic,
        'diastolic': diastolic,
        if (heartRate != null) 'heart_rate': heartRate,
        if (arm != null) 'arm': arm,
        if (position != null) 'position': position,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (tags.isNotEmpty) 'tags': tags,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory BloodPressureEntry.fromJson(Map<String, dynamic> json) {
    return BloodPressureEntry(
      id: json['id'] as String,
      timestamp: json['timestamp'] as String,
      systolic: json['systolic'] as int,
      diastolic: json['diastolic'] as int,
      heartRate: json['heart_rate'] as int?,
      arm: json['arm'] as String?,
      position: json['position'] as String?,
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
}

/// Statistics for a measurement type
class MeasurementStatistics {
  final int count;
  final double min;
  final double max;
  final double avg;
  final String? firstEntry;
  final String? lastEntry;

  const MeasurementStatistics({
    this.count = 0,
    this.min = 0,
    this.max = 0,
    this.avg = 0,
    this.firstEntry,
    this.lastEntry,
  });

  factory MeasurementStatistics.calculate(List<MeasurementEntry> entries) {
    if (entries.isEmpty) {
      return const MeasurementStatistics();
    }

    final values = entries.map((e) => e.value).toList()..sort();
    final sum = values.fold<double>(0, (a, b) => a + b);

    // Sort by timestamp to find first and last
    final sorted = List<MeasurementEntry>.from(entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return MeasurementStatistics(
      count: entries.length,
      min: values.first,
      max: values.last,
      avg: sum / entries.length,
      firstEntry: sorted.first.timestamp,
      lastEntry: sorted.last.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'min': min,
        'max': max,
        'avg': avg,
        if (firstEntry != null) 'first_entry': firstEntry,
        if (lastEntry != null) 'last_entry': lastEntry,
      };

  factory MeasurementStatistics.fromJson(Map<String, dynamic> json) {
    return MeasurementStatistics(
      count: json['count'] as int? ?? 0,
      min: (json['min'] as num?)?.toDouble() ?? 0,
      max: (json['max'] as num?)?.toDouble() ?? 0,
      avg: (json['avg'] as num?)?.toDouble() ?? 0,
      firstEntry: json['first_entry'] as String?,
      lastEntry: json['last_entry'] as String?,
    );
  }
}

/// Measurement data file (e.g., weight.json)
class MeasurementData {
  final String typeId;
  final int year;
  final String displayName;
  final String unit;
  final double? minValue;
  final double? maxValue;
  final int decimalPlaces;
  final MeasurementGoal? goal;
  final List<MeasurementEntry> entries;
  final MeasurementStatistics? statistics;
  final TrackerVisibility? visibility;

  const MeasurementData({
    required this.typeId,
    required this.year,
    required this.displayName,
    required this.unit,
    this.minValue,
    this.maxValue,
    this.decimalPlaces = 1,
    this.goal,
    this.entries = const [],
    this.statistics,
    this.visibility,
  });

  /// Create from a built-in type
  factory MeasurementData.fromType(String typeId, int year) {
    final config = MeasurementTypeConfig.builtInTypes[typeId];
    if (config == null) {
      return MeasurementData(
        typeId: typeId,
        year: year,
        displayName: typeId,
        unit: 'units',
      );
    }
    return MeasurementData(
      typeId: config.typeId,
      year: year,
      displayName: config.displayName,
      unit: config.unit,
      minValue: config.minValue,
      maxValue: config.maxValue,
      decimalPlaces: config.decimalPlaces,
    );
  }

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'year': year,
        'display_name': displayName,
        'unit': unit,
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        'decimal_places': decimalPlaces,
        if (goal != null) 'goal': goal!.toJson(),
        'entries': entries.map((e) => e.toJson()).toList(),
        if (statistics != null) 'statistics': statistics!.toJson(),
        if (visibility != null) 'visibility': visibility!.toJson(),
      };

  factory MeasurementData.fromJson(Map<String, dynamic> json) {
    return MeasurementData(
      typeId: json['type_id'] as String,
      year: json['year'] as int,
      displayName: json['display_name'] as String,
      unit: json['unit'] as String,
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      decimalPlaces: json['decimal_places'] as int? ?? 1,
      goal: json['goal'] != null
          ? MeasurementGoal.fromJson(json['goal'] as Map<String, dynamic>)
          : null,
      entries: (json['entries'] as List<dynamic>?)
              ?.map(
                  (e) => MeasurementEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      statistics: json['statistics'] != null
          ? MeasurementStatistics.fromJson(
              json['statistics'] as Map<String, dynamic>)
          : null,
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
    );
  }

  MeasurementData copyWith({
    String? typeId,
    int? year,
    String? displayName,
    String? unit,
    double? minValue,
    double? maxValue,
    int? decimalPlaces,
    MeasurementGoal? goal,
    List<MeasurementEntry>? entries,
    MeasurementStatistics? statistics,
    TrackerVisibility? visibility,
  }) {
    return MeasurementData(
      typeId: typeId ?? this.typeId,
      year: year ?? this.year,
      displayName: displayName ?? this.displayName,
      unit: unit ?? this.unit,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      goal: goal ?? this.goal,
      entries: entries ?? this.entries,
      statistics: statistics ?? this.statistics,
      visibility: visibility ?? this.visibility,
    );
  }

  /// Add a new entry and recalculate statistics
  MeasurementData addEntry(MeasurementEntry entry) {
    final newEntries = [...entries, entry];
    return copyWith(
      entries: newEntries,
      statistics: MeasurementStatistics.calculate(newEntries),
    );
  }

  /// Remove an entry and recalculate statistics
  MeasurementData removeEntry(String entryId) {
    final newEntries = entries.where((e) => e.id != entryId).toList();
    return copyWith(
      entries: newEntries,
      statistics: MeasurementStatistics.calculate(newEntries),
    );
  }
}

/// Blood pressure data file (special structure)
class BloodPressureData {
  final String typeId;
  final int year;
  final String displayName;
  final List<BloodPressureEntry> entries;
  final TrackerVisibility? visibility;

  const BloodPressureData({
    this.typeId = 'blood_pressure',
    required this.year,
    this.displayName = 'Blood Pressure',
    this.entries = const [],
    this.visibility,
  });

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'year': year,
        'display_name': displayName,
        'entries': entries.map((e) => e.toJson()).toList(),
        if (visibility != null) 'visibility': visibility!.toJson(),
      };

  factory BloodPressureData.fromJson(Map<String, dynamic> json) {
    return BloodPressureData(
      typeId: json['type_id'] as String? ?? 'blood_pressure',
      year: json['year'] as int,
      displayName: json['display_name'] as String? ?? 'Blood Pressure',
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) =>
                  BloodPressureEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      visibility: json['visibility'] != null
          ? TrackerVisibility.fromJson(
              json['visibility'] as Map<String, dynamic>)
          : null,
    );
  }

  BloodPressureData copyWith({
    String? typeId,
    int? year,
    String? displayName,
    List<BloodPressureEntry>? entries,
    TrackerVisibility? visibility,
  }) {
    return BloodPressureData(
      typeId: typeId ?? this.typeId,
      year: year ?? this.year,
      displayName: displayName ?? this.displayName,
      entries: entries ?? this.entries,
      visibility: visibility ?? this.visibility,
    );
  }

  /// Add a new entry
  BloodPressureData addEntry(BloodPressureEntry entry) {
    return copyWith(entries: [...entries, entry]);
  }

  /// Remove an entry
  BloodPressureData removeEntry(String entryId) {
    return copyWith(entries: entries.where((e) => e.id != entryId).toList());
  }
}
