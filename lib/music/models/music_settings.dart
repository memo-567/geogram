/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Music app settings
class MusicSettings {
  final String version;
  final List<String> sourceFolders;
  final bool scanOnStartup;
  final bool watchFolders;
  final PlaybackSettings playback;
  final DisplaySettings display;
  final LibrarySettings library;
  final OnlineSettings online;
  final CacheSettings cache;

  MusicSettings({
    this.version = '1.0',
    List<String>? sourceFolders,
    this.scanOnStartup = true,
    this.watchFolders = true,
    PlaybackSettings? playback,
    DisplaySettings? display,
    LibrarySettings? library,
    OnlineSettings? online,
    CacheSettings? cache,
  })  : sourceFolders = sourceFolders ?? [],
        playback = playback ?? PlaybackSettings(),
        display = display ?? DisplaySettings(),
        library = library ?? LibrarySettings(),
        online = online ?? OnlineSettings(),
        cache = cache ?? CacheSettings();

  factory MusicSettings.fromJson(Map<String, dynamic> json) {
    return MusicSettings(
      version: json['version'] as String? ?? '1.0',
      sourceFolders: (json['source_folders'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      scanOnStartup: json['scan_on_startup'] as bool? ?? true,
      watchFolders: json['watch_folders'] as bool? ?? true,
      playback: json['playback'] != null
          ? PlaybackSettings.fromJson(json['playback'] as Map<String, dynamic>)
          : null,
      display: json['display'] != null
          ? DisplaySettings.fromJson(json['display'] as Map<String, dynamic>)
          : null,
      library: json['library'] != null
          ? LibrarySettings.fromJson(json['library'] as Map<String, dynamic>)
          : null,
      online: json['online'] != null
          ? OnlineSettings.fromJson(json['online'] as Map<String, dynamic>)
          : null,
      cache: json['cache'] != null
          ? CacheSettings.fromJson(json['cache'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'source_folders': sourceFolders,
      'scan_on_startup': scanOnStartup,
      'watch_folders': watchFolders,
      'playback': playback.toJson(),
      'display': display.toJson(),
      'library': library.toJson(),
      'online': online.toJson(),
      'cache': cache.toJson(),
    };
  }

  MusicSettings copyWith({
    String? version,
    List<String>? sourceFolders,
    bool? scanOnStartup,
    bool? watchFolders,
    PlaybackSettings? playback,
    DisplaySettings? display,
    LibrarySettings? library,
    OnlineSettings? online,
    CacheSettings? cache,
  }) {
    return MusicSettings(
      version: version ?? this.version,
      sourceFolders: sourceFolders ?? this.sourceFolders,
      scanOnStartup: scanOnStartup ?? this.scanOnStartup,
      watchFolders: watchFolders ?? this.watchFolders,
      playback: playback ?? this.playback,
      display: display ?? this.display,
      library: library ?? this.library,
      online: online ?? this.online,
      cache: cache ?? this.cache,
    );
  }
}

/// Playback settings
class PlaybackSettings {
  final bool gapless;
  final int crossfadeSeconds;
  final String replayGain; // 'off', 'track', 'album'
  final bool volumeNormalization;

  PlaybackSettings({
    this.gapless = true,
    this.crossfadeSeconds = 0,
    this.replayGain = 'album',
    this.volumeNormalization = true,
  });

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      gapless: json['gapless'] as bool? ?? true,
      crossfadeSeconds: json['crossfade_seconds'] as int? ?? 0,
      replayGain: json['replay_gain'] as String? ?? 'album',
      volumeNormalization: json['volume_normalization'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gapless': gapless,
      'crossfade_seconds': crossfadeSeconds,
      'replay_gain': replayGain,
      'volume_normalization': volumeNormalization,
    };
  }

  PlaybackSettings copyWith({
    bool? gapless,
    int? crossfadeSeconds,
    String? replayGain,
    bool? volumeNormalization,
  }) {
    return PlaybackSettings(
      gapless: gapless ?? this.gapless,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      replayGain: replayGain ?? this.replayGain,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
    );
  }
}

/// Album sort options
enum AlbumSortOrder {
  artist,
  year,
  name,
  added,
  mostPlayed,
}

/// Display settings
class DisplaySettings {
  final AlbumSortOrder albumSort;
  final bool showTrackNumbers;
  final String artworkSize; // 'small', 'medium', 'large'

  DisplaySettings({
    this.albumSort = AlbumSortOrder.artist,
    this.showTrackNumbers = true,
    this.artworkSize = 'medium',
  });

  factory DisplaySettings.fromJson(Map<String, dynamic> json) {
    return DisplaySettings(
      albumSort: AlbumSortOrder.values.firstWhere(
        (e) => e.name == json['album_sort'],
        orElse: () => AlbumSortOrder.artist,
      ),
      showTrackNumbers: json['show_track_numbers'] as bool? ?? true,
      artworkSize: json['artwork_size'] as String? ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'album_sort': albumSort.name,
      'show_track_numbers': showTrackNumbers,
      'artwork_size': artworkSize,
    };
  }

  DisplaySettings copyWith({
    AlbumSortOrder? albumSort,
    bool? showTrackNumbers,
    String? artworkSize,
  }) {
    return DisplaySettings(
      albumSort: albumSort ?? this.albumSort,
      showTrackNumbers: showTrackNumbers ?? this.showTrackNumbers,
      artworkSize: artworkSize ?? this.artworkSize,
    );
  }
}

/// Library settings
class LibrarySettings {
  final bool groupCompilations;
  final int compilationThreshold;

  LibrarySettings({
    this.groupCompilations = true,
    this.compilationThreshold = 3,
  });

  factory LibrarySettings.fromJson(Map<String, dynamic> json) {
    return LibrarySettings(
      groupCompilations: json['group_compilations'] as bool? ?? true,
      compilationThreshold: json['compilation_threshold'] as int? ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'group_compilations': groupCompilations,
      'compilation_threshold': compilationThreshold,
    };
  }

  LibrarySettings copyWith({
    bool? groupCompilations,
    int? compilationThreshold,
  }) {
    return LibrarySettings(
      groupCompilations: groupCompilations ?? this.groupCompilations,
      compilationThreshold: compilationThreshold ?? this.compilationThreshold,
    );
  }
}

/// Online feature settings
class OnlineSettings {
  final bool autoFetchCovers;
  final List<String> coverSources;
  final String coverSize; // 'small', 'medium', 'large'
  final bool autoDetectGenre;
  final bool fingerprintUntaggedOnly;
  final bool autoFetchLyrics;
  final String? acoustidApiKey;

  OnlineSettings({
    this.autoFetchCovers = true,
    List<String>? coverSources,
    this.coverSize = 'large',
    this.autoDetectGenre = true,
    this.fingerprintUntaggedOnly = true,
    this.autoFetchLyrics = true,
    this.acoustidApiKey,
  }) : coverSources = coverSources ?? ['coverartarchive', 'musicbrainz'];

  factory OnlineSettings.fromJson(Map<String, dynamic> json) {
    return OnlineSettings(
      autoFetchCovers: json['auto_fetch_covers'] as bool? ?? true,
      coverSources: (json['cover_sources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['coverartarchive', 'musicbrainz'],
      coverSize: json['cover_size'] as String? ?? 'large',
      autoDetectGenre: json['auto_detect_genre'] as bool? ?? true,
      fingerprintUntaggedOnly:
          json['fingerprint_untagged_only'] as bool? ?? true,
      autoFetchLyrics: json['auto_fetch_lyrics'] as bool? ?? true,
      acoustidApiKey: json['acoustid_api_key'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_fetch_covers': autoFetchCovers,
      'cover_sources': coverSources,
      'cover_size': coverSize,
      'auto_detect_genre': autoDetectGenre,
      'fingerprint_untagged_only': fingerprintUntaggedOnly,
      'auto_fetch_lyrics': autoFetchLyrics,
      if (acoustidApiKey != null) 'acoustid_api_key': acoustidApiKey,
    };
  }

  OnlineSettings copyWith({
    bool? autoFetchCovers,
    List<String>? coverSources,
    String? coverSize,
    bool? autoDetectGenre,
    bool? fingerprintUntaggedOnly,
    bool? autoFetchLyrics,
    String? acoustidApiKey,
  }) {
    return OnlineSettings(
      autoFetchCovers: autoFetchCovers ?? this.autoFetchCovers,
      coverSources: coverSources ?? this.coverSources,
      coverSize: coverSize ?? this.coverSize,
      autoDetectGenre: autoDetectGenre ?? this.autoDetectGenre,
      fingerprintUntaggedOnly:
          fingerprintUntaggedOnly ?? this.fingerprintUntaggedOnly,
      autoFetchLyrics: autoFetchLyrics ?? this.autoFetchLyrics,
      acoustidApiKey: acoustidApiKey ?? this.acoustidApiKey,
    );
  }
}

/// Cache settings
class CacheSettings {
  final int artworkQuality;
  final int artworkMaxSize;
  final int maxCacheSizeMb;

  CacheSettings({
    this.artworkQuality = 80,
    this.artworkMaxSize = 500,
    this.maxCacheSizeMb = 500,
  });

  factory CacheSettings.fromJson(Map<String, dynamic> json) {
    return CacheSettings(
      artworkQuality: json['artwork_quality'] as int? ?? 80,
      artworkMaxSize: json['artwork_max_size'] as int? ?? 500,
      maxCacheSizeMb: json['max_cache_size_mb'] as int? ?? 500,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'artwork_quality': artworkQuality,
      'artwork_max_size': artworkMaxSize,
      'max_cache_size_mb': maxCacheSizeMb,
    };
  }

  CacheSettings copyWith({
    int? artworkQuality,
    int? artworkMaxSize,
    int? maxCacheSizeMb,
  }) {
    return CacheSettings(
      artworkQuality: artworkQuality ?? this.artworkQuality,
      artworkMaxSize: artworkMaxSize ?? this.artworkMaxSize,
      maxCacheSizeMb: maxCacheSizeMb ?? this.maxCacheSizeMb,
    );
  }
}
