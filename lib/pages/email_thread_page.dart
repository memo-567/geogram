/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Email Thread Page - Displays email conversation
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../models/email_message.dart';
import '../models/email_thread.dart';
import '../services/email_service.dart';
import '../services/profile_service.dart';
import 'email_compose_page.dart';
import 'photo_viewer_page.dart';

/// Email thread page showing conversation messages
class EmailThreadPage extends StatefulWidget {
  final EmailThread thread;

  /// Whether this is embedded in a larger layout (no AppBar)
  final bool embedded;

  const EmailThreadPage({
    Key? key,
    required this.thread,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<EmailThreadPage> createState() => _EmailThreadPageState();
}

class _EmailThreadPageState extends State<EmailThreadPage> {
  final EmailService _emailService = EmailService();
  final ProfileService _profileService = ProfileService();
  final ScrollController _scrollController = ScrollController();

  late EmailThread _thread;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
  }

  @override
  void didUpdateWidget(EmailThreadPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thread.threadId != oldWidget.thread.threadId) {
      _thread = widget.thread;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadThread() async {
    if (_thread.folderPath == null) return;

    setState(() => _isLoading = true);

    final reloaded = await _emailService.loadThread(_thread.folderPath!);
    if (reloaded != null && mounted) {
      setState(() {
        _thread = reloaded;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reply() async {
    final result = await Navigator.of(context).push<EmailThread>(
      MaterialPageRoute(
        builder: (context) => EmailComposePage(
          replyTo: _thread,
        ),
      ),
    );

    if (result != null) {
      await _reloadThread();
    }
  }

  Future<void> _replyAll() async {
    final result = await Navigator.of(context).push<EmailThread>(
      MaterialPageRoute(
        builder: (context) => EmailComposePage(
          replyTo: _thread,
          replyAll: true,
        ),
      ),
    );

    if (result != null) {
      await _reloadThread();
    }
  }

  Future<void> _forward() async {
    final result = await Navigator.of(context).push<EmailThread>(
      MaterialPageRoute(
        builder: (context) => EmailComposePage(
          forwardFrom: _thread,
        ),
      ),
    );

    if (result != null) {
      // Navigate back or show success
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildContent();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _thread.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.reply),
            onPressed: _reply,
            tooltip: 'Reply',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'reply_all':
                  _replyAll();
                  break;
                case 'forward':
                  _forward();
                  break;
                case 'mark_spam':
                  _emailService.markAsSpam(_thread);
                  Navigator.pop(context);
                  break;
                case 'delete':
                  _emailService.deleteThread(_thread);
                  Navigator.pop(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reply_all',
                child: ListTile(
                  leading: Icon(Icons.reply_all),
                  title: Text('Reply All'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'forward',
                child: ListTile(
                  leading: Icon(Icons.forward),
                  title: Text('Forward'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'mark_spam',
                child: ListTile(
                  leading: Icon(Icons.report),
                  title: Text('Mark as Spam'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _reply,
        child: const Icon(Icons.reply),
        tooltip: 'Reply',
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Thread header
        _buildThreadHeader(),
        const Divider(height: 1),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _thread.messages.length,
            itemBuilder: (context, index) {
              final message = _thread.messages[index];
              final isFirst = index == 0;
              return _buildMessageCard(message, isFirst);
            },
          ),
        ),
        // Quick reply bar (for embedded view)
        if (widget.embedded) _buildQuickReplyBar(),
      ],
    );
  }

  Widget _buildThreadHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            _thread.subject,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // Participants
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildParticipantChip('From', _thread.from, Colors.blue),
              for (final to in _thread.to)
                _buildParticipantChip('To', to, Colors.green),
              for (final cc in _thread.cc)
                _buildParticipantChip('CC', cc, Colors.orange),
            ],
          ),
          const SizedBox(height: 8),
          // Labels
          if (_thread.labels.isNotEmpty)
            Wrap(
              spacing: 4,
              children: _thread.labels.map((label) {
                return Chip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          // Station info
          Row(
            children: [
              Icon(Icons.cloud, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                _thread.station,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.email, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${_thread.messageCount} message(s)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantChip(String role, String email, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 10,
        child: Text(
          role[0],
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
      label: Text(email, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildMessageCard(EmailMessage message, bool isFirst) {
    final profile = _profileService.getProfile();
    final isOwn = profile?.callsign == message.author;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isOwn
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isOwn
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                  child: Text(
                    message.author.isNotEmpty
                        ? message.author[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.author,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatDateTime(message.dateTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Verification badge
                _buildVerificationBadge(message),
                // Actions
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) => _handleMessageAction(value, message),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy'),
                    ),
                    const PopupMenuItem(
                      value: 'quote',
                      child: Text('Quote'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Message content
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              message.content,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          // Attachments
          if (message.hasFile || message.hasImage)
            _buildAttachments(message),
          // Edited indicator
          if (message.isEdited)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'Edited ${message.editedAt}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(EmailMessage message) {
    IconData icon;
    Color color;
    String tooltip;

    switch (message.verificationState) {
      case EmailVerificationState.verified:
        icon = Icons.verified;
        color = Colors.green;
        tooltip = 'Verified sender';
        break;
      case EmailVerificationState.pending:
        icon = Icons.pending;
        color = Colors.orange;
        tooltip = 'Verification pending';
        break;
      case EmailVerificationState.invalid:
        icon = Icons.error;
        color = Colors.red;
        tooltip = 'Invalid signature';
        break;
      case EmailVerificationState.mismatch:
        icon = Icons.warning;
        color = Colors.orange;
        tooltip = 'Sender mismatch';
        break;
      case EmailVerificationState.unverified:
      default:
        // No badge for unverified
        return const SizedBox.shrink();
    }

    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildAttachments(EmailMessage message) {
    // Collect all attachment filenames
    final attachments = <String>[];

    // Single file attachment
    if (message.hasFile && message.attachedFile != null) {
      attachments.add(message.attachedFile!);
    }
    // Single image attachment
    if (message.hasImage && message.attachedImage != null) {
      attachments.add(message.attachedImage!);
    }
    // Multiple files
    final filesStr = message.getMeta('files');
    if (filesStr != null && filesStr.isNotEmpty) {
      attachments.addAll(filesStr.split(','));
    }

    if (attachments.isEmpty) return const SizedBox.shrink();

    // Separate images from other files
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    final images = <String>[];
    final files = <String>[];

    for (final attachment in attachments) {
      final ext = p.extension(attachment).toLowerCase();
      if (imageExtensions.contains(ext)) {
        images.add(attachment);
      } else {
        files.add(attachment);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image thumbnails
          if (images.isNotEmpty) _buildImageAttachments(images),
          // File attachments
          if (files.isNotEmpty) _buildFileAttachments(files),
        ],
      ),
    );
  }

  Widget _buildImageAttachments(List<String> images) {
    return FutureBuilder<String?>(
      future: _emailService.getThreadFolderPath(_thread),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final threadPath = snapshot.data!;

        // Build full paths for images
        final imagePaths =
            images.map((img) => p.join(threadPath, img)).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: imagePaths.asMap().entries.map((entry) {
              final index = entry.key;
              final path = entry.value;
              return _buildImageThumbnail(path, imagePaths, index);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildImageThumbnail(
      String path, List<String> allImagePaths, int index) {
    if (kIsWeb) {
      // Web fallback
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 40, color: Colors.grey),
      );
    }

    return GestureDetector(
      onTap: () {
        // Open in PhotoViewerPage
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PhotoViewerPage(
              imagePaths: allImagePaths,
              initialIndex: index,
            ),
          ),
        );
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileAttachments(List<String> files) {
    return FutureBuilder<String?>(
      future: _emailService.getThreadFolderPath(_thread),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final threadPath = snapshot.data!;

        return Column(
          children: files.map((file) {
            final displayName = _getDisplayFileName(file);
            final fullPath = p.join(threadPath, file);

            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file, size: 20),
              title: Text(
                displayName,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => _openFile(fullPath),
                tooltip: 'Open',
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Extract display name from hashed filename
  String _getDisplayFileName(String hashedName) {
    // Format: sha1hash_originalname.ext
    final underscoreIndex = hashedName.indexOf('_');
    if (underscoreIndex == 40) {
      return hashedName.substring(41);
    }
    return hashedName;
  }

  Future<void> _openFile(String path) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File opening not supported on web')),
      );
      return;
    }

    try {
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No app found to open this file')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  Widget _buildQuickReplyBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _reply,
              icon: const Icon(Icons.reply, size: 18),
              label: const Text('Reply'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _replyAll,
            icon: const Icon(Icons.reply_all, size: 18),
            label: const Text('Reply All'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _forward,
            icon: const Icon(Icons.forward, size: 18),
            label: const Text('Forward'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    String date;
    if (diff.inDays == 0) {
      date = 'Today';
    } else if (diff.inDays == 1) {
      date = 'Yesterday';
    } else {
      date = '${dt.day}/${dt.month}/${dt.year}';
    }

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return '$date at $time';
  }

  void _handleMessageAction(String action, EmailMessage message) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: message.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
        break;
      case 'quote':
        // TODO: Open compose with quoted message
        break;
    }
  }
}
