/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'package:flutter/material.dart';

import '../../../services/audio_service.dart';

/// Audio player widget for playing voice memo clips
class VoiceMemoPlayerWidget extends StatefulWidget {
  /// Path to the audio file to play
  final String audioPath;

  /// Total duration of the clip in milliseconds
  final int durationMs;

  /// Whether to auto-play when the widget is created
  final bool autoPlay;

  /// Called when playback completes
  final VoidCallback? onComplete;

  const VoiceMemoPlayerWidget({
    super.key,
    required this.audioPath,
    required this.durationMs,
    this.autoPlay = false,
    this.onComplete,
  });

  @override
  State<VoiceMemoPlayerWidget> createState() => _VoiceMemoPlayerWidgetState();
}

class _VoiceMemoPlayerWidgetState extends State<VoiceMemoPlayerWidget> {
  final AudioService _audioService = AudioService();

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = true;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _audioService.initialize();

      _positionSubscription = _audioService.positionStream.listen((position) {
        if (!mounted) return;
        setState(() {
          _position = position;
        });

        // Check if playback completed
        if (_duration > Duration.zero &&
            position >= _duration - const Duration(milliseconds: 100)) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
          widget.onComplete?.call();
        }
      });

      _playingSubscription = _audioService.playingStream.listen((playing) {
        if (!mounted) return;
        setState(() {
          _isPlaying = playing;
        });
      });

      // Load the audio
      final duration = await _audioService.load(widget.audioPath);
      if (mounted) {
        setState(() {
          _duration = duration ?? Duration(milliseconds: widget.durationMs);
          _isLoading = false;
        });

        if (widget.autoPlay) {
          await _audioService.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioService.pause();
    } else {
      // If at the end, seek to start
      if (_position >= _duration - const Duration(milliseconds: 100)) {
        await _audioService.seek(Duration.zero);
        setState(() {
          _position = Duration.zero;
        });
      }
      await _audioService.play();
    }
  }

  Future<void> _seek(double value) async {
    final position = Duration(milliseconds: (value * _duration.inMilliseconds).round());
    await _audioService.seek(position);
    setState(() {
      _position = position;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading...'),
          ],
        ),
      );
    }

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Play/Pause button
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: theme.colorScheme.primary,
            ),
            onPressed: _togglePlayback,
            tooltip: _isPlaying ? 'Pause' : 'Play',
          ),

          // Progress bar
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: _seek,
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.surfaceContainerLowest,
                  ),
                ),
              ],
            ),
          ),

          // Duration display
          SizedBox(
            width: 70,
            child: Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
