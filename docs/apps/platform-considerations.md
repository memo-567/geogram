# Platform Considerations

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Platform Support Matrix](#platform-support-matrix)
- [Desktop (Linux/Windows)](#desktop-linuxwindows)
- [Mobile (Android/iOS)](#mobile-androidios)
- [Web/Browser](#webbrowser)
- [ESP32](#esp32)
- [Cross-Platform Manifest Support](#cross-platform-manifest-support)
- [Validation Rules](#validation-rules)
- [Change Log](#change-log)

## Overview

The Geogram Installer must function across four distinct platform classes, each with different capabilities for JS execution, package installation, and available APIs. This document describes the platform-specific behavior, limitations, and implementation strategies.

## Platform Support Matrix

| Feature | Desktop | Mobile | Web | ESP32 |
|---------|---------|--------|-----|-------|
| **JS Engine** | QuickJS (flutter_js) | QuickJS (flutter_js) | Browser native JS | QuickJS-C |
| **Installation** | git clone | HTTP archive download | Bundled/fetch | Synced from host |
| **GUI entry point** | Yes | Yes | Yes | No |
| **API entry point** | Yes | Yes | Yes | Yes |
| **CLI entry point** | Yes | No | No | Yes |
| **geogram.storage** | Filesystem | Filesystem | IndexedDB | Flash storage |
| **geogram.network** | Full | Full | Browser fetch | WiFi HTTP |
| **geogram.ui** | Full widget tree | Full widget tree | Full widget tree | N/A |
| **geogram.host** | Full | Full | Full | Limited |
| **Max package size** | 10 MB | 10 MB | 5 MB | 512 KB |
| **Max storage per app** | 50 MB | 50 MB | 10 MB | 1 MB |

## Desktop (Linux/Windows)

### JS Engine

- **Engine**: QuickJS via `flutter_js` package
- **Context**: Each app/extension gets an isolated QuickJS context
- **Performance**: Near-native JS execution; suitable for complex computations
- **ES version**: ES2020 (QuickJS supports most ES2020 features)

### Installation Method

Desktop uses **git clone** for package installation:

```
1. User provides repository URL
   ↓
2. Installer runs: git clone --depth 1 --branch <version_tag> <url> <temp_dir>
   ↓
3. Validate manifest.json from cloned directory
   ↓
4. Copy validated files to installed/<folder_name>/
   ↓
5. Clean up temp directory
```

**Advantages**:
- Full git history available for updates (`git pull`)
- Branch/tag-based version selection
- Efficient incremental updates

**Update process**:
```
1. git fetch --tags in package directory
   ↓
2. Compare current tag with latest tag
   ↓
3. If newer: git checkout <new_tag>
   ↓
4. Re-validate manifest
   ↓
5. Reload if enabled
```

### CLI Entry Point

Desktop supports the CLI entry point, invoked from the Geogram command-line:

```bash
geogram run <app-folder-name> [args...]
```

The CLI entry point uses QuickJS in headless mode (no Flutter UI). Only `geogram.storage`, `geogram.network`, `geogram.events`, and `geogram.app` are available — `geogram.ui` is replaced with a simple stdout/stdin interface.

### Desktop-Specific APIs

| API | Desktop Behavior |
|-----|-----------------|
| `geogram.storage` | Direct filesystem read/write |
| `geogram.network` | Dart `HttpClient` proxied through host |
| `geogram.ui` | Full Flutter widget rendering |

## Mobile (Android/iOS)

### JS Engine

- **Engine**: QuickJS via `flutter_js` package (same as desktop)
- **Context**: Isolated contexts per app/extension
- **Performance**: Good; QuickJS is efficient on ARM
- **ES version**: ES2020

### Installation Method

Mobile uses **HTTP archive download** since git binaries are not available:

```
1. User provides repository URL
   ↓
2. Installer converts git URL to archive URL:
   GitHub: https://github.com/<user>/<repo>/archive/refs/tags/<version>.zip
   GitLab: https://gitlab.com/<user>/<repo>/-/archive/<version>/<repo>-<version>.zip
   ↓
3. Download ZIP archive
   ↓
4. Extract to temp directory
   ↓
5. Validate manifest.json
   ↓
6. Copy validated files to installed/<folder_name>/
   ↓
7. Clean up temp files
```

**Update process**:
```
1. Fetch manifest.json from repository (raw URL)
   ↓
2. Compare version with installed version
   ↓
3. If newer: download new archive
   ↓
4. Replace files in installed/<folder_name>/
   ↓
5. Reload if enabled
```

### Mobile-Specific Considerations

| Consideration | Detail |
|---------------|--------|
| **Storage location** | App-specific directory (no root access needed) |
| **Background execution** | Limited by OS; API entry point runs in foreground service |
| **Permissions** | `geolocation` and `camera` require Android/iOS runtime permissions |
| **Memory** | Lower memory limits due to device constraints (16 MB → 8 MB heap) |
| **No CLI** | CLI entry point not available on mobile |

### Mobile-Specific APIs

| API | Mobile Behavior |
|-----|----------------|
| `geogram.storage` | App-sandboxed filesystem |
| `geogram.network` | Dart `HttpClient` proxied through host |
| `geogram.ui` | Full Flutter widget rendering |
| `geogram.geolocation` | Delegates to Flutter location plugin |
| `geogram.camera` | Delegates to Flutter camera plugin |

## Web/Browser

### JS Engine

- **Engine**: Browser's native JavaScript engine via `dart:js_interop`
- **Context**: Each app runs in a sandboxed iframe or Web Worker
- **Performance**: Excellent; V8/SpiderMonkey are highly optimized
- **ES version**: Full ES2023+ (whatever the browser supports)

### Key Difference: Native JS

On web, third-party JS code runs in the **browser's native JS engine**, not QuickJS. This means:

1. The `geogram.*` API is still the only interface (same sandbox contract)
2. The API bridge uses `dart:js_interop` instead of `flutter_js`
3. Performance is higher than QuickJS
4. Browser DevTools can debug the JS code

### Installation Method

Web uses **fetch** to download packages at runtime:

```
1. Installer fetches manifest.json from repository raw URL
   ↓
2. Validate manifest
   ↓
3. Fetch all entry point JS files and assets
   ↓
4. Store in browser's IndexedDB (via geogram.storage backend)
   ↓
5. Register in in-memory registry (persisted to IndexedDB)
```

### Web-Specific Considerations

| Consideration | Detail |
|---------------|--------|
| **Storage backend** | IndexedDB (no filesystem access) |
| **Storage limit** | Browser-dependent (~10 MB recommended max per app) |
| **Network** | Browser `fetch` API (CORS restrictions apply) |
| **No CLI** | CLI entry point not available on web |
| **No git** | Archives fetched via HTTP, not git clone |
| **Security** | Browser Same-Origin Policy adds additional isolation |
| **Offline** | Installed apps cached in IndexedDB; work offline after first install |

### Web-Specific APIs

| API | Web Behavior |
|-----|-------------|
| `geogram.storage` | IndexedDB via `dart:js_interop` bridge |
| `geogram.network` | Browser `fetch` (subject to CORS) |
| `geogram.ui` | Flutter web widget rendering |

## ESP32

### JS Engine

- **Engine**: QuickJS-C component compiled for ESP-IDF
- **Context**: Single JS context (memory-constrained)
- **Performance**: Limited; ESP32 has ~520 KB SRAM
- **ES version**: ES2020 (QuickJS subset)

### Installation Method

ESP32 cannot install packages directly. Apps are **synced from a host device** (desktop or mobile):

```
1. User installs app on desktop/mobile
   ↓
2. User selects "Sync to ESP32" option
   ↓
3. Installer extracts CLI entry point and minimal dependencies
   ↓
4. Transfers JS bundle to ESP32 via:
   - USB serial connection (flasher module)
   - WiFi/BLE direct connection
   - NOSTR relay (for remote devices)
   ↓
5. ESP32 stores JS bundle in flash/SPIFFS partition
   ↓
6. ESP32 runtime loads and executes CLI entry point
```

### ESP32-Specific Constraints

| Constraint | Limit | Description |
|------------|-------|-------------|
| **JS heap** | 256 KB | Maximum QuickJS heap (shared with firmware) |
| **Package size** | 512 KB | Maximum JS bundle size on flash |
| **Storage** | 1 MB | Maximum app data in SPIFFS/LittleFS |
| **Entry points** | CLI only | No GUI or full API entry points |
| **Network** | WiFi HTTP only | No HTTPS certificate validation (resource constraints) |
| **Concurrency** | 1 app | Only one JS app runs at a time |

### ESP32-Specific APIs

| API | ESP32 Behavior |
|-----|---------------|
| `geogram.storage` | SPIFFS/LittleFS read/write |
| `geogram.network` | ESP-IDF HTTP client (WiFi required) |
| `geogram.ui` | Not available (CLI mode) |
| `geogram.events` | Limited to system events |
| `geogram.app` | Available (read-only metadata) |

### ESP32 Console Integration

On ESP32, CLI apps integrate with the Geogram console:

```
geogram> app list
  my-weather v1.2.0 (CLI)
  ham-logbook v0.3.0 (CLI)

geogram> app run my-weather --city London
Temperature: 12°C, Humidity: 78%

geogram> app run ham-logbook --log "QSO with AB1CD on 40m"
Logged: 2026-02-06 14:32 UTC - AB1CD - 40m
```

## Cross-Platform Manifest Support

### Platform Field

The manifest's `platforms` array controls which platforms the app supports:

```json
{
  "platforms": ["desktop", "mobile", "web", "esp32"]
}
```

### Entry Point Availability

| Entry Point | desktop | mobile | web | esp32 |
|-------------|---------|--------|-----|-------|
| `gui` | Yes | Yes | Yes | No |
| `api` | Yes | Yes | Yes | Yes |
| `cli` | Yes | No | No | Yes |

### Platform-Conditional Code

Apps can check the current platform at runtime:

```javascript
if (geogram.app.platform === "esp32") {
  // Minimal CLI output
  console.log(formatCompact(data));
} else if (geogram.app.platform === "mobile") {
  // Mobile-optimized layout
  geogram.ui.render(mobileLayout(data));
} else {
  // Desktop layout with more detail
  geogram.ui.render(desktopLayout(data));
}
```

### Platform-Specific Manifest Overrides

The manifest can include platform-specific overrides:

```json
{
  "platforms": ["desktop", "mobile", "esp32"],
  "entry_points": {
    "gui": "main.js",
    "cli": "cli.js"
  },
  "platform_overrides": {
    "esp32": {
      "entry_points": {
        "cli": "cli-minimal.js"
      },
      "permissions": ["storage"]
    },
    "mobile": {
      "permissions": ["storage", "network", "geolocation"]
    }
  }
}
```

## Validation Rules

### Platform Validation

1. `platforms` array must contain at least one valid platform
2. Valid values: `"desktop"`, `"mobile"`, `"web"`, `"esp32"`
3. If `"esp32"` is listed, a `cli` entry point must exist
4. If only `"esp32"` is listed, `gui` entry point is optional
5. Platform overrides must only reference declared platforms

### Size Validation by Platform

1. Package size checked against the target platform's limit
2. ESP32 packages must be under 512 KB (JS files + assets)
3. Web packages should be under 5 MB for reasonable load times
4. Desktop/mobile packages must be under 10 MB

## Change Log

### Version 1.0 (2026-02-06)

- Initial platform considerations specification
- Four platform classes: desktop, mobile, web, ESP32
- Platform-specific JS engines, installation methods, and API availability
- ESP32 sync-from-host installation model
- Cross-platform manifest support with platform overrides
