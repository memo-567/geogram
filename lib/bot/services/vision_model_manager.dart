/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/vision_model_info.dart';
import '../../connection/connection_manager.dart';
import '../../services/log_service.dart';
import '../../services/station_service.dart';

/// Manages vision model downloads and storage
class VisionModelManager {
  static final VisionModelManager _instance = VisionModelManager._internal();
  factory VisionModelManager() => _instance;
  VisionModelManager._internal();

  /// Directory for storing vision models
  String? _modelsPath;

  /// Currently downloading models
  final Map<String, _DownloadProgress> _activeDownloads = {};

  /// Notifier for download state changes
  final StreamController<String> _downloadStateController =
      StreamController<String>.broadcast();

  /// Stream of model IDs when their download state changes
  Stream<String> get downloadStateChanges => _downloadStateController.stream;

  /// Initialize the manager
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _modelsPath = '${appDir.path}/bot/models/vision';

    // Create directory if it doesn't exist
    final dir = Directory(_modelsPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    LogService().log('VisionModelManager: Initialized at $_modelsPath');
  }

  /// Get path to models directory
  Future<String> get modelsPath async {
    if (_modelsPath == null) {
      await initialize();
    }
    return _modelsPath!;
  }

  /// Get path to a specific model file
  Future<String> getModelPath(String modelId) async {
    final basePath = await modelsPath;
    final model = VisionModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }
    final extension = model.format == 'tflite' ? '.tflite' : '.gguf';
    return '$basePath/$modelId$extension';
  }

  /// Check if a model is downloaded
  Future<bool> isDownloaded(String modelId) async {
    try {
      final path = await getModelPath(modelId);
      final file = File(path);
      if (!await file.exists()) return false;

      // Verify file size matches expected
      final model = VisionModels.getById(modelId);
      if (model == null) return false;

      final actualSize = await file.length();
      // Allow 5% tolerance for size difference
      final tolerance = model.size * 0.05;
      return (actualSize - model.size).abs() < tolerance;
    } catch (e) {
      return false;
    }
  }

  /// Check if a model is currently downloading
  bool isDownloading(String modelId) => _activeDownloads.containsKey(modelId);

  /// Get download progress (0.0 - 1.0) for a model
  double getDownloadProgress(String modelId) {
    return _activeDownloads[modelId]?.progress ?? 0.0;
  }

  /// Download a model with progress tracking
  /// Uses station-first download pattern (like map tiles):
  /// 1. Check local cache
  /// 2. Try station server via ConnectionManager
  /// 3. Fallback to internet (HuggingFace/TFHub)
  /// Returns a stream of progress updates (0.0 - 1.0)
  Stream<double> downloadModel(String modelId) async* {
    final model = VisionModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }

    // Check if already downloading
    if (_activeDownloads.containsKey(modelId)) {
      // Return existing download progress
      while (_activeDownloads.containsKey(modelId)) {
        yield _activeDownloads[modelId]!.progress;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    // Check if already downloaded
    if (await isDownloaded(modelId)) {
      yield 1.0;
      return;
    }

    final path = await getModelPath(modelId);
    final file = File(path);
    final tempFile = File('$path.tmp');

    // Create parent directory if needed
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // Track download
    _activeDownloads[modelId] = _DownloadProgress();
    _downloadStateController.add(modelId);

    final extension = model.format == 'tflite' ? 'tflite' : 'gguf';

    try {
      // Station-first download pattern
      // Try station server first if reachable (via any transport)
      if (await _isStationReachable()) {
        final stationUrl = _getStationModelUrl(modelId, extension);
        if (stationUrl != null) {
          LogService().log('VisionModelManager: Trying station download for $modelId');
          try {
            yield* _downloadFromUrl(stationUrl, modelId, model, path, tempFile);
            return; // Success - exit early
          } catch (e) {
            LogService().log('VisionModelManager: Station download failed: $e, trying internet...');
            // Clean up temp file before trying internet fallback
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        }
      }

      // Fallback to internet (HuggingFace/TFHub)
      LogService().log('VisionModelManager: Starting internet download of $modelId from ${model.url}');
      yield* _downloadFromUrl(model.url, modelId, model, path, tempFile);
    } catch (e) {
      LogService().log('VisionModelManager: Error downloading $modelId: $e');

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      rethrow;
    } finally {
      _activeDownloads.remove(modelId);
      _downloadStateController.add(modelId);
    }
  }

  /// Download from a specific URL with progress tracking
  Stream<double> _downloadFromUrl(
    String url,
    String modelId,
    VisionModelInfo model,
    String path,
    File tempFile,
  ) async* {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to download model from $url');
    }

    final totalBytes = response.contentLength ?? model.size;
    var receivedBytes = 0;

    final sink = tempFile.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      final progress = receivedBytes / totalBytes;
      _activeDownloads[modelId]!.progress = progress;
      yield progress;
    }

    await sink.close();

    // Move temp file to final location
    await tempFile.rename(path);

    LogService().log('VisionModelManager: Downloaded $modelId (${model.sizeString}) from $url');
    yield 1.0;
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    // Cancel if downloading
    if (_activeDownloads.containsKey(modelId)) {
      _activeDownloads.remove(modelId);
    }

    final path = await getModelPath(modelId);
    final file = File(path);

    if (await file.exists()) {
      await file.delete();
      LogService().log('VisionModelManager: Deleted model $modelId');
    }

    // Also delete temp file if exists
    final tempFile = File('$path.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    _downloadStateController.add(modelId);
  }

  /// Get list of downloaded models
  Future<List<VisionModelInfo>> getDownloadedModels() async {
    final downloaded = <VisionModelInfo>[];

    for (final model in VisionModels.available) {
      if (await isDownloaded(model.id)) {
        downloaded.add(model);
      }
    }

    return downloaded;
  }

  /// Get total storage used by vision models in bytes
  Future<int> getTotalStorageUsed() async {
    var total = 0;

    for (final model in VisionModels.available) {
      try {
        final path = await getModelPath(model.id);
        final file = File(path);
        if (await file.exists()) {
          total += await file.length();
        }
      } catch (_) {
        // Ignore errors
      }
    }

    return total;
  }

  /// Get human-readable storage used string
  Future<String> getStorageUsedString() async {
    final bytes = await getTotalStorageUsed();

    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Clear all downloaded vision models
  Future<void> clearAllModels() async {
    for (final model in VisionModels.available) {
      await deleteModel(model.id);
    }
    LogService().log('VisionModelManager: Cleared all vision models');
  }

  /// Get recommended models based on device RAM
  List<VisionModelInfo> getRecommendedModels(int availableRamMb) {
    return VisionModels.available
        .where((m) => m.minRamMb <= availableRamMb)
        .toList();
  }

  // ============================================================
  // Station-First Download (Offline-First Pattern)
  // ============================================================

  /// Get station URL for model downloads (same pattern as MapTileService)
  String? _getStationModelUrl(String modelId, String extension) {
    final station = StationService().getPreferredStation();
    if (station == null || station.url.isEmpty) return null;

    var stationUrl = station.url;
    // Convert WebSocket URL to HTTP (same pattern as MapTileService)
    if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    } else if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    }

    // Remove trailing slash if present
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }

    return '$stationUrl/bot/models/$modelId.$extension';
  }

  /// Check if station is reachable via any transport
  /// Uses ConnectionManager for transport-agnostic reachability check
  Future<bool> _isStationReachable() async {
    final station = StationService().getPreferredStation();
    if (station == null || station.callsign == null) return false;

    try {
      // Use ConnectionManager to check reachability across all transports
      // (LAN, WebRTC, Station WS, BLE+, BLE)
      return await ConnectionManager()
          .isReachable(station.callsign!)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (e) {
      LogService().log('VisionModelManager: Station reachability check failed: $e');
      return false;
    }
  }

  void dispose() {
    _downloadStateController.close();
  }
}

/// Tracks download progress for a model
class _DownloadProgress {
  double progress = 0.0;
}
