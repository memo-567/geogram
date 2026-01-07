/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Information about a Whisper speech recognition model available for download
class WhisperModelInfo {
  /// Unique identifier for the model
  final String id;

  /// Display name
  final String name;

  /// Model tier: 'tiny', 'base', 'small', 'medium', 'large'
  final String tier;

  /// Model size in bytes
  final int size;

  /// Download URL (HuggingFace ggerganov/whisper.cpp)
  final String url;

  /// Model filename (e.g., 'ggml-small.bin')
  final String filename;

  /// Brief description of the model
  final String description;

  /// Minimum recommended RAM in MB
  final int minRamMb;

  /// Estimated realtime factor (e.g., 16.0 means 16x realtime speed)
  final double realtimeFactor;

  const WhisperModelInfo({
    required this.id,
    required this.name,
    required this.tier,
    required this.size,
    required this.url,
    required this.filename,
    required this.description,
    this.minRamMb = 400,
    this.realtimeFactor = 1.0,
  });

  /// Get human-readable size string
  String get sizeString {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Get tier display name
  String get tierDisplayName {
    switch (tier) {
      case 'tiny':
        return 'Tiny';
      case 'base':
        return 'Base';
      case 'small':
        return 'Small';
      case 'medium':
        return 'Medium';
      case 'large':
        return 'Large';
      default:
        return tier;
    }
  }

  /// Get estimated transcription time for a given audio duration
  Duration estimatedTranscriptionTime(Duration audioDuration) {
    if (realtimeFactor <= 0) return audioDuration;
    return Duration(
      milliseconds: (audioDuration.inMilliseconds / realtimeFactor).round(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tier': tier,
        'size': size,
        'url': url,
        'filename': filename,
        'description': description,
        'minRamMb': minRamMb,
        'realtimeFactor': realtimeFactor,
      };

  factory WhisperModelInfo.fromJson(Map<String, dynamic> json) {
    return WhisperModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      tier: json['tier'] as String,
      size: json['size'] as int,
      url: json['url'] as String,
      filename: json['filename'] as String,
      description: json['description'] as String,
      minRamMb: json['minRamMb'] as int? ?? 400,
      realtimeFactor: (json['realtimeFactor'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Available Whisper models for download
class WhisperModels {
  /// HuggingFace base URL for whisper.cpp models
  static const String huggingFaceBaseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

  static const List<WhisperModelInfo> available = [
    // Tiny - fastest, lower accuracy
    WhisperModelInfo(
      id: 'whisper-tiny',
      name: 'Whisper Tiny',
      tier: 'tiny',
      size: 39 * 1024 * 1024, // ~39 MB
      url: '$huggingFaceBaseUrl/ggml-tiny.bin',
      filename: 'ggml-tiny.bin',
      description: 'Fastest transcription, lower accuracy - good for quick notes',
      minRamMb: 200,
      realtimeFactor: 32.0,
    ),

    // Base - good balance (DEFAULT)
    WhisperModelInfo(
      id: 'whisper-base',
      name: 'Whisper Base',
      tier: 'base',
      size: 145 * 1024 * 1024, // ~145 MB
      url: '$huggingFaceBaseUrl/ggml-base.bin',
      filename: 'ggml-base.bin',
      description: 'Good balance of speed and accuracy, recommended for most uses',
      minRamMb: 400,
      realtimeFactor: 16.0,
    ),

    // Small - better accuracy
    WhisperModelInfo(
      id: 'whisper-small',
      name: 'Whisper Small',
      tier: 'small',
      size: 465 * 1024 * 1024, // ~465 MB
      url: '$huggingFaceBaseUrl/ggml-small.bin',
      filename: 'ggml-small.bin',
      description: 'Better accuracy, slower processing',
      minRamMb: 800,
      realtimeFactor: 6.0,
    ),

    // Medium - high accuracy
    WhisperModelInfo(
      id: 'whisper-medium',
      name: 'Whisper Medium',
      tier: 'medium',
      size: 1500 * 1024 * 1024, // ~1.5 GB
      url: '$huggingFaceBaseUrl/ggml-medium.bin',
      filename: 'ggml-medium.bin',
      description: 'High accuracy, slower processing',
      minRamMb: 2000,
      realtimeFactor: 2.0,
    ),

    // Large v2 - best accuracy
    WhisperModelInfo(
      id: 'whisper-large-v2',
      name: 'Whisper Large v2',
      tier: 'large',
      size: 3000 * 1024 * 1024, // ~3 GB
      url: '$huggingFaceBaseUrl/ggml-large-v2.bin',
      filename: 'ggml-large-v2.bin',
      description: 'Best accuracy, requires significant resources',
      minRamMb: 4000,
      realtimeFactor: 1.0,
    ),
  ];

  /// Default model ID
  static const String defaultModelId = 'whisper-base';

  /// Get the default model
  static WhisperModelInfo get defaultModel =>
      available.firstWhere((m) => m.id == defaultModelId);

  /// Get models by tier
  static List<WhisperModelInfo> byTier(String tier) =>
      available.where((m) => m.tier == tier).toList();

  /// Get model by ID
  static WhisperModelInfo? getById(String id) {
    try {
      return available.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get recommended models based on device RAM
  static List<WhisperModelInfo> recommendedForRam(int availableRamMb) =>
      available.where((m) => m.minRamMb <= availableRamMb).toList();
}
