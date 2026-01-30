/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:path/path.dart' as path;

/// Path utilities for the music app
class MusicPathUtils {
  MusicPathUtils._();

  // File names
  static const settingsFile = 'settings.json';
  static const libraryFile = 'library.json';
  static const queueFile = 'queue.json';
  static const historyFile = 'history.json';

  // Folder names
  static const playlistsFolder = 'playlists';
  static const cacheFolder = 'cache';
  static const artworkCacheFolder = 'cache/artwork';

  // Album metadata files (saved in album folders)
  static const coverMetadataFile = 'cover.json';
  static const lyricsFile = 'lyrics.json';

  // Cover art file names (priority order)
  static const coverArtNames = [
    'cover.jpg',
    'cover.png',
    'folder.jpg',
    'folder.png',
    'front.jpg',
    'front.png',
    'album.jpg',
    'album.png',
    'artwork.jpg',
    'artwork.png',
  ];

  /// Get settings file path
  static String getSettingsPath(String basePath) {
    return path.join(basePath, settingsFile);
  }

  /// Get library file path
  static String getLibraryPath(String basePath) {
    return path.join(basePath, libraryFile);
  }

  /// Get queue file path
  static String getQueuePath(String basePath) {
    return path.join(basePath, queueFile);
  }

  /// Get history file path
  static String getHistoryPath(String basePath) {
    return path.join(basePath, historyFile);
  }

  /// Get playlists folder path
  static String getPlaylistsPath(String basePath) {
    return path.join(basePath, playlistsFolder);
  }

  /// Get playlist file path (.m3u8)
  static String getPlaylistFilePath(String basePath, String playlistId) {
    return path.join(basePath, playlistsFolder, '$playlistId.m3u8');
  }

  /// Get playlist metadata file path (.m3u8.json)
  static String getPlaylistMetadataPath(String basePath, String playlistId) {
    return path.join(basePath, playlistsFolder, '$playlistId.m3u8.json');
  }

  /// Get cache folder path
  static String getCachePath(String basePath) {
    return path.join(basePath, cacheFolder);
  }

  /// Get artwork cache folder path
  static String getArtworkCachePath(String basePath) {
    return path.join(basePath, artworkCacheFolder);
  }

  /// Get cached artwork path for an album
  static String getAlbumArtworkCachePath(String basePath, String albumId) {
    return path.join(basePath, artworkCacheFolder, '$albumId.jpg');
  }

  /// Get cached artwork path for an artist
  static String getArtistArtworkCachePath(String basePath, String artistId) {
    return path.join(basePath, artworkCacheFolder, '$artistId.jpg');
  }

  /// Get cover metadata path in album folder
  static String getAlbumCoverMetadataPath(String albumFolder) {
    return path.join(albumFolder, coverMetadataFile);
  }

  /// Get lyrics file path in album folder
  static String getAlbumLyricsPath(String albumFolder) {
    return path.join(albumFolder, lyricsFile);
  }

  /// Generate album ID from folder path
  static String generateAlbumId(String folderPath) {
    // Use hash of normalized path for uniqueness
    final normalized = folderPath.toLowerCase().replaceAll('\\', '/');
    final hash = normalized.hashCode.abs().toRadixString(36);
    final folderName = path.basename(folderPath)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .trim();
    return 'album_${folderName.isEmpty ? hash : '${folderName}_$hash'}';
  }

  /// Generate track ID from file path
  static String generateTrackId(String filePath) {
    final normalized = filePath.toLowerCase().replaceAll('\\', '/');
    final hash = normalized.hashCode.abs().toRadixString(36);
    return 'track_$hash';
  }

  /// Extract track number from filename
  /// Supports: "01 - Song.mp3", "01. Song.mp3", "01_Song.mp3", "1 Song.mp3"
  static int? extractTrackNumber(String filename) {
    final name = path.basenameWithoutExtension(filename);

    // Try patterns: "01 - ", "01. ", "01_", "01 "
    final patterns = [
      RegExp(r'^(\d{1,3})\s*[-._]\s*'),
      RegExp(r'^(\d{1,3})\s+'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        final numStr = match.group(1);
        if (numStr != null) {
          return int.tryParse(numStr);
        }
      }
    }

    return null;
  }

  /// Extract title from filename (strip track number prefix)
  static String extractTitleFromFilename(String filename) {
    final name = path.basenameWithoutExtension(filename);

    // Remove track number prefix
    final patterns = [
      RegExp(r'^(\d{1,3})\s*[-._]\s*'),
      RegExp(r'^(\d{1,3})\s+'),
    ];

    String title = name;
    for (final pattern in patterns) {
      title = title.replaceFirst(pattern, '');
    }

    return title.trim();
  }

  /// Check if file is a supported audio format
  static bool isAudioFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return supportedExtensions.contains(ext);
  }

  /// Check if file is an image
  static bool isImageFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png';
  }

  /// Supported audio file extensions
  static const supportedExtensions = [
    '.flac',
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.aiff',
    '.aif',
  ];
}
