/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../models/story.dart';
import '../services/stories_storage_service.dart';
import '../widgets/story_card_widget.dart';
import 'story_viewer_page.dart';
import 'story_studio_page.dart';

/// Main Stories app home page - browser for story documents
class StoriesHomePage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;
  final I18nService i18n;

  const StoriesHomePage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
    required this.i18n,
  });

  @override
  State<StoriesHomePage> createState() => _StoriesHomePageState();
}

class _StoriesHomePageState extends State<StoriesHomePage> {
  late StoriesStorageService _storage;
  List<Story> _stories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _storage = StoriesStorageService(basePath: widget.collectionPath);
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() => _isLoading = true);
    try {
      await _storage.initialize();
      _stories = await _storage.loadStories();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createStory() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.get('story_create', 'stories')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: widget.i18n.get('story_title', 'stories'),
                hintText: widget.i18n.get('story_title_hint', 'stories'),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: widget.i18n.get('story_description', 'stories'),
                hintText: widget.i18n.get('story_description_hint', 'stories'),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.isNotEmpty && mounted) {
      final story = await _storage.createStory(
        title: titleController.text,
        description: descController.text.isNotEmpty ? descController.text : null,
        ownerNpub: '', // TODO: Get from profile
        ownerName: null,
      );

      await _loadStories();

      // Open Studio for the new story
      if (mounted) {
        _openStudio(story);
      }
    }
  }

  void _openViewer(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryViewerPage(
          story: story,
          storage: _storage,
          i18n: widget.i18n,
        ),
      ),
    );
  }

  void _openStudio(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryStudioPage(
          story: story,
          storage: _storage,
          i18n: widget.i18n,
        ),
      ),
    ).then((_) => _loadStories());
  }

  Future<void> _deleteStory(Story story) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.get('story_delete', 'stories')),
        content: Text(widget.i18n.get('story_delete_confirm', 'stories')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.get('story_delete', 'stories')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.deleteStory(story);
      await _loadStories();
    }
  }

  Future<void> _renameStory(Story story) async {
    final controller = TextEditingController(text: story.title);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.get('story_rename', 'stories')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: widget.i18n.get('story_title', 'stories'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );

    if (result == true && controller.text.isNotEmpty && controller.text != story.title) {
      await _storage.renameStory(story, controller.text);
      await _loadStories();
    }
  }

  Future<void> _duplicateStory(Story story) async {
    final newTitle = '${story.title} (copy)';
    await _storage.duplicateStory(story, newTitle);
    await _loadStories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collectionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStories,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createStory,
        icon: const Icon(Icons.add),
        label: Text(widget.i18n.get('story_create', 'stories')),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.get('stories_empty', 'stories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.i18n.get('stories_empty_hint', 'stories'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _stories.length,
      itemBuilder: (context, index) {
        final story = _stories[index];
        return StoryCardWidget(
          story: story,
          storage: _storage,
          onTap: () => _openViewer(story),
          onEdit: () => _openStudio(story),
          onDelete: () => _deleteStory(story),
          onRename: () => _renameStory(story),
          onDuplicate: () => _duplicateStory(story),
        );
      },
    );
  }
}
