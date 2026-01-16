/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/material.dart';
import '../models/video.dart';

/// YouTube-style video card with large thumbnail
class VideoTileWidget extends StatelessWidget {
  final Video video;
  final bool isSelected;
  final VoidCallback onTap;
  final String langCode;

  const VideoTileWidget({
    super.key,
    required this.video,
    required this.onTap,
    this.isSelected = false,
    this.langCode = 'EN',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail section (16:9 aspect ratio)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Thumbnail image
                  _buildThumbnail(theme),
                  // Duration badge
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _buildDurationBadge(theme),
                  ),
                  // Visibility badge (if not public)
                  if (!video.isPublic)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _buildVisibilityBadge(theme),
                    ),
                ],
              ),
            ),
            // Video info section - compact layout
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    video.getTitle(langCode),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Author, date and category row
                  Row(
                    children: [
                      // Author avatar placeholder
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          video.author.isNotEmpty
                              ? video.author[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Author name and date
                      Expanded(
                        child: Text(
                          '${video.author} • ${video.displayDate}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Category chip inline
                      if (video.category.displayName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(video.category)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            video.category.displayName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _getCategoryColor(video.category),
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme) {
    if (video.thumbnailPath != null && video.thumbnailPath!.isNotEmpty) {
      return Image.file(
        File(video.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(theme),
      );
    }
    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildDurationBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        video.formattedDuration,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildVisibilityBadge(ThemeData theme) {
    IconData icon;
    Color color;

    switch (video.visibility) {
      case VideoVisibility.private:
        icon = Icons.lock;
        color = Colors.red;
        break;
      case VideoVisibility.unlisted:
        icon = Icons.link_off;
        color = Colors.orange;
        break;
      case VideoVisibility.restricted:
        icon = Icons.group;
        color = Colors.blue;
        break;
      default:
        icon = Icons.public;
        color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Color _getCategoryColor(VideoCategory category) {
    switch (category) {
      case VideoCategory.entertainment:
      case VideoCategory.comedy:
      case VideoCategory.gaming:
        return Colors.purple;
      case VideoCategory.music:
        return Colors.pink;
      case VideoCategory.education:
      case VideoCategory.tutorial:
      case VideoCategory.course:
      case VideoCategory.lecture:
      case VideoCategory.science:
      case VideoCategory.history:
      case VideoCategory.language:
        return Colors.blue;
      case VideoCategory.documentary:
        return Colors.teal;
      case VideoCategory.travel:
        return Colors.green;
      case VideoCategory.food:
        return Colors.orange;
      case VideoCategory.fitness:
        return Colors.red;
      case VideoCategory.tech:
      case VideoCategory.programming:
      case VideoCategory.hardware:
      case VideoCategory.gadgets:
      case VideoCategory.apps:
      case VideoCategory.ai:
        return Colors.indigo;
      case VideoCategory.news:
      case VideoCategory.politics:
      case VideoCategory.business:
        return Colors.blueGrey;
      case VideoCategory.sports:
        return Colors.amber;
      case VideoCategory.vlog:
      case VideoCategory.family:
      case VideoCategory.events:
      case VideoCategory.memories:
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
}
