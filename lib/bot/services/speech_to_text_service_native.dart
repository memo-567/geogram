/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../models/whisper_model_info.dart';
import 'whisper_model_manager.dart';
import '../../services/log_service.dart';

/// Result of a transcription operation
class TranscriptionResult {
  /// The transcribed text
  final String text;

  /// Time taken to transcribe in milliseconds
  final int transcriptionTimeMs;

  /// Model used for transcription
  final String modelUsed;

  /// Whether transcription was successful
  final bool success;

  /// Error message if transcription failed
  final String? error;

  const TranscriptionResult({
    required this.text,
    required this.transcriptionTimeMs,
    required this.modelUsed,
    required this.success,
    this.error,
  });

  /// Create a successful result
  factory TranscriptionResult.success({
    required String text,
    required int transcriptionTimeMs,
    required String modelUsed,
  }) {
    return TranscriptionResult(
      text: text,
      transcriptionTimeMs: transcriptionTimeMs,
      modelUsed: modelUsed,
      success: true,
    );
  }

  /// Create a failed result
  factory TranscriptionResult.failure({
    required String error,
    String modelUsed = '',
  }) {
    return TranscriptionResult(
      text: '',
      transcriptionTimeMs: 0,
      modelUsed: modelUsed,
      success: false,
      error: error,
    );
  }
}

/// State of the speech-to-text service
enum SpeechToTextState {
  /// Service is idle, ready to transcribe
  idle,

  /// Model is being loaded
  loadingModel,

  /// Audio is being transcribed
  transcribing,

  /// An error occurred
  error,
}

/// Service for converting speech to text using Whisper
class SpeechToTextService {
  static final SpeechToTextService _instance = SpeechToTextService._internal();
  factory SpeechToTextService() => _instance;
  SpeechToTextService._internal();

  final WhisperModelManager _modelManager = WhisperModelManager();

  Whisper? _whisper;
  String? _loadedModelId;
  SpeechToTextState _state = SpeechToTextState.idle;
  Completer<bool>? _preloadCompleter;

  final StreamController<SpeechToTextState> _stateController =
      StreamController<SpeechToTextState>.broadcast();

  /// Stream of state changes
  Stream<SpeechToTextState> get stateStream => _stateController.stream;

  /// Current state
  SpeechToTextState get state => _state;

  /// Whether a model is currently loaded
  bool get isModelLoaded => _whisper != null && _loadedModelId != null;

  /// ID of the currently loaded model
  String? get loadedModelId => _loadedModelId;

  /// Check if speech-to-text is supported on this platform
  static bool get isSupported {
    if (kIsWeb) return false;
    // whisper_flutter_new supports: Android 5.0+, iOS 13+, macOS 11+
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Check if preload is in progress
  bool get isPreloading =>
      _preloadCompleter != null && !_preloadCompleter!.isCompleted;

  /// Wait for any in-progress preload to complete
  Future<bool> waitForPreload() async {
    if (_preloadCompleter != null) {
      return _preloadCompleter!.future;
    }
    return isModelLoaded;
  }

  /// Preload model in background (called from main.dart)
  /// Sets up completer so dialog can wait for completion
  Future<void> preloadModel(String modelId) async {
    if (_preloadCompleter != null) return; // Already preloading

    _preloadCompleter = Completer<bool>();
    final stopwatch = Stopwatch()..start();

    try {
      final success = await loadModel(modelId);
      stopwatch.stop();
      LogService().log(
          'SpeechToTextService: Preload completed in ${stopwatch.elapsedMilliseconds}ms');
      _preloadCompleter!.complete(success);
    } catch (e) {
      LogService().log('SpeechToTextService: Preload failed: $e');
      _preloadCompleter!.completeError(e);
    }
  }

  void _setState(SpeechToTextState state) {
    _state = state;
    _stateController.add(state);
  }

  /// Initialize the service
  Future<void> initialize() async {
    await _modelManager.initialize();
    LogService().log('SpeechToTextService: Initialized');
  }

  /// Convert our model ID to whisper_flutter_new's WhisperModel enum
  WhisperModel _getWhisperModel(String modelId) {
    switch (modelId) {
      case 'whisper-tiny':
        return WhisperModel.tiny;
      case 'whisper-base':
        return WhisperModel.base;
      case 'whisper-small':
        return WhisperModel.small;
      case 'whisper-medium':
        return WhisperModel.medium;
      case 'whisper-large-v2':
        return WhisperModel.largeV2;
      default:
        return WhisperModel.small; // Default to small
    }
  }

  /// Load a Whisper model
  ///
  /// Returns true if model was loaded successfully
  Future<bool> loadModel(String modelId) async {
    if (_loadedModelId == modelId && _whisper != null) {
      LogService().log('SpeechToTextService: Model $modelId already loaded, skipping reload');
      return true; // Already loaded - instant
    }

    // Unload current model first
    await unloadModel();

    final model = WhisperModels.getById(modelId);
    if (model == null) {
      LogService().log('SpeechToTextService: Unknown model $modelId');
      return false;
    }

    _setState(SpeechToTextState.loadingModel);

    try {
      final modelDir = await _modelManager.modelsPath;
      final whisperModel = _getWhisperModel(modelId);

      LogService().log('SpeechToTextService: Loading model $modelId from $modelDir');

      // Create Whisper instance with our custom model directory
      _whisper = Whisper(
        model: whisperModel,
        modelDir: modelDir,
      );

      _loadedModelId = modelId;
      _setState(SpeechToTextState.idle);

      LogService().log('SpeechToTextService: Model $modelId loaded');
      return true;
    } catch (e) {
      LogService().log('SpeechToTextService: Error loading model: $e');
      _setState(SpeechToTextState.error);
      return false;
    }
  }

  /// Unload the current model to free memory
  Future<void> unloadModel() async {
    _whisper = null;
    _loadedModelId = null;
    _setState(SpeechToTextState.idle);
  }

  /// Transcribe an audio file to text
  ///
  /// The audio file should be in a supported format (wav, mp3, etc.)
  /// Returns a [TranscriptionResult] with the transcribed text or error
  Future<TranscriptionResult> transcribe(String audioFilePath) async {
    if (!isSupported) {
      return TranscriptionResult.failure(
        error: 'Speech-to-text not supported on this platform',
      );
    }

    if (!isModelLoaded) {
      return TranscriptionResult.failure(
        error: 'No model loaded',
      );
    }

    // Verify audio file exists
    final audioFile = File(audioFilePath);
    if (!await audioFile.exists()) {
      return TranscriptionResult.failure(
        error: 'Audio file not found',
        modelUsed: _loadedModelId ?? '',
      );
    }

    _setState(SpeechToTextState.transcribing);

    try {
      final stopwatch = Stopwatch()..start();

      // Transcribe the audio
      // whisper_flutter_new handles isolate/background processing internally
      // Use available CPU cores for faster processing (default is 6)
      final cpuCores = Platform.numberOfProcessors;
      final result = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioFilePath,
          isTranslate: false,
          isNoTimestamps: true,
          splitOnWord: true,
          threads: cpuCores > 4 ? cpuCores - 2 : cpuCores, // Leave 2 cores for system
        ),
      );

      stopwatch.stop();

      _setState(SpeechToTextState.idle);

      final transcribedText = result.text.trim();

      LogService().log(
          'SpeechToTextService: Transcribed ${audioFilePath.split('/').last} in ${stopwatch.elapsedMilliseconds}ms');

      if (transcribedText.isEmpty) {
        return TranscriptionResult.failure(
          error: 'No speech detected',
          modelUsed: _loadedModelId ?? '',
        );
      }

      return TranscriptionResult.success(
        text: transcribedText,
        transcriptionTimeMs: stopwatch.elapsedMilliseconds,
        modelUsed: _loadedModelId ?? '',
      );
    } catch (e) {
      LogService().log('SpeechToTextService: Transcription error: $e');
      _setState(SpeechToTextState.error);

      return TranscriptionResult.failure(
        error: e.toString(),
        modelUsed: _loadedModelId ?? '',
      );
    }
  }

  /// Ensure a model is loaded, downloading if necessary
  ///
  /// Returns a stream of download progress (0.0 - 1.0) or yields 1.0 immediately if already available
  Stream<double> ensureModelReady({String? modelId}) async* {
    final id = modelId ?? await _modelManager.getPreferredModel();

    // Check if already loaded
    if (_loadedModelId == id && _whisper != null) {
      yield 1.0;
      return;
    }

    // Check if downloaded
    if (!await _modelManager.isDownloaded(id)) {
      // Download the model
      yield* _modelManager.downloadModel(id);
    } else {
      yield 1.0;
    }

    // Load the model
    await loadModel(id);
  }

  void dispose() {
    _stateController.close();
    _whisper = null;
    _loadedModelId = null;
  }
}
