/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// An RSS/Atom feed post
class RssPost {
  final String id;
  final String title;
  final String? author;
  final DateTime publishedAt;
  final DateTime fetchedAt;
  final String url;
  final String? guid;
  final String? summary;
  final int? wordCount;
  final int? readTimeMinutes;
  final List<String> categories;
  final List<String> tags;
  final List<PostImage> images;
  bool isRead;
  bool isStarred;

  RssPost({
    required this.id,
    required this.title,
    this.author,
    required this.publishedAt,
    required this.fetchedAt,
    required this.url,
    this.guid,
    this.summary,
    this.wordCount,
    this.readTimeMinutes,
    List<String>? categories,
    List<String>? tags,
    List<PostImage>? images,
    this.isRead = false,
    this.isStarred = false,
  })  : categories = categories ?? [],
        tags = tags ?? [],
        images = images ?? [];

  factory RssPost.fromJson(Map<String, dynamic> json) {
    return RssPost(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      publishedAt: DateTime.parse(json['published_at'] as String),
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
      url: json['url'] as String,
      guid: json['guid'] as String?,
      summary: json['summary'] as String?,
      wordCount: json['word_count'] as int?,
      readTimeMinutes: json['read_time_minutes'] as int?,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => PostImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isRead: json['is_read'] as bool? ?? false,
      isStarred: json['is_starred'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'published_at': publishedAt.toIso8601String(),
      'fetched_at': fetchedAt.toIso8601String(),
      'url': url,
      'guid': guid,
      'summary': summary,
      'word_count': wordCount,
      'read_time_minutes': readTimeMinutes,
      'categories': categories,
      'tags': tags,
      'images': images.map((e) => e.toJson()).toList(),
      'is_read': isRead,
      'is_starred': isStarred,
    };
  }

  RssPost copyWith({
    String? id,
    String? title,
    String? author,
    DateTime? publishedAt,
    DateTime? fetchedAt,
    String? url,
    String? guid,
    String? summary,
    int? wordCount,
    int? readTimeMinutes,
    List<String>? categories,
    List<String>? tags,
    List<PostImage>? images,
    bool? isRead,
    bool? isStarred,
  }) {
    return RssPost(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      url: url ?? this.url,
      guid: guid ?? this.guid,
      summary: summary ?? this.summary,
      wordCount: wordCount ?? this.wordCount,
      readTimeMinutes: readTimeMinutes ?? this.readTimeMinutes,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      images: images ?? this.images,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
    );
  }
}

/// Image attached to a post
class PostImage {
  final String originalUrl;
  final String localFilename;
  final String? altText;

  PostImage({
    required this.originalUrl,
    required this.localFilename,
    this.altText,
  });

  factory PostImage.fromJson(Map<String, dynamic> json) {
    return PostImage(
      originalUrl: json['original_url'] as String,
      localFilename: json['local_filename'] as String,
      altText: json['alt_text'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'original_url': originalUrl,
      'local_filename': localFilename,
      'alt_text': altText,
    };
  }
}

/// Parsed RSS feed item (before conversion to RssPost)
class RssFeedItem {
  final String? id;
  final String title;
  final String url;
  final String? author;
  final DateTime? publishedAt;
  final String? summary;
  final String? content;
  final List<String> categories;
  final List<String> imageUrls;

  RssFeedItem({
    this.id,
    required this.title,
    required this.url,
    this.author,
    this.publishedAt,
    this.summary,
    this.content,
    List<String>? categories,
    List<String>? imageUrls,
  })  : categories = categories ?? [],
        imageUrls = imageUrls ?? [];
}
