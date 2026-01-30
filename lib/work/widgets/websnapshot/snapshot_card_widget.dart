/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../../services/i18n_service.dart';
import '../../models/websnapshot_content.dart';

/// Card widget displaying a web snapshot
class SnapshotCardWidget extends StatelessWidget {
  final WebSnapshot snapshot;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const SnapshotCardWidget({
    super.key,
    required this.snapshot,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();

    final statusColor = _getStatusColor(snapshot.status, theme);
    final statusIcon = _getStatusIcon(snapshot.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: snapshot.status == CrawlStatus.complete ? onView : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title and status
              Row(
                children: [
                  Icon(
                    statusIcon,
                    color: statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snapshot.title ?? snapshot.url,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      if (action == 'view') {
                        onView();
                      } else if (action == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      if (snapshot.status == CrawlStatus.complete)
                        PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              const Icon(Icons.open_in_browser),
                              const SizedBox(width: 8),
                              Text(i18n.t('work_websnapshot_view')),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                color: theme.colorScheme.error),
                            const SizedBox(width: 8),
                            Text(
                              i18n.t('delete'),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // URL
              const SizedBox(height: 4),
              Text(
                snapshot.url,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Description if available
              if (snapshot.description != null &&
                  snapshot.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot.description!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Stats row
              const SizedBox(height: 12),
              Row(
                children: [
                  // Date
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(snapshot.capturedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Pages
                  if (snapshot.pageCount > 0) ...[
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      i18n.t('work_websnapshot_pages')
                          .replaceAll('{count}', snapshot.pageCount.toString()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  // Assets
                  if (snapshot.assetCount > 0) ...[
                    Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      i18n.t('work_websnapshot_assets')
                          .replaceAll('{count}', snapshot.assetCount.toString()),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  // Size
                  if (snapshot.totalSizeBytes > 0) ...[
                    Icon(
                      Icons.data_usage,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      snapshot.sizeFormatted,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),

              // Error message if failed
              if (snapshot.status == CrawlStatus.failed &&
                  snapshot.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          snapshot.error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(CrawlStatus status, ThemeData theme) {
    switch (status) {
      case CrawlStatus.pending:
        return theme.colorScheme.onSurfaceVariant;
      case CrawlStatus.crawling:
        return theme.colorScheme.primary;
      case CrawlStatus.complete:
        return Colors.green;
      case CrawlStatus.failed:
        return theme.colorScheme.error;
    }
  }

  IconData _getStatusIcon(CrawlStatus status) {
    switch (status) {
      case CrawlStatus.pending:
        return Icons.schedule;
      case CrawlStatus.crawling:
        return Icons.sync;
      case CrawlStatus.complete:
        return Icons.check_circle_outline;
      case CrawlStatus.failed:
        return Icons.error_outline;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes < 1) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    return '${date.day}/${date.month}/${date.year}';
  }
}
