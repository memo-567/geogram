/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'story_scene.dart';

/// Story-wide settings
class StorySettings {
  /// Default transition type between scenes
  final String defaultTransition;

  /// Transition duration in milliseconds
  final int transitionDuration;

  /// Whether to show scene titles
  final bool showSceneTitle;

  /// Whether to allow swipe navigation
  final bool enableSwipeNavigation;

  /// Whether to allow back navigation (global setting)
  final bool allowBackNavigation;

  const StorySettings({
    this.defaultTransition = 'fade',
    this.transitionDuration = 300,
    this.showSceneTitle = false,
    this.enableSwipeNavigation = true,
    this.allowBackNavigation = true,
  });

  factory StorySettings.fromJson(Map<String, dynamic> json) {
    return StorySettings(
      defaultTransition: json['defaultTransition'] as String? ?? 'fade',
      transitionDuration: (json['transitionDuration'] as num?)?.toInt() ?? 300,
      showSceneTitle: json['showSceneTitle'] as bool? ?? false,
      enableSwipeNavigation: json['enableSwipeNavigation'] as bool? ?? true,
      allowBackNavigation: json['allowBackNavigation'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultTransition': defaultTransition,
      'transitionDuration': transitionDuration,
      'showSceneTitle': showSceneTitle,
      'enableSwipeNavigation': enableSwipeNavigation,
      'allowBackNavigation': allowBackNavigation,
    };
  }

  StorySettings copyWith({
    String? defaultTransition,
    int? transitionDuration,
    bool? showSceneTitle,
    bool? enableSwipeNavigation,
    bool? allowBackNavigation,
  }) {
    return StorySettings(
      defaultTransition: defaultTransition ?? this.defaultTransition,
      transitionDuration: transitionDuration ?? this.transitionDuration,
      showSceneTitle: showSceneTitle ?? this.showSceneTitle,
      enableSwipeNavigation:
          enableSwipeNavigation ?? this.enableSwipeNavigation,
      allowBackNavigation: allowBackNavigation ?? this.allowBackNavigation,
    );
  }
}

/// Story content stored in content/main.json
class StoryContent {
  /// Content type (always 'story')
  final String type;

  /// Schema version
  final String schema;

  /// ID of the first scene to display
  final String startSceneId;

  /// Story-wide settings
  final StorySettings settings;

  /// Ordered list of scene IDs
  final List<String> sceneIds;

  /// Loaded scenes (may be loaded on demand)
  final Map<String, StoryScene> scenes;

  const StoryContent({
    this.type = 'story',
    this.schema = 'ndf-story-1.0',
    required this.startSceneId,
    this.settings = const StorySettings(),
    this.sceneIds = const [],
    this.scenes = const {},
  });

  /// Get scene by ID
  StoryScene? getScene(String id) => scenes[id];

  /// Get the start scene
  StoryScene? get startScene => scenes[startSceneId];

  /// Get scenes in order
  List<StoryScene> get orderedScenes {
    return sceneIds.map((id) => scenes[id]).whereType<StoryScene>().toList();
  }

  /// Get scene count
  int get sceneCount => sceneIds.length;

  /// Check if back navigation is allowed for a specific scene
  bool isBackAllowed(StoryScene scene) {
    return scene.allowBack ?? settings.allowBackNavigation;
  }

  factory StoryContent.fromJson(
    Map<String, dynamic> json, {
    Map<String, StoryScene>? loadedScenes,
  }) {
    final sceneIds = (json['scenes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return StoryContent(
      type: json['type'] as String? ?? 'story',
      schema: json['schema'] as String? ?? 'ndf-story-1.0',
      startSceneId: json['startSceneId'] as String? ?? sceneIds.firstOrNull ?? '',
      settings: json['settings'] != null
          ? StorySettings.fromJson(json['settings'] as Map<String, dynamic>)
          : const StorySettings(),
      sceneIds: sceneIds,
      scenes: loadedScenes ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'schema': schema,
      'startSceneId': startSceneId,
      'settings': settings.toJson(),
      'scenes': sceneIds,
    };
  }

  StoryContent copyWith({
    String? type,
    String? schema,
    String? startSceneId,
    StorySettings? settings,
    List<String>? sceneIds,
    Map<String, StoryScene>? scenes,
  }) {
    return StoryContent(
      type: type ?? this.type,
      schema: schema ?? this.schema,
      startSceneId: startSceneId ?? this.startSceneId,
      settings: settings ?? this.settings,
      sceneIds: sceneIds ?? this.sceneIds,
      scenes: scenes ?? this.scenes,
    );
  }

  /// Add a scene to the content
  StoryContent addScene(StoryScene scene) {
    final newSceneIds = [...sceneIds, scene.id];
    final newScenes = {...scenes, scene.id: scene};
    return copyWith(
      sceneIds: newSceneIds,
      scenes: newScenes,
      startSceneId: startSceneId.isEmpty ? scene.id : startSceneId,
    );
  }

  /// Remove a scene from the content
  StoryContent removeScene(String sceneId) {
    final newSceneIds = sceneIds.where((id) => id != sceneId).toList();
    final newScenes = Map<String, StoryScene>.from(scenes)..remove(sceneId);
    return copyWith(
      sceneIds: newSceneIds,
      scenes: newScenes,
      startSceneId: startSceneId == sceneId
          ? (newSceneIds.firstOrNull ?? '')
          : startSceneId,
    );
  }

  /// Update a scene in the content
  StoryContent updateScene(StoryScene scene) {
    final newScenes = {...scenes, scene.id: scene};
    return copyWith(scenes: newScenes);
  }

  /// Reorder scenes
  StoryContent reorderScenes(List<String> newOrder) {
    // Update scene indices
    final newScenes = <String, StoryScene>{};
    for (var i = 0; i < newOrder.length; i++) {
      final scene = scenes[newOrder[i]];
      if (scene != null) {
        newScenes[newOrder[i]] = scene.copyWith(index: i);
      }
    }
    return copyWith(sceneIds: newOrder, scenes: newScenes);
  }
}
