/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// A music playlist
class MusicPlaylist {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int trackCount;
  final int totalDurationSeconds;
  final String? artwork;
  final List<String> trackPaths;

  MusicPlaylist({
    required this.id,
    required this.name,
    this.description,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.trackCount = 0,
    this.totalDurationSeconds = 0,
    this.artwork,
    List<String>? trackPaths,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now(),
        trackPaths = trackPaths ?? [];

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      modifiedAt: json['modified_at'] != null
          ? DateTime.parse(json['modified_at'] as String)
          : null,
      trackCount: json['track_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      artwork: json['artwork'] as String?,
      trackPaths: (json['track_paths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'created_at': createdAt.toIso8601String(),
      'modified_at': modifiedAt.toIso8601String(),
      'track_count': trackCount,
      'total_duration_seconds': totalDurationSeconds,
      if (artwork != null) 'artwork': artwork,
      'track_paths': trackPaths,
    };
  }

  MusicPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? trackCount,
    int? totalDurationSeconds,
    String? artwork,
    List<String>? trackPaths,
  }) {
    return MusicPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      trackCount: trackCount ?? this.trackCount,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      artwork: artwork ?? this.artwork,
      trackPaths: trackPaths ?? this.trackPaths,
    );
  }

  /// Get formatted duration string
  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h ${minutes} min';
    }
    return '$minutes min';
  }

  /// Generate playlist ID from name
  static String generateId(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .trim();
    return 'playlist_$normalized';
  }

  /// Generate M3U8 content for export
  String toM3u8() {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#PLAYLIST:$name');
    buffer.writeln();

    for (final path in trackPaths) {
      // Simple format - just the path
      buffer.writeln(path);
    }

    return buffer.toString();
  }

  /// Parse M3U8 content
  static List<String> parseM3u8(String content) {
    final paths = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      // Skip empty lines, comments, and extended info
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      paths.add(trimmed);
    }

    return paths;
  }
}

/// Smart playlist based on query rules (future feature)
class SmartPlaylist {
  final String id;
  final String name;
  final String type; // 'smart'
  final SmartPlaylistRules rules;
  final SmartPlaylistSort? sort;
  final int? limit;

  SmartPlaylist({
    required this.id,
    required this.name,
    this.type = 'smart',
    required this.rules,
    this.sort,
    this.limit,
  });

  factory SmartPlaylist.fromJson(Map<String, dynamic> json) {
    return SmartPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'smart',
      rules: SmartPlaylistRules.fromJson(json['rules'] as Map<String, dynamic>),
      sort: json['sort'] != null
          ? SmartPlaylistSort.fromJson(json['sort'] as Map<String, dynamic>)
          : null,
      limit: json['limit'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'rules': rules.toJson(),
      if (sort != null) 'sort': sort!.toJson(),
      if (limit != null) 'limit': limit,
    };
  }
}

class SmartPlaylistRules {
  final String match; // 'all' or 'any'
  final List<SmartPlaylistCondition> conditions;

  SmartPlaylistRules({
    this.match = 'all',
    List<SmartPlaylistCondition>? conditions,
  }) : conditions = conditions ?? [];

  factory SmartPlaylistRules.fromJson(Map<String, dynamic> json) {
    return SmartPlaylistRules(
      match: json['match'] as String? ?? 'all',
      conditions: (json['conditions'] as List<dynamic>?)
              ?.map((e) =>
                  SmartPlaylistCondition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'match': match,
      'conditions': conditions.map((c) => c.toJson()).toList(),
    };
  }
}

class SmartPlaylistCondition {
  final String field; // 'added_at', 'genre', 'artist', 'year', 'play_count'
  final String operator; // 'equals', 'contains', 'within', 'greater', 'less'
  final String value;

  SmartPlaylistCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  factory SmartPlaylistCondition.fromJson(Map<String, dynamic> json) {
    return SmartPlaylistCondition(
      field: json['field'] as String,
      operator: json['operator'] as String,
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'operator': operator,
      'value': value,
    };
  }
}

class SmartPlaylistSort {
  final String field;
  final String order; // 'asc' or 'desc'

  SmartPlaylistSort({
    required this.field,
    this.order = 'desc',
  });

  factory SmartPlaylistSort.fromJson(Map<String, dynamic> json) {
    return SmartPlaylistSort(
      field: json['field'] as String,
      order: json['order'] as String? ?? 'desc',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'order': order,
    };
  }
}
