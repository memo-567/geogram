/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/tts_model_info.dart';
import '../../services/log_service.dart';
import '../../services/websocket_service.dart';
import '../../services/storage_config.dart';

/// Manages Supertonic TTS model downloads and storage
///
/// Downloads models from the connected station server first,
/// then falls back to HuggingFace if no station is available.
///
/// Supertonic requires multiple ONNX files:
/// - text_encoder.onnx
/// - duration_predictor.onnx
/// - vector_estimator.onnx
/// - vocoder.onnx
/// Plus config files: tts.json, unicode_indexer.json
class TtsModelManager {
  static final TtsModelManager _instance = TtsModelManager._internal();
  factory TtsModelManager() => _instance;
  TtsModelManager._internal();

  /// Directory for storing TTS models
  String? _modelsPath;

  /// Currently downloading
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _currentFile = '';

  /// Notifier for download state changes
  final StreamController<String> _downloadStateController =
      StreamController<String>.broadcast();

  /// Stream of status messages when download state changes
  Stream<String> get downloadStateChanges => _downloadStateController.stream;

  /// Initialize the manager
  Future<void> initialize() async {
    final storageConfig = StorageConfig();
    if (!storageConfig.isInitialized) {
      await storageConfig.init();
    }

    _modelsPath = p.join(storageConfig.baseDir, 'bot', 'models', 'supertonic');

    // Create directory if it doesn't exist
    final dir = Directory(_modelsPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    LogService().log('TtsModelManager: Initialized at $_modelsPath');
  }

  /// Get path to models directory
  Future<String> get modelsPath async {
    if (_modelsPath == null) {
      await initialize();
    }
    return _modelsPath!;
  }

  /// Get path to a specific ONNX file
  Future<String> getFilePath(String filename) async {
    final basePath = await modelsPath;
    return p.join(basePath, filename);
  }

  /// Get path to text encoder ONNX
  Future<String> get textEncoderPath => getFilePath('text_encoder.onnx');

  /// Get path to duration predictor ONNX
  Future<String> get durationPredictorPath =>
      getFilePath('duration_predictor.onnx');

  /// Get path to vector estimator ONNX
  Future<String> get vectorEstimatorPath =>
      getFilePath('vector_estimator.onnx');

  /// Get path to vocoder ONNX
  Future<String> get vocoderPath => getFilePath('vocoder.onnx');

  /// Get path to TTS config
  Future<String> get ttsConfigPath => getFilePath('tts.json');

  /// Get path to unicode indexer config
  Future<String> get unicodeIndexerPath => getFilePath('unicode_indexer.json');

  /// Get path to a voice style file
  Future<String> voiceStylePath(TtsVoice voice) => getFilePath(voice.filename);

  /// Check if all required files are downloaded
  Future<bool> isDownloaded() async {
    try {
      for (final file in TtsModels.allFiles) {
        final path = await getFilePath(file.filename);
        final f = File(path);
        if (!await f.exists()) {
          LogService().log('TtsModelManager: Missing file: ${file.filename}');
          return false;
        }

        // Verify file size (allow 10% tolerance for compression differences)
        final actualSize = await f.length();
        final tolerance = file.size * 0.1;
        if ((actualSize - file.size).abs() > tolerance && actualSize < file.size * 0.5) {
          LogService().log(
              'TtsModelManager: File size mismatch for ${file.filename}: expected ~${file.size}, got $actualSize');
          return false;
        }
      }
      return true;
    } catch (e) {
      LogService().log('TtsModelManager: Error checking download status: $e');
      return false;
    }
  }

  /// Check if currently downloading
  bool get isDownloading => _isDownloading;

  /// Get current download progress (0.0 - 1.0)
  double get downloadProgress => _downloadProgress;

  /// Get current file being downloaded
  String get currentFile => _currentFile;

  /// Ensure all model files are downloaded, yields progress 0.0 to 1.0
  Stream<double> ensureModel() async* {
    if (await isDownloaded()) {
      yield 1.0;
      return;
    }

    yield* downloadAllFiles();
  }

  /// Download all required files with progress tracking
  Stream<double> downloadAllFiles() async* {
    if (_isDownloading) {
      // Already downloading, just yield current progress
      yield _downloadProgress;
      return;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;

    try {
      final allFiles = TtsModels.allFiles;
      final totalSize = TtsModels.totalSize;
      var downloadedSize = 0;

      // Get station URL if connected
      String? httpUrl;
      final wsUrl = WebSocketService().connectedUrl;
      if (wsUrl != null) {
        httpUrl = wsUrl
            .replaceFirst('wss://', 'https://')
            .replaceFirst('ws://', 'http://');
      }

      for (var i = 0; i < allFiles.length; i++) {
        final file = allFiles[i];
        _currentFile = file.name;
        _downloadStateController.add('Downloading ${file.name}...');

        final localPath = await getFilePath(file.filename);

        // Check if file already exists and is valid
        final existingFile = File(localPath);
        if (await existingFile.exists()) {
          final size = await existingFile.length();
          // Allow 10% tolerance
          if ((size - file.size).abs() < file.size * 0.1 || size > file.size * 0.5) {
            LogService().log(
                'TtsModelManager: ${file.filename} already exists, skipping');
            downloadedSize += file.size;
            _downloadProgress = downloadedSize / totalSize;
            yield _downloadProgress;
            continue;
          }
        }

        // Try station first, then HuggingFace
        bool downloaded = false;

        if (httpUrl != null) {
          try {
            // Construct station URL with proper subdir
            final stationSubdir = file.subdir ?? 'onnx';
            final stationUrl = '$httpUrl/bot/models/supertonic/$stationSubdir/${file.filename}';
            await for (final fileProgress in _downloadFile(
              file,
              localPath,
              stationUrl,
            )) {
              final overallProgress =
                  (downloadedSize + fileProgress * file.size) / totalSize;
              _downloadProgress = overallProgress;
              yield overallProgress;
            }
            downloaded = true;
          } catch (e) {
            LogService().log(
                'TtsModelManager: Station download failed for ${file.filename}: $e');
          }
        }

        if (!downloaded) {
          // Fall back to HuggingFace
          LogService().log(
              'TtsModelManager: Downloading ${file.filename} from HuggingFace');
          await for (final fileProgress in _downloadFile(
            file,
            localPath,
            file.url,
          )) {
            final overallProgress =
                (downloadedSize + fileProgress * file.size) / totalSize;
            _downloadProgress = overallProgress;
            yield overallProgress;
          }
        }

        downloadedSize += file.size;
      }

      _downloadProgress = 1.0;
      _currentFile = '';
      _downloadStateController.add('Download complete');
      yield 1.0;
    } catch (e) {
      LogService().log('TtsModelManager: Download error: $e');
      _downloadStateController.add('Download failed: $e');
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  /// Download a single file with progress tracking
  Stream<double> _downloadFile(
    TtsOnnxFile file,
    String localPath,
    String url,
  ) async* {
    final tempFile = File('$localPath.tmp');

    try {
      // Create parent directory if needed
      final parentDir = File(localPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Check for partial download (resume support)
      int downloadedBytes = 0;
      if (await tempFile.exists()) {
        downloadedBytes = await tempFile.length();
        LogService().log(
            'TtsModelManager: Resuming ${file.filename} from $downloadedBytes bytes');
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      try {
        LogService().log('TtsModelManager: Downloading from $url');

        final request = await client.getUrl(Uri.parse(url));

        // Add range header for resume support
        if (downloadedBytes > 0) {
          request.headers.set('Range', 'bytes=$downloadedBytes-');
        }

        final response = await request.close();

        LogService()
            .log('TtsModelManager: Response status ${response.statusCode}');

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception(
              'Failed to download ${file.filename}: HTTP ${response.statusCode}');
        }

        // Get total size
        final contentLength = response.contentLength;
        final totalBytes =
            contentLength > 0 ? contentLength + downloadedBytes : file.size;

        // Open file for writing (append mode if resuming)
        final sink = tempFile.openWrite(
            mode: downloadedBytes > 0 ? FileMode.append : FileMode.write);

        await for (final chunk in response) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          final progress = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
          yield progress.clamp(0.0, 1.0);
        }

        await sink.close();

        // Rename temp file to final file
        final finalFile = File(localPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await tempFile.rename(localPath);

        LogService()
            .log('TtsModelManager: Downloaded ${file.filename} successfully');
        yield 1.0;
      } finally {
        client.close();
      }
    } catch (e) {
      LogService()
          .log('TtsModelManager: Error downloading ${file.filename}: $e');
      rethrow;
    }
  }

  /// Delete all downloaded model files
  Future<void> deleteAllFiles() async {
    final basePath = await modelsPath;

    for (final file in TtsModels.allFiles) {
      try {
        final path = p.join(basePath, file.filename);
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }

        // Also delete temp file if exists
        final tempFile = File('$path.tmp');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        LogService()
            .log('TtsModelManager: Error deleting ${file.filename}: $e');
      }
    }

    LogService().log('TtsModelManager: Deleted all model files');
    _downloadStateController.add('deleted');
  }

  /// Get total storage used by TTS models in bytes
  Future<int> getTotalStorageUsed() async {
    var total = 0;
    final basePath = await modelsPath;

    for (final file in TtsModels.allFiles) {
      try {
        final path = p.join(basePath, file.filename);
        final f = File(path);
        if (await f.exists()) {
          total += await f.length();
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

  void dispose() {
    _downloadStateController.close();
  }
}
