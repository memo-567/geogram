/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Types of triggers available in stories
enum TriggerType {
  /// Navigate to another scene
  goToScene,

  /// Open external URL in browser
  openUrl,

  /// Play audio from assets
  playSound,

  /// Show a popup dialog with title and message
  showPopup,
}

/// Touch areas for triggers without visible elements
enum TouchArea {
  leftHalf,
  rightHalf,
  topHalf,
  bottomHalf,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center,
}

/// A trigger that fires an action on user interaction or timer.
class StoryTrigger {
  /// Unique trigger identifier
  final String id;

  /// Type of action to perform
  final TriggerType type;

  /// Element ID this trigger is attached to (optional)
  final String? elementId;

  /// Touch area for triggers without elements (optional)
  final TouchArea? touchArea;

  /// Target scene ID (for goToScene)
  final String? targetSceneId;

  /// URL to open (for openUrl)
  final String? url;

  /// Sound asset path (for playSound)
  final String? soundAsset;

  /// Popup title (for showPopup)
  final String? popupTitle;

  /// Popup message (for showPopup)
  final String? popupMessage;

  const StoryTrigger({
    required this.id,
    required this.type,
    this.elementId,
    this.touchArea,
    this.targetSceneId,
    this.url,
    this.soundAsset,
    this.popupTitle,
    this.popupMessage,
  });

  factory StoryTrigger.goToScene({
    required String id,
    required String targetSceneId,
    String? elementId,
    TouchArea? touchArea,
  }) {
    return StoryTrigger(
      id: id,
      type: TriggerType.goToScene,
      targetSceneId: targetSceneId,
      elementId: elementId,
      touchArea: touchArea,
    );
  }

  factory StoryTrigger.openUrl({
    required String id,
    required String url,
    String? elementId,
  }) {
    return StoryTrigger(
      id: id,
      type: TriggerType.openUrl,
      url: url,
      elementId: elementId,
    );
  }

  factory StoryTrigger.playSound({
    required String id,
    required String soundAsset,
    String? elementId,
  }) {
    return StoryTrigger(
      id: id,
      type: TriggerType.playSound,
      soundAsset: soundAsset,
      elementId: elementId,
    );
  }

  factory StoryTrigger.showPopup({
    required String id,
    required String title,
    required String message,
    String? elementId,
  }) {
    return StoryTrigger(
      id: id,
      type: TriggerType.showPopup,
      popupTitle: title,
      popupMessage: message,
      elementId: elementId,
    );
  }

  factory StoryTrigger.fromJson(Map<String, dynamic> json) {
    return StoryTrigger(
      id: json['id'] as String,
      type: TriggerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TriggerType.goToScene,
      ),
      elementId: json['elementId'] as String?,
      touchArea: json['touchArea'] != null
          ? TouchArea.values.firstWhere(
              (e) => e.name == json['touchArea'],
              orElse: () => TouchArea.center,
            )
          : null,
      targetSceneId: json['targetSceneId'] as String?,
      url: json['url'] as String?,
      soundAsset: json['soundAsset'] as String?,
      popupTitle: json['popupTitle'] as String?,
      popupMessage: json['popupMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      if (elementId != null) 'elementId': elementId,
      if (touchArea != null) 'touchArea': touchArea!.name,
      if (targetSceneId != null) 'targetSceneId': targetSceneId,
      if (url != null) 'url': url,
      if (soundAsset != null) 'soundAsset': soundAsset,
      if (popupTitle != null) 'popupTitle': popupTitle,
      if (popupMessage != null) 'popupMessage': popupMessage,
    };
  }

  StoryTrigger copyWith({
    String? id,
    TriggerType? type,
    String? elementId,
    TouchArea? touchArea,
    String? targetSceneId,
    String? url,
    String? soundAsset,
    String? popupTitle,
    String? popupMessage,
  }) {
    return StoryTrigger(
      id: id ?? this.id,
      type: type ?? this.type,
      elementId: elementId ?? this.elementId,
      touchArea: touchArea ?? this.touchArea,
      targetSceneId: targetSceneId ?? this.targetSceneId,
      url: url ?? this.url,
      soundAsset: soundAsset ?? this.soundAsset,
      popupTitle: popupTitle ?? this.popupTitle,
      popupMessage: popupMessage ?? this.popupMessage,
    );
  }
}
