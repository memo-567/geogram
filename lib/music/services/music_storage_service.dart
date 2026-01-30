/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import '../../services/log_service.dart';
import '../models/music_models.dart';
import '../utils/music_path_utils.dart';

/// Storage service for music app data
class MusicStorageService {
  final String basePath;
  final LogService _log = LogService();

  MusicStorageService({required this.basePath});

  static const _encoder = JsonEncoder.withIndent('  ');

  // === Settings ===

  /// Load settings from disk
  Future<MusicSettings> loadSettings() async {
    try {
      final file = File(MusicPathUtils.getSettingsPath(basePath));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return MusicSettings.fromJson(json);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading settings: $e');
    }
    return MusicSettings();
  }

  /// Save settings to disk
  Future<void> saveSettings(MusicSettings settings) async {
    try {
      final file = File(MusicPathUtils.getSettingsPath(basePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_encoder.convert(settings.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving settings: $e');
    }
  }

  // === Library ===

  /// Load library from disk
  Future<MusicLibrary> loadLibrary() async {
    try {
      final file = File(MusicPathUtils.getLibraryPath(basePath));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return MusicLibrary.fromJson(json);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading library: $e');
    }
    return MusicLibrary();
  }

  /// Save library to disk
  Future<void> saveLibrary(MusicLibrary library) async {
    try {
      final file = File(MusicPathUtils.getLibraryPath(basePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_encoder.convert(library.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving library: $e');
    }
  }

  // === Queue ===

  /// Load playback queue from disk
  Future<PlaybackQueue> loadQueue() async {
    try {
      final file = File(MusicPathUtils.getQueuePath(basePath));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return PlaybackQueue.fromJson(json);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading queue: $e');
    }
    return PlaybackQueue();
  }

  /// Save playback queue to disk
  Future<void> saveQueue(PlaybackQueue queue) async {
    try {
      final file = File(MusicPathUtils.getQueuePath(basePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_encoder.convert(queue.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving queue: $e');
    }
  }

  // === History ===

  /// Load play history from disk
  Future<PlayHistory> loadHistory() async {
    try {
      final file = File(MusicPathUtils.getHistoryPath(basePath));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return PlayHistory.fromJson(json);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading history: $e');
    }
    return PlayHistory();
  }

  /// Save play history to disk
  Future<void> saveHistory(PlayHistory history) async {
    try {
      final file = File(MusicPathUtils.getHistoryPath(basePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(_encoder.convert(history.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving history: $e');
    }
  }

  // === Playlists ===

  /// Load all playlists
  Future<List<MusicPlaylist>> loadPlaylists() async {
    final playlists = <MusicPlaylist>[];
    try {
      final dir = Directory(MusicPathUtils.getPlaylistsPath(basePath));
      if (!await dir.exists()) return playlists;

      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.m3u8.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final playlist = MusicPlaylist.fromJson(json);

            // Load track paths from M3U8 file
            final m3u8Path = file.path.replaceAll('.json', '');
            final m3u8File = File(m3u8Path);
            if (await m3u8File.exists()) {
              final m3u8Content = await m3u8File.readAsString();
              final trackPaths = MusicPlaylist.parseM3u8(m3u8Content);
              playlists.add(playlist.copyWith(trackPaths: trackPaths));
            } else {
              playlists.add(playlist);
            }
          } catch (e) {
            _log.log('MusicStorageService: Error loading playlist ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading playlists: $e');
    }
    return playlists;
  }

  /// Save a playlist
  Future<void> savePlaylist(MusicPlaylist playlist) async {
    try {
      final playlistsDir = Directory(MusicPathUtils.getPlaylistsPath(basePath));
      await playlistsDir.create(recursive: true);

      // Save M3U8 file
      final m3u8Path =
          MusicPathUtils.getPlaylistFilePath(basePath, playlist.id);
      final m3u8File = File(m3u8Path);
      await m3u8File.writeAsString(playlist.toM3u8());

      // Save metadata JSON
      final metaPath =
          MusicPathUtils.getPlaylistMetadataPath(basePath, playlist.id);
      final metaFile = File(metaPath);
      await metaFile.writeAsString(_encoder.convert(playlist.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving playlist: $e');
    }
  }

  /// Delete a playlist
  Future<void> deletePlaylist(String playlistId) async {
    try {
      final m3u8Path =
          MusicPathUtils.getPlaylistFilePath(basePath, playlistId);
      final metaPath =
          MusicPathUtils.getPlaylistMetadataPath(basePath, playlistId);

      final m3u8File = File(m3u8Path);
      final metaFile = File(metaPath);

      if (await m3u8File.exists()) await m3u8File.delete();
      if (await metaFile.exists()) await metaFile.delete();
    } catch (e) {
      _log.log('MusicStorageService: Error deleting playlist: $e');
    }
  }

  // === Album Metadata (in album folders) ===

  /// Load album cover metadata from album folder
  Future<AlbumCoverMetadata?> loadAlbumCoverMetadata(String albumFolder) async {
    try {
      final file = File(MusicPathUtils.getAlbumCoverMetadataPath(albumFolder));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return AlbumCoverMetadata.fromJson(json);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error loading album metadata: $e');
    }
    return null;
  }

  /// Save album cover metadata to album folder
  Future<void> saveAlbumCoverMetadata(
    String albumFolder,
    AlbumCoverMetadata metadata,
  ) async {
    try {
      final file = File(MusicPathUtils.getAlbumCoverMetadataPath(albumFolder));
      await file.writeAsString(_encoder.convert(metadata.toJson()));
    } catch (e) {
      _log.log('MusicStorageService: Error saving album metadata: $e');
    }
  }

  // === Cache Management ===

  /// Ensure cache directories exist
  Future<void> ensureCacheDirectories() async {
    try {
      await Directory(MusicPathUtils.getCachePath(basePath))
          .create(recursive: true);
      await Directory(MusicPathUtils.getArtworkCachePath(basePath))
          .create(recursive: true);
      await Directory(MusicPathUtils.getPlaylistsPath(basePath))
          .create(recursive: true);
    } catch (e) {
      _log.log('MusicStorageService: Error creating cache directories: $e');
    }
  }

  /// Get total cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final dir = Directory(MusicPathUtils.getCachePath(basePath));
      if (!await dir.exists()) return 0;

      int size = 0;
      await for (final file in dir.list(recursive: true)) {
        if (file is File) {
          size += await file.length();
        }
      }
      return size;
    } catch (e) {
      _log.log('MusicStorageService: Error calculating cache size: $e');
      return 0;
    }
  }

  /// Clear artwork cache
  Future<void> clearArtworkCache() async {
    try {
      final dir = Directory(MusicPathUtils.getArtworkCachePath(basePath));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      _log.log('MusicStorageService: Error clearing artwork cache: $e');
    }
  }

  /// Check if cached artwork exists
  Future<bool> hasArtworkCache(String albumId) async {
    final file =
        File(MusicPathUtils.getAlbumArtworkCachePath(basePath, albumId));
    return file.exists();
  }

  /// Get cached artwork path (null if not cached)
  Future<String?> getArtworkCachePath(String albumId) async {
    final path = MusicPathUtils.getAlbumArtworkCachePath(basePath, albumId);
    final file = File(path);
    if (await file.exists()) {
      return path;
    }
    return null;
  }

  /// Save artwork to cache
  Future<String?> cacheArtwork(String albumId, List<int> bytes) async {
    try {
      final path = MusicPathUtils.getAlbumArtworkCachePath(basePath, albumId);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return path;
    } catch (e) {
      _log.log('MusicStorageService: Error caching artwork: $e');
      return null;
    }
  }
}
