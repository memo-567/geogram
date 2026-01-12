/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../bot/models/whisper_model_info.dart';
import '../bot/services/speech_to_text_service.dart';
import '../bot/services/whisper_model_manager.dart';
import '../services/audio_service.dart';
import '../services/ble_foreground_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';

/// Dialog state machine
enum _DialogState {
  /// Initial: checking if model is downloaded
  checkingModel,

  /// Auto-downloading model
  downloadingModel,

  /// Ready to record
  idle,

  /// Currently recording
  recording,

  /// Transcribing audio
  processing,

  /// Error occurred
  error,
}

/// Dialog for recording and transcribing voice to text
class TranscriptionDialog extends StatefulWidget {
  /// Localization service
  final I18nService i18n;

  /// Maximum recording duration
  final Duration maxRecordingDuration;

  const TranscriptionDialog({
    super.key,
    required this.i18n,
    this.maxRecordingDuration = const Duration(seconds: 30),
  });

  @override
  State<TranscriptionDialog> createState() => _TranscriptionDialogState();
}

class _TranscriptionDialogState extends State<TranscriptionDialog>
    with SingleTickerProviderStateMixin {
  final SpeechToTextService _sttService = SpeechToTextService();
  final WhisperModelManager _modelManager = WhisperModelManager();
  final AudioService _audioService = AudioService();
  final AudioRecorder _wavRecorder = AudioRecorder();
  final BLEForegroundService _foregroundService = BLEForegroundService();

  _DialogState _state = _DialogState.checkingModel;
  Duration _recordingDuration = Duration.zero;
  double _downloadProgress = 0;
  String? _errorMessage;
  String? _recordedFilePath;
  String? _modelId;
  bool _isRecording = false;
  String? _wavRecordingPath;
  bool _modelReady = false;
  bool _modelLoading = false;
  Future<void>? _modelLoadFuture;

  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<double>? _downloadSubscription;
  Timer? _recordingTimer;

  bool _foregroundServiceStarted = false;
  bool _foregroundServiceWasRunning = false;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _prepareModel();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _animationController.repeat(reverse: true);
  }

  Future<void> _prepareModel() async {
    try {
      await _modelManager.initialize();
      await _sttService.initialize();

      // Get preferred model
      _modelId = await _modelManager.getPreferredModel();

      // Model not loaded yet - check if downloaded
      if (await _modelManager.isDownloaded(_modelId!)) {
        if (mounted) {
          setState(() => _state = _DialogState.idle);
        }
        _startBackgroundModelLoad();
        return;
      }

      // Need to download model first
      if (mounted) {
        setState(() => _state = _DialogState.downloadingModel);
      }
      _startModelDownload();
    } catch (e) {
      LogService().log('TranscriptionDialog: Error checking model: $e');
      if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _startModelDownload() {
    _downloadSubscription?.cancel();
    _downloadSubscription = _modelManager.downloadModel(_modelId!).listen(
      (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
      onDone: () async {
        if (mounted) {
          setState(() => _state = _DialogState.idle);
        }
        _startBackgroundModelLoad();
      },
      onError: (e) {
        LogService().log('TranscriptionDialog: Download error: $e');
        if (mounted) {
          setState(() {
            _state = _DialogState.error;
            _errorMessage = e.toString();
          });
        }
      },
    );
  }

  void _startBackgroundModelLoad() {
    if (_modelId == null) {
      return;
    }

    if (_sttService.isModelLoaded && _sttService.loadedModelId == _modelId) {
      if (mounted) {
        setState(() {
          _modelReady = true;
          _modelLoading = false;
        });
        // Model already loaded, start recording immediately
        _startRecording();
      }
      return;
    }

    if (_modelLoadFuture != null) {
      return;
    }

    if (mounted) {
      setState(() {
        _modelLoading = true;
      });
    } else {
      _modelLoading = true;
    }
    _modelLoadFuture = () async {
      try {
        LogService().log('TranscriptionDialog: Background loading model $_modelId');
        final loaded = await _sttService.loadModel(_modelId!);
        final warmed = loaded
            ? await _sttService.ensureModelWarm(_modelId!)
            : false;
        if (mounted) {
          setState(() {
            _modelReady = loaded && warmed;
            _modelLoading = false;
            if (!_modelReady) {
              _state = _DialogState.error;
              _errorMessage = widget.i18n.t('transcription_failed');
            }
          });
          // Model loaded, start recording automatically
          if (_modelReady) {
            _startRecording();
          }
        }
      } catch (e) {
        LogService().log('TranscriptionDialog: Background load error: $e');
        if (mounted) {
          setState(() {
            _modelLoading = false;
            _state = _DialogState.error;
            _errorMessage = e.toString();
          });
        }
      }
    }();
  }

  Future<void> _handleStartRecording() async {
    if (_modelReady) {
      await _startRecording();
      return;
    }

    // Wait for model to finish loading, then start recording
    if (_modelLoadFuture != null) {
      await _modelLoadFuture;
      if (_modelReady && mounted) {
        await _startRecording();
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      // Check permission using the recorder directly
      if (!await _wavRecorder.hasPermission()) {
        if (mounted) {
          setState(() {
            _state = _DialogState.error;
            _errorMessage = widget.i18n.t('microphone_permission_required');
          });
        }
        return;
      }

      // Get temp directory for WAV file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _wavRecordingPath = '${tempDir.path}/transcription_$timestamp.wav';

      LogService().log('TranscriptionDialog: Starting WAV recording to $_wavRecordingPath');

      // Start recording in WAV format (16kHz mono for Whisper)
      await _wavRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _wavRecordingPath!,
      );

      _isRecording = true;
      _recordingDuration = Duration.zero;

      // Start duration timer
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingDuration += const Duration(milliseconds: 100);
        });

        // Auto-stop at max duration
        if (_recordingDuration >= widget.maxRecordingDuration) {
          _stopRecording();
        }
      });

      if (mounted) {
        setState(() {
          _state = _DialogState.recording;
        });
      }
    } catch (e) {
      LogService().log('TranscriptionDialog: Recording error: $e');
      if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _isRecording = false;

    try {
      final path = await _wavRecorder.stop();
      LogService().log('TranscriptionDialog: Recording stopped, path: $path');

      if (path != null && mounted) {
        _recordedFilePath = path;
        setState(() => _state = _DialogState.processing);
        _transcribeAudio();
      } else if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = widget.i18n.t('recording_failed');
        });
      }
    } catch (e) {
      LogService().log('TranscriptionDialog: Error stopping recording: $e');
      if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _transcribeAudio() async {
    if (_recordedFilePath == null) {
      setState(() {
        _state = _DialogState.error;
        _errorMessage = widget.i18n.t('no_audio_recorded');
      });
      return;
    }

    await _beginForegroundProcessing();

    try {
      // Convert audio to WAV format for Whisper
      // The audio service records in Opus/WebM, but Whisper needs WAV
      final wavPath = await _convertToWav(_recordedFilePath!);

      final result = await _sttService.transcribe(wavPath);

      // Cleanup temporary files
      _cleanupTempFiles(wavPath);

      if (result.success && mounted) {
        Navigator.of(context).pop(result.text);
      } else if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = result.error ?? widget.i18n.t('transcription_failed');
        });
      }
    } catch (e) {
      LogService().log('TranscriptionDialog: Transcription error: $e');
      if (mounted) {
        setState(() {
          _state = _DialogState.error;
          _errorMessage = e.toString();
        });
      }
    } finally {
      await _endForegroundProcessing();
    }
  }

  /// Convert audio file to WAV format for Whisper
  /// Note: Currently returns the original file and relies on Whisper to handle it
  /// If Whisper can't handle it, we need to add FFmpeg support
  Future<String> _convertToWav(String inputPath) async {
    // If already WAV, return as-is
    if (inputPath.toLowerCase().endsWith('.wav')) {
      return inputPath;
    }

    // For now, whisper_flutter_new should handle common formats
    // If it fails, the error will be caught and shown to user
    LogService().log('TranscriptionDialog: Using audio file directly: ${inputPath.split('/').last}');
    return inputPath;
  }

  void _cleanupTempFiles(String wavPath) {
    // Delete recorded file and any temp files
    try {
      if (_recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      if (wavPath != _recordedFilePath) {
        final wavFile = File(wavPath);
        if (wavFile.existsSync()) {
          wavFile.deleteSync();
        }
      }
    } catch (e) {
      LogService().log('TranscriptionDialog: Cleanup error: $e');
    }
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _downloadProgress = 0;
      _recordingDuration = Duration.zero;
      _modelReady = false;
      _modelLoading = false;
      _modelLoadFuture = null;
    });
    _prepareModel();
  }

  void _cancel() {
    _durationSubscription?.cancel();
    _downloadSubscription?.cancel();

    // Stop recording if in progress
    if (_state == _DialogState.recording) {
      _audioService.stopRecording();
    }

    // Cleanup any temp files
    if (_recordedFilePath != null) {
      _cleanupTempFiles(_recordedFilePath!);
    }

    Navigator.of(context).pop();
  }

  Future<void> _beginForegroundProcessing() async {
    if (!Platform.isAndroid) {
      return;
    }
    _foregroundServiceWasRunning = _foregroundService.isRunning;
    if (!_foregroundServiceWasRunning) {
      _foregroundServiceStarted = await _foregroundService.start();
      if (_foregroundServiceStarted) {
        LogService().log('TranscriptionDialog: Foreground service started for transcription');
      }
    }
  }

  Future<void> _endForegroundProcessing() async {
    if (!Platform.isAndroid) {
      return;
    }
    if (_foregroundServiceStarted && !_foregroundServiceWasRunning) {
      if (_foregroundService.isRunning && !_foregroundService.keepAliveEnabled) {
        await _foregroundService.stop();
        LogService().log('TranscriptionDialog: Foreground service stopped after transcription');
      }
    }
    _foregroundServiceStarted = false;
    _foregroundServiceWasRunning = false;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _animationController.dispose();
    _durationSubscription?.cancel();
    _downloadSubscription?.cancel();
    _recordingTimer?.cancel();
    _wavRecorder.dispose();
    unawaited(_endForegroundProcessing());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildTitle(),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  Widget _buildTitle() {
    switch (_state) {
      case _DialogState.checkingModel:
        return Text(widget.i18n.t('voice_to_text'));
      case _DialogState.downloadingModel:
        return Text(widget.i18n.t('downloading_speech_model'));
      case _DialogState.idle:
        return Text(widget.i18n.t('voice_to_text'));
      case _DialogState.recording:
        return Text(widget.i18n.t('listening'));
      case _DialogState.processing:
        return Text(widget.i18n.t('processing_speech'));
      case _DialogState.error:
        return Text(widget.i18n.t('error'));
    }
  }

  Widget _buildContent() {
    return SizedBox(
      width: 280,
      child: switch (_state) {
        _DialogState.checkingModel => _buildCheckingUI(),
        _DialogState.downloadingModel => _buildDownloadingUI(),
        _DialogState.idle => _buildIdleUI(),
        _DialogState.recording => _buildRecordingUI(),
        _DialogState.processing => _buildProcessingUI(),
        _DialogState.error => _buildErrorUI(),
      },
    );
  }

  Widget _buildCheckingUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(widget.i18n.t('checking_speech_model')),
      ],
    );
  }

  Widget _buildDownloadingUI() {
    final model = WhisperModels.getById(_modelId ?? WhisperModels.defaultModelId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: _downloadProgress,
                strokeWidth: 6,
              ),
            ),
            Text(
              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (model != null) ...[
          Text(
            model.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            model.sizeString,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          widget.i18n.t('first_time_download'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildIdleUI() {
    // When model is loading, show loading UI (recording will auto-start when ready)
    if (_modelLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            widget.i18n.t('voice_model_loading_one_time'),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Fallback UI (should rarely be seen since recording auto-starts)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Icon(
          Icons.mic,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          widget.i18n.t('tap_to_start_recording'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.i18n.t('max_duration_seconds',
              params: [widget.maxRecordingDuration.inSeconds.toString()]),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          // Animated waveform visualization
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(120, 60),
                painter: _AnimatedWaveformPainter(
                  color: Theme.of(context).colorScheme.error,
                  scale: _pulseAnimation.value,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _formatDuration(_recordingDuration),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          // Progress bar showing time remaining
          LinearProgressIndicator(
            value: _recordingDuration.inMilliseconds /
                widget.maxRecordingDuration.inMilliseconds,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Text(
            widget.i18n.t('up_to_seconds', params: ['${widget.maxRecordingDuration.inSeconds}']),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(),
        ),
        const SizedBox(height: 24),
        Text(
          widget.i18n.t('transcription_wait_notice'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildErrorUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Icon(
          Icons.error_outline,
          size: 64,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          _errorMessage ?? widget.i18n.t('unknown_error'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case _DialogState.checkingModel:
        return [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.i18n.t('cancel')),
          ),
        ];

      case _DialogState.downloadingModel:
        return [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.i18n.t('cancel')),
          ),
        ];

      case _DialogState.idle:
        // When model is loading, only show Cancel (recording will auto-start)
        if (_modelLoading) {
          return [
            TextButton(
              onPressed: _cancel,
              child: Text(widget.i18n.t('cancel')),
            ),
          ];
        }
        // Fallback: show Start button if model ready but recording hasn't started
        return [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: _handleStartRecording,
            icon: const Icon(Icons.mic),
            label: Text(widget.i18n.t('start')),
          ),
        ];

      case _DialogState.recording:
        return [
          FilledButton.icon(
            onPressed: _stopRecording,
            icon: const Icon(Icons.stop),
            label: Text(widget.i18n.t('stop')),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ];

      case _DialogState.processing:
        return []; // No actions while processing

      case _DialogState.error:
        return [
          TextButton(
            onPressed: _cancel,
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: _retry,
            child: Text(widget.i18n.t('retry')),
          ),
        ];
    }
  }
}

/// Animated waveform painter for recording state
class _AnimatedWaveformPainter extends CustomPainter {
  final Color color;
  final double scale;

  _AnimatedWaveformPainter({
    required this.color,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const barCount = 7;
    final barWidth = size.width / (barCount * 2 - 1);

    // Varying heights with animation
    final baseHeights = [0.3, 0.5, 0.7, 1.0, 0.7, 0.5, 0.3];

    for (var i = 0; i < barCount; i++) {
      final x = barWidth * (i * 2) + barWidth / 2;

      // Animate alternating bars differently
      final animatedScale = i % 2 == 0 ? scale : 2 - scale;
      final barHeight = size.height * baseHeights[i] * animatedScale * 0.8;
      final top = (size.height - barHeight) / 2;

      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedWaveformPainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.color != color;
  }
}
