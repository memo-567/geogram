/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/music_model_info.dart';
import '../../connection/connection_manager.dart';
import '../../services/log_service.dart';
import '../../services/station_service.dart';

/// Manages music generation model downloads and storage.
/// Follows the same station-first pattern as VisionModelManager.
class MusicModelManager {
  static final MusicModelManager _instance = MusicModelManager._internal();
  factory MusicModelManager() => _instance;
  MusicModelManager._internal();

  /// Directory for storing music models
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
    _modelsPath = '${appDir.path}/bot/models/music';

    // Create directory if it doesn't exist
    final dir = Directory(_modelsPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    LogService().log('MusicModelManager: Initialized at $_modelsPath');
  }

  /// Get path to models directory
  Future<String> get modelsPath async {
    if (_modelsPath == null) {
      await initialize();
    }
    return _modelsPath!;
  }

  /// Get path to a specific model directory
  Future<String> getModelDir(String modelId) async {
    final basePath = await modelsPath;
    final model = MusicModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }

    // FM synth doesn't have a file
    if (model.isNative) {
      throw ArgumentError('Native model $modelId has no directory');
    }

    return path.join(basePath, modelId);
  }

  /// Get path to a specific model file (relative to model directory)
  Future<String> getModelFilePath(String modelId, String relativePath) async {
    final modelDir = await getModelDir(modelId);
    return path.join(modelDir, relativePath);
  }

  /// Check if a model is downloaded
  Future<bool> isDownloaded(String modelId) async {
    final model = MusicModels.getById(modelId);
    if (model == null) return false;

    // FM synth is always "downloaded" (native)
    if (model.isNative) return true;

    try {
      if (model.files.isEmpty) {
        // Legacy single-file model fallback
        final extension = model.format == 'onnx' ? '.onnx' : '.tflite';
        final legacyPath = path.join(await modelsPath, '$modelId$extension');
        final file = File(legacyPath);
        if (!await file.exists()) return false;

        if (model.size > 0) {
          final actualSize = await file.length();
          final tolerance = model.size * 0.05;
          return (actualSize - model.size).abs() < tolerance;
        }
        return true;
      }

      for (final fileInfo in model.files) {
        final filePath = await getModelFilePath(modelId, fileInfo.path);
        final file = File(filePath);
        if (!await file.exists()) return false;

        if (fileInfo.size > 0) {
          final actualSize = await file.length();
          final tolerance = fileInfo.size * 0.05;
          if ((actualSize - fileInfo.size).abs() >= tolerance) {
            return false;
          }
        }
      }

      return true;
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

  /// Download a model with progress tracking.
  /// Uses station-first download pattern:
  /// 1. Check local cache
  /// 2. Try station server via ConnectionManager
  /// 3. Fallback to internet (HuggingFace)
  /// Returns a stream of progress updates (0.0 - 1.0)
  Stream<double> downloadModel(String modelId) async* {
    final model = MusicModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }

    // Native models don't need downloading
    if (model.isNative) {
      yield 1.0;
      return;
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

    // Track download
    _activeDownloads[modelId] = _DownloadProgress();
    _downloadStateController.add(modelId);

    final files = model.files.isNotEmpty
        ? model.files
        : [
            MusicModelFile(
              path: '$modelId.${model.format == 'onnx' ? 'onnx' : 'tflite'}',
              size: model.size,
            )
          ];

    try {
      for (var i = 0; i < files.length; i++) {
        final fileInfo = files[i];
        final destPath = model.files.isNotEmpty
            ? await getModelFilePath(modelId, fileInfo.path)
            : path.join(await modelsPath, fileInfo.path);
        final destFile = File(destPath);
        final tempFile = File('$destPath.tmp');

        // Create parent directory if needed
        final parentDir = destFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        // Skip if already downloaded
        if (await destFile.exists()) {
          if (fileInfo.size > 0) {
            final actualSize = await destFile.length();
            final tolerance = fileInfo.size * 0.05;
            if ((actualSize - fileInfo.size).abs() < tolerance) {
              _activeDownloads[modelId]!.progress = (i + 1) / files.length;
              yield _activeDownloads[modelId]!.progress;
              continue;
            }
          } else {
            _activeDownloads[modelId]!.progress = (i + 1) / files.length;
            yield _activeDownloads[modelId]!.progress;
            continue;
          }
        }

        // Station-first download pattern per file
        if (await _isStationReachable()) {
          final stationUrl = _getStationModelUrl(modelId, fileInfo.path);
          if (stationUrl != null) {
            LogService().log(
                'MusicModelManager: Trying station download for $modelId (${fileInfo.path})');
            try {
              await for (final progress in _downloadFromUrl(
                stationUrl,
                modelId,
                fileInfo.path,
                destPath,
                tempFile,
                expectedSize: fileInfo.size,
              )) {
                final overall = (i + progress) / files.length;
                _activeDownloads[modelId]!.progress = overall;
                yield overall;
              }
              continue; // Success - next file
            } catch (e) {
              LogService().log(
                  'MusicModelManager: Station download failed: $e, trying internet...');
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            }
          }
        }

        // Fallback to internet (HuggingFace)
        final url = _buildInternetUrl(model, fileInfo.path);
        if (url == null) {
          throw Exception('Model $modelId has no download URL for ${fileInfo.path}');
        }

        LogService().log(
            'MusicModelManager: Starting internet download of $modelId (${fileInfo.path}) from $url');
        await for (final progress in _downloadFromUrl(
          url,
          modelId,
          fileInfo.path,
          destPath,
          tempFile,
          expectedSize: fileInfo.size,
        )) {
          final overall = (i + progress) / files.length;
          _activeDownloads[modelId]!.progress = overall;
          yield overall;
        }
      }

      yield 1.0;
    } catch (e) {
      LogService().log('MusicModelManager: Error downloading $modelId: $e');

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
    String fileLabel,
    String path,
    File tempFile, {
    int expectedSize = 0,
  }) async* {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'HTTP ${response.statusCode}: Failed to download model from $url');
    }

    final totalBytes = response.contentLength ?? expectedSize;
    var receivedBytes = 0;

    final sink = tempFile.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      final progress =
          totalBytes > 0 ? receivedBytes / totalBytes : 0.0;
      yield progress;
    }

    await sink.close();

    // Move temp file to final location
    await tempFile.rename(path);

    LogService().log(
        'MusicModelManager: Downloaded $modelId ($fileLabel) from $url');
    yield 1.0;
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    final model = MusicModels.getById(modelId);
    if (model == null || model.isNative) return;

    // Cancel if downloading
    if (_activeDownloads.containsKey(modelId)) {
      _activeDownloads.remove(modelId);
    }

    final dir = Directory(await getModelDir(modelId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      LogService().log('MusicModelManager: Deleted model $modelId');
    }

    _downloadStateController.add(modelId);
  }

  /// Get list of downloaded AI models (excludes FM synth)
  Future<List<MusicModelInfo>> getDownloadedModels() async {
    final downloaded = <MusicModelInfo>[];

    for (final model in MusicModels.aiModels) {
      if (await isDownloaded(model.id)) {
        downloaded.add(model);
      }
    }

    return downloaded;
  }

  /// Get the best available model for the device.
  Future<MusicModelInfo> getBestAvailableModel(int availableRamMb) async {
    final recommended = MusicModels.selectForRam(availableRamMb);
    if (!recommended.isNative && await isDownloaded(recommended.id)) {
      return recommended;
    }

    final downloaded = await getDownloadedModels();
    if (downloaded.isNotEmpty) {
      downloaded.sort((a, b) => b.size.compareTo(a.size));
      return downloaded.first;
    }

    return MusicModels.fmSynth;
  }

  /// Get recommended model for device RAM (may not be downloaded)
  MusicModelInfo getRecommendedModel(int availableRamMb) {
    return MusicModels.selectForRam(availableRamMb);
  }

  /// Get total storage used by music models in bytes
  Future<int> getTotalStorageUsed() async {
    var total = 0;

    for (final model in MusicModels.aiModels) {
      if (model.files.isEmpty) {
        try {
          final extension = model.format == 'onnx' ? '.onnx' : '.tflite';
          final legacyPath = path.join(await modelsPath, '${model.id}$extension');
          final file = File(legacyPath);
          if (await file.exists()) {
            total += await file.length();
          }
        } catch (_) {
          // Ignore errors
        }
      } else {
        for (final fileInfo in model.files) {
          try {
            final filePath = await getModelFilePath(model.id, fileInfo.path);
            final file = File(filePath);
            if (await file.exists()) {
              total += await file.length();
            }
          } catch (_) {
            // Ignore errors
          }
        }
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

  /// Clear all downloaded music models
  Future<void> clearAllModels() async {
    for (final model in MusicModels.aiModels) {
      await deleteModel(model.id);
    }
    LogService().log('MusicModelManager: Cleared all music models');
  }

  // ============================================================
  // Station-First Download (Offline-First Pattern)
  // ============================================================

  /// Get station URL for model downloads
  String? _getStationModelUrl(String modelId, String relativePath) {
    final station = StationService().getPreferredStation();
    if (station == null || station.url.isEmpty) return null;

    var stationUrl = station.url;
    // Convert WebSocket URL to HTTP
    if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    } else if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    }

    // Remove trailing slash if present
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }

    return '$stationUrl/bot/models/music/$modelId/$relativePath';
  }

  String? _buildInternetUrl(MusicModelInfo model, String relativePath) {
    if (model.repoId != null && model.repoId!.isNotEmpty) {
      return 'https://huggingface.co/${model.repoId}/resolve/main/$relativePath';
    }
    return model.url;
  }

  /// Check if station is reachable via any transport
  Future<bool> _isStationReachable() async {
    final station = StationService().getPreferredStation();
    if (station == null || station.callsign == null) return false;

    try {
      return await ConnectionManager()
          .isReachable(station.callsign!)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (e) {
      LogService()
          .log('MusicModelManager: Station reachability check failed: $e');
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
