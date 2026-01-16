/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/whisper_model_info.dart';
import '../../services/log_service.dart';
import '../../services/station_service.dart';
import '../../services/storage_config.dart';
import '../../services/whisper_library_service.dart';
import '../../transfer/models/transfer_models.dart';
import '../../transfer/services/transfer_service.dart';
import '../../util/event_bus.dart';

/// Manages Whisper speech recognition model downloads and storage
class WhisperModelManager {
  static final WhisperModelManager _instance = WhisperModelManager._internal();
  factory WhisperModelManager() => _instance;
  WhisperModelManager._internal();

  /// Directory for storing whisper models
  String? _modelsPath;

  /// Transfer service for downloading models
  final TransferService _transferService = TransferService();
  final EventBus _eventBus = EventBus();

  /// Maps model IDs to their active transfer IDs
  final Map<String, String> _modelTransferIds = {};

  /// Currently downloading models (for backward compatibility with UI)
  final Map<String, _DownloadProgress> _activeDownloads = {};

  /// Notifier for download state changes
  final StreamController<String> _downloadStateController =
      StreamController<String>.broadcast();

  /// Stream of model IDs when their download state changes
  Stream<String> get downloadStateChanges => _downloadStateController.stream;

  /// Preferred model preference key
  static const String _preferredModelKey = 'whisper_preferred_model';

  /// Library service for managing native library downloads
  final WhisperLibraryService _libraryService = WhisperLibraryService();

  /// Check if the whisper native library is available
  /// Returns true if bundled (normal builds) or downloaded (F-Droid)
  Future<bool> isLibraryAvailable() async {
    return _libraryService.isWhisperAvailable();
  }

  /// Check if the native library needs to be downloaded (F-Droid builds)
  Future<bool> needsLibraryDownload() async {
    if (await _libraryService.isLibraryBundled()) {
      return false;
    }
    return !(await _libraryService.isLibraryDownloaded());
  }

  /// Download the native library from a station server
  /// This is needed for F-Droid builds where binaries aren't bundled
  Future<void> downloadLibrary({
    required String stationUrl,
    void Function(double progress)? onProgress,
  }) async {
    await _libraryService.downloadLibrary(
      stationUrl: stationUrl,
      onProgress: onProgress,
    );
    _downloadStateController.add('library');
  }

  /// Initialize the manager
  Future<void> initialize() async {
    final storageConfig = StorageConfig();
    if (!storageConfig.isInitialized) {
      await storageConfig.init();
    }

    _modelsPath = p.join(storageConfig.baseDir, 'bot', 'models', 'whisper');

    // Create directory if it doesn't exist
    final dir = Directory(_modelsPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    LogService().log('WhisperModelManager: Initialized at $_modelsPath');

    // Ensure whisper library is ready (for F-Droid builds that downloaded it)
    await _libraryService.ensureLibraryReady();
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
    final model = WhisperModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }
    return '$basePath/${model.filename}';
  }

  /// Check if a model is downloaded
  Future<bool> isDownloaded(String modelId) async {
    try {
      final path = await getModelPath(modelId);
      final file = File(path);
      if (!await file.exists()) return false;

      // Verify file size matches expected
      final model = WhisperModels.getById(modelId);
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
  ///
  /// First attempts to download from a configured station server,
  /// then falls back to HuggingFace if no station is available.
  ///
  /// Returns a stream of progress updates (0.0 - 1.0)
  Stream<double> downloadModel(
    String modelId, {
    String? stationUrl,
    String? stationCallsign,
  }) async* {
    final model = WhisperModels.getById(modelId);
    if (model == null) {
      throw ArgumentError('Unknown model: $modelId');
    }

    // Check if already downloaded
    if (await isDownloaded(modelId)) {
      yield 1.0;
      return;
    }

    final localPath = await getModelPath(modelId);

    // Always download directly from HuggingFace for whisper models
    // (stations typically don't host these large model files)
    LogService().log(
        'WhisperModelManager: Downloading $modelId directly from HuggingFace');
    yield* _downloadDirectly(modelId, model, localPath);
  }

  /// Download via TransferService (station)
  Stream<double> _downloadViaTransferService({
    required String modelId,
    required WhisperModelInfo model,
    required String localPath,
    required String remotePath,
    required String stationUrl,
    required String callsign,
  }) async* {
    // Ensure TransferService is initialized
    if (!_transferService.isInitialized) {
      await _transferService.initialize();
    }

    // Check if transfer already exists
    var transfer = _transferService.findTransfer(
      callsign: callsign,
      remotePath: remotePath,
    );

    if (transfer == null) {
      LogService().log(
          'WhisperModelManager: Requesting transfer for $modelId from station $callsign');

      // Create parent directory if needed
      final parentDir = Directory(localPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      transfer = await _transferService.requestDownload(
        TransferRequest(
          direction: TransferDirection.download,
          callsign: callsign,
          stationUrl: stationUrl,
          remotePath: remotePath,
          localPath: localPath,
          expectedBytes: model.size,
          timeout: const Duration(hours: 2),
          priority: TransferPriority.high,
          requestingApp: 'bot',
          metadata: {
            'model_id': modelId,
            'model_type': 'whisper',
            'model_name': model.name,
            'model_tier': model.tier,
            'size_tolerance_ratio': 0.05,
          },
        ),
      );
    }

    // Track the transfer
    _modelTransferIds[modelId] = transfer.id;
    _activeDownloads[modelId] = _DownloadProgress();
    _downloadStateController.add(modelId);

    // Create a completer to track completion
    final completer = Completer<void>();

    // Subscribe to progress events
    final progressSub = _eventBus.on<TransferProgressEvent>((event) {
      if (event.transferId == transfer!.id) {
        final progress = event.totalBytes > 0
            ? event.bytesTransferred / event.totalBytes
            : 0.0;
        _activeDownloads[modelId]?.progress = progress;
      }
    });

    // Subscribe to completion events
    final completeSub = _eventBus.on<TransferCompletedEvent>((event) {
      if (event.transferId == transfer!.id) {
        _activeDownloads[modelId]?.progress = 1.0;
        if (!completer.isCompleted) completer.complete();
      }
    });

    // Subscribe to failure events
    final failedSub = _eventBus.on<TransferFailedEvent>((event) {
      if (event.transferId == transfer!.id && !event.willRetry) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(event.error));
        }
      }
    });

    try {
      // Yield progress updates until transfer completes
      while (!completer.isCompleted) {
        final progress = _activeDownloads[modelId]?.progress ?? 0.0;
        yield progress;

        if (progress >= 1.0) break;

        // Check transfer status periodically
        final currentTransfer = _transferService.getTransfer(transfer.id);
        if (currentTransfer != null) {
          if (currentTransfer.isCompleted) {
            yield 1.0;
            break;
          }
          if (currentTransfer.isFailed) {
            throw Exception(currentTransfer.error ?? 'Transfer failed');
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Wait for completion
      await completer.future;
      LogService()
          .log('WhisperModelManager: Downloaded $modelId via TransferService');
      yield 1.0;
    } finally {
      // Cleanup subscriptions
      progressSub.cancel();
      completeSub.cancel();
      failedSub.cancel();

      _activeDownloads.remove(modelId);
      _modelTransferIds.remove(modelId);
      _downloadStateController.add(modelId);
    }
  }

  /// Download directly from HuggingFace with resume support
  Stream<double> _downloadDirectly(
    String modelId,
    WhisperModelInfo model,
    String localPath,
  ) async* {
    _activeDownloads[modelId] = _DownloadProgress();
    _downloadStateController.add(modelId);

    final file = File(localPath);
    final tempFile = File('$localPath.tmp');

    try {
      // Create parent directory if needed
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Check for partial download (resume support)
      int downloadedBytes = 0;
      if (await tempFile.exists()) {
        downloadedBytes = await tempFile.length();
        LogService().log(
            'WhisperModelManager: Resuming download from $downloadedBytes bytes');
      }

      // Use HttpClient which follows redirects automatically
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      try {
        LogService().log('WhisperModelManager: Downloading from ${model.url}');

        final request = await client.getUrl(Uri.parse(model.url));

        // Add range header for resume support
        if (downloadedBytes > 0) {
          request.headers.set('Range', 'bytes=$downloadedBytes-');
        }

        final response = await request.close();

        LogService().log('WhisperModelManager: Response status ${response.statusCode}');

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception(
              'Failed to download model: HTTP ${response.statusCode}');
        }

        // Get total size
        final contentLength = response.contentLength;
        final totalBytes = contentLength > 0
            ? contentLength + downloadedBytes
            : model.size;

        LogService().log('WhisperModelManager: Expected total bytes: $totalBytes');

        // Open file for writing (append mode if resuming)
        final sink = tempFile.openWrite(
            mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

        await for (final chunk in response) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          final progress =
              totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          _activeDownloads[modelId]?.progress = progress;
          yield progress;
        }

        await sink.close();

        // Rename temp file to final file
        await tempFile.rename(localPath);

        LogService()
            .log('WhisperModelManager: Downloaded $modelId from HuggingFace');
        yield 1.0;
      } finally {
        client.close();
      }
    } catch (e) {
      LogService().log('WhisperModelManager: Error downloading $modelId: $e');
      rethrow;
    } finally {
      _activeDownloads.remove(modelId);
      _downloadStateController.add(modelId);
    }
  }

  /// Get the transfer ID for a model download (if in progress)
  String? getTransferId(String modelId) => _modelTransferIds[modelId];

  /// Get the current transfer for a model (if in progress)
  Transfer? getTransfer(String modelId) {
    final transferId = _modelTransferIds[modelId];
    if (transferId == null) return null;
    return _transferService.getTransfer(transferId);
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
      LogService().log('WhisperModelManager: Deleted model $modelId');
    }

    // Also delete temp file if exists
    final tempFile = File('$path.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    _downloadStateController.add(modelId);
  }

  /// Get list of downloaded models
  Future<List<WhisperModelInfo>> getDownloadedModels() async {
    final downloaded = <WhisperModelInfo>[];

    for (final model in WhisperModels.available) {
      if (await isDownloaded(model.id)) {
        downloaded.add(model);
      }
    }

    return downloaded;
  }

  /// Get total storage used by whisper models in bytes
  Future<int> getTotalStorageUsed() async {
    var total = 0;

    for (final model in WhisperModels.available) {
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

  /// Clear all downloaded whisper models
  Future<void> clearAllModels() async {
    for (final model in WhisperModels.available) {
      await deleteModel(model.id);
    }
    LogService().log('WhisperModelManager: Cleared all whisper models');
  }

  /// Get recommended models based on device RAM
  List<WhisperModelInfo> getRecommendedModels(int availableRamMb) {
    return WhisperModels.available
        .where((m) => m.minRamMb <= availableRamMb)
        .toList();
  }

  /// Set preferred model
  Future<void> setPreferredModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredModelKey, modelId);
    LogService().log('WhisperModelManager: Set preferred model to $modelId');
  }

  /// Get preferred model (or default)
  Future<String> getPreferredModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_preferredModelKey) ?? WhisperModels.defaultModelId;
  }

  /// Ensure a model is available (download if needed)
  /// Returns true if model is ready, false if download failed
  Stream<double> ensureModelAvailable(String? modelId) async* {
    final id = modelId ?? await getPreferredModel();

    if (await isDownloaded(id)) {
      yield 1.0;
      return;
    }

    yield* downloadModel(id);
  }

  void dispose() {
    _downloadStateController.close();
  }
}

/// Tracks download progress for a model
class _DownloadProgress {
  double progress = 0.0;
}
