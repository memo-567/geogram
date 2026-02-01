/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../services/storage_config.dart';

/// Represents a category of sound tracks
class SoundCategory {
  final String id;
  final String description;
  final List<SoundTrack> tracks;

  const SoundCategory({
    required this.id,
    required this.description,
    required this.tracks,
  });

  factory SoundCategory.fromJson(String id, Map<String, dynamic> json) {
    final tracksJson = json['tracks'] as List<dynamic>? ?? [];
    return SoundCategory(
      id: id,
      description: json['description'] as String? ?? '',
      tracks: tracksJson
          .map((t) => SoundTrack.fromJson(t as Map<String, dynamic>, id))
          .toList(),
    );
  }
}

/// Represents a sound track
class SoundTrack {
  final String file;
  final String title;
  final String durationApprox;
  final String mood;
  final String category;

  const SoundTrack({
    required this.file,
    required this.title,
    required this.durationApprox,
    required this.mood,
    required this.category,
  });

  /// Special marker for "no music" selection (to distinguish from cancel)
  factory SoundTrack.none() => const SoundTrack(
        file: '',
        title: '',
        durationApprox: '',
        mood: '',
        category: '',
      );

  factory SoundTrack.fromJson(Map<String, dynamic> json, String category) {
    return SoundTrack(
      file: json['file'] as String? ?? '',
      title: json['title'] as String? ?? '',
      durationApprox: json['duration_approx'] as String? ?? '',
      mood: json['mood'] as String? ?? '',
      category: category,
    );
  }

  /// Check if this is the "none" marker
  bool get isNone => file.isEmpty;

  /// Get display title for the track
  String get displayTitle => title.isNotEmpty ? title : path.basenameWithoutExtension(file);
}

/// Singleton service for managing bundled sound clips
class SoundClipsService {
  static final SoundClipsService _instance = SoundClipsService._internal();
  factory SoundClipsService() => _instance;
  SoundClipsService._internal();

  bool _initialized = false;
  List<SoundCategory> _categories = [];
  String? _soundsDir;

  /// Get all categories
  List<SoundCategory> get categories => _categories;

  /// Get all tracks across all categories
  List<SoundTrack> getAllTracks() {
    return _categories.expand((c) => c.tracks).toList();
  }

  /// Get the sounds directory path
  String get soundsDir {
    if (_soundsDir == null) {
      throw StateError('SoundClipsService not initialized');
    }
    return _soundsDir!;
  }

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    // Set up sounds directory
    _soundsDir = path.join(StorageConfig().baseDir, 'sounds');

    // Extract any missing bundled sounds
    await _extractMissingSounds();

    // Load tracks metadata
    await _loadTracksMetadata();

    _initialized = true;
  }

  /// Extract bundled sounds, verifying each file exists
  Future<void> _extractMissingSounds() async {
    final targetDir = Directory(_soundsDir!);
    await targetDir.create(recursive: true);

    // Load the tracks.json to get the list of files
    try {
      final tracksJson = await rootBundle.loadString('sounds/tracks.json');
      final tracksData = json.decode(tracksJson) as Map<String, dynamic>;

      // Copy tracks.json if missing
      final tracksFile = File(path.join(_soundsDir!, 'tracks.json'));
      if (!await tracksFile.exists()) {
        await tracksFile.writeAsString(tracksJson);
      }

      // Copy LICENSE.txt if missing
      final licenseFile = File(path.join(_soundsDir!, 'LICENSE.txt'));
      if (!await licenseFile.exists()) {
        try {
          final licenseData = await rootBundle.load('sounds/LICENSE.txt');
          await licenseFile.writeAsBytes(licenseData.buffer.asUint8List());
        } catch (_) {
          // License file is optional
        }
      }

      // Extract each track, checking if it already exists
      final categories = tracksData['categories'] as Map<String, dynamic>? ?? {};
      for (final categoryEntry in categories.entries) {
        final categoryData = categoryEntry.value as Map<String, dynamic>;
        final tracks = categoryData['tracks'] as List<dynamic>? ?? [];

        for (final track in tracks) {
          final trackData = track as Map<String, dynamic>;
          final file = trackData['file'] as String?;
          if (file == null || file.isEmpty) continue;

          final targetFile = File(path.join(_soundsDir!, file));

          // Skip if file already exists
          if (await targetFile.exists()) continue;

          // Create category subdirectory if needed
          final categoryDir = path.dirname(file);
          final targetCategoryDir = Directory(path.join(_soundsDir!, categoryDir));
          if (!await targetCategoryDir.exists()) {
            await targetCategoryDir.create(recursive: true);
          }

          // Extract the audio file from bundle
          try {
            final audioData = await rootBundle.load('sounds/$file');
            await targetFile.writeAsBytes(audioData.buffer.asUint8List());
          } catch (e) {
            stderr.writeln('SoundClipsService: Failed to extract $file: $e');
          }
        }
      }
    } catch (e) {
      stderr.writeln('SoundClipsService: Failed to extract bundled sounds: $e');
    }
  }

  /// Load tracks metadata from tracks.json
  Future<void> _loadTracksMetadata() async {
    final tracksFile = File(path.join(_soundsDir!, 'tracks.json'));

    if (!await tracksFile.exists()) {
      stderr.writeln('SoundClipsService: tracks.json not found');
      return;
    }

    try {
      final content = await tracksFile.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      final categoriesData = data['categories'] as Map<String, dynamic>? ?? {};

      _categories = categoriesData.entries
          .map((e) => SoundCategory.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList();
    } catch (e) {
      stderr.writeln('SoundClipsService: Failed to load tracks metadata: $e');
    }
  }

  /// Get the full path for a track file
  String getTrackPath(String relativeFile) {
    return path.join(_soundsDir!, relativeFile);
  }

  /// Find a track by its file path
  SoundTrack? findTrack(String file) {
    for (final category in _categories) {
      for (final track in category.tracks) {
        if (track.file == file) {
          return track;
        }
      }
    }
    return null;
  }

  /// Check if a track file exists
  Future<bool> trackExists(String relativeFile) async {
    final trackPath = getTrackPath(relativeFile);
    return File(trackPath).exists();
  }
}
