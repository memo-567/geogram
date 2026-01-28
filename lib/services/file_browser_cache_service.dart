/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../models/file_browser_cache_models.dart';
import 'log_service.dart';
import 'storage_config.dart';

/// Singleton service for caching file browser data persistently
///
/// Provides caching for:
/// - Directory listings (file names, sizes, modification times)
/// - Folder size calculations
/// - Video thumbnails (stored in ZIP archives per volume)
///
/// Cache is organized by volume (internal, USB drives, SD cards) to allow
/// independent invalidation when volumes are unmounted.
class FileBrowserCacheService {
  static final FileBrowserCacheService _instance =
      FileBrowserCacheService._internal();
  factory FileBrowserCacheService() => _instance;
  FileBrowserCacheService._internal();

  String? _cacheDir;
  bool _initialized = false;

  // In-memory caches loaded from disk
  final Map<String, VolumeCacheFile> _volumeCaches = {};
  final Map<String, ThumbnailMetaFile> _thumbnailMetas = {};

  // Pending writes for batching
  final Set<String> _dirtyVolumes = {};
  final Set<String> _dirtyThumbnailMetas = {};
  bool _flushScheduled = false;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      LogService().log('FileBrowserCacheService: Web platform, disabled');
      _initialized = true;
      return;
    }

    try {
      _cacheDir = StorageConfig().fileBrowserCacheDir;
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _initialized = true;
      LogService().log('FileBrowserCacheService initialized at: $_cacheDir');
    } catch (e) {
      LogService().log('Error initializing FileBrowserCacheService: $e');
    }
  }

  /// Get the volume ID for a given path
  ///
  /// Examples:
  /// - /home/user/... -> "internal"
  /// - /media/user/USB_NAME/... -> "media_USB_NAME"
  /// - /storage/emulated/0/... -> "internal"
  /// - /storage/XXXX-XXXX/... -> "sdcard_XXXX-XXXX"
  String getVolumeId(String path) {
    // Android
    if (path.startsWith('/storage/emulated/0')) {
      return 'internal';
    }

    // Android SD card pattern: /storage/XXXX-XXXX
    final sdcardMatch = RegExp(r'/storage/([A-F0-9]{4}-[A-F0-9]{4})').firstMatch(path);
    if (sdcardMatch != null) {
      return 'sdcard_${sdcardMatch.group(1)}';
    }

    // Linux home directory
    final home = Platform.environment['HOME'];
    if (home != null && path.startsWith(home)) {
      return 'internal';
    }

    // Linux /media mounts
    final mediaMatch = RegExp(r'/media/[^/]+/([^/]+)').firstMatch(path);
    if (mediaMatch != null) {
      return 'media_${mediaMatch.group(1)}';
    }

    // Linux /mnt mounts
    final mntMatch = RegExp(r'/mnt/([^/]+)').firstMatch(path);
    if (mntMatch != null) {
      return 'mnt_${mntMatch.group(1)}';
    }

    // Linux /run/media mounts (Fedora, Arch, etc.)
    final runMediaMatch = RegExp(r'/run/media/[^/]+/([^/]+)').firstMatch(path);
    if (runMediaMatch != null) {
      return 'media_${runMediaMatch.group(1)}';
    }

    return 'default';
  }

  /// Get the cache file path for a volume's directory listings
  String _getVolumeCacheFilePath(String volumeId) {
    return p.join(_cacheDir!, 'files_$volumeId.json');
  }

  /// Get the thumbnail metadata file path for a volume
  String _getThumbnailMetaFilePath(String volumeId) {
    return p.join(_cacheDir!, 'thumbnails_${volumeId}_meta.json');
  }

  /// Get the thumbnail ZIP archive path for a volume
  String _getThumbnailZipPath(String volumeId) {
    return p.join(_cacheDir!, 'thumbnails_$volumeId.zip');
  }

  /// Generate a hash key for a file path (for thumbnail naming)
  String _hashPath(String path) {
    return sha1.convert(utf8.encode(path)).toString();
  }

  /// Load volume cache from disk if not already loaded
  Future<VolumeCacheFile> _loadVolumeCache(String volumeId) async {
    if (_volumeCaches.containsKey(volumeId)) {
      return _volumeCaches[volumeId]!;
    }

    final filePath = _getVolumeCacheFilePath(volumeId);
    final file = File(filePath);

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final cache = VolumeCacheFile.fromJson(json);
        _volumeCaches[volumeId] = cache;
        return cache;
      } catch (e) {
        LogService().log('Error loading volume cache $volumeId: $e');
      }
    }

    // Create new empty cache
    final cache = VolumeCacheFile(
      version: 1,
      volumeId: volumeId,
      directories: {},
    );
    _volumeCaches[volumeId] = cache;
    return cache;
  }

  /// Load thumbnail metadata from disk if not already loaded
  Future<ThumbnailMetaFile> _loadThumbnailMeta(String volumeId) async {
    if (_thumbnailMetas.containsKey(volumeId)) {
      return _thumbnailMetas[volumeId]!;
    }

    final filePath = _getThumbnailMetaFilePath(volumeId);
    final file = File(filePath);

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final meta = ThumbnailMetaFile.fromJson(json);
        _thumbnailMetas[volumeId] = meta;
        return meta;
      } catch (e) {
        LogService().log('Error loading thumbnail meta $volumeId: $e');
      }
    }

    // Create new empty metadata
    final meta = ThumbnailMetaFile(
      version: 1,
      volumeId: volumeId,
      thumbnails: {},
    );
    _thumbnailMetas[volumeId] = meta;
    return meta;
  }

  /// Get cached directory listing
  Future<DirectoryCache?> getDirectoryCache(String path) async {
    if (kIsWeb || _cacheDir == null) return null;

    final volumeId = getVolumeId(path);
    final cache = await _loadVolumeCache(volumeId);
    return cache.directories[path];
  }

  /// Save directory cache
  Future<void> saveDirectoryCache(
    String path,
    List<CachedFileEntry> entries,
    DateTime dirModified,
  ) async {
    if (kIsWeb || _cacheDir == null) return;

    final volumeId = getVolumeId(path);
    final cache = await _loadVolumeCache(volumeId);

    // Calculate total size
    int totalSize = 0;
    for (final entry in entries) {
      totalSize += entry.size;
    }

    final dirCache = DirectoryCache(
      path: path,
      lastScanned: DateTime.now(),
      directoryModified: dirModified,
      totalSize: totalSize,
      entries: entries,
    );

    // Update in-memory cache
    final newDirectories = Map<String, DirectoryCache>.from(cache.directories);
    newDirectories[path] = dirCache;
    _volumeCaches[volumeId] = VolumeCacheFile(
      version: cache.version,
      volumeId: volumeId,
      directories: newDirectories,
    );

    // Mark for flush
    _dirtyVolumes.add(volumeId);
    _scheduleFlush();
  }

  /// Check if directory cache is valid (not stale)
  Future<bool> isCacheValid(String path) async {
    if (kIsWeb || _cacheDir == null) return false;

    final cache = await getDirectoryCache(path);
    if (cache == null) return false;

    try {
      final dir = Directory(path);
      final stat = await dir.stat();
      return !cache.isStale(stat.modified);
    } catch (e) {
      return false;
    }
  }

  /// Get cached folder size
  Future<int?> getCachedFolderSize(String folderPath) async {
    if (kIsWeb || _cacheDir == null) return null;

    final parentPath = p.dirname(folderPath);
    final cache = await getDirectoryCache(parentPath);
    if (cache == null) return null;

    final entry = cache.entries.where((e) => e.path == folderPath).firstOrNull;
    return entry?.size;
  }

  /// Save folder size to cache
  Future<void> saveFolderSize(String folderPath, int size) async {
    if (kIsWeb || _cacheDir == null) return;

    final parentPath = p.dirname(folderPath);
    final volumeId = getVolumeId(parentPath);
    final cache = await _loadVolumeCache(volumeId);
    final dirCache = cache.directories[parentPath];

    if (dirCache == null) return;

    // Update the entry with new size
    final updatedEntries = dirCache.entries.map((entry) {
      if (entry.path == folderPath) {
        return CachedFileEntry(
          name: entry.name,
          path: entry.path,
          isDirectory: entry.isDirectory,
          size: size,
          modified: entry.modified,
        );
      }
      return entry;
    }).toList();

    final updatedDirCache = DirectoryCache(
      path: dirCache.path,
      lastScanned: dirCache.lastScanned,
      directoryModified: dirCache.directoryModified,
      totalSize: updatedEntries.fold(0, (sum, e) => sum + e.size),
      entries: updatedEntries,
    );

    final newDirectories = Map<String, DirectoryCache>.from(cache.directories);
    newDirectories[parentPath] = updatedDirCache;
    _volumeCaches[volumeId] = VolumeCacheFile(
      version: cache.version,
      volumeId: volumeId,
      directories: newDirectories,
    );

    _dirtyVolumes.add(volumeId);
    _scheduleFlush();
  }

  /// Check if a thumbnail exists in the cache
  Future<bool> hasThumbnail(String filePath, DateTime sourceModified) async {
    if (kIsWeb || _cacheDir == null) return false;

    final volumeId = getVolumeId(filePath);
    final meta = await _loadThumbnailMeta(volumeId);
    final hashKey = _hashPath(filePath);
    final thumbMeta = meta.thumbnails[hashKey];

    if (thumbMeta == null) return false;

    // Check if source file has been modified
    return !thumbMeta.sourceModified.isBefore(sourceModified);
  }

  /// Get thumbnail from cache, extracting from ZIP to temp directory
  Future<String?> getThumbnailTempPath(String filePath) async {
    if (kIsWeb || _cacheDir == null) return null;

    final volumeId = getVolumeId(filePath);
    final hashKey = _hashPath(filePath);
    final meta = await _loadThumbnailMeta(volumeId);
    final thumbMeta = meta.thumbnails[hashKey];

    if (thumbMeta == null) return null;

    // Check if already extracted to temp
    final tempPath = p.join(
      Directory.systemTemp.path,
      'geogram_thumbs',
      '$hashKey.${thumbMeta.extension}',
    );
    final tempFile = File(tempPath);

    if (await tempFile.exists()) {
      return tempPath;
    }

    // Extract from ZIP
    final zipPath = _getThumbnailZipPath(volumeId);
    final zipFile = File(zipPath);

    if (!await zipFile.exists()) return null;

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final thumbFileName = '$hashKey.${thumbMeta.extension}';
      for (final file in archive) {
        if (file.name == thumbFileName && file.isFile) {
          // Ensure temp directory exists
          final tempDir = Directory(p.dirname(tempPath));
          if (!await tempDir.exists()) {
            await tempDir.create(recursive: true);
          }

          // Write extracted thumbnail
          await tempFile.writeAsBytes(file.content as List<int>);
          return tempPath;
        }
      }
    } catch (e) {
      LogService().log('Error extracting thumbnail from ZIP: $e');
    }

    return null;
  }

  /// Save a thumbnail to the cache
  Future<void> saveThumbnail(
    String filePath,
    Uint8List bytes,
    DateTime sourceModified, {
    String extension = 'png',
  }) async {
    if (kIsWeb || _cacheDir == null) return;

    final volumeId = getVolumeId(filePath);
    final hashKey = _hashPath(filePath);

    // Update metadata
    final meta = await _loadThumbnailMeta(volumeId);
    final thumbMeta = ThumbnailMeta(
      sourcePath: filePath,
      sourceModified: sourceModified,
      extension: extension,
      hashKey: hashKey,
    );

    final newThumbnails = Map<String, ThumbnailMeta>.from(meta.thumbnails);
    newThumbnails[hashKey] = thumbMeta;
    _thumbnailMetas[volumeId] = ThumbnailMetaFile(
      version: meta.version,
      volumeId: volumeId,
      thumbnails: newThumbnails,
    );

    // Save to temp file for immediate use
    final tempPath = p.join(
      Directory.systemTemp.path,
      'geogram_thumbs',
      '$hashKey.$extension',
    );
    final tempDir = Directory(p.dirname(tempPath));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    await File(tempPath).writeAsBytes(bytes);

    // Add to ZIP archive
    await _addToThumbnailZip(volumeId, hashKey, extension, bytes);

    // Mark metadata for flush
    _dirtyThumbnailMetas.add(volumeId);
    _scheduleFlush();
  }

  /// Add a thumbnail to the volume's ZIP archive
  Future<void> _addToThumbnailZip(
    String volumeId,
    String hashKey,
    String extension,
    Uint8List bytes,
  ) async {
    final zipPath = _getThumbnailZipPath(volumeId);
    final zipFile = File(zipPath);

    Archive archive;
    if (await zipFile.exists()) {
      try {
        final existingBytes = await zipFile.readAsBytes();
        archive = ZipDecoder().decodeBytes(existingBytes);
      } catch (e) {
        LogService().log('Error reading existing ZIP, creating new: $e');
        archive = Archive();
      }
    } else {
      archive = Archive();
    }

    // Remove existing file with same name if present
    final fileName = '$hashKey.$extension';
    archive.files.removeWhere((f) => f.name == fileName);

    // Add new file
    final archiveFile = ArchiveFile(fileName, bytes.length, bytes);
    archive.addFile(archiveFile);

    // Encode and save
    final encoded = ZipEncoder().encode(archive);
    if (encoded != null) {
      await zipFile.writeAsBytes(encoded);
    }
  }

  /// Schedule a flush to disk (debounced)
  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;

    Future.delayed(const Duration(seconds: 2), () {
      _flushScheduled = false;
      flush();
    });
  }

  /// Flush all pending changes to disk
  Future<void> flush() async {
    if (kIsWeb || _cacheDir == null) return;

    // Flush dirty volume caches
    for (final volumeId in _dirtyVolumes.toList()) {
      final cache = _volumeCaches[volumeId];
      if (cache != null) {
        try {
          final filePath = _getVolumeCacheFilePath(volumeId);
          final json = const JsonEncoder.withIndent('  ').convert(cache.toJson());
          await File(filePath).writeAsString(json);
        } catch (e) {
          LogService().log('Error flushing volume cache $volumeId: $e');
        }
      }
    }
    _dirtyVolumes.clear();

    // Flush dirty thumbnail metadata
    for (final volumeId in _dirtyThumbnailMetas.toList()) {
      final meta = _thumbnailMetas[volumeId];
      if (meta != null) {
        try {
          final filePath = _getThumbnailMetaFilePath(volumeId);
          final json = const JsonEncoder.withIndent('  ').convert(meta.toJson());
          await File(filePath).writeAsString(json);
        } catch (e) {
          LogService().log('Error flushing thumbnail meta $volumeId: $e');
        }
      }
    }
    _dirtyThumbnailMetas.clear();
  }

  /// Clear all cache data for a specific volume
  Future<void> clearVolumeCache(String volumeId) async {
    if (kIsWeb || _cacheDir == null) return;

    // Clear in-memory
    _volumeCaches.remove(volumeId);
    _thumbnailMetas.remove(volumeId);
    _dirtyVolumes.remove(volumeId);
    _dirtyThumbnailMetas.remove(volumeId);

    // Delete files
    try {
      final cacheFile = File(_getVolumeCacheFilePath(volumeId));
      if (await cacheFile.exists()) await cacheFile.delete();

      final metaFile = File(_getThumbnailMetaFilePath(volumeId));
      if (await metaFile.exists()) await metaFile.delete();

      final zipFile = File(_getThumbnailZipPath(volumeId));
      if (await zipFile.exists()) await zipFile.delete();

      LogService().log('Cleared cache for volume: $volumeId');
    } catch (e) {
      LogService().log('Error clearing volume cache $volumeId: $e');
    }
  }

  /// Clear all cache data
  Future<void> clearAllCaches() async {
    if (kIsWeb || _cacheDir == null) return;

    _volumeCaches.clear();
    _thumbnailMetas.clear();
    _dirtyVolumes.clear();
    _dirtyThumbnailMetas.clear();

    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      LogService().log('Cleared all file browser caches');
    } catch (e) {
      LogService().log('Error clearing all caches: $e');
    }
  }
}
