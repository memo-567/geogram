# JS Runtime API

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [API Namespaces](#api-namespaces)
- [geogram.storage](#geogramstorage)
- [geogram.network](#geogramnetwork)
- [geogram.ui](#geogramui)
- [geogram.events](#geogramevents)
- [geogram.app](#geogramapp)
- [geogram.host](#geogramhost)
- [JSON Widget Tree Specification](#json-widget-tree-specification)
- [Error Handling](#error-handling)
- [Validation Rules](#validation-rules)
- [Security Considerations](#security-considerations)
- [Change Log](#change-log)

## Overview

The JS Runtime API is the set of host functions injected into the JavaScript engine for apps and extensions. These APIs are the **only** way JS code can interact with the Geogram platform — there is no direct access to the filesystem, network, or Flutter framework.

The API is exposed as a global `geogram` object with the following namespaces:

```javascript
geogram.storage   // Read/write to own app folder
geogram.network   // HTTP fetch (requires "network" permission)
geogram.ui        // JSON widget tree rendering, navigation, messages
geogram.events    // Subscribe to and emit events
geogram.app       // Metadata about the running app
geogram.host      // For extensions: access to the host app's data
```

### Availability by Permission

| Namespace | Required Permission | Always Available |
|-----------|-------------------|------------------|
| `geogram.storage` | `storage` | No |
| `geogram.network` | `network` | No |
| `geogram.ui` | — | Yes |
| `geogram.events` | — | Yes |
| `geogram.app` | — | Yes |
| `geogram.host` | `host_read` / `host_write` | No |

## API Namespaces

## geogram.storage

Read/write access to the app's own data folder (`installed/<folder_name>/data/`). Apps cannot access files outside their own data directory.

**Required permission**: `storage`

### Methods

#### `geogram.storage.read(path)`

Read a file from the app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Relative path within the app's data folder |

**Returns**: `Promise<string|null>` — File contents as string, or `null` if not found.

```javascript
const settings = await geogram.storage.read("settings.json");
if (settings) {
  const config = JSON.parse(settings);
}
```

#### `geogram.storage.write(path, content)`

Write a file to the app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Relative path within the app's data folder |
| `content` | string | Yes | File contents to write |

**Returns**: `Promise<boolean>` — `true` if successful.

```javascript
await geogram.storage.write("settings.json", JSON.stringify(config));
```

#### `geogram.storage.delete(path)`

Delete a file from the app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Relative path within the app's data folder |

**Returns**: `Promise<boolean>` — `true` if deleted, `false` if not found.

#### `geogram.storage.list(path)`

List files and directories in a folder within the app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | No | Relative path (defaults to root of data folder) |

**Returns**: `Promise<Array<{name: string, isDirectory: boolean, size: number}>>` — Directory listing.

#### `geogram.storage.exists(path)`

Check if a file or directory exists.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Relative path within the app's data folder |

**Returns**: `Promise<boolean>`

### Path Security

- All paths are resolved relative to `installed/<folder_name>/data/`
- Path traversal attempts (`../`, absolute paths) are rejected with an error
- Maximum file size: 5 MB per file
- Maximum total storage per app: 50 MB (configurable)

## geogram.network

HTTP client for making network requests. All requests go through the Geogram host, which enforces permission checks and rate limits.

**Required permission**: `network`

### Methods

#### `geogram.network.fetch(url, options)`

Make an HTTP request.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `url` | string | Yes | Request URL (must be HTTPS) |
| `options` | object | No | Request options |
| `options.method` | string | No | HTTP method (default: `"GET"`) |
| `options.headers` | object | No | Request headers |
| `options.body` | string | No | Request body |
| `options.timeout` | number | No | Timeout in milliseconds (default: 30000, max: 60000) |

**Returns**: `Promise<{status: number, headers: object, body: string}>`

```javascript
const response = await geogram.network.fetch("https://api.weather.com/current", {
  method: "GET",
  headers: { "Accept": "application/json" },
  timeout: 10000
});

if (response.status === 200) {
  const weather = JSON.parse(response.body);
}
```

### Network Restrictions

- Only HTTPS URLs are allowed (HTTP is rejected)
- Requests to localhost, private IP ranges, and link-local addresses are blocked
- Rate limit: 60 requests per minute per app
- Maximum response size: 2 MB
- Maximum request body size: 1 MB

## geogram.ui

UI rendering and interaction API. This namespace handles JSON widget tree rendering, navigation between screens, user messages, and input dialogs.

**Required permission**: None (always available)

### Methods

#### `geogram.ui.render(widgetTree)`

Render a JSON widget tree to the screen. Replaces the current app view.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `widgetTree` | object | Yes | JSON widget tree (see [JSON Widget Tree Specification](#json-widget-tree-specification)) |

**Returns**: `void`

```javascript
geogram.ui.render({
  type: "Column",
  children: [
    { type: "Text", text: "Hello World", style: { fontSize: 24, fontWeight: "bold" } },
    { type: "Button", text: "Click Me", onPressed: "handleClick" }
  ]
});
```

#### `geogram.ui.update(widgetId, properties)`

Update properties of a specific widget without re-rendering the entire tree.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `widgetId` | string | Yes | The `id` property of the widget to update |
| `properties` | object | Yes | Properties to update |

**Returns**: `void`

```javascript
geogram.ui.update("temperature-text", { text: "23°C" });
```

#### `geogram.ui.showMessage(message, type)`

Show a temporary message (snackbar/toast) to the user.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | string | Yes | Message text |
| `type` | string | No | `"info"` (default), `"success"`, `"warning"`, `"error"` |

**Returns**: `void`

#### `geogram.ui.showDialog(options)`

Show a dialog and wait for user response.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `options.title` | string | Yes | Dialog title |
| `options.message` | string | No | Dialog body text |
| `options.buttons` | array | Yes | Array of `{text: string, value: string}` |
| `options.input` | object | No | If present, shows a text input. `{hint: string, defaultValue: string}` |

**Returns**: `Promise<{button: string, input?: string}>` — The `value` of the pressed button, and input text if applicable.

```javascript
const result = await geogram.ui.showDialog({
  title: "Confirm Delete",
  message: "Are you sure you want to delete this entry?",
  buttons: [
    { text: "Cancel", value: "cancel" },
    { text: "Delete", value: "delete" }
  ]
});

if (result.button === "delete") {
  // proceed with deletion
}
```

#### `geogram.ui.navigate(route)`

Navigate to a different screen within the app.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `route` | string | Yes | Route name (app-defined) |

**Returns**: `void`

#### `geogram.ui.setTitle(title)`

Set the screen title in the app bar.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `title` | string | Yes | New title text |

**Returns**: `void`

## geogram.events

Event system for subscribing to and emitting events. Apps can listen to system events and communicate with extensions or other components.

**Required permission**: None (always available, but some events require specific permissions)

### Methods

#### `geogram.events.on(eventName, callback)`

Subscribe to an event.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `eventName` | string | Yes | Event name (e.g., `"app:resumed"`, `"tracker:location_updated"`) |
| `callback` | function | Yes | Handler function called with event data |

**Returns**: `string` — Subscription ID (used to unsubscribe).

```javascript
const subId = geogram.events.on("app:resumed", (data) => {
  refreshWeatherData();
});
```

#### `geogram.events.off(subscriptionId)`

Unsubscribe from an event.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `subscriptionId` | string | Yes | Subscription ID returned by `on()` |

**Returns**: `void`

#### `geogram.events.emit(eventName, data)`

Emit a custom event. Events are scoped to the app's own namespace.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `eventName` | string | Yes | Event name (automatically prefixed with app's folder name) |
| `data` | any | No | Event payload (must be JSON-serializable) |

**Returns**: `void`

```javascript
// Emitted as "my-weather:forecast_updated"
geogram.events.emit("forecast_updated", { temperature: 23, unit: "C" });
```

### System Events

| Event | Data | Description |
|-------|------|-------------|
| `app:mounted` | `{}` | App has been opened and rendered |
| `app:unmounted` | `{}` | App is being closed |
| `app:resumed` | `{}` | App returned to foreground |
| `app:paused` | `{}` | App moved to background |
| `system:connectivity_changed` | `{online: boolean}` | Network connectivity changed |

### Core App Events (require `host_read` permission)

| Event | Data | Description |
|-------|------|-------------|
| `tracker:location_updated` | `{lat, lon, alt, timestamp}` | New GPS position recorded |
| `chat:message_received` | `{channel, sender, text}` | New chat message |
| `contacts:updated` | `{npub, action}` | Contact list changed |

## geogram.app

Metadata about the currently running app or extension. Read-only.

**Required permission**: None (always available)

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `geogram.app.id` | string | Package ID from manifest (e.g., `"com.example.my-weather"`) |
| `geogram.app.name` | string | Package display name |
| `geogram.app.version` | string | Package version |
| `geogram.app.folderName` | string | Package folder name |
| `geogram.app.kind` | string | `"app"` or `"extension"` |
| `geogram.app.platform` | string | Current platform: `"desktop"`, `"mobile"`, `"web"`, `"esp32"` |
| `geogram.app.geogramVersion` | string | Host Geogram version |
| `geogram.app.locale` | string | Current user locale (e.g., `"en"`, `"pt"`) |

```javascript
if (geogram.app.platform === "mobile") {
  // Use mobile-optimized layout
}
```

## geogram.host

For extensions only: access to the host app's data. Allows reading and writing data in the core app's data folder.

**Required permission**: `host_read` for read operations, `host_write` for write operations

### Methods

#### `geogram.host.read(app, path)`

Read a file from a core app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app` | string | Yes | Core app folder name (must match an entry in `extends[].app`) |
| `path` | string | Yes | Relative path within the core app's folder |

**Returns**: `Promise<string|null>`

```javascript
// Extension extending tracker — read tracker data
const locations = await geogram.host.read("tracker", "locations.json");
```

#### `geogram.host.write(app, path, content)`

Write a file to a core app's data folder. The extension can only write to designated extension areas within the host app.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app` | string | Yes | Core app folder name (must match an entry in `extends[].app`) |
| `path` | string | Yes | Relative path (limited to `extensions/<extension-folder>/` within the host app) |
| `content` | string | Yes | File contents |

**Returns**: `Promise<boolean>`

```javascript
// Write to tracker/extensions/tracker-satellite/passes.json
await geogram.host.write("tracker", "extensions/tracker-satellite/passes.json", data);
```

#### `geogram.host.list(app, path)`

List files in a core app's data folder.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `app` | string | Yes | Core app folder name |
| `path` | string | No | Relative path (defaults to root) |

**Returns**: `Promise<Array<{name: string, isDirectory: boolean, size: number}>>`

### Host Access Restrictions

- Extensions can only access apps listed in their manifest's `extends[].app`
- Read access requires `host_read` permission
- Write access requires `host_write` permission
- Writes are restricted to `extensions/<extension-folder>/` within the host app
- Path traversal attempts are rejected

## JSON Widget Tree Specification

Apps and extensions describe their GUI as JSON widget trees. The Flutter host interprets this JSON and renders native widgets.

### Widget Tree Structure

Every widget is a JSON object with a `type` field and type-specific properties:

```json
{
  "type": "WidgetType",
  "id": "optional-unique-id",
  "key": "optional-key",
  ...properties
}
```

### Supported Widget Types

#### Layout Widgets

| Widget | Description | Key Properties |
|--------|-------------|----------------|
| `Column` | Vertical layout | `children`, `mainAxisAlignment`, `crossAxisAlignment`, `spacing` |
| `Row` | Horizontal layout | `children`, `mainAxisAlignment`, `crossAxisAlignment`, `spacing` |
| `Stack` | Overlapping layout | `children`, `alignment` |
| `Container` | Box with decoration | `child`, `padding`, `margin`, `color`, `borderRadius`, `width`, `height` |
| `Padding` | Padding wrapper | `child`, `padding` |
| `Center` | Center child | `child` |
| `Expanded` | Fill available space | `child`, `flex` |
| `SizedBox` | Fixed size box | `child`, `width`, `height` |
| `ScrollView` | Scrollable content | `children`, `direction` |
| `Wrap` | Flow layout | `children`, `spacing`, `runSpacing` |

#### Display Widgets

| Widget | Description | Key Properties |
|--------|-------------|----------------|
| `Text` | Text display | `text`, `style`, `maxLines`, `overflow` |
| `Icon` | Material icon | `icon`, `size`, `color` |
| `Image` | Image display | `src` (asset path or URL), `width`, `height`, `fit` |
| `Divider` | Horizontal line | `thickness`, `color` |
| `CircularProgress` | Loading spinner | `size`, `color` |
| `LinearProgress` | Progress bar | `value` (0.0-1.0), `color` |
| `Card` | Material card | `child`, `elevation`, `color` |
| `Chip` | Material chip | `label`, `avatar`, `onDeleted` |

#### Input Widgets

| Widget | Description | Key Properties |
|--------|-------------|----------------|
| `Button` | Raised button | `text`, `onPressed`, `color`, `disabled` |
| `TextButton` | Flat text button | `text`, `onPressed` |
| `IconButton` | Icon-only button | `icon`, `onPressed`, `tooltip` |
| `TextField` | Text input | `id`, `hint`, `value`, `onChanged`, `obscureText`, `maxLines` |
| `Checkbox` | Checkbox | `id`, `value`, `label`, `onChanged` |
| `Switch` | Toggle switch | `id`, `value`, `label`, `onChanged` |
| `Slider` | Range slider | `id`, `value`, `min`, `max`, `onChanged` |
| `DropdownButton` | Dropdown selector | `id`, `value`, `items`, `onChanged` |
| `RadioGroup` | Radio buttons | `id`, `value`, `options`, `onChanged` |

#### List Widgets

| Widget | Description | Key Properties |
|--------|-------------|----------------|
| `ListView` | Scrollable list | `children`, `itemCount`, `onItemBuild` |
| `ListTile` | Standard list item | `title`, `subtitle`, `leading`, `trailing`, `onTap` |
| `GridView` | Grid layout | `children`, `crossAxisCount`, `spacing` |

#### Navigation Widgets

| Widget | Description | Key Properties |
|--------|-------------|----------------|
| `TabBar` | Tab navigation | `tabs` (array of `{label, icon}`), `selectedIndex`, `onChanged` |
| `BottomNavBar` | Bottom navigation | `items` (array of `{label, icon}`), `selectedIndex`, `onChanged` |
| `AppBar` | Top app bar | `title`, `actions` (array of icon buttons) |

### Widget Properties

#### Common Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | string | Unique widget identifier (for `geogram.ui.update()`) |
| `key` | string | Flutter key for efficient reconciliation |
| `visible` | boolean | Whether the widget is visible (default: `true`) |

#### Text Style

```json
{
  "fontSize": 16,
  "fontWeight": "bold",
  "fontStyle": "italic",
  "color": "#FF5722",
  "letterSpacing": 1.2,
  "decoration": "underline"
}
```

**fontWeight values**: `"normal"`, `"bold"`, `"w100"` through `"w900"`

#### Padding/Margin

```json
{ "all": 16 }
{ "horizontal": 16, "vertical": 8 }
{ "left": 8, "top": 16, "right": 8, "bottom": 16 }
```

#### Alignment

**mainAxisAlignment**: `"start"`, `"end"`, `"center"`, `"spaceBetween"`, `"spaceAround"`, `"spaceEvenly"`

**crossAxisAlignment**: `"start"`, `"end"`, `"center"`, `"stretch"`

### Event Handlers

Event handlers are string references to JavaScript function names. When a user interacts with a widget, the runtime calls the named function with an event object.

```json
{
  "type": "Button",
  "text": "Submit",
  "onPressed": "handleSubmit"
}
```

```javascript
// In the app's JS code:
function handleSubmit(event) {
  // event.widgetId — the widget's id
  // event.type — "pressed"
}

function handleTextChange(event) {
  // event.widgetId — the widget's id
  // event.type — "changed"
  // event.value — current text value
}
```

#### Event Handler Parameters

| Event | Properties |
|-------|------------|
| `onPressed` | `{widgetId, type: "pressed"}` |
| `onChanged` | `{widgetId, type: "changed", value: any}` |
| `onTap` | `{widgetId, type: "tap"}` |
| `onLongPress` | `{widgetId, type: "longPress"}` |
| `onDeleted` | `{widgetId, type: "deleted"}` |

### Complete Widget Tree Example

See [examples/example-widget-tree.json](examples/example-widget-tree.json) for a full example.

## Error Handling

### API Errors

All async API methods can throw errors. Errors are JavaScript `Error` objects with a `code` property:

```javascript
try {
  await geogram.storage.read("config.json");
} catch (error) {
  // error.message — human-readable description
  // error.code — machine-readable error code
}
```

### Error Codes

| Code | Description |
|------|-------------|
| `PERMISSION_DENIED` | Missing required permission |
| `NOT_FOUND` | File or resource not found |
| `STORAGE_QUOTA_EXCEEDED` | Storage limit reached |
| `NETWORK_ERROR` | Network request failed |
| `NETWORK_TIMEOUT` | Request timed out |
| `RATE_LIMITED` | Too many requests |
| `INVALID_PATH` | Path traversal or invalid path |
| `INVALID_ARGUMENT` | Invalid function argument |
| `HOST_ACCESS_DENIED` | Extension tried to access an app not in its `extends` list |
| `WIDGET_ERROR` | Invalid widget tree JSON |

## Validation Rules

### Widget Tree Validation

1. Root widget must be a valid layout widget
2. All `type` values must be from the supported widget types list
3. `children` must be arrays of valid widget objects
4. `child` must be a single valid widget object
5. Event handler names must be valid JavaScript identifiers
6. `id` values must be unique within the widget tree
7. Colors must be valid hex strings (`#RRGGBB` or `#AARRGGBB`)
8. Icon names must be valid Material icon identifiers

### API Call Validation

1. Permission checks happen before every API call
2. Path parameters are sanitized and validated
3. Network URLs are validated for HTTPS and non-private addresses
4. JSON payloads are validated for size limits

## Security Considerations

- All API calls go through the Flutter host — JS code never accesses native APIs directly
- Storage paths are jail-rooted to the app's data directory
- Network requests are proxied through the host for URL validation and rate limiting
- Event subscriptions to core app events require `host_read` permission
- Widget tree rendering is done by the host; JS code cannot inject arbitrary Flutter widgets
- See [security-model.md](security-model.md) for the complete security model

## Change Log

### Version 1.0 (2026-02-06)

- Initial JS Runtime API specification
- Six API namespaces: storage, network, ui, events, app, host
- JSON widget tree specification with 30+ widget types
- Event handler system
- Error codes and handling
