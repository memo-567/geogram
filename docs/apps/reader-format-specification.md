# Reader Format Specification

**Version**: 1.1
**Last Updated**: 2026-01-24
**Status**: Active

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Source Architecture](#source-architecture)
- [RSS Sources](#rss-sources)
- [Manga Sources](#manga-sources)
- [Books Category](#books-category)
- [Settings](#settings)
- [Reading Progress](#reading-progress)
- [Complete Examples](#complete-examples)
- [Parsing Implementation](#parsing-implementation)
- [File Operations](#file-operations)
- [Validation Rules](#validation-rules)
- [Best Practices](#best-practices)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

This document specifies the format used for the Reader app in the Geogram system. The Reader provides an e-reader experience for e-books, manga, and RSS feeds with offline reading capabilities, progress tracking, and a source-based architecture for content acquisition.

### Key Features

- **Source-Based Architecture**: Extensible JavaScript crawlers for content sources
- **Three Content Categories**: RSS feeds, Manga, and Books with dedicated icons
- **Offline Reading**: All content downloaded and stored locally
- **Progress Tracking**: Reading position saved across all content types
- **RSS/Atom Support**: Built-in parsing for standard feed formats
- **Manga CBZ Support**: Chapter-based reading with automatic detection
- **JavaScript Crawlers**: Customizable `source.js` files for each data source

### Content Categories

| Category | Icon | Source Type | Storage |
|----------|------|-------------|---------|
| RSS | Feed icon | `source.js` with URL | Posts as markdown |
| Manga | Book icon | `source.js` with crawler | CBZ chapter files |
| Books | Library icon | Local files | EPUB, PDF, TXT, MD |

## File Organization

### Directory Structure

The Reader app uses a category-based structure where each content type has its own root folder with sources defined by JavaScript crawler files.

```
reader/                                     # Reader root (NOT reader/reader)
├── settings.json                           # App settings
├── progress.json                           # Global reading progress
│
├── rss/                                    # RSS Category
│   ├── {source-slug}/                      # Each source is a folder
│   │   ├── source.js                       # JavaScript crawler definition
│   │   ├── data.json                       # Source metadata cache
│   │   ├── icon.png                        # Optional source icon
│   │   └── posts/                          # Downloaded posts
│   │       ├── YYYY-MM-DD_article-title/
│   │       │   ├── data.json               # Post metadata
│   │       │   ├── content.md              # Post content (markdown)
│   │       │   └── images/                 # Downloaded images
│   │       │       ├── {sha1}_{filename}
│   │       │       └── ...
│   │       └── ...
│   └── ...
│
├── manga/                                  # Manga Category
│   ├── {source-slug}/                      # Each source is a folder
│   │   ├── source.js                       # JavaScript crawler definition
│   │   ├── data.json                       # Source metadata cache
│   │   └── series/                         # Downloaded manga series
│   │       ├── {manga-slug}/
│   │       │   ├── data.json               # Manga metadata
│   │       │   ├── thumbnail.jpg           # Cover image
│   │       │   ├── chapter-001.cbz         # Chapter files
│   │       │   ├── chapter-002.cbz
│   │       │   └── ...
│   │       └── ...
│   └── ...
│
└── books/                                  # Books Category
    ├── folder.json                         # Optional folder metadata
    ├── {subfolder}/                        # User-defined folders (5 levels max)
    │   ├── folder.json
    │   └── *.epub, *.pdf, *.txt, *.md
    └── ...
```

### Folder Naming Convention

**Pattern**: `{sanitized-name}/`

**Sanitization Rules**:
1. Convert to lowercase
2. Replace spaces and underscores with hyphens
3. Remove non-alphanumeric characters (except hyphens)
4. Collapse multiple consecutive hyphens
5. Remove leading/trailing hyphens
6. Truncate to 50 characters

**Examples**:
```
"Hacker News" → hackernews/
"Tech Crunch" → tech-crunch/
"MangaDex" → mangadex/
"One Punch Man!" → one-punch-man/
```

### Post Folder Naming Convention

**Pattern**: `YYYY-MM-DD_sanitized-title/`

**Examples**:
```
2026-01-15_my-first-post/
2026-01-20_getting-started-with-python/
2026-02-01_10-tips-for-better-code/
```

## Source Architecture

### What is a Source?

A **source** is a folder containing a `source.js` file that defines how to:
1. Connect to a website or feed
2. List available content (articles, chapters)
3. Download and store content locally
4. Format the local folder structure

### source.js File Structure

The `source.js` file exports a configuration object with metadata and optional async functions for custom crawling.

```javascript
// Example: reader/rss/hackernews/source.js
module.exports = {
  // Required: Source metadata
  name: "Hacker News",
  type: "rss",                              // rss | manga
  url: "https://news.ycombinator.com",

  // Optional: Icon filename
  icon: "icon.png",

  // Optional: Feed type (for RSS sources)
  feedType: "auto",                         // auto | rss | atom | custom

  // Optional: Custom settings
  settings: {
    maxPosts: 100,
    fetchIntervalHours: 1,
    downloadImages: true
  },

  // Optional: Custom fetch for listing content
  async fetchList() {
    // Return array of items
    return [
      { id: "123", title: "Article Title", url: "...", date: "..." }
    ];
  },

  // Optional: Custom fetch for individual items
  async fetchItem(item) {
    return {
      title: item.title,
      content: "...",                       // Markdown content
      images: []                            // Array of image URLs
    };
  },

  // Optional: Folder structure configuration
  folderStructure: {
    postFolder: "{date}_{slug}",
    files: ["data.json", "content.md"]
  }
};
```

### Source Types

| Type | Purpose | Required Functions |
|------|---------|-------------------|
| `rss` | RSS/Atom feeds | None (built-in parser) or custom `fetchList`, `fetchItem` |
| `manga` | Manga sites | `search`, `getChapters`, `downloadChapter` |

## RSS Sources

### Simple RSS Source (Minimal)

For standard RSS/Atom feeds, only the URL is required:

```javascript
// reader/rss/my-blog/source.js
module.exports = {
  name: "My Favorite Blog",
  type: "rss",
  url: "https://blog.example.com/feed.xml"
};
```

### Custom RSS Source

For sites without standard feeds or with custom requirements:

```javascript
// reader/rss/hackernews/source.js
module.exports = {
  name: "Hacker News",
  type: "rss",
  url: "https://news.ycombinator.com/rss",
  feedType: "auto",

  settings: {
    maxPosts: 100,
    fetchIntervalHours: 1,
    downloadImages: true
  },

  // Optional: Override default content extraction
  async fetchItem(item) {
    // Fetch the actual article content
    const response = await fetch(item.url);
    const html = await response.text();
    // Extract and convert to markdown
    return {
      title: item.title,
      content: extractContent(html),
      images: extractImages(html)
    };
  }
};
```

### RSS Source data.json Schema

```json
{
  "id": "source_hackernews",
  "name": "Hacker News",
  "url": "https://news.ycombinator.com/rss",
  "feed_type": "rss",
  "post_count": 100,
  "unread_count": 15,
  "last_fetched_at": "2026-01-23T10:00:00Z",
  "created_at": "2026-01-01T10:00:00Z",
  "modified_at": "2026-01-23T10:00:00Z"
}
```

### RSS Post data.json Schema

```json
{
  "id": "post_2026-01-15_article-title",
  "title": "Article Title",
  "author": "John Doe",
  "published_at": "2026-01-15T08:00:00Z",
  "fetched_at": "2026-01-15T10:30:00Z",
  "url": "https://example.com/article",
  "guid": "https://example.com/article",
  "summary": "First paragraph of the article...",
  "word_count": 1250,
  "read_time_minutes": 5,
  "categories": ["technology", "programming"],
  "tags": ["python", "tutorial"],
  "images": [
    {
      "original_url": "https://example.com/images/hero.jpg",
      "local_filename": "a1b2c3d4_hero.jpg",
      "alt_text": "Hero image"
    }
  ],
  "is_read": false,
  "is_starred": false
}
```

### RSS Post data.json Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique post identifier |
| `title` | string | Yes | Post title |
| `author` | string | No | Post author name |
| `published_at` | ISO 8601 | Yes | Original publication date |
| `fetched_at` | ISO 8601 | Yes | When post was downloaded |
| `url` | string | Yes | Original post URL |
| `guid` | string | Yes | RSS GUID for deduplication |
| `summary` | string | No | Short excerpt |
| `word_count` | integer | No | Content word count |
| `read_time_minutes` | integer | No | Estimated reading time |
| `categories` | array | No | RSS categories |
| `tags` | array | No | RSS tags |
| `images` | array | No | Downloaded image metadata |
| `is_read` | boolean | Yes | Read status |
| `is_starred` | boolean | Yes | Starred/bookmarked status |

### RSS Post Content (content.md)

Post content is converted to markdown and stored in `content.md`. Image references are rewritten to local paths.

```markdown
# Article Title

By John Doe | Published: January 15, 2026

This is the first paragraph of the article about technology...

![Hero image](images/a1b2c3d4_hero.jpg)

More content goes here with proper markdown formatting...

## Section Title

Additional content with inline images:

![Chart](images/d4e5f6g7_chart.png)

---

*Originally published at: https://example.com/article*
```

## Manga Sources

### Manga source.js Structure

Manga sources require specific functions for searching, listing chapters, and downloading:

```javascript
// reader/manga/mangadex/source.js
module.exports = {
  name: "MangaDex",
  type: "manga",
  url: "https://mangadex.org",

  // Search for manga series
  async search(query) {
    const response = await fetch(`https://api.mangadex.org/manga?title=${encodeURIComponent(query)}`);
    const data = await response.json();
    return data.data.map(manga => ({
      id: manga.id,
      title: manga.attributes.title.en,
      thumbnail: `https://uploads.mangadex.org/covers/${manga.id}/${manga.relationships[0].attributes.fileName}`,
      description: manga.attributes.description.en,
      author: manga.relationships.find(r => r.type === 'author')?.attributes.name,
      status: manga.attributes.status,
      year: manga.attributes.year
    }));
  },

  // Get chapters for a manga
  async getChapters(mangaId) {
    const response = await fetch(`https://api.mangadex.org/manga/${mangaId}/feed?translatedLanguage[]=en&order[chapter]=asc`);
    const data = await response.json();
    return data.data.map(ch => ({
      id: ch.id,
      number: parseFloat(ch.attributes.chapter),
      title: ch.attributes.title || `Chapter ${ch.attributes.chapter}`,
      volume: ch.attributes.volume ? parseInt(ch.attributes.volume) : null,
      pages: ch.attributes.pages
    }));
  },

  // Download chapter pages
  async downloadChapter(chapterId) {
    const response = await fetch(`https://api.mangadex.org/at-home/server/${chapterId}`);
    const data = await response.json();
    const baseUrl = data.baseUrl;
    const hash = data.chapter.hash;
    return data.chapter.data.map(filename => `${baseUrl}/data/${hash}/${filename}`);
  }
};
```

### Local Manga Source

For locally stored manga without crawling:

```javascript
// reader/manga/local/source.js
module.exports = {
  name: "Local Manga",
  type: "manga",
  url: null,
  local: true
  // No search/getChapters/downloadChapter needed
  // App scans folder for data.json files and CBZ files
};
```

### Manga data.json Schema

Each manga series has a `data.json` file with metadata. Chapters are auto-detected from CBZ files in the folder.

```json
{
  "id": "manga_one-punch-man",
  "title": "One Punch Man",
  "original_title": "ワンパンマン",
  "author": "ONE",
  "artist": "Yusuke Murata",
  "description": "The story of Saitama, a hero who can defeat any opponent with a single punch but struggles to find a worthy foe.",
  "status": "ongoing",
  "genres": ["action", "comedy", "superhero", "parody"],
  "tags": ["martial-arts", "overpowered-protagonist"],
  "year": 2009,
  "language": "en",
  "thumbnail": "thumbnail.jpg",
  "source_url": "https://mangadex.org/title/d8a959f7-648e-4c8d-8f23-f1f3f8e129f3",
  "source_id": "mangadex",
  "created_at": "2026-01-01T10:00:00Z",
  "modified_at": "2026-01-15T14:30:00Z"
}
```

### Manga data.json Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique manga identifier |
| `title` | string | Yes | Display title |
| `original_title` | string | No | Original title (Japanese, Korean, etc.) |
| `author` | string | No | Story author |
| `artist` | string | No | Artist (if different from author) |
| `description` | string | Yes | Synopsis |
| `status` | string | Yes | `ongoing`, `completed`, `hiatus`, `cancelled` |
| `genres` | array | No | Genre list |
| `tags` | array | No | Additional tags |
| `year` | integer | No | Publication year |
| `language` | string | No | Content language (ISO 639-1) |
| `thumbnail` | string | Yes | Thumbnail filename |
| `source_url` | string | No | Original source URL |
| `source_id` | string | No | Source identifier (e.g., "mangadex") |
| `created_at` | ISO 8601 | Yes | When manga was added |
| `modified_at` | ISO 8601 | Yes | Last modification |

### Chapter Detection

Chapters are automatically detected from CBZ files in the manga folder:

1. App scans folder for `*.cbz` files
2. Files are sorted alphanumerically
3. Chapter number extracted from filename if possible

**Recommended naming patterns**:
- `chapter-001.cbz`, `chapter-002.cbz` (simple)
- `vol-01-ch-001.cbz`, `vol-02-ch-010.cbz` (with volume)
- `ch-001-part-1.cbz`, `ch-001-part-2.cbz` (multi-part)

### CBZ File Format

CBZ files are ZIP archives containing images:
- Images sorted alphanumerically: `001.jpg`, `002.jpg`, etc.
- Supported formats: JPG, PNG, WebP, GIF
- Standard comic book archive format

### Manga Thumbnails

- **Required**: Yes
- **Filename**: `thumbnail.jpg` or `thumbnail.png`
- **Location**: Same folder as manga `data.json`
- **Recommended size**: 300x450 pixels (2:3 aspect ratio)
- **Max file size**: 500 KB

## Books Category

### Design Philosophy

Books are the simplest category - just local files organized by the user without requiring `source.js` crawlers.

### Supported Formats

| Format | Extension | Description |
|--------|-----------|-------------|
| EPUB | `.epub` | Standard e-book format |
| PDF | `.pdf` | Portable Document Format |
| Plain Text | `.txt` | Simple text files |
| Markdown | `.md` | Markdown formatted text |

### Folder Organization

- Up to **5 levels** of subfolders for organization
- Optional `folder.json` for folder metadata
- Files open directly in the appropriate viewer

### folder.json Schema (Optional)

```json
{
  "name": "Science Fiction",
  "description": "My favorite sci-fi books",
  "icon": "rocket",
  "color": "#4CAF50",
  "created_at": "2026-01-01T10:00:00Z",
  "modified_at": "2026-01-15T14:30:00Z"
}
```

## Settings

### settings.json Schema

App settings are stored in `reader/settings.json`:

```json
{
  "version": "1.0",
  "general": {
    "theme": "dark",
    "font_size": 16,
    "line_height": 1.6,
    "font_family": "system"
  },
  "rss": {
    "auto_fetch": true,
    "fetch_interval_hours": 1,
    "max_posts_per_source": 100,
    "mark_read_on_open": true,
    "download_images": true
  },
  "manga": {
    "page_mode": "single",
    "reading_direction": "ltr",
    "preload_pages": 3
  },
  "books": {
    "epub_theme": "sepia",
    "pdf_continuous": true,
    "remember_position": true
  }
}
```

### Settings Field Descriptions

| Section | Field | Type | Default | Description |
|---------|-------|------|---------|-------------|
| general | theme | string | "dark" | UI theme: light, dark, system |
| general | font_size | integer | 16 | Base font size in pixels |
| general | line_height | float | 1.6 | Line height multiplier |
| general | font_family | string | "system" | Font family |
| rss | auto_fetch | boolean | true | Automatically fetch feeds |
| rss | fetch_interval_hours | integer | 1 | Hours between auto-fetch |
| rss | max_posts_per_source | integer | 100 | Max posts to keep per source |
| rss | mark_read_on_open | boolean | true | Mark article read on open |
| rss | download_images | boolean | true | Download article images |
| manga | page_mode | string | "single" | single, double, webtoon |
| manga | reading_direction | string | "ltr" | ltr (left-to-right), rtl |
| manga | preload_pages | integer | 3 | Pages to preload ahead |
| books | epub_theme | string | "sepia" | light, dark, sepia |
| books | pdf_continuous | boolean | true | Continuous scroll mode |
| books | remember_position | boolean | true | Remember last position |

## Reading Progress

### progress.json Schema

Global reading progress is tracked in `reader/progress.json`:

```json
{
  "version": "1.0",
  "last_updated": "2026-01-23T14:30:00Z",
  "books": {
    "books/fiction/dune.epub": {
      "type": "ebook",
      "position": {
        "chapter": 5,
        "page": 142,
        "cfi": "epubcfi(/6/14!/4/2/1:0)",
        "percent": 45.2
      },
      "last_read_at": "2026-01-22T20:00:00Z",
      "total_reading_time_seconds": 7200,
      "started_at": "2026-01-10T10:00:00Z"
    },
    "books/technical/manual.pdf": {
      "type": "ebook",
      "position": {
        "page": 87,
        "percent": 32.5
      },
      "last_read_at": "2026-01-20T15:00:00Z",
      "total_reading_time_seconds": 3600,
      "started_at": "2026-01-15T09:00:00Z"
    }
  },
  "manga": {
    "manga/mangadex/series/one-punch-man": {
      "current_chapter": "chapter-003.cbz",
      "current_page": 12,
      "chapters_read": ["chapter-001.cbz", "chapter-002.cbz"],
      "last_read_at": "2026-01-23T14:00:00Z",
      "started_at": "2026-01-20T10:00:00Z"
    }
  },
  "rss": {
    "rss/hackernews/posts/2026-01-15_article-title": {
      "is_read": true,
      "read_at": "2026-01-16T10:00:00Z",
      "scroll_position": 0.85
    }
  }
}
```

### Book Progress Fields

| Field | Type | Description |
|-------|------|-------------|
| `position.chapter` | integer | Chapter number (EPUB) |
| `position.page` | integer | Page number |
| `position.cfi` | string | EPUB CFI position identifier |
| `position.percent` | float | Percent complete (0-100) |
| `last_read_at` | ISO 8601 | Last reading session |
| `total_reading_time_seconds` | integer | Cumulative reading time |
| `started_at` | ISO 8601 | When reading started |

### Manga Progress Fields

| Field | Type | Description |
|-------|------|-------------|
| `current_chapter` | string | Current chapter filename |
| `current_page` | integer | Current page in chapter |
| `chapters_read` | array | List of completed chapter filenames |
| `last_read_at` | ISO 8601 | Last reading session |
| `started_at` | ISO 8601 | When reading started |

### RSS Progress Fields

| Field | Type | Description |
|-------|------|-------------|
| `is_read` | boolean | Read status |
| `read_at` | ISO 8601 | When marked as read |
| `scroll_position` | float | Scroll position (0-1) |

## Complete Examples

### Example 1: Simple RSS Source

**Directory Structure**:
```
reader/rss/my-blog/
├── source.js
├── data.json
└── posts/
    └── 2026-01-15_hello-world/
        ├── data.json
        └── content.md
```

**source.js**:
```javascript
module.exports = {
  name: "My Blog",
  type: "rss",
  url: "https://myblog.com/feed.xml"
};
```

### Example 2: Manga Source with Custom Crawler

**Directory Structure**:
```
reader/manga/mangadex/
├── source.js
├── data.json
└── series/
    └── one-punch-man/
        ├── data.json
        ├── thumbnail.jpg
        ├── chapter-001.cbz
        ├── chapter-002.cbz
        └── chapter-003.cbz
```

### Example 3: Local Books Organization

**Directory Structure**:
```
reader/books/
├── folder.json
├── fiction/
│   ├── folder.json
│   ├── sci-fi/
│   │   ├── dune.epub
│   │   └── foundation.epub
│   └── fantasy/
│       └── lotr.epub
└── technical/
    ├── programming.pdf
    └── design-patterns.pdf
```

## Parsing Implementation

### Loading a Source

```dart
Future<Source> loadSource(String categoryPath, String sourceName) async {
  final sourcePath = '$categoryPath/$sourceName/source.js';
  final file = File(sourcePath);

  if (!await file.exists()) {
    throw SourceNotFoundException(sourceName);
  }

  final jsContent = await file.readAsString();
  // Evaluate JavaScript and extract module.exports
  final config = await evaluateJavaScript(jsContent);

  return Source.fromConfig(config, sourcePath);
}
```

### Detecting Manga Chapters

```dart
Future<List<String>> detectChapters(String mangaPath) async {
  final dir = Directory(mangaPath);
  final files = await dir.list().toList();

  return files
    .where((f) => f.path.endsWith('.cbz'))
    .map((f) => path.basename(f.path))
    .toList()
    ..sort(); // Alphanumeric sort
}
```

### Parsing RSS Feeds

```dart
Future<List<RssPost>> fetchFeed(String url) async {
  final response = await http.get(Uri.parse(url));
  final document = XmlDocument.parse(response.body);

  // Detect RSS vs Atom
  if (document.findAllElements('rss').isNotEmpty) {
    return parseRss(document);
  } else if (document.findAllElements('feed').isNotEmpty) {
    return parseAtom(document);
  }

  throw UnsupportedFeedFormat();
}
```

## File Operations

### Creating a New Source

1. Create source folder: `reader/{category}/{source-slug}/`
2. Create `source.js` with configuration
3. Create `data.json` with source metadata
4. Optionally add `icon.png`

### Adding Content

**RSS Posts**:
1. Fetch feed using `source.js` configuration
2. For each new item, create `posts/YYYY-MM-DD_slug/`
3. Create `data.json` with post metadata
4. Download and convert content to `content.md`
5. Download images to `images/` subfolder

**Manga Series**:
1. Use source crawler to search/select manga
2. Create `series/{manga-slug}/`
3. Create `data.json` with manga metadata
4. Download thumbnail
5. Download chapters as CBZ files

**Books**:
1. Copy file to `books/` or subfolder
2. Optionally create `folder.json` for organization

### Updating Progress

1. Read current `progress.json`
2. Update relevant entry
3. Write back with `last_updated` timestamp
4. Use atomic write (temp file + rename)

## Validation Rules

### Source Validation

- `source.js` must be valid JavaScript
- `name` field is required
- `type` must be `rss` or `manga`
- `url` is required for non-local sources

### RSS Validation

- Post folders must follow `YYYY-MM-DD_slug` pattern
- `data.json` must contain required fields: `id`, `title`, `published_at`, `url`
- `content.md` should exist for each post

### Manga Validation

- `data.json` must exist with required fields: `id`, `title`, `thumbnail`, `description`
- Thumbnail file must exist
- At least one `.cbz` file should exist

### Progress Validation

- Paths must reference existing content
- Percent values must be 0-100
- Page numbers must be positive integers

## Best Practices

### For Users

1. **Organize sources by topic**: Keep RSS sources grouped logically
2. **Use meaningful folder names**: Clear names for book organization
3. **Regular cleanup**: Remove old posts to save space
4. **Backup progress**: Save `progress.json` for continuity

### For Developers

1. **Lazy loading**: Load content on demand
2. **Cache thumbnails**: Pre-generate grid views
3. **Background sync**: Fetch RSS in background
4. **Atomic writes**: Use temp files for progress saves
5. **Image cleanup**: Remove orphaned images periodically
6. **Respect rate limits**: Add delays between API calls

### For Source Authors

1. **Handle errors gracefully**: Return empty arrays on failure
2. **Provide fallbacks**: Handle missing fields in API responses
3. **Use pagination**: Don't fetch everything at once
4. **Cache responses**: Avoid redundant API calls

## Security Considerations

### JavaScript Execution

- Source files execute with limited permissions
- Network access restricted to specified URLs
- No filesystem access outside source folder
- Sandboxed execution environment

### File Security

- Validate file paths to prevent directory traversal
- Scan CBZ contents for malicious files
- Limit image download sizes
- Sanitize HTML in RSS content before conversion

### Network Security

- Use HTTPS for feeds when available
- Validate SSL certificates
- Set reasonable timeouts
- Respect robots.txt and rate limits

### Privacy

- All content stored locally (no cloud sync)
- RSS fetches may reveal reading habits to feed providers
- Consider proxy options for privacy-sensitive sources

## Related Documentation

- [Blog Format Specification](blog-format-specification.md) - Similar folder and date patterns
- [Video Format Specification](video-format-specification.md) - Metadata and thumbnail patterns
- [News Format Specification](news-format-specification.md) - Content download patterns

## Change Log

### Version 1.1 (2026-01-24)

- Added Settings section with settings.json schema
- Updated status from Draft to Active

### Version 1.0 (2026-01-23)

- Initial specification
- Source-based architecture with JavaScript crawlers
- Three content categories: RSS, Manga, Books
- RSS/Atom feed support with custom crawler option
- Manga support with CBZ chapters and auto-detection
- Local book support (EPUB, PDF, TXT, MD)
- Global progress tracking
- Thumbnail handling for visual previews
