/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/profile_service.dart';
import '../services/devices_service.dart';
import '../util/reaction_utils.dart';
import 'voice_player_widget.dart';
import '../platform/file_image_helper.dart' as file_helper;

/// Widget for displaying a single chat message bubble
class MessageBubbleWidget extends StatefulWidget {
  static const Map<String, String> reactionEmojiMap = {
    'thumbs-up': '👍',
    'heart': '❤️',
    'fire': '🔥',
    'laugh': '😂',
    'celebrate': '🎉',
    'surprise': '😮',
    'sad': '😢',
  };

  final ChatMessage message;
  final bool isGroupChat;
  final VoidCallback? onFileOpen;
  final VoidCallback? onLocationView;
  final VoidCallback? onDelete;
  final VoidCallback? onQuote;
  final VoidCallback? onHide;
  final bool canDelete;
  final bool isHidden;
  final VoidCallback? onUnhide;
  final VoidCallback? onImageOpen;
  final void Function(String reaction)? onReact;
  /// Path to the voice file (for voice messages)
  final String? voiceFilePath;
  /// Callback to request download of voice file from remote
  final Future<String?> Function()? onVoiceDownloadRequested;
  /// Callback to request attachment file path (async)
  final Future<String?> Function()? onAttachmentPathRequested;
  /// Callback when content size changes (e.g., image loaded)
  final VoidCallback? onContentSizeChanged;

  const MessageBubbleWidget({
    Key? key,
    required this.message,
    this.isGroupChat = true,
    this.onFileOpen,
    this.onLocationView,
    this.onDelete,
    this.onQuote,
    this.onHide,
    this.canDelete = false,
    this.voiceFilePath,
    this.onVoiceDownloadRequested,
    this.isHidden = false,
    this.onUnhide,
    this.onAttachmentPathRequested,
    this.onImageOpen,
    this.onReact,
    this.onContentSizeChanged,
  }) : super(key: key);

  @override
  State<MessageBubbleWidget> createState() => _MessageBubbleWidgetState();
}

class _MessageBubbleWidgetState extends State<MessageBubbleWidget> {
  String? _attachmentPath;
  bool _isLoadingAttachment = false;

  @override
  void initState() {
    super.initState();
    _loadAttachmentPath();
  }

  @override
  void didUpdateWidget(MessageBubbleWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload if the message identity or file attachment actually changed
    // Don't reset if only reactions/metadata changed (preserves image display)
    final oldFile = oldWidget.message.attachedFile;
    final newFile = widget.message.attachedFile;
    final timestampChanged = oldWidget.message.timestamp != widget.message.timestamp;
    final fileChanged = oldFile != newFile;

    if (timestampChanged || fileChanged) {
      _attachmentPath = null;
      _loadAttachmentPath();
    } else if (_attachmentPath == null && widget.message.hasFile && !_isLoadingAttachment) {
      // If we have a file but no path yet, try loading it
      _loadAttachmentPath();
    }
  }

  Future<void> _loadAttachmentPath() async {
    if (widget.onAttachmentPathRequested == null || !widget.message.hasFile) {
      return;
    }
    if (_isLoadingAttachment) return;

    setState(() {
      _isLoadingAttachment = true;
    });

    try {
      final path = await widget.onAttachmentPathRequested!();
      if (mounted) {
        final hadNoPath = _attachmentPath == null;
        setState(() {
          _attachmentPath = path;
          _isLoadingAttachment = false;
        });
        // Notify parent that content size changed (image loaded)
        if (hadNoPath && path != null && widget.onContentSizeChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onContentSizeChanged?.call();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAttachment = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileService = ProfileService();
    final currentProfile = profileService.getProfile();
    final currentCallsign = currentProfile.callsign;
    final normalizedCallsign = currentCallsign.toUpperCase();

    // Compare case-insensitively for callsigns, or by npub if available
    final isOwnMessage = widget.message.author.toUpperCase() == currentCallsign.toUpperCase() ||
        (widget.message.npub != null &&
         widget.message.npub!.isNotEmpty &&
         currentProfile.npub.isNotEmpty &&
         widget.message.npub == currentProfile.npub);

    // Get sender's preferred color from cached device status
    final Color bubbleColor;
    final Color textColor;
    if (isOwnMessage) {
      bubbleColor = theme.colorScheme.primaryContainer;
      textColor = theme.colorScheme.onPrimaryContainer;
    } else {
      final device = DevicesService().getDevice(widget.message.author);
      bubbleColor = _getBubbleColor(device?.preferredColor, theme);
      textColor = _getTextColor(device?.preferredColor, theme);
    }

    final hasActions = (widget.onQuote != null) || (widget.onHide != null) || (widget.canDelete && widget.onDelete != null);
    final isImageAttachment = _isImageAttachment();
    final imageWidget = isImageAttachment && _attachmentPath != null
        ? file_helper.buildFileImage(
            _attachmentPath!,
            width: 280,
            height: 200,
            fit: BoxFit.cover,
          )
        : null;
    final showImagePreview = imageWidget != null;

    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment:
              isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Author name (only for group chats and other people's messages)
            if (widget.isGroupChat && !isOwnMessage)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  widget.message.author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Message bubble
            InkWell(
              onLongPress: () => _showMessageOptions(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isHidden)
                      _buildHiddenMessage(theme, textColor)
                    else ...[
                      if (widget.message.isQuote) _buildQuotePreview(theme),
                      if (showImagePreview)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: widget.onImageOpen ?? widget.onFileOpen,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: imageWidget,
                            ),
                          ),
                        ),
                      // Voice message player (takes priority over text content)
                      if (widget.message.hasVoice)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: VoicePlayerWidget(
                            key: ValueKey('voice_${widget.message.voiceFile}'),
                            filePath: widget.voiceFilePath ?? '',
                            durationSeconds: widget.message.voiceDuration,
                            isLocal: widget.voiceFilePath != null,
                            onDownloadRequested: widget.onVoiceDownloadRequested,
                          ),
                        )
                      // Text message content
                      else if (widget.message.content.isNotEmpty)
                        SelectableText(
                          widget.message.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                          ),
                        ),
                      // Metadata chips (file, location, poll - but NOT signature)
                      if (((!isImageAttachment || !showImagePreview) && widget.message.hasFile) ||
                          widget.message.hasLocation ||
                          widget.message.isPoll)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildMetadataChips(context, theme, isOwnMessage),
                        ),
                    ],
                    // Timestamp, signature icon, and options
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.message.displayTime,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: textColor.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                          // Verified indicator (signature verified by server)
                          if (widget.message.isVerified) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified,
                                    size: 11,
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'verified',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                          // Failed verification (has signature but verification failed - possible spoofing)
                          else if (widget.message.isSigned) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning,
                                    size: 11,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'unverified',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Pending status (queued for offline delivery)
                          if (widget.message.isPending) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 11,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'queued',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]
                          // Failed delivery status
                          else if (widget.message.isFailed) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 11,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'failed',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Options menu button (desktop)
                          if (hasActions && _isDesktopPlatform()) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.more_horiz, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              tooltip: 'Message options',
                              onPressed: () => _showMessageOptions(context),
                              color: textColor.withOpacity(0.7),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.message.reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildReactionsRow(theme, normalizedCallsign),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isImageAttachment() {
    if (!widget.message.hasFile) return false;
    final name = (_attachmentPath ?? widget.message.attachedFile ?? '').toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.bmp');
  }

  bool _isDesktopPlatform() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Widget _buildHiddenMessage(ThemeData theme, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.visibility_off,
          size: 16,
          color: textColor.withOpacity(0.7),
        ),
        const SizedBox(width: 8),
        Text(
          'Message hidden',
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor.withOpacity(0.7),
            fontStyle: FontStyle.italic,
          ),
        ),
        if (widget.onUnhide != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onUnhide,
            child: const Text('Show'),
          ),
        ],
      ],
    );
  }

  Widget _buildQuotePreview(ThemeData theme) {
    final author = widget.message.quotedAuthor ?? 'Unknown';
    final excerpt = widget.message.quotedExcerpt ?? '';
    final display = excerpt.isNotEmpty ? excerpt : 'Quoted message';
    final truncated = display.length > 120 ? '${display.substring(0, 120)}...' : display;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            truncated,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build metadata chips (file, location, etc.)
  Widget _buildMetadataChips(
      BuildContext context, ThemeData theme, bool isOwnMessage) {
    List<Widget> chips = [];

    // File attachment chip
    if (widget.message.hasFile) {
      chips.add(
        ActionChip(
          avatar: Icon(
            Icons.attach_file,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          label: Text(
            widget.message.attachedFile ?? 'File',
            style: theme.textTheme.bodySmall,
          ),
          onPressed: widget.onFileOpen,
          backgroundColor: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    // Location chip
    if (widget.message.hasLocation) {
      chips.add(
        ActionChip(
          avatar: Icon(
            Icons.location_on,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          label: Text(
            '${widget.message.latitude?.toStringAsFixed(4)}, ${widget.message.longitude?.toStringAsFixed(4)}',
            style: theme.textTheme.bodySmall,
          ),
          onPressed: widget.onLocationView,
          backgroundColor: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    // Poll chip
    if (widget.message.isPoll) {
      chips.add(
        Chip(
          avatar: Icon(
            Icons.poll,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          label: Text(
            'Poll',
            style: theme.textTheme.bodySmall,
          ),
          backgroundColor: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    // Note: Signature indicator is now shown as a small icon next to timestamp

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _buildReactionsRow(ThemeData theme, String currentCallsign) {
    final normalized = ReactionUtils.normalizeReactionMap(widget.message.reactions);
    final entries = normalized.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final chips = <Widget>[];

    for (final entry in entries) {
      final reactionKey = entry.key;
      final users = entry.value;
      if (users.isEmpty) continue;
      final count = users.length;
      final reacted = users.any((u) => u.toUpperCase() == currentCallsign);
      final label = '${_reactionLabel(reactionKey)} $count';

      chips.add(
        InkWell(
          onTap: widget.onReact != null ? () => widget.onReact!(reactionKey) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: reacted
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: reacted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: reacted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }

  String _reactionLabel(String reactionKey) {
    final normalizedKey = ReactionUtils.normalizeReactionKey(reactionKey);
    final emoji = MessageBubbleWidget.reactionEmojiMap[normalizedKey];
    if (emoji != null) {
      return emoji;
    }
    return normalizedKey;
  }

  /// Show message options (copy, etc.)
  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onReact != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  children: MessageBubbleWidget.reactionEmojiMap.entries.map((entry) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onReact!(entry.key);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (widget.onQuote != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onQuote!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.message.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (widget.onHide != null)
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: const Text('Hide message'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onHide!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Message info'),
              onTap: () {
                Navigator.pop(context);
                _showMessageInfo(context);
              },
            ),
            if (widget.canDelete && widget.onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete message',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Confirm deletion
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.onDelete != null) {
                widget.onDelete!();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Show detailed message information
  void _showMessageInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Author', widget.message.author),
              _buildInfoRow('Timestamp', widget.message.timestamp),
              if (widget.message.npub != null)
                _buildInfoRow('npub', widget.message.npub!),
              if (widget.message.hasFile)
                _buildInfoRow('File', widget.message.attachedFile!),
              if (widget.message.hasLocation)
                _buildInfoRow('Location',
                    '${widget.message.latitude}, ${widget.message.longitude}'),
              if (widget.message.isSigned) ...[
                _buildInfoRow('Signature', widget.message.signature!),
                _buildInfoRow('Verified', widget.message.isVerified ? 'Yes' : 'No'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build info row for dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 12),
          ),
          const Divider(),
        ],
      ),
    );
  }

  /// Convert color name to Material Color with appropriate shade for bubble background
  Color _getBubbleColor(String? colorName, ThemeData theme) {
    if (colorName == null || colorName.isEmpty) {
      return theme.colorScheme.surfaceVariant;
    }

    final MaterialColor baseColor;
    switch (colorName.toLowerCase()) {
      case 'red':
        baseColor = Colors.red;
        break;
      case 'green':
        baseColor = Colors.green;
        break;
      case 'yellow':
        baseColor = Colors.amber;
        break;
      case 'purple':
        baseColor = Colors.purple;
        break;
      case 'orange':
        baseColor = Colors.orange;
        break;
      case 'pink':
        baseColor = Colors.pink;
        break;
      case 'cyan':
        baseColor = Colors.cyan;
        break;
      case 'blue':
        baseColor = Colors.blue;
        break;
      default:
        return theme.colorScheme.surfaceVariant;
    }

    // Use shade100 for a subtle bubble background
    return baseColor.shade100;
  }

  /// Get high-contrast text color for bubble based on preferred color
  Color _getTextColor(String? colorName, ThemeData theme) {
    if (colorName == null || colorName.isEmpty) {
      return theme.colorScheme.onSurfaceVariant;
    }

    // Use shade900 (very dark) for high contrast on shade100 backgrounds
    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red.shade900;
      case 'green':
        return Colors.green.shade900;
      case 'yellow':
        return Colors.amber.shade900;
      case 'purple':
        return Colors.purple.shade900;
      case 'orange':
        return Colors.orange.shade900;
      case 'pink':
        return Colors.pink.shade900;
      case 'cyan':
        return Colors.cyan.shade900;
      case 'blue':
        return Colors.blue.shade900;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}
