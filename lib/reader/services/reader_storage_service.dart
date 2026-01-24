/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import '../models/reader_models.dart';
import '../utils/reader_path_utils.dart';
import '../../services/log_service.dart';

/// Service for handling reader file I/O operations
class ReaderStorageService {
  final String basePath;

  ReaderStorageService(this.basePath);

  // ============ Settings Operations ============

  /// Read reader settings
  Future<ReaderSettings> readSettings() async {
    try {
      final filePath = ReaderPathUtils.settingsFile(basePath);
      final file = File(filePath);
      if (!await file.exists()) {
        return ReaderSettings();
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ReaderSettings.fromJson(json);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading settings: $e');
      return ReaderSettings();
    }
  }

  /// Write reader settings
  Future<bool> writeSettings(ReaderSettings settings) async {
    try {
      final filePath = ReaderPathUtils.settingsFile(basePath);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error writing settings: $e');
      return false;
    }
  }

  // ============ Progress Operations ============

  /// Read reading progress
  Future<ReadingProgress> readProgress() async {
    try {
      final filePath = ReaderPathUtils.progressFile(basePath);
      final file = File(filePath);
      if (!await file.exists()) {
        return ReadingProgress();
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ReadingProgress.fromJson(json);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading progress: $e');
      return ReadingProgress();
    }
  }

  /// Write reading progress
  Future<bool> writeProgress(ReadingProgress progress) async {
    try {
      final filePath = ReaderPathUtils.progressFile(basePath);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      progress.lastUpdated = DateTime.now();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(progress.toJson()),
      );
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error writing progress: $e');
      return false;
    }
  }

  // ============ Source Operations ============

  /// List sources in a category
  Future<List<Source>> listSources(String category) async {
    try {
      final dirPath = '$basePath/$category';
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final sources = <Source>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final sourceId = entity.path.split('/').last;
          final source = await readSource(category, sourceId);
          if (source != null) {
            sources.add(source);
          }
        }
      }
      return sources;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing sources: $e');
      return [];
    }
  }

  /// Read source metadata
  Future<Source?> readSource(String category, String sourceId) async {
    try {
      final dataPath =
          ReaderPathUtils.sourceDataFile(basePath, category, sourceId);
      final file = File(dataPath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final sourcePath =
          ReaderPathUtils.sourceDir(basePath, category, sourceId);
      return Source.fromJson(json, sourcePath);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading source: $e');
      return null;
    }
  }

  /// Write source metadata
  Future<bool> writeSource(String category, Source source) async {
    try {
      final dataPath =
          ReaderPathUtils.sourceDataFile(basePath, category, source.id);
      final file = File(dataPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(source.toJson()),
      );
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error writing source: $e');
      return false;
    }
  }

  /// Check if source.js exists
  Future<bool> sourceJsExists(String category, String sourceId) async {
    final jsPath = ReaderPathUtils.sourceJsFile(basePath, category, sourceId);
    return File(jsPath).exists();
  }

  /// Read source.js content
  Future<String?> readSourceJs(String category, String sourceId) async {
    try {
      final jsPath = ReaderPathUtils.sourceJsFile(basePath, category, sourceId);
      final file = File(jsPath);
      if (!await file.exists()) return null;
      return file.readAsString();
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading source.js: $e');
      return null;
    }
  }

  // ============ RSS Post Operations ============

  /// List posts for an RSS source
  Future<List<RssPost>> listPosts(String sourceId) async {
    try {
      final dirPath = ReaderPathUtils.postsDir(basePath, sourceId);
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final posts = <RssPost>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final postSlug = entity.path.split('/').last;
          final post = await readPost(sourceId, postSlug);
          if (post != null) {
            posts.add(post);
          }
        }
      }

      // Sort by published date, newest first
      posts.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return posts;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing posts: $e');
      return [];
    }
  }

  /// Read a post
  Future<RssPost?> readPost(String sourceId, String postSlug) async {
    try {
      final dataPath =
          ReaderPathUtils.postDataFile(basePath, sourceId, postSlug);
      final file = File(dataPath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return RssPost.fromJson(json);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading post: $e');
      return null;
    }
  }

  /// Write a post
  Future<bool> writePost(String sourceId, String postSlug, RssPost post) async {
    try {
      final dataPath =
          ReaderPathUtils.postDataFile(basePath, sourceId, postSlug);
      final file = File(dataPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(post.toJson()),
      );
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error writing post: $e');
      return false;
    }
  }

  /// Read post content (markdown)
  Future<String?> readPostContent(String sourceId, String postSlug) async {
    try {
      final contentPath =
          ReaderPathUtils.postContentFile(basePath, sourceId, postSlug);
      final file = File(contentPath);
      if (!await file.exists()) return null;
      return file.readAsString();
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading post content: $e');
      return null;
    }
  }

  /// Write post content (markdown)
  Future<bool> writePostContent(
      String sourceId, String postSlug, String content) async {
    try {
      final contentPath =
          ReaderPathUtils.postContentFile(basePath, sourceId, postSlug);
      final file = File(contentPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return true;
    } catch (e) {
      LogService()
          .log('ReaderStorageService: Error writing post content: $e');
      return false;
    }
  }

  /// Delete a post
  Future<bool> deletePost(String sourceId, String postSlug) async {
    try {
      final postPath = ReaderPathUtils.postDir(basePath, sourceId, postSlug);
      final dir = Directory(postPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error deleting post: $e');
      return false;
    }
  }

  // ============ Manga Operations ============

  /// List manga series for a source
  Future<List<Manga>> listManga(String sourceId) async {
    try {
      final dirPath = ReaderPathUtils.seriesDir(basePath, sourceId);
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final mangaList = <Manga>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final mangaSlug = entity.path.split('/').last;
          final manga = await readManga(sourceId, mangaSlug);
          if (manga != null) {
            mangaList.add(manga);
          }
        }
      }

      // Sort alphabetically by title
      mangaList.sort((a, b) => a.title.compareTo(b.title));
      return mangaList;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing manga: $e');
      return [];
    }
  }

  /// Read manga metadata
  Future<Manga?> readManga(String sourceId, String mangaSlug) async {
    try {
      final dataPath =
          ReaderPathUtils.mangaDataFile(basePath, sourceId, mangaSlug);
      final file = File(dataPath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Manga.fromJson(json);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading manga: $e');
      return null;
    }
  }

  /// Write manga metadata
  Future<bool> writeManga(
      String sourceId, String mangaSlug, Manga manga) async {
    try {
      final dataPath =
          ReaderPathUtils.mangaDataFile(basePath, sourceId, mangaSlug);
      final file = File(dataPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manga.toJson()),
      );
      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error writing manga: $e');
      return false;
    }
  }

  /// List chapters (CBZ files) for a manga
  Future<List<MangaChapter>> listChapters(
      String sourceId, String mangaSlug) async {
    try {
      final dirPath =
          ReaderPathUtils.mangaSeriesDir(basePath, sourceId, mangaSlug);
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final chapters = <MangaChapter>[];
      await for (final entity in dir.list()) {
        if (entity is File && ReaderPathUtils.isCbzFile(entity.path)) {
          final filename = entity.path.split('/').last;
          chapters.add(MangaChapter.fromFilename(filename));
        }
      }

      // Sort chapters
      chapters.sort((a, b) => a.compareTo(b));
      return chapters;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing chapters: $e');
      return [];
    }
  }

  /// Get chapter file path
  String getChapterPath(String sourceId, String mangaSlug, String filename) {
    return '${ReaderPathUtils.mangaSeriesDir(basePath, sourceId, mangaSlug)}/$filename';
  }

  // ============ Books Operations ============

  /// List folders in books directory
  Future<List<BookFolder>> listBookFolders(List<String> parentPath) async {
    try {
      final String dirPath;
      if (parentPath.isEmpty) {
        dirPath = ReaderPathUtils.booksDir(basePath);
      } else {
        dirPath = '${ReaderPathUtils.booksDir(basePath)}/${parentPath.join('/')}';
      }

      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final folders = <BookFolder>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final folderId = entity.path.split('/').last;
          final folderPath = [...parentPath, folderId];

          // Try to read folder.json
          final folder = await readBookFolder(folderPath);
          if (folder != null) {
            folders.add(folder);
          } else {
            // Create a basic folder entry
            folders.add(BookFolder(id: folderId, name: folderId));
          }
        }
      }

      // Sort alphabetically
      folders.sort((a, b) => a.name.compareTo(b.name));
      return folders;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing book folders: $e');
      return [];
    }
  }

  /// Read book folder metadata
  Future<BookFolder?> readBookFolder(List<String> folderPath) async {
    try {
      final filePath = ReaderPathUtils.booksFolderFile(basePath, folderPath);
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return BookFolder.fromJson(json, folderPath.last);
    } catch (e) {
      LogService().log('ReaderStorageService: Error reading book folder: $e');
      return null;
    }
  }

  /// List books in a folder
  Future<List<Book>> listBooks(List<String> folderPath) async {
    try {
      final String dirPath;
      if (folderPath.isEmpty) {
        dirPath = ReaderPathUtils.booksDir(basePath);
      } else {
        dirPath = '${ReaderPathUtils.booksDir(basePath)}/${folderPath.join('/')}';
      }

      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final books = <Book>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          final filename = entity.path.split('/').last;
          if (ReaderPathUtils.isSupportedBookFormat(filename)) {
            books.add(Book.fromFile(dirPath, filename));
          }
        }
      }

      // Sort alphabetically by title
      books.sort((a, b) => a.title.compareTo(b.title));
      return books;
    } catch (e) {
      LogService().log('ReaderStorageService: Error listing books: $e');
      return [];
    }
  }

  // ============ Initialization ============

  /// Initialize the reader directory structure
  Future<bool> initialize() async {
    try {
      final baseDir = Directory(basePath);
      await baseDir.create(recursive: true);

      // Create category directories
      await Directory(ReaderPathUtils.rssDir(basePath)).create(recursive: true);
      await Directory(ReaderPathUtils.mangaDir(basePath))
          .create(recursive: true);
      await Directory(ReaderPathUtils.booksDir(basePath))
          .create(recursive: true);

      return true;
    } catch (e) {
      LogService().log('ReaderStorageService: Error initializing: $e');
      return false;
    }
  }

  /// Check if the reader has been initialized
  Future<bool> isInitialized() async {
    try {
      final baseDir = Directory(basePath);
      return baseDir.exists();
    } catch (e) {
      return false;
    }
  }
}
