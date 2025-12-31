/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vision_result.dart';
import '../models/vision_model_info.dart';
import 'vision_model_manager.dart';
import 'tflite_service.dart';
import '../../services/log_service.dart';

/// Main service for vision/image processing
class VisionService {
  static final VisionService _instance = VisionService._internal();
  factory VisionService() => _instance;
  VisionService._internal();

  final VisionModelManager _modelManager = VisionModelManager();
  final TFLiteService _tfliteService = TFLiteService();

  /// Cache directory for analysis results
  String? _cachePath;

  bool _initialized = false;

  /// Initialize the service
  Future<void> initialize() async {
    if (_initialized) return;

    await _modelManager.initialize();

    final appDir = await getApplicationDocumentsDirectory();
    _cachePath = '${appDir.path}/bot/cache/vision';

    final cacheDir = Directory(_cachePath!);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    _initialized = true;
    LogService().log('VisionService: Initialized');
  }

  /// Get the model manager
  VisionModelManager get modelManager => _modelManager;

  /// Check if any vision model is available
  Future<bool> hasVisionModel() async {
    final downloaded = await _modelManager.getDownloadedModels();
    return downloaded.isNotEmpty;
  }

  /// Get the best available model for a capability
  Future<VisionModelInfo?> getBestModelFor(String capability) async {
    final downloaded = await _modelManager.getDownloadedModels();

    // Filter by capability
    final capable = downloaded.where((m) => m.hasCapability(capability)).toList();
    if (capable.isEmpty) return null;

    // Sort by tier (premium > quality > standard > lite)
    final tierOrder = {'premium': 0, 'quality': 1, 'standard': 2, 'lite': 3};
    capable.sort((a, b) =>
        (tierOrder[a.tier] ?? 4).compareTo(tierOrder[b.tier] ?? 4));

    return capable.first;
  }

  /// Analyze an image with the best available model
  Future<VisionResult> analyzeImage(
    String imagePath, {
    String? question,
    List<String>? requestedCapabilities,
  }) async {
    await initialize();

    final stopwatch = Stopwatch()..start();

    // Check cache first
    final cacheKey = _getCacheKey(imagePath, question);
    final cached = await _loadFromCache(cacheKey);
    if (cached != null) {
      LogService().log('VisionService: Returning cached result for $imagePath');
      return cached;
    }

    // Get downloaded models
    final downloaded = await _modelManager.getDownloadedModels();
    if (downloaded.isEmpty) {
      return VisionResult(
        modelUsed: 'none',
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    // Determine which capabilities we need
    final capabilities = requestedCapabilities ?? _inferCapabilities(question);

    VisionResult result;

    // Try to use the best model for the job
    if (capabilities.contains('visual_qa') || question != null) {
      // Need a multimodal model (GGUF)
      final model = await getBestModelFor('visual_qa');
      if (model != null && model.format == 'gguf') {
        result = await _processWithGGUF(imagePath, question, model);
      } else {
        // Fallback to TFLite classification
        result = await _processWithTFLite(imagePath, capabilities);
      }
    } else {
      // Use TFLite for classification/detection
      result = await _processWithTFLite(imagePath, capabilities);
    }

    // Add processing time
    result = VisionResult(
      description: result.description,
      objects: result.objects,
      extractedText: result.extractedText,
      transliteration: result.transliteration,
      translation: result.translation,
      labels: result.labels,
      species: result.species,
      confidence: result.confidence,
      modelUsed: result.modelUsed,
      processingTimeMs: stopwatch.elapsedMilliseconds,
    );

    // Cache result
    await _saveToCache(cacheKey, result);

    LogService().log(
        'VisionService: Analyzed image in ${stopwatch.elapsedMilliseconds}ms using ${result.modelUsed}');

    return result;
  }

  /// Process image with TFLite models
  Future<VisionResult> _processWithTFLite(
    String imagePath,
    List<String> capabilities,
  ) async {
    String? description;
    List<DetectedObject> objects = [];
    List<String> labels = [];
    SpeciesIdentification? species;
    double confidence = 0.0;
    String modelUsed = 'tflite';

    // Try object detection first if requested
    if (capabilities.contains('object_detection')) {
      final model = await getBestModelFor('object_detection');
      if (model != null) {
        try {
          final modelPath = await _modelManager.getModelPath(model.id);
          await _tfliteService.loadModel(modelPath);
          objects = await _tfliteService.detectObjects(imagePath);
          modelUsed = model.id;
          if (objects.isNotEmpty) {
            confidence = objects.map((o) => o.confidence).reduce((a, b) => a > b ? a : b);
          }
        } catch (e) {
          LogService().log('VisionService: Detection error: $e');
        }
      }
    }

    // Try classification
    if (capabilities.contains('classification') || capabilities.isEmpty) {
      final model = await getBestModelFor('classification');
      if (model != null) {
        try {
          final modelPath = await _modelManager.getModelPath(model.id);
          await _tfliteService.loadModel(modelPath);
          final results = await _tfliteService.classify(imagePath);
          labels = results.map((r) => r.label).toList();
          if (results.isNotEmpty && results.first.confidence > confidence) {
            confidence = results.first.confidence;
            modelUsed = model.id;
          }
        } catch (e) {
          LogService().log('VisionService: Classification error: $e');
        }
      }
    }

    // Try plant identification
    if (capabilities.contains('plant_id')) {
      final model = await getBestModelFor('plant_id');
      if (model != null) {
        try {
          final modelPath = await _modelManager.getModelPath(model.id);
          await _tfliteService.loadModel(modelPath);
          final results = await _tfliteService.classify(imagePath);
          if (results.isNotEmpty) {
            // Parse plant classification result
            final topResult = results.first;
            species = SpeciesIdentification(
              scientificName: topResult.label,
              confidence: topResult.confidence,
              // TODO: Add toxicity warnings from a database
              isToxic: _checkIfToxic(topResult.label),
              warning: _checkIfToxic(topResult.label)
                  ? 'This species may be toxic. Do not consume without expert verification.'
                  : null,
            );
            modelUsed = model.id;
            confidence = topResult.confidence;
          }
        } catch (e) {
          LogService().log('VisionService: Plant ID error: $e');
        }
      }
    }

    // Generate description from detected objects/labels
    if (objects.isNotEmpty || labels.isNotEmpty) {
      description = _generateDescription(objects, labels, species);
    }

    return VisionResult(
      description: description,
      objects: objects,
      labels: labels,
      species: species,
      confidence: confidence,
      modelUsed: modelUsed,
    );
  }

  /// Process image with GGUF multimodal model (LLaVA, Qwen-VL, etc.)
  Future<VisionResult> _processWithGGUF(
    String imagePath,
    String? question,
    VisionModelInfo model,
  ) async {
    // TODO: Implement GGUF/LLaVA processing when flutter_llama is integrated
    // For now, fall back to TFLite
    LogService().log('VisionService: GGUF processing not yet implemented, falling back to TFLite');
    return _processWithTFLite(imagePath, ['classification', 'object_detection']);
  }

  /// Infer required capabilities from the question
  List<String> _inferCapabilities(String? question) {
    if (question == null || question.isEmpty) {
      return ['classification'];
    }

    final lower = question.toLowerCase();
    final capabilities = <String>[];

    // Check for plant/nature queries
    if (lower.contains('plant') ||
        lower.contains('flower') ||
        lower.contains('mushroom') ||
        lower.contains('tree') ||
        lower.contains('species') ||
        lower.contains('identify')) {
      capabilities.add('plant_id');
    }

    // Check for text/translation queries
    if (lower.contains('text') ||
        lower.contains('read') ||
        lower.contains('say') ||
        lower.contains('translate') ||
        lower.contains('written') ||
        lower.contains('sign')) {
      capabilities.add('ocr');
      capabilities.add('translation');
    }

    // Check for object detection queries
    if (lower.contains('detect') ||
        lower.contains('find') ||
        lower.contains('where') ||
        lower.contains('how many') ||
        lower.contains('count')) {
      capabilities.add('object_detection');
    }

    // Default: use visual Q&A for complex questions
    if (capabilities.isEmpty || lower.contains('?')) {
      capabilities.add('visual_qa');
      capabilities.add('classification');
    }

    return capabilities;
  }

  /// Generate a text description from detection results
  String _generateDescription(
    List<DetectedObject> objects,
    List<String> labels,
    SpeciesIdentification? species,
  ) {
    final parts = <String>[];

    if (species != null) {
      parts.add('Identified: ${species.scientificName}');
      if (species.commonName != null) {
        parts.add('(${species.commonName})');
      }
      if (species.isToxic) {
        parts.add('\n⚠️ Warning: This may be toxic.');
      }
    }

    if (objects.isNotEmpty) {
      final objectCounts = <String, int>{};
      for (final obj in objects) {
        objectCounts[obj.label] = (objectCounts[obj.label] ?? 0) + 1;
      }
      final objectStr = objectCounts.entries
          .map((e) => e.value > 1 ? '${e.value} ${e.key}s' : e.key)
          .join(', ');
      parts.add('Detected: $objectStr');
    }

    if (labels.isNotEmpty && species == null) {
      parts.add('Classification: ${labels.take(3).join(', ')}');
    }

    return parts.join('\n');
  }

  /// Check if a species name is known to be toxic
  bool _checkIfToxic(String speciesName) {
    // Simple list of known toxic species - should be expanded
    final toxicSpecies = [
      'amanita',
      'death cap',
      'destroying angel',
      'fly agaric',
      'poison',
      'deadly',
      'toxic',
      'hemlock',
      'nightshade',
      'oleander',
      'ricin',
      'foxglove',
    ];

    final lower = speciesName.toLowerCase();
    return toxicSpecies.any((t) => lower.contains(t));
  }

  /// Get cache key for an image + question
  String _getCacheKey(String imagePath, String? question) {
    final file = File(imagePath);
    final stat = file.statSync();
    final input = '$imagePath|${stat.modified.millisecondsSinceEpoch}|${question ?? ""}';
    return md5.convert(utf8.encode(input)).toString();
  }

  /// Load result from cache
  Future<VisionResult?> _loadFromCache(String cacheKey) async {
    if (_cachePath == null) return null;

    try {
      final file = File('$_cachePath/$cacheKey.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return VisionResult.fromJson(jsonDecode(content));
      }
    } catch (e) {
      // Ignore cache errors
    }
    return null;
  }

  /// Save result to cache
  Future<void> _saveToCache(String cacheKey, VisionResult result) async {
    if (_cachePath == null) return;

    try {
      final file = File('$_cachePath/$cacheKey.json');
      await file.writeAsString(jsonEncode(result.toJson()));
    } catch (e) {
      // Ignore cache errors
    }
  }

  /// Clear the vision cache
  Future<void> clearCache() async {
    if (_cachePath == null) return;

    try {
      final dir = Directory(_cachePath!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      LogService().log('VisionService: Cleared cache');
    } catch (e) {
      LogService().log('VisionService: Error clearing cache: $e');
    }
  }

  void dispose() {
    _tfliteService.dispose();
    _modelManager.dispose();
  }
}
