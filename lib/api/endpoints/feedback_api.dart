/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Feedback API endpoints (points, likes, verifications, comments).
 */

import '../api.dart';

/// Feedback counts for content
class FeedbackCounts {
  final int points;
  final int likes;
  final int dislikes;
  final int verifications;
  final int comments;
  final Map<String, int> reactions;

  const FeedbackCounts({
    this.points = 0,
    this.likes = 0,
    this.dislikes = 0,
    this.verifications = 0,
    this.comments = 0,
    this.reactions = const {},
  });

  factory FeedbackCounts.fromJson(Map<String, dynamic> json) {
    return FeedbackCounts(
      points: json['points'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
      verifications: json['verifications'] as int? ?? 0,
      comments: json['comments'] as int? ?? 0,
      reactions: (json['reactions'] as Map<String, dynamic>?)?.cast<String, int>() ?? {},
    );
  }

  @override
  String toString() => 'FeedbackCounts(points: $points, likes: $likes, comments: $comments)';
}

/// User's feedback state for content
class UserFeedbackState {
  final bool hasPointed;
  final bool hasLiked;
  final bool hasDisliked;
  final bool hasVerified;
  final bool hasSubscribed;
  final Set<String> reactions;

  const UserFeedbackState({
    this.hasPointed = false,
    this.hasLiked = false,
    this.hasDisliked = false,
    this.hasVerified = false,
    this.hasSubscribed = false,
    this.reactions = const {},
  });

  factory UserFeedbackState.fromJson(Map<String, dynamic> json) {
    return UserFeedbackState(
      hasPointed: json['hasPointed'] as bool? ?? json['pointed'] as bool? ?? false,
      hasLiked: json['hasLiked'] as bool? ?? json['liked'] as bool? ?? false,
      hasDisliked: json['hasDisliked'] as bool? ?? json['disliked'] as bool? ?? false,
      hasVerified: json['hasVerified'] as bool? ?? json['verified'] as bool? ?? false,
      hasSubscribed: json['hasSubscribed'] as bool? ?? json['subscribed'] as bool? ?? false,
      reactions: (json['reactions'] as List?)?.cast<String>().toSet() ?? {},
    );
  }
}

/// Combined feedback data (counts + user state)
class FeedbackData {
  final FeedbackCounts counts;
  final UserFeedbackState userState;

  const FeedbackData({
    required this.counts,
    required this.userState,
  });

  factory FeedbackData.fromJson(Map<String, dynamic> json) {
    return FeedbackData(
      counts: FeedbackCounts.fromJson(json),
      userState: UserFeedbackState.fromJson(json['userState'] as Map<String, dynamic>? ?? json),
    );
  }
}

/// Comment on content
class FeedbackComment {
  final String id;
  final String author;
  final String content;
  final DateTime timestamp;
  final String? npub;
  final String? signature;

  const FeedbackComment({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    this.npub,
    this.signature,
  });

  factory FeedbackComment.fromJson(Map<String, dynamic> json) {
    return FeedbackComment(
      id: json['id'] as String? ?? '',
      author: json['author'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['timestamp'] as num).toInt() * 1000,
            )
          : DateTime.now(),
      npub: json['npub'] as String?,
      signature: json['signature'] as String?,
    );
  }
}

/// Feedback API endpoints
///
/// Unified feedback system for alerts, places, events, blog posts, and videos.
class FeedbackApi {
  final GeogramApi _api;

  FeedbackApi(this._api);

  // ============================================================
  // Generic Feedback Methods
  // ============================================================

  /// Get feedback counts and user state for content
  Future<ApiResponse<FeedbackData>> get(
    String callsign,
    String contentType,
    String contentId, {
    String? npub,
  }) {
    return _api.get<FeedbackData>(
      callsign,
      '/api/feedback/$contentType/$contentId',
      queryParams: npub != null ? {'npub': npub} : null,
      fromJson: (json) => FeedbackData.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Point/unpoint content (call attention to it)
  Future<ApiResponse<Map<String, dynamic>>> point(
    String callsign,
    String contentType,
    String contentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/point',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Like/unlike content
  Future<ApiResponse<Map<String, dynamic>>> like(
    String callsign,
    String contentType,
    String contentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/like',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Dislike/undislike content
  Future<ApiResponse<Map<String, dynamic>>> dislike(
    String callsign,
    String contentType,
    String contentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/dislike',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Verify content (for alerts)
  Future<ApiResponse<Map<String, dynamic>>> verify(
    String callsign,
    String contentType,
    String contentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/verify',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Subscribe/unsubscribe to content updates
  Future<ApiResponse<Map<String, dynamic>>> subscribe(
    String callsign,
    String contentType,
    String contentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/subscribe',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Add emoji reaction
  Future<ApiResponse<Map<String, dynamic>>> react(
    String callsign,
    String contentType,
    String contentId,
    String emoji,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/feedback/$contentType/$contentId/react/$emoji',
      body: signedEvent,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Add comment to content
  Future<ApiResponse<FeedbackComment>> comment(
    String callsign,
    String contentType,
    String contentId, {
    required String author,
    required String content,
    String? npub,
    String? signature,
  }) {
    return _api.post<FeedbackComment>(
      callsign,
      '/api/feedback/$contentType/$contentId/comment',
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
    String contentType,
    String contentId,
    String commentId,
    Map<String, dynamic> signedEvent,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/feedback/$contentType/$contentId/comment/$commentId',
      headers: {'X-Nostr-Event': signedEvent.toString()},
    );
  }

  // ============================================================
  // Content-Specific Convenience Methods
  // ============================================================

  /// Point an alert
  Future<ApiResponse<Map<String, dynamic>>> pointAlert(
    String callsign,
    String alertId,
    Map<String, dynamic> signedEvent,
  ) => point(callsign, 'alert', alertId, signedEvent);

  /// Verify an alert
  Future<ApiResponse<Map<String, dynamic>>> verifyAlert(
    String callsign,
    String alertId,
    Map<String, dynamic> signedEvent,
  ) => verify(callsign, 'alert', alertId, signedEvent);

  /// Comment on an alert
  Future<ApiResponse<FeedbackComment>> commentOnAlert(
    String callsign,
    String alertId, {
    required String author,
    required String content,
    String? npub,
    String? signature,
  }) => comment(callsign, 'alert', alertId, author: author, content: content, npub: npub, signature: signature);

  /// Like a blog post
  Future<ApiResponse<Map<String, dynamic>>> likeBlogPost(
    String callsign,
    String postId,
    Map<String, dynamic> signedEvent,
  ) => like(callsign, 'blog', postId, signedEvent);

  /// Like a video
  Future<ApiResponse<Map<String, dynamic>>> likeVideo(
    String callsign,
    String videoId,
    Map<String, dynamic> signedEvent,
  ) => like(callsign, 'video', videoId, signedEvent);
}
