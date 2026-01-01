/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/music_track.dart';
import '../../services/log_service.dart';

/// Manages storage of generated music tracks
class MusicStorageService {
  static final MusicStorageService _instance = MusicStorageService._internal();
  factory MusicStorageService() => _instance;
  MusicStorageService._internal();

  /// Directory for storing music tracks
  String? _musicPath;

  /// Cached track index
  List<MusicTrack>? _trackIndex;

  /// Notifier for track changes
  final StreamController<void> _tracksChangedController =
      StreamController<void>.broadcast();

  /// Stream that fires when tracks are added/removed
  Stream<void> get tracksChanged => _tracksChangedController.stream;

  /// Maximum number of tracks to keep (oldest deleted first)
  static const int maxTracks = 50;

  /// Maximum storage in bytes (500 MB)
  static const int maxStorageBytes = 500 * 1024 * 1024;

  /// Initialize the service
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _musicPath = '${appDir.path}/bot/music';

    // Create directories if they don't exist
    final tracksDir = Directory('$_musicPath/tracks');
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }

    LogService().log('MusicStorageService: Initialized at $_musicPath');

    // Load track index
    await _loadIndex();
  }

  /// Get path to music directory
  Future<String> get musicPath async {
    if (_musicPath == null) {
      await initialize();
    }
    return _musicPath!;
  }

  /// Get path to tracks directory
  Future<String> get tracksPath async {
    final basePath = await musicPath;
    return '$basePath/tracks';
  }

  /// Load track index from disk
  Future<void> _loadIndex() async {
    final basePath = await musicPath;
    final indexFile = File('$basePath/index.json');

    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final tracksJson = json['tracks'] as List<dynamic>? ?? [];

        _trackIndex = tracksJson
            .map((t) => MusicTrack.fromJson(t as Map<String, dynamic>))
            .toList();

        LogService().log(
            'MusicStorageService: Loaded ${_trackIndex!.length} tracks from index');
      } catch (e) {
        LogService().log('MusicStorageService: Error loading index: $e');
        _trackIndex = [];
      }
    } else {
      _trackIndex = [];
    }
  }

  /// Save track index to disk
  Future<void> _saveIndex() async {
    final basePath = await musicPath;
    final indexFile = File('$basePath/index.json');

    final json = {
      'version': 1,
      'tracks': _trackIndex!.map((t) => t.toJson()).toList(),
      'lastUpdated': DateTime.now().toIso8601String(),
    };

    await indexFile.writeAsString(jsonEncode(json));
  }

  /// Save a generated track
  /// Returns the file path where the track was saved
  /// [format] specifies the audio format: 'wav', 'ogg', etc.
  Future<String> saveTrack(MusicTrack track, List<int> audioData, {String format = 'wav'}) async {
    if (_trackIndex == null) {
      await _loadIndex();
    }

    final basePath = await tracksPath;

    // Generate filename from track ID with correct extension
    final audioFile = File('$basePath/${track.id}.$format');
    final metadataFile = File('$basePath/${track.id}.json');

    // Write audio data
    await audioFile.writeAsBytes(audioData);

    // Write metadata
    await metadataFile.writeAsString(jsonEncode(track.toJson()));

    // Update track with actual file path and stats
    final savedTrack = track.copyWith(
      filePath: audioFile.path,
      stats: track.stats?.copyWith(fileSizeBytes: audioData.length) ??
          MusicGenerationStats(
            processingTimeMs: 0,
            fileSizeBytes: audioData.length,
          ),
    );

    // Add to index
    _trackIndex!.insert(0, savedTrack);
    await _saveIndex();

    // Trigger cleanup if needed
    await _cleanupIfNeeded();

    _tracksChangedController.add(null);

    LogService().log(
        'MusicStorageService: Saved track ${track.id} (${track.genre}, ${track.durationString})');

    return audioFile.path;
  }

  /// Get all saved tracks (most recent first)
  Future<List<MusicTrack>> getSavedTracks() async {
    if (_trackIndex == null) {
      await _loadIndex();
    }
    return List.unmodifiable(_trackIndex!);
  }

  /// Get a track by ID
  Future<MusicTrack?> getTrackById(String id) async {
    if (_trackIndex == null) {
      await _loadIndex();
    }

    try {
      return _trackIndex!.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get tracks by genre
  Future<List<MusicTrack>> getTracksByGenre(String genre) async {
    if (_trackIndex == null) {
      await _loadIndex();
    }

    return _trackIndex!
        .where((t) => t.genre.toLowerCase() == genre.toLowerCase())
        .toList();
  }

  /// Delete a track
  Future<void> deleteTrack(String id) async {
    if (_trackIndex == null) {
      await _loadIndex();
    }

    final basePath = await tracksPath;

    // Remove from index
    _trackIndex!.removeWhere((t) => t.id == id);
    await _saveIndex();

    // Delete files (try both .wav and .ogg extensions)
    for (final ext in ['wav', 'ogg']) {
      final audioFile = File('$basePath/$id.$ext');
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
    }
    final metadataFile = File('$basePath/$id.json');
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }

    _tracksChangedController.add(null);

    LogService().log('MusicStorageService: Deleted track $id');
  }

  /// Delete all tracks
  Future<void> clearAllTracks() async {
    if (_trackIndex == null) {
      await _loadIndex();
    }

    final basePath = await tracksPath;
    final dir = Directory(basePath);

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }

    _trackIndex!.clear();
    await _saveIndex();

    _tracksChangedController.add(null);

    LogService().log('MusicStorageService: Cleared all tracks');
  }

  /// Get total storage used by tracks in bytes
  Future<int> getTotalStorageBytes() async {
    final basePath = await tracksPath;
    final dir = Directory(basePath);

    var total = 0;

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }

    return total;
  }

  /// Get human-readable storage used string
  Future<String> getStorageUsedString() async {
    final bytes = await getTotalStorageBytes();

    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Get track count
  Future<int> getTrackCount() async {
    if (_trackIndex == null) {
      await _loadIndex();
    }
    return _trackIndex!.length;
  }

  /// Cleanup old tracks if storage limits exceeded
  Future<void> _cleanupIfNeeded() async {
    if (_trackIndex == null) return;

    var changed = false;

    // Remove tracks if count exceeds max
    while (_trackIndex!.length > maxTracks) {
      final oldest = _trackIndex!.last;
      await _deleteTrackFiles(oldest.id);
      _trackIndex!.removeLast();
      changed = true;

      LogService().log(
          'MusicStorageService: Removed old track ${oldest.id} (max tracks exceeded)');
    }

    // Remove tracks if storage exceeds max
    var storageUsed = await getTotalStorageBytes();
    while (storageUsed > maxStorageBytes && _trackIndex!.isNotEmpty) {
      final oldest = _trackIndex!.last;
      await _deleteTrackFiles(oldest.id);
      _trackIndex!.removeLast();
      storageUsed = await getTotalStorageBytes();
      changed = true;

      LogService().log(
          'MusicStorageService: Removed old track ${oldest.id} (storage exceeded)');
    }

    if (changed) {
      await _saveIndex();
    }
  }

  /// Delete track files without updating index
  Future<void> _deleteTrackFiles(String id) async {
    final basePath = await tracksPath;

    // Delete audio files (try both extensions)
    for (final ext in ['wav', 'ogg']) {
      final audioFile = File('$basePath/$id.$ext');
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
    }
    final metadataFile = File('$basePath/$id.json');
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  /// Check if a track file exists
  Future<bool> trackFileExists(String id) async {
    final basePath = await tracksPath;
    for (final ext in ['wav', 'ogg']) {
      final audioFile = File('$basePath/$id.$ext');
      if (await audioFile.exists()) {
        return true;
      }
    }
    return false;
  }

  /// Get audio file path for a track
  Future<String?> getTrackFilePath(String id) async {
    final basePath = await tracksPath;
    for (final ext in ['wav', 'ogg']) {
      final audioFile = File('$basePath/$id.$ext');
      if (await audioFile.exists()) {
        return audioFile.path;
      }
    }
    return null;
  }

  void dispose() {
    _tracksChangedController.close();
  }
}

/// Extension to add copyWith to MusicGenerationStats
extension MusicGenerationStatsCopyWith on MusicGenerationStats {
  MusicGenerationStats copyWith({
    int? processingTimeMs,
    String? modelVersion,
    String? qualityLevel,
    int? fileSizeBytes,
  }) {
    return MusicGenerationStats(
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      modelVersion: modelVersion ?? this.modelVersion,
      qualityLevel: qualityLevel ?? this.qualityLevel,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }
}
