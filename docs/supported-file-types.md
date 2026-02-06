# Supported File Types

File types supported by Geogram viewers, as documented in `reusable.md`.

---

## PhotoViewerPage

**File:** `lib/pages/photo_viewer_page.dart`

Full-screen media viewer for photos and videos.

### Images
No specific formats listed - accepts image paths generically.

### Videos
| Extension | Format |
|-----------|--------|
| `.mp4` | MPEG-4 |
| `.avi` | Audio Video Interleave |
| `.mkv` | Matroska |
| `.mov` | QuickTime |
| `.wmv` | Windows Media Video |
| `.flv` | Flash Video |
| `.webm` | WebM |

---

## DocumentViewerWidget / DocumentViewerEditorPage

**File:** `lib/pages/document_viewer_editor_page.dart`

Document viewer with auto-detection for text, markdown, and PDF files.

### Viewer Types

| Type | Extensions |
|------|------------|
| `DocumentViewerType.text` | `.txt`, `.log`, `.json`, `.xml`, etc. |
| `DocumentViewerType.markdown` | `.md`, `.markdown` |
| `DocumentViewerType.pdf` | `.pdf` |
| `DocumentViewerType.cbz` | `.cbz` (future implementation) |

### Editable Text Extensions

Files that support inline editing via `DocumentViewerWidget.isEditableExtension()`:

| Category | Extensions |
|----------|------------|
| Plain text | `txt`, `log` |
| Data formats | `json`, `xml`, `csv`, `yaml`, `yml`, `ini`, `conf`, `cfg`, `toml` |
| Markup | `md`, `markdown`, `html`, `htm`, `css` |
| Programming | `dart`, `py`, `js`, `ts`, `java`, `c`, `cpp`, `h`, `sh`, `bat`, `kt`, `go`, `rs`, `rb`, `php` |

---

## ReaderService (E-Reader)

**File:** `lib/reader/services/reader_service.dart`

E-reader for books and manga.

| Type | Format |
|------|--------|
| E-books | `.epub` |
| Manga chapters | `.cbz` |

---

## Summary

| Widget | File Types |
|--------|------------|
| PhotoViewerPage | Images (generic), Videos (mp4, avi, mkv, mov, wmv, flv, webm) |
| DocumentViewerWidget | Text (32 extensions), Markdown, PDF, CBZ (future) |
| ReaderService | EPUB, CBZ |
