/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Newsgroup Tile Widget - Displays a subscription entry
 */

import 'package:flutter/material.dart';

import '../../models/nntp_subscription.dart';

/// Tile widget for displaying a newsgroup subscription
class NewsgroupTile extends StatelessWidget {
  final NNTPSubscription subscription;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  const NewsgroupTile({
    super.key,
    required this.subscription,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = subscription.hasUnread;

    // Format group name with hierarchy
    final parts = subscription.groupName.split('.');
    final shortName = parts.length > 2
        ? '${parts.sublist(0, 2).join('.')}.${parts.last}'
        : subscription.groupName;

    return ListTile(
      selected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.forum,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          if (hasUnread)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  subscription.unreadCount > 99
                      ? '99+'
                      : subscription.unreadCount.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onError,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        subscription.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (subscription.lastSyncedAt != null)
            Text(
              _formatSyncTime(subscription.lastSyncedAt!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${subscription.estimatedCount}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (!subscription.postingAllowed)
            Icon(
              Icons.lock,
              size: 14,
              color: theme.colorScheme.outline,
            ),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.month}/${time.day}';
  }
}
