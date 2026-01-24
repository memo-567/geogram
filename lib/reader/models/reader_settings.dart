/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Reader app settings
class ReaderSettings {
  final String version;
  final GeneralSettings general;
  final RssSettings rss;
  final MangaSettings manga;
  final BookSettings books;

  ReaderSettings({
    this.version = '1.0',
    GeneralSettings? general,
    RssSettings? rss,
    MangaSettings? manga,
    BookSettings? books,
  })  : general = general ?? GeneralSettings(),
        rss = rss ?? RssSettings(),
        manga = manga ?? MangaSettings(),
        books = books ?? BookSettings();

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      version: json['version'] as String? ?? '1.0',
      general: json['general'] != null
          ? GeneralSettings.fromJson(json['general'] as Map<String, dynamic>)
          : null,
      rss: json['rss'] != null
          ? RssSettings.fromJson(json['rss'] as Map<String, dynamic>)
          : null,
      manga: json['manga'] != null
          ? MangaSettings.fromJson(json['manga'] as Map<String, dynamic>)
          : null,
      books: json['books'] != null
          ? BookSettings.fromJson(json['books'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'general': general.toJson(),
      'rss': rss.toJson(),
      'manga': manga.toJson(),
      'books': books.toJson(),
    };
  }

  ReaderSettings copyWith({
    String? version,
    GeneralSettings? general,
    RssSettings? rss,
    MangaSettings? manga,
    BookSettings? books,
  }) {
    return ReaderSettings(
      version: version ?? this.version,
      general: general ?? this.general,
      rss: rss ?? this.rss,
      manga: manga ?? this.manga,
      books: books ?? this.books,
    );
  }
}

/// General reader settings
class GeneralSettings {
  final String theme;
  final int fontSize;
  final double lineHeight;
  final String fontFamily;

  GeneralSettings({
    this.theme = 'dark',
    this.fontSize = 16,
    this.lineHeight = 1.6,
    this.fontFamily = 'system',
  });

  factory GeneralSettings.fromJson(Map<String, dynamic> json) {
    return GeneralSettings(
      theme: json['theme'] as String? ?? 'dark',
      fontSize: json['font_size'] as int? ?? 16,
      lineHeight: (json['line_height'] as num?)?.toDouble() ?? 1.6,
      fontFamily: json['font_family'] as String? ?? 'system',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'font_size': fontSize,
      'line_height': lineHeight,
      'font_family': fontFamily,
    };
  }

  GeneralSettings copyWith({
    String? theme,
    int? fontSize,
    double? lineHeight,
    String? fontFamily,
  }) {
    return GeneralSettings(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

/// RSS-specific settings
class RssSettings {
  final bool autoFetch;
  final int fetchIntervalHours;
  final int maxPostsPerSource;
  final bool markReadOnOpen;
  final bool downloadImages;

  RssSettings({
    this.autoFetch = true,
    this.fetchIntervalHours = 1,
    this.maxPostsPerSource = 100,
    this.markReadOnOpen = true,
    this.downloadImages = true,
  });

  factory RssSettings.fromJson(Map<String, dynamic> json) {
    return RssSettings(
      autoFetch: json['auto_fetch'] as bool? ?? true,
      fetchIntervalHours: json['fetch_interval_hours'] as int? ?? 1,
      maxPostsPerSource: json['max_posts_per_source'] as int? ?? 100,
      markReadOnOpen: json['mark_read_on_open'] as bool? ?? true,
      downloadImages: json['download_images'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_fetch': autoFetch,
      'fetch_interval_hours': fetchIntervalHours,
      'max_posts_per_source': maxPostsPerSource,
      'mark_read_on_open': markReadOnOpen,
      'download_images': downloadImages,
    };
  }

  RssSettings copyWith({
    bool? autoFetch,
    int? fetchIntervalHours,
    int? maxPostsPerSource,
    bool? markReadOnOpen,
    bool? downloadImages,
  }) {
    return RssSettings(
      autoFetch: autoFetch ?? this.autoFetch,
      fetchIntervalHours: fetchIntervalHours ?? this.fetchIntervalHours,
      maxPostsPerSource: maxPostsPerSource ?? this.maxPostsPerSource,
      markReadOnOpen: markReadOnOpen ?? this.markReadOnOpen,
      downloadImages: downloadImages ?? this.downloadImages,
    );
  }
}

/// Manga reading direction
enum MangaReadingDirection {
  ltr, // Left to right
  rtl, // Right to left (traditional manga)
}

/// Manga page display mode
enum MangaPageMode {
  single, // One page at a time
  double, // Two pages side by side
  webtoon, // Vertical scroll
}

/// Manga-specific settings
class MangaSettings {
  final MangaPageMode pageMode;
  final MangaReadingDirection readingDirection;
  final int preloadPages;

  MangaSettings({
    this.pageMode = MangaPageMode.single,
    this.readingDirection = MangaReadingDirection.ltr,
    this.preloadPages = 3,
  });

  factory MangaSettings.fromJson(Map<String, dynamic> json) {
    return MangaSettings(
      pageMode: MangaPageMode.values.firstWhere(
        (m) => m.name == json['page_mode'],
        orElse: () => MangaPageMode.single,
      ),
      readingDirection: MangaReadingDirection.values.firstWhere(
        (d) => d.name == json['reading_direction'],
        orElse: () => MangaReadingDirection.ltr,
      ),
      preloadPages: json['preload_pages'] as int? ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'page_mode': pageMode.name,
      'reading_direction': readingDirection.name,
      'preload_pages': preloadPages,
    };
  }

  MangaSettings copyWith({
    MangaPageMode? pageMode,
    MangaReadingDirection? readingDirection,
    int? preloadPages,
  }) {
    return MangaSettings(
      pageMode: pageMode ?? this.pageMode,
      readingDirection: readingDirection ?? this.readingDirection,
      preloadPages: preloadPages ?? this.preloadPages,
    );
  }
}

/// Book reader theme
enum BookTheme {
  light,
  dark,
  sepia,
}

/// Book-specific settings
class BookSettings {
  final BookTheme epubTheme;
  final bool pdfContinuous;
  final bool rememberPosition;

  BookSettings({
    this.epubTheme = BookTheme.sepia,
    this.pdfContinuous = true,
    this.rememberPosition = true,
  });

  factory BookSettings.fromJson(Map<String, dynamic> json) {
    return BookSettings(
      epubTheme: BookTheme.values.firstWhere(
        (t) => t.name == json['epub_theme'],
        orElse: () => BookTheme.sepia,
      ),
      pdfContinuous: json['pdf_continuous'] as bool? ?? true,
      rememberPosition: json['remember_position'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'epub_theme': epubTheme.name,
      'pdf_continuous': pdfContinuous,
      'remember_position': rememberPosition,
    };
  }

  BookSettings copyWith({
    BookTheme? epubTheme,
    bool? pdfContinuous,
    bool? rememberPosition,
  }) {
    return BookSettings(
      epubTheme: epubTheme ?? this.epubTheme,
      pdfContinuous: pdfContinuous ?? this.pdfContinuous,
      rememberPosition: rememberPosition ?? this.rememberPosition,
    );
  }
}
