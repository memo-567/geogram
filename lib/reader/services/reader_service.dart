/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';

import '../models/reader_models.dart';
import '../utils/reader_path_utils.dart';
import 'manga_service.dart';
import 'reader_storage_service.dart';
import 'rss_service.dart';
import '../../services/log_service.dart';

/// Main service for managing reader operations
class ReaderService {
  static final ReaderService _instance = ReaderService._internal();
  factory ReaderService() => _instance;
  ReaderService._internal();

  ReaderStorageService? _storage;
  String? _currentPath;
  ReaderSettings? _settings;
  ReadingProgress? _progress;

  /// Stream controller for reader changes
  final _changesController = StreamController<ReaderChange>.broadcast();

  /// Stream of reader changes
  Stream<ReaderChange> get changes => _changesController.stream;

  /// Check if the service is initialized
  bool get isInitialized => _storage != null;

  /// Get the current collection path
  String? get currentPath => _currentPath;

  /// Get current settings
  ReaderSettings get settings => _settings ?? ReaderSettings();

  /// Get current progress
  ReadingProgress get progress => _progress ?? ReadingProgress();

  /// Initialize the service with a collection path
  Future<void> initializeCollection(String path) async {
    _currentPath = path;
    _storage = ReaderStorageService(path);
    await _storage!.initialize();

    // Load settings and progress
    _settings = await _storage!.readSettings();
    _progress = await _storage!.readProgress();

    LogService().log('ReaderService: Initialized with path $path');
  }

  /// Reset the service (for switching collections)
  void reset() {
    _storage = null;
    _currentPath = null;
    _settings = null;
    _progress = null;
    MangaService().clearCache();
  }

  // ============ Settings Operations ============

  /// Update settings
  Future<bool> updateSettings(ReaderSettings settings) async {
    if (_storage == null) return false;
    final success = await _storage!.writeSettings(settings);
    if (success) {
      _settings = settings;
      _notifyChange(ReaderChangeType.settingsUpdated);
    }
    return success;
  }

  // ============ Source Operations ============

  /// Get all RSS sources
  Future<List<Source>> getRssSources() async {
    if (_storage == null) return [];
    return _storage!.listSources('rss');
  }

  /// Get all manga sources
  Future<List<Source>> getMangaSources() async {
    if (_storage == null) return [];
    return _storage!.listSources('manga');
  }

  /// Get a source by category and ID
  Future<Source?> getSource(String category, String sourceId) async {
    if (_storage == null) return null;
    return _storage!.readSource(category, sourceId);
  }

  /// Refresh an RSS source (fetch new posts)
  Future<int> refreshRssSource(String sourceId) async {
    if (_storage == null) return 0;

    final source = await _storage!.readSource('rss', sourceId);
    if (source == null || source.url == null) return 0;

    try {
      // Fetch feed
      final feedItems = await RssService().fetchFeed(source.url!);

      // Get existing posts for deduplication
      final existingPosts = await _storage!.listPosts(sourceId);
      final existingGuids = existingPosts.map((p) => p.guid).toSet();

      int newCount = 0;

      for (final item in feedItems) {
        // Skip if already exists
        if (item.id != null && existingGuids.contains(item.id)) continue;
        if (existingGuids.contains(item.url)) continue;

        // Convert to post
        final post = RssService().feedItemToPost(item, sourceId: sourceId);
        final slug = ReaderPathUtils.postSlug(post.publishedAt, post.title);

        // Save post metadata
        await _storage!.writePost(sourceId, slug, post);

        // Save content as markdown
        if (item.content != null) {
          final markdown = RssService().htmlToMarkdown(item.content!);
          await _storage!.writePostContent(sourceId, slug, markdown);
        }

        newCount++;
      }

      // Update source metadata
      final updatedSource = source.copyWith(
        lastFetchedAt: DateTime.now(),
        postCount: existingPosts.length + newCount,
        error: null,
      );
      await _storage!.writeSource('rss', updatedSource);

      // Recalculate unread count
      await _updateSourceUnreadCount(sourceId);

      _notifyChange(ReaderChangeType.sourceRefreshed, sourceId: sourceId);
      return newCount;
    } catch (e) {
      LogService().log('ReaderService: Error refreshing source: $e');

      // Save error to source
      final updatedSource = source.copyWith(
        error: e.toString(),
        modifiedAt: DateTime.now(),
      );
      await _storage!.writeSource('rss', updatedSource);

      return 0;
    }
  }

  /// Update source unread count
  Future<void> _updateSourceUnreadCount(String sourceId) async {
    if (_storage == null) return;

    final posts = await _storage!.listPosts(sourceId);
    final unreadCount = posts.where((p) => !p.isRead).length;

    final source = await _storage!.readSource('rss', sourceId);
    if (source != null) {
      final updated = source.copyWith(
        unreadCount: unreadCount,
        postCount: posts.length,
      );
      await _storage!.writeSource('rss', updated);
    }
  }

  // ============ RSS Post Operations ============

  /// Get posts for an RSS source
  Future<List<RssPost>> getPosts(String sourceId) async {
    if (_storage == null) return [];
    return _storage!.listPosts(sourceId);
  }

  /// Get a specific post
  Future<RssPost?> getPost(String sourceId, String postSlug) async {
    if (_storage == null) return null;
    return _storage!.readPost(sourceId, postSlug);
  }

  /// Get post content (markdown)
  Future<String?> getPostContent(String sourceId, String postSlug) async {
    if (_storage == null) return null;
    return _storage!.readPostContent(sourceId, postSlug);
  }

  /// Mark post as read
  Future<bool> markPostRead(String sourceId, String postSlug) async {
    if (_storage == null) return false;

    final post = await _storage!.readPost(sourceId, postSlug);
    if (post == null) return false;

    post.isRead = true;
    final success = await _storage!.writePost(sourceId, postSlug, post);

    if (success) {
      // Update progress
      final progressKey = 'rss/$sourceId/posts/$postSlug';
      _progress!.updateRssProgress(
        progressKey,
        RssProgress(isRead: true, readAt: DateTime.now()),
      );
      await _storage!.writeProgress(_progress!);

      await _updateSourceUnreadCount(sourceId);
      _notifyChange(ReaderChangeType.postRead, sourceId: sourceId);
    }

    return success;
  }

  /// Toggle post starred status
  Future<bool> togglePostStarred(String sourceId, String postSlug) async {
    if (_storage == null) return false;

    final post = await _storage!.readPost(sourceId, postSlug);
    if (post == null) return false;

    post.isStarred = !post.isStarred;
    return _storage!.writePost(sourceId, postSlug, post);
  }

  /// Delete a post
  Future<bool> deletePost(String sourceId, String postSlug) async {
    if (_storage == null) return false;

    final success = await _storage!.deletePost(sourceId, postSlug);
    if (success) {
      await _updateSourceUnreadCount(sourceId);
      _notifyChange(ReaderChangeType.postDeleted, sourceId: sourceId);
    }
    return success;
  }

  // ============ Manga Operations ============

  /// Get manga series for a source
  Future<List<Manga>> getMangaSeries(String sourceId) async {
    if (_storage == null) return [];
    return _storage!.listManga(sourceId);
  }

  /// Get a specific manga
  Future<Manga?> getManga(String sourceId, String mangaSlug) async {
    if (_storage == null) return null;
    return _storage!.readManga(sourceId, mangaSlug);
  }

  /// Get chapters for a manga
  Future<List<MangaChapter>> getMangaChapters(
      String sourceId, String mangaSlug) async {
    if (_storage == null) return [];
    return _storage!.listChapters(sourceId, mangaSlug);
  }

  /// Get chapter file path
  String? getChapterPath(
      String sourceId, String mangaSlug, String filename) {
    if (_storage == null) return null;
    return _storage!.getChapterPath(sourceId, mangaSlug, filename);
  }

  /// Get pages from a chapter
  Future<List<MangaPage>> getChapterPages(String chapterPath) async {
    return MangaService().extractPages(chapterPath);
  }

  /// Update manga reading progress
  Future<bool> updateMangaProgress(
    String sourceId,
    String mangaSlug,
    String chapter,
    int page,
  ) async {
    if (_storage == null) return false;

    final progressKey = 'manga/$sourceId/series/$mangaSlug';
    var mangaProgress = _progress!.getMangaProgress(progressKey);

    if (mangaProgress == null) {
      mangaProgress = MangaProgress();
    }

    mangaProgress.updatePosition(chapter, page);
    _progress!.updateMangaProgress(progressKey, mangaProgress);

    return _storage!.writeProgress(_progress!);
  }

  /// Mark chapter as read
  Future<bool> markChapterRead(
    String sourceId,
    String mangaSlug,
    String chapter,
  ) async {
    if (_storage == null) return false;

    final progressKey = 'manga/$sourceId/series/$mangaSlug';
    var mangaProgress = _progress!.getMangaProgress(progressKey);

    if (mangaProgress == null) {
      mangaProgress = MangaProgress();
    }

    mangaProgress.markChapterRead(chapter);
    _progress!.updateMangaProgress(progressKey, mangaProgress);

    final success = await _storage!.writeProgress(_progress!);
    if (success) {
      _notifyChange(ReaderChangeType.chapterRead,
          sourceId: sourceId, mangaSlug: mangaSlug);
    }
    return success;
  }

  /// Get manga progress
  MangaProgress? getMangaProgress(String sourceId, String mangaSlug) {
    final progressKey = 'manga/$sourceId/series/$mangaSlug';
    return _progress?.getMangaProgress(progressKey);
  }

  // ============ Books Operations ============

  /// Get book folders
  Future<List<BookFolder>> getBookFolders(List<String> parentPath) async {
    if (_storage == null) return [];
    return _storage!.listBookFolders(parentPath);
  }

  /// Get books in a folder
  Future<List<Book>> getBooks(List<String> folderPath) async {
    if (_storage == null) return [];
    return _storage!.listBooks(folderPath);
  }

  /// Update book reading progress
  Future<bool> updateBookProgress(String bookPath, BookPosition position) async {
    if (_storage == null) return false;

    var bookProgress = _progress!.getBookProgress(bookPath);

    if (bookProgress == null) {
      bookProgress = BookProgress(position: position);
    } else {
      bookProgress.updatePosition(position);
    }

    _progress!.updateBookProgress(bookPath, bookProgress);

    return _storage!.writeProgress(_progress!);
  }

  /// Get book progress
  BookProgress? getBookProgress(String bookPath) {
    return _progress?.getBookProgress(bookPath);
  }

  /// Add reading time to book
  Future<bool> addBookReadingTime(String bookPath, int seconds) async {
    if (_storage == null) return false;

    var bookProgress = _progress!.getBookProgress(bookPath);
    if (bookProgress == null) return false;

    bookProgress.addReadingTime(seconds);
    _progress!.updateBookProgress(bookPath, bookProgress);

    return _storage!.writeProgress(_progress!);
  }

  // ============ Helper Methods ============

  void _notifyChange(
    ReaderChangeType type, {
    String? sourceId,
    String? mangaSlug,
    String? postSlug,
  }) {
    _changesController.add(ReaderChange(
      type: type,
      sourceId: sourceId,
      mangaSlug: mangaSlug,
      postSlug: postSlug,
    ));
  }

  void dispose() {
    _changesController.close();
    MangaService().clearCache();
  }
}

/// Types of reader changes
enum ReaderChangeType {
  settingsUpdated,
  sourceRefreshed,
  sourceAdded,
  sourceDeleted,
  postRead,
  postDeleted,
  chapterRead,
  bookProgressUpdated,
}

/// Represents a reader change event
class ReaderChange {
  final ReaderChangeType type;
  final String? sourceId;
  final String? mangaSlug;
  final String? postSlug;
  final DateTime timestamp;

  ReaderChange({
    required this.type,
    this.sourceId,
    this.mangaSlug,
    this.postSlug,
  }) : timestamp = DateTime.now();
}
