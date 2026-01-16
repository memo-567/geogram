/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/tts_model_info.dart';
import 'tts_model_manager.dart';
import '../../services/audio_service.dart';
import '../../services/i18n_service.dart';
import '../../services/log_service.dart';

/// Text-to-Speech service using Supertonic ONNX models.
///
/// Provides offline voice synthesis with automatic language matching
/// based on the app's current language setting.
///
/// Supertonic uses a pipeline of 4 ONNX models:
/// 1. Text Encoder - converts text to embeddings
/// 2. Duration Predictor - predicts phoneme durations
/// 3. Vector Estimator - generates acoustic features
/// 4. Vocoder - converts features to audio waveform
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final OnnxRuntime _ort = OnnxRuntime();
  final TtsModelManager _modelManager = TtsModelManager();
  final AudioService _audioService = AudioService();

  // ONNX sessions for each pipeline stage
  OrtSession? _textEncoderSession;
  OrtSession? _durationPredictorSession;
  OrtSession? _vectorEstimatorSession;
  OrtSession? _vocoderSession;

  // Config data for ONNX inference pipeline (ttsConfig may be used for future config options)
  // ignore: unused_field
  Map<String, dynamic>? _ttsConfig;
  List<int>? _unicodeIndexer;

  // Loaded voice styles cache
  final Map<TtsVoice, VoiceStyle> _voiceStyles = {};

  // Random number generator for noise
  final Random _random = Random();

  bool _isLoaded = false;
  bool _isLoading = false;

  /// Sample rate of Supertonic output (44.1kHz)
  static const int sampleRate = 44100;

  /// Whether the TTS model is loaded and ready
  bool get isLoaded => _isLoaded;

  /// Whether the model is currently loading
  bool get isLoading => _isLoading;

  /// Get TTS language matching current app language
  TtsLanguage get _currentLanguage {
    final locale = I18nService().currentLanguage;
    return TtsLanguageExtension.fromLocale(locale);
  }

  /// Load the TTS models (lazy, downloads if needed)
  ///
  /// Call this before synthesize() or speak().
  /// Progress is yielded as 0.0 to 1.0 during download.
  Stream<double> load() async* {
    if (_isLoaded) {
      yield 1.0;
      return;
    }

    if (_isLoading) {
      // Wait for existing load to complete
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      yield _isLoaded ? 1.0 : 0.0;
      return;
    }

    _isLoading = true;

    try {
      // Download models if needed (90% of progress)
      await for (final progress in _modelManager.ensureModel()) {
        yield progress * 0.9;
        LogService().log(
            'TtsService: Download progress ${(progress * 100).toStringAsFixed(1)}%');
      }

      // Load config files
      LogService().log('TtsService: Loading config files...');
      await _loadConfigs();
      yield 0.92;

      // Load ONNX sessions (remaining 8% of progress)
      LogService().log('TtsService: Loading ONNX sessions...');

      final textEncoderPath = await _modelManager.textEncoderPath;
      if (await File(textEncoderPath).exists()) {
        _textEncoderSession = await _ort.createSession(textEncoderPath);
        LogService().log('TtsService: Text encoder loaded');
      }
      yield 0.94;

      final durationPredictorPath = await _modelManager.durationPredictorPath;
      if (await File(durationPredictorPath).exists()) {
        _durationPredictorSession =
            await _ort.createSession(durationPredictorPath);
        LogService().log('TtsService: Duration predictor loaded');
      }
      yield 0.96;

      final vectorEstimatorPath = await _modelManager.vectorEstimatorPath;
      if (await File(vectorEstimatorPath).exists()) {
        _vectorEstimatorSession =
            await _ort.createSession(vectorEstimatorPath);
        LogService().log('TtsService: Vector estimator loaded');
      }
      yield 0.98;

      final vocoderPath = await _modelManager.vocoderPath;
      if (await File(vocoderPath).exists()) {
        _vocoderSession = await _ort.createSession(vocoderPath);
        LogService().log('TtsService: Vocoder loaded');
      }

      _isLoaded = _textEncoderSession != null &&
          _durationPredictorSession != null &&
          _vectorEstimatorSession != null &&
          _vocoderSession != null;

      if (_isLoaded) {
        LogService().log('TtsService: All models loaded successfully');
      } else {
        LogService().log('TtsService: Some models failed to load');
      }

      yield 1.0;
    } catch (e) {
      LogService().log('TtsService: Failed to load models: $e');
      _isLoaded = false;
    } finally {
      _isLoading = false;
    }
  }

  /// Load configuration files
  Future<void> _loadConfigs() async {
    try {
      // Load TTS config
      final ttsConfigPath = await _modelManager.ttsConfigPath;
      final ttsConfigFile = File(ttsConfigPath);
      if (await ttsConfigFile.exists()) {
        final content = await ttsConfigFile.readAsString();
        _ttsConfig = json.decode(content) as Map<String, dynamic>;
        LogService().log('TtsService: TTS config loaded');
      }

      // Load unicode indexer - it's a list of ints mapping codepoint → token
      final unicodeIndexerPath = await _modelManager.unicodeIndexerPath;
      final unicodeIndexerFile = File(unicodeIndexerPath);
      if (await unicodeIndexerFile.exists()) {
        final content = await unicodeIndexerFile.readAsString();
        final data = json.decode(content) as List<dynamic>;
        _unicodeIndexer = data.cast<int>();
        LogService().log(
            'TtsService: Unicode indexer loaded with ${_unicodeIndexer!.length} entries');
      }
    } catch (e) {
      LogService().log('TtsService: Error loading configs: $e');
    }
  }

  /// Load a voice style, caching it for reuse
  Future<VoiceStyle?> _loadVoiceStyle(TtsVoice voice) async {
    // Check cache first
    if (_voiceStyles.containsKey(voice)) {
      return _voiceStyles[voice];
    }

    try {
      final voiceStylePath = await _modelManager.voiceStylePath(voice);
      final voiceStyleFile = File(voiceStylePath);
      if (await voiceStyleFile.exists()) {
        final content = await voiceStyleFile.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        final style = VoiceStyle.fromJson(data);
        _voiceStyles[voice] = style;
        LogService().log('TtsService: Loaded voice style ${voice.id}');
        return style;
      }
    } catch (e) {
      LogService().log('TtsService: Error loading voice style ${voice.id}: $e');
    }
    return null;
  }

  /// Tokenize text to token IDs using the unicode indexer
  List<int> _tokenizeText(String text) {
    if (_unicodeIndexer == null) {
      throw StateError('Unicode indexer not loaded');
    }

    final tokens = <int>[];
    for (final char in text.runes) {
      // Get token ID from unicode indexer (indexed by codepoint)
      if (char < _unicodeIndexer!.length) {
        final tokenId = _unicodeIndexer![char];
        // -1 means unmapped character
        if (tokenId >= 0) {
          tokens.add(tokenId);
        }
      }
    }
    return tokens;
  }

  /// Create a binary mask from length
  List<double> _createMask(int length, int maxLength) {
    final mask = List<double>.filled(maxLength, 0.0);
    for (var i = 0; i < length && i < maxLength; i++) {
      mask[i] = 1.0;
    }
    return mask;
  }

  /// Generate Gaussian random numbers using Box-Muller transform
  double _gaussianRandom() {
    double u1, u2;
    do {
      u1 = _random.nextDouble();
    } while (u1 == 0);
    u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// Number of diffusion denoising steps (more = higher quality, slower)
  static const int _totalSteps = 5;

  /// Latent dimension from tts.json config
  static const int _latentDim = 24;

  /// Chunk compress factor from tts.json config
  static const int _chunkCompressFactor = 6;

  /// Synthesize text to audio samples.
  ///
  /// Returns Float32List of PCM samples at 44.1kHz sample rate.
  /// Uses the current app language unless [language] is specified.
  Future<Float32List?> synthesize(
    String text, {
    TtsVoice voice = TtsVoice.f3,
    TtsLanguage? language,
    double speed = 1.05,
  }) async {
    // Ensure models are loaded
    if (!_isLoaded) {
      await for (final _ in load()) {}
    }

    if (!_isLoaded) {
      LogService().log('TtsService: Models not loaded');
      return null;
    }

    if (_unicodeIndexer == null) {
      LogService().log('TtsService: Unicode indexer not loaded');
      return null;
    }

    final lang = language ?? _currentLanguage;

    try {
      LogService().log(
          'TtsService: Synthesizing "${text.substring(0, text.length.clamp(0, 50))}..." with voice ${voice.id}, language ${lang.code}');

      // Load voice style
      final voiceStyle = await _loadVoiceStyle(voice);
      if (voiceStyle == null) {
        LogService().log('TtsService: Failed to load voice style ${voice.id}');
        return null;
      }

      // Step 1: Tokenize text
      final tokens = _tokenizeText(text);
      if (tokens.isEmpty) {
        LogService().log('TtsService: No valid tokens from text');
        return null;
      }
      final maxLength = tokens.length;
      LogService().log('TtsService: Tokenized to ${tokens.length} tokens');

      // Create text_ids tensor: shape [1, max_length]
      final textIds = tokens.map((t) => t.toDouble()).toList();

      // Create text_mask tensor: shape [1, 1, max_length]
      final textMask = _createMask(maxLength, maxLength);

      // Step 2: Run duration predictor
      LogService().log('TtsService: Running duration predictor...');
      final durationInput = {
        'text_ids': await OrtValue.fromList(
            textIds, [1, maxLength]),
        'style_dp': await OrtValue.fromList(
            voiceStyle.styleDp, voiceStyle.styleDpDims),
        'text_mask': await OrtValue.fromList(
            textMask, [1, 1, maxLength]),
      };

      final durationOutput = await _durationPredictorSession!.run(durationInput);
      final durationsRaw =
          await durationOutput.values.first.asList() as List<double>;

      // Clean up duration inputs
      for (final tensor in durationInput.values) {
        tensor.dispose();
      }
      for (final tensor in durationOutput.values) {
        tensor.dispose();
      }

      // Apply speed and compute latent length
      final durations =
          durationsRaw.map((d) => (d / speed).clamp(0, double.infinity)).toList();
      final totalDuration = durations.fold(0.0, (a, b) => a + b);
      final latentLength = (totalDuration / _chunkCompressFactor).ceil();
      LogService().log(
          'TtsService: Duration predictor: total=$totalDuration, latent_len=$latentLength');

      if (latentLength <= 0) {
        LogService().log('TtsService: Invalid latent length');
        return null;
      }

      // Step 3: Run text encoder
      LogService().log('TtsService: Running text encoder...');
      final textEncoderInput = {
        'text_ids': await OrtValue.fromList(
            textIds, [1, maxLength]),
        'style_ttl': await OrtValue.fromList(
            voiceStyle.styleTtl, voiceStyle.styleTtlDims),
        'text_mask': await OrtValue.fromList(
            textMask, [1, 1, maxLength]),
      };

      final textEncoderOutput =
          await _textEncoderSession!.run(textEncoderInput);
      final textEmb = await textEncoderOutput.values.first.asList() as List<double>;

      // Clean up text encoder inputs (keep output for vector estimator)
      for (final tensor in textEncoderInput.values) {
        tensor.dispose();
      }

      // Get text embedding shape from output
      // Expected: [1, embed_dim, max_length] or similar
      LogService().log(
          'TtsService: Text encoder output size: ${textEmb.length}');

      // Step 4: Create latent mask from durations
      final latentMask = _createMask(latentLength, latentLength);

      // Step 5: Initialize noisy latent (Gaussian noise)
      // Shape: [1, latent_dim * chunk_compress_factor, latent_length]
      final latentChannels = _latentDim * _chunkCompressFactor; // 144
      final latentSize = latentChannels * latentLength;
      var noisyLatent =
          List<double>.generate(latentSize, (_) => _gaussianRandom());

      // Step 6: Run diffusion denoising loop
      LogService().log(
          'TtsService: Running vector estimator with $_totalSteps steps...');

      for (var step = 0; step < _totalSteps; step++) {
        final vectorInput = {
          'noisy_latent': await OrtValue.fromList(
              noisyLatent, [1, latentChannels, latentLength]),
          'text_emb': await OrtValue.fromList(textEmb, textEncoderOutput.values.first.shape),
          'style_ttl': await OrtValue.fromList(
              voiceStyle.styleTtl, voiceStyle.styleTtlDims),
          'text_mask': await OrtValue.fromList(
              textMask, [1, 1, maxLength]),
          'latent_mask': await OrtValue.fromList(
              latentMask, [1, 1, latentLength]),
          'current_step': await OrtValue.fromList(
              [step.toDouble()], [1]),
          'total_step': await OrtValue.fromList(
              [_totalSteps.toDouble()], [1]),
        };

        final vectorOutput = await _vectorEstimatorSession!.run(vectorInput);
        noisyLatent = await vectorOutput.values.first.asList() as List<double>;

        // Clean up this iteration's tensors
        for (final tensor in vectorInput.values) {
          tensor.dispose();
        }
        for (final tensor in vectorOutput.values) {
          tensor.dispose();
        }

        LogService().log('TtsService: Denoising step ${step + 1}/$_totalSteps');
      }

      // Clean up text encoder output
      for (final tensor in textEncoderOutput.values) {
        tensor.dispose();
      }

      // Step 7: Run vocoder to generate audio
      LogService().log('TtsService: Running vocoder...');
      final vocoderInput = {
        'latent': await OrtValue.fromList(
            noisyLatent, [1, latentChannels, latentLength]),
      };

      final vocoderOutput = await _vocoderSession!.run(vocoderInput);
      final wavData =
          await vocoderOutput.values.first.asList() as List<double>;

      // Clean up vocoder tensors
      for (final tensor in vocoderInput.values) {
        tensor.dispose();
      }
      for (final tensor in vocoderOutput.values) {
        tensor.dispose();
      }

      // Convert to Float32List
      final samples = Float32List(wavData.length);
      for (var i = 0; i < wavData.length; i++) {
        samples[i] = wavData[i].clamp(-1.0, 1.0);
      }

      LogService().log(
          'TtsService: Generated ${samples.length} samples (${(samples.length / sampleRate * 1000).round()}ms)');

      return samples;
    } catch (e, st) {
      LogService().log('TtsService: Synthesis error: $e\n$st');
      return null;
    }
  }

  /// Speak text immediately using the current app language.
  ///
  /// This is a convenience method that synthesizes and plays audio.
  Future<void> speak(
    String text, {
    TtsVoice voice = TtsVoice.f3,
    TtsLanguage? language,
  }) async {
    final samples = await synthesize(text, voice: voice, language: language);
    if (samples != null && samples.isNotEmpty) {
      await _audioService.playSamples(samples, sampleRate: sampleRate);
    }
  }

  /// Save synthesized audio to a WAV file.
  Future<File?> saveToFile(
    String text,
    String outputPath, {
    TtsVoice voice = TtsVoice.f3,
    TtsLanguage? language,
  }) async {
    final samples = await synthesize(text, voice: voice, language: language);
    if (samples == null || samples.isEmpty) {
      return null;
    }

    try {
      final wavBytes = _createWavFile(samples);
      final file = File(outputPath);
      await file.writeAsBytes(wavBytes);
      LogService().log(
          'TtsService: Saved ${(wavBytes.length / 1024).toStringAsFixed(1)} KB to $outputPath');
      return file;
    } catch (e) {
      LogService().log('TtsService: Failed to save file: $e');
      return null;
    }
  }

  /// Create WAV file bytes from Float32 samples.
  Uint8List _createWavFile(Float32List samples) {
    // Convert float samples to 16-bit PCM
    final int16Samples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      int16Samples[i] = (clamped * 32767).round();
    }

    final dataSize = int16Samples.length * 2;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    var offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // 'R'
    buffer.setUint8(offset++, 0x49); // 'I'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // 'W'
    buffer.setUint8(offset++, 0x41); // 'A'
    buffer.setUint8(offset++, 0x56); // 'V'
    buffer.setUint8(offset++, 0x45); // 'E'

    // fmt chunk
    buffer.setUint8(offset++, 0x66); // 'f'
    buffer.setUint8(offset++, 0x6D); // 'm'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x20); // ' '
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little); // PCM
    offset += 2;
    buffer.setUint16(offset, 1, Endian.little); // Mono
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, sampleRate * 2, Endian.little);
    offset += 4;
    buffer.setUint16(offset, 2, Endian.little);
    offset += 2;
    buffer.setUint16(offset, 16, Endian.little);
    offset += 2;

    // data chunk
    buffer.setUint8(offset++, 0x64); // 'd'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    for (var i = 0; i < int16Samples.length; i++) {
      buffer.setInt16(offset, int16Samples[i], Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _textEncoderSession?.close();
    await _durationPredictorSession?.close();
    await _vectorEstimatorSession?.close();
    await _vocoderSession?.close();
    _textEncoderSession = null;
    _durationPredictorSession = null;
    _vectorEstimatorSession = null;
    _vocoderSession = null;
    _isLoaded = false;
  }
}
