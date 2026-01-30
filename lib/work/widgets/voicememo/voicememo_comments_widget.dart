/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/i18n_service.dart';
import '../../../util/comment_utils.dart';

/// Comments widget for voice memo clips
///
/// Displays a list of NOSTR-signed comments with options to add new comments.
class VoiceMemoCommentsWidget extends StatelessWidget {
  /// List of comments to display
  final List<SignedComment> comments;

  /// Whether commenting is enabled
  final bool enabled;

  /// Called when user wants to add a comment
  final VoidCallback? onAddComment;

  /// Called when user wants to delete a comment
  final void Function(String commentId)? onDeleteComment;

  /// Current user's npub (to determine which comments can be deleted)
  final String? currentUserNpub;

  const VoiceMemoCommentsWidget({
    super.key,
    required this.comments,
    this.enabled = true,
    this.onAddComment,
    this.onDeleteComment,
    this.currentUserNpub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              Icons.comment_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '${i18n.t('work_voicememo_comments')} (${comments.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            if (enabled && onAddComment != null)
              TextButton.icon(
                onPressed: onAddComment,
                icon: const Icon(Icons.add, size: 18),
                label: Text(i18n.t('work_voicememo_add_comment')),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // Comments list
        if (comments.isEmpty)
          Text(
            i18n.t('work_voicememo_no_comments'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...comments.map((comment) => _CommentTile(
                comment: comment,
                canDelete: currentUserNpub != null &&
                    comment.npub == currentUserNpub &&
                    onDeleteComment != null,
                onDelete: onDeleteComment != null
                    ? () => onDeleteComment!(comment.id)
                    : null,
              )),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final SignedComment comment;
  final bool canDelete;
  final VoidCallback? onDelete;

  const _CommentTile({
    required this.comment,
    required this.canDelete,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd().add_jm();

    DateTime? parsedDate;
    try {
      if (comment.createdAt != null) {
        parsedDate = DateTime.fromMillisecondsSinceEpoch(comment.createdAt! * 1000);
      } else if (comment.created.isNotEmpty) {
        // Try parsing the created string
        final parts = comment.created.split(' ');
        if (parts.length >= 2) {
          parsedDate = DateTime.tryParse('${parts[0]}T${parts[1].replaceAll('_', ':')}');
        }
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: author, date, verified badge
          Row(
            children: [
              // Author
              Text(
                comment.author,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),

              // Verified badge
              if (comment.verified) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.verified,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ],

              const Spacer(),

              // Date
              if (parsedDate != null)
                Text(
                  dateFormat.format(parsedDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

              // Delete button
              if (canDelete)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Content
          Text(
            comment.content,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding a new comment
class AddCommentDialog extends StatefulWidget {
  final String clipTitle;

  const AddCommentDialog({
    super.key,
    required this.clipTitle,
  });

  @override
  State<AddCommentDialog> createState() => _AddCommentDialogState();
}

class _AddCommentDialogState extends State<AddCommentDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService();

    return AlertDialog(
      title: Text(i18n.t('work_voicememo_add_comment')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comment on "${widget.clipTitle}"',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: 'Write your comment...',
              border: const OutlineInputBorder(),
            ),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_controller.text.trim().isNotEmpty) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: Text(i18n.t('save')),
        ),
      ],
    );
  }
}
