/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/reader_models.dart';
import '../services/reader_service.dart';
import '../../services/i18n_service.dart';

/// Page for browsing local books
class BookBrowserPage extends StatefulWidget {
  final String collectionPath;
  final I18nService i18n;
  final List<String> initialPath;

  const BookBrowserPage({
    super.key,
    required this.collectionPath,
    required this.i18n,
    this.initialPath = const [],
  });

  @override
  State<BookBrowserPage> createState() => _BookBrowserPageState();
}

class _BookBrowserPageState extends State<BookBrowserPage> {
  final ReaderService _service = ReaderService();
  List<String> _currentPath = [];
  List<BookFolder> _folders = [];
  List<Book> _books = [];
  bool _loading = true;
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _currentPath = List.from(widget.initialPath);
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);

    final folders = await _service.getBookFolders(_currentPath);
    final books = await _service.getBooks(_currentPath);

    if (mounted) {
      setState(() {
        _folders = folders;
        _books = books;
        _loading = false;
      });
    }
  }

  void _openFolder(BookFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookBrowserPage(
          collectionPath: widget.collectionPath,
          i18n: widget.i18n,
          initialPath: [..._currentPath, folder.id],
        ),
      ),
    );
  }

  void _openBook(Book book) {
    // TODO: Implement book reader (EPUB, PDF, TXT, MD)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${book.title}... (not implemented)')),
    );
  }

  void _addFolder() {
    showDialog(
      context: context,
      builder: (context) => _CreateFolderDialog(
        onCreated: (name) async {
          // TODO: Implement folder creation
          await _loadContent();
        },
      ),
    );
  }

  void _importBook() {
    // TODO: Implement book import (file picker)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import not implemented yet')),
    );
  }

  String get _title {
    if (_currentPath.isEmpty) {
      return 'Books';
    }
    return _currentPath.last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = _folders.isEmpty && _books.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: Icon(_gridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _gridView = !_gridView),
            tooltip: _gridView ? 'List view' : 'Grid view',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'import') _importBook();
              if (value == 'folder') _addFolder();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_upload),
                  title: Text('Import book'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'folder',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder),
                  title: Text('New folder'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadContent,
                  child: _gridView ? _buildGridView() : _buildListView(),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importBook,
        tooltip: 'Import book',
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
            Icons.book_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No books here',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to import your first book',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder),
            label: const Text('Create folder'),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return ListView(
      children: [
        ..._folders.map((folder) => _buildFolderTile(folder)),
        ..._books.map((book) => _buildBookTile(book)),
      ],
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _folders.length + _books.length,
      itemBuilder: (context, index) {
        if (index < _folders.length) {
          return _buildFolderCard(_folders[index]);
        }
        return _buildBookCard(_books[index - _folders.length]);
      },
    );
  }

  Widget _buildFolderTile(BookFolder folder) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.teal.withValues(alpha: 0.2),
        child: const Icon(Icons.folder, color: Colors.teal),
      ),
      title: Text(folder.name),
      subtitle: folder.description != null ? Text(folder.description!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openFolder(folder),
    );
  }

  Widget _buildFolderCard(BookFolder folder) {
    return GestureDetector(
      onTap: () => _openFolder(folder),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder, color: Colors.teal, size: 40),
          ),
          const SizedBox(height: 8),
          Text(
            folder.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBookTile(Book book) {
    final theme = Theme.of(context);
    final progress = _service.getBookProgress(book.fullPath);

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: _buildBookIcon(book),
      ),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author != null)
            Text(
              book.author!,
              style: theme.textTheme.bodySmall,
            ),
          Row(
            children: [
              _buildFormatChip(book.format),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${progress.position.percent.round()}%',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openBook(book),
      onLongPress: () => _showBookOptions(book),
    );
  }

  Widget _buildBookCard(Book book) {
    final theme = Theme.of(context);
    final progress = _service.getBookProgress(book.fullPath);

    return GestureDetector(
      onTap: () => _openBook(book),
      onLongPress: () => _showBookOptions(book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildBookCover(book),
                ),
                if (progress != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: progress.position.percent / 100,
                        backgroundColor: Colors.black54,
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
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

  Widget _buildBookIcon(Book book) {
    IconData icon;
    Color color;

    switch (book.format) {
      case BookFormat.epub:
        icon = Icons.menu_book;
        color = Colors.blue;
        break;
      case BookFormat.pdf:
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case BookFormat.txt:
        icon = Icons.article;
        color = Colors.grey;
        break;
      case BookFormat.md:
        icon = Icons.description;
        color = Colors.purple;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(icon, color: color),
      ),
    );
  }

  Widget _buildBookCover(Book book) {
    // Check for cover image
    if (book.thumbnail != null) {
      final coverPath = '${book.path}/${book.thumbnail}';
      return FutureBuilder<bool>(
        future: File(coverPath).exists(),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return Image.file(
              File(coverPath),
              fit: BoxFit.cover,
            );
          }
          return _buildBookIcon(book);
        },
      );
    }
    return _buildBookIcon(book);
  }

  Widget _buildFormatChip(BookFormat format) {
    String text;
    Color color;

    switch (format) {
      case BookFormat.epub:
        text = 'EPUB';
        color = Colors.blue;
        break;
      case BookFormat.pdf:
        text = 'PDF';
        color = Colors.red;
        break;
      case BookFormat.txt:
        text = 'TXT';
        color = Colors.grey;
        break;
      case BookFormat.md:
        text = 'MD';
        color = Colors.purple;
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

  void _showBookOptions(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(context);
                _showBookDetails(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement share
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

  void _showBookDetails(Book book) {
    final progress = _service.getBookProgress(book.fullPath);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(book.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book.author != null) Text('Author: ${book.author}'),
            Text('Format: ${book.format.name.toUpperCase()}'),
            Text('Filename: ${book.filename}'),
            if (progress != null) ...[
              const SizedBox(height: 8),
              Text('Progress: ${progress.position.percent.round()}%'),
              Text('Page: ${progress.position.page}'),
            ],
          ],
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
}

/// Dialog for creating a new folder
class _CreateFolderDialog extends StatefulWidget {
  final Future<void> Function(String name) onCreated;

  const _CreateFolderDialog({required this.onCreated});

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    setState(() => _loading = true);

    try {
      await widget.onCreated(name);
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
      title: const Text('New Folder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          hintText: 'e.g., Science Fiction',
        ),
        onSubmitted: (_) => _submit(),
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
              : const Text('Create'),
        ),
      ],
    );
  }
}
