/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Audio format types
enum AudioFormat {
  flac,
  mp3,
  m4a,
  aac,
  ogg,
  opus,
  wav,
  aiff,
  unknown,
}

/// A music track with metadata
class MusicTrack {
  final String id;
  final String filePath;
  final String title;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final int durationSeconds;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? channels;
  final AudioFormat format;
  final int fileSizeBytes;
  final bool hasEmbeddedArtwork;
  final DateTime? modifiedAt;
  final DateTime? addedAt;

  MusicTrack({
    required this.id,
    required this.filePath,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    required this.durationSeconds,
    this.bitrateKbps,
    this.sampleRateHz,
    this.channels,
    this.format = AudioFormat.unknown,
    this.fileSizeBytes = 0,
    this.hasEmbeddedArtwork = false,
    this.modifiedAt,
    this.addedAt,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String,
      filePath: json['file_path'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      artistId: json['artist_id'] as String?,
      album: json['album'] as String?,
      albumId: json['album_id'] as String?,
      albumArtist: json['album_artist'] as String?,
      trackNumber: json['track_number'] as int?,
      discNumber: json['disc_number'] as int?,
      year: json['year'] as int?,
      genre: json['genre'] as String?,
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      bitrateKbps: json['bitrate_kbps'] as int?,
      sampleRateHz: json['sample_rate_hz'] as int?,
      channels: json['channels'] as int?,
      format: AudioFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => AudioFormat.unknown,
      ),
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      hasEmbeddedArtwork: json['has_embedded_artwork'] as bool? ?? false,
      modifiedAt: json['modified_at'] != null
          ? DateTime.parse(json['modified_at'] as String)
          : null,
      addedAt: json['added_at'] != null
          ? DateTime.parse(json['added_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_path': filePath,
      'title': title,
      'artist': artist,
      if (artistId != null) 'artist_id': artistId,
      if (album != null) 'album': album,
      if (albumId != null) 'album_id': albumId,
      if (albumArtist != null) 'album_artist': albumArtist,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (year != null) 'year': year,
      if (genre != null) 'genre': genre,
      'duration_seconds': durationSeconds,
      if (bitrateKbps != null) 'bitrate_kbps': bitrateKbps,
      if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
      if (channels != null) 'channels': channels,
      'format': format.name,
      'file_size_bytes': fileSizeBytes,
      'has_embedded_artwork': hasEmbeddedArtwork,
      if (modifiedAt != null) 'modified_at': modifiedAt!.toIso8601String(),
      if (addedAt != null) 'added_at': addedAt!.toIso8601String(),
    };
  }

  MusicTrack copyWith({
    String? id,
    String? filePath,
    String? title,
    String? artist,
    String? artistId,
    String? album,
    String? albumId,
    String? albumArtist,
    int? trackNumber,
    int? discNumber,
    int? year,
    String? genre,
    int? durationSeconds,
    int? bitrateKbps,
    int? sampleRateHz,
    int? channels,
    AudioFormat? format,
    int? fileSizeBytes,
    bool? hasEmbeddedArtwork,
    DateTime? modifiedAt,
    DateTime? addedAt,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistId: artistId ?? this.artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      channels: channels ?? this.channels,
      format: format ?? this.format,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      hasEmbeddedArtwork: hasEmbeddedArtwork ?? this.hasEmbeddedArtwork,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  /// Get formatted duration string (mm:ss or h:mm:ss)
  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get formatted file size (KB, MB, GB)
  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Get audio format from file extension
  static AudioFormat formatFromExtension(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'flac':
        return AudioFormat.flac;
      case 'mp3':
        return AudioFormat.mp3;
      case 'm4a':
        return AudioFormat.m4a;
      case 'aac':
        return AudioFormat.aac;
      case 'ogg':
        return AudioFormat.ogg;
      case 'opus':
        return AudioFormat.opus;
      case 'wav':
        return AudioFormat.wav;
      case 'aiff':
      case 'aif':
        return AudioFormat.aiff;
      default:
        return AudioFormat.unknown;
    }
  }

  /// Check if file is a supported audio format
  static bool isSupportedFormat(String path) {
    return formatFromExtension(path) != AudioFormat.unknown;
  }

  /// List of supported audio extensions
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
