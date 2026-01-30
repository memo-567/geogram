/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../services/i18n_service.dart';
import '../../models/voicememo_content.dart';

/// Transcription display widget for voice memo clips
///
/// Shows the transcription text with metadata and actions.
class VoiceMemoTranscriptionWidget extends StatelessWidget {
  /// The transcription data
  final ClipTranscription? transcription;

  /// Whether transcription is currently in progress
  final bool isTranscribing;

  /// Called when user wants to start transcription
  final VoidCallback? onTranscribe;

  /// Called when user wants to re-transcribe
  final VoidCallback? onRetranscribe;

  const VoiceMemoTranscriptionWidget({
    super.key,
    this.transcription,
    this.isTranscribing = false,
    this.onTranscribe,
    this.onRetranscribe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();

    // Show loading state
    if (isTranscribing) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              i18n.t('work_voicememo_transcribing'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Show transcribe button if no transcription
    if (transcription == null) {
      return OutlinedButton.icon(
        onPressed: onTranscribe,
        icon: const Icon(Icons.text_snippet_outlined, size: 18),
        label: Text(i18n.t('work_voicememo_transcribe')),
      );
    }

    // Show transcription
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.text_snippet_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                i18n.t('work_voicememo_transcription'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Copy button
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => _copyToClipboard(context, transcription!.text),
                tooltip: 'Copy',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              // Re-transcribe button
              if (onRetranscribe != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: onRetranscribe,
                  tooltip: 'Re-transcribe',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Transcription text
          SelectableText(
            transcription!.text,
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: 12),

          // Metadata
          Row(
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                transcription!.model,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.schedule,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                dateFormat.format(transcription!.transcribedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Compact transcription preview widget
class VoiceMemoTranscriptionPreviewWidget extends StatelessWidget {
  /// The transcription data
  final ClipTranscription transcription;

  /// Maximum number of lines to show
  final int maxLines;

  /// Called when user taps to expand
  final VoidCallback? onTap;

  const VoiceMemoTranscriptionPreviewWidget({
    super.key,
    required this.transcription,
    this.maxLines = 2,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              Icons.text_snippet_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                transcription.text,
                style: theme.textTheme.bodySmall,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
