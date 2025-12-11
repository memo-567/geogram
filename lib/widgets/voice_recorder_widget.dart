import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/log_service.dart';
import '../services/audio_platform_stub.dart'
    if (dart.library.io) '../services/audio_platform_io.dart';

/// Voice message recorder widget.
///
/// States:
/// 1. **Recording**: Red dot, timer (max 30s), cancel/send buttons
/// 2. **Preview**: Play button, progress bar, cancel/send buttons (no waveform)
class VoiceRecorderWidget extends StatefulWidget {
  /// Called when user sends the voice message.
  /// Receives the file path and duration in seconds.
  final void Function(String filePath, int durationSeconds) onSend;

  /// Called when user cancels recording.
  final VoidCallback onCancel;

  const VoiceRecorderWidget({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final AudioService _audioService = AudioService();

  _RecorderState _state = _RecorderState.idle;
  Duration _recordingDuration = Duration.zero;
  String? _recordedFilePath;
  int _recordedDurationSeconds = 0;

  // Preview playback
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _isPreviewPlaying = false;

  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _previewPositionSubscription;
  StreamSubscription<bool>? _previewPlayingSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _startRecording();
  }

  void _setupListeners() {
    // Recording duration updates
    _durationSubscription = _audioService.recordingDurationStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        _recordingDuration = duration;
      });
    });

    // Preview player position - use AudioService streams
    _previewPositionSubscription = _audioService.positionStream.listen((position) {
      if (!mounted || _state != _RecorderState.preview) return;
      setState(() {
        _previewPosition = position;
        // Check if playback completed
        if (_previewDuration > Duration.zero && position >= _previewDuration - const Duration(milliseconds: 100)) {
          _isPreviewPlaying = false;
          _previewPosition = Duration.zero;
        }
      });
    });

    // Preview player playing state
    _previewPlayingSubscription = _audioService.playingStream.listen((playing) {
      if (!mounted || _state != _RecorderState.preview) return;
      setState(() {
        _isPreviewPlaying = playing;
      });
    });
  }

  Future<void> _startRecording() async {
    try {
      // Initialize audio service
      await _audioService.initialize();

      // Check permission first
      if (!await _audioService.hasPermission()) {
        LogService().log('VoiceRecorderWidget: No microphone permission');
        // Show error and cancel
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
          widget.onCancel();
        }
        return;
      }

      final path = await _audioService.startRecording();
      if (path != null && mounted) {
        setState(() {
          _state = _RecorderState.recording;
        });
      } else if (mounted) {
        final error = _audioService.lastError ?? 'Unknown error';
        LogService().log('VoiceRecorderWidget: Recording failed: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $error')),
        );
        widget.onCancel();
      }
    } catch (e) {
      LogService().log('VoiceRecorderWidget: Exception starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
        widget.onCancel();
      }
    }
  }

  Future<void> _stopRecording() async {
    final path = await _audioService.stopRecording();
    if (path != null && mounted) {
      _recordedFilePath = path;
      _recordedDurationSeconds = _recordingDuration.inSeconds;

      // Load for preview using AudioService
      final duration = await _audioService.load(path);

      // Also get file duration for more accuracy
      final fileDuration = await _audioService.getFileDuration(path);

      setState(() {
        _state = _RecorderState.preview;
        _previewDuration = fileDuration ?? duration ?? Duration.zero;
        _previewPosition = Duration.zero;
      });

      LogService().log('VoiceRecorderWidget: Preview loaded, duration: $_previewDuration');
    } else if (mounted) {
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    if (_state == _RecorderState.recording) {
      await _audioService.cancelRecording();
    } else if (_recordedFilePath != null) {
      // Delete preview file
      final file = PlatformFile(_recordedFilePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    widget.onCancel();
  }

  void _send() {
    if (_recordedFilePath != null) {
      widget.onSend(_recordedFilePath!, _recordedDurationSeconds);
    }
  }

  Future<void> _togglePreviewPlayback() async {
    if (_isPreviewPlaying) {
      await _audioService.pause();
    } else {
      // If at the end, seek to start
      if (_previewPosition >= _previewDuration - const Duration(milliseconds: 100)) {
        await _audioService.seek(Duration.zero);
        setState(() {
          _previewPosition = Duration.zero;
        });
      }
      await _audioService.play();
    }
  }

  Future<void> _seekPreview(double value) async {
    final position = Duration(milliseconds: (value * _previewDuration.inMilliseconds).round());
    await _audioService.seek(position);
    setState(() {
      _previewPosition = position;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _previewPositionSubscription?.cancel();
    _previewPlayingSubscription?.cancel();
    // Stop any playback when widget is disposed
    if (_state == _RecorderState.preview && _isPreviewPlaying) {
      _audioService.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: _state == _RecorderState.recording
          ? _buildRecordingUI(theme)
          : _buildPreviewUI(theme),
    );
  }

  Widget _buildRecordingUI(ThemeData theme) {
    final maxDuration = AudioService.maxRecordingDuration;
    final progress = _recordingDuration.inMilliseconds / maxDuration.inMilliseconds;

    return Row(
      children: [
        // Cancel button
        IconButton(
          icon: Icon(Icons.close, color: theme.colorScheme.error),
          onPressed: _cancel,
          tooltip: 'Cancel',
        ),

        const SizedBox(width: 8),

        // Recording indicator and timer
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated recording dot
              _AnimatedRecordingDot(),
              const SizedBox(width: 8),

              // Timer
              Text(
                _formatDuration(_recordingDuration),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              const SizedBox(width: 8),

              // Max duration indicator
              Text(
                '/ ${_formatDuration(maxDuration)}',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Stop/Send button
        IconButton(
          icon: Icon(Icons.stop, color: theme.colorScheme.primary),
          onPressed: _stopRecording,
          tooltip: 'Stop recording',
        ),
      ],
    );
  }

  Widget _buildPreviewUI(ThemeData theme) {
    return Row(
      children: [
        // Cancel/Delete button
        IconButton(
          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          onPressed: _cancel,
          tooltip: 'Delete',
        ),

        // Duration display
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_previewDuration),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),

        // Send button
        IconButton(
          icon: Icon(Icons.send, color: theme.colorScheme.primary),
          onPressed: _send,
          tooltip: 'Send',
        ),
      ],
    );
  }
}

enum _RecorderState {
  idle,
  recording,
  preview,
}

/// Animated recording indicator (pulsing red dot)
class _AnimatedRecordingDot extends StatefulWidget {
  @override
  State<_AnimatedRecordingDot> createState() => _AnimatedRecordingDotState();
}

class _AnimatedRecordingDotState extends State<_AnimatedRecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(_animation.value),
          ),
        );
      },
    );
  }
}
