/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import '../models/news_article.dart';
import '../models/blog_comment.dart';
import 'log_service.dart';
import 'profile_storage.dart';

/// Model for chat security (reused for news)
class ChatSecurity {
  final String? adminNpub;
  final Map<String, List<String>> moderators;

  ChatSecurity({
    this.adminNpub,
    this.moderators = const {},
  });

  bool isAdmin(String? npub) {
    return npub != null && npub == adminNpub;
  }

  bool isModerator(String? npub, String sectionId) {
    if (npub == null) return false;
    return moderators[sectionId]?.contains(npub) ?? false;
  }

  bool canModerate(String? npub, String sectionId) {
    return isAdmin(npub) || isModerator(npub, sectionId);
  }

  factory ChatSecurity.fromJson(Map<String, dynamic> json) {
    final moderatorMap = <String, List<String>>{};
    if (json.containsKey('moderators')) {
      final mods = json['moderators'] as Map<String, dynamic>;
      for (var entry in mods.entries) {
        moderatorMap[entry.key] = List<String>.from(entry.value as List);
      }
    }

    return ChatSecurity(
      adminNpub: json['admin'] as String?,
      moderators: moderatorMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': '1.0',
      'admin': adminNpub,
      'moderators': moderators,
    };
  }
}

/// Service for managing news articles and comments
class NewsService {
  static final NewsService _instance = NewsService._internal();
  factory NewsService() => _instance;
  NewsService._internal();

  /// Profile storage for file operations (encrypted or filesystem)
  /// IMPORTANT: This MUST be set before using the service.
  late ProfileStorage _storage;

  String? _appPath;
  ChatSecurity _security = ChatSecurity();

  /// Whether using encrypted storage
  bool get useEncryptedStorage => _storage.isEncrypted;

  /// Set the profile storage for file operations
  /// MUST be called before initializeApp
  void setStorage(ProfileStorage storage) {
    _storage = storage;
  }

  /// Initialize news service for a collection
  Future<void> initializeApp(String appPath, {String? creatorNpub}) async {
    LogService().log('NewsService: Initializing with collection path: $appPath');
    _appPath = appPath;

    // Ensure news directory exists using storage
    await _storage.createDirectory('news');
    LogService().log('NewsService: Created news directory');

    // Load security
    await _loadSecurity();

    // If no admin set and creator provided, set as admin
    if (_security.adminNpub == null && creatorNpub != null && creatorNpub.isNotEmpty) {
      LogService().log('NewsService: Setting creator as admin: $creatorNpub');
      final newSecurity = ChatSecurity(adminNpub: creatorNpub);
      await saveSecurity(newSecurity);
    }
  }

  /// Load security settings
  Future<void> _loadSecurity() async {
    if (_appPath == null) return;

    final content = await _storage.readString('extra/security.json');
    if (content != null) {
      try {
        final json = jsonDecode(content) as Map<String, dynamic>;
        _security = ChatSecurity.fromJson(json);
        LogService().log('NewsService: Loaded security settings');
      } catch (e) {
        LogService().log('NewsService: Error loading security: $e');
        _security = ChatSecurity();
      }
    } else {
      _security = ChatSecurity();
    }
  }

  /// Save security settings
  Future<void> saveSecurity(ChatSecurity security) async {
    if (_appPath == null) return;

    _security = security;

    await _storage.createDirectory('extra');
    await _storage.writeString('extra/security.json', jsonEncode(security.toJson()));

    LogService().log('NewsService: Saved security settings');
  }

  /// Get available years (folders in news directory)
  Future<List<int>> getYears() async {
    if (_appPath == null) return [];

    if (!await _storage.exists('news')) return [];

    final years = <int>[];
    final entries = await _storage.listDirectory('news');

    for (var entry in entries) {
      if (entry.isDirectory) {
        final year = int.tryParse(entry.name);
        if (year != null) {
          years.add(year);
        }
      }
    }

    years.sort((a, b) => b.compareTo(a)); // Most recent first
    return years;
  }

  /// Load articles metadata for a specific year or all years
  Future<List<NewsArticle>> loadArticles({
    int? year,
    bool includeExpired = true,
    String? currentUserNpub,
  }) async {
    if (_appPath == null) return [];

    final articles = <NewsArticle>[];
    final years = year != null ? [year] : await getYears();

    for (var y in years) {
      final yearPath = 'news/$y';
      if (!await _storage.exists(yearPath)) continue;

      final entries = await _storage.listDirectory(yearPath);

      for (var entry in entries) {
        if (!entry.isDirectory && entry.name.endsWith('.md')) {
          try {
            final articleId = entry.name.substring(0, entry.name.length - 3); // Remove .md

            final content = await _storage.readString(entry.path);
            if (content == null) continue;

            final article = NewsArticle.fromText(content, articleId);

            // Filter by expiry status
            if (!includeExpired && article.isExpired) {
              continue;
            }

            articles.add(article);
          } catch (e) {
            LogService().log('NewsService: Error loading article ${entry.path}: $e');
          }
        }
      }
    }

    // Sort by date (most recent first)
    articles.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return articles;
  }

  /// Load full article with comments
  Future<NewsArticle?> loadFullArticle(String articleId) async {
    if (_appPath == null) return null;

    // Extract year from articleId (format: YYYY-MM-DD_title)
    final year = articleId.substring(0, 4);
    final articlePath = 'news/$year/$articleId.md';

    final content = await _storage.readString(articlePath);
    if (content == null) {
      LogService().log('NewsService: Article file not found: $articlePath');
      return null;
    }

    try {
      return NewsArticle.fromText(content, articleId);
    } catch (e) {
      LogService().log('NewsService: Error loading full article: $e');
      return null;
    }
  }

  /// Sanitize headline to create valid filename
  String sanitizeFilename(String headline, DateTime? date) {
    date ??= DateTime.now();

    // Convert to lowercase, replace spaces with hyphens
    String sanitized = headline.toLowerCase().trim();

    // Replace spaces and underscores with hyphens
    sanitized = sanitized.replaceAll(RegExp(r'[\s_]+'), '-');

    // Remove non-alphanumeric characters except hyphens
    sanitized = sanitized.replaceAll(RegExp(r'[^a-z0-9-]'), '');

    // Remove multiple consecutive hyphens
    sanitized = sanitized.replaceAll(RegExp(r'-+'), '-');

    // Remove leading/trailing hyphens
    sanitized = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');

    // Truncate to 50 characters
    if (sanitized.length > 50) {
      sanitized = sanitized.substring(0, 50);
    }

    // Format date as YYYY-MM-DD
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day\_$sanitized';
  }

  /// Check if filename already exists, add suffix if needed
  Future<String> _ensureUniqueFilename(String baseFilename, int year) async {
    String filename = baseFilename;
    int suffix = 1;

    while (await _storage.exists('news/$year/$filename.md')) {
      filename = '$baseFilename-$suffix';
      suffix++;
    }

    return filename;
  }

  /// Format timestamp for storage
  String _formatTimestamp(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  /// Create new news article
  Future<NewsArticle?> createArticle({
    required String author,
    required Map<String, String> headlines,  // Language code -> headline
    required Map<String, String> contents,   // Language code -> content
    NewsClassification classification = NewsClassification.normal,
    double? latitude,
    double? longitude,
    String? address,
    double? radiusKm,
    DateTime? expiryDateTime,
    String? source,
    List<String>? tags,
    String? npub,
    Map<String, String>? metadata,
  }) async {
    if (_appPath == null) return null;

    try {
      // Validate headlines not empty
      if (headlines.isEmpty) {
        print('NewsService: At least one headline is required');
        return null;
      }

      // Validate contents not empty
      if (contents.isEmpty) {
        print('NewsService: At least one content version is required');
        return null;
      }

      // Validate content length for each language
      for (var entry in contents.entries) {
        if (entry.value.length > 500) {
          print('NewsService: Content for language ${entry.key} exceeds 500 character limit');
          return null;
        }
      }

      // Validate radius requires location
      if (radiusKm != null && (latitude == null || longitude == null)) {
        print('NewsService: Radius requires location coordinates');
        return null;
      }

      // Validate radius range
      if (radiusKm != null && (radiusKm < 0.1 || radiusKm > 100)) {
        print('NewsService: Radius must be between 0.1 and 100 km');
        return null;
      }

      final now = DateTime.now();
      final year = now.year;

      // Sanitize filename using first available headline
      final firstHeadline = headlines.values.first;
      final baseFilename = sanitizeFilename(firstHeadline, now);
      final filename = await _ensureUniqueFilename(baseFilename, year);

      // Ensure year directory exists using storage
      await _storage.createDirectory('news/$year');

      // Create news article
      final article = NewsArticle(
        id: filename,
        author: author,
        timestamp: _formatTimestamp(now),
        headlines: headlines,
        contents: contents,
        classification: classification,
        latitude: latitude,
        longitude: longitude,
        address: address,
        radiusKm: radiusKm,
        expiry: expiryDateTime != null ? _formatTimestamp(expiryDateTime) : null,
        source: source,
        tags: tags ?? [],
        metadata: {
          ...?metadata,
          if (npub != null) 'npub': npub,
        },
      );

      // Write to file using storage
      await _storage.writeString('news/$year/$filename.md', article.exportAsText());

      LogService().log('NewsService: Created article: $filename');
      return article;
    } catch (e) {
      LogService().log('NewsService: Error creating article: $e');
      return null;
    }
  }

  /// Update existing news article
  Future<bool> updateArticle({
    required String articleId,
    Map<String, String>? headlines,
    Map<String, String>? contents,
    NewsClassification? classification,
    double? latitude,
    double? longitude,
    String? address,
    double? radiusKm,
    DateTime? expiryDateTime,
    String? source,
    List<String>? tags,
    Map<String, String>? metadata,
    required String? userNpub,
  }) async {
    if (_appPath == null) return false;

    // Load existing article
    final article = await loadFullArticle(articleId);
    if (article == null) return false;

    // Check permissions (author or admin)
    if (!_security.isAdmin(userNpub) && !article.isOwnArticle(userNpub)) {
      print('NewsService: User $userNpub cannot edit article by ${article.npub}');
      return false;
    }

    // Validate content length for each language if provided
    if (contents != null) {
      for (var entry in contents.entries) {
        if (entry.value.length > 500) {
          print('NewsService: Content for language ${entry.key} exceeds 500 character limit');
          return false;
        }
      }
    }

    try {
      // Update article
      final updatedArticle = article.copyWith(
        headlines: headlines ?? article.headlines,
        contents: contents ?? article.contents,
        classification: classification ?? article.classification,
        latitude: latitude ?? article.latitude,
        longitude: longitude ?? article.longitude,
        address: address ?? article.address,
        radiusKm: radiusKm ?? article.radiusKm,
        expiry: expiryDateTime != null ? _formatTimestamp(expiryDateTime) : article.expiry,
        source: source ?? article.source,
        tags: tags ?? article.tags,
        metadata: metadata ?? article.metadata,
      );

      // Write to file using storage
      final year = article.year;
      await _storage.writeString('news/$year/$articleId.md', updatedArticle.exportAsText());

      print('NewsService: Updated article: $articleId');
      return true;
    } catch (e) {
      print('NewsService: Error updating article: $e');
      return false;
    }
  }

  /// Delete news article
  Future<bool> deleteArticle(String articleId, String? userNpub) async {
    if (_appPath == null) return false;

    // Load article to check permissions
    final article = await loadFullArticle(articleId);
    if (article == null) return false;

    // Check permissions (author or admin)
    if (!_security.isAdmin(userNpub) && !article.isOwnArticle(userNpub)) {
      print('NewsService: User $userNpub cannot delete article by ${article.npub}');
      return false;
    }

    try {
      final year = article.year;
      final articlePath = 'news/$year/$articleId.md';

      if (await _storage.exists(articlePath)) {
        await _storage.delete(articlePath);
        print('NewsService: Deleted article: $articleId');
        return true;
      }

      return false;
    } catch (e) {
      print('NewsService: Error deleting article: $e');
      return false;
    }
  }

  /// Toggle like on an article
  Future<bool> toggleLike(String articleId, String callsign) async {
    if (_appPath == null) return false;

    // Load article
    final article = await loadFullArticle(articleId);
    if (article == null) return false;

    try {
      final likes = List<String>.from(article.likes);

      if (likes.contains(callsign)) {
        // Unlike
        likes.remove(callsign);
      } else {
        // Like
        likes.add(callsign);
      }

      // Update article with new likes
      final updatedArticle = article.copyWith(likes: likes);

      // Write to file using storage
      final year = article.year;
      await _storage.writeString('news/$year/$articleId.md', updatedArticle.exportAsText());

      print('NewsService: Toggled like for $callsign on article $articleId');
      return true;
    } catch (e) {
      print('NewsService: Error toggling like: $e');
      return false;
    }
  }

  /// Add comment to article
  Future<bool> addComment({
    required String articleId,
    required String author,
    required String content,
    String? npub,
    String? signature,
  }) async {
    if (_appPath == null) return false;

    // Load article
    final article = await loadFullArticle(articleId);
    if (article == null) return false;

    try {
      final now = DateTime.now();

      // Create comment
      final comment = BlogComment(
        author: author,
        timestamp: _formatTimestamp(now),
        content: content,
        metadata: {
          if (npub != null) 'npub': npub,
          if (signature != null) 'signature': signature,
        },
      );

      // Add to comments list
      final comments = List<BlogComment>.from(article.comments);
      comments.add(comment);

      // Update article
      final updatedArticle = article.copyWith(comments: comments);

      // Write to file using storage
      final year = article.year;
      await _storage.writeString('news/$year/$articleId.md', updatedArticle.exportAsText());

      print('NewsService: Added comment to article $articleId');
      return true;
    } catch (e) {
      print('NewsService: Error adding comment: $e');
      return false;
    }
  }

  /// Delete comment from article
  Future<bool> deleteComment({
    required String articleId,
    required int commentIndex,
    required String? userNpub,
  }) async {
    if (_appPath == null) return false;

    // Load article
    final article = await loadFullArticle(articleId);
    if (article == null) return false;

    if (commentIndex < 0 || commentIndex >= article.comments.length) {
      print('NewsService: Invalid comment index');
      return false;
    }

    final comment = article.comments[commentIndex];

    // Check permissions (comment author or admin)
    if (!_security.isAdmin(userNpub) && comment.npub != userNpub) {
      print('NewsService: User $userNpub cannot delete comment by ${comment.npub}');
      return false;
    }

    try {
      // Remove comment
      final comments = List<BlogComment>.from(article.comments);
      comments.removeAt(commentIndex);

      // Update article
      final updatedArticle = article.copyWith(comments: comments);

      // Write to file using storage
      final year = article.year;
      await _storage.writeString('news/$year/$articleId.md', updatedArticle.exportAsText());

      print('NewsService: Deleted comment from article $articleId');
      return true;
    } catch (e) {
      print('NewsService: Error deleting comment: $e');
      return false;
    }
  }

  /// Check if user is admin
  bool isAdmin(String? npub) {
    return _security.isAdmin(npub);
  }
}
