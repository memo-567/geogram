/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Generate a title from a URL (domain and path)
/// Example: "https://indieweb.org/POSSE#section" becomes "indieweb.org/POSSE"
/// Note: This is for the document title in metadata, not for filenames
String titleFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    var title = uri.host;

    // Add path if not empty or just "/"
    if (uri.path.isNotEmpty && uri.path != '/') {
      var path = uri.path;
      // Remove trailing slash
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      title += path;
    }

    // Limit length for display
    if (title.length > 200) {
      title = title.substring(0, 200);
    }

    return title.isEmpty ? 'Web Snapshot' : title;
  } catch (e) {
    return 'Web Snapshot';
  }
}

/// Sanitize a string to be safe as a filename on Windows and Linux
/// Characters forbidden on Windows: \ / : * ? " < > |
String sanitizeFilename(String name) {
  var sanitized = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'[\x00-\x1F]'), '') // Control characters
      .trim();

  // Remove leading dots (hidden files on Unix, problematic on Windows)
  while (sanitized.startsWith('.')) {
    sanitized = sanitized.substring(1);
  }

  // Remove trailing dots (problematic on Windows)
  while (sanitized.endsWith('.')) {
    sanitized = sanitized.substring(0, sanitized.length - 1);
  }

  // Limit length (leave room for extension and path)
  if (sanitized.length > 200) {
    sanitized = sanitized.substring(0, 200);
  }

  return sanitized.trim();
}

/// Crawl depth configuration
enum CrawlDepth {
  single,  // Single page only
  one,     // 1 level deep
  two,     // 2 levels deep
  three,   // 3 levels deep
}

/// Crawl/capture status
enum CrawlStatus {
  pending,
  crawling,
  complete,
  failed,
}

/// Settings for web snapshot document
class WebSnapshotSettings {
  final CrawlDepth defaultDepth;
  final bool includeScripts;
  final bool includeStyles;
  final bool includeImages;
  final bool includeFonts;
  final int maxAssetSizeMb;

  WebSnapshotSettings({
    this.defaultDepth = CrawlDepth.single,
    this.includeScripts = true,
    this.includeStyles = true,
    this.includeImages = true,
    this.includeFonts = true,
    this.maxAssetSizeMb = 10,
  });

  factory WebSnapshotSettings.fromJson(Map<String, dynamic> json) {
    return WebSnapshotSettings(
      defaultDepth: CrawlDepth.values.firstWhere(
        (d) => d.name == json['default_depth'],
        orElse: () => CrawlDepth.single,
      ),
      includeScripts: json['include_scripts'] as bool? ?? true,
      includeStyles: json['include_styles'] as bool? ?? true,
      includeImages: json['include_images'] as bool? ?? true,
      includeFonts: json['include_fonts'] as bool? ?? true,
      maxAssetSizeMb: json['max_asset_size_mb'] as int? ?? 10,
    );
  }

  Map<String, dynamic> toJson() => {
    'default_depth': defaultDepth.name,
    'include_scripts': includeScripts,
    'include_styles': includeStyles,
    'include_images': includeImages,
    'include_fonts': includeFonts,
    'max_asset_size_mb': maxAssetSizeMb,
  };

  WebSnapshotSettings copyWith({
    CrawlDepth? defaultDepth,
    bool? includeScripts,
    bool? includeStyles,
    bool? includeImages,
    bool? includeFonts,
    int? maxAssetSizeMb,
  }) {
    return WebSnapshotSettings(
      defaultDepth: defaultDepth ?? this.defaultDepth,
      includeScripts: includeScripts ?? this.includeScripts,
      includeStyles: includeStyles ?? this.includeStyles,
      includeImages: includeImages ?? this.includeImages,
      includeFonts: includeFonts ?? this.includeFonts,
      maxAssetSizeMb: maxAssetSizeMb ?? this.maxAssetSizeMb,
    );
  }
}

/// Captured asset metadata
class CapturedAsset {
  final String originalUrl;
  final String localPath;  // Relative path in assets/snapshots/{snapshotId}/
  final String mimeType;
  final int sizeBytes;

  CapturedAsset({
    required this.originalUrl,
    required this.localPath,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory CapturedAsset.fromJson(Map<String, dynamic> json) {
    return CapturedAsset(
      originalUrl: json['original_url'] as String,
      localPath: json['local_path'] as String,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'original_url': originalUrl,
    'local_path': localPath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
  };
}

/// Metadata for a single snapshot
class WebSnapshot {
  final String id;
  final String url;
  final DateTime capturedAt;
  final CrawlDepth depth;
  int pageCount;
  int assetCount;
  int totalSizeBytes;
  String? title;
  String? description;
  String? favicon;      // asset:// reference
  String? thumbnail;    // asset:// reference to preview
  List<String> pages;   // List of captured page paths
  List<CapturedAsset> assets;
  CrawlStatus status;
  String? error;

  WebSnapshot({
    required this.id,
    required this.url,
    required this.capturedAt,
    this.depth = CrawlDepth.single,
    this.pageCount = 0,
    this.assetCount = 0,
    this.totalSizeBytes = 0,
    this.title,
    this.description,
    this.favicon,
    this.thumbnail,
    List<String>? pages,
    List<CapturedAsset>? assets,
    this.status = CrawlStatus.pending,
    this.error,
  }) : pages = pages ?? [],
       assets = assets ?? [];

  factory WebSnapshot.create({
    required String url,
    CrawlDepth depth = CrawlDepth.single,
  }) {
    final now = DateTime.now();
    final id = 'snap-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return WebSnapshot(
      id: id,
      url: url,
      capturedAt: now,
      depth: depth,
      status: CrawlStatus.pending,
    );
  }

  factory WebSnapshot.fromJson(Map<String, dynamic> json) {
    return WebSnapshot(
      id: json['id'] as String,
      url: json['url'] as String,
      capturedAt: DateTime.parse(json['captured_at'] as String),
      depth: CrawlDepth.values.firstWhere(
        (d) => d.name == json['depth'],
        orElse: () => CrawlDepth.single,
      ),
      pageCount: json['page_count'] as int? ?? 0,
      assetCount: json['asset_count'] as int? ?? 0,
      totalSizeBytes: json['total_size_bytes'] as int? ?? 0,
      title: json['title'] as String?,
      description: json['description'] as String?,
      favicon: json['favicon'] as String?,
      thumbnail: json['thumbnail'] as String?,
      pages: (json['pages'] as List<dynamic>?)
          ?.map((p) => p as String)
          .toList() ?? [],
      assets: (json['assets'] as List<dynamic>?)
          ?.map((a) => CapturedAsset.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
      status: CrawlStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CrawlStatus.pending,
      ),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'captured_at': capturedAt.toIso8601String(),
    'depth': depth.name,
    'page_count': pageCount,
    'asset_count': assetCount,
    'total_size_bytes': totalSizeBytes,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (favicon != null) 'favicon': favicon,
    if (thumbnail != null) 'thumbnail': thumbnail,
    'pages': pages,
    'assets': assets.map((a) => a.toJson()).toList(),
    'status': status.name,
    if (error != null) 'error': error,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Get formatted size string (KB, MB)
  String get sizeFormatted {
    if (totalSizeBytes < 1024) {
      return '$totalSizeBytes B';
    } else if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  WebSnapshot copyWith({
    String? url,
    CrawlDepth? depth,
    int? pageCount,
    int? assetCount,
    int? totalSizeBytes,
    String? title,
    String? description,
    String? favicon,
    String? thumbnail,
    List<String>? pages,
    List<CapturedAsset>? assets,
    CrawlStatus? status,
    String? error,
    bool clearError = false,
  }) {
    return WebSnapshot(
      id: id,
      url: url ?? this.url,
      capturedAt: capturedAt,
      depth: depth ?? this.depth,
      pageCount: pageCount ?? this.pageCount,
      assetCount: assetCount ?? this.assetCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      title: title ?? this.title,
      description: description ?? this.description,
      favicon: favicon ?? this.favicon,
      thumbnail: thumbnail ?? this.thumbnail,
      pages: pages ?? List.from(this.pages),
      assets: assets ?? List.from(this.assets),
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Main content for websnapshot document (stored in content/main.json)
class WebSnapshotContent {
  final String id;
  final String schema;
  String title;
  String targetUrl;  // Default URL for new snapshots
  int version;
  final DateTime created;
  DateTime modified;
  WebSnapshotSettings settings;
  List<String> snapshots;  // List of snapshot IDs in order

  WebSnapshotContent({
    required this.id,
    this.schema = 'ndf-websnapshot-1.0',
    required this.title,
    this.targetUrl = '',
    this.version = 1,
    required this.created,
    required this.modified,
    WebSnapshotSettings? settings,
    List<String>? snapshots,
  }) : settings = settings ?? WebSnapshotSettings(),
       snapshots = snapshots ?? [];

  factory WebSnapshotContent.create({required String title}) {
    final now = DateTime.now();
    final id = 'websnapshot-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return WebSnapshotContent(
      id: id,
      title: title,
      created: now,
      modified: now,
    );
  }

  factory WebSnapshotContent.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final id = json['id'] as String? ??
        'websnapshot-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final createdStr = json['created'] as String?;
    final modifiedStr = json['modified'] as String?;
    final created = createdStr != null ? DateTime.parse(createdStr) : now;
    final modified = modifiedStr != null ? DateTime.parse(modifiedStr) : now;

    WebSnapshotSettings? settings;
    final settingsJson = json['settings'] as Map<String, dynamic>?;
    if (settingsJson != null) {
      settings = WebSnapshotSettings.fromJson(settingsJson);
    }

    // Derive title from URL if not provided
    final targetUrl = json['target_url'] as String? ?? '';
    var title = json['title'] as String?;
    if (title == null || title.isEmpty) {
      title = targetUrl.isNotEmpty ? titleFromUrl(targetUrl) : 'Web Snapshot';
    }

    return WebSnapshotContent(
      id: id,
      schema: json['schema'] as String? ?? 'ndf-websnapshot-1.0',
      title: title,
      targetUrl: targetUrl,
      version: json['version'] as int? ?? 1,
      created: created,
      modified: modified,
      settings: settings,
      snapshots: (json['snapshots'] as List<dynamic>?)
          ?.map((s) => s as String)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'websnapshot',
    'id': id,
    'schema': schema,
    'title': title,
    'target_url': targetUrl,
    'version': version,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'settings': settings.toJson(),
    'snapshots': snapshots,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Touch the modified timestamp and increment version
  void touch() {
    modified = DateTime.now();
    version++;
  }

  /// Add a snapshot ID
  void addSnapshot(String snapshotId) {
    snapshots.add(snapshotId);
    touch();
  }

  /// Remove a snapshot ID
  void removeSnapshot(String snapshotId) {
    snapshots.remove(snapshotId);
    touch();
  }
}
