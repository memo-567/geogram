# Geogram Sync API

This document describes the synchronization methods available for peer-to-peer data sync between Geogram instances.

## Table of Contents

- [Overview](#overview)
- [Simple Mirror](#simple-mirror)
  - [Protocol Flow](#protocol-flow)
  - [Authentication](#authentication)
  - [API Endpoints](#api-endpoints)
  - [Request/Response Examples](#requestresponse-examples)
- [Future: Bidirectional Sync](#future-bidirectional-sync)
- [Future: Selective Sync](#future-selective-sync)

## Overview

Geogram supports peer-to-peer synchronization of data folders between instances. The sync system uses NOSTR-signed events for authentication and provides multiple sync strategies depending on use case.

### Sync Methods

| Method | Direction | Use Case |
|--------|-----------|----------|
| Simple Mirror | A → B (one-way) | Backup, read-only replicas |
| Bidirectional | A ↔ B (two-way) | Multi-device sync (future) |
| Selective | Configurable | Partial sync (future) |

---

## Simple Mirror

Simple Mirror is a one-way sync where Instance B requests and copies a folder from Instance A. Instance B's local changes are discarded and overwritten by Instance A's content.

### Protocol Flow

```
Instance A (Source)              Instance B (Destination)
     │                                    │
     │  1. GET /api/mirror/challenge      │
     │ ◄──────────────────────────────────│
     │   (folder path)                    │
     │                                    │
     │  2. Return challenge nonce         │
     │──────────────────────────────────► │
     │   (random nonce, expires in 2 min) │
     │                                    │
     │  3. POST /api/mirror/request       │
     │ ◄──────────────────────────────────│
     │   (NOSTR-signed challenge response)│
     │                                    │
     │  4. Verify signature & challenge   │
     │──────────────────────────────────► │
     │   (allowed: true, token)           │
     │                                    │
     │  5. GET /api/mirror/manifest       │
     │ ◄──────────────────────────────────│
     │   (folder path, token)             │
     │                                    │
     │  6. Return manifest                │
     │──────────────────────────────────► │
     │   (file list with SHA1, mtime, size)│
     │                                    │
     │  7. Compare local vs manifest      │
     │                                    │
     │  8. GET /api/mirror/file (repeat)  │
     │ ◄──────────────────────────────────│
     │   (file path, token)               │
     │                                    │
     │  9. Return file content            │
     │──────────────────────────────────► │
     │                                    │
     │  10. Write file locally            │
     │                                    │
     ▼                                    ▼
```

### Authentication (Challenge-Response)

The sync protocol uses challenge-response authentication to prevent replay attacks:

1. **Challenge Request**: Instance B requests a challenge from Instance A
   - A generates a random 256-bit nonce
   - Nonce is valid for 2 minutes (single-use)

2. **Challenge Response**: Instance B signs a NOSTR event (kind 1) containing:
   - `content`: `mirror_response:<nonce>:<folder>` format
   - `pubkey`: Requester's NOSTR public key
   - `created_at`: Response timestamp
   - `sig`: BIP-340 Schnorr signature

3. **Verification**: Instance A verifies:
   - Valid NOSTR signature using `pubkey`
   - Nonce matches an active challenge (single-use, not expired)
   - Folder matches the challenge folder
   - Response is recent (within 5 minutes)
   - Requester's callsign is in the allowed peers list

4. **Token**: Upon successful verification, Instance A returns a temporary access token valid for the sync session (default: 1 hour expiry).

**Why Challenge-Response?**

Without challenge-response, an attacker could:
- Capture a valid signed request from Instance B
- Replay it later to gain unauthorized access to Instance A's files

The challenge-response ensures that only someone with access to the private key (NSEC) can authenticate, as they must sign a fresh, unpredictable challenge.

### API Endpoints

#### GET /api/mirror/challenge

Request a challenge nonce for authentication.

**Query Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `folder` | string | Yes | Folder path to sync |

**Response (200 OK):**
```json
{
  "success": true,
  "nonce": "a1b2c3d4e5f6...64_hex_chars...",
  "folder": "collections/blog",
  "expires_at": 1706000120
}
```

**Error Responses:**

| Code | Error | Description |
|------|-------|-------------|
| 400 | `INVALID_REQUEST` | Missing folder parameter |
| 404 | `FOLDER_NOT_FOUND` | Folder does not exist |

---

#### POST /api/mirror/request

Request permission to sync a folder (must include signed challenge response).

**Request Body:**
```json
{
  "event": {
    "id": "abc123...",
    "kind": 1,
    "pubkey": "def456...",
    "created_at": 1706000000,
    "content": "mirror_response:a1b2c3d4e5f6...64_hex_chars...:collections/blog",
    "tags": [
      ["t", "mirror_response"],
      ["folder", "collections/blog"],
      ["nonce", "a1b2c3d4e5f6...64_hex_chars..."]
    ],
    "sig": "789abc..."
  },
  "folder": "collections/blog"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "allowed": true,
  "token": "temp_access_token_123",
  "expires_at": 1706003600,
  "peer_callsign": "X1ABCD"
}
```

**Error Responses:**

| Code | Error | Description |
|------|-------|-------------|
| 400 | `INVALID_REQUEST` | Missing or malformed request body |
| 400 | `INVALID_CHALLENGE_FORMAT` | Challenge response content malformed |
| 401 | `INVALID_SIGNATURE` | NOSTR signature verification failed |
| 401 | `INVALID_CHALLENGE` | Challenge nonce not found (may be replayed) |
| 401 | `CHALLENGE_EXPIRED` | Challenge nonce has expired |
| 401 | `EXPIRED_REQUEST` | Request timestamp too old |
| 403 | `PEER_NOT_ALLOWED` | Peer not in allowed list |
| 403 | `FOLDER_MISMATCH` | Folder doesn't match challenge |
| 404 | `FOLDER_NOT_FOUND` | Requested folder does not exist |

---

#### GET /api/mirror/manifest

Get folder structure with file metadata.

**Query Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `folder` | string | Yes | Folder path relative to data directory |
| `token` | string | Yes | Access token from request step |

**Response (200 OK):**
```json
{
  "success": true,
  "folder": "collections/blog",
  "total_files": 3,
  "total_bytes": 15360,
  "files": [
    {
      "path": "post1/content.md",
      "sha1": "a1b2c3d4e5f6...",
      "mtime": 1706000000,
      "size": 2048
    },
    {
      "path": "post1/image.jpg",
      "sha1": "d4e5f6a1b2c3...",
      "mtime": 1705999000,
      "size": 10240
    },
    {
      "path": "post2/content.md",
      "sha1": "g7h8i9j0k1l2...",
      "mtime": 1705998000,
      "size": 3072
    }
  ],
  "generated_at": 1706000500
}
```

**Error Responses:**

| Code | Error | Description |
|------|-------|-------------|
| 401 | `INVALID_TOKEN` | Token missing, expired, or invalid |
| 404 | `FOLDER_NOT_FOUND` | Folder no longer exists |

---

#### GET /api/mirror/file

Download a specific file.

**Query Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | Yes | File path relative to synced folder |
| `token` | string | Yes | Access token from request step |

**Headers (Optional):**
- `Range`: Byte range for resumable downloads (e.g., `bytes=1024-2047`)

**Response (200 OK):**
- `Content-Type`: Based on file extension
- `Content-Length`: File size in bytes
- `X-SHA1`: SHA1 hash for verification
- Body: Raw file content (binary)

**Response (206 Partial Content):**
- Same as 200 but for range requests
- `Content-Range`: Byte range returned (e.g., `bytes 1024-2047/10240`)

**Error Responses:**

| Code | Error | Description |
|------|-------|-------------|
| 401 | `INVALID_TOKEN` | Token missing, expired, or invalid |
| 404 | `FILE_NOT_FOUND` | File does not exist |
| 416 | `RANGE_NOT_SATISFIABLE` | Invalid byte range |

---

### Request/Response Examples

#### Complete Sync Flow Example

**Step 1: Request sync permission**
```bash
curl -X POST http://instance-a:3456/api/mirror/request \
  -H "Content-Type: application/json" \
  -d '{
    "event": {
      "id": "abc123...",
      "kind": 1,
      "pubkey": "02def456...",
      "created_at": 1706000000,
      "content": "simple_mirror:collections/blog",
      "tags": [["t", "mirror_request"], ["folder", "collections/blog"]],
      "sig": "789abc..."
    },
    "folder": "collections/blog"
  }'
```

**Response:**
```json
{
  "success": true,
  "allowed": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_at": 1706003600,
  "peer_callsign": "X1ABCD"
}
```

**Step 2: Get manifest**
```bash
curl "http://instance-a:3456/api/mirror/manifest?folder=collections/blog&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**Response:**
```json
{
  "success": true,
  "folder": "collections/blog",
  "total_files": 2,
  "total_bytes": 5120,
  "files": [
    {"path": "post1.md", "sha1": "abc123", "mtime": 1706000000, "size": 2048},
    {"path": "post2.md", "sha1": "def456", "mtime": 1705999000, "size": 3072}
  ],
  "generated_at": 1706000500
}
```

**Step 3: Download changed files**
```bash
curl "http://instance-a:3456/api/mirror/file?path=post1.md&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -o post1.md
```

---

### Sync Logic on Destination (Instance B)

When syncing, Instance B:

1. **Requests manifest** from Instance A
2. **Compares** each file in manifest against local folder:
   - If file doesn't exist locally → **download**
   - If SHA1 differs → **download** (overwrite local)
   - If SHA1 matches → **skip** (already synced)
3. **Deletes** local files not in manifest (optional, controlled by config)
4. **Updates** local mtime to match source

```dart
// Pseudocode for diff logic
Future<List<FileChange>> diffManifest(MirrorManifest remote, String localPath) async {
  final changes = <FileChange>[];

  for (final remoteFile in remote.files) {
    final localFile = File('$localPath/${remoteFile.path}');

    if (!await localFile.exists()) {
      changes.add(FileChange.add(remoteFile));
    } else {
      final localSha1 = await computeSha1(localFile);
      if (localSha1 != remoteFile.sha1) {
        changes.add(FileChange.modify(remoteFile));
      }
    }
  }

  // Optionally mark local-only files for deletion
  // ...

  return changes;
}
```

---

## Future: Bidirectional Sync

Bidirectional sync will use vector clocks or CRDTs to handle concurrent modifications on both sides. This enables true multi-device sync where changes can happen on any device.

---

## Future: Selective Sync

Selective sync will allow filtering which files to sync based on:
- File patterns (e.g., `*.md` only)
- Folder whitelists/blacklists
- File size limits
- Date ranges

---

## Related Files

| File | Description |
|------|-------------|
| `lib/services/mirror_sync_service.dart` | Mirror sync implementation |
| `lib/services/mirror_config_service.dart` | Configuration persistence |
| `lib/models/mirror_config.dart` | Configuration models |
| `lib/services/log_api_service.dart` | API endpoint handlers |
| `lib/services/debug_controller.dart` | Debug actions for testing |
| `docs/API.md` | Main API documentation |
