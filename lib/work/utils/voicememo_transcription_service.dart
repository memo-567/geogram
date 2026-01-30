/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import '../../services/log_service.dart';
import '../models/voicememo_content.dart';

/// Result of a voice memo transcription
class VoiceMemoTranscriptionResult {
  final bool success;
  final String? text;
  final String? model;
  final String? error;
  final bool cancelled;

  const VoiceMemoTranscriptionResult({
    required this.success,
    this.text,
    this.model,
    this.error,
    this.cancelled = false,
  });

  factory VoiceMemoTranscriptionResult.success({
    required String text,
    required String model,
  }) {
    return VoiceMemoTranscriptionResult(
      success: true,
      text: text,
      model: model,
    );
  }

  factory VoiceMemoTranscriptionResult.failure(String error) {
    return VoiceMemoTranscriptionResult(
      success: false,
      error: error,
    );
  }

  factory VoiceMemoTranscriptionResult.cancelled() {
    return const VoiceMemoTranscriptionResult(
      success: false,
      cancelled: true,
    );
  }

  ClipTranscription? toClipTranscription() {
    if (!success || text == null) return null;
    return ClipTranscription(
      text: text!,
      model: model ?? 'whisper',
      transcribedAt: DateTime.now(),
    );
  }
}

/// State of the transcription service
enum TranscriptionState {
  idle,
  preparing,
  transcribing,
  cancelling,
}

/// Service for transcribing voice memo clips using Whisper
///
/// This service provides:
/// - Background transcription that doesn't block UI
/// - Cancellation support at any time
/// - Single session enforcement (only 1 transcription at a time)
/// - Linux support via whisper CLI (whisper.cpp)
///
/// On Linux, requires one of these whisper CLI tools to be installed:
/// - main (from whisper.cpp build)
/// - whisper (openai-whisper Python package)
/// - whisper-cpp
class VoiceMemoTranscriptionService {
  static final VoiceMemoTranscriptionService _instance =
      VoiceMemoTranscriptionService._internal();
  factory VoiceMemoTranscriptionService() => _instance;
  VoiceMemoTranscriptionService._internal();

  TranscriptionState _state = TranscriptionState.idle;
  Process? _currentProcess;
  String? _currentClipId;
  Completer<VoiceMemoTranscriptionResult>? _currentCompleter;
  String? _whisperPath;
  String? _whisperModel;

  final _stateController = StreamController<TranscriptionState>.broadcast();

  /// Stream of state changes
  Stream<TranscriptionState> get stateStream => _stateController.stream;

  /// Current state
  TranscriptionState get state => _state;

  /// ID of the clip currently being transcribed
  String? get currentClipId => _currentClipId;

  /// Whether a transcription is in progress
  bool get isBusy => _state != TranscriptionState.idle;

  void _setState(TranscriptionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Initialize the service - detect available whisper CLI
  Future<void> initialize() async {
    if (_whisperPath != null) return;

    // Try to find whisper CLI on the system
    // Priority: main (whisper.cpp) > whisper-cpp > whisper (Python)
    final candidates = ['main', 'whisper-cpp', 'whisper'];

    for (final cmd in candidates) {
      try {
        final result = await Process.run('which', [cmd]);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty) {
            // Verify it's actually whisper
            final versionResult = await Process.run(path, ['--help']);
            final help = versionResult.stdout.toString().toLowerCase() +
                versionResult.stderr.toString().toLowerCase();
            if (help.contains('whisper') || help.contains('transcri')) {
              _whisperPath = path;
              LogService().log(
                'VoiceMemoTranscriptionService: Found whisper at $path',
              );
              break;
            }
          }
        }
      } catch (_) {
        // Continue to next candidate
      }
    }

    // Set default model (small is a good balance of speed/quality)
    _whisperModel = 'small';

    if (_whisperPath == null) {
      LogService().log(
        'VoiceMemoTranscriptionService: No whisper CLI found. '
        'Install whisper.cpp or openai-whisper for transcription support.',
      );
    }
  }

  /// Check if transcription is supported on this platform
  Future<bool> isSupported() async {
    await initialize();
    return _whisperPath != null;
  }

  /// Get help message for installing whisper
  String getInstallHelp() {
    if (Platform.isLinux) {
      return 'Install whisper.cpp:\n'
          '  git clone https://github.com/ggml-org/whisper.cpp\n'
          '  cd whisper.cpp && make\n'
          '  sudo cp main /usr/local/bin/whisper-cpp\n\n'
          'Or install Python whisper:\n'
          '  pip install openai-whisper';
    }
    return 'Speech-to-text is not available on this platform.';
  }

  /// Transcribe a voice memo clip
  ///
  /// [audioBytes] - The audio data (OGG/Opus format)
  /// [clipId] - ID of the clip being transcribed (for tracking)
  ///
  /// Returns a [VoiceMemoTranscriptionResult] with the transcription or error.
  /// Can be cancelled at any time using [cancel].
  Future<VoiceMemoTranscriptionResult> transcribe({
    required List<int> audioBytes,
    required String clipId,
  }) async {
    // Check if already busy
    if (isBusy) {
      return VoiceMemoTranscriptionResult.failure(
        'Another transcription is in progress',
      );
    }

    // Check if whisper is available
    await initialize();
    if (_whisperPath == null) {
      return VoiceMemoTranscriptionResult.failure(
        'Whisper not installed. ${getInstallHelp()}',
      );
    }

    _currentClipId = clipId;
    _currentCompleter = Completer<VoiceMemoTranscriptionResult>();
    _setState(TranscriptionState.preparing);

    // Create temp files
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final oggPath = '${tempDir.path}/transcribe_$timestamp.ogg';
    final wavPath = '${tempDir.path}/transcribe_$timestamp.wav';

    try {
      // Write audio to temp file
      await File(oggPath).writeAsBytes(audioBytes);

      // Convert OGG to WAV (16kHz mono for Whisper)
      _setState(TranscriptionState.preparing);
      final convertResult = await _convertToWav(oggPath, wavPath);
      if (!convertResult) {
        return VoiceMemoTranscriptionResult.failure(
          'Failed to convert audio format. Is ffmpeg installed?',
        );
      }

      // Check if cancelled during conversion
      if (_state == TranscriptionState.cancelling) {
        return VoiceMemoTranscriptionResult.cancelled();
      }

      // Run whisper transcription
      _setState(TranscriptionState.transcribing);
      final result = await _runWhisper(wavPath);

      return result;
    } catch (e) {
      LogService().log('VoiceMemoTranscriptionService: Error: $e');
      return VoiceMemoTranscriptionResult.failure(e.toString());
    } finally {
      // Cleanup
      _currentClipId = null;
      _currentProcess = null;
      _currentCompleter = null;
      _setState(TranscriptionState.idle);

      // Delete temp files
      await _safeDelete(oggPath);
      await _safeDelete(wavPath);
    }
  }

  /// Cancel the current transcription
  Future<void> cancel() async {
    if (!isBusy) return;

    _setState(TranscriptionState.cancelling);

    // Kill the whisper process if running
    if (_currentProcess != null) {
      _currentProcess!.kill(ProcessSignal.sigterm);
      _currentProcess = null;
    }

    // Complete with cancelled result
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete(VoiceMemoTranscriptionResult.cancelled());
    }

    LogService().log(
      'VoiceMemoTranscriptionService: Cancelled transcription for $_currentClipId',
    );
  }

  /// Convert OGG/Opus to WAV (16kHz mono) using ffmpeg
  Future<bool> _convertToWav(String oggPath, String wavPath) async {
    try {
      final result = await Process.run('ffmpeg', [
        '-i', oggPath,
        '-ar', '16000', // 16kHz sample rate (required by Whisper)
        '-ac', '1', // Mono
        '-y', // Overwrite output
        wavPath,
      ]);

      if (result.exitCode != 0) {
        LogService().log(
          'VoiceMemoTranscriptionService: ffmpeg conversion failed: ${result.stderr}',
        );
        return false;
      }

      return true;
    } catch (e) {
      LogService().log(
        'VoiceMemoTranscriptionService: ffmpeg not available: $e',
      );
      return false;
    }
  }

  /// Run whisper CLI to transcribe the audio
  Future<VoiceMemoTranscriptionResult> _runWhisper(String wavPath) async {
    try {
      // Determine arguments based on whisper variant
      final List<String> args;

      if (_whisperPath!.contains('main') || _whisperPath!.contains('whisper-cpp')) {
        // whisper.cpp main binary
        // Needs model path - try standard locations
        final modelPath = await _findWhisperModel();
        if (modelPath == null) {
          return VoiceMemoTranscriptionResult.failure(
            'Whisper model not found. Download a model:\n'
            '  cd whisper.cpp && ./models/download-ggml-model.sh small',
          );
        }

        args = [
          '-m', modelPath,
          '-f', wavPath,
          '--no-timestamps',
          '-otxt', // Output as text
        ];
      } else {
        // openai-whisper Python package
        args = [
          wavPath,
          '--model', _whisperModel!,
          '--output_format', 'txt',
          '--output_dir', Directory.systemTemp.path,
        ];
      }

      // Start the process
      _currentProcess = await Process.start(_whisperPath!, args);

      // Capture output
      final stdout = StringBuffer();
      final stderr = StringBuffer();

      _currentProcess!.stdout.transform(const SystemEncoding().decoder).listen(
        (data) => stdout.write(data),
      );
      _currentProcess!.stderr.transform(const SystemEncoding().decoder).listen(
        (data) => stderr.write(data),
      );

      // Wait for completion
      final exitCode = await _currentProcess!.exitCode;

      // Check if cancelled
      if (_state == TranscriptionState.cancelling) {
        return VoiceMemoTranscriptionResult.cancelled();
      }

      if (exitCode != 0) {
        LogService().log(
          'VoiceMemoTranscriptionService: whisper failed: ${stderr.toString()}',
        );
        return VoiceMemoTranscriptionResult.failure(
          'Transcription failed: ${stderr.toString().split('\n').first}',
        );
      }

      // Get transcription text
      String text;
      if (_whisperPath!.contains('main') || _whisperPath!.contains('whisper-cpp')) {
        // whisper.cpp outputs to stdout or .txt file
        text = stdout.toString().trim();
        if (text.isEmpty) {
          // Try reading output file
          final txtPath = wavPath.replaceAll('.wav', '.txt');
          final txtFile = File(txtPath);
          if (await txtFile.exists()) {
            text = await txtFile.readAsString();
            await txtFile.delete();
          }
        }
      } else {
        // openai-whisper creates a .txt file
        final baseName = wavPath.split('/').last.replaceAll('.wav', '');
        final txtPath = '${Directory.systemTemp.path}/$baseName.txt';
        final txtFile = File(txtPath);
        if (await txtFile.exists()) {
          text = await txtFile.readAsString();
          await txtFile.delete();
        } else {
          text = stdout.toString().trim();
        }
      }

      text = text.trim();

      if (text.isEmpty) {
        return VoiceMemoTranscriptionResult.failure('No speech detected');
      }

      LogService().log(
        'VoiceMemoTranscriptionService: Transcription complete (${text.length} chars)',
      );

      return VoiceMemoTranscriptionResult.success(
        text: text,
        model: 'whisper-$_whisperModel',
      );
    } catch (e) {
      LogService().log('VoiceMemoTranscriptionService: whisper error: $e');
      return VoiceMemoTranscriptionResult.failure(e.toString());
    }
  }

  /// Find whisper model file
  Future<String?> _findWhisperModel() async {
    // Common locations for whisper.cpp models
    final home = Platform.environment['HOME'] ?? '';
    final modelName = 'ggml-$_whisperModel.bin';

    final searchPaths = [
      '/usr/share/whisper/models/$modelName',
      '/usr/local/share/whisper/models/$modelName',
      '$home/.local/share/whisper/models/$modelName',
      '$home/whisper.cpp/models/$modelName',
      '$home/.cache/whisper/$modelName',
      // Also try without ggml- prefix
      '/usr/share/whisper/models/$_whisperModel.bin',
      '$home/.local/share/whisper/models/$_whisperModel.bin',
    ];

    for (final path in searchPaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  void dispose() {
    cancel();
    _stateController.close();
  }
}
