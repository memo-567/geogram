/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/i18n_service.dart';
import '../../models/voicememo_content.dart';

/// Card widget for displaying a voice memo clip
class VoiceMemoClipCardWidget extends StatelessWidget {
  final VoiceMemoClip clip;
  final bool isExpanded;
  final bool isPlaying;
  final bool isTranscribing;
  final VoiceMemoSettings settings;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMerge;
  final VoidCallback onTranscribe;

  const VoiceMemoClipCardWidget({
    super.key,
    required this.clip,
    required this.isExpanded,
    required this.isPlaying,
    this.isTranscribing = false,
    required this.settings,
    required this.onToggleExpanded,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
    required this.onMerge,
    required this.onTranscribe,
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
                        Text(
                          clip.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                              Text(
                                i18n.t('work_voicememo_transcription'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
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

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (clip.transcription == null)
                        TextButton.icon(
                          onPressed: isTranscribing ? null : onTranscribe,
                          icon: isTranscribing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.text_snippet_outlined, size: 18),
                          label: Text(isTranscribing
                              ? i18n.t('work_voicememo_transcribing')
                              : i18n.t('work_voicememo_transcribe')),
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
}
