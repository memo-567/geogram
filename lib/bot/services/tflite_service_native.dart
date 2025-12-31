/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/vision_result.dart' show DetectedObject, BoundingBox;
import '../../services/log_service.dart';

/// Service for running TensorFlow Lite vision models
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  /// Currently loaded interpreter
  Interpreter? _interpreter;

  /// ID of currently loaded model
  String? _loadedModelId;

  /// Labels for classification models
  List<String>? _labels;

  /// Check if a model is loaded
  bool get isModelLoaded => _interpreter != null;

  /// Get currently loaded model ID
  String? get loadedModelId => _loadedModelId;

  /// Load a TFLite model from file
  Future<void> loadModel(String modelPath, {String? labelsPath}) async {
    try {
      // Close existing interpreter
      _interpreter?.close();
      _interpreter = null;
      _loadedModelId = null;
      _labels = null;

      // Check if model file exists
      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $modelPath');
      }

      // Load interpreter
      _interpreter = Interpreter.fromFile(modelFile);

      // Extract model ID from path
      _loadedModelId = modelPath.split('/').last.split('.').first;

      // Load labels if provided
      if (labelsPath != null) {
        final labelsFile = File(labelsPath);
        if (await labelsFile.exists()) {
          final content = await labelsFile.readAsString();
          _labels = content.split('\n').where((l) => l.isNotEmpty).toList();
        }
      }

      LogService().log('TFLiteService: Loaded model from $modelPath');
    } catch (e) {
      LogService().log('TFLiteService: Error loading model: $e');
      rethrow;
    }
  }

  /// Preprocess an image for model input
  /// Returns normalized float array suitable for TFLite input
  Float32List preprocessImage(String imagePath, int inputSize) {
    // Read image file
    final bytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image: $imagePath');
    }

    // Resize to model input size
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to normalized float array [0, 1]
    final buffer = Float32List(inputSize * inputSize * 3);
    var index = 0;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        buffer[index++] = pixel.r / 255.0;
        buffer[index++] = pixel.g / 255.0;
        buffer[index++] = pixel.b / 255.0;
      }
    }

    return buffer;
  }

  /// Run classification inference on an image
  Future<List<ClassificationResult>> classify(
    String imagePath, {
    int inputSize = 224,
    int topK = 5,
  }) async {
    if (_interpreter == null) {
      throw Exception('No model loaded');
    }

    try {
      // Preprocess image
      final input = preprocessImage(imagePath, inputSize);

      // Reshape input for model [1, height, width, channels]
      final inputShape = [1, inputSize, inputSize, 3];
      final inputTensor = input.reshape(inputShape);

      // Get output shape from model
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final numClasses = outputShape[1];

      // Create output buffer
      final output = List.generate(
        1,
        (_) => List.filled(numClasses, 0.0),
      );

      // Run inference
      _interpreter!.run(inputTensor, output);

      // Get top-K results
      final results = <ClassificationResult>[];
      final scores = output[0];

      // Create list of (index, score) pairs
      final indexed = List.generate(
        scores.length,
        (i) => MapEntry(i, scores[i]),
      );

      // Sort by score descending
      indexed.sort((a, b) => b.value.compareTo(a.value));

      // Take top K
      for (var i = 0; i < topK && i < indexed.length; i++) {
        final index = indexed[i].key;
        final score = indexed[i].value;

        // Skip low confidence results
        if (score < 0.01) break;

        final label = _labels != null && index < _labels!.length
            ? _labels![index]
            : 'Class $index';

        results.add(ClassificationResult(
          label: label,
          confidence: score,
          index: index,
        ));
      }

      return results;
    } catch (e) {
      LogService().log('TFLiteService: Classification error: $e');
      rethrow;
    }
  }

  /// Run object detection on an image
  Future<List<DetectedObject>> detectObjects(
    String imagePath, {
    int inputSize = 320,
    double confidenceThreshold = 0.5,
  }) async {
    if (_interpreter == null) {
      throw Exception('No model loaded');
    }

    try {
      // Preprocess image
      final input = preprocessImage(imagePath, inputSize);

      // Reshape input
      final inputShape = [1, inputSize, inputSize, 3];
      final inputTensor = input.reshape(inputShape);

      // EfficientDet outputs: boxes, classes, scores, num_detections
      // This is a simplified implementation - actual shapes depend on model
      final outputBoxes = List.generate(1, (_) => List.generate(25, (_) => List.filled(4, 0.0)));
      final outputClasses = List.generate(1, (_) => List.filled(25, 0.0));
      final outputScores = List.generate(1, (_) => List.filled(25, 0.0));
      final outputCount = List.filled(1, 0.0);

      final outputs = {
        0: outputBoxes,
        1: outputClasses,
        2: outputScores,
        3: outputCount,
      };

      // Run inference
      _interpreter!.runForMultipleInputs([inputTensor], outputs);

      // Parse results
      final results = <DetectedObject>[];
      final numDetections = outputCount[0].toInt();

      for (var i = 0; i < numDetections && i < 25; i++) {
        final score = outputScores[0][i];
        if (score < confidenceThreshold) continue;

        final classId = outputClasses[0][i].toInt();
        final box = outputBoxes[0][i];

        // Box format: [ymin, xmin, ymax, xmax] normalized
        final boundingBox = BoundingBox.fromLTRB(
          box[1], // xmin (left)
          box[0], // ymin (top)
          box[3], // xmax (right)
          box[2], // ymax (bottom)
        );

        final label = _labels != null && classId < _labels!.length
            ? _labels![classId]
            : 'Object $classId';

        results.add(DetectedObject(
          label: label,
          confidence: score,
          boundingBox: boundingBox,
        ));
      }

      return results;
    } catch (e) {
      LogService().log('TFLiteService: Detection error: $e');
      rethrow;
    }
  }

  /// Close the interpreter and free resources
  void close() {
    _interpreter?.close();
    _interpreter = null;
    _loadedModelId = null;
    _labels = null;
  }

  void dispose() {
    close();
  }
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
