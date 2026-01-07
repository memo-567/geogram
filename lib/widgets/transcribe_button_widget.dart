/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../bot/services/speech_to_text_service.dart';
import '../services/i18n_service.dart';
import 'transcription_dialog.dart';

/// A reusable voice-to-text button for text fields.
///
/// Shows an audio waveform icon that opens a recording dialog when tapped.
/// Automatically hides on unsupported platforms (Windows, Linux, Web).
///
/// Usage:
/// ```dart
/// TextFormField(
///   controller: _controller,
///   decoration: InputDecoration(
///     labelText: 'Description',
///     suffixIcon: TranscribeButtonWidget(
///       i18n: widget.i18n,
///       onTranscribed: (text) {
///         _controller.text += text;
///       },
///     ),
///   ),
/// )
/// ```
class TranscribeButtonWidget extends StatelessWidget {
  /// Localization service
  final I18nService i18n;

  /// Callback when transcription is complete
  final void Function(String text) onTranscribed;

  /// Whether the button is enabled
  final bool enabled;

  /// Icon size
  final double iconSize;

  const TranscribeButtonWidget({
    super.key,
    required this.i18n,
    required this.onTranscribed,
    this.enabled = true,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    // Hide on unsupported platforms
    if (!SpeechToTextService.isSupported) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: CustomPaint(
        size: Size(iconSize, iconSize),
        painter: _WaveformIconPainter(
          color: enabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
      onPressed: enabled ? () => _showTranscriptionDialog(context) : null,
      tooltip: i18n.t('voice_to_text'),
    );
  }

  Future<void> _showTranscriptionDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TranscriptionDialog(i18n: i18n),
    );

    if (result != null && result.isNotEmpty) {
      onTranscribed(result);
    }
  }
}

/// Custom painter for the waveform icon (similar to ChatGPT's voice icon)
class _WaveformIconPainter extends CustomPainter {
  final Color color;

  _WaveformIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 10
      ..strokeCap = StrokeCap.round;

    // Draw 5 vertical bars of varying heights (audio waveform style)
    const barCount = 5;
    final barWidth = size.width / (barCount * 2 - 1);
    final heights = [0.35, 0.65, 1.0, 0.65, 0.35];

    for (var i = 0; i < barCount; i++) {
      final x = barWidth * (i * 2) + barWidth / 2;
      final barHeight = size.height * heights[i];
      final top = (size.height - barHeight) / 2;

      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
