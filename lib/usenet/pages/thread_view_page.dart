/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Thread View Page - View articles/threads in a newsgroup
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nntp/nntp.dart';

import '../../models/nntp_subscription.dart';
import '../../services/nntp_service.dart';
import '../utils/article_format.dart';
import '../widgets/article_tile.dart';
import '../widgets/compose_dialog.dart';

/// Page for viewing threads in a newsgroup
class ThreadViewPage extends StatefulWidget {
  final NNTPSubscription subscription;
  final bool embedded;

  const ThreadViewPage({
    super.key,
    required this.subscription,
    this.embedded = false,
  });

  @override
  State<ThreadViewPage> createState() => _ThreadViewPageState();
}

class _ThreadViewPageState extends State<ThreadViewPage> {
  final NNTPService _nntpService = NNTPService();

  List<OverviewEntry> _entries = [];
  List<ArticleThread> _threads = [];
  NNTPArticle? _selectedArticle;
  bool _isLoading = true;
  bool _isLoadingArticle = false;
  String? _error;
  bool _showThreaded = true;

  StreamSubscription<NNTPChangeEvent>? _nntpSubscription;

  @override
  void initState() {
    super.initState();
    _loadOverview();

    _nntpSubscription = _nntpService.onNNTPChange.listen(_handleNNTPEvent);
  }

  @override
  void dispose() {
    _nntpSubscription?.cancel();
    super.dispose();
  }

  void _handleNNTPEvent(NNTPChangeEvent event) {
    if (!mounted) return;

    if (event.accountId == widget.subscription.accountId &&
        event.groupName == widget.subscription.groupName) {
      switch (event.type) {
        case NNTPChangeType.syncCompleted:
        case NNTPChangeType.newArticles:
          _loadOverview();
          break;
        default:
          break;
      }
    }
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Determine range to fetch
      final sub = widget.subscription;
      final range = sub.lastRead > 0
          ? Range(sub.lastRead - 50, sub.lastArticle)
          : Range(sub.lastArticle - 100, sub.lastArticle);

      _entries = await _nntpService.fetchOverview(
        sub.accountId,
        sub.groupName,
        range: range,
      );

      // Build threads
      _threads = _nntpService.buildThreads(_entries);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadArticle(OverviewEntry entry) async {
    setState(() {
      _isLoadingArticle = true;
    });

    try {
      final article = await _nntpService.fetchArticle(
        widget.subscription.accountId,
        widget.subscription.groupName,
        entry.articleNumber,
      );

      if (mounted) {
        setState(() {
          _selectedArticle = article;
          _isLoadingArticle = false;
        });
      }

      // Mark as read
      await _nntpService.markAsRead(
        widget.subscription.accountId,
        widget.subscription.groupName,
        upToArticle: entry.articleNumber,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingArticle = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load article: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _compose({NNTPArticle? replyTo}) {
    showDialog(
      context: context,
      builder: (context) => ComposeDialog(
        accountId: widget.subscription.accountId,
        newsgroup: widget.subscription.groupName,
        replyTo: replyTo,
      ),
    ).then((posted) {
      if (posted == true) {
        _loadOverview();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWideScreen = MediaQuery.of(context).size.width > 900;

    Widget body;

    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOverview,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_entries.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No articles',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This group appears to be empty',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    } else if (isWideScreen) {
      body = Row(
        children: [
          SizedBox(
            width: 400,
            child: _buildThreadList(theme),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _buildArticleView(theme),
          ),
        ],
      );
    } else if (_selectedArticle != null) {
      body = _buildArticleView(theme);
    } else {
      body = _buildThreadList(theme);
    }

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        leading: _selectedArticle != null && !isWideScreen
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedArticle = null),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedArticle?.subject ?? widget.subscription.groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_selectedArticle == null)
              Text(
                '${_entries.length} articles',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        actions: [
          if (_selectedArticle == null) ...[
            IconButton(
              icon: Icon(_showThreaded ? Icons.view_list : Icons.account_tree),
              onPressed: () {
                setState(() => _showThreaded = !_showThreaded);
              },
              tooltip: _showThreaded ? 'Flat List' : 'Threaded View',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _nntpService.syncGroup(
                  widget.subscription.accountId,
                  widget.subscription.groupName,
                );
              },
              tooltip: 'Sync',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.reply),
              onPressed: () => _compose(replyTo: _selectedArticle),
              tooltip: 'Reply',
            ),
          ],
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              if (_selectedArticle == null) ...[
                const PopupMenuItem(
                  value: 'mark_read',
                  child: ListTile(
                    leading: Icon(Icons.done_all),
                    title: Text('Mark All Read'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'compose',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('New Post'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: body,
      floatingActionButton: _selectedArticle == null
          ? FloatingActionButton(
              onPressed: () => _compose(),
              tooltip: 'New Post',
              child: const Icon(Icons.edit),
            )
          : null,
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'mark_read':
        _nntpService.markAsRead(
          widget.subscription.accountId,
          widget.subscription.groupName,
          all: true,
        );
        break;
      case 'compose':
        _compose();
        break;
    }
  }

  Widget _buildThreadList(ThemeData theme) {
    if (_showThreaded) {
      return RefreshIndicator(
        onRefresh: _loadOverview,
        child: ListView.builder(
          itemCount: _threads.length,
          itemBuilder: (context, index) {
            final thread = _threads[index];
            return _buildThreadTile(thread, theme);
          },
        ),
      );
    }

    // Flat list sorted by date
    final sorted = List<OverviewEntry>.from(_entries)
      ..sort((a, b) {
        final aDate = a.date ?? DateTime(1970);
        final bDate = b.date ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final entry = sorted[index];
          return ArticleTile(
            entry: entry,
            onTap: () => _loadArticle(entry),
          );
        },
      ),
    );
  }

  Widget _buildThreadTile(ArticleThread thread, ThemeData theme) {
    final root = thread.root;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArticleTile(
            entry: root,
            onTap: () => _loadArticle(root),
          ),
          if (thread.replies.isNotEmpty && !thread.isCollapsed)
            ...thread.replies.map((reply) {
              return Padding(
                padding: const EdgeInsets.only(left: 24),
                child: ArticleTile(
                  entry: reply,
                  onTap: () => _loadArticle(reply),
                ),
              );
            }),
          if (thread.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    thread.isCollapsed = !thread.isCollapsed;
                  });
                },
                icon: Icon(
                  thread.isCollapsed ? Icons.expand_more : Icons.expand_less,
                  size: 18,
                ),
                label: Text(
                  thread.isCollapsed
                      ? 'Show ${thread.replies.length} replies'
                      : 'Hide replies',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArticleView(ThemeData theme) {
    if (_isLoadingArticle) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedArticle == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Select an article to read',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    final article = _selectedArticle!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            article.subject,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Author and date
          Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  ArticleFormat.extractAuthorName(article.from)
                      .substring(0, 1)
                      .toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ArticleFormat.extractAuthorName(article.from),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ArticleFormat.formatDate(article.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Newsgroups
          if (article.newsgroups.contains(','))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 4,
                children: article.newsgroups.split(',').map((g) {
                  return Chip(
                    label: Text(g.trim()),
                    labelStyle: theme.textTheme.labelSmall,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),

          const Divider(),
          const SizedBox(height: 8),

          // Body
          SelectableText(
            article.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _compose(replyTo: article),
                icon: const Icon(Icons.reply),
                label: const Text('Reply'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: Quote and reply
                },
                icon: const Icon(Icons.format_quote),
                label: const Text('Quote'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
