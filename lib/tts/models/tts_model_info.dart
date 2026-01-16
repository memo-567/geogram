/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Voice options for Supertonic TTS
enum TtsVoice {
  m1, // Male voice 1
  m2, // Male voice 2
  m3, // Male voice 3
  m4, // Male voice 4
  m5, // Male voice 5
  f1, // Female voice 1
  f2, // Female voice 2
  f3, // Female voice 3
  f4, // Female voice 4
  f5, // Female voice 5
}

/// Language options for Supertonic TTS
enum TtsLanguage {
  en, // English
  pt, // Portuguese
  es, // Spanish
  fr, // French
  ko, // Korean
}

/// Extension methods for TtsVoice
extension TtsVoiceExtension on TtsVoice {
  /// Get the voice ID string for Supertonic (uppercase: M1, F1, etc.)
  String get id => name.toUpperCase();

  /// Get the filename for the voice style JSON
  String get filename => '$id.json';

  /// Get display name
  String get displayName {
    switch (this) {
      case TtsVoice.m1:
        return 'Male 1';
      case TtsVoice.m2:
        return 'Male 2';
      case TtsVoice.m3:
        return 'Male 3';
      case TtsVoice.m4:
        return 'Male 4';
      case TtsVoice.m5:
        return 'Male 5';
      case TtsVoice.f1:
        return 'Female 1';
      case TtsVoice.f2:
        return 'Female 2';
      case TtsVoice.f3:
        return 'Female 3';
      case TtsVoice.f4:
        return 'Female 4';
      case TtsVoice.f5:
        return 'Female 5';
    }
  }

  /// Whether this is a male voice
  bool get isMale => name.startsWith('m');
}

/// Extension methods for TtsLanguage
extension TtsLanguageExtension on TtsLanguage {
  /// Get the language code for Supertonic
  String get code => name;

  /// Get display name
  String get displayName {
    switch (this) {
      case TtsLanguage.en:
        return 'English';
      case TtsLanguage.pt:
        return 'Portuguese';
      case TtsLanguage.es:
        return 'Spanish';
      case TtsLanguage.fr:
        return 'French';
      case TtsLanguage.ko:
        return 'Korean';
    }
  }

  /// Get language from Geogram locale code
  static TtsLanguage fromLocale(String locale) {
    if (locale.startsWith('pt')) return TtsLanguage.pt;
    if (locale.startsWith('es')) return TtsLanguage.es;
    if (locale.startsWith('fr')) return TtsLanguage.fr;
    if (locale.startsWith('ko')) return TtsLanguage.ko;
    return TtsLanguage.en; // Default to English
  }
}

/// Information about a Supertonic TTS model available for download
class TtsModelInfo {
  /// Unique identifier for the model
  final String id;

  /// Display name
  final String name;

  /// Model size in bytes
  final int size;

  /// Download URL (HuggingFace)
  final String url;

  /// Model filename
  final String filename;

  /// Brief description of the model
  final String description;

  /// Supported languages
  final List<TtsLanguage> languages;

  /// Minimum recommended RAM in MB
  final int minRamMb;

  const TtsModelInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.url,
    required this.filename,
    required this.description,
    required this.languages,
    this.minRamMb = 256,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'url': url,
        'filename': filename,
        'description': description,
        'languages': languages.map((l) => l.code).toList(),
        'minRamMb': minRamMb,
      };

  factory TtsModelInfo.fromJson(Map<String, dynamic> json) {
    return TtsModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      url: json['url'] as String,
      filename: json['filename'] as String,
      description: json['description'] as String,
      languages: (json['languages'] as List<dynamic>)
          .map((l) => TtsLanguage.values.firstWhere(
                (v) => v.code == l,
                orElse: () => TtsLanguage.en,
              ))
          .toList(),
      minRamMb: json['minRamMb'] as int? ?? 256,
    );
  }
}

/// Individual file in the Supertonic TTS bundle
class TtsOnnxFile {
  final String name;
  final String filename;
  final int size;
  final String? subdir;

  const TtsOnnxFile({
    required this.name,
    required this.filename,
    required this.size,
    this.subdir = 'onnx',
  });

  String get url =>
      '${TtsModels.huggingFaceBaseUrl}/$subdir/$filename';
}

/// Available Supertonic TTS models for download
class TtsModels {
  /// HuggingFace base URL for Supertonic models
  static const String huggingFaceBaseUrl =
      'https://huggingface.co/Supertone/supertonic-2/resolve/main';

  /// ONNX files required for the Supertonic pipeline
  static const List<TtsOnnxFile> onnxFiles = [
    TtsOnnxFile(
      name: 'Text Encoder',
      filename: 'text_encoder.onnx',
      size: 27 * 1024 * 1024, // ~27 MB
    ),
    TtsOnnxFile(
      name: 'Duration Predictor',
      filename: 'duration_predictor.onnx',
      size: 2 * 1024 * 1024, // ~1.5 MB
    ),
    TtsOnnxFile(
      name: 'Vector Estimator',
      filename: 'vector_estimator.onnx',
      size: 132 * 1024 * 1024, // ~132 MB
    ),
    TtsOnnxFile(
      name: 'Vocoder',
      filename: 'vocoder.onnx',
      size: 101 * 1024 * 1024, // ~101 MB
    ),
  ];

  /// Config files required
  static const List<TtsOnnxFile> configFiles = [
    TtsOnnxFile(
      name: 'TTS Config',
      filename: 'tts.json',
      size: 9 * 1024, // ~9 KB
    ),
    TtsOnnxFile(
      name: 'Unicode Indexer',
      filename: 'unicode_indexer.json',
      size: 262 * 1024, // ~262 KB
    ),
  ];

  /// Voice style files - each ~420 KB
  static List<TtsOnnxFile> get voiceStyleFiles => TtsVoice.values
      .map((v) => TtsOnnxFile(
            name: 'Voice ${v.displayName}',
            filename: v.filename,
            size: 420 * 1024, // ~420 KB each
            subdir: 'voice_styles',
          ))
      .toList();

  /// All files required for Supertonic TTS
  static List<TtsOnnxFile> get allFiles =>
      [...onnxFiles, ...configFiles, ...voiceStyleFiles];

  /// Total size of all files
  static int get totalSize =>
      allFiles.fold(0, (sum, file) => sum + file.size);

  static const List<TtsModelInfo> available = [
    TtsModelInfo(
      id: 'supertonic-2',
      name: 'Supertonic 2',
      size: 263 * 1024 * 1024, // ~263 MB total
      url: huggingFaceBaseUrl,
      filename: 'onnx', // Directory name
      description:
          'Fast on-device text-to-speech with natural voice synthesis',
      languages: [
        TtsLanguage.en,
        TtsLanguage.pt,
        TtsLanguage.es,
        TtsLanguage.fr,
        TtsLanguage.ko,
      ],
      minRamMb: 512,
    ),
  ];

  /// Default model ID
  static const String defaultModelId = 'supertonic-2';

  /// Get the default model
  static TtsModelInfo get defaultModel =>
      available.firstWhere((m) => m.id == defaultModelId);

  /// Get model by ID
  static TtsModelInfo? getById(String id) {
    try {
      return available.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Voice style data loaded from JSON for Supertonic TTS.
///
/// Contains two style tensors:
/// - styleTtl: [1, 50, 256] tensor for text-to-latent model
/// - styleDp: [1, 8, 16] tensor for duration predictor
class VoiceStyle {
  /// Style tensor for text-to-latent model: shape [1, 50, 256]
  final List<double> styleTtl;

  /// Style tensor for duration predictor: shape [1, 8, 16]
  final List<double> styleDp;

  /// Dimensions for styleTtl tensor
  final List<int> styleTtlDims;

  /// Dimensions for styleDp tensor
  final List<int> styleDpDims;

  const VoiceStyle({
    required this.styleTtl,
    required this.styleDp,
    required this.styleTtlDims,
    required this.styleDpDims,
  });

  /// Load voice style from JSON map
  factory VoiceStyle.fromJson(Map<String, dynamic> json) {
    final ttlData = json['style_ttl'] as Map<String, dynamic>;
    final dpData = json['style_dp'] as Map<String, dynamic>;

    return VoiceStyle(
      styleTtl: (ttlData['data'] as List).cast<num>().map((n) => n.toDouble()).toList(),
      styleDp: (dpData['data'] as List).cast<num>().map((n) => n.toDouble()).toList(),
      styleTtlDims: (ttlData['dims'] as List).cast<int>(),
      styleDpDims: (dpData['dims'] as List).cast<int>(),
    );
  }
}
