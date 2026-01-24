/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import '../../services/i18n_service.dart';

/// Page for reading an article
class ArticleReaderPage extends StatefulWidget {
  final String collectionPath;
  final String sourceId;
  final RssPost post;
  final I18nService i18n;

  const ArticleReaderPage({
    super.key,
    required this.collectionPath,
    required this.sourceId,
    required this.post,
    required this.i18n,
  });

  @override
  State<ArticleReaderPage> createState() => _ArticleReaderPageState();
}

class _ArticleReaderPageState extends State<ArticleReaderPage> {
  final ReaderService _service = ReaderService();
  String? _content;
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    final slug = widget.post.id.replaceFirst('post_', '');
    final content = await _service.getPostContent(widget.sourceId, slug);
    if (mounted) {
      setState(() {
        _content = content;
        _loading = false;
      });
    }
  }

  void _openInBrowser() async {
    final url = Uri.parse(widget.post.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _shareArticle() {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share not implemented yet')),
    );
  }

  void _toggleStarred() async {
    final slug = widget.post.id.replaceFirst('post_', '');
    await _service.togglePostStarred(widget.sourceId, slug);
    setState(() {
      widget.post.isStarred = !widget.post.isStarred;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _service.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Article'),
        actions: [
          IconButton(
            icon: Icon(
              widget.post.isStarred ? Icons.star : Icons.star_border,
              color: widget.post.isStarred ? Colors.amber : null,
            ),
            onPressed: _toggleStarred,
            tooltip: widget.post.isStarred ? 'Unstar' : 'Star',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
            tooltip: 'Open in browser',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'share') _shareArticle();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('Share'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    widget.post.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Meta info
                  Wrap(
                    spacing: 8,
                    children: [
                      if (widget.post.author != null)
                        Chip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(widget.post.author!),
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        avatar: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_formatDate(widget.post.publishedAt)),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (widget.post.readTimeMinutes != null)
                        Chip(
                          avatar: const Icon(Icons.timer, size: 16),
                          label: Text('${widget.post.readTimeMinutes} min'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Categories/tags
                  if (widget.post.categories.isNotEmpty ||
                      widget.post.tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ...widget.post.categories.map((cat) => Chip(
                              label: Text(cat),
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  Colors.blue.withValues(alpha: 0.2),
                            )),
                        ...widget.post.tags.map((tag) => Chip(
                              label: Text('#$tag'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor:
                                  Colors.green.withValues(alpha: 0.2),
                            )),
                      ],
                    ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Content
                  if (_content != null)
                    MarkdownBody(
                      data: _content!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: settings.general.fontSize.toDouble(),
                          height: settings.general.lineHeight,
                        ),
                        h1: theme.textTheme.headlineMedium,
                        h2: theme.textTheme.titleLarge,
                        h3: theme.textTheme.titleMedium,
                        code: TextStyle(
                          backgroundColor:
                              theme.colorScheme.surface.withValues(alpha: 0.5),
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        blockquote: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 4,
                            ),
                          ),
                        ),
                        blockquotePadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          launchUrl(
                            Uri.parse(href),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    )
                  else
                    Center(
                      child: Text(
                        'No content available',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Source link
                  OutlinedButton.icon(
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.link),
                    label: const Text('View original'),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
