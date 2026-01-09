import 'package:flutter/material.dart';

/// Types of paths that can be recorded
enum TrackerPathType {
  walk('walk', Icons.directions_walk),
  travel('travel', Icons.travel_explore),
  run('run', Icons.directions_run),
  bicycle('bicycle', Icons.directions_bike),
  car('car', Icons.directions_car),
  train('train', Icons.train),
  airplane('airplane', Icons.flight),
  hike('hike', Icons.terrain),
  other('other', Icons.route);

  final String id;
  final IconData icon;

  const TrackerPathType(this.id, this.icon);

  /// Get the translation key for this path type
  String get translationKey => 'tracker_path_type_$id';

  /// Convert to a tag string for storage
  String toTag() => 'type:$id';

  /// Parse from a tag string
  static TrackerPathType? fromTag(String tag) {
    if (!tag.startsWith('type:')) return null;
    final typeId = tag.substring(5);
    return TrackerPathType.values.cast<TrackerPathType?>().firstWhere(
          (t) => t?.id == typeId,
          orElse: () => null,
        );
  }

  /// Parse from a type ID
  static TrackerPathType fromId(String id) {
    return TrackerPathType.values.firstWhere(
      (t) => t.id == id,
      orElse: () => TrackerPathType.other,
    );
  }

  /// Extract path type from a list of tags
  static TrackerPathType? fromTags(List<String> tags) {
    for (final tag in tags) {
      final type = fromTag(tag);
      if (type != null) return type;
    }
    return null;
  }

  /// Get all path types as a list
  static List<TrackerPathType> get all => TrackerPathType.values.toList();
}
