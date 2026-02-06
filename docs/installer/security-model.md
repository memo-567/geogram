# Security Model

**Version**: 1.0
**Last Updated**: 2026-02-06
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [JS Engine Sandbox](#js-engine-sandbox)
- [Permission Model](#permission-model)
- [NOSTR-Based Code Signing](#nostr-based-code-signing)
- [Install-Time Confirmation](#install-time-confirmation)
- [Resource Limits](#resource-limits)
- [Threat Model](#threat-model)
- [Validation Rules](#validation-rules)
- [Change Log](#change-log)

## Overview

The security model for the Geogram Installer protects users from malicious or buggy third-party JavaScript code. It operates on the principle of **least privilege**: packages get no capabilities by default and must request each permission explicitly. Users review and approve permissions at install time.

### Security Layers

```
+------------------------------------------------------------------+
|  Layer 1: JS Engine Sandbox                                       |
|  - No direct filesystem, network, or native API access            |
|  - Code runs in isolated QuickJS context                          |
+------------------------------------------------------------------+
|  Layer 2: Permission Model                                        |
|  - Each API namespace gated by a named permission                 |
|  - Permissions granted at install time, revocable any time        |
+------------------------------------------------------------------+
|  Layer 3: Code Signing (NOSTR)                                    |
|  - Author identity verified via NOSTR keypair                     |
|  - Manifest signed with author's nsec                             |
|  - Signature verified against author's npub                       |
+------------------------------------------------------------------+
|  Layer 4: Resource Limits                                         |
|  - CPU time limits per execution cycle                            |
|  - Memory caps per JS context                                     |
|  - Storage quotas per app                                         |
|  - Network rate limits                                            |
+------------------------------------------------------------------+
```

## JS Engine Sandbox

### QuickJS Isolation

Third-party JS code runs inside QuickJS (via `flutter_js`), a lightweight JavaScript engine that provides:

- **No built-in I/O**: QuickJS has no `fs`, `net`, `child_process`, or similar modules
- **No browser APIs**: No `window`, `document`, `fetch`, `XMLHttpRequest`, `localStorage`
- **No eval of external code**: `import()` and dynamic `require()` are disabled
- **Separate contexts**: Each app/extension runs in its own JS context with no shared globals

### Injected APIs Only

The only way JS code interacts with the system is through the `geogram.*` API object injected by the Flutter host. See [js-runtime-api.md](js-runtime-api.md) for the complete API.

```
+------------------+          +------------------+
|  JS App Code     |          |  Flutter Host    |
|                  |          |                  |
|  geogram.storage |  ---->   |  StorageHandler  |
|  geogram.network |  ---->   |  NetworkHandler  |
|  geogram.ui      |  ---->   |  UIHandler       |
|  geogram.events  |  ---->   |  EventHandler    |
|  geogram.app     |  ---->   |  AppHandler      |
|  geogram.host    |  ---->   |  HostHandler     |
|                  |          |                  |
+------------------+          +------------------+
       JS side                     Dart side
    (sandboxed)               (permission checks)
```

### What JS Code Cannot Do

| Blocked Capability | Reason |
|-------------------|--------|
| Read arbitrary files | No filesystem API; `geogram.storage` is jail-rooted |
| Make arbitrary network requests | No `fetch`/`XMLHttpRequest`; `geogram.network` enforces HTTPS and blocks private IPs |
| Execute system commands | No `child_process` or similar |
| Access other apps' data | `geogram.storage` scoped to own folder; `geogram.host` requires permission and is scoped to declared apps |
| Modify the Flutter UI directly | UI described as JSON; host renders it |
| Load external JS code | Dynamic imports disabled |
| Access device sensors directly | Must go through permitted `geogram.*` APIs |

## Permission Model

### Permissions

| Permission | Description | Risk Level |
|------------|-------------|------------|
| `storage` | Read/write files in the app's own data folder | Low |
| `network` | Make HTTP requests to external URLs (HTTPS only) | Medium |
| `notifications` | Display system notifications | Low |
| `host_read` | Read data from core apps listed in `extends` | Medium |
| `host_write` | Write data to extension namespace in core apps | Medium |
| `geolocation` | Access device GPS location | High |
| `contacts` | Read the user's contacts list | High |
| `camera` | Access device camera | High |

### Permission Lifecycle

```
1. Package declares permissions in manifest.json
   ↓
2. Installer shows permissions to user before install
   ↓
3. User reviews and approves/denies
   ↓
4. Granted permissions stored in registry.json
   ↓
5. At runtime, each API call checks granted permissions
   ↓
6. If permission not granted → PERMISSION_DENIED error
   ↓
7. User can revoke permissions at any time via installer settings
```

### Permission Combinations

Some operations require multiple permissions:

| Operation | Required Permissions |
|-----------|---------------------|
| Extension reads host app data | `host_read` |
| Extension writes to host app namespace | `host_write` |
| App fetches data and caches locally | `storage` + `network` |
| Extension reads host data and fetches enrichment | `host_read` + `network` |
| App shows location on map | `geolocation` + `network` (for map tiles) |

### Permission Revocation

Users can revoke permissions at any time through the Installer settings:

1. Open Installer app
2. Select installed package
3. Toggle individual permissions on/off
4. Changes take effect immediately (no restart needed)
5. The app/extension will receive `PERMISSION_DENIED` errors for revoked APIs

## NOSTR-Based Code Signing

### Purpose

Code signing allows users to verify that a package was published by a known author and has not been tampered with. It uses NOSTR keypairs, which Geogram users already possess.

### Signing Process (Author)

```
1. Author writes their package (manifest.json, *.js, assets)
   ↓
2. Author generates a content hash:
   - Sort all package files alphabetically
   - Concatenate SHA256 hashes of each file
   - SHA256 the concatenated result → package_hash
   ↓
3. Author signs the package_hash with their nsec (NOSTR private key)
   ↓
4. Author adds signature to manifest.json:
   {
     "author": {
       "npub": "npub1abc...",
       "name": "Author Name"
     },
     "signature": {
       "hash": "<package_hash>",
       "sig": "<schnorr_signature>",
       "signed_at": "2026-02-01T10:00:00Z",
       "files": ["manifest.json", "main.js", "api.js", "assets/icon.png"]
     }
   }
   ↓
5. Author publishes the repository
```

### Verification Process (Installer)

```
1. Installer downloads the package
   ↓
2. Read author.npub from manifest.json
   ↓
3. Recalculate package_hash from all files listed in signature.files
   ↓
4. Verify the Schnorr signature against:
   - The recalculated hash
   - The author's npub (public key)
   ↓
5. If valid: mark signature_verified = true in registry
   If invalid: warn user, allow install at user's discretion
   If no signature: mark as unsigned, warn user
```

### Signature States

| State | Display | User Action |
|-------|---------|-------------|
| **Verified** | Green checkmark + author name | Install normally |
| **Invalid** | Red warning | Strong warning; user must explicitly accept risk |
| **Unsigned** | Yellow warning | Mild warning; user can proceed |
| **Author unknown** | Orange info | Signature valid but npub not in user's contacts |

### NOSTR Author Discovery

The installer can discover packages via NOSTR relays:

- Authors publish NIP-78 events (kind 30078) with app metadata
- Events include the git repository URL, version, and description
- The event is signed with the author's NOSTR key, providing authenticity
- Users can browse available packages by querying relays

## Install-Time Confirmation

### Confirmation Dialog

Before installing any package, the user sees a confirmation dialog:

```
+-----------------------------------------------+
|  Install "My Weather" v1.2.0?                  |
|                                                 |
|  Author: Weather Dev (npub1abc...)              |
|  Signature: ✓ Verified                          |
|  Repository: github.com/example/my-weather      |
|                                                 |
|  Requested Permissions:                         |
|  ☑ Storage - Read/write app data               |
|  ☑ Network - Make HTTP requests                |
|                                                 |
|  [Cancel]                  [Install]            |
+-----------------------------------------------+
```

### Extension Confirmation

Extensions show additional information about host app access:

```
+-----------------------------------------------+
|  Install "Tracker Satellite" v0.5.0?           |
|                                                 |
|  Author: Satellite Dev (npub1xyz...)            |
|  Signature: ✓ Verified                          |
|  Type: Extension for Tracker                    |
|                                                 |
|  Requested Permissions:                         |
|  ☑ Storage - Read/write extension data          |
|  ☑ Host Read - Read Tracker app data            |
|  ☑ Network - Make HTTP requests                 |
|                                                 |
|  This extension will:                           |
|  • Add "Satellites" tab to Tracker              |
|  • Add "Satellite Pass" data type               |
|                                                 |
|  [Cancel]                  [Install]            |
+-----------------------------------------------+
```

### Unsigned Package Warning

```
+-----------------------------------------------+
|  ⚠ Unsigned Package                            |
|                                                 |
|  "My Custom Tool" has no code signature.        |
|  The author's identity cannot be verified.      |
|                                                 |
|  Only install packages from sources you trust.  |
|                                                 |
|  [Cancel]            [Install Anyway]           |
+-----------------------------------------------+
```

## Resource Limits

### CPU Limits

| Limit | Value | Description |
|-------|-------|-------------|
| Render timeout | 500 ms | Maximum time for a render function to return a widget tree |
| Event handler timeout | 1000 ms | Maximum time for an event handler to complete |
| API call timeout | 5000 ms | Maximum time for a single API call (excluding network) |
| Total CPU per minute | 10 seconds | Cumulative JS execution time per minute |

If a limit is exceeded:
1. The JS execution is interrupted
2. An error is logged
3. The user is notified if the app becomes unresponsive
4. After 3 consecutive timeouts, the app is automatically disabled

### Memory Limits

| Limit | Value | Description |
|-------|-------|-------------|
| JS heap per app | 16 MB | Maximum memory for the JS context |
| JS heap per extension | 8 MB | Maximum memory for an extension context |
| Widget tree depth | 50 levels | Maximum nesting depth |
| Widget tree size | 10000 nodes | Maximum total widgets in a tree |

### Storage Limits

| Limit | Value | Description |
|-------|-------|-------------|
| Per-app data folder | 50 MB | Maximum total size of `data/` folder |
| Per-file size | 5 MB | Maximum size of a single file |
| Extension host data | 10 MB | Maximum data in `extensions/<name>/` per host app |
| Total installed packages | 500 MB | Maximum total size of all `installed/` packages |

### Network Limits

| Limit | Value | Description |
|-------|-------|-------------|
| Requests per minute | 60 | Rate limit per app |
| Response size | 2 MB | Maximum response body |
| Request body size | 1 MB | Maximum request body |
| Concurrent requests | 4 | Maximum simultaneous requests per app |
| Timeout | 30 seconds | Default request timeout (max 60s) |

## Threat Model

### Threats and Mitigations

| Threat | Mitigation |
|--------|-----------|
| **Data exfiltration**: Malicious app reads user data and sends to remote server | Storage is scoped to app's own folder; host access requires permission; network requires permission; no access to contacts/location without permission |
| **Denial of service**: App consumes excessive CPU/memory | CPU time limits, memory caps, automatic disable after repeated timeouts |
| **Code injection**: App injects malicious code into other apps | Separate JS contexts per app; no shared globals; no dynamic code loading |
| **UI spoofing**: App mimics system dialogs to phish credentials | UI rendered as JSON widget trees; no access to system dialog APIs; install dialogs are rendered by the host, not by JS |
| **Path traversal**: App reads files outside its sandbox | All paths resolved relative to jail root; `../` sequences are rejected |
| **SSRF**: App makes requests to internal services | Network proxy blocks private IP ranges, localhost, and link-local addresses |
| **Supply chain**: Compromised repository pushes malicious update | Code signing verifies author identity; user sees update diff summary; manual update approval |
| **Privilege escalation**: Extension escalates from host_read to host_write | Permissions checked independently per API call; granted set stored in registry |

### Trust Boundaries

```
+----------------------------------------------------------+
|  TRUSTED: Geogram Flutter Host                            |
|  - Renders UI                                             |
|  - Enforces permissions                                   |
|  - Manages storage                                        |
|  - Proxies network                                        |
+---------------------------+------------------------------+
                            |
                   API boundary
                   (permission checks)
                            |
+---------------------------v------------------------------+
|  UNTRUSTED: Third-party JS Code                          |
|  - App logic                                             |
|  - Widget tree generation                                |
|  - Event handling                                        |
+----------------------------------------------------------+
```

## Validation Rules

### Pre-Installation

1. Manifest must be valid JSON with required fields
2. Folder name must not collide with reserved names
3. Permissions must be from the defined set
4. If signed, signature must be valid
5. Package size must be within limits
6. JS files must parse without syntax errors

### Runtime

1. Every `geogram.*` API call checks the caller's granted permissions
2. Storage paths are validated against the app's jail root
3. Network URLs are validated for HTTPS and non-private addresses
4. Widget trees are validated for depth, size, and schema compliance
5. CPU and memory usage are monitored against limits
6. Extension host access is verified against the manifest's `extends` list

### Post-Installation

1. Registry entry must be consistent with manifest
2. Registration files must match manifest hooks
3. Enabled/disabled state must be respected at load time

## Change Log

### Version 1.0 (2026-02-06)

- Initial security model specification
- JS engine sandbox description
- Permission model with 8 permission types
- NOSTR-based code signing and verification
- Install-time confirmation dialogs
- Resource limits (CPU, memory, storage, network)
- Threat model and mitigations
