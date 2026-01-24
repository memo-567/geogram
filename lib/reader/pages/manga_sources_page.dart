/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import 'manga_series_page.dart';
import '../../services/i18n_service.dart';

/// Page showing list of manga sources
class MangaSourcesPage extends StatefulWidget {
  final String collectionPath;
  final I18nService i18n;

  const MangaSourcesPage({
    super.key,
    required this.collectionPath,
    required this.i18n,
  });

  @override
  State<MangaSourcesPage> createState() => _MangaSourcesPageState();
}

class _MangaSourcesPageState extends State<MangaSourcesPage> {
  final ReaderService _service = ReaderService();
  List<Source> _sources = [];
  Map<String, int> _seriesCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    final sources = await _service.getMangaSources();

    // Load series counts for each source
    final counts = <String, int>{};
    for (final source in sources) {
      final series = await _service.getMangaSeries(source.id);
      counts[source.id] = series.length;
    }

    if (mounted) {
      setState(() {
        _sources = sources;
        _seriesCounts = counts;
        _loading = false;
      });
    }
  }

  void _openSource(Source source) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaSeriesPage(
          collectionPath: widget.collectionPath,
          source: source,
          i18n: widget.i18n,
        ),
      ),
    ).then((_) => _loadSources());
  }

  void _addSource() {
    // TODO: Implement add manga source dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add manga source not implemented yet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manga'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadSources,
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
            Icons.auto_stories_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No manga sources',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first manga source',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(Source source) {
    final count = _seriesCounts[source.id] ?? 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.purple.withValues(alpha: 0.2),
        child: const Icon(Icons.auto_stories, color: Colors.purple),
      ),
      title: Text(source.name),
      subtitle: Text(
        source.isLocal
            ? '$count series (local)'
            : '$count series from ${source.url ?? 'unknown'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openSource(source),
    );
  }
}
