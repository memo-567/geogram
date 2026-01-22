/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Blog API endpoints.
 */

import '../api.dart';

/// Blog post summary (from list)
class BlogPostSummary {
  final String id;
  final String? title;
  final String? excerpt;
  final String? author;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final String? coverImage;
  final int commentCount;
  final int likeCount;
  final int pointCount;

  const BlogPostSummary({
    required this.id,
    this.title,
    this.excerpt,
    this.author,
    this.publishedAt,
    this.updatedAt,
    this.tags = const [],
    this.coverImage,
    this.commentCount = 0,
    this.likeCount = 0,
    this.pointCount = 0,
  });

  factory BlogPostSummary.fromJson(Map<String, dynamic> json) {
    return BlogPostSummary(
      id: json['id'] as String? ?? json['slug'] as String? ?? '',
      title: json['title'] as String?,
      excerpt: json['excerpt'] as String? ?? json['summary'] as String?,
      author: json['author'] as String?,
      publishedAt: _parseDateTime(json['publishedAt'] ?? json['published_at'] ?? json['date']),
      updatedAt: _parseDateTime(json['updatedAt'] ?? json['updated_at']),
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      coverImage: json['coverImage'] as String? ?? json['cover_image'] as String?,
      commentCount: json['commentCount'] as int? ?? json['comments'] as int? ?? 0,
      likeCount: json['likeCount'] as int? ?? json['likes'] as int? ?? 0,
      pointCount: json['pointCount'] as int? ?? json['points'] as int? ?? 0,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  String toString() => 'BlogPostSummary($id, $title)';
}

/// Full blog post details
class BlogPostDetails extends BlogPostSummary {
  final String? content;
  final String? contentHtml;
  final List<String> attachments;
  final List<FeedbackComment> comments;
  final FeedbackCounts? feedbackCounts;

  const BlogPostDetails({
    required super.id,
    super.title,
    super.excerpt,
    super.author,
    super.publishedAt,
    super.updatedAt,
    super.tags,
    super.coverImage,
    super.commentCount,
    super.likeCount,
    super.pointCount,
    this.content,
    this.contentHtml,
    this.attachments = const [],
    this.comments = const [],
    this.feedbackCounts,
  });

  factory BlogPostDetails.fromJson(Map<String, dynamic> json) {
    final summary = BlogPostSummary.fromJson(json);
    return BlogPostDetails(
      id: summary.id,
      title: summary.title,
      excerpt: summary.excerpt,
      author: summary.author,
      publishedAt: summary.publishedAt,
      updatedAt: summary.updatedAt,
      tags: summary.tags,
      coverImage: summary.coverImage,
      commentCount: summary.commentCount,
      likeCount: summary.likeCount,
      pointCount: summary.pointCount,
      content: json['content'] as String?,
      contentHtml: json['contentHtml'] as String? ?? json['content_html'] as String?,
      attachments: (json['attachments'] as List?)?.cast<String>() ?? [],
      comments: (json['comments'] as List?)
              ?.map((e) => FeedbackComment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      feedbackCounts: json['feedback'] != null
          ? FeedbackCounts.fromJson(json['feedback'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Blog API endpoints
class BlogApi {
  final GeogramApi _api;

  BlogApi(this._api);

  /// List blog posts
  ///
  /// [tag] - Filter by tag
  /// [limit] - Maximum number of results
  /// [offset] - Pagination offset
  Future<ApiListResponse<BlogPostSummary>> list(
    String callsign, {
    String? tag,
    int? limit,
    int? offset,
  }) {
    return _api.list<BlogPostSummary>(
      callsign,
      '/api/blog',
      queryParams: {
        if (tag != null) 'tag': tag,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
      itemFromJson: (json) => BlogPostSummary.fromJson(json as Map<String, dynamic>),
      listKey: 'posts',
    );
  }

  /// Get blog post details with comments
  Future<ApiResponse<BlogPostDetails>> get(String callsign, String postId) {
    return _api.get<BlogPostDetails>(
      callsign,
      '/api/blog/$postId',
      fromJson: (json) => BlogPostDetails.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get post feedback counts and user state
  Future<ApiResponse<FeedbackData>> getFeedback(
    String callsign,
    String postId, {
    String? npub,
  }) {
    return _api.get<FeedbackData>(
      callsign,
      '/api/blog/$postId/feedback',
      queryParams: npub != null ? {'npub': npub} : null,
      fromJson: (json) => FeedbackData.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get post attachment file
  Future<ApiResponse<dynamic>> getFile(
    String callsign,
    String postId,
    String filename,
  ) {
    return _api.get<dynamic>(
      callsign,
      '/api/blog/$postId/files/$filename',
    );
  }

  /// Add comment to post
  Future<ApiResponse<FeedbackComment>> comment(
    String callsign,
    String postId, {
    required String author,
    required String content,
    String? npub,
    String? signature,
  }) {
    return _api.post<FeedbackComment>(
      callsign,
      '/api/blog/$postId/comment',
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
    String postId,
    String commentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/blog/$postId/comment/$commentId',
      headers: {'X-Nostr-Event': signedEvent.toString()},
    );
  }

  /// Like/unlike post
  Future<ApiResponse<Map<String, dynamic>>> like(
    String callsign,
    String postId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/blog/$postId/like',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Point/unpoint post
  Future<ApiResponse<Map<String, dynamic>>> point(
    String callsign,
    String postId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/blog/$postId/point',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Dislike/undislike post
  Future<ApiResponse<Map<String, dynamic>>> dislike(
    String callsign,
    String postId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/blog/$postId/dislike',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Subscribe/unsubscribe to post
  Future<ApiResponse<Map<String, dynamic>>> subscribe(
    String callsign,
    String postId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/blog/$postId/subscribe',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// React with emoji
  Future<ApiResponse<Map<String, dynamic>>> react(
    String callsign,
    String postId,
    String emoji,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/blog/$postId/react/$emoji',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }
}
