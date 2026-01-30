# NDF Web Snapshot Document Type

## Overview

Create a new NDF document type `websnapshot` that allows users to capture and store static versions of websites for offline viewing and sharing. Supports multiple snapshots over time with configurable crawl depth and **content-addressed asset deduplication** to minimize storage.

## Key Features

1. **URL Input** - User provides URL to capture
2. **Configurable Crawl Depth** - 0 (single page), 1, 2, or 3 levels deep
3. **Asset Capture** - Downloads images, CSS, JS, fonts
4. **Multiple Snapshots** - Take new snapshots at different times
5. **Asset Deduplication** - Shared asset pool using content hashing (SHA256)
6. **WebView Preview** - View captured sites in embedded WebView
7. **JS Rendering** - Use Flutter WebView to render JS before capturing (platform permitting)
8. **Self-Contained Viewer** - index.html with metrics and snapshot navigation
9. **Offline Sharing** - Self-contained NDF file works without internet

## Archive Structure

Assets are stored in a **shared pool** using content-addressed storage (SHA256 hash of content). Each snapshot only stores its HTML files, referencing shared assets. This drastically reduces storage when taking multiple snapshots of the same or similar sites.

```
websnapshot.ndf
├── ndf.json                         # type: "websnapshot"
├── permissions.json
├── index.html                       # Self-viewing HTML with metrics & navigation
│
├── content/
│   ├── main.json                    # WebSnapshotContent (URL, settings, snapshot list)
│   └── snapshots/
│       ├── snap-001.json            # Snapshot 1 metadata
│       └── snap-002.json            # Snapshot 2 metadata
│
├── assets/
│   ├── thumbnails/
│   │   ├── preview.png              # Document thumbnail
│   │   ├── snap-001.png             # Snapshot 1 preview
│   │   └── snap-002.png             # Snapshot 2 preview
│   │
│   ├── pool/                        # SHARED content-addressed asset pool
│   │   ├── css/
│   │   │   ├── a1b2c3d4.css         # Hash-named CSS files
│   │   │   └── e5f6g7h8.css
│   │   ├── js/
│   │   │   └── i9j0k1l2.js
│   │   ├── images/
│   │   │   ├── m3n4o5p6.png
│   │   │   └── q7r8s9t0.jpg
│   │   └── fonts/
│   │       └── u1v2w3x4.woff2
│   │
│   └── snapshots/                   # Per-snapshot HTML pages only
│       ├── snap-001/
│       │   ├── index.html           # Rewritten HTML → references ../pool/*
│       │   └── about.html           # Additional pages (if depth > 0)
│       └── snap-002/
│           └── index.html
```

## Deduplication Strategy

### Content-Addressed Storage

1. **Hash each asset** - Compute SHA256 of file content
2. **Store once** - Save to `assets/pool/{type}/{hash}.{ext}`
3. **Reference by hash** - HTML/CSS rewrites point to pool paths
4. **Track references** - Each snapshot tracks which hashes it uses

### Asset Manifest (in main.json)

```json
{
  "asset_pool": {
    "a1b2c3d4e5f6": {
      "original_urls": [
        "https://example.com/styles/main.css",
        "https://example.com/css/main.css"
      ],
      "local_path": "pool/css/a1b2c3d4.css",
      "mime_type": "text/css",
      "size_bytes": 15420,
      "first_seen": "2025-01-30T10:00:00Z",
      "referenced_by": ["snap-001", "snap-002"]
    }
  }
}
```

### Deduplication Benefits

| Scenario | Without Dedup | With Dedup | Savings |
|----------|---------------|------------|---------|
| 2 snapshots, same site | 10 MB × 2 = 20 MB | 10 MB + 0.1 MB | ~50% |
| 5 snapshots, same site | 10 MB × 5 = 50 MB | 10 MB + 0.5 MB | ~80% |
| 3 snapshots, similar sites | 30 MB | ~15 MB | ~50% |

## Self-Viewing index.html

The root `index.html` provides a complete offline viewer with:

### Metrics Dashboard
- **Target URL** - The website being captured
- **Total snapshots** - Count of all snapshots
- **Total size** - Combined size of all assets
- **Unique assets** - Count of deduplicated files
- **Date range** - First and last snapshot dates

### Snapshot Navigation
- List of all snapshots with:
  - Thumbnail preview
  - Capture date/time
  - Page count
  - Size (unique to this snapshot)
  - Status badge (complete/partial/failed)
- Click to view any snapshot
- Compare mode (side-by-side of two snapshots)

### Viewer Features
- Dark theme
- Responsive layout
- Keyboard navigation
- Search snapshots by date

### Example index.html Structure

```html
<!DOCTYPE html>
<html>
<head>
  <title>Web Snapshot: example.com</title>
  <style>/* Embedded CSS for viewer */</style>
</head>
<body>
  <header>
    <h1>Web Snapshot</h1>
    <div class="metrics">
      <div class="metric">
        <span class="value" id="url">example.com</span>
        <span class="label">Target URL</span>
      </div>
      <div class="metric">
        <span class="value" id="snapshot-count">5</span>
        <span class="label">Snapshots</span>
      </div>
      <div class="metric">
        <span class="value" id="total-size">12.4 MB</span>
        <span class="label">Total Size</span>
      </div>
      <div class="metric">
        <span class="value" id="unique-assets">142</span>
        <span class="label">Unique Assets</span>
      </div>
    </div>
  </header>

  <main>
    <nav id="snapshot-list">
      <!-- Populated by JS from content/main.json -->
    </nav>

    <iframe id="viewer" src=""></iframe>
  </main>

  <script>
    // Load main.json and populate snapshot list
    // Handle navigation between snapshots
  </script>
</body>
</html>
```

## Files to Create/Modify

### 1. Add Document Type
**File:** `lib/work/models/ndf_document.dart`

```dart
enum NdfDocumentType {
  // ... existing types
  websnapshot,
}

// In iconName getter:
case NdfDocumentType.websnapshot:
  return 'language';
```

### 2. Create Content Model
**File:** `lib/work/models/websnapshot_content.dart` (NEW)

```dart
/// Crawl depth configuration
enum CrawlDepth { single, one, two, three }

/// Status of a crawl operation
enum CrawlStatus { pending, crawling, complete, failed }

/// Settings for web snapshot document
class WebSnapshotSettings {
  final CrawlDepth defaultDepth;
  final bool includeScripts;
  final bool includeStyles;
  final bool includeImages;
  final bool includeFonts;
  final int maxAssetSizeMb;
  // fromJson, toJson, copyWith
}

/// A deduplicated asset in the shared pool
class PooledAsset {
  final String hash;              // SHA256 hash (first 12 chars for filename)
  final List<String> originalUrls; // All URLs that resolved to this content
  final String localPath;          // Path in pool (e.g., "pool/css/a1b2c3d4.css")
  final String mimeType;
  final int sizeBytes;
  final DateTime firstSeen;
  final List<String> referencedBy; // Snapshot IDs using this asset
  // fromJson, toJson
}

/// Metadata for a single snapshot
class WebSnapshot {
  final String id;
  final String url;
  final DateTime capturedAt;
  final CrawlDepth depth;
  final int pageCount;             // Number of HTML pages captured
  final int newAssetCount;         // Assets added by this snapshot (not deduped)
  final int totalAssetCount;       // Total assets referenced
  final int uniqueSizeBytes;       // Size of new assets only
  final String? title;             // Page title
  final String? description;       // Meta description
  final String? thumbnail;         // asset:// reference to preview
  final List<String> pages;        // List of HTML page paths
  final List<String> assetHashes;  // Hashes of assets used
  final CrawlStatus status;
  final String? error;
  // fromJson, toJson, copyWith
}

/// Main content for websnapshot document
class WebSnapshotContent {
  final String id;
  final String schema;             // 'ndf-websnapshot-1.0'
  String title;
  String targetUrl;                // Primary URL being captured
  int version;
  final DateTime created;
  DateTime modified;
  WebSnapshotSettings settings;
  List<String> snapshots;          // Snapshot IDs in chronological order
  Map<String, PooledAsset> assetPool; // Hash -> PooledAsset
  // create(), fromJson, toJson, toJsonString, touch()

  /// Get total size of all unique assets
  int get totalPoolSize => assetPool.values.fold(0, (sum, a) => sum + a.sizeBytes);

  /// Get count of unique assets
  int get uniqueAssetCount => assetPool.length;
}
```

### 3. Create Capture Service
**File:** `lib/work/services/web_snapshot_service.dart` (NEW)

```dart
enum CapturePhase { fetching, parsing, downloading, deduplicating, rewriting, saving }

class CaptureProgress {
  final CapturePhase phase;
  final double progress;
  final String message;
  final int pagesProcessed;
  final int totalPages;
  final int assetsDownloaded;
  final int totalAssets;
  final int assetsDeduped;         // Assets that already existed in pool
}

class WebSnapshotService {
  /// Capture a website snapshot with deduplication
  Stream<CaptureProgress> captureWebsite({
    required String url,
    required CrawlDepth depth,
    required WebSnapshotSettings settings,
    required Map<String, PooledAsset> existingPool, // For deduplication
    CancelToken? cancelToken,
  });

  /// Compute SHA256 hash of content (first 12 hex chars for filename)
  String hashContent(Uint8List content);

  /// Check if asset already exists in pool
  bool assetExists(String hash, Map<String, PooledAsset> pool);

  /// Rewrite HTML to use pool asset references
  String rewriteHtmlForPool(String html, Map<String, String> urlToPoolPath);

  /// Rewrite CSS to use pool asset references
  String rewriteCssForPool(String css, Map<String, String> urlToPoolPath);

  /// Generate the self-viewing index.html
  String generateIndexHtml(WebSnapshotContent content, List<WebSnapshot> snapshots);

  /// Extract asset URLs from HTML
  List<String> extractAssetUrls(String html, String baseUrl);

  /// Extract linked pages from HTML (same domain only)
  List<String> extractPageUrls(String html, String baseUrl);
}
```

### 4. Add NDF Service Methods
**File:** `lib/work/services/ndf_service.dart`

Add to `_createDefaultContent()`:
```dart
case NdfDocumentType.websnapshot:
  final now = DateTime.now();
  return {
    'type': 'websnapshot',
    'id': 'websnapshot-${now.millisecondsSinceEpoch.toRadixString(36)}',
    'schema': 'ndf-websnapshot-1.0',
    'title': 'Untitled Web Snapshot',
    'target_url': '',
    'version': 1,
    'created': now.toIso8601String(),
    'modified': now.toIso8601String(),
    'settings': {
      'default_depth': 'single',
      'include_scripts': true,
      'include_styles': true,
      'include_images': true,
      'include_fonts': true,
      'max_asset_size_mb': 10,
    },
    'snapshots': [],
    'asset_pool': {},
  };
```

Add service methods:
```dart
// Read/write content
Future<WebSnapshotContent?> readWebSnapshotContent(String filePath);
Future<void> saveWebSnapshotContent(String filePath, WebSnapshotContent content);

// Read/write snapshots
Future<WebSnapshot?> readWebSnapshot(String filePath, String snapshotId);
Future<List<WebSnapshot>> readWebSnapshots(String filePath, List<String> snapshotIds);
Future<void> saveWebSnapshot(String filePath, WebSnapshot snapshot);
Future<void> deleteWebSnapshot(String filePath, String snapshotId);

// Asset pool operations
Future<void> savePooledAsset(String filePath, String hash, String subdir, Uint8List data);
Future<Uint8List?> readPooledAsset(String filePath, String poolPath);
Future<bool> pooledAssetExists(String filePath, String poolPath);

// Snapshot HTML pages
Future<void> saveSnapshotPage(String filePath, String snapshotId, String pageName, String html);
Future<String?> readSnapshotPage(String filePath, String snapshotId, String pageName);

// Index.html generation
Future<void> updateIndexHtml(String filePath, WebSnapshotContent content, List<WebSnapshot> snapshots);

// Cleanup orphaned assets (after snapshot deletion)
Future<void> cleanupUnreferencedAssets(String filePath, WebSnapshotContent content);
```

### 5. Create Editor Page
**File:** `lib/work/pages/websnapshot_editor_page.dart` (NEW)

```dart
class WebSnapshotEditorPage extends StatefulWidget {
  final String filePath;
  final String? title;
}

class _WebSnapshotEditorPageState extends State<WebSnapshotEditorPage> {
  // State
  WebSnapshotContent? _content;
  List<WebSnapshot> _snapshots = [];
  String? _selectedSnapshotId;
  bool _isCapturing = false;
  CaptureProgress? _captureProgress;

  // UI Components:
  // - Header with URL input and capture button
  // - Metrics panel (total snapshots, size, assets)
  // - Snapshot list (cards with preview, date, stats)
  // - Progress overlay during capture
  // - Snapshot viewer (WebView or external browser)
  // - Settings dialog
}
```

### 6. Create Widgets
**Directory:** `lib/work/widgets/websnapshot/` (NEW)

| Widget | Purpose |
|--------|---------|
| `snapshot_card_widget.dart` | Card with thumbnail, date, page count, size |
| `capture_progress_widget.dart` | Progress with phases and dedup stats |
| `snapshot_viewer_widget.dart` | WebView or external browser viewer |
| `url_input_widget.dart` | URL input with depth selector |
| `metrics_panel_widget.dart` | Document-level metrics display |

### 7. Add Navigation
**File:** `lib/work/pages/workspace_detail_page.dart`

```dart
case NdfDocumentType.websnapshot:
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => WebSnapshotEditorPage(
      filePath: filePath,
      title: doc.title,
    ),
  ));
```

### 8. Add i18n Strings
**Files:** `languages/en_US/work.json`, `languages/pt_PT/work.json`

```json
{
  "work_websnapshot": "Web Snapshot",
  "work_websnapshot_capture": "Capture",
  "work_websnapshot_url_hint": "Enter website URL",
  "work_websnapshot_depth": "Crawl Depth",
  "work_websnapshot_depth_single": "Single page",
  "work_websnapshot_depth_one": "1 level deep",
  "work_websnapshot_depth_two": "2 levels deep",
  "work_websnapshot_depth_three": "3 levels deep",
  "work_websnapshot_capturing": "Capturing website...",
  "work_websnapshot_no_snapshots": "No snapshots yet",
  "work_websnapshot_add_first": "Enter a URL above to capture a website",
  "work_websnapshot_delete_snapshot": "Delete Snapshot",
  "work_websnapshot_delete_confirm": "Delete snapshot from {date}?",
  "work_websnapshot_pages": "{count} pages",
  "work_websnapshot_assets": "{count} assets",
  "work_websnapshot_new_assets": "{count} new",
  "work_websnapshot_deduped": "{count} reused",
  "work_websnapshot_size": "{size}",
  "work_websnapshot_total_size": "Total: {size}",
  "work_websnapshot_unique_assets": "{count} unique assets",
  "work_websnapshot_view": "View Snapshot",
  "work_websnapshot_settings": "Capture Settings",
  "work_websnapshot_js_warning": "JavaScript content may not be captured on this platform"
}
```

## Implementation Phases

### Phase 1: Core Model & Service (Foundation)
1. Add `websnapshot` to `NdfDocumentType` enum
2. Create `websnapshot_content.dart` model with deduplication structures
3. Add NDF service methods for read/write
4. Add default content creation

### Phase 2: Capture Service with Deduplication
1. Create `web_snapshot_service.dart`
2. Implement content hashing (SHA256)
3. Implement pool-aware asset downloading
4. Implement HTML/CSS rewriting for pool paths
5. Implement progress streaming with dedup stats

### Phase 3: Editor Page & UI
1. Create `websnapshot_editor_page.dart`
2. Create widget components
3. Add navigation routing
4. Add i18n strings

### Phase 4: Self-Viewing index.html
1. Create index.html template with metrics
2. Implement snapshot navigation
3. Implement iframe viewer
4. Update index.html on each capture

### Phase 5: WebView Preview & Polish
1. Implement snapshot extraction to temp
2. Integrate WebView for in-app viewing
3. Add cleanup for orphaned assets
4. Test deduplication efficiency

## Platform Considerations

| Platform | WebView | JS Rendering | Notes |
|----------|---------|--------------|-------|
| Android | Yes | Yes | Full support |
| iOS | Yes | Yes | Full support |
| macOS | Yes | Yes | Full support |
| Linux | Limited | No | Static capture, external browser |
| Windows | Limited | No | Static capture, external browser |

## Verification

1. Create web snapshot document
2. Capture `https://example.com` (single page)
3. Verify snapshot appears with correct stats
4. Capture same URL again
5. **Verify deduplication**: second snapshot should show "X assets reused"
6. Check total size didn't double
7. Open in-app viewer or external browser
8. Extract NDF and verify:
   ```bash
   unzip -l document.ndf | grep pool/   # Shared assets
   unzip -p document.ndf content/main.json | jq '.asset_pool | length'
   ```
9. Open `index.html` in browser (via local server)
10. Verify metrics and snapshot navigation work
11. Delete one snapshot
12. Verify orphan cleanup removes unused assets
