/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/i18n_service.dart';
import '../../models/voicememo_content.dart';
import '../../utils/voicememo_transcription_service.dart';

/// Card widget for displaying a voice memo clip
class VoiceMemoClipCardWidget extends StatelessWidget {
  final VoiceMemoClip clip;
  final bool isExpanded;
  final bool isPlaying;
  final bool isTranscribing;
  final TranscriptionProgress? transcriptionProgress;
  final VoiceMemoSettings settings;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMerge;
  final VoidCallback onTranscribe;
  final VoidCallback? onCancelTranscription;
  final VoidCallback? onDeleteTranscription;

  const VoiceMemoClipCardWidget({
    super.key,
    required this.clip,
    required this.isExpanded,
    required this.isPlaying,
    this.isTranscribing = false,
    this.transcriptionProgress,
    required this.settings,
    required this.onToggleExpanded,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
    required this.onMerge,
    required this.onTranscribe,
    this.onCancelTranscription,
    this.onDeleteTranscription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row - always visible
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Play button
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.stop : Icons.play_arrow,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: onPlay,
                    tooltip: isPlaying ? i18n.t('stop') : i18n.t('play'),
                  ),

                  const SizedBox(width: 8),

                  // Title and duration
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                clip.title,
                                style: theme.textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Compact transcription indicator (visible when collapsed)
                            if (isTranscribing) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                i18n.t('work_voicememo_transcribing'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              clip.durationFormatted,
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
                              dateFormat.format(clip.recordedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand/collapse icon
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  if (clip.description != null && clip.description!.isNotEmpty) ...[
                    Text(
                      clip.description!,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Transcription
                  if (clip.transcription != null && settings.showTranscriptions) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.text_snippet_outlined,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  i18n.t('work_voicememo_transcription'),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              // Re-transcribe button
                              if (onDeleteTranscription != null && !isTranscribing)
                                IconButton(
                                  icon: Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  onPressed: onDeleteTranscription,
                                  tooltip: i18n.t('work_voicememo_retranscribe'),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            clip.transcription!.text,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Merged from indicator
                  if (clip.mergedFrom != null && clip.mergedFrom!.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.merge_type,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Merged from ${clip.mergedFrom!.length} clips',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Social data (ratings)
                  if (settings.allowRatings) ...[
                    _buildSocialData(context, theme),
                    const SizedBox(height: 12),
                  ],

                  // Transcription progress (when transcribing)
                  if (isTranscribing && clip.transcription == null) ...[
                    _buildTranscriptionProgress(context, theme, i18n),
                    const SizedBox(height: 12),
                  ],

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (clip.transcription == null && !isTranscribing)
                        TextButton.icon(
                          onPressed: onTranscribe,
                          icon: const Icon(Icons.text_snippet_outlined, size: 18),
                          label: Text(i18n.t('work_voicememo_transcribe')),
                        ),
                      TextButton.icon(
                        onPressed: onMerge,
                        icon: const Icon(Icons.merge_type, size: 18),
                        label: Text(i18n.t('work_voicememo_merge')),
                      ),
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(i18n.t('edit')),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                        label: Text(
                          i18n.t('delete'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSocialData(BuildContext context, ThemeData theme) {
    final social = clip.social;

    return Row(
      children: [
        // Stars rating
        if (settings.ratingType == RatingType.stars ||
            settings.ratingType == RatingType.both) ...[
          Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            social.starsCount > 0
                ? '${social.averageStars.toStringAsFixed(1)} (${social.starsCount})'
                : '-',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 16),
        ],

        // Like/Dislike
        if (settings.ratingType == RatingType.likeDislike ||
            settings.ratingType == RatingType.both) ...[
          Icon(Icons.thumb_up_outlined, size: 16, color: Colors.green),
          const SizedBox(width: 4),
          Text('${social.likes}', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Icon(Icons.thumb_down_outlined, size: 16, color: Colors.red),
          const SizedBox(width: 4),
          Text('${social.dislikes}', style: theme.textTheme.bodySmall),
          const SizedBox(width: 16),
        ],

        // Comments count
        if (settings.allowComments) ...[
          Icon(Icons.comment_outlined, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text('${social.commentIds.length}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _buildTranscriptionProgress(
      BuildContext context, ThemeData theme, I18nService i18n) {
    final p = transcriptionProgress;
    final state = p?.state ?? TranscriptionState.preparing;
    final progressValue = p?.progress ?? 0.0;

    // Determine stage info
    String stageTitle;
    String? stageDetail;
    bool showProgressBar = false;

    switch (state) {
      case TranscriptionState.preparing:
        stageTitle = i18n.t('work_voicememo_checking_model');
        break;
      case TranscriptionState.downloadingModel:
        stageTitle = i18n.t('work_voicememo_downloading_model');
        if (p != null && p.totalBytes > 0) {
          stageDetail = '${p.downloadProgressString} (${p.progressPercent}%)';
        }
        showProgressBar = true;
        break;
      case TranscriptionState.loadingModel:
        stageTitle = i18n.t('work_voicememo_loading_model');
        stageDetail = p?.modelName;
        showProgressBar = true;
        break;
      case TranscriptionState.convertingAudio:
        stageTitle = i18n.t('work_voicememo_converting_audio');
        break;
      case TranscriptionState.transcribing:
        stageTitle = i18n.t('work_voicememo_transcribing');
        stageDetail = p?.modelName;
        break;
      case TranscriptionState.cancelling:
        stageTitle = i18n.t('cancelling');
        break;
      default:
        stageTitle = i18n.t('work_voicememo_transcribing');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with stage title and cancel button
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: state == TranscriptionState.downloadingModel && progressValue > 0
                      ? progressValue
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (stageDetail != null)
                      Text(
                        stageDetail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (state != TranscriptionState.cancelling &&
                  onCancelTranscription != null)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onCancelTranscription,
                  tooltip: i18n.t('cancel'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),

          // Progress bar for download/loading stages
          if (showProgressBar && progressValue > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 6,
                backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
