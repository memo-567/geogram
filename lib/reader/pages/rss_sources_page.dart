/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import 'rss_posts_page.dart';
import '../../services/i18n_service.dart';

/// Page showing list of RSS sources
class RssSourcesPage extends StatefulWidget {
  final String collectionPath;
  final I18nService i18n;

  const RssSourcesPage({
    super.key,
    required this.collectionPath,
    required this.i18n,
  });

  @override
  State<RssSourcesPage> createState() => _RssSourcesPageState();
}

class _RssSourcesPageState extends State<RssSourcesPage> {
  final ReaderService _service = ReaderService();
  List<Source> _sources = [];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final sources = await _service.getRssSources();
    if (mounted) {
      setState(() {
        _sources = sources;
        _loading = false;
      });
    }
  }

  Future<void> _refreshSource(Source source) async {
    setState(() => _refreshing = true);

    final count = await _service.refreshRssSource(source.id);
    await _loadSources();

    if (mounted) {
      setState(() => _refreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0
              ? 'Fetched $count new posts from ${source.name}'
              : 'No new posts from ${source.name}'),
        ),
      );
    }
  }

  Future<void> _refreshAll() async {
    setState(() => _refreshing = true);

    int totalNew = 0;
    for (final source in _sources) {
      final count = await _service.refreshRssSource(source.id);
      totalNew += count;
    }

    await _loadSources();

    if (mounted) {
      setState(() => _refreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fetched $totalNew new posts from ${_sources.length} sources'),
        ),
      );
    }
  }

  void _openSource(Source source) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RssPostsPage(
          collectionPath: widget.collectionPath,
          source: source,
          i18n: widget.i18n,
        ),
      ),
    ).then((_) => _loadSources());
  }

  void _addSource() {
    showDialog(
      context: context,
      builder: (context) => _AddSourceDialog(
        onAdd: (name, url) async {
          // TODO: Implement source creation through SourceService
          await _loadSources();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RSS Feeds'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
              tooltip: 'Refresh all',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView.builder(
                    itemCount: _sources.length,
                    itemBuilder: (context, index) {
                      return _buildSourceTile(_sources[index]);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSource,
        tooltip: 'Add source',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rss_feed_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No RSS sources',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first RSS feed',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(Source source) {
    final theme = Theme.of(context);
    final hasError = source.error != null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: hasError
            ? Colors.red.withValues(alpha: 0.2)
            : Colors.orange.withValues(alpha: 0.2),
        child: Icon(
          hasError ? Icons.error_outline : Icons.rss_feed,
          color: hasError ? Colors.red : Colors.orange,
        ),
      ),
      title: Text(source.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasError)
            Text(
              'Error: ${source.error}',
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              '${source.postCount} posts${source.unreadCount > 0 ? ', ${source.unreadCount} unread' : ''}',
            ),
          if (source.lastFetchedAt != null)
            Text(
              'Updated ${_formatTimeAgo(source.lastFetchedAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
      trailing: source.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${source.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshSource(source),
            ),
      onTap: () => _openSource(source),
      onLongPress: () => _showSourceOptions(source),
    );
  }

  void _showSourceOptions(Source source) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh'),
              onTap: () {
                Navigator.pop(context);
                _refreshSource(source);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement edit
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement delete
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }
}

/// Dialog for adding a new RSS source
class _AddSourceDialog extends StatefulWidget {
  final Future<void> Function(String name, String url) onAdd;

  const _AddSourceDialog({required this.onAdd});

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await widget.onAdd(
        _nameController.text.trim(),
        _urlController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add RSS Source'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g., Hacker News',
              ),
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Feed URL',
                hintText: 'https://example.com/feed.xml',
              ),
              validator: (v) {
                if (v?.isEmpty == true) return 'Required';
                if (!v!.startsWith('http')) return 'Must be a URL';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
