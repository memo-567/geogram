/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:path/path.dart' as p;

import 'music_track.dart';
import 'music_album.dart';
import 'music_artist.dart';

/// A node in the music folder tree
class MusicFolderNode {
  final String path;
  final String name;
  final List<MusicFolderNode> subfolders;
  final List<String> albumIds;
  final int totalTrackCount;
  String? artwork;

  MusicFolderNode({
    required this.path,
    required this.name,
    List<MusicFolderNode>? subfolders,
    List<String>? albumIds,
    this.totalTrackCount = 0,
    this.artwork,
  })  : subfolders = subfolders ?? [],
        albumIds = albumIds ?? [];
}

/// Contents of a folder (lazy-loaded)
class MusicFolderContents {
  final List<MusicFolderNode> subfolders;
  final List<MusicAlbum> albums;

  MusicFolderContents({
    required this.subfolders,
    required this.albums,
  });
}

/// Library statistics
class LibraryStats {
  final int totalTracks;
  final int totalAlbums;
  final int totalArtists;
  final int totalDurationSeconds;
  final int totalSizeBytes;

  LibraryStats({
    this.totalTracks = 0,
    this.totalAlbums = 0,
    this.totalArtists = 0,
    this.totalDurationSeconds = 0,
    this.totalSizeBytes = 0,
  });

  factory LibraryStats.fromJson(Map<String, dynamic> json) {
    return LibraryStats(
      totalTracks: json['total_tracks'] as int? ?? 0,
      totalAlbums: json['total_albums'] as int? ?? 0,
      totalArtists: json['total_artists'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      totalSizeBytes: json['total_size_bytes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_tracks': totalTracks,
      'total_albums': totalAlbums,
      'total_artists': totalArtists,
      'total_duration_seconds': totalDurationSeconds,
      'total_size_bytes': totalSizeBytes,
    };
  }

  /// Formatted total duration
  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h ${minutes} min';
    }
    return '$minutes min';
  }

  /// Formatted total size
  String get formattedSize {
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalSizeBytes < 1024 * 1024 * 1024) {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// The music library containing all discovered tracks, albums, and artists
class MusicLibrary {
  final String version;
  final DateTime? lastScan;
  final int? scanDurationSeconds;
  final LibraryStats stats;
  final List<MusicArtist> artists;
  final List<MusicAlbum> albums;
  final List<MusicTrack> tracks;

  // Quick lookup maps (built on demand)
  Map<String, MusicTrack>? _trackById;
  Map<String, MusicAlbum>? _albumById;
  Map<String, MusicArtist>? _artistById;
  Map<String, List<MusicTrack>>? _tracksByAlbum;
  Map<String, List<MusicAlbum>>? _albumsByArtist;

  MusicLibrary({
    this.version = '1.0',
    this.lastScan,
    this.scanDurationSeconds,
    LibraryStats? stats,
    List<MusicArtist>? artists,
    List<MusicAlbum>? albums,
    List<MusicTrack>? tracks,
  })  : stats = stats ?? LibraryStats(),
        artists = artists ?? [],
        albums = albums ?? [],
        tracks = tracks ?? [];

  factory MusicLibrary.fromJson(Map<String, dynamic> json) {
    return MusicLibrary(
      version: json['version'] as String? ?? '1.0',
      lastScan: json['last_scan'] != null
          ? DateTime.parse(json['last_scan'] as String)
          : null,
      scanDurationSeconds: json['scan_duration_seconds'] as int?,
      stats: json['stats'] != null
          ? LibraryStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => MusicArtist.fromJson(e as Map<String, dynamic>))
          .toList(),
      albums: (json['albums'] as List<dynamic>?)
          ?.map((e) => MusicAlbum.fromJson(e as Map<String, dynamic>))
          .toList(),
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      if (lastScan != null) 'last_scan': lastScan!.toIso8601String(),
      if (scanDurationSeconds != null)
        'scan_duration_seconds': scanDurationSeconds,
      'stats': stats.toJson(),
      'artists': artists.map((a) => a.toJson()).toList(),
      'albums': albums.map((a) => a.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  /// Get track by ID
  MusicTrack? getTrack(String id) {
    _trackById ??= {for (final t in tracks) t.id: t};
    return _trackById![id];
  }

  /// Get album by ID
  MusicAlbum? getAlbum(String id) {
    _albumById ??= {for (final a in albums) a.id: a};
    return _albumById![id];
  }

  /// Get artist by ID
  MusicArtist? getArtist(String id) {
    _artistById ??= {for (final a in artists) a.id: a};
    return _artistById![id];
  }

  /// Get all tracks in an album, sorted by track number
  List<MusicTrack> getAlbumTracks(String albumId) {
    _tracksByAlbum ??= _buildTracksByAlbum();
    final albumTracks = _tracksByAlbum![albumId] ?? [];
    return List.from(albumTracks)
      ..sort((a, b) {
        // Sort by disc number first, then track number
        final discCompare = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (discCompare != 0) return discCompare;
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });
  }

  Map<String, List<MusicTrack>> _buildTracksByAlbum() {
    final map = <String, List<MusicTrack>>{};
    for (final track in tracks) {
      if (track.albumId != null) {
        map.putIfAbsent(track.albumId!, () => []).add(track);
      }
    }
    return map;
  }

  /// Get all albums by an artist
  List<MusicAlbum> getArtistAlbums(String artistId) {
    _albumsByArtist ??= _buildAlbumsByArtist();
    return _albumsByArtist![artistId] ?? [];
  }

  Map<String, List<MusicAlbum>> _buildAlbumsByArtist() {
    final map = <String, List<MusicAlbum>>{};
    for (final album in albums) {
      if (album.artistId != null) {
        map.putIfAbsent(album.artistId!, () => []).add(album);
      }
    }
    return map;
  }

  /// Check if library is empty
  bool get isEmpty => tracks.isEmpty;

  /// Check if library needs rescan
  bool get needsRescan {
    if (lastScan == null) return true;
    // Rescan if older than 24 hours
    return DateTime.now().difference(lastScan!).inHours > 24;
  }

  /// Build a folder tree from the music library based on source folders
  List<MusicFolderNode> buildFolderTree(List<String> sourceFolders) {
    final rootNodes = <MusicFolderNode>[];

    // Group albums by folder path
    final albumsByFolder = <String, List<MusicAlbum>>{};
    for (final album in albums) {
      albumsByFolder.putIfAbsent(album.folderPath, () => []).add(album);
    }

    // Track count per folder (including subfolders)
    final trackCountByFolder = <String, int>{};
    for (final album in albums) {
      trackCountByFolder[album.folderPath] =
          (trackCountByFolder[album.folderPath] ?? 0) + album.trackCount;
    }

    for (final sourceFolder in sourceFolders) {
      final rootNode = _buildFolderNode(
        sourceFolder,
        albumsByFolder,
        trackCountByFolder,
        sourceFolders,
      );
      if (rootNode != null) {
        rootNodes.add(rootNode);
      }
    }

    return rootNodes;
  }

  /// Recursively build a folder node
  MusicFolderNode? _buildFolderNode(
    String folderPath,
    Map<String, List<MusicAlbum>> albumsByFolder,
    Map<String, int> trackCountByFolder,
    List<String> sourceFolders,
  ) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return null;

    final name = p.basename(folderPath);

    // Find albums directly in this folder
    final directAlbums = albumsByFolder[folderPath] ?? [];
    final albumIds = directAlbums.map((a) => a.id).toList();

    // Find subfolders that contain music (directly or in descendants)
    final subfolders = <MusicFolderNode>[];
    final relevantPaths = <String>{};

    // Find all folder paths that are direct children of this folder
    for (final albumFolder in albumsByFolder.keys) {
      if (albumFolder != folderPath && p.isWithin(folderPath, albumFolder)) {
        // Get the immediate child folder
        final relative = p.relative(albumFolder, from: folderPath);
        final childName = p.split(relative).first;
        final childPath = p.join(folderPath, childName);

        // Skip if this child is itself a source folder (handled separately)
        if (!sourceFolders.contains(childPath)) {
          relevantPaths.add(childPath);
        }
      }
    }

    // Build child nodes
    for (final childPath in relevantPaths) {
      final childNode = _buildFolderNode(
        childPath,
        albumsByFolder,
        trackCountByFolder,
        sourceFolders,
      );
      if (childNode != null) {
        subfolders.add(childNode);
      }
    }

    // Sort subfolders by name
    subfolders.sort((a, b) => a.name.compareTo(b.name));

    // Calculate total track count (this folder + all descendants)
    var totalTrackCount = trackCountByFolder[folderPath] ?? 0;
    for (final subfolder in subfolders) {
      totalTrackCount += subfolder.totalTrackCount;
    }

    // Find artwork: first check folder artwork, then use first album's artwork
    String? artwork;
    final artworkFiles = [
      p.join(folderPath, 'cover.jpg'),
      p.join(folderPath, 'cover.png'),
      p.join(folderPath, 'artwork.jpg'),
      p.join(folderPath, 'artwork.png'),
      p.join(folderPath, 'folder.jpg'),
      p.join(folderPath, 'folder.png'),
    ];
    for (final artworkPath in artworkFiles) {
      if (File(artworkPath).existsSync()) {
        artwork = artworkPath;
        break;
      }
    }
    // If no folder artwork, use first album's artwork
    if (artwork == null && directAlbums.isNotEmpty) {
      artwork = directAlbums.first.artwork;
    }

    // Only return node if it has albums or subfolders with music
    if (albumIds.isEmpty && subfolders.isEmpty) {
      return null;
    }

    return MusicFolderNode(
      path: folderPath,
      name: name,
      subfolders: subfolders,
      albumIds: albumIds,
      totalTrackCount: totalTrackCount,
      artwork: artwork,
    );
  }

  /// Get all tracks in a folder recursively
  List<MusicTrack> getTracksInFolder(String folderPath) {
    final result = <MusicTrack>[];
    for (final album in albums) {
      if (album.folderPath == folderPath ||
          p.isWithin(folderPath, album.folderPath)) {
        result.addAll(getAlbumTracks(album.id));
      }
    }
    return result;
  }

  /// Get folder contents lazily (only immediate children, no deep recursion)
  /// Returns a tuple of (subfolders, albums in this folder)
  MusicFolderContents getFolderContents(String folderPath) {
    // Find albums directly in this folder
    final directAlbums = albums.where((a) => a.folderPath == folderPath).toList();

    // Find immediate child folders that contain music (at any depth)
    final childFolders = <String>{};
    for (final album in albums) {
      if (album.folderPath != folderPath &&
          p.isWithin(folderPath, album.folderPath)) {
        // Get the immediate child folder name
        final relative = p.relative(album.folderPath, from: folderPath);
        final childName = p.split(relative).first;
        childFolders.add(p.join(folderPath, childName));
      }
    }

    // Build folder nodes for immediate children only
    final subfolderNodes = <MusicFolderNode>[];
    for (final childPath in childFolders) {
      final name = p.basename(childPath);

      // Count tracks in this subfolder and its descendants
      var trackCount = 0;
      for (final album in albums) {
        if (album.folderPath == childPath ||
            p.isWithin(childPath, album.folderPath)) {
          trackCount += album.trackCount;
        }
      }

      // Find artwork (check folder first, then first album in folder)
      String? artwork = _findFolderArtwork(childPath);
      if (artwork == null) {
        // Use first album's artwork from this folder or subfolders
        for (final album in albums) {
          if (album.folderPath == childPath ||
              p.isWithin(childPath, album.folderPath)) {
            if (album.artwork != null) {
              artwork = album.artwork;
              break;
            }
          }
        }
      }

      subfolderNodes.add(MusicFolderNode(
        path: childPath,
        name: name,
        totalTrackCount: trackCount,
        artwork: artwork,
      ));
    }

    // Sort by name
    subfolderNodes.sort((a, b) => a.name.compareTo(b.name));
    directAlbums.sort((a, b) => a.title.compareTo(b.title));

    return MusicFolderContents(
      subfolders: subfolderNodes,
      albums: directAlbums,
    );
  }

  /// Find artwork file in a folder
  String? _findFolderArtwork(String folderPath) {
    const artworkFiles = [
      'cover.jpg',
      'cover.png',
      'artwork.jpg',
      'artwork.png',
      'folder.jpg',
      'folder.png',
    ];
    for (final filename in artworkFiles) {
      final file = File(p.join(folderPath, filename));
      if (file.existsSync()) {
        return file.path;
      }
    }
    return null;
  }

  /// Create updated library with new stats
  MusicLibrary copyWith({
    String? version,
    DateTime? lastScan,
    int? scanDurationSeconds,
    LibraryStats? stats,
    List<MusicArtist>? artists,
    List<MusicAlbum>? albums,
    List<MusicTrack>? tracks,
  }) {
    return MusicLibrary(
      version: version ?? this.version,
      lastScan: lastScan ?? this.lastScan,
      scanDurationSeconds: scanDurationSeconds ?? this.scanDurationSeconds,
      stats: stats ?? this.stats,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      tracks: tracks ?? this.tracks,
    );
  }
}
