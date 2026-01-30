/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// A single play event
class PlayEvent {
  final String trackId;
  final String? albumId;
  final String? artistId;
  final DateTime playedAt;
  final int durationPlayedSeconds;
  final bool completed;

  PlayEvent({
    required this.trackId,
    this.albumId,
    this.artistId,
    DateTime? playedAt,
    this.durationPlayedSeconds = 0,
    this.completed = false,
  }) : playedAt = playedAt ?? DateTime.now();

  factory PlayEvent.fromJson(Map<String, dynamic> json) {
    return PlayEvent(
      trackId: json['track_id'] as String,
      albumId: json['album_id'] as String?,
      artistId: json['artist_id'] as String?,
      playedAt: json['played_at'] != null
          ? DateTime.parse(json['played_at'] as String)
          : null,
      durationPlayedSeconds: json['duration_played_seconds'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'track_id': trackId,
      if (albumId != null) 'album_id': albumId,
      if (artistId != null) 'artist_id': artistId,
      'played_at': playedAt.toIso8601String(),
      'duration_played_seconds': durationPlayedSeconds,
      'completed': completed,
    };
  }

  /// Minimum duration to count as a play (30 seconds)
  static const minPlayDurationSeconds = 30;

  /// Check if this event should count as a play
  bool get countsAsPlay {
    return completed || durationPlayedSeconds >= minPlayDurationSeconds;
  }
}

/// Play history statistics
class PlayHistoryStats {
  final int totalPlays;
  final int totalTimeSeconds;
  final DateTime? firstPlay;
  final DateTime? lastPlay;

  PlayHistoryStats({
    this.totalPlays = 0,
    this.totalTimeSeconds = 0,
    this.firstPlay,
    this.lastPlay,
  });

  factory PlayHistoryStats.fromJson(Map<String, dynamic> json) {
    return PlayHistoryStats(
      totalPlays: json['total_plays'] as int? ?? 0,
      totalTimeSeconds: json['total_time_seconds'] as int? ?? 0,
      firstPlay: json['first_play'] != null
          ? DateTime.parse(json['first_play'] as String)
          : null,
      lastPlay: json['last_play'] != null
          ? DateTime.parse(json['last_play'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_plays': totalPlays,
      'total_time_seconds': totalTimeSeconds,
      if (firstPlay != null) 'first_play': firstPlay!.toIso8601String(),
      if (lastPlay != null) 'last_play': lastPlay!.toIso8601String(),
    };
  }

  /// Formatted total listening time
  String get formattedListeningTime {
    final hours = totalTimeSeconds ~/ 3600;
    final minutes = (totalTimeSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h ${minutes} min';
    }
    return '$minutes min';
  }

  PlayHistoryStats copyWith({
    int? totalPlays,
    int? totalTimeSeconds,
    DateTime? firstPlay,
    DateTime? lastPlay,
  }) {
    return PlayHistoryStats(
      totalPlays: totalPlays ?? this.totalPlays,
      totalTimeSeconds: totalTimeSeconds ?? this.totalTimeSeconds,
      firstPlay: firstPlay ?? this.firstPlay,
      lastPlay: lastPlay ?? this.lastPlay,
    );
  }
}

/// Play history tracking
class PlayHistory {
  final String version;
  final List<PlayEvent> plays;
  final Map<String, int> trackPlayCounts;
  final Map<String, int> albumPlayCounts;
  final Map<String, int> artistPlayCounts;
  final PlayHistoryStats stats;

  PlayHistory({
    this.version = '1.0',
    List<PlayEvent>? plays,
    Map<String, int>? trackPlayCounts,
    Map<String, int>? albumPlayCounts,
    Map<String, int>? artistPlayCounts,
    PlayHistoryStats? stats,
  })  : plays = plays ?? [],
        trackPlayCounts = trackPlayCounts ?? {},
        albumPlayCounts = albumPlayCounts ?? {},
        artistPlayCounts = artistPlayCounts ?? {},
        stats = stats ?? PlayHistoryStats();

  factory PlayHistory.fromJson(Map<String, dynamic> json) {
    return PlayHistory(
      version: json['version'] as String? ?? '1.0',
      plays: (json['plays'] as List<dynamic>?)
          ?.map((e) => PlayEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      trackPlayCounts:
          (json['track_play_counts'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as int),
      ),
      albumPlayCounts:
          (json['album_play_counts'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as int),
      ),
      artistPlayCounts:
          (json['artist_play_counts'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as int),
      ),
      stats: json['stats'] != null
          ? PlayHistoryStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'plays': plays.map((p) => p.toJson()).toList(),
      'track_play_counts': trackPlayCounts,
      'album_play_counts': albumPlayCounts,
      'artist_play_counts': artistPlayCounts,
      'stats': stats.toJson(),
    };
  }

  PlayHistory copyWith({
    String? version,
    List<PlayEvent>? plays,
    Map<String, int>? trackPlayCounts,
    Map<String, int>? albumPlayCounts,
    Map<String, int>? artistPlayCounts,
    PlayHistoryStats? stats,
  }) {
    return PlayHistory(
      version: version ?? this.version,
      plays: plays ?? this.plays,
      trackPlayCounts: trackPlayCounts ?? this.trackPlayCounts,
      albumPlayCounts: albumPlayCounts ?? this.albumPlayCounts,
      artistPlayCounts: artistPlayCounts ?? this.artistPlayCounts,
      stats: stats ?? this.stats,
    );
  }

  /// Record a play event
  PlayHistory recordPlay(PlayEvent event) {
    if (!event.countsAsPlay) return this;

    final newPlays = List<PlayEvent>.from(plays)..add(event);

    final newTrackCounts = Map<String, int>.from(trackPlayCounts);
    newTrackCounts[event.trackId] = (newTrackCounts[event.trackId] ?? 0) + 1;

    final newAlbumCounts = Map<String, int>.from(albumPlayCounts);
    if (event.albumId != null) {
      newAlbumCounts[event.albumId!] =
          (newAlbumCounts[event.albumId!] ?? 0) + 1;
    }

    final newArtistCounts = Map<String, int>.from(artistPlayCounts);
    if (event.artistId != null) {
      newArtistCounts[event.artistId!] =
          (newArtistCounts[event.artistId!] ?? 0) + 1;
    }

    return copyWith(
      plays: newPlays,
      trackPlayCounts: newTrackCounts,
      albumPlayCounts: newAlbumCounts,
      artistPlayCounts: newArtistCounts,
      stats: stats.copyWith(
        totalPlays: stats.totalPlays + 1,
        totalTimeSeconds: stats.totalTimeSeconds + event.durationPlayedSeconds,
        firstPlay: stats.firstPlay ?? event.playedAt,
        lastPlay: event.playedAt,
      ),
    );
  }

  /// Get top tracks by play count
  List<MapEntry<String, int>> getTopTracks({int limit = 10}) {
    final sorted = trackPlayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Get top albums by play count
  List<MapEntry<String, int>> getTopAlbums({int limit = 10}) {
    final sorted = albumPlayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Get top artists by play count
  List<MapEntry<String, int>> getTopArtists({int limit = 10}) {
    final sorted = artistPlayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Get plays within a time period
  List<PlayEvent> getPlaysInPeriod(DateTime start, DateTime end) {
    return plays
        .where((p) => p.playedAt.isAfter(start) && p.playedAt.isBefore(end))
        .toList();
  }

  /// Get total listening time for a period
  int getListeningTimeInPeriod(DateTime start, DateTime end) {
    return getPlaysInPeriod(start, end)
        .fold(0, (sum, p) => sum + p.durationPlayedSeconds);
  }

  /// Get play count for track
  int getTrackPlayCount(String trackId) {
    return trackPlayCounts[trackId] ?? 0;
  }

  /// Get play count for album
  int getAlbumPlayCount(String albumId) {
    return albumPlayCounts[albumId] ?? 0;
  }

  /// Get play count for artist
  int getArtistPlayCount(String artistId) {
    return artistPlayCounts[artistId] ?? 0;
  }
}
