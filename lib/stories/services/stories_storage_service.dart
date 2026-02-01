/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import '../../services/log_service.dart';
import '../models/story.dart';
import '../models/story_content.dart';
import '../models/story_scene.dart';
import 'story_ndf_service.dart';

/// Service for managing story files in a collection
class StoriesStorageService {
  final String basePath;
  final _log = LogService();
  final _ndfService = StoryNdfService();

  StoriesStorageService({required this.basePath});

  /// Get the stories directory path
  String get storiesDir => '$basePath/stories';

  /// Initialize the storage (create directories if needed)
  Future<void> initialize() async {
    final dir = Directory(storiesDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// List all stories in the collection
  Future<List<Story>> loadStories() async {
    final stories = <Story>[];

    final dir = Directory(storiesDir);
    if (!await dir.exists()) {
      return stories;
    }

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.ndf')) {
        final story = await _ndfService.readStory(entity.path);
        if (story != null) {
          stories.add(story.copyWith(filePath: entity.path));
        }
      }
    }

    // Sort by modified date (newest first)
    stories.sort((a, b) => b.modified.compareTo(a.modified));
    return stories;
  }

  /// Get a single story by ID
  Future<Story?> getStory(String storyId) async {
    final stories = await loadStories();
    return stories.cast<Story?>().firstWhere(
          (s) => s?.id == storyId,
          orElse: () => null,
        );
  }

  /// Get a story by filename
  Future<Story?> getStoryByFilename(String filename) async {
    final filePath = '$storiesDir/$filename';
    return _ndfService.readStory(filePath);
  }

  /// Create a new story
  Future<Story> createStory({
    required String title,
    String? description,
    required String ownerNpub,
    String? ownerName,
  }) async {
    await initialize();

    final story = Story.create(title: title, description: description);
    final filePath = '$storiesDir/${story.filename}';

    // Check for filename collision and add number if needed
    final finalPath = await _getUniqueFilePath(filePath);

    await _ndfService.createStory(
      outputPath: finalPath,
      story: story,
      ownerNpub: ownerNpub,
      ownerName: ownerName,
    );

    return story.copyWith(filePath: finalPath);
  }

  /// Get unique file path, adding number suffix if needed
  Future<String> _getUniqueFilePath(String basePath) async {
    var path = basePath;
    var counter = 2;

    while (await File(path).exists()) {
      final nameWithoutExt = basePath.substring(0, basePath.length - 4);
      path = '$nameWithoutExt-$counter.ndf';
      counter++;
    }

    return path;
  }

  /// Rename a story (updates title and filename)
  Future<Story> renameStory(Story story, String newTitle) async {
    if (story.filePath == null) {
      throw Exception('Story has no file path');
    }

    final updated = story.copyWith(
      title: newTitle,
      modified: DateTime.now(),
      revision: story.revision + 1,
    );

    // Save updated metadata
    await _ndfService.saveStoryMetadata(story.filePath!, updated);

    // Rename file if needed
    final newFilename = updated.filename;
    final currentFilename = story.filePath!.split('/').last;

    if (newFilename != currentFilename) {
      final newPath = '$storiesDir/$newFilename';
      final uniquePath = await _getUniqueFilePath(newPath);

      await File(story.filePath!).rename(uniquePath);
      _log.log('StoriesStorageService: Renamed ${story.filePath} to $uniquePath');
      return updated.copyWith(filePath: uniquePath);
    }

    return updated;
  }

  /// Delete a story
  Future<void> deleteStory(Story story) async {
    if (story.filePath == null) return;

    final file = File(story.filePath!);
    if (await file.exists()) {
      await file.delete();
      _log.log('StoriesStorageService: Deleted ${story.filePath}');
    }
  }

  /// Load story content
  Future<StoryContent?> loadStoryContent(Story story) async {
    if (story.filePath == null) return null;
    return _ndfService.readStoryContent(story.filePath!);
  }

  /// Save story content
  Future<void> saveStoryContent(Story story, StoryContent content) async {
    if (story.filePath == null) return;
    await _ndfService.saveStoryContent(story.filePath!, content);

    // Update story metadata
    final updated = story.touch();
    await _ndfService.saveStoryMetadata(story.filePath!, updated);
  }

  /// Save a single scene
  Future<void> saveScene(Story story, StoryScene scene) async {
    if (story.filePath == null) return;
    await _ndfService.saveScene(story.filePath!, scene);
  }

  /// Delete a scene
  Future<void> deleteScene(Story story, String sceneId) async {
    if (story.filePath == null) return;
    await _ndfService.deleteScene(story.filePath!, sceneId);
  }

  /// Add media to story
  Future<String> addMedia(Story story, String sourceFilePath) async {
    if (story.filePath == null) {
      throw Exception('Story has no file path');
    }
    return _ndfService.addMediaFromFile(story.filePath!, sourceFilePath);
  }

  /// Read media from story
  Future<String?> extractMedia(Story story, String assetRef) async {
    if (story.filePath == null) return null;
    return _ndfService.extractMediaToTemp(story.filePath!, assetRef);
  }

  /// Set story thumbnail
  Future<void> setThumbnail(Story story, String imagePath) async {
    if (story.filePath == null) return;

    final file = File(imagePath);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    await _ndfService.setThumbnail(story.filePath!, bytes);
  }

  /// Read story thumbnail
  Future<String?> extractThumbnail(Story story) async {
    if (story.filePath == null || story.thumbnail == null) return null;
    return _ndfService.extractMediaToTemp(story.filePath!, story.thumbnail!);
  }

  /// Cleanup unused media in a story
  Future<void> cleanupMedia(Story story) async {
    if (story.filePath == null) return;
    await _ndfService.cleanupUnusedMedia(story.filePath!);
  }

  /// Duplicate a story
  Future<Story> duplicateStory(Story original, String newTitle) async {
    if (original.filePath == null) {
      throw Exception('Original story has no file path');
    }

    // Read original file
    final originalFile = File(original.filePath!);
    final bytes = await originalFile.readAsBytes();

    // Create new story metadata
    final newStory = Story.create(
      title: newTitle,
      description: original.description,
    );

    // Write to new file
    final newPath = await _getUniqueFilePath('$storiesDir/${newStory.filename}');
    await File(newPath).writeAsBytes(bytes);

    // Update the metadata in the new file
    await _ndfService.saveStoryMetadata(newPath, newStory);

    _log.log('StoriesStorageService: Duplicated story to $newPath');
    return newStory.copyWith(filePath: newPath);
  }
}
