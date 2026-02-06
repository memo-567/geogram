# Installer Format Specification

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Glossary](#glossary)
- [Architecture](#architecture)
- [File Organization](#file-organization)
- [Installer Storage](#installer-storage)
- [Core App Collision Rules](#core-app-collision-rules)
- [Installation Workflow](#installation-workflow)
- [App Lifecycle](#app-lifecycle)
- [Validation Rules](#validation-rules)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

The Installer is a standard Geogram module (like flasher, tracker, wallet) that manages discovering, downloading, validating, installing, and running third-party JavaScript packages. These packages are hosted in git repositories and executed within an embedded JS engine (QuickJS via `flutter_js`). JS apps describe their GUI as JSON widget trees that Flutter renders natively.

### Purpose

- Allow third-party developers to extend Geogram with custom apps and extensions
- Provide a safe, sandboxed environment for executing third-party JS code
- Enable a decentralized distribution model using git repositories and NOSTR for discovery
- Support all Geogram platforms: desktop, mobile, web, and ESP32

### Key Features

- **Git-based distribution**: Apps are hosted in git repositories; installation clones or downloads archives
- **Embedded JS engine**: QuickJS via `flutter_js` for desktop/mobile; native JS on web
- **JSON widget trees**: JS apps describe their UI as JSON; Flutter renders it natively
- **Permission model**: Fine-grained permissions requested at install time
- **Extension system**: Third-party code can extend existing core apps via hook points
- **NOSTR integration**: Author verification, app discovery, and code signing via NOSTR

## Glossary

| Term | Definition |
|------|-----------|
| **App** | A standalone JavaScript package with its own folder, manifest, entry points, and UI. Appears as a new item in the Geogram app list. |
| **Extension** | A JavaScript package that hooks into one or more existing core apps (e.g., tracker, chat) to add tabs, settings, data types, actions, or widgets. Does not appear as a standalone app. |
| **Core App** | A built-in Geogram app type defined in `knownAppTypesConst` (e.g., chat, tracker, wallet). These are implemented in Dart/Flutter and cannot be replaced by installed packages. |
| **Manifest** | A `manifest.json` file included in every JS package that declares metadata, permissions, entry points, and (for extensions) hook points. See [manifest-schema.md](manifest-schema.md). |
| **JS Engine** | The embedded JavaScript runtime (QuickJS) that executes third-party code in a sandboxed environment. |
| **Widget Tree** | A JSON structure describing a UI layout. The host Flutter app interprets this JSON and renders native Flutter widgets. See [js-runtime-api.md](js-runtime-api.md). |
| **Hook Point** | A named location in a core app where extensions can inject UI or behavior. See [extension-mechanism.md](extension-mechanism.md). |
| **Source** | A git repository URL or NOSTR relay used to discover available packages. |

## Architecture

```
+------------------------------------------------------------------+
|                        Geogram Flutter App                        |
|                                                                    |
|  +------------------+  +------------------+  +------------------+  |
|  |   Core Apps      |  |   Installer      |  |  Installed Apps  |  |
|  |  (Dart/Flutter)  |  |  (Dart/Flutter)  |  |  (JS packages)   |  |
|  |                  |  |                  |  |                  |  |
|  |  chat, tracker,  |  |  - Discovery     |  |  - my-weather    |  |
|  |  wallet, ...     |  |  - Download      |  |  - ham-logbook   |  |
|  |                  |  |  - Validate      |  |  - ...           |  |
|  +--------+---------+  |  - Install       |  +--------+---------+  |
|           |             |  - Update        |           |            |
|           |             |  - Remove        |           |            |
|           |             +--------+---------+           |            |
|           |                      |                     |            |
|  +--------v----------------------v---------------------v---------+  |
|  |                     JS Runtime (QuickJS)                      |  |
|  |  +------------------+  +------------------+  +--------------+  |
|  |  | geogram.storage  |  | geogram.ui       |  | geogram.net  |  |
|  |  | geogram.events   |  | geogram.app      |  | geogram.host |  |
|  |  +------------------+  +------------------+  +--------------+  |
|  +---------------------------------------------------------------+  |
+------------------------------------------------------------------+
```

## File Organization

### Profile Directory Structure

Installed apps and extensions live within the user's profile directory alongside core app data:

```
<devices_dir>/<callsign>/
├── chat/                          # Core app data
├── tracker/                       # Core app data
├── wallet/                        # Core app data
├── ...                            # Other core apps
├── installed/                     # All installed packages
│   ├── registry.json              # Master registry of installed packages
│   ├── sources.json               # Package source repositories
│   ├── my-weather/                # Installed app
│   │   ├── manifest.json          # App manifest
│   │   ├── main.js                # GUI entry point
│   │   ├── api.js                 # API entry point (optional)
│   │   ├── cli.js                 # CLI entry point (optional)
│   │   ├── assets/                # App assets (icons, images)
│   │   │   └── icon.png
│   │   └── data/                  # App runtime data (created by app)
│   │       └── settings.json
│   ├── ham-logbook/               # Another installed app
│   │   ├── manifest.json
│   │   ├── main.js
│   │   └── assets/
│   │       └── icon.png
│   └── tracker-satellite/         # Installed extension
│       ├── manifest.json          # Extension manifest (has "extends" field)
│       ├── main.js                # Extension entry point
│       └── assets/
│           └── icon.png
├── extensions/                    # Extension registrations (symlinks/refs)
│   ├── tracker/                   # Extensions registered for tracker
│   │   └── tracker-satellite.json # Reference to installed/tracker-satellite
│   └── chat/                      # Extensions registered for chat
│       └── chat-translator.json   # Reference to installed/chat-translator
└── extra/
    └── security.json
```

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `installed/` | Contains all installed packages (both apps and extensions) |
| `installed/<name>/` | A single installed package with its manifest, JS files, and assets |
| `installed/<name>/data/` | Runtime data written by the app via `geogram.storage` |
| `extensions/<app>/` | Registration files linking extensions to their target core apps |
| `extra/` | Profile-level metadata (existing Geogram pattern) |

## Installer Storage

### Registry File (`installed/registry.json`)

The registry tracks all installed packages:

```json
{
  "version": "1.0",
  "packages": [
    {
      "id": "com.example.my-weather",
      "folder_name": "my-weather",
      "kind": "app",
      "name": "My Weather",
      "version": "1.2.0",
      "installed_at": "2026-02-01T10:00:00Z",
      "updated_at": "2026-02-01T10:00:00Z",
      "source": "https://github.com/example/my-weather.git",
      "commit_hash": "abc123def456",
      "author_npub": "npub1abc...",
      "signature_verified": true,
      "permissions_granted": ["storage", "network"],
      "enabled": true
    },
    {
      "id": "com.example.tracker-satellite",
      "folder_name": "tracker-satellite",
      "kind": "extension",
      "name": "Tracker Satellite View",
      "version": "0.5.0",
      "installed_at": "2026-02-03T14:30:00Z",
      "updated_at": "2026-02-03T14:30:00Z",
      "source": "https://github.com/example/tracker-satellite.git",
      "commit_hash": "789ghi012jkl",
      "author_npub": "npub1xyz...",
      "signature_verified": true,
      "permissions_granted": ["storage", "host_read"],
      "enabled": true
    }
  ]
}
```

### Registry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | Registry format version |
| `packages` | array | Yes | List of installed packages |
| `packages[].id` | string | Yes | Unique package identifier (reverse domain) |
| `packages[].folder_name` | string | Yes | Folder name under `installed/` |
| `packages[].kind` | string | Yes | `"app"` or `"extension"` |
| `packages[].name` | string | Yes | Display name |
| `packages[].version` | string | Yes | Installed version (semver) |
| `packages[].installed_at` | ISO 8601 | Yes | First installation timestamp |
| `packages[].updated_at` | ISO 8601 | Yes | Last update timestamp |
| `packages[].source` | string | Yes | Git repository URL |
| `packages[].commit_hash` | string | Yes | Git commit hash of installed version |
| `packages[].author_npub` | string | No | Author's NOSTR public key |
| `packages[].signature_verified` | boolean | Yes | Whether code signature was verified |
| `packages[].permissions_granted` | array | Yes | Permissions the user approved |
| `packages[].enabled` | boolean | Yes | Whether the package is currently active |

### Sources File (`installed/sources.json`)

Lists repositories and relays used to discover packages:

```json
{
  "version": "1.0",
  "sources": [
    {
      "type": "git",
      "url": "https://github.com/geograms/geogram-apps.git",
      "name": "Official Geogram Apps",
      "added_at": "2026-01-01T00:00:00Z",
      "last_checked": "2026-02-06T12:00:00Z"
    },
    {
      "type": "nostr_relay",
      "url": "wss://relay.damus.io",
      "name": "Damus Relay",
      "filter_kind": 30078,
      "added_at": "2026-02-01T00:00:00Z",
      "last_checked": "2026-02-06T12:00:00Z"
    }
  ]
}
```

## Core App Collision Rules

Installed packages **must not** use folder names that collide with core Geogram app types. The following folder names are reserved (sourced from `knownAppTypesConst` and `singleInstanceTypesConst`):

```
www        blog       chat       email      forum      events
alerts     places     files      contacts   transfer   groups
news       postcards  market     station    documents  photos
inventory  wallet     log        backup     console    tracker
videos     reader     work       usenet     music      stories
qr         flasher    shared_folder
```

**Total reserved names**: 33

### Collision Validation

1. Before installation, the installer reads the package's `manifest.json` `folder_name` field
2. It checks the name against the reserved list (case-insensitive)
3. If a collision is detected, the installation is rejected with an error message
4. Folder names must also not collide with `installed/` or `extensions/` directory names
5. Additionally, folder names must not collide with other already-installed packages

### Folder Name Requirements

- Lowercase alphanumeric characters and hyphens only
- Must start with a letter
- Must be between 2 and 64 characters
- Must not match any reserved name
- Must be unique among installed packages
- Pattern: `^[a-z][a-z0-9-]{1,63}$`

## Installation Workflow

### From Git Repository

```
1. User provides repository URL
   ↓
2. Installer fetches manifest.json from repository
   ↓
3. Validate manifest (schema, folder name, permissions)
   ↓
4. Show user: app info, requested permissions, author
   ↓
5. User confirms installation
   ↓
6. Clone repository (desktop) or download archive (mobile)
   ↓
7. Verify code signature (if author_npub present)
   ↓
8. Copy package files to installed/<folder_name>/
   ↓
9. If extension: register in extensions/<target_app>/
   ↓
10. Update registry.json
   ↓
11. App/extension is ready to use
```

### From NOSTR Discovery

```
1. Installer queries NOSTR relays for app announcement events
   ↓
2. User browses available packages
   ↓
3. User selects a package → extracts git URL from event
   ↓
4. Continues from step 2 of git workflow above
```

## App Lifecycle

### States

```
+----------+     +-----------+     +---------+     +----------+
| Available| --> | Installing| --> | Enabled | --> | Updating |
|  (remote)|     |           |     |         |     |          |
+----------+     +-----+-----+     +----+----+     +----+-----+
                       |                |                |
                       v                v                v
                 +-----------+     +----------+     +---------+
                 |  Failed   |     | Disabled |     | Enabled |
                 |           |     |          |     | (new v) |
                 +-----------+     +-----+----+     +---------+
                                        |
                                        v
                                  +-----------+
                                  | Uninstalled|
                                  +-----------+
```

### Lifecycle Operations

| Operation | Description |
|-----------|-------------|
| **Install** | Download, validate, copy files, register, enable |
| **Enable** | Activate a disabled package (load into runtime) |
| **Disable** | Deactivate without removing files (unload from runtime) |
| **Update** | Fetch new version, validate, replace files, reload |
| **Uninstall** | Remove files, deregister extensions, update registry |

## Validation Rules

### Package Validation

- `manifest.json` must exist and be valid JSON
- Manifest must pass schema validation (see [manifest-schema.md](manifest-schema.md))
- `folder_name` must not collide with reserved names or existing packages
- At least one entry point file must exist (`main.js`, `api.js`, or `cli.js`)
- Entry point files referenced in manifest must exist in the package
- Total package size must not exceed 10 MB (configurable)

### Extension Validation

- `extends` field must reference valid core app types
- Hook points must be valid for the target app (see [extension-mechanism.md](extension-mechanism.md))
- Extension entry points must exist

### Runtime Validation

- JS code must not throw errors during initial load
- Required permissions must be granted before API calls
- Widget tree JSON must conform to the widget schema

## Security Considerations

For the complete security model, see [security-model.md](security-model.md).

### Summary

- All JS code runs in a sandboxed QuickJS environment with no direct filesystem or network access
- Apps can only access their own data folder via the `geogram.storage` API
- Network access requires explicit `network` permission
- Extensions accessing host app data require `host_read`/`host_write` permissions
- Code signing via NOSTR enables author verification
- Resource limits prevent runaway CPU and memory usage

## Related Documentation

- [Manifest Schema](manifest-schema.md) — JSON manifest format for apps and extensions
- [JS Runtime API](js-runtime-api.md) — Host API injected into the JS engine
- [Extension Mechanism](extension-mechanism.md) — How extensions hook into core apps
- [Security Model](security-model.md) — Sandboxing, permissions, and code signing
- [Platform Considerations](platform-considerations.md) — Platform-specific behavior
- [Examples](examples/) — Sample manifests and widget trees
- [Flasher Format Specification](../apps/flasher-format-specification.md) — Similar module pattern

## Change Log

### Version 1.0 (2026-02-06)

- Initial specification
- Package format with manifest-based metadata
- Git-based distribution model
- Installer registry and sources management
- Core app collision rules
- Installation workflow and app lifecycle
- Extension registration system
