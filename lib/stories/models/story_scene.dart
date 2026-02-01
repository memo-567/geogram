/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'story_element.dart';
import 'story_trigger.dart';

/// Scene background configuration - always requires an image
class SceneBackground {
  /// Image asset path (required)
  final String? asset;

  /// Placeholder/letterbox color (shown where image doesn't cover)
  final String placeholder;

  /// When background appears (ms from scene start, 0-5000)
  final int appearAt;

  const SceneBackground({
    this.asset,
    this.placeholder = '#000000',
    this.appearAt = 0,
  });

  /// Whether the background has an image set
  bool get hasImage => asset != null && asset!.isNotEmpty;

  factory SceneBackground.fromJson(Map<String, dynamic> json) {
    return SceneBackground(
      asset: json['asset'] as String?,
      placeholder: json['placeholder'] as String? ??
          json['color'] as String? ??
          '#000000',
      appearAt: (json['appearAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (asset != null) 'asset': asset,
      'placeholder': placeholder,
      if (appearAt > 0) 'appearAt': appearAt,
    };
  }

  SceneBackground copyWith({
    String? asset,
    String? placeholder,
    int? appearAt,
  }) {
    return SceneBackground(
      asset: asset ?? this.asset,
      placeholder: placeholder ?? this.placeholder,
      appearAt: appearAt ?? this.appearAt,
    );
  }
}

/// Auto-advance configuration for timed navigation
class AutoAdvance {
  /// Delay in milliseconds (1000-60000, i.e., 1-60 seconds)
  final int delay;

  /// Target scene to navigate to
  final String targetSceneId;

  /// Whether to show countdown in lower-right corner
  final bool showCountdown;

  const AutoAdvance({
    required this.delay,
    required this.targetSceneId,
    this.showCountdown = true,
  });

  factory AutoAdvance.fromJson(Map<String, dynamic> json) {
    return AutoAdvance(
      delay: (json['delay'] as num).toInt().clamp(1000, 60000),
      targetSceneId: json['targetSceneId'] as String,
      showCountdown: json['showCountdown'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'delay': delay,
      'targetSceneId': targetSceneId,
      'showCountdown': showCountdown,
    };
  }

  /// Get delay in seconds
  int get delaySeconds => (delay / 1000).round();
}

/// A scene in a story - represents a single view with elements and triggers.
class StoryScene {
  /// Unique scene identifier
  final String id;

  /// Scene order (0-based)
  final int index;

  /// Optional scene title
  final String? title;

  /// Override global back navigation setting for this scene
  final bool? allowBack;

  /// Scene background
  final SceneBackground background;

  /// Elements positioned on the scene
  final List<StoryElement> elements;

  /// Triggers for user interaction
  final List<StoryTrigger> triggers;

  /// Auto-advance configuration (optional)
  final AutoAdvance? autoAdvance;

  const StoryScene({
    required this.id,
    required this.index,
    this.title,
    this.allowBack,
    required this.background,
    this.elements = const [],
    this.triggers = const [],
    this.autoAdvance,
  });

  /// Get elements sorted by appearAt time
  List<StoryElement> get elementsByAppearTime {
    final sorted = List<StoryElement>.from(elements);
    sorted.sort((a, b) => a.appearAt.compareTo(b.appearAt));
    return sorted;
  }

  /// Get trigger for a specific element
  StoryTrigger? getTriggerForElement(String elementId) {
    return triggers.cast<StoryTrigger?>().firstWhere(
          (t) => t?.elementId == elementId,
          orElse: () => null,
        );
  }

  /// Get triggers for touch areas (no element attached)
  List<StoryTrigger> get touchAreaTriggers {
    return triggers.where((t) => t.touchArea != null).toList();
  }

  factory StoryScene.fromJson(Map<String, dynamic> json) {
    return StoryScene(
      id: json['id'] as String,
      index: (json['index'] as num?)?.toInt() ?? 0,
      title: json['title'] as String?,
      allowBack: json['allowBack'] as bool?,
      background: json['background'] != null
          ? SceneBackground.fromJson(json['background'] as Map<String, dynamic>)
          : const SceneBackground(),
      elements: (json['elements'] as List<dynamic>?)
              ?.map((e) => StoryElement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      triggers: (json['triggers'] as List<dynamic>?)
              ?.map((e) => StoryTrigger.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      autoAdvance: json['autoAdvance'] != null
          ? AutoAdvance.fromJson(json['autoAdvance'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index': index,
      if (title != null) 'title': title,
      if (allowBack != null) 'allowBack': allowBack,
      'background': background.toJson(),
      'elements': elements.map((e) => e.toJson()).toList(),
      'triggers': triggers.map((t) => t.toJson()).toList(),
      if (autoAdvance != null) 'autoAdvance': autoAdvance!.toJson(),
    };
  }

  StoryScene copyWith({
    String? id,
    int? index,
    String? title,
    bool? allowBack,
    SceneBackground? background,
    List<StoryElement>? elements,
    List<StoryTrigger>? triggers,
    AutoAdvance? autoAdvance,
  }) {
    return StoryScene(
      id: id ?? this.id,
      index: index ?? this.index,
      title: title ?? this.title,
      allowBack: allowBack ?? this.allowBack,
      background: background ?? this.background,
      elements: elements ?? this.elements,
      triggers: triggers ?? this.triggers,
      autoAdvance: autoAdvance ?? this.autoAdvance,
    );
  }
}
