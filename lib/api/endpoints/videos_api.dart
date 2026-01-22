/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Videos API endpoints.
 */

import '../api.dart';

/// Video summary (from list)
class VideoSummary {
  final String id;
  final String? title;
  final String? description;
  final String? author;
  final String? thumbnailPath;
  final int? duration; // in seconds
  final DateTime? uploadedAt;
  final List<String> tags;
  final String? category;
  final int viewCount;
  final int likeCount;
  final int pointCount;
  final int commentCount;

  const VideoSummary({
    required this.id,
    this.title,
    this.description,
    this.author,
    this.thumbnailPath,
    this.duration,
    this.uploadedAt,
    this.tags = const [],
    this.category,
    this.viewCount = 0,
    this.likeCount = 0,
    this.pointCount = 0,
    this.commentCount = 0,
  });

  factory VideoSummary.fromJson(Map<String, dynamic> json) {
    return VideoSummary(
      id: json['id'] as String? ?? json['videoId'] as String? ?? '',
      title: json['title'] as String?,
      description: json['description'] as String?,
      author: json['author'] as String?,
      thumbnailPath: json['thumbnailPath'] as String? ?? json['thumbnail'] as String?,
      duration: json['duration'] as int?,
      uploadedAt: _parseDateTime(json['uploadedAt'] ?? json['uploaded_at']),
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      category: json['category'] as String?,
      viewCount: json['viewCount'] as int? ?? json['views'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? json['likes'] as int? ?? 0,
      pointCount: json['pointCount'] as int? ?? json['points'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? json['comments'] as int? ?? 0,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String get durationFormatted {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'VideoSummary($id, $title)';
}

/// Video folder structure
class VideoFolder {
  final String name;
  final String path;
  final int videoCount;
  final List<VideoFolder> subfolders;

  const VideoFolder({
    required this.name,
    required this.path,
    this.videoCount = 0,
    this.subfolders = const [],
  });

  factory VideoFolder.fromJson(Map<String, dynamic> json) {
    return VideoFolder(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      videoCount: json['videoCount'] as int? ?? json['video_count'] as int? ?? 0,
      subfolders: (json['subfolders'] as List?)
              ?.map((e) => VideoFolder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Videos API endpoints
class VideosApi {
  final GeogramApi _api;

  VideosApi(this._api);

  /// List videos with optional filtering
  ///
  /// [category] - Filter by category
  /// [tag] - Filter by tag
  /// [folder] - Filter by folder path
  /// [limit] - Maximum number of results
  /// [offset] - Pagination offset
  Future<ApiListResponse<VideoSummary>> list(
    String callsign, {
    String? category,
    String? tag,
    String? folder,
    int? limit,
    int? offset,
  }) {
    return _api.list<VideoSummary>(
      callsign,
      '/api/videos',
      queryParams: {
        if (category != null) 'category': category,
        if (tag != null) 'tag': tag,
        if (folder != null) 'folder': folder,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
      itemFromJson: (json) => VideoSummary.fromJson(json as Map<String, dynamic>),
      listKey: 'videos',
    );
  }

  /// Get video details
  Future<ApiResponse<VideoSummary>> get(String callsign, String videoId) {
    return _api.get<VideoSummary>(
      callsign,
      '/api/videos/$videoId',
      fromJson: (json) => VideoSummary.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get video thumbnail
  Future<ApiResponse<String>> getThumbnail(String callsign, String videoId) {
    return _api.get<String>(
      callsign,
      '/api/videos/$videoId/thumbnail',
      fromJson: (json) {
        if (json is Map) return json['path'] as String? ?? '';
        return json.toString();
      },
    );
  }

  /// Get video feedback counts
  Future<ApiResponse<FeedbackData>> getFeedback(
    String callsign,
    String videoId, {
    String? npub,
  }) {
    return _api.get<FeedbackData>(
      callsign,
      '/api/videos/$videoId/feedback',
      queryParams: npub != null ? {'npub': npub} : null,
      fromJson: (json) => FeedbackData.fromJson(json as Map<String, dynamic>),
    );
  }

  /// List video comments
  Future<ApiListResponse<FeedbackComment>> comments(
    String callsign,
    String videoId, {
    int? limit,
    int? offset,
  }) {
    return _api.list<FeedbackComment>(
      callsign,
      '/api/videos/$videoId/comments',
      queryParams: {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
      itemFromJson: (json) => FeedbackComment.fromJson(json as Map<String, dynamic>),
      listKey: 'comments',
    );
  }

  /// List available categories
  Future<ApiResponse<List<String>>> categories(String callsign) {
    return _api.get<List<String>>(
      callsign,
      '/api/videos/categories',
      fromJson: (json) {
        if (json is List) return json.cast<String>();
        if (json is Map) return (json['categories'] as List?)?.cast<String>() ?? [];
        return [];
      },
    );
  }

  /// List all tags
  Future<ApiResponse<List<String>>> tags(String callsign) {
    return _api.get<List<String>>(
      callsign,
      '/api/videos/tags',
      fromJson: (json) {
        if (json is List) return json.cast<String>();
        if (json is Map) return (json['tags'] as List?)?.cast<String>() ?? [];
        return [];
      },
    );
  }

  /// Get folder structure
  Future<ApiListResponse<VideoFolder>> folders(String callsign) {
    return _api.list<VideoFolder>(
      callsign,
      '/api/videos/folders',
      itemFromJson: (json) => VideoFolder.fromJson(json as Map<String, dynamic>),
      listKey: 'folders',
    );
  }

  /// Record a view
  Future<ApiResponse<void>> recordView(
    String callsign,
    String videoId, {
    String? viewerId,
  }) {
    return _api.post<void>(
      callsign,
      '/api/videos/$videoId/view',
      body: viewerId != null ? {'viewerId': viewerId} : null,
    );
  }

  /// Add comment to video
  Future<ApiResponse<FeedbackComment>> comment(
    String callsign,
    String videoId, {
    required String author,
    required String content,
    String? npub,
    String? signature,
  }) {
    return _api.post<FeedbackComment>(
      callsign,
      '/api/videos/$videoId/comment',
      body: {
        'author': author,
        'content': content,
        if (npub != null) 'npub': npub,
        if (signature != null) 'signature': signature,
      },
      fromJson: (json) => FeedbackComment.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Delete a comment
  Future<ApiResponse<void>> deleteComment(
    String callsign,
    String videoId,
    String commentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/videos/$videoId/comment/$commentId',
      headers: {'X-Nostr-Event': signedEvent.toString()},
    );
  }

  /// Like/unlike video
  Future<ApiResponse<Map<String, dynamic>>> like(
    String callsign,
    String videoId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/videos/$videoId/like',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Point/unpoint video
  Future<ApiResponse<Map<String, dynamic>>> point(
    String callsign,
    String videoId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/videos/$videoId/point',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Dislike/undislike video
  Future<ApiResponse<Map<String, dynamic>>> dislike(
    String callsign,
    String videoId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/videos/$videoId/dislike',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// React with emoji
  Future<ApiResponse<Map<String, dynamic>>> react(
    String callsign,
    String videoId,
    String emoji,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/videos/$videoId/react/$emoji',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }
}
