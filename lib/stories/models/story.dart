/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'story_content.dart';

/// Story metadata from ndf.json
class Story {
  /// NDF format version
  final String ndfVersion;

  /// Document type (always 'story')
  final String type;

  /// Internal UUID (remains constant, used for sync/tracking)
  final String id;

  /// Display name (determines filename on disk)
  final String title;

  /// Optional description
  final String? description;

  /// Asset reference to logo
  final String? logo;

  /// Asset reference to preview image
  final String? thumbnail;

  /// ISO 639-1 language code
  final String? language;

  /// Creation timestamp
  final DateTime created;

  /// Last modification timestamp
  final DateTime modified;

  /// Revision counter
  final int revision;

  /// Keywords for categorization
  final List<String> tags;

  /// SHA256 hash of content
  final String? contentHash;

  /// Path to the NDF file on disk
  final String? filePath;

  /// Story content (loaded on demand)
  final StoryContent? content;

  const Story({
    this.ndfVersion = '1.0.0',
    this.type = 'story',
    required this.id,
    required this.title,
    this.description,
    this.logo,
    this.thumbnail,
    this.language,
    required this.created,
    required this.modified,
    this.revision = 1,
    this.tags = const [],
    this.contentHash,
    this.filePath,
    this.content,
  });

  /// Generate filesystem-safe filename from title
  String get filename {
    var name = title.toLowerCase();

    // Replace spaces with hyphens
    name = name.replaceAll(' ', '-');

    // Remove invalid filesystem characters: \ / : * ? " < > |
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');

    // Replace accented characters with ASCII equivalents
    name = _removeAccents(name);

    // Replace consecutive hyphens with single hyphen
    name = name.replaceAll(RegExp(r'-+'), '-');

    // Trim hyphens from start/end
    name = name.replaceAll(RegExp(r'^-+|-+$'), '');

    // Limit to 100 characters
    if (name.length > 100) {
      name = name.substring(0, 100);
      // Don't end with a hyphen after truncation
      name = name.replaceAll(RegExp(r'-+$'), '');
    }

    // Ensure we have a valid name
    if (name.isEmpty) {
      name = 'story';
    }

    return '$name.ndf';
  }

  static String _removeAccents(String input) {
    const accents = 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿ';
    const withoutAccents = 'aaaaaaaceeeeiiiinooooooouuuuyy';

    var result = input;
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], withoutAccents[i]);
    }
    return result;
  }

  /// Get scene count from content
  int get sceneCount => content?.sceneCount ?? 0;

  factory Story.create({
    required String title,
    String? description,
  }) {
    final now = DateTime.now();
    return Story(
      id: _generateUuid(),
      title: title,
      description: description,
      created: now,
      modified: now,
    );
  }

  static String _generateUuid() {
    // Simple UUID v4 generation
    final random = DateTime.now().millisecondsSinceEpoch;
    return '${_hex(random, 8)}-${_hex(random >> 32, 4)}-4${_hex(random >> 48, 3)}-${_hex(0x8 | (random & 0x3), 1)}${_hex(random >> 52, 3)}-${_hex(random >> 60, 12)}';
  }

  static String _hex(int value, int length) {
    return value.toRadixString(16).padLeft(length, '0').substring(0, length);
  }

  factory Story.fromJson(Map<String, dynamic> json, {String? filePath}) {
    return Story(
      ndfVersion: json['ndf'] as String? ?? '1.0.0',
      type: json['type'] as String? ?? 'story',
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      logo: json['logo'] as String?,
      thumbnail: json['thumbnail'] as String?,
      language: json['language'] as String?,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      contentHash: json['content_hash'] as String?,
      filePath: filePath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ndf': ndfVersion,
      'type': type,
      'id': id,
      'title': title,
      if (description != null) 'description': description,
      if (logo != null) 'logo': logo,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (language != null) 'language': language,
      'created': created.toIso8601String(),
      'modified': modified.toIso8601String(),
      'revision': revision,
      if (tags.isNotEmpty) 'tags': tags,
      if (contentHash != null) 'content_hash': contentHash,
      'required_features': ['story_viewer'],
      'extensions': <String>[],
    };
  }

  Story copyWith({
    String? ndfVersion,
    String? type,
    String? id,
    String? title,
    String? description,
    String? logo,
    String? thumbnail,
    String? language,
    DateTime? created,
    DateTime? modified,
    int? revision,
    List<String>? tags,
    String? contentHash,
    String? filePath,
    StoryContent? content,
  }) {
    return Story(
      ndfVersion: ndfVersion ?? this.ndfVersion,
      type: type ?? this.type,
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      logo: logo ?? this.logo,
      thumbnail: thumbnail ?? this.thumbnail,
      language: language ?? this.language,
      created: created ?? this.created,
      modified: modified ?? this.modified,
      revision: revision ?? this.revision,
      tags: tags ?? this.tags,
      contentHash: contentHash ?? this.contentHash,
      filePath: filePath ?? this.filePath,
      content: content ?? this.content,
    );
  }

  /// Update modified timestamp and increment revision
  Story touch() {
    return copyWith(
      modified: DateTime.now(),
      revision: revision + 1,
    );
  }
}
