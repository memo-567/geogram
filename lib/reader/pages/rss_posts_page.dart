/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import 'article_reader_page.dart';
import '../../services/i18n_service.dart';

/// Page showing list of posts from an RSS source
class RssPostsPage extends StatefulWidget {
  final String collectionPath;
  final Source source;
  final I18nService i18n;

  const RssPostsPage({
    super.key,
    required this.collectionPath,
    required this.source,
    required this.i18n,
  });

  @override
  State<RssPostsPage> createState() => _RssPostsPageState();
}

class _RssPostsPageState extends State<RssPostsPage> {
  final ReaderService _service = ReaderService();
  List<RssPost> _posts = [];
  bool _loading = true;
  String _filter = 'all'; // all, unread, starred

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final posts = await _service.getPosts(widget.source.id);
    if (mounted) {
      setState(() {
        _posts = posts;
        _loading = false;
      });
    }
  }

  List<RssPost> get _filteredPosts {
    switch (_filter) {
      case 'unread':
        return _posts.where((p) => !p.isRead).toList();
      case 'starred':
        return _posts.where((p) => p.isStarred).toList();
      default:
        return _posts;
    }
  }

  void _openPost(RssPost post) async {
    // Mark as read
    final slug = post.id.replaceFirst('post_', '');
    await _service.markPostRead(widget.source.id, slug);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArticleReaderPage(
            collectionPath: widget.collectionPath,
            sourceId: widget.source.id,
            post: post,
            i18n: widget.i18n,
          ),
        ),
      ).then((_) => _loadPosts());
    }
  }

  void _toggleStarred(RssPost post) async {
    final slug = post.id.replaceFirst('post_', '');
    await _service.togglePostStarred(widget.source.id, slug);
    await _loadPosts();
  }

  void _markAllRead() async {
    for (final post in _posts.where((p) => !p.isRead)) {
      final slug = post.id.replaceFirst('post_', '');
      await _service.markPostRead(widget.source.id, slug);
    }
    await _loadPosts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All posts marked as read')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadCount = _posts.where((p) => !p.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.source.name),
            if (unreadCount > 0)
              Text(
                '$unreadCount unread',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    if (_filter == 'all') const Icon(Icons.check, size: 18),
                    if (_filter == 'all') const SizedBox(width: 8),
                    const Text('All posts'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'unread',
                child: Row(
                  children: [
                    if (_filter == 'unread') const Icon(Icons.check, size: 18),
                    if (_filter == 'unread') const SizedBox(width: 8),
                    const Text('Unread'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'starred',
                child: Row(
                  children: [
                    if (_filter == 'starred') const Icon(Icons.check, size: 18),
                    if (_filter == 'starred') const SizedBox(width: 8),
                    const Text('Starred'),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_read') {
                _markAllRead();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Text('Mark all as read'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredPosts.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: () async {
                    await _service.refreshRssSource(widget.source.id);
                    await _loadPosts();
                  },
                  child: ListView.builder(
                    itemCount: _filteredPosts.length,
                    itemBuilder: (context, index) {
                      return _buildPostTile(_filteredPosts[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    String message;
    switch (_filter) {
      case 'unread':
        message = 'No unread posts';
        break;
      case 'starred':
        message = 'No starred posts';
        break;
      default:
        message = 'No posts yet';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostTile(RssPost post) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.MMMd();

    return Dismissible(
      key: Key(post.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete post?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        final slug = post.id.replaceFirst('post_', '');
        await _service.deletePost(widget.source.id, slug);
        await _loadPosts();
      },
      child: ListTile(
        title: Text(
          post.title,
          style: TextStyle(
            fontWeight: post.isRead ? FontWeight.normal : FontWeight.bold,
            color: post.isRead
                ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                : null,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.summary != null && post.summary!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  post.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (post.author != null && post.author!.isNotEmpty) ...[
                  Text(
                    post.author!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Text(' \u2022 '),
                ],
                Text(
                  dateFormat.format(post.publishedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (post.readTimeMinutes != null) ...[
                  const Text(' \u2022 '),
                  Text(
                    '${post.readTimeMinutes} min read',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            post.isStarred ? Icons.star : Icons.star_border,
            color: post.isStarred ? Colors.amber : null,
          ),
          onPressed: () => _toggleStarred(post),
        ),
        onTap: () => _openPost(post),
      ),
    );
  }
}
