/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Type of content source
enum SourceType {
  rss,
  manga,
}

/// Feed type for RSS sources
enum FeedType {
  auto,
  rss,
  atom,
  custom,
}

/// Configuration for a content source
class Source {
  final String id;
  final String name;
  final SourceType type;
  final String? url;
  final String? icon;
  final FeedType feedType;
  final SourceSettings settings;
  final bool isLocal;
  final String path;
  DateTime? lastFetchedAt;
  int postCount;
  int unreadCount;
  String? error;
  DateTime createdAt;
  DateTime modifiedAt;

  Source({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.icon,
    this.feedType = FeedType.auto,
    SourceSettings? settings,
    this.isLocal = false,
    required this.path,
    this.lastFetchedAt,
    this.postCount = 0,
    this.unreadCount = 0,
    this.error,
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : settings = settings ?? SourceSettings(),
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  factory Source.fromJson(Map<String, dynamic> json, String path) {
    return Source(
      id: json['id'] as String,
      name: json['name'] as String,
      type: SourceType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SourceType.rss,
      ),
      url: json['url'] as String?,
      icon: json['icon'] as String?,
      feedType: FeedType.values.firstWhere(
        (t) => t.name == json['feed_type'],
        orElse: () => FeedType.auto,
      ),
      settings: json['settings'] != null
          ? SourceSettings.fromJson(json['settings'] as Map<String, dynamic>)
          : SourceSettings(),
      isLocal: json['local'] as bool? ?? false,
      path: path,
      lastFetchedAt: json['last_fetched_at'] != null
          ? DateTime.parse(json['last_fetched_at'] as String)
          : null,
      postCount: json['post_count'] as int? ?? 0,
      unreadCount: json['unread_count'] as int? ?? 0,
      error: json['error'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      modifiedAt: json['modified_at'] != null
          ? DateTime.parse(json['modified_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'url': url,
      'icon': icon,
      'feed_type': feedType.name,
      'settings': settings.toJson(),
      'local': isLocal,
      'last_fetched_at': lastFetchedAt?.toIso8601String(),
      'post_count': postCount,
      'unread_count': unreadCount,
      'error': error,
      'created_at': createdAt.toIso8601String(),
      'modified_at': modifiedAt.toIso8601String(),
    };
  }

  Source copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? url,
    String? icon,
    FeedType? feedType,
    SourceSettings? settings,
    bool? isLocal,
    String? path,
    DateTime? lastFetchedAt,
    int? postCount,
    int? unreadCount,
    String? error,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return Source(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      url: url ?? this.url,
      icon: icon ?? this.icon,
      feedType: feedType ?? this.feedType,
      settings: settings ?? this.settings,
      isLocal: isLocal ?? this.isLocal,
      path: path ?? this.path,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      postCount: postCount ?? this.postCount,
      unreadCount: unreadCount ?? this.unreadCount,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}

/// Settings for a source
class SourceSettings {
  final int maxPosts;
  final int fetchIntervalHours;
  final bool downloadImages;

  SourceSettings({
    this.maxPosts = 100,
    this.fetchIntervalHours = 1,
    this.downloadImages = true,
  });

  factory SourceSettings.fromJson(Map<String, dynamic> json) {
    return SourceSettings(
      maxPosts: json['maxPosts'] as int? ?? 100,
      fetchIntervalHours: json['fetchIntervalHours'] as int? ?? 1,
      downloadImages: json['downloadImages'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxPosts': maxPosts,
      'fetchIntervalHours': fetchIntervalHours,
      'downloadImages': downloadImages,
    };
  }
}

/// Configuration parsed from source.js
class SourceConfig {
  final String name;
  final String type;
  final String? url;
  final String? icon;
  final String? feedType;
  final bool? local;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? folderStructure;

  SourceConfig({
    required this.name,
    required this.type,
    this.url,
    this.icon,
    this.feedType,
    this.local,
    this.settings,
    this.folderStructure,
  });

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    return SourceConfig(
      name: json['name'] as String,
      type: json['type'] as String,
      url: json['url'] as String?,
      icon: json['icon'] as String?,
      feedType: json['feedType'] as String?,
      local: json['local'] as bool?,
      settings: json['settings'] as Map<String, dynamic>?,
      folderStructure: json['folderStructure'] as Map<String, dynamic>?,
    );
  }
}
