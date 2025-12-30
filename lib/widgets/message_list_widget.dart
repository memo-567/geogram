/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'message_bubble_widget.dart';

/// Widget for displaying a scrollable list of chat messages
class MessageListWidget extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isGroupChat;
  final VoidCallback? onLoadMore;
  final bool isLoading;
  final Function(ChatMessage)? onFileOpen;
  final Function(ChatMessage)? onMessageDelete;
  final bool Function(ChatMessage)? canDeleteMessage;
  final Function(ChatMessage)? onMessageQuote;
  final Function(ChatMessage)? onMessageHide;
  final bool Function(ChatMessage)? isMessageHidden;
  final Function(ChatMessage)? onMessageUnhide;
  final Future<String?> Function(ChatMessage)? getAttachmentPath;
  final Function(ChatMessage)? onImageOpen;
  final void Function(ChatMessage, String)? onMessageReact;
  /// Callback to get voice file path for a message
  final Future<String?> Function(ChatMessage)? getVoiceFilePath;

  const MessageListWidget({
    Key? key,
    required this.messages,
    this.isGroupChat = true,
    this.onLoadMore,
    this.isLoading = false,
    this.onFileOpen,
    this.onMessageDelete,
    this.canDeleteMessage,
    this.onMessageQuote,
    this.onMessageHide,
    this.isMessageHidden,
    this.onMessageUnhide,
    this.getAttachmentPath,
    this.onImageOpen,
    this.onMessageReact,
    this.getVoiceFilePath,
  }) : super(key: key);

  @override
  State<MessageListWidget> createState() => _MessageListWidgetState();
}

class _MessageListWidgetState extends State<MessageListWidget> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _lastMessageCount = widget.messages.length;

    // Auto-scroll to bottom on first load
    _requestScrollToBottom(animate: false);
  }

  @override
  void didUpdateWidget(MessageListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCount = _lastMessageCount;
    _lastMessageCount = widget.messages.length;

    // Scroll to bottom when messages are added (if autoScroll is enabled)
    if (widget.messages.length > oldCount && _autoScroll) {
      _requestScrollToBottom(animate: oldCount > 0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Request a scroll to bottom, retrying until the scroll controller is ready
  void _requestScrollToBottom({bool animate = true, int attempts = 0}) {
    if (!mounted || attempts > 10) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
        _scrollToBottom(animate: animate);
      } else {
        // Controller not ready yet, retry
        _requestScrollToBottom(animate: animate, attempts: attempts + 1);
      }
    });
  }

  /// Called when a message's content size changes (e.g., image loaded)
  void _onContentSizeChanged() {
    if (_autoScroll && mounted) {
      _requestScrollToBottom(animate: false);
    }
  }

  /// Listen for scroll events
  void _scrollListener() {
    // Check if at bottom (within 100 pixels)
    if (_scrollController.hasClients) {
      final atBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 100;
      if (_autoScroll != atBottom) {
        setState(() {
          _autoScroll = atBottom;
        });
      }

      // Load more when scrolling near top
      if (_scrollController.position.pixels <= 100 &&
          widget.onLoadMore != null &&
          !widget.isLoading) {
        widget.onLoadMore!();
      }
    }
  }

  /// Scroll to bottom of list
  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    if (animate) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _buildItems();

    return Stack(
      children: [
        // Message list
        widget.messages.isEmpty
            ? _buildEmptyState(theme)
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: items.length + (widget.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  // Loading indicator at top
                  if (widget.isLoading && index == 0) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }

                  // Message bubble
                  final messageIndex = widget.isLoading ? index - 1 : index;
                  final item = items[messageIndex];

                  if (item.isSeparator) {
                    return _buildDateSeparator(theme, item.label ?? '');
                  }

                  final message = item.message!;

                  return MessageBubbleWidget(
                    key: ValueKey(message.timestamp + message.author),
                    message: message,
                    isGroupChat: widget.isGroupChat,
                    onFileOpen: widget.onFileOpen != null
                        ? () => widget.onFileOpen!(message)
                        : null,
                    onDelete: widget.onMessageDelete != null
                        ? () => widget.onMessageDelete!(message)
                        : null,
                    canDelete: widget.canDeleteMessage != null
                        ? widget.canDeleteMessage!(message)
                        : false,
                    onQuote: widget.onMessageQuote != null
                        ? () => widget.onMessageQuote!(message)
                        : null,
                    onHide: widget.onMessageHide != null
                        ? () => widget.onMessageHide!(message)
                        : null,
                    isHidden: widget.isMessageHidden != null
                        ? widget.isMessageHidden!(message)
                        : false,
                    onUnhide: widget.onMessageUnhide != null
                        ? () => widget.onMessageUnhide!(message)
                        : null,
                    onAttachmentPathRequested: widget.getAttachmentPath != null && message.hasFile
                        ? () => widget.getAttachmentPath!(message)
                        : null,
                    onImageOpen: widget.onImageOpen != null
                        ? () => widget.onImageOpen!(message)
                        : null,
                    onReact: widget.onMessageReact != null
                        ? (reaction) => widget.onMessageReact!(message, reaction)
                        : null,
                    // Voice message support
                    onVoiceDownloadRequested: widget.getVoiceFilePath != null && message.hasVoice
                        ? () => widget.getVoiceFilePath!(message)
                        : null,
                    // Scroll to bottom when image loads
                    onContentSizeChanged: _autoScroll ? _onContentSizeChanged : null,
                  );
                },
              ),
        // Scroll to bottom button
        if (!_autoScroll)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () => _scrollToBottom(),
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.arrow_downward,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
      ],
    );
  }

  /// Build empty state widget
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  List<_MessageListItem> _buildItems() {
    final items = <_MessageListItem>[];
    String? lastDate;

    for (final message in widget.messages) {
      final date = message.datePortion;
      if (date != lastDate) {
        lastDate = date;
        items.add(_MessageListItem.separator(_formatDateLabel(message.dateTime)));
      }
      items.add(_MessageListItem.message(message));
    }

    return items;
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);
    final difference = msgDate.difference(today).inDays;

    if (difference == 0) return 'Today';
    if (difference == -1) return 'Yesterday';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildDateSeparator(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageListItem {
  final ChatMessage? message;
  final String? label;

  bool get isSeparator => label != null;

  _MessageListItem.message(this.message) : label = null;
  _MessageListItem.separator(this.label) : message = null;
}
