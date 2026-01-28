/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import '../widgets/file_folder_picker.dart' show FileSystemItem;
import 'dart:io';

/// Cached directory listing with metadata for invalidation
class DirectoryCache {
  final String path;
  final DateTime lastScanned;
  final DateTime directoryModified;
  final int totalSize;
  final List<CachedFileEntry> entries;

  const DirectoryCache({
    required this.path,
    required this.lastScanned,
    required this.directoryModified,
    required this.totalSize,
    required this.entries,
  });

  /// Check if this cache is stale compared to the current directory modification time
  bool isStale(DateTime currentDirModified) =>
      directoryModified.isBefore(currentDirModified);

  factory DirectoryCache.fromJson(Map<String, dynamic> json) {
    return DirectoryCache(
      path: json['path'] as String,
      lastScanned: DateTime.parse(json['lastScanned'] as String),
      directoryModified: DateTime.parse(json['directoryModified'] as String),
      totalSize: json['totalSize'] as int? ?? 0,
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => CachedFileEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'lastScanned': lastScanned.toIso8601String(),
        'directoryModified': directoryModified.toIso8601String(),
        'totalSize': totalSize,
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

/// Cached file/folder entry with size and modification time
class CachedFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  const CachedFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  /// Convert to FileSystemItem for use in FileFolderPicker
  FileSystemItem toFileSystemItem() => FileSystemItem(
        path: path,
        name: name,
        isDirectory: isDirectory,
        size: size,
        modified: modified,
        type: isDirectory
            ? FileSystemEntityType.directory
            : FileSystemEntityType.file,
      );

  factory CachedFileEntry.fromFileSystemItem(FileSystemItem item) =>
      CachedFileEntry(
        name: item.name,
        path: item.path,
        isDirectory: item.isDirectory,
        size: item.size,
        modified: item.modified,
      );

  factory CachedFileEntry.fromJson(Map<String, dynamic> json) {
    return CachedFileEntry(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool? ?? false,
      size: json['size'] as int? ?? 0,
      modified: DateTime.parse(json['modified'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'isDirectory': isDirectory,
        'size': size,
        'modified': modified.toIso8601String(),
      };
}

/// Metadata for a cached thumbnail
class ThumbnailMeta {
  final String sourcePath;
  final DateTime sourceModified;
  final String extension;
  final String hashKey;

  const ThumbnailMeta({
    required this.sourcePath,
    required this.sourceModified,
    required this.extension,
    required this.hashKey,
  });

  factory ThumbnailMeta.fromJson(Map<String, dynamic> json) {
    return ThumbnailMeta(
      sourcePath: json['sourcePath'] as String,
      sourceModified: DateTime.parse(json['sourceModified'] as String),
      extension: json['extension'] as String? ?? 'png',
      hashKey: json['hashKey'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'sourceModified': sourceModified.toIso8601String(),
        'extension': extension,
        'hashKey': hashKey,
      };
}

/// Root structure for volume cache file
class VolumeCacheFile {
  final int version;
  final String volumeId;
  final Map<String, DirectoryCache> directories;

  const VolumeCacheFile({
    required this.version,
    required this.volumeId,
    required this.directories,
  });

  factory VolumeCacheFile.fromJson(Map<String, dynamic> json) {
    final dirJson = json['directories'] as Map<String, dynamic>? ?? {};
    final directories = <String, DirectoryCache>{};
    for (final entry in dirJson.entries) {
      directories[entry.key] =
          DirectoryCache.fromJson(entry.value as Map<String, dynamic>);
    }
    return VolumeCacheFile(
      version: json['version'] as int? ?? 1,
      volumeId: json['volumeId'] as String? ?? 'default',
      directories: directories,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'volumeId': volumeId,
        'directories':
            directories.map((key, value) => MapEntry(key, value.toJson())),
      };
}

/// Root structure for thumbnail metadata file
class ThumbnailMetaFile {
  final int version;
  final String volumeId;
  final Map<String, ThumbnailMeta> thumbnails;

  const ThumbnailMetaFile({
    required this.version,
    required this.volumeId,
    required this.thumbnails,
  });

  factory ThumbnailMetaFile.fromJson(Map<String, dynamic> json) {
    final thumbJson = json['thumbnails'] as Map<String, dynamic>? ?? {};
    final thumbnails = <String, ThumbnailMeta>{};
    for (final entry in thumbJson.entries) {
      thumbnails[entry.key] =
          ThumbnailMeta.fromJson(entry.value as Map<String, dynamic>);
    }
    return ThumbnailMetaFile(
      version: json['version'] as int? ?? 1,
      volumeId: json['volumeId'] as String? ?? 'default',
      thumbnails: thumbnails,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'volumeId': volumeId,
        'thumbnails':
            thumbnails.map((key, value) => MapEntry(key, value.toJson())),
      };
}
