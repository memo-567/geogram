/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Sort order for voice memo clips
enum VoiceMemoSortOrder {
  recordedAsc,
  recordedDesc,
  durationAsc,
  durationDesc,
}

/// Rating type options for voice memo clips
enum RatingType {
  stars, // 1-5 stars only
  likeDislike, // like/dislike only
  both, // both stars and like/dislike
}

/// Transcription data for a voice memo clip
class ClipTranscription {
  final String text;
  final String model;
  final DateTime transcribedAt;

  ClipTranscription({
    required this.text,
    required this.model,
    required this.transcribedAt,
  });

  factory ClipTranscription.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    final model = json['model'] as String?;
    final transcribedAtStr = json['transcribed_at'] as String?;

    if (text == null || model == null || transcribedAtStr == null) {
      throw FormatException(
        'Missing required transcription fields: '
        'text=${text != null}, model=${model != null}, transcribed_at=${transcribedAtStr != null}',
      );
    }

    return ClipTranscription(
      text: text,
      model: model,
      transcribedAt: DateTime.parse(transcribedAtStr),
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'model': model,
    'transcribed_at': transcribedAt.toIso8601String(),
  };

  ClipTranscription copyWith({
    String? text,
    String? model,
    DateTime? transcribedAt,
  }) {
    return ClipTranscription(
      text: text ?? this.text,
      model: model ?? this.model,
      transcribedAt: transcribedAt ?? this.transcribedAt,
    );
  }
}

/// Aggregated social data for a voice memo clip
class ClipSocialData {
  int likes;
  int dislikes;
  int starsTotal;
  int starsCount;
  List<String> commentIds;

  ClipSocialData({
    this.likes = 0,
    this.dislikes = 0,
    this.starsTotal = 0,
    this.starsCount = 0,
    List<String>? commentIds,
  }) : commentIds = commentIds ?? [];

  factory ClipSocialData.fromJson(Map<String, dynamic> json) {
    return ClipSocialData(
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
      starsTotal: json['stars_total'] as int? ?? 0,
      starsCount: json['stars_count'] as int? ?? 0,
      commentIds: (json['comment_ids'] as List<dynamic>?)
          ?.map((c) => c as String)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'likes': likes,
    'dislikes': dislikes,
    'stars_total': starsTotal,
    'stars_count': starsCount,
    if (commentIds.isNotEmpty) 'comment_ids': commentIds,
  };

  /// Get average star rating (0 if no ratings)
  double get averageStars => starsCount > 0 ? starsTotal / starsCount : 0;

  ClipSocialData copyWith({
    int? likes,
    int? dislikes,
    int? starsTotal,
    int? starsCount,
    List<String>? commentIds,
  }) {
    return ClipSocialData(
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      starsTotal: starsTotal ?? this.starsTotal,
      starsCount: starsCount ?? this.starsCount,
      commentIds: commentIds ?? List.from(this.commentIds),
    );
  }
}

/// Individual rating for a clip with NOSTR signature
class ClipRating {
  final String id;
  final String clipId;
  final String author;
  final DateTime createdAt;
  final int? stars; // 1-5 or null
  final bool? liked; // true=like, false=dislike, null=none
  final String? npub;
  final String? signature;
  final int? nostrCreatedAt;

  ClipRating({
    required this.id,
    required this.clipId,
    required this.author,
    required this.createdAt,
    this.stars,
    this.liked,
    this.npub,
    this.signature,
    this.nostrCreatedAt,
  });

  factory ClipRating.create({
    required String clipId,
    required String author,
    int? stars,
    bool? liked,
    String? npub,
    String? signature,
    int? nostrCreatedAt,
  }) {
    final now = DateTime.now();
    final id = 'rating-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return ClipRating(
      id: id,
      clipId: clipId,
      author: author,
      createdAt: now,
      stars: stars,
      liked: liked,
      npub: npub,
      signature: signature,
      nostrCreatedAt: nostrCreatedAt,
    );
  }

  factory ClipRating.fromJson(Map<String, dynamic> json) {
    return ClipRating(
      id: json['id'] as String,
      clipId: json['clip_id'] as String,
      author: json['author'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      stars: json['stars'] as int?,
      liked: json['liked'] as bool?,
      npub: json['npub'] as String?,
      signature: json['signature'] as String?,
      nostrCreatedAt: json['nostr_created_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'clip_id': clipId,
    'author': author,
    'created_at': createdAt.toIso8601String(),
    if (stars != null) 'stars': stars,
    if (liked != null) 'liked': liked,
    if (npub != null) 'npub': npub,
    if (signature != null) 'signature': signature,
    if (nostrCreatedAt != null) 'nostr_created_at': nostrCreatedAt,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// A single voice memo clip
class VoiceMemoClip {
  final String id;
  String title;
  String? description;
  final DateTime recordedAt;
  DateTime? finishedAt;
  int durationMs;
  String audioFile;
  ClipTranscription? transcription;
  List<String>? mergedFrom;
  ClipSocialData social;

  VoiceMemoClip({
    required this.id,
    required this.title,
    this.description,
    required this.recordedAt,
    this.finishedAt,
    required this.durationMs,
    required this.audioFile,
    this.transcription,
    this.mergedFrom,
    ClipSocialData? social,
  }) : social = social ?? ClipSocialData();

  factory VoiceMemoClip.create({
    required String title,
    String? description,
    required int durationMs,
    required String audioFile,
  }) {
    final now = DateTime.now();
    final id = 'clip-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return VoiceMemoClip(
      id: id,
      title: title,
      description: description,
      recordedAt: now,
      finishedAt: now,
      durationMs: durationMs,
      audioFile: audioFile,
    );
  }

  factory VoiceMemoClip.fromJson(Map<String, dynamic> json) {
    ClipTranscription? transcription;
    final transcriptionJson = json['transcription'] as Map<String, dynamic>?;
    if (transcriptionJson != null) {
      transcription = ClipTranscription.fromJson(transcriptionJson);
    }

    ClipSocialData? social;
    final socialJson = json['social'] as Map<String, dynamic>?;
    if (socialJson != null) {
      social = ClipSocialData.fromJson(socialJson);
    }

    return VoiceMemoClip(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
      durationMs: json['duration_ms'] as int,
      audioFile: json['audio_file'] as String,
      transcription: transcription,
      mergedFrom: (json['merged_from'] as List<dynamic>?)
          ?.map((m) => m as String)
          .toList(),
      social: social,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'recorded_at': recordedAt.toIso8601String(),
    if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
    'duration_ms': durationMs,
    'audio_file': audioFile,
    if (transcription != null) 'transcription': transcription!.toJson(),
    if (mergedFrom != null && mergedFrom!.isNotEmpty) 'merged_from': mergedFrom,
    'social': social.toJson(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Get formatted duration string (MM:SS or HH:MM:SS)
  String get durationFormatted {
    final totalSeconds = durationMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  VoiceMemoClip copyWith({
    String? title,
    String? description,
    DateTime? finishedAt,
    int? durationMs,
    String? audioFile,
    ClipTranscription? transcription,
    bool clearTranscription = false,
    List<String>? mergedFrom,
    ClipSocialData? social,
  }) {
    return VoiceMemoClip(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      recordedAt: recordedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationMs: durationMs ?? this.durationMs,
      audioFile: audioFile ?? this.audioFile,
      transcription: clearTranscription ? null : (transcription ?? this.transcription),
      mergedFrom: mergedFrom ?? this.mergedFrom,
      social: social ?? this.social,
    );
  }
}

/// Settings for voice memo document
class VoiceMemoSettings {
  final bool allowComments;
  final bool allowRatings;
  final RatingType ratingType;
  final VoiceMemoSortOrder defaultSort;
  final bool showTranscriptions;

  VoiceMemoSettings({
    this.allowComments = true,
    this.allowRatings = true,
    this.ratingType = RatingType.both,
    this.defaultSort = VoiceMemoSortOrder.recordedDesc,
    this.showTranscriptions = true,
  });

  factory VoiceMemoSettings.fromJson(Map<String, dynamic> json) {
    return VoiceMemoSettings(
      allowComments: json['allow_comments'] as bool? ?? true,
      allowRatings: json['allow_ratings'] as bool? ?? true,
      ratingType: RatingType.values.firstWhere(
        (r) => r.name == json['rating_type'],
        orElse: () => RatingType.both,
      ),
      defaultSort: VoiceMemoSortOrder.values.firstWhere(
        (s) => s.name == json['default_sort'],
        orElse: () => VoiceMemoSortOrder.recordedDesc,
      ),
      showTranscriptions: json['show_transcriptions'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'allow_comments': allowComments,
    'allow_ratings': allowRatings,
    'rating_type': ratingType.name,
    'default_sort': defaultSort.name,
    'show_transcriptions': showTranscriptions,
  };

  VoiceMemoSettings copyWith({
    bool? allowComments,
    bool? allowRatings,
    RatingType? ratingType,
    VoiceMemoSortOrder? defaultSort,
    bool? showTranscriptions,
  }) {
    return VoiceMemoSettings(
      allowComments: allowComments ?? this.allowComments,
      allowRatings: allowRatings ?? this.allowRatings,
      ratingType: ratingType ?? this.ratingType,
      defaultSort: defaultSort ?? this.defaultSort,
      showTranscriptions: showTranscriptions ?? this.showTranscriptions,
    );
  }
}

/// Main voice memo document content (stored in content/main.json)
class VoiceMemoContent {
  final String id;
  final String schema;
  String title;
  int version;
  final DateTime created;
  DateTime modified;
  VoiceMemoSettings settings;
  List<String> clips; // List of clip IDs

  VoiceMemoContent({
    required this.id,
    this.schema = 'ndf-voicememo-1.0',
    required this.title,
    this.version = 1,
    required this.created,
    required this.modified,
    VoiceMemoSettings? settings,
    List<String>? clips,
  }) : settings = settings ?? VoiceMemoSettings(),
       clips = clips ?? [];

  factory VoiceMemoContent.create({required String title}) {
    final now = DateTime.now();
    final id = 'voicememo-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return VoiceMemoContent(
      id: id,
      title: title,
      created: now,
      modified: now,
    );
  }

  factory VoiceMemoContent.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final id = json['id'] as String? ??
        'voicememo-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final createdStr = json['created'] as String?;
    final modifiedStr = json['modified'] as String?;
    final created = createdStr != null ? DateTime.parse(createdStr) : now;
    final modified = modifiedStr != null ? DateTime.parse(modifiedStr) : now;

    VoiceMemoSettings? settings;
    final settingsJson = json['settings'] as Map<String, dynamic>?;
    if (settingsJson != null) {
      settings = VoiceMemoSettings.fromJson(settingsJson);
    }

    return VoiceMemoContent(
      id: id,
      schema: json['schema'] as String? ?? 'ndf-voicememo-1.0',
      title: json['title'] as String? ?? 'Untitled Voice Memo',
      version: json['version'] as int? ?? 1,
      created: created,
      modified: modified,
      settings: settings,
      clips: (json['clips'] as List<dynamic>?)
          ?.map((c) => c as String)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'voicememo',
    'id': id,
    'schema': schema,
    'title': title,
    'version': version,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'settings': settings.toJson(),
    'clips': clips,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Touch the modified timestamp and increment version
  void touch() {
    modified = DateTime.now();
    version++;
  }

  /// Add a clip ID
  void addClip(String clipId) {
    clips.add(clipId);
    touch();
  }

  /// Remove a clip ID
  void removeClip(String clipId) {
    clips.remove(clipId);
    touch();
  }

  /// Get total duration of all clips in milliseconds
  int getTotalDurationMs(List<VoiceMemoClip> clipList) {
    return clipList.fold(0, (sum, clip) => sum + clip.durationMs);
  }

  /// Get formatted total duration string
  String getTotalDurationFormatted(List<VoiceMemoClip> clipList) {
    final totalMs = getTotalDurationMs(clipList);
    final totalSeconds = totalMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
