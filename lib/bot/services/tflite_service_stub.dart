/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Stub implementation of TFLiteService for web platform
/// TFLite is not supported on web, so this provides no-op implementations

import 'dart:typed_data';

import '../models/vision_result.dart' show DetectedObject;

/// Service for running TensorFlow Lite vision models (web stub)
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  /// Check if a model is loaded (always false on web)
  bool get isModelLoaded => false;

  /// Get currently loaded model ID (always null on web)
  String? get loadedModelId => null;

  /// Load a TFLite model from file (not supported on web)
  Future<void> loadModel(String modelPath, {String? labelsPath}) async {
    throw UnsupportedError('TFLite is not supported on web platform');
  }

  /// Preprocess an image for model input (not supported on web)
  Float32List preprocessImage(String imagePath, int inputSize) {
    throw UnsupportedError('TFLite is not supported on web platform');
  }

  /// Run classification inference on an image (not supported on web)
  Future<List<ClassificationResult>> classify(
    String imagePath, {
    int inputSize = 224,
    int topK = 5,
  }) async {
    throw UnsupportedError('TFLite is not supported on web platform');
  }

  /// Run object detection on an image (not supported on web)
  Future<List<DetectedObject>> detectObjects(
    String imagePath, {
    int inputSize = 320,
    double confidenceThreshold = 0.5,
  }) async {
    throw UnsupportedError('TFLite is not supported on web platform');
  }

  /// Close the interpreter and free resources
  void close() {}

  void dispose() {}
}

/// Result of image classification
class ClassificationResult {
  final String label;
  final double confidence;
  final int index;

  const ClassificationResult({
    required this.label,
    required this.confidence,
    required this.index,
  });

  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(1)}%)';
}
