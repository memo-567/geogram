/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/video.dart';
import '../services/i18n_service.dart';
import '../pages/location_picker_page.dart';
import 'video_player_widget.dart';

/// Widget for displaying video detail with player and metadata
class VideoDetailWidget extends StatefulWidget {
  final Video video;
  final String collectionPath;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? stationUrl;
  final String? profileIdentifier;
  final void Function(String tag)? onTagTap;
  final String langCode;

  // Feedback callbacks
  final VoidCallback? onLike;
  final VoidCallback? onPoint;
  final VoidCallback? onDislike;
  final VoidCallback? onSubscribe;
  final void Function(String emoji)? onReaction;

  const VideoDetailWidget({
    Key? key,
    required this.video,
    required this.collectionPath,
    this.canEdit = false,
    this.onEdit,
    this.onDelete,
    this.stationUrl,
    this.profileIdentifier,
    this.onTagTap,
    this.langCode = 'EN',
    this.onLike,
    this.onPoint,
    this.onDislike,
    this.onSubscribe,
    this.onReaction,
  }) : super(key: key);

  /// Get shareable URL for this video
  String? get shareableUrl {
    if (stationUrl == null || profileIdentifier == null || !video.isPublic) {
      return null;
    }
    final httpUrl = stationUrl!
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
    return '$httpUrl/$profileIdentifier/videos/${video.id}';
  }

  @override
  State<VideoDetailWidget> createState() => _VideoDetailWidgetState();
}

class _VideoDetailWidgetState extends State<VideoDetailWidget> {
  bool _isPlayerExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();
    final video = widget.video;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video player section
        _buildPlayerSection(theme),
        const SizedBox(height: 16),

        // Header with title and actions
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    video.getTitle(widget.langCode),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Metadata row
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      // Author
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            video.author,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      // Date
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${video.displayDate} ${video.displayTime}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      // Views
                      if (video.viewsCount > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${video.viewsCount} ${i18n.t('views')}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      // Location
                      if (video.hasLocation)
                        InkWell(
                          onTap: () => _openLocationOnMap(context),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${video.latitude!.toStringAsFixed(4)}, ${video.longitude!.toStringAsFixed(4)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Visibility badge
                      _buildVisibilityBadge(theme, i18n),
                      // Category badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          video.category.displayName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Action buttons
            if (widget.canEdit) ...[
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: widget.onEdit,
                tooltip: i18n.t('edit'),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: widget.onDelete,
                tooltip: i18n.t('delete'),
                color: theme.colorScheme.error,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Technical metadata
        _buildTechnicalMetadata(theme, i18n),
        const SizedBox(height: 16),

        // Description
        if (video.getDescription(widget.langCode).isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              video.getDescription(widget.langCode),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Tags
        if (video.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: video.tags.map((tag) {
              return ActionChip(
                label: Text('#$tag'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: theme.colorScheme.surfaceVariant,
                onPressed: widget.onTagTap != null ? () => widget.onTagTap!(tag) : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        const Divider(),
        const SizedBox(height: 16),

        // Feedback bar
        if (video.isPublic) ...[
          _buildFeedbackBar(context, theme),
          const SizedBox(height: 16),
        ],

        // Signature indicator
        if (video.isSigned) ...[
          Row(
            children: [
              Icon(
                Icons.verified,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
              Text(
                i18n.t('signed_with_nostr'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Shareable URL
        if (widget.shareableUrl != null) ...[
          _buildShareableUrl(theme, i18n),
        ],
      ],
    );
  }

  Widget _buildPlayerSection(ThemeData theme) {
    final video = widget.video;

    if (!video.isLocal || video.videoFilePath == null) {
      // Remote video - show preview only
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: VideoPreviewWidget(
          thumbnailPath: video.thumbnailPath,
          formattedDuration: video.formattedDuration,
          onPlay: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Remote playback not available yet')),
            );
          },
        ),
      );
    }

    // Local video - show player or preview
    if (_isPlayerExpanded) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: VideoPlayerWidget(
          videoPath: video.videoFilePath!,
          autoPlay: true,
          showControls: true,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: VideoPreviewWidget(
        thumbnailPath: video.thumbnailPath,
        formattedDuration: video.formattedDuration,
        onPlay: () {
          setState(() {
            _isPlayerExpanded = true;
          });
        },
      ),
    );
  }

  Widget _buildTechnicalMetadata(ThemeData theme, I18nService i18n) {
    final video = widget.video;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _buildMetadataItem(theme, Icons.timelapse, i18n.t('duration'), video.formattedDuration),
          _buildMetadataItem(theme, Icons.aspect_ratio, i18n.t('resolution'), video.resolution),
          _buildMetadataItem(theme, Icons.storage, i18n.t('size'), video.formattedFileSize),
          _buildMetadataItem(theme, Icons.video_file, i18n.t('format'), video.mimeType.split('/').last.toUpperCase()),
        ],
      ),
    );
  }

  Widget _buildMetadataItem(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilityBadge(ThemeData theme, I18nService i18n) {
    final video = widget.video;
    IconData icon;
    Color color;
    String label;

    switch (video.visibility) {
      case VideoVisibility.private:
        icon = Icons.lock;
        color = theme.colorScheme.error;
        label = i18n.t('private');
        break;
      case VideoVisibility.unlisted:
        icon = Icons.link_off;
        color = theme.colorScheme.secondary;
        label = i18n.t('unlisted');
        break;
      case VideoVisibility.restricted:
        icon = Icons.group;
        color = theme.colorScheme.tertiary;
        label = i18n.t('restricted');
        break;
      case VideoVisibility.public:
        icon = Icons.public;
        color = theme.colorScheme.primary;
        label = i18n.t('public');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBar(BuildContext context, ThemeData theme) {
    final video = widget.video;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary feedback actions
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFeedbackButton(
              theme: theme,
              icon: Icons.thumb_up,
              label: 'Like',
              count: video.likesCount,
              isActive: video.hasLiked,
              onPressed: widget.onLike,
              activeColor: Colors.blue,
            ),
            _buildFeedbackButton(
              theme: theme,
              icon: Icons.push_pin,
              label: 'Point',
              count: video.pointsCount,
              isActive: video.hasPointed,
              onPressed: widget.onPoint,
              activeColor: Colors.orange,
            ),
            _buildFeedbackButton(
              theme: theme,
              icon: Icons.thumb_down,
              label: 'Dislike',
              count: video.dislikesCount,
              isActive: video.hasDisliked,
              onPressed: widget.onDislike,
              activeColor: Colors.red,
            ),
            _buildFeedbackButton(
              theme: theme,
              icon: Icons.notifications,
              label: 'Subscribe',
              count: video.subscribeCount,
              isActive: video.hasSubscribed,
              onPressed: widget.onSubscribe,
              activeColor: Colors.green,
            ),
          ],
        ),
        // Emoji reactions
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '❤️',
              count: video.heartCount,
              isActive: video.hasHearted,
              onPressed: () => widget.onReaction?.call('heart'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '👍',
              count: video.thumbsUpCount,
              isActive: video.hasThumbsUp,
              onPressed: () => widget.onReaction?.call('thumbs-up'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '🔥',
              count: video.fireCount,
              isActive: video.hasFired,
              onPressed: () => widget.onReaction?.call('fire'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '🎉',
              count: video.celebrateCount,
              isActive: video.hasCelebrated,
              onPressed: () => widget.onReaction?.call('celebrate'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '😂',
              count: video.laughCount,
              isActive: video.hasLaughed,
              onPressed: () => widget.onReaction?.call('laugh'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '😢',
              count: video.sadCount,
              isActive: video.hasSad,
              onPressed: () => widget.onReaction?.call('sad'),
            ),
            _buildEmojiReactionButton(
              theme: theme,
              emoji: '😲',
              count: video.surpriseCount,
              isActive: video.hasSurprised,
              onPressed: () => widget.onReaction?.call('surprise'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeedbackButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback? onPressed,
    required Color activeColor,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 18,
        color: isActive ? activeColor : theme.colorScheme.onSurfaceVariant,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : theme.colorScheme.onSurface,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? activeColor.withOpacity(0.2) : theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? activeColor : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: isActive ? activeColor : theme.colorScheme.outline,
          width: isActive ? 2 : 1,
        ),
        backgroundColor: isActive ? activeColor.withOpacity(0.1) : null,
      ),
    );
  }

  Widget _buildEmojiReactionButton({
    required ThemeData theme,
    required String emoji,
    required int count,
    required bool isActive,
    required VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
            width: isActive ? 2 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShareableUrl(ThemeData theme, I18nService i18n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.link,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              widget.shareableUrl!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.shareableUrl!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(i18n.t('url_copied')),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: i18n.t('copy_url'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  void _openLocationOnMap(BuildContext context) {
    final video = widget.video;
    final lat = video.latitude;
    final lon = video.longitude;

    if (lat == null || lon == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialPosition: LatLng(lat, lon),
          viewOnly: true,
        ),
      ),
    );
  }
}
