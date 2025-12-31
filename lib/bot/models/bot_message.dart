/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'vision_result.dart';

/// Represents a message in the bot conversation
class BotMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<String> sources;
  final bool isThinking;
  final String? error;

  /// Path to attached image (if any)
  final String? imagePath;

  /// Vision analysis result (for image messages)
  final VisionResult? visionResult;

  const BotMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.sources = const [],
    this.isThinking = false,
    this.error,
    this.imagePath,
    this.visionResult,
  });

  /// Check if this message has an image
  bool get hasImage => imagePath != null;

  BotMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    List<String>? sources,
    bool? isThinking,
    String? error,
    String? imagePath,
    VisionResult? visionResult,
  }) {
    return BotMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      sources: sources ?? this.sources,
      isThinking: isThinking ?? this.isThinking,
      error: error ?? this.error,
      imagePath: imagePath ?? this.imagePath,
      visionResult: visionResult ?? this.visionResult,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'sources': sources,
      'error': error,
      if (imagePath != null) 'imagePath': imagePath,
      if (visionResult != null) 'visionResult': visionResult!.toJson(),
    };
  }

  factory BotMessage.fromJson(Map<String, dynamic> json) {
    return BotMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sources: (json['sources'] as List<dynamic>?)?.cast<String>() ?? [],
      error: json['error'] as String?,
      imagePath: json['imagePath'] as String?,
      visionResult: json['visionResult'] != null
          ? VisionResult.fromJson(json['visionResult'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Create a user message
  factory BotMessage.user(String content, {String? imagePath}) {
    return BotMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
      imagePath: imagePath,
    );
  }

  /// Create a bot response message
  factory BotMessage.bot(
    String content, {
    List<String> sources = const [],
    VisionResult? visionResult,
  }) {
    return BotMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
      sources: sources,
      visionResult: visionResult,
    );
  }

  /// Create a thinking indicator message
  factory BotMessage.thinking() {
    return BotMessage(
      id: 'thinking_${DateTime.now().millisecondsSinceEpoch}',
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      isThinking: true,
    );
  }

  /// Create an error message
  factory BotMessage.error(String errorMessage) {
    return BotMessage(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}',
      content: errorMessage,
      isUser: false,
      timestamp: DateTime.now(),
      error: errorMessage,
    );
  }
}
