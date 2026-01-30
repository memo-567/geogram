/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Article Tile Widget - Displays an article overview entry
 */

import 'package:flutter/material.dart';
import 'package:nntp/nntp.dart';

import '../utils/article_format.dart';

/// Tile widget for displaying an article overview entry
class ArticleTile extends StatelessWidget {
  final OverviewEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isRead;

  const ArticleTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isRead = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorName = ArticleFormat.extractAuthorName(entry.from);
    final dateStr = entry.date != null
        ? ArticleFormat.formatDate(entry.date!)
        : entry.dateString;

    return ListTile(
      selected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          authorName.isNotEmpty ? authorName.substring(0, 1).toUpperCase() : '?',
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        entry.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          color: isRead
              ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
              : theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Text(
            dateStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: entry.references != null
          ? Icon(
              Icons.reply,
              size: 16,
              color: theme.colorScheme.outline,
            )
          : null,
    );
  }
}
