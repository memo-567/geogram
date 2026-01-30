/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Artwork source type
enum ArtworkSource {
  folder, // cover.jpg in folder
  embedded, // Embedded in audio file
  downloaded, // Downloaded from online
  none, // No artwork
}

/// A music album
class MusicAlbum {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final int? year;
  final String? genre;
  final List<String>? genres;
  final int trackCount;
  final int totalDurationSeconds;
  final String folderPath;
  final String? artwork;
  final ArtworkSource artworkSource;
  final int discCount;
  final bool isCompilation;
  final DateTime? addedAt;

  // Online metadata
  final String? musicbrainzAlbumId;
  final String? musicbrainzArtistId;
  final int? discogsId;

  MusicAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.year,
    this.genre,
    this.genres,
    this.trackCount = 0,
    this.totalDurationSeconds = 0,
    required this.folderPath,
    this.artwork,
    this.artworkSource = ArtworkSource.none,
    this.discCount = 1,
    this.isCompilation = false,
    this.addedAt,
    this.musicbrainzAlbumId,
    this.musicbrainzArtistId,
    this.discogsId,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> json) {
    return MusicAlbum(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      artistId: json['artist_id'] as String?,
      year: json['year'] as int?,
      genre: json['genre'] as String?,
      genres: (json['genres'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      trackCount: json['track_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      folderPath: json['folder_path'] as String,
      artwork: json['artwork'] as String?,
      artworkSource: ArtworkSource.values.firstWhere(
        (s) => s.name == json['artwork_source'],
        orElse: () => ArtworkSource.none,
      ),
      discCount: json['disc_count'] as int? ?? 1,
      isCompilation: json['is_compilation'] as bool? ?? false,
      addedAt: json['added_at'] != null
          ? DateTime.parse(json['added_at'] as String)
          : null,
      musicbrainzAlbumId: json['musicbrainz_album_id'] as String?,
      musicbrainzArtistId: json['musicbrainz_artist_id'] as String?,
      discogsId: json['discogs_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (year != null) 'year': year,
      if (genre != null) 'genre': genre,
      if (genres != null) 'genres': genres,
      'track_count': trackCount,
      'total_duration_seconds': totalDurationSeconds,
      'folder_path': folderPath,
      if (artwork != null) 'artwork': artwork,
      'artwork_source': artworkSource.name,
      'disc_count': discCount,
      'is_compilation': isCompilation,
      if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
      if (musicbrainzAlbumId != null) 'musicbrainz_album_id': musicbrainzAlbumId,
      if (musicbrainzArtistId != null)
        'musicbrainz_artist_id': musicbrainzArtistId,
      if (discogsId != null) 'discogs_id': discogsId,
    };
  }

  MusicAlbum copyWith({
    String? id,
    String? title,
    String? artist,
    String? artistId,
    int? year,
    String? genre,
    List<String>? genres,
    int? trackCount,
    int? totalDurationSeconds,
    String? folderPath,
    String? artwork,
    ArtworkSource? artworkSource,
    int? discCount,
    bool? isCompilation,
    DateTime? addedAt,
    String? musicbrainzAlbumId,
    String? musicbrainzArtistId,
    int? discogsId,
  }) {
    return MusicAlbum(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      genres: genres ?? this.genres,
      trackCount: trackCount ?? this.trackCount,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      folderPath: folderPath ?? this.folderPath,
      artwork: artwork ?? this.artwork,
      artworkSource: artworkSource ?? this.artworkSource,
      discCount: discCount ?? this.discCount,
      isCompilation: isCompilation ?? this.isCompilation,
      addedAt: addedAt ?? this.addedAt,
      musicbrainzAlbumId: musicbrainzAlbumId ?? this.musicbrainzAlbumId,
      musicbrainzArtistId: musicbrainzArtistId ?? this.musicbrainzArtistId,
      discogsId: discogsId ?? this.discogsId,
    );
  }

  /// Get formatted total duration string
  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h ${minutes} min';
    }
    return '$minutes min';
  }

  /// Display string: "Artist - Album (Year)"
  String get displayTitle {
    if (year != null) {
      return '$artist - $title ($year)';
    }
    return '$artist - $title';
  }
}

/// Album cover metadata saved alongside music files
class AlbumCoverMetadata {
  final String album;
  final String artist;
  final int? year;
  final String? genre;
  final List<String>? genres;
  final String? musicbrainzAlbumId;
  final String? musicbrainzArtistId;
  final int? discogsId;
  final String? coverSource;
  final String? coverUrl;
  final DateTime? fetchedAt;

  AlbumCoverMetadata({
    required this.album,
    required this.artist,
    this.year,
    this.genre,
    this.genres,
    this.musicbrainzAlbumId,
    this.musicbrainzArtistId,
    this.discogsId,
    this.coverSource,
    this.coverUrl,
    this.fetchedAt,
  });

  factory AlbumCoverMetadata.fromJson(Map<String, dynamic> json) {
    return AlbumCoverMetadata(
      album: json['album'] as String,
      artist: json['artist'] as String,
      year: json['year'] as int?,
      genre: json['genre'] as String?,
      genres: (json['genres'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      musicbrainzAlbumId: json['musicbrainz_album_id'] as String?,
      musicbrainzArtistId: json['musicbrainz_artist_id'] as String?,
      discogsId: json['discogs_id'] as int?,
      coverSource: json['cover_source'] as String?,
      coverUrl: json['cover_url'] as String?,
      fetchedAt: json['fetched_at'] != null
          ? DateTime.parse(json['fetched_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'album': album,
      'artist': artist,
      if (year != null) 'year': year,
      if (genre != null) 'genre': genre,
      if (genres != null) 'genres': genres,
      if (musicbrainzAlbumId != null) 'musicbrainz_album_id': musicbrainzAlbumId,
      if (musicbrainzArtistId != null)
        'musicbrainz_artist_id': musicbrainzArtistId,
      if (discogsId != null) 'discogs_id': discogsId,
      if (coverSource != null) 'cover_source': coverSource,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String(),
    };
  }
}
