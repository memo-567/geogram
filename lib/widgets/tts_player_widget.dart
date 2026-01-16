/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tts/models/tts_model_info.dart';
import '../tts/services/tts_service.dart';

/// A reusable widget for text-to-speech playback.
///
/// Automatically uses the app's selected language (English or Portuguese).
/// The TTS model downloads automatically from the station server on first use.
///
/// Example usage:
/// ```dart
/// // Simple - shows play button
/// TtsPlayerWidget(text: 'Hello, welcome to Geogram!')
///
/// // Auto-play notification
/// TtsPlayerWidget(
///   text: notification.message,
///   autoPlay: true,
///   showControls: false,
/// )
///
/// // Custom trigger with male voice
/// TtsPlayerWidget(
///   text: article.content,
///   voice: TtsVoice.m4,
///   child: IconButton(
///     icon: Icon(Icons.volume_up),
///     onPressed: null,
///   ),
/// )
/// ```
class TtsPlayerWidget extends StatefulWidget {
  /// Text to synthesize and speak
  final String text;

  /// Play immediately when widget mounts
  final bool autoPlay;

  /// Show play/loading controls
  final bool showControls;

  /// Voice to use (default: female voice 3)
  final TtsVoice voice;

  /// Callback when audio is generated (before playing)
  final void Function(Float32List samples)? onAudioGenerated;

  /// Custom child widget (tapping it triggers playback)
  final Widget? child;

  /// Icon size for default controls
  final double iconSize;

  /// Color for the icon
  final Color? iconColor;

  const TtsPlayerWidget({
    super.key,
    required this.text,
    this.autoPlay = false,
    this.showControls = true,
    this.voice = TtsVoice.f3,
    this.onAudioGenerated,
    this.child,
    this.iconSize = 24.0,
    this.iconColor,
  });

  @override
  State<TtsPlayerWidget> createState() => _TtsPlayerWidgetState();
}

class _TtsPlayerWidgetState extends State<TtsPlayerWidget> {
  final TtsService _tts = TtsService();

  bool _isLoading = false;
  bool _isPlaying = false;
  double _loadProgress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(TtsPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-play when text changes if autoPlay is enabled
    if (widget.autoPlay && widget.text != oldWidget.text) {
      _play();
    }
  }

  Future<void> _play() async {
    if (_isLoading || _isPlaying || widget.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load model if needed
      if (!_tts.isLoaded) {
        await for (final progress in _tts.load()) {
          if (mounted) {
            setState(() => _loadProgress = progress);
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isPlaying = true;
      });

      // Synthesize and play
      final samples = await _tts.synthesize(widget.text, voice: widget.voice);

      if (samples != null && samples.isNotEmpty) {
        widget.onAudioGenerated?.call(samples);
        await _tts.speak(widget.text, voice: widget.voice);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Custom child - wrap with tap handler
    if (widget.child != null) {
      return GestureDetector(
        onTap: _isLoading || _isPlaying ? null : _play,
        child: widget.child,
      );
    }

    // No controls - invisible widget (for autoPlay only scenarios)
    if (!widget.showControls) {
      return const SizedBox.shrink();
    }

    // Default controls
    final color = widget.iconColor ?? Theme.of(context).iconTheme.color;

    if (_isLoading) {
      return SizedBox(
        width: widget.iconSize,
        height: widget.iconSize,
        child: _loadProgress > 0 && _loadProgress < 1
            ? CircularProgressIndicator(
                value: _loadProgress,
                strokeWidth: 2,
                color: color,
              )
            : CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
      );
    }

    if (_error != null) {
      return Tooltip(
        message: _error!,
        child: Icon(
          Icons.error_outline,
          size: widget.iconSize,
          color: Colors.red,
        ),
      );
    }

    return IconButton(
      onPressed: _isPlaying ? null : _play,
      icon: Icon(
        _isPlaying ? Icons.volume_up : Icons.volume_up_outlined,
        size: widget.iconSize,
        color: _isPlaying ? color?.withValues(alpha: 0.5) : color,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: widget.iconSize,
        minHeight: widget.iconSize,
      ),
      tooltip: 'Speak',
    );
  }
}
