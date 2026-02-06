# Manifest Schema

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [App Manifest](#app-manifest)
- [Extension Manifest](#extension-manifest)
- [Shared Fields](#shared-fields)
- [Entry Points](#entry-points)
- [Folder Name Validation](#folder-name-validation)
- [Reserved Folder Names](#reserved-folder-names)
- [Complete Examples](#complete-examples)
- [Validation Rules](#validation-rules)
- [Change Log](#change-log)

## Overview

Every JavaScript package (app or extension) distributed for Geogram must include a `manifest.json` file at the package root. This file declares metadata, permissions, entry points, platform support, and — for extensions — which core apps it extends and how.

The manifest is read by the installer during discovery, validation, and installation. It is also read at runtime to determine which entry points to load and what permissions to enforce.

## App Manifest

An app manifest describes a standalone JavaScript package that appears as a new item in the Geogram app list.

### App Manifest Schema

```json
{
  "kind": "app",
  "id": "com.example.my-weather",
  "name": "My Weather",
  "version": "1.2.0",
  "folder_name": "my-weather",
  "description": "Real-time weather dashboard with forecasts and alerts",
  "repository": "https://github.com/example/my-weather.git",
  "entry_points": {
    "gui": "main.js",
    "api": "api.js",
    "cli": "cli.js"
  },
  "platforms": ["desktop", "mobile", "web"],
  "permissions": ["storage", "network"],
  "min_geogram_version": "2.0.0",
  "icon": "assets/icon.png",
  "author": {
    "name": "Weather Dev",
    "npub": "npub1abc123...",
    "url": "https://example.com"
  },
  "license": "MIT",
  "translations": {
    "pt": {
      "name": "Meu Clima",
      "description": "Painel meteorologico em tempo real com previsoes e alertas"
    }
  }
}
```

### App-Specific Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | Yes | Must be `"app"` |
| `icon` | string | No | Path to app icon relative to package root (PNG, 256x256 recommended) |

## Extension Manifest

An extension manifest describes a package that hooks into one or more existing core apps. Extensions do not appear as standalone items in the app list.

### Extension Manifest Schema

```json
{
  "kind": "extension",
  "id": "com.example.tracker-satellite",
  "name": "Tracker Satellite View",
  "version": "0.5.0",
  "folder_name": "tracker-satellite",
  "description": "Adds satellite pass prediction and sky view to the Tracker app",
  "repository": "https://github.com/example/tracker-satellite.git",
  "entry_points": {
    "gui": "main.js"
  },
  "platforms": ["desktop", "mobile"],
  "permissions": ["storage", "host_read", "network"],
  "min_geogram_version": "2.0.0",
  "icon": "assets/icon.png",
  "author": {
    "name": "Satellite Dev",
    "npub": "npub1xyz789...",
    "url": "https://example.com"
  },
  "license": "MIT",
  "extends": [
    {
      "app": "tracker",
      "hooks": [
        {
          "type": "tab",
          "id": "satellite-tab",
          "label": "Satellites",
          "icon": "satellite_alt",
          "entry_point": "main.js",
          "function": "renderSatelliteTab"
        },
        {
          "type": "data_type",
          "id": "satellite-pass",
          "label": "Satellite Pass",
          "entry_point": "main.js",
          "function": "handleSatelliteData"
        }
      ]
    }
  ]
}
```

### Extension-Specific Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | Yes | Must be `"extension"` |
| `extends` | array | Yes | List of core apps this extension hooks into |
| `extends[].app` | string | Yes | Core app folder name (e.g., `"tracker"`, `"chat"`) |
| `extends[].hooks` | array | Yes | Hook definitions for this target app |
| `extends[].hooks[].type` | string | Yes | Hook type: `"tab"`, `"settings"`, `"data_type"`, `"action"`, `"widget"` |
| `extends[].hooks[].id` | string | Yes | Unique hook identifier within this extension |
| `extends[].hooks[].label` | string | Yes | Display label for the hook |
| `extends[].hooks[].icon` | string | No | Material icon name (e.g., `"satellite_alt"`) |
| `extends[].hooks[].entry_point` | string | Yes | JS file containing the hook handler |
| `extends[].hooks[].function` | string | Yes | Exported function name to call |

## Shared Fields

These fields are common to both app and extension manifests.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | Yes | Package type: `"app"` or `"extension"` |
| `id` | string | Yes | Globally unique identifier in reverse domain notation (e.g., `"com.example.my-app"`) |
| `name` | string | Yes | Human-readable display name (max 64 characters) |
| `version` | string | Yes | Semantic version (e.g., `"1.2.0"`) following [semver](https://semver.org/) |
| `folder_name` | string | Yes | Directory name used under `installed/`. Must pass [folder name validation](#folder-name-validation) |
| `description` | string | Yes | Short description (max 256 characters) |
| `repository` | string | Yes | Git repository URL for the package source |
| `entry_points` | object | Yes | Map of entry point types to JS file paths |
| `platforms` | array | Yes | Supported platforms: `"desktop"`, `"mobile"`, `"web"`, `"esp32"` |
| `permissions` | array | Yes | Requested permissions (can be empty `[]`). See [security-model.md](security-model.md) |
| `min_geogram_version` | string | No | Minimum required Geogram version (semver) |
| `icon` | string | No | Path to icon file relative to package root |
| `author` | object | No | Author information |
| `author.name` | string | No | Author display name |
| `author.npub` | string | No | Author's NOSTR public key (npub-encoded). Used for code signing verification |
| `author.url` | string | No | Author website or profile URL |
| `license` | string | No | SPDX license identifier (e.g., `"MIT"`, `"GPL-3.0"`) |
| `translations` | object | No | Localized overrides keyed by ISO 639-1 language code |

### Translatable Fields

The following fields can be overridden in the `translations` object:

- `name`
- `description`
- Hook `label` fields (within `extends[].hooks[].label`)

## Entry Points

Entry points define the JavaScript files that the runtime loads for different contexts.

| Entry Point | Key | Description |
|-------------|-----|-------------|
| **GUI** | `gui` | Main graphical entry point. Loaded when the user opens the app or extension. Must export a `render()` function that returns a JSON widget tree. |
| **API** | `api` | Background/service entry point. Loaded for event handling, data processing, and background tasks. Must export an `init()` function. |
| **CLI** | `cli` | Command-line entry point. Loaded when invoked from the Geogram CLI or ESP32 console. Must export a `main(args)` function. |

### Entry Point Requirements

- At least one entry point must be specified
- Apps should have at least a `gui` entry point (unless CLI-only)
- Extensions must have a `gui` entry point if any hook type is `tab`, `settings`, or `widget`
- File paths are relative to the package root
- Files must have `.js` extension

### Entry Point Function Signatures

**GUI entry point** (`main.js`):
```javascript
// Must export render()
export function render() {
  return { type: "Column", children: [...] };
}

// Optional: called when app is opened
export function onMount(context) { }

// Optional: called when app is closed
export function onUnmount() { }
```

**API entry point** (`api.js`):
```javascript
// Must export init()
export function init(context) {
  geogram.events.on("tracker:location_updated", handleLocation);
}

// Optional: cleanup
export function dispose() { }
```

**CLI entry point** (`cli.js`):
```javascript
// Must export main()
export function main(args) {
  const command = args[0];
  // Handle CLI commands
}
```

## Folder Name Validation

### Rules

1. **Charset**: Lowercase ASCII letters (`a-z`), digits (`0-9`), and hyphens (`-`)
2. **Start**: Must begin with a letter
3. **Length**: 2 to 64 characters inclusive
4. **Pattern**: `^[a-z][a-z0-9-]{1,63}$`
5. **No collision**: Must not match any [reserved folder name](#reserved-folder-names)
6. **Unique**: Must not match any already-installed package's `folder_name`
7. **No trailing/leading hyphens**: Must not start or end with a hyphen (implied by rule 2 and good practice)
8. **No consecutive hyphens**: `my--app` is not allowed

### Validation Examples

| Folder Name | Valid | Reason |
|-------------|-------|--------|
| `my-weather` | Yes | Letters, hyphens, starts with letter |
| `ham-logbook` | Yes | Valid characters and length |
| `tracker-satellite` | Yes | Valid (not colliding — `tracker` is reserved but `tracker-satellite` is not) |
| `chat` | No | Reserved core app name |
| `WEATHER` | No | Uppercase not allowed |
| `3d-viewer` | No | Must start with a letter |
| `a` | No | Too short (minimum 2 characters) |
| `my_weather` | No | Underscores not allowed |

## Reserved Folder Names

The following names are reserved for core Geogram app types and system directories. This list is derived from `knownAppTypesConst` and `singleInstanceTypesConst` in `lib/util/app_constants.dart`:

### Core App Types (33 names)

```
alerts        backup        blog          chat          console
contacts      documents     email         events        files
flasher       forum         groups        inventory     log
market        music         news          photos        places
postcards     qr            reader        shared_folder station
stories       tracker       transfer      usenet        videos
wallet        work          www
```

### System Directory Names (2 names)

```
installed     extensions
```

### Validation Note

The collision check must be **case-insensitive**: `Chat`, `CHAT`, and `chat` all collide with the reserved name `chat`.

## Complete Examples

### App Manifest

See [examples/example-app-manifest.json](examples/example-app-manifest.json) for a complete standalone app manifest.

### Extension Manifest

See [examples/example-extension-manifest.json](examples/example-extension-manifest.json) for a complete extension manifest that adds features to the tracker app.

## Validation Rules

### Schema Validation

1. `manifest.json` must be valid JSON
2. `kind` must be `"app"` or `"extension"`
3. `id` must match pattern `^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*(\.[a-z][a-z0-9-]*)$` (reverse domain)
4. `version` must be valid semver (`major.minor.patch`)
5. `folder_name` must pass [folder name validation](#folder-name-validation)
6. `entry_points` must have at least one key
7. `platforms` must be a non-empty array with values from `["desktop", "mobile", "web", "esp32"]`
8. `permissions` values must be from the defined set (see [security-model.md](security-model.md))
9. If `kind` is `"extension"`, `extends` must be present and non-empty
10. If `kind` is `"extension"`, each `extends[].app` must reference a valid core app type

### File Validation

1. All files referenced in `entry_points` must exist in the package
2. Files referenced in `extends[].hooks[].entry_point` must exist in the package
3. Icon file (if specified) must exist and be a valid PNG image
4. Total package size must not exceed 10 MB

### Cross-Reference Validation

1. `extends[].app` values must be valid core app types from `knownAppTypesConst`
2. Hook `type` values must be valid hook types for the target app
3. Hook `function` values must be exported from the referenced entry point JS file

## Change Log

### Version 1.0 (2026-02-06)

- Initial manifest schema specification
- App and extension manifest formats
- Folder name validation rules with reserved name list
- Entry point definitions (GUI, API, CLI)
- Extension hook declarations
- Translation support
