/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Information about a vision model available for download
class VisionModelInfo {
  /// Unique identifier for the model
  final String id;

  /// Display name
  final String name;

  /// Model tier: 'lite', 'standard', 'quality', 'premium'
  final String tier;

  /// Category: 'general', 'plant', 'ocr', 'detection'
  final String category;

  /// Model size in bytes
  final int size;

  /// List of capabilities: 'classification', 'object_detection', 'visual_qa', 'ocr', 'translation', 'plant_id'
  final List<String> capabilities;

  /// Download URL (HuggingFace or other source)
  final String url;

  /// Model format: 'tflite', 'gguf'
  final String format;

  /// Brief description of the model
  final String description;

  /// Minimum recommended RAM in MB
  final int minRamMb;

  const VisionModelInfo({
    required this.id,
    required this.name,
    required this.tier,
    required this.category,
    required this.size,
    required this.capabilities,
    required this.url,
    required this.format,
    required this.description,
    this.minRamMb = 500,
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

  /// Check if model supports a specific capability
  bool hasCapability(String capability) => capabilities.contains(capability);

  /// Get tier display name
  String get tierDisplayName {
    switch (tier) {
      case 'lite':
        return 'Lite';
      case 'standard':
        return 'Standard';
      case 'quality':
        return 'Quality';
      case 'premium':
        return 'Premium';
      default:
        return tier;
    }
  }

  /// Get category display name
  String get categoryDisplayName {
    switch (category) {
      case 'general':
        return 'General Vision';
      case 'plant':
        return 'Plant & Nature';
      case 'ocr':
        return 'Text Recognition';
      case 'detection':
        return 'Object Detection';
      default:
        return category;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tier': tier,
        'category': category,
        'size': size,
        'capabilities': capabilities,
        'url': url,
        'format': format,
        'description': description,
        'minRamMb': minRamMb,
      };

  factory VisionModelInfo.fromJson(Map<String, dynamic> json) {
    return VisionModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      tier: json['tier'] as String,
      category: json['category'] as String,
      size: json['size'] as int,
      capabilities: (json['capabilities'] as List<dynamic>).cast<String>(),
      url: json['url'] as String,
      format: json['format'] as String,
      description: json['description'] as String,
      minRamMb: json['minRamMb'] as int? ?? 500,
    );
  }
}

/// Available vision models for download
class VisionModels {
  static const List<VisionModelInfo> available = [
    // Lite tier - TensorFlow Lite models (fast, small)
    VisionModelInfo(
      id: 'mobilenet-v3',
      name: 'MobileNet v3',
      tier: 'lite',
      category: 'general',
      size: 5 * 1024 * 1024, // 5 MB
      capabilities: ['classification'],
      url: 'https://tfhub.dev/google/lite-model/imagenet/mobilenet_v3_small_100_224/classification/5/default/1',
      format: 'tflite',
      description: 'Fast image classification - identifies objects in photos',
      minRamMb: 100,
    ),
    VisionModelInfo(
      id: 'efficientdet-lite0',
      name: 'EfficientDet Lite',
      tier: 'lite',
      category: 'detection',
      size: 20 * 1024 * 1024, // 20 MB
      capabilities: ['object_detection'],
      url: 'https://tfhub.dev/tensorflow/lite-model/efficientdet/lite0/detection/metadata/1',
      format: 'tflite',
      description: 'Object detection with bounding boxes',
      minRamMb: 200,
    ),
    VisionModelInfo(
      id: 'plant-classifier',
      name: 'Plant Classifier',
      tier: 'lite',
      category: 'plant',
      size: 80 * 1024 * 1024, // 80 MB
      capabilities: ['plant_id', 'classification'],
      url: 'https://huggingface.co/google/plant-classifier-lite/resolve/main/model.tflite',
      format: 'tflite',
      description: 'Identify plant species from photos',
      minRamMb: 300,
    ),
    VisionModelInfo(
      id: 'paddle-ocr-lite',
      name: 'PaddleOCR Lite',
      tier: 'lite',
      category: 'ocr',
      size: 15 * 1024 * 1024, // 15 MB
      capabilities: ['ocr'],
      url: 'https://huggingface.co/PaddlePaddle/ppocr-lite/resolve/main/model.tflite',
      format: 'tflite',
      description: 'Extract text from images (multilingual)',
      minRamMb: 200,
    ),

    // Standard tier - Quantized multimodal models
    VisionModelInfo(
      id: 'llava-7b-q3',
      name: 'LLaVA 7B (Q3)',
      tier: 'standard',
      category: 'general',
      size: 800 * 1024 * 1024, // 800 MB
      capabilities: ['visual_qa', 'classification', 'ocr', 'translation'],
      url: 'https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q3_k.gguf',
      format: 'gguf',
      description: 'Full visual Q&A - ask any question about images',
      minRamMb: 1500,
    ),

    // Quality tier - Better quantization
    VisionModelInfo(
      id: 'llava-7b-q4',
      name: 'LLaVA 7B (Q4)',
      tier: 'quality',
      category: 'general',
      size: 1200 * 1024 * 1024, // 1.2 GB
      capabilities: ['visual_qa', 'classification', 'ocr', 'translation'],
      url: 'https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q4_k.gguf',
      format: 'gguf',
      description: 'Better quality visual Q&A with improved accuracy',
      minRamMb: 2000,
    ),
    VisionModelInfo(
      id: 'qwen2-vl-7b-q4',
      name: 'Qwen2-VL 7B (Q4)',
      tier: 'quality',
      category: 'general',
      size: 1000 * 1024 * 1024, // 1 GB
      capabilities: ['visual_qa', 'classification', 'ocr', 'translation', 'transliteration'],
      url: 'https://huggingface.co/Qwen/Qwen2-VL-7B-Instruct-GGUF/resolve/main/qwen2-vl-7b-instruct-q4_k_m.gguf',
      format: 'gguf',
      description: 'Multilingual vision - best for translation and OCR',
      minRamMb: 2000,
    ),

    // Premium tier - Highest quality
    VisionModelInfo(
      id: 'llava-7b-q6',
      name: 'LLaVA 7B (Q6)',
      tier: 'premium',
      category: 'general',
      size: 2000 * 1024 * 1024, // 2 GB
      capabilities: ['visual_qa', 'classification', 'ocr', 'translation'],
      url: 'https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q6_k.gguf',
      format: 'gguf',
      description: 'Highest quality visual understanding',
      minRamMb: 2500,
    ),
  ];

  /// Get models by tier
  static List<VisionModelInfo> byTier(String tier) =>
      available.where((m) => m.tier == tier).toList();

  /// Get models by category
  static List<VisionModelInfo> byCategory(String category) =>
      available.where((m) => m.category == category).toList();

  /// Get models by capability
  static List<VisionModelInfo> withCapability(String capability) =>
      available.where((m) => m.hasCapability(capability)).toList();

  /// Get model by ID
  static VisionModelInfo? getById(String id) {
    try {
      return available.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
