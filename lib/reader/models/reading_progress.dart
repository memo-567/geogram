/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Global reading progress across all content types
class ReadingProgress {
  final String version;
  DateTime lastUpdated;
  final Map<String, BookProgress> books;
  final Map<String, MangaProgress> manga;
  final Map<String, RssProgress> rss;

  ReadingProgress({
    this.version = '1.0',
    DateTime? lastUpdated,
    Map<String, BookProgress>? books,
    Map<String, MangaProgress>? manga,
    Map<String, RssProgress>? rss,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        books = books ?? {},
        manga = manga ?? {},
        rss = rss ?? {};

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      version: json['version'] as String? ?? '1.0',
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
      books: (json['books'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, BookProgress.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      manga: (json['manga'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, MangaProgress.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      rss: (json['rss'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, RssProgress.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'last_updated': lastUpdated.toIso8601String(),
      'books': books.map((k, v) => MapEntry(k, v.toJson())),
      'manga': manga.map((k, v) => MapEntry(k, v.toJson())),
      'rss': rss.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  /// Update book progress
  void updateBookProgress(String path, BookProgress progress) {
    books[path] = progress;
    lastUpdated = DateTime.now();
  }

  /// Update manga progress
  void updateMangaProgress(String path, MangaProgress progress) {
    manga[path] = progress;
    lastUpdated = DateTime.now();
  }

  /// Update RSS progress
  void updateRssProgress(String path, RssProgress progress) {
    rss[path] = progress;
    lastUpdated = DateTime.now();
  }

  /// Get book progress
  BookProgress? getBookProgress(String path) => books[path];

  /// Get manga progress
  MangaProgress? getMangaProgress(String path) => manga[path];

  /// Get RSS progress
  RssProgress? getRssProgress(String path) => rss[path];
}

/// Reading position for a book
class BookPosition {
  final int? chapter;
  final int page;
  final String? cfi;
  final double percent;

  BookPosition({
    this.chapter,
    required this.page,
    this.cfi,
    required this.percent,
  });

  factory BookPosition.fromJson(Map<String, dynamic> json) {
    return BookPosition(
      chapter: json['chapter'] as int?,
      page: json['page'] as int,
      cfi: json['cfi'] as String?,
      percent: (json['percent'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapter': chapter,
      'page': page,
      'cfi': cfi,
      'percent': percent,
    };
  }
}

/// Progress for a book (EPUB, PDF, etc.)
class BookProgress {
  final String type;
  BookPosition position;
  DateTime lastReadAt;
  int totalReadingTimeSeconds;
  final DateTime startedAt;
  DateTime? finishedAt;

  BookProgress({
    this.type = 'ebook',
    required this.position,
    DateTime? lastReadAt,
    this.totalReadingTimeSeconds = 0,
    DateTime? startedAt,
    this.finishedAt,
  })  : lastReadAt = lastReadAt ?? DateTime.now(),
        startedAt = startedAt ?? DateTime.now();

  factory BookProgress.fromJson(Map<String, dynamic> json) {
    return BookProgress(
      type: json['type'] as String? ?? 'ebook',
      position: BookPosition.fromJson(json['position'] as Map<String, dynamic>),
      lastReadAt: json['last_read_at'] != null
          ? DateTime.parse(json['last_read_at'] as String)
          : null,
      totalReadingTimeSeconds: json['total_reading_time_seconds'] as int? ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'position': position.toJson(),
      'last_read_at': lastReadAt.toIso8601String(),
      'total_reading_time_seconds': totalReadingTimeSeconds,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt?.toIso8601String(),
    };
  }

  /// Update reading position
  void updatePosition(BookPosition newPosition) {
    position = newPosition;
    lastReadAt = DateTime.now();
  }

  /// Add reading time
  void addReadingTime(int seconds) {
    totalReadingTimeSeconds += seconds;
    lastReadAt = DateTime.now();
  }

  /// Mark as finished
  void markFinished() {
    finishedAt = DateTime.now();
    lastReadAt = DateTime.now();
  }

  bool get isFinished => finishedAt != null;
}

/// Progress for a manga series
class MangaProgress {
  String? currentChapter;
  int currentPage;
  final List<String> chaptersRead;
  DateTime lastReadAt;
  final DateTime startedAt;

  MangaProgress({
    this.currentChapter,
    this.currentPage = 0,
    List<String>? chaptersRead,
    DateTime? lastReadAt,
    DateTime? startedAt,
  })  : chaptersRead = chaptersRead ?? [],
        lastReadAt = lastReadAt ?? DateTime.now(),
        startedAt = startedAt ?? DateTime.now();

  factory MangaProgress.fromJson(Map<String, dynamic> json) {
    return MangaProgress(
      currentChapter: json['current_chapter'] as String?,
      currentPage: json['current_page'] as int? ?? 0,
      chaptersRead: (json['chapters_read'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastReadAt: json['last_read_at'] != null
          ? DateTime.parse(json['last_read_at'] as String)
          : null,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_chapter': currentChapter,
      'current_page': currentPage,
      'chapters_read': chaptersRead,
      'last_read_at': lastReadAt.toIso8601String(),
      'started_at': startedAt.toIso8601String(),
    };
  }

  /// Update current reading position
  void updatePosition(String chapter, int page) {
    currentChapter = chapter;
    currentPage = page;
    lastReadAt = DateTime.now();
  }

  /// Mark a chapter as read
  void markChapterRead(String chapter) {
    if (!chaptersRead.contains(chapter)) {
      chaptersRead.add(chapter);
    }
    lastReadAt = DateTime.now();
  }

  /// Check if a chapter has been read
  bool isChapterRead(String chapter) => chaptersRead.contains(chapter);
}

/// Progress for an RSS post
class RssProgress {
  bool isRead;
  DateTime? readAt;
  double scrollPosition;
  bool isStarred;

  RssProgress({
    this.isRead = false,
    this.readAt,
    this.scrollPosition = 0.0,
    this.isStarred = false,
  });

  factory RssProgress.fromJson(Map<String, dynamic> json) {
    return RssProgress(
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      scrollPosition: (json['scroll_position'] as num?)?.toDouble() ?? 0.0,
      isStarred: json['is_starred'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'scroll_position': scrollPosition,
      'is_starred': isStarred,
    };
  }

  /// Mark as read
  void markRead() {
    isRead = true;
    readAt = DateTime.now();
  }

  /// Update scroll position
  void updateScroll(double position) {
    scrollPosition = position;
  }

  /// Toggle starred status
  void toggleStarred() {
    isStarred = !isStarred;
  }
}
