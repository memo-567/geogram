/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/reader_models.dart';
import '../../services/log_service.dart';

/// Service for handling manga CBZ files
class MangaService {
  static final MangaService _instance = MangaService._internal();
  factory MangaService() => _instance;
  MangaService._internal();

  // Cache for extracted pages
  final Map<String, List<MangaPage>> _pageCache = {};
  static const int _maxCacheSize = 5; // Keep pages from 5 chapters in memory

  /// Extract pages from a CBZ file
  Future<List<MangaPage>> extractPages(String cbzPath) async {
    // Check cache
    if (_pageCache.containsKey(cbzPath)) {
      return _pageCache[cbzPath]!;
    }

    try {
      final file = File(cbzPath);
      if (!await file.exists()) {
        throw Exception('CBZ file not found: $cbzPath');
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final pages = <MangaPage>[];

      for (final entry in archive) {
        if (entry.isFile && _isImageFile(entry.name)) {
          final data = entry.content as List<int>;
          pages.add(MangaPage(
            filename: entry.name,
            data: Uint8List.fromList(data),
          ));
        }
      }

      // Sort pages by filename (alphanumeric)
      pages.sort((a, b) => _compareFilenames(a.filename, b.filename));

      // Update cache
      _addToCache(cbzPath, pages);

      return pages;
    } catch (e) {
      LogService().log('MangaService: Error extracting pages: $e');
      rethrow;
    }
  }

  /// Get a single page from a CBZ file
  Future<MangaPage?> getPage(String cbzPath, int pageIndex) async {
    final pages = await extractPages(cbzPath);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return null;
    }
    return pages[pageIndex];
  }

  /// Get page count for a CBZ file
  Future<int> getPageCount(String cbzPath) async {
    try {
      final file = File(cbzPath);
      if (!await file.exists()) return 0;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      int count = 0;
      for (final entry in archive) {
        if (entry.isFile && _isImageFile(entry.name)) {
          count++;
        }
      }
      return count;
    } catch (e) {
      LogService().log('MangaService: Error getting page count: $e');
      return 0;
    }
  }

  /// Create a CBZ file from a list of image files
  Future<bool> createCbz(String cbzPath, List<String> imagePaths) async {
    try {
      final archive = Archive();

      for (int i = 0; i < imagePaths.length; i++) {
        final imagePath = imagePaths[i];
        final file = File(imagePath);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        final ext = imagePath.split('.').last.toLowerCase();
        final filename = '${(i + 1).toString().padLeft(3, '0')}.$ext';

        archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        throw Exception('Failed to encode CBZ archive');
      }

      final outputFile = File(cbzPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(encoded);

      return true;
    } catch (e) {
      LogService().log('MangaService: Error creating CBZ: $e');
      return false;
    }
  }

  /// Add images to an existing CBZ or create new
  Future<bool> addImagesToCbz(
      String cbzPath, List<Uint8List> images, List<String> filenames) async {
    try {
      Archive archive;

      // Load existing archive or create new
      final file = File(cbzPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        archive = ZipDecoder().decodeBytes(bytes);
      } else {
        archive = Archive();
      }

      // Find the highest existing page number
      int maxPage = 0;
      for (final entry in archive) {
        if (entry.isFile && _isImageFile(entry.name)) {
          final match = RegExp(r'^(\d+)').firstMatch(entry.name);
          if (match != null) {
            final num = int.tryParse(match.group(1)!) ?? 0;
            if (num > maxPage) maxPage = num;
          }
        }
      }

      // Add new images
      for (int i = 0; i < images.length; i++) {
        final pageNum = maxPage + i + 1;
        final ext = filenames[i].split('.').last.toLowerCase();
        final filename = '${pageNum.toString().padLeft(3, '0')}.$ext';
        archive.addFile(ArchiveFile(filename, images[i].length, images[i]));
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        throw Exception('Failed to encode CBZ archive');
      }

      await file.parent.create(recursive: true);
      await file.writeAsBytes(encoded);

      // Invalidate cache
      _pageCache.remove(cbzPath);

      return true;
    } catch (e) {
      LogService().log('MangaService: Error adding images to CBZ: $e');
      return false;
    }
  }

  /// Extract thumbnail (first page) from a CBZ file
  Future<Uint8List?> extractThumbnail(String cbzPath) async {
    try {
      final pages = await extractPages(cbzPath);
      if (pages.isEmpty) return null;
      return pages.first.data;
    } catch (e) {
      LogService().log('MangaService: Error extracting thumbnail: $e');
      return null;
    }
  }

  /// Check if a file is an image
  bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  /// Compare filenames for sorting (handles numeric ordering)
  int _compareFilenames(String a, String b) {
    // Extract numbers for natural sorting
    final numA = _extractNumber(a);
    final numB = _extractNumber(b);

    if (numA != null && numB != null) {
      return numA.compareTo(numB);
    }

    return a.compareTo(b);
  }

  /// Extract number from filename for sorting
  int? _extractNumber(String filename) {
    // Remove extension
    final noExt = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
    // Find number
    final match = RegExp(r'(\d+)').firstMatch(noExt);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Add pages to cache with size limit
  void _addToCache(String cbzPath, List<MangaPage> pages) {
    // Remove oldest entries if cache is full
    while (_pageCache.length >= _maxCacheSize) {
      _pageCache.remove(_pageCache.keys.first);
    }
    _pageCache[cbzPath] = pages;
  }

  /// Clear page cache
  void clearCache() {
    _pageCache.clear();
  }

  /// Preload pages for a chapter
  Future<void> preloadChapter(String cbzPath) async {
    if (!_pageCache.containsKey(cbzPath)) {
      await extractPages(cbzPath);
    }
  }
}

/// A single page from a manga chapter
class MangaPage {
  final String filename;
  final Uint8List data;

  MangaPage({
    required this.filename,
    required this.data,
  });

  String get extension => filename.split('.').last.toLowerCase();

  String get mimeType {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
}
