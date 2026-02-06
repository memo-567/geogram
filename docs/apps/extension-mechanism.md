# Extension Mechanism

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Hook Points](#hook-points)
- [Extension Registration](#extension-registration)
- [Extension Loading Lifecycle](#extension-loading-lifecycle)
- [Data Isolation](#data-isolation)
- [Extension Communication](#extension-communication)
- [Complete Examples](#complete-examples)
- [Validation Rules](#validation-rules)
- [Security Considerations](#security-considerations)
- [Change Log](#change-log)

## Overview

Extensions are JavaScript packages that hook into existing core Geogram apps to add functionality without modifying the core app code. An extension declares in its [manifest](manifest-schema.md) which core apps it extends and what hook points it uses.

Extensions can:
- Add new tabs to core app screens
- Add settings panels
- Register new data types
- Add action menu items
- Inject widgets into designated areas

Extensions cannot:
- Replace or remove core app functionality
- Modify core app data directly (writes go to a namespaced subfolder)
- Access core apps not listed in their manifest
- Run without user consent

## Hook Points

Hook points are named locations in core apps where extensions can inject UI or behavior. Each hook type has a specific purpose and rendering context.

### Hook Types

#### `tab` — Tab Page

Adds a new tab to a core app's tab bar.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"tab"` |
| `id` | string | Yes | Unique hook ID |
| `label` | string | Yes | Tab label text |
| `icon` | string | No | Material icon name |
| `entry_point` | string | Yes | JS file path |
| `function` | string | Yes | Exported function returning a widget tree |
| `position` | string | No | `"start"`, `"end"` (default), or `"after:<tab-id>"` |

**Function signature**:
```javascript
export function renderSatelliteTab(context) {
  // context.app — host app name
  // context.data — host app's current data snapshot (if host_read permission)
  return {
    type: "Column",
    children: [
      { type: "Text", text: "Satellite Passes" },
      // ... widget tree
    ]
  };
}
```

#### `settings` — Settings Panel

Adds a section to the core app's settings page.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"settings"` |
| `id` | string | Yes | Unique hook ID |
| `label` | string | Yes | Settings section label |
| `icon` | string | No | Material icon name |
| `entry_point` | string | Yes | JS file path |
| `function` | string | Yes | Exported function returning a widget tree |

**Function signature**:
```javascript
export function renderSettings(context) {
  return {
    type: "Column",
    children: [
      {
        type: "Switch",
        id: "auto-track",
        label: "Auto-track satellites",
        value: true,
        onChanged: "onAutoTrackChanged"
      }
    ]
  };
}
```

#### `data_type` — Custom Data Type

Registers a new data type that the core app can store and display.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"data_type"` |
| `id` | string | Yes | Unique data type identifier |
| `label` | string | Yes | Display label for this data type |
| `icon` | string | No | Material icon name |
| `entry_point` | string | Yes | JS file path |
| `function` | string | Yes | Exported function for data handling |
| `schema` | object | No | JSON schema for the data type (for validation) |

**Function signature**:
```javascript
export function handleSatelliteData(context) {
  return {
    // How to render an item of this type
    renderItem: function(item) {
      return {
        type: "ListTile",
        title: item.satellite_name,
        subtitle: `Pass at ${item.time}`,
        leading: { type: "Icon", icon: "satellite_alt" }
      };
    },
    // How to create a new item
    renderEditor: function(existing) {
      return { type: "Column", children: [...] };
    }
  };
}
```

#### `action` — Action Menu Item

Adds an item to the core app's action menu (overflow menu or floating action button menu).

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"action"` |
| `id` | string | Yes | Unique action ID |
| `label` | string | Yes | Action menu label |
| `icon` | string | No | Material icon name |
| `entry_point` | string | Yes | JS file path |
| `function` | string | Yes | Exported function called when action is triggered |
| `context` | string | No | Where the action appears: `"global"` (default), `"item"`, `"selection"` |

**Function signature**:
```javascript
export function predictNextPass(context) {
  // context.selectedItems — if context is "item" or "selection"
  // Returns void — use geogram.ui methods for output
  const passes = calculatePasses(context.data);
  geogram.ui.showMessage(`Next pass: ${passes[0].time}`, "info");
}
```

#### `widget` — Injected Widget

Injects a widget into a designated slot in the core app's UI.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `type` | string | Yes | `"widget"` |
| `id` | string | Yes | Unique widget ID |
| `label` | string | Yes | Widget label (shown in settings) |
| `slot` | string | Yes | Target slot in the host app (e.g., `"header"`, `"footer"`, `"sidebar"`, `"detail"`) |
| `entry_point` | string | Yes | JS file path |
| `function` | string | Yes | Exported function returning a widget tree |

**Function signature**:
```javascript
export function renderSatelliteWidget(context) {
  return {
    type: "Card",
    child: {
      type: "Column",
      children: [
        { type: "Text", text: "ISS Overhead", style: { fontWeight: "bold" } },
        { type: "Text", text: "Next pass: 14:32 UTC" }
      ]
    }
  };
}
```

### Available Slots by Core App

| Core App | Available Slots |
|----------|----------------|
| `tracker` | `header`, `footer`, `detail`, `map-overlay` |
| `chat` | `header`, `footer`, `message-extra` |
| `wallet` | `header`, `footer`, `transaction-detail` |
| `contacts` | `header`, `detail` |
| `reader` | `header`, `footer`, `sidebar` |
| `events` | `header`, `detail` |
| (others) | `header`, `footer` |

## Extension Registration

When an extension is installed, the installer creates registration files that link the extension to its target core apps.

### Registration File Structure

For each `extends[].app` entry in the manifest, a registration file is created at:

```
extensions/<target_app>/<extension-folder-name>.json
```

### Registration File Schema

```json
{
  "extension_id": "com.example.tracker-satellite",
  "folder_name": "tracker-satellite",
  "name": "Tracker Satellite View",
  "version": "0.5.0",
  "enabled": true,
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
  ],
  "registered_at": "2026-02-03T14:30:00Z"
}
```

### Registration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `extension_id` | string | Yes | Package ID from manifest |
| `folder_name` | string | Yes | Extension's folder name under `installed/` |
| `name` | string | Yes | Display name |
| `version` | string | Yes | Installed version |
| `enabled` | boolean | Yes | Whether this extension is active for this app |
| `hooks` | array | Yes | Hooks registered for this specific app (subset of manifest hooks) |
| `registered_at` | ISO 8601 | Yes | When the extension was registered |

### Directory Layout Example

```
extensions/
├── tracker/
│   ├── tracker-satellite.json      # Satellite view extension
│   └── tracker-ham-grid.json       # Ham radio grid extension
├── chat/
│   └── chat-translator.json        # Auto-translate extension
└── wallet/
    └── wallet-budget.json          # Budget tracking extension
```

## Extension Loading Lifecycle

### App Startup (Core App Opens)

```
1. Core app initializes its own UI
   ↓
2. Core app queries extensions/ directory for registered extensions
   ↓
3. For each enabled registration file:
   a. Load the extension's JS entry point
   b. Initialize the JS runtime context
   c. For each hook:
      - "tab": Add tab to tab bar, defer render until tab selected
      - "settings": Register settings section
      - "data_type": Register type handler
      - "action": Add to action menu
      - "widget": Render widget in slot
   ↓
4. Core app renders with extensions integrated
```

### Tab Selection

```
1. User taps extension tab
   ↓
2. Host calls the registered render function
   ↓
3. Function returns JSON widget tree
   ↓
4. Host renders the widget tree as native Flutter widgets
   ↓
5. User interactions trigger event handlers in JS
```

### Extension Update

```
1. Installer detects new version available
   ↓
2. Download and validate new version
   ↓
3. Disable extension (unload from running apps)
   ↓
4. Replace files in installed/<folder_name>/
   ↓
5. Update registration files in extensions/<app>/
   ↓
6. Re-enable extension (reload in running apps)
```

### App Shutdown

```
1. Core app is closing
   ↓
2. For each loaded extension:
   a. Call onUnmount() if exported
   b. Clean up event subscriptions
   c. Release JS runtime resources
```

## Data Isolation

Extensions and their host apps maintain strict data boundaries.

### Storage Boundaries

```
<callsign>/
├── tracker/                         # Host app's data (core app owns this)
│   ├── metadata.json
│   ├── tracks/
│   │   └── 2026-02-06.json
│   └── extensions/                  # Extension data WITHIN host app
│       └── tracker-satellite/       # Namespaced by extension folder
│           ├── passes.json
│           └── tle-cache.json
├── installed/
│   └── tracker-satellite/           # Extension's OWN data
│       ├── manifest.json            # Read-only after install
│       ├── main.js                  # Read-only after install
│       └── data/                    # Extension's private storage
│           └── settings.json
```

### Access Rules

| Operation | API | Scope |
|-----------|-----|-------|
| Extension reads own data | `geogram.storage.read()` | `installed/<folder>/data/` |
| Extension writes own data | `geogram.storage.write()` | `installed/<folder>/data/` |
| Extension reads host data | `geogram.host.read()` | `<host_app>/` (read-only) |
| Extension writes to host | `geogram.host.write()` | `<host_app>/extensions/<folder>/` only |
| Host app reads extension data | Core Dart code | `extensions/<folder>/` within its own directory |

### Isolation Guarantees

1. **No cross-extension access**: Extension A cannot read Extension B's data
2. **No unauthorized host access**: Extensions can only access apps listed in `extends`
3. **Write containment**: Extension writes to host apps go to `extensions/<name>/` subfolder
4. **Read-only package files**: After installation, `manifest.json`, `*.js`, and `assets/` are read-only
5. **Uninstall cleanup**: Removing an extension deletes both `installed/<folder>/` and all `extensions/*/<folder>.json` entries, plus `<host>/extensions/<folder>/` data

## Extension Communication

### Extension to Host

Extensions communicate with host apps through:

1. **Hook functions**: Render content in designated areas
2. **`geogram.host` API**: Read/write data
3. **Events**: Listen to host app events

### Host to Extension

Core apps communicate with extensions through:

1. **Calling render functions**: Request widget trees for tabs, settings, etc.
2. **Context objects**: Pass current app state to render functions
3. **Events**: Emit events that extensions can subscribe to

### Extension to Extension

Extensions do not communicate directly with each other. If coordination is needed:

1. Use the `geogram.events` system with scoped event names
2. Write data to a shared location via `geogram.host.write()` (both extensions must extend the same host app)

## Complete Examples

### Multi-Hook Extension

An extension that adds both a tab and a settings panel to the tracker app:

**Manifest** (`extends` section):
```json
{
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
          "type": "settings",
          "id": "satellite-settings",
          "label": "Satellite Settings",
          "icon": "settings",
          "entry_point": "main.js",
          "function": "renderSatelliteSettings"
        },
        {
          "type": "action",
          "id": "predict-pass",
          "label": "Predict Next Pass",
          "icon": "schedule",
          "entry_point": "main.js",
          "function": "predictNextPass",
          "context": "global"
        }
      ]
    }
  ]
}
```

### Multi-App Extension

An extension that hooks into both tracker and contacts:

```json
{
  "extends": [
    {
      "app": "tracker",
      "hooks": [
        {
          "type": "widget",
          "id": "grid-locator",
          "label": "Grid Locator",
          "slot": "detail",
          "entry_point": "main.js",
          "function": "renderGridLocator"
        }
      ]
    },
    {
      "app": "contacts",
      "hooks": [
        {
          "type": "widget",
          "id": "contact-grid",
          "label": "Grid Square",
          "slot": "detail",
          "entry_point": "main.js",
          "function": "renderContactGrid"
        }
      ]
    }
  ]
}
```

## Validation Rules

### Hook Validation

1. Hook `type` must be one of: `"tab"`, `"settings"`, `"data_type"`, `"action"`, `"widget"`
2. Hook `id` must be unique within the extension
3. Hook `entry_point` must reference an existing JS file in the package
4. Hook `function` must be a valid JavaScript identifier
5. For `widget` hooks, `slot` must be a valid slot for the target app
6. For `action` hooks, `context` must be `"global"`, `"item"`, or `"selection"`
7. `extends[].app` must be a valid core app type from `knownAppTypesConst`

### Registration Validation

1. Registration file must be valid JSON matching the registration schema
2. `folder_name` must match an installed package
3. `hooks` must be a subset of hooks declared in the manifest for that app

### Runtime Validation

1. Render functions must return valid JSON widget trees
2. Event handler functions must be callable
3. Context objects passed to render functions are read-only

## Security Considerations

- Extensions run in the same JS sandbox as apps — no direct native access
- Host data access requires explicit `host_read`/`host_write` permissions granted at install time
- Write access to host apps is confined to `extensions/<folder>/` subdirectory
- Extensions cannot impersonate core app UI or intercept user credentials
- Malicious extensions can be disabled or uninstalled at any time
- Core app authors can define which slots and events are available to extensions
- See [security-model.md](security-model.md) for the complete security model

## Change Log

### Version 1.0 (2026-02-06)

- Initial extension mechanism specification
- Five hook types: tab, settings, data_type, action, widget
- Extension registration and loading lifecycle
- Data isolation model with namespaced writes
- Available slots per core app
- Multi-hook and multi-app extension examples
