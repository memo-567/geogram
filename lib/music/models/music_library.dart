/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'music_track.dart';
import 'music_album.dart';
import 'music_artist.dart';

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
