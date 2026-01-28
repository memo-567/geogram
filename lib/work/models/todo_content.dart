/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Sort order for TODO items
enum TodoSortOrder {
  createdAsc,
  createdDesc,
  completedFirst,
  pendingFirst,
}

/// A link attached to a TODO item
class TodoLink {
  final String id;
  final String title;
  final String url;

  TodoLink({
    required this.id,
    required this.title,
    required this.url,
  });

  factory TodoLink.create({required String title, required String url}) {
    final id = 'link-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    return TodoLink(id: id, title: title, url: url);
  }

  factory TodoLink.fromJson(Map<String, dynamic> json) {
    return TodoLink(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
  };

  TodoLink copyWith({String? title, String? url}) {
    return TodoLink(
      id: id,
      title: title ?? this.title,
      url: url ?? this.url,
    );
  }
}

/// An update/note attached to a TODO item
class TodoUpdate {
  final String id;
  final String content;
  final DateTime createdAt;

  TodoUpdate({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  factory TodoUpdate.create({required String content}) {
    final now = DateTime.now();
    final id = 'upd-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return TodoUpdate(id: id, content: content, createdAt: now);
  }

  factory TodoUpdate.fromJson(Map<String, dynamic> json) {
    return TodoUpdate(
      id: json['id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };
}

/// A single TODO item
class TodoItem {
  final String id;
  String title;
  String? description;
  final DateTime createdAt;
  DateTime? completedAt;
  bool isCompleted;
  List<String> pictures;
  List<TodoLink> links;
  List<TodoUpdate> updates;

  TodoItem({
    required this.id,
    required this.title,
    this.description,
    required this.createdAt,
    this.completedAt,
    this.isCompleted = false,
    List<String>? pictures,
    List<TodoLink>? links,
    List<TodoUpdate>? updates,
  }) : pictures = pictures ?? [],
       links = links ?? [],
       updates = updates ?? [];

  factory TodoItem.create({required String title, String? description}) {
    final now = DateTime.now();
    final id = 'item-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return TodoItem(
      id: id,
      title: title,
      description: description,
      createdAt: now,
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      isCompleted: json['is_completed'] as bool? ?? false,
      pictures: (json['pictures'] as List<dynamic>?)
          ?.map((p) => p as String)
          .toList() ?? [],
      links: (json['links'] as List<dynamic>?)
          ?.map((l) => TodoLink.fromJson(l as Map<String, dynamic>))
          .toList() ?? [],
      updates: (json['updates'] as List<dynamic>?)
          ?.map((u) => TodoUpdate.fromJson(u as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'created_at': createdAt.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    'is_completed': isCompleted,
    if (pictures.isNotEmpty) 'pictures': pictures,
    if (links.isNotEmpty) 'links': links.map((l) => l.toJson()).toList(),
    if (updates.isNotEmpty) 'updates': updates.map((u) => u.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Toggle completion status
  void toggleCompleted() {
    isCompleted = !isCompleted;
    completedAt = isCompleted ? DateTime.now() : null;
  }

  /// Get duration summary for completed items
  String? get durationSummary {
    if (!isCompleted || completedAt == null) return null;

    final duration = completedAt!.difference(createdAt);

    if (duration.inDays >= 1) {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      if (hours > 0) {
        return '${days}d ${hours}h';
      }
      return '${days}d';
    } else if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${hours}h';
    } else if (duration.inMinutes >= 1) {
      return '${duration.inMinutes}m';
    } else {
      return '<1m';
    }
  }

  /// Add a picture path
  void addPicture(String path) {
    pictures.add(path);
  }

  /// Remove a picture path
  void removePicture(String path) {
    pictures.remove(path);
  }

  /// Add a link
  void addLink(TodoLink link) {
    links.add(link);
  }

  /// Remove a link
  void removeLink(String linkId) {
    links.removeWhere((l) => l.id == linkId);
  }

  /// Add an update
  void addUpdate(TodoUpdate update) {
    updates.add(update);
  }

  /// Remove an update
  void removeUpdate(String updateId) {
    updates.removeWhere((u) => u.id == updateId);
  }

  TodoItem copyWith({
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? completedAt,
    List<String>? pictures,
    List<TodoLink>? links,
    List<TodoUpdate>? updates,
  }) {
    return TodoItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      pictures: pictures ?? List.from(this.pictures),
      links: links ?? List.from(this.links),
      updates: updates ?? List.from(this.updates),
    );
  }
}

/// Settings for TODO list display
class TodoSettings {
  final bool showCompleted;
  final TodoSortOrder sortOrder;
  final bool defaultExpanded;

  TodoSettings({
    this.showCompleted = true,
    this.sortOrder = TodoSortOrder.createdDesc,
    this.defaultExpanded = false,
  });

  factory TodoSettings.fromJson(Map<String, dynamic> json) {
    return TodoSettings(
      showCompleted: json['show_completed'] as bool? ?? true,
      sortOrder: TodoSortOrder.values.firstWhere(
        (s) => s.name == json['sort_order'],
        orElse: () => TodoSortOrder.createdDesc,
      ),
      defaultExpanded: json['default_expanded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'show_completed': showCompleted,
    'sort_order': sortOrder.name,
    'default_expanded': defaultExpanded,
  };

  TodoSettings copyWith({
    bool? showCompleted,
    TodoSortOrder? sortOrder,
    bool? defaultExpanded,
  }) {
    return TodoSettings(
      showCompleted: showCompleted ?? this.showCompleted,
      sortOrder: sortOrder ?? this.sortOrder,
      defaultExpanded: defaultExpanded ?? this.defaultExpanded,
    );
  }
}

/// Main TODO document content (stored in content/main.json)
class TodoContent {
  final String id;
  final String schema;
  String title;
  int version;
  final DateTime created;
  DateTime modified;
  TodoSettings settings;
  List<String> items; // List of item IDs

  TodoContent({
    required this.id,
    this.schema = 'ndf-todo-1.0',
    required this.title,
    this.version = 1,
    required this.created,
    required this.modified,
    TodoSettings? settings,
    List<String>? items,
  }) : settings = settings ?? TodoSettings(),
       items = items ?? [];

  factory TodoContent.create({required String title}) {
    final now = DateTime.now();
    final id = 'todo-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return TodoContent(
      id: id,
      title: title,
      created: now,
      modified: now,
    );
  }

  factory TodoContent.fromJson(Map<String, dynamic> json) {
    // Handle missing id, created, modified for backwards compatibility
    final now = DateTime.now();
    final id = json['id'] as String? ?? 'todo-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final createdStr = json['created'] as String?;
    final modifiedStr = json['modified'] as String?;
    final created = createdStr != null ? DateTime.parse(createdStr) : now;
    final modified = modifiedStr != null ? DateTime.parse(modifiedStr) : now;

    TodoSettings? settings;
    final settingsJson = json['settings'] as Map<String, dynamic>?;
    if (settingsJson != null) {
      settings = TodoSettings.fromJson(settingsJson);
    }

    return TodoContent(
      id: id,
      schema: json['schema'] as String? ?? 'ndf-todo-1.0',
      title: json['title'] as String? ?? 'Untitled TODO',
      version: json['version'] as int? ?? 1,
      created: created,
      modified: modified,
      settings: settings,
      items: (json['items'] as List<dynamic>?)
          ?.map((i) => i as String)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'todo',
    'id': id,
    'schema': schema,
    'title': title,
    'version': version,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'settings': settings.toJson(),
    'items': items,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Touch the modified timestamp and increment version
  void touch() {
    modified = DateTime.now();
    version++;
  }

  /// Add an item ID
  void addItem(String itemId) {
    items.add(itemId);
    touch();
  }

  /// Remove an item ID
  void removeItem(String itemId) {
    items.remove(itemId);
    touch();
  }
}
