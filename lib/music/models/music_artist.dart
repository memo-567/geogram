/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// A music artist
class MusicArtist {
  final String id;
  final String name;
  final String? sortName;
  final int albumCount;
  final int trackCount;
  final String? artwork;
  final String? musicbrainzArtistId;

  MusicArtist({
    required this.id,
    required this.name,
    this.sortName,
    this.albumCount = 0,
    this.trackCount = 0,
    this.artwork,
    this.musicbrainzArtistId,
  });

  factory MusicArtist.fromJson(Map<String, dynamic> json) {
    return MusicArtist(
      id: json['id'] as String,
      name: json['name'] as String,
      sortName: json['sort_name'] as String?,
      albumCount: json['album_count'] as int? ?? 0,
      trackCount: json['track_count'] as int? ?? 0,
      artwork: json['artwork'] as String?,
      musicbrainzArtistId: json['musicbrainz_artist_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (sortName != null) 'sort_name': sortName,
      'album_count': albumCount,
      'track_count': trackCount,
      if (artwork != null) 'artwork': artwork,
      if (musicbrainzArtistId != null)
        'musicbrainz_artist_id': musicbrainzArtistId,
    };
  }

  MusicArtist copyWith({
    String? id,
    String? name,
    String? sortName,
    int? albumCount,
    int? trackCount,
    String? artwork,
    String? musicbrainzArtistId,
  }) {
    return MusicArtist(
      id: id ?? this.id,
      name: name ?? this.name,
      sortName: sortName ?? this.sortName,
      albumCount: albumCount ?? this.albumCount,
      trackCount: trackCount ?? this.trackCount,
      artwork: artwork ?? this.artwork,
      musicbrainzArtistId: musicbrainzArtistId ?? this.musicbrainzArtistId,
    );
  }

  /// Get display name (name or sort name if different)
  String get displayName => name;

  /// Get sort key for alphabetical sorting
  String get sortKey {
    final key = (sortName ?? name).toLowerCase();
    // Remove common prefixes for better sorting
    if (key.startsWith('the ')) return key.substring(4);
    if (key.startsWith('a ')) return key.substring(2);
    if (key.startsWith('an ')) return key.substring(3);
    return key;
  }

  /// Generate artist ID from name
  static String generateId(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .trim();
    return 'artist_$normalized';
  }
}
