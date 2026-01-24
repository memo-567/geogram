/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import '../utils/reader_path_utils.dart';
import 'manga_reader_page.dart';
import '../../services/i18n_service.dart';

/// Page showing manga series from a source
class MangaSeriesPage extends StatefulWidget {
  final String collectionPath;
  final Source source;
  final I18nService i18n;

  const MangaSeriesPage({
    super.key,
    required this.collectionPath,
    required this.source,
    required this.i18n,
  });

  @override
  State<MangaSeriesPage> createState() => _MangaSeriesPageState();
}

class _MangaSeriesPageState extends State<MangaSeriesPage> {
  final ReaderService _service = ReaderService();
  List<Manga> _series = [];
  bool _loading = true;
  bool _gridView = true;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    final series = await _service.getMangaSeries(widget.source.id);
    if (mounted) {
      setState(() {
        _series = series;
        _loading = false;
      });
    }
  }

  void _openManga(Manga manga) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaDetailPage(
          collectionPath: widget.collectionPath,
          sourceId: widget.source.id,
          manga: manga,
          i18n: widget.i18n,
        ),
      ),
    ).then((_) => _loadSeries());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        actions: [
          IconButton(
            icon: Icon(_gridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _gridView = !_gridView),
            tooltip: _gridView ? 'List view' : 'Grid view',
          ),
          if (!widget.source.isLocal)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _showSearch,
              tooltip: 'Search',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _series.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadSeries,
                  child: _gridView
                      ? _buildGridView()
                      : _buildListView(),
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No manga series',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          if (!widget.source.isLocal)
            ElevatedButton.icon(
              onPressed: _showSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search for manga'),
            ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _series.length,
      itemBuilder: (context, index) {
        return _buildMangaCard(_series[index]);
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _series.length,
      itemBuilder: (context, index) {
        return _buildMangaTile(_series[index]);
      },
    );
  }

  Widget _buildMangaCard(Manga manga) {
    final theme = Theme.of(context);
    final progress = _service.getMangaProgress(widget.source.id, manga.id);

    return GestureDetector(
      onTap: () => _openManga(manga),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(manga),
                  if (progress != null && progress.chaptersRead.isNotEmpty)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${progress.chaptersRead.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMangaTile(Manga manga) {
    final theme = Theme.of(context);
    final progress = _service.getMangaProgress(widget.source.id, manga.id);

    return ListTile(
      leading: SizedBox(
        width: 50,
        height: 70,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _buildThumbnail(manga),
        ),
      ),
      title: Text(
        manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (manga.author != null)
            Text(
              manga.author!,
              style: theme.textTheme.bodySmall,
            ),
          Row(
            children: [
              _buildStatusChip(manga.status),
              if (progress != null && progress.chaptersRead.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${progress.chaptersRead.length} read',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openManga(manga),
    );
  }

  Widget _buildThumbnail(Manga manga) {
    final thumbnailPath =
        '${widget.collectionPath}/manga/${widget.source.id}/series/${ReaderPathUtils.slugify(manga.title)}/${manga.thumbnail}';

    return FutureBuilder<bool>(
      future: File(thumbnailPath).exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            File(thumbnailPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          );
        }
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.purple.withValues(alpha: 0.2),
      child: const Center(
        child: Icon(Icons.auto_stories, color: Colors.purple),
      ),
    );
  }

  Widget _buildStatusChip(MangaStatus status) {
    Color color;
    String text;

    switch (status) {
      case MangaStatus.ongoing:
        color = Colors.green;
        text = 'Ongoing';
        break;
      case MangaStatus.completed:
        color = Colors.blue;
        text = 'Completed';
        break;
      case MangaStatus.hiatus:
        color = Colors.orange;
        text = 'Hiatus';
        break;
      case MangaStatus.cancelled:
        color = Colors.red;
        text = 'Cancelled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSearch() {
    // TODO: Implement search dialog using source's search function
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search not implemented yet')),
    );
  }
}

/// Page showing details of a manga with chapter list
class MangaDetailPage extends StatefulWidget {
  final String collectionPath;
  final String sourceId;
  final Manga manga;
  final I18nService i18n;

  const MangaDetailPage({
    super.key,
    required this.collectionPath,
    required this.sourceId,
    required this.manga,
    required this.i18n,
  });

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  final ReaderService _service = ReaderService();
  List<MangaChapter> _chapters = [];
  bool _loading = true;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    final chapters =
        await _service.getMangaChapters(widget.sourceId, widget.manga.id);
    if (mounted) {
      setState(() {
        _chapters = chapters;
        _loading = false;
      });
    }
  }

  void _openChapter(MangaChapter chapter) {
    final chapterPath =
        _service.getChapterPath(widget.sourceId, widget.manga.id, chapter.filename);

    if (chapterPath != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MangaReaderPage(
            collectionPath: widget.collectionPath,
            sourceId: widget.sourceId,
            mangaSlug: widget.manga.id,
            chapter: chapter,
            chapterPath: chapterPath,
            i18n: widget.i18n,
          ),
        ),
      ).then((_) => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _service.getMangaProgress(widget.sourceId, widget.manga.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with thumbnail
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.manga.title,
                style: const TextStyle(shadows: [
                  Shadow(blurRadius: 10, color: Colors.black),
                ]),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildHeaderImage(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Manga info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.manga.author != null)
                        Chip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(widget.manga.author!),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.manga.year != null)
                        Chip(
                          avatar: const Icon(Icons.calendar_today, size: 16),
                          label: Text('${widget.manga.year}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        label: Text(widget.manga.status.name.toUpperCase()),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _getStatusColor(widget.manga.status),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Description
                  GestureDetector(
                    onTap: () => setState(() =>
                        _descriptionExpanded = !_descriptionExpanded),
                    child: Text(
                      widget.manga.description,
                      maxLines: _descriptionExpanded ? null : 3,
                      overflow: _descriptionExpanded
                          ? null
                          : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Genres
                  if (widget.manga.genres.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: widget.manga.genres
                          .map((g) => Chip(
                                label: Text(g),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),

                  const SizedBox(height: 16),
                  const Divider(),

                  // Chapters header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Chapters (${_chapters.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (progress != null)
                        Text(
                          '${progress.chaptersRead.length} read',
                          style: TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Chapter list
          if (_loading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = _chapters[index];
                  final isRead = progress?.isChapterRead(chapter.filename) ?? false;

                  return ListTile(
                    leading: isRead
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.circle_outlined),
                    title: Text(
                      chapter.displayName,
                      style: TextStyle(
                        color: isRead
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    subtitle: chapter.pages != null
                        ? Text('${chapter.pages} pages')
                        : null,
                    onTap: () => _openChapter(chapter),
                  );
                },
                childCount: _chapters.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderImage() {
    final thumbnailPath =
        '${widget.collectionPath}/manga/${widget.sourceId}/series/${ReaderPathUtils.slugify(widget.manga.title)}/${widget.manga.thumbnail}';

    return FutureBuilder<bool>(
      future: File(thumbnailPath).exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            File(thumbnailPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.purple.withValues(alpha: 0.3),
            ),
          );
        }
        return Container(color: Colors.purple.withValues(alpha: 0.3));
      },
    );
  }

  Color _getStatusColor(MangaStatus status) {
    switch (status) {
      case MangaStatus.ongoing:
        return Colors.green.withValues(alpha: 0.2);
      case MangaStatus.completed:
        return Colors.blue.withValues(alpha: 0.2);
      case MangaStatus.hiatus:
        return Colors.orange.withValues(alpha: 0.2);
      case MangaStatus.cancelled:
        return Colors.red.withValues(alpha: 0.2);
    }
  }
}
