# Backup Format Specification

**Version**: 1.3
**Last Updated**: 2026-01-04
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Terminology](#terminology)
- [File Organization](#file-organization)
- [Configuration Files](#configuration-files)
- [Backup Relationship Lifecycle](#backup-relationship-lifecycle)
- [Provider Availability and Discovery (LAN + Station)](#provider-availability-and-discovery-lan--station)
- [Snapshot Format](#snapshot-format)
- [Encryption](#encryption)
- [Protocol Messages](#protocol-messages)
- [API Endpoints](#api-endpoints)
- [Backup Process](#backup-process)
- [Restore Process](#restore-process)
- [Automatic Provider Discovery](#automatic-provider-discovery)
- [Error Handling](#error-handling)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

The Backup app enables peer-to-peer backup and restore functionality between Geogram devices. A device can request another trusted device to act as a "backup provider", storing encrypted snapshots of the local device's working folder. The system provides:

- **End-to-end encryption**: Backup data is encrypted using the client's NPUB before transmission; the provider cannot read the contents
- **Scheduled backups**: Automatic backups at configurable intervals (e.g., every 3 days)
- **Snapshot versioning**: Multiple snapshots retained; retention limits are stored but not enforced yet
- **Integrity verification**: SHA1 hashes for all files to ensure download correctness
- **Restore**: Writes files from a snapshot and overwrites existing files (extra files are not deleted)

### Key Features

1. **Invitation-based trust**: Providers must explicitly accept backup requests
2. **Provider-controlled quotas**: Storage limits and max snapshots per client (tracked, not enforced yet)
3. **Client-controlled scheduling**: Backup frequency determined by the client
4. **Bidirectional control**: Either party can pause or terminate the relationship
5. **Multi-transport support**: Bulk transfers use HTTP over LAN or Station proxy; message-only signaling can use other transports
6. **Snapshot notes & history**: Users can browse all snapshots, attach notes, and restore from any point-in-time copy
7. **Event-driven alerts**: Backup/restore lifecycle events are published on the app EventBus to trigger UI and push notifications

## Terminology

| Term | Definition |
|------|------------|
| **Backup Client** | The device that wants to backup its data to a remote device |
| **Backup Provider** | The device that stores encrypted backup data for one or more clients |
| **Snapshot** | A point-in-time copy of the client's working folder, identified by start date |
| **Manifest** | Encrypted file containing a JSON list of files in a snapshot with SHA1 hashes |
| **Relationship** | An established backup agreement between a client and provider |
| **Working Folder** | The Geogram data directory to be backed up |

## File Organization

### Provider Storage Structure

Providers store backup data in a dedicated directory structure:

```
{data_dir}/backups/
├── settings.json                    # Provider global settings
└── {client_callsign}/               # Per-client directory
    ├── config.json                  # Relationship configuration
    ├── 2025-12-12_153015-abcd/      # Snapshot folder (start datetime + random suffix)
    │   ├── manifest.json            # Encrypted manifest bytes (decrypt to get file list)
    │   ├── status.json              # Snapshot status (in_progress/complete/failed)
    │   └── files.zip                # Encrypted file blobs (one entry per file)
    ├── 2025-12-09/
    │   ├── manifest.json
    │   ├── status.json
    │   └── files.zip
    └── 2025-12-06/
        ├── manifest.json
        ├── status.json
        └── files.zip
```

### Client Storage Structure

Clients store backup configuration inside the same backup root:

```
{data_dir}/backups/config/
├── settings.json                    # Client global settings
└── providers/
    └── {provider_callsign}/
        └── config.json              # Per-provider configuration
```

### Naming Conventions

- **Snapshot folders**: Named by start datetime `YYYY-MM-DD_HHMMSS-rrrr` (local time, plus 4-hex random suffix) so multiple snapshots per day are kept separately
- **Encrypted files**: Named by 16 random bytes (32 hex chars) with `.enc` extension

## Configuration Files

### Provider Global Settings

`{data_dir}/backups/settings.json`:

```json
{
  "enabled": true,
  "max_total_storage_bytes": 107374182400,
  "default_max_client_storage_bytes": 10737418240,
  "default_max_snapshots": 10,
  "auto_accept_from_contacts": false,
  "updated_at": "2025-12-12T10:00:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | Whether to accept new backup clients |
| `max_total_storage_bytes` | integer | Total storage available for all clients combined |
| `default_max_client_storage_bytes` | integer | Default storage quota per new client |
| `default_max_snapshots` | integer | Default max snapshots per new client |
| `auto_accept_from_contacts` | boolean | Auto-accept invites from contacts list |
| `updated_at` | string | ISO 8601 timestamp of last update |

### Provider-Client Relationship Config

`{data_dir}/backups/{client_callsign}/config.json`:

```json
{
  "client_npub": "npub1abc123...",
  "client_callsign": "X1ABCD",
  "max_storage_bytes": 10737418240,
  "max_snapshots": 10,
  "current_storage_bytes": 524288000,
  "snapshot_count": 3,
  "status": "active",
  "created_at": "2025-12-01T10:00:00Z",
  "last_backup_at": "2025-12-12T15:30:00Z",
  "last_backup_status": "complete"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `client_npub` | string | Client's NOSTR public key (for encryption key derivation) |
| `client_callsign` | string | Client's callsign |
| `max_storage_bytes` | integer | Storage quota for this client |
| `max_snapshots` | integer | Maximum snapshots to retain |
| `current_storage_bytes` | integer | Current storage used |
| `snapshot_count` | integer | Number of existing snapshots |
| `status` | string | `pending`, `active`, `paused`, `terminated` |
| `created_at` | string | When relationship was established |
| `last_backup_at` | string | Last successful backup timestamp |
| `last_backup_status` | string | `complete`, `partial`, `failed` |

### Client Global Settings

`{data_dir}/backups/config/settings.json`:

```json
{
  "enabled": true,
  "exclude_patterns": [
    "*.log",
    "cache/*",
    "temp/*"
  ],
  "updated_at": "2025-12-12T10:00:00Z"
}
```

Note: `exclude_patterns` are not applied yet; current backups use fixed exclusions for system folders (see Backup Process).

### Client-Provider Config

`{data_dir}/backups/config/providers/{provider_callsign}/config.json`:

```json
{
  "provider_npub": "npub1xyz789...",
  "provider_callsign": "X2BCDE",
  "backup_interval_days": 3,
  "status": "active",
  "max_storage_bytes": 10737418240,
  "max_snapshots": 10,
  "last_successful_backup": "2025-12-12T15:30:00Z",
  "next_scheduled_backup": "2025-12-15T15:30:00Z",
  "created_at": "2025-12-01T10:00:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `provider_npub` | string | Provider's NOSTR public key |
| `provider_callsign` | string | Provider's callsign |
| `backup_interval_days` | integer | Days between automatic backups |
| `status` | string | `pending`, `active`, `paused`, `terminated` |
| `max_storage_bytes` | integer | Provider-allocated storage quota |
| `max_snapshots` | integer | Provider-allowed max snapshots |
| `last_successful_backup` | string | Last successful backup timestamp |
| `next_scheduled_backup` | string | Next scheduled backup timestamp |
| `created_at` | string | When relationship was established |

## Backup Relationship Lifecycle

### States

```
[None] --> [Pending] --> [Active] <--> [Paused] --> [Terminated]
                  |                         |
                  +--> [Declined]           |
                                            v
                                      [Terminated]
```

| State | Description |
|-------|-------------|
| `pending` | Invite sent, awaiting provider response |
| `active` | Relationship active, backups allowed |
| `paused` | Temporarily suspended by either party |
| `terminated` | Permanently ended, data may be deleted |
| `declined` | Provider rejected the invite |

### Lifecycle Events

1. **Invite**: Client sends backup invitation to provider
2. **Accept/Decline**: Provider responds with decision and quota
3. **Activate**: Relationship becomes active after acceptance
4. **Backup**: Client initiates backup to provider
5. **Pause**: Either party temporarily suspends backups
6. **Resume**: Either party resumes paused relationship
7. **Terminate**: Either party permanently ends relationship

## Provider Availability and Discovery (LAN + Station)

This section covers opt-in provider discovery for selecting a backup provider.
It is separate from "Automatic Provider Discovery", which is used for account restoration and uses a privacy-preserving challenge.

### Goals

- Fast listing of devices that are willing to receive backups
- Prefer LAN devices as the most trusted and reliable option
- Keep station listings fresh (no offline devices)
- Avoid exposing client relationships or snapshot details

### Provider Availability State

Providers are considered "available" when:

- `backups/settings.json` has `enabled = true`
- The device is reachable (LAN or station connection)
- The provider is actively advertising or has a fresh station registry entry

### Authentication

All availability requests and announces must be authenticated with a NOSTR-signed JSON event.
This prevents attackers from impersonating other users or forging provider announcements.

Accepted authentication patterns:

1. **HTTP Authorization header** (recommended for GET):
   - `Authorization: Nostr <base64_encoded_event_json>`
2. **Signed JSON body** (for POST):
   - `{ "event": { ...signed_nostr_event... }, "payload": { ... } }`

Verification rules:

- Signature must verify for the `pubkey` in the event
- `created_at` must be within a short freshness window (recommended: 5 minutes)
- `callsign` tag must match the device identity for announce messages
- Station should ignore announces that do not match the connected device identity

### LAN Priority Query

Clients must query LAN devices first. These are typically the most trusted devices and do not require any station access.

Recommended flow:

1. Use device discovery to get LAN-reachable devices (local URL or LAN transport)
2. For each LAN device, query provider availability:
   - `GET /api/backup/availability` (recommended lightweight response)
   - or `GET /api/backup/settings` if availability endpoint is not implemented
   - include `Authorization: Nostr <base64_event_json>` on the request
3. Include only devices that return `enabled = true`
4. Show LAN results in a "Nearby (LAN)" section and use them as first choice

Suggested `GET /api/backup/availability` response:

```json
{
  "enabled": true,
  "callsign": "X2BCDE",
  "npub": "npub1xyz789...",
  "max_total_storage_bytes": 10737418240,
  "default_max_client_storage_bytes": 1073741824,
  "default_max_snapshots": 10,
  "updated_at": "2026-01-04T10:00:00Z"
}
```

### Station Provider Directory (Fast Listing)

When a device is connected to a station and is willing to receive backups, it should notify the station so clients can query a fast list of available providers.

#### Provider Announce Message (Provider -> Station)

Providers send an availability announce on connect and whenever settings change. A periodic refresh keeps the listing alive.

```json
{
  "type": "backup_provider_announce",
  "event": {
    "pubkey": "provider_hex_pubkey",
    "created_at": 1767520800,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "provider_announce"],
      ["callsign", "X2BCDE"],
      ["enabled", "true"],
      ["max_total_storage_bytes", "10737418240"],
      ["default_max_client_storage_bytes", "1073741824"],
      ["default_max_snapshots", "10"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

Station behavior:

- Store an in-memory directory keyed by callsign/npub
- Expire entries after a short TTL (current: 90 seconds)
- Remove entries immediately on device disconnect
- Only return providers that are currently connected and enabled
- Never include client lists or snapshot details
- Verify announce signatures and reject mismatched callsign/npub identity

#### Station Query

`GET /api/backup/providers/available`

Clients must include `Authorization: Nostr <base64_event_json>` so the station can verify the requester.
Station verifies signature, timestamp freshness, and requester identity before responding.

**Response:**
```json
{
  "providers": [
    {
      "callsign": "X2BCDE",
      "npub": "npub1xyz789...",
      "max_total_storage_bytes": 10737418240,
      "default_max_client_storage_bytes": 1073741824,
      "default_max_snapshots": 10,
      "last_seen": "2026-01-04T10:00:30Z",
      "connection_method": "station"
    }
  ]
}
```

### Discovery Order (Recommended)

1. LAN availability query (fast, trusted)
2. Station provider directory (fast, wider reach)
3. Manual add by callsign

If the same provider appears in both LAN and station results, prefer the LAN route for invitations and backups.

### Transport Notes

- The station directory is discovery only; invitations and backups still use ConnectionManager routing
- If no station is connected, LAN discovery remains the primary path

### Privacy Notes

- Availability only indicates willingness to accept new backup clients
- No relationship details or snapshot metadata are exposed
- Clients still need explicit provider approval

## Snapshot Format

### Snapshot Directory

Each snapshot is stored in a date-named directory:

```
{client_callsign}/2025-12-12/
├── manifest.json
├── status.json
└── files/
    ├── a94a8fe5.enc
    ├── b2c3d4e5.enc
    └── ...
```

### Manifest File

`manifest.json` stores encrypted bytes (nonce + ciphertext). After decrypting with the client's NSEC, the JSON payload is:

```json
{
  "version": "1.0",
  "snapshot_id": "2025-12-12",
  "client_callsign": "X1ABCD",
  "client_npub": "npub1abc123...",
  "started_at": "2025-12-12T15:30:00Z",
  "completed_at": "2025-12-12T16:45:00Z",
  "total_files": 1234,
  "total_bytes": 524288000,
  "files": [
    {
      "path": "chat/general/2025/2025-12-12_chat.txt",
      "sha1": "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
      "size": 4096,
      "encrypted_size": 4128,
      "encrypted_name": "9f3a2b1c4d5e6f7890ab12cd34ef56aa.enc",
      "modified_at": "2025-12-12T14:30:00Z"
    },
    {
      "path": "devices/X2BCDE/status.json",
      "sha1": "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1",
      "size": 512,
      "encrypted_size": 544,
      "encrypted_name": "0a1b2c3d4e5f66778899aabbccddeeff.enc",
      "modified_at": "2025-12-12T10:00:00Z"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Manifest format version |
| `snapshot_id` | string | Date identifier `YYYY-MM-DD` |
| `client_callsign` | string | Client's callsign |
| `client_npub` | string | Client's NPUB (for decryption) |
| `started_at` | string | Backup start time |
| `completed_at` | string | Backup completion time (null if in progress) |
| `total_files` | integer | Number of files in snapshot |
| `total_bytes` | integer | Total unencrypted size |
| `files` | array | List of file entries |

### File Entry

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Relative path from working folder |
| `sha1` | string | SHA1 hash of original (unencrypted) file |
| `size` | integer | Original file size in bytes |
| `encrypted_size` | integer | Encrypted file size in bytes |
| `encrypted_name` | string | Random 16-byte hex filename in `files/` directory |
| `modified_at` | string | File modification timestamp |

### Status File

`status.json` tracks snapshot metadata:

```json
{
  "snapshot_id": "2025-12-12",
  "status": "complete",
  "note": "Field work day 3",
  "total_files": 1234,
  "total_bytes": 524288000,
  "started_at": "2025-12-12T15:30:00Z",
  "completed_at": "2025-12-12T16:45:00Z"
}
```

**Fields:**
- `note` (optional): User-supplied label for the snapshot. Providers persist it alongside status for history/restore UI.

## Encryption

### Overview

All backup data is end-to-end encrypted using the client's NOSTR key pair. The provider stores only encrypted blobs and cannot read the contents.

### Encryption Scheme

**Algorithm**: ECIES (Elliptic Curve Integrated Encryption Scheme) with:
- Curve: secp256k1 (same as NOSTR/Bitcoin)
- KDF: HKDF-SHA256
- Cipher: ChaCha20-Poly1305 (AEAD)

### Key Derivation

1. Client generates ephemeral key pair for each file
2. Shared secret derived via ECDH with client's NPUB
3. Encryption key derived from shared secret using HKDF
4. File encrypted with ChaCha20-Poly1305

### Encrypted File Format

```
+------------------+
| Ephemeral pubkey | 33 bytes (compressed)
+------------------+
| Nonce            | 12 bytes
+------------------+
| Ciphertext       | Variable length
+------------------+
| Auth tag         | 16 bytes
+------------------+
```

### Decryption Process

1. Extract ephemeral public key from encrypted file
2. Derive shared secret using client's NSEC and ephemeral pubkey
3. Derive decryption key using HKDF
4. Decrypt ciphertext and verify auth tag
5. Verify SHA1 hash matches manifest entry

### Manifest Encryption

The manifest is encrypted with a deterministic key derived from the client's NSEC so the client can always decrypt it:

```
manifest_key = SHA256("geogram-backup-manifest" || client_nsec_bytes)
```

Encrypted manifest format:

- Nonce (12 bytes) + Ciphertext + Auth tag (16 bytes)

## Protocol Messages

All protocol messages are sent as JSON over WebSocket or HTTP, depending on connectivity. Messages requiring authentication include a NOSTR-signed event.

### Signed Request Envelope

For HTTP APIs, requests that change state or enumerate providers must be authenticated:

- `Authorization: Nostr <base64_encoded_event_json>`
- or include a signed `event` object inside the JSON body

The receiver must verify the signature, freshness, and `callsign`/`pubkey` tags before acting on the request.
Once the sender is authenticated, large payloads (files/manifests) are transferred as raw bytes (`application/octet-stream`) over LAN or station proxy HTTP.
WebRTC transports are used for message signaling only and are not used for bulk file transfers.

### Provider Availability Announce (Provider → Station)

```json
{
  "type": "backup_provider_announce",
  "event": {
    "pubkey": "provider_hex_pubkey",
    "created_at": 1767520800,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "provider_announce"],
      ["callsign", "X2BCDE"],
      ["enabled", "true"],
      ["max_total_storage_bytes", "10737418240"],
      ["default_max_client_storage_bytes", "1073741824"],
      ["default_max_snapshots", "10"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

### Backup Invite (Client → Provider)

```json
{
  "type": "backup_invite",
  "event": {
    "pubkey": "client_hex_pubkey",
    "created_at": 1733923456,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "backup_invite"],
      ["callsign", "X1ABCD"],
      ["target", "X2BCDE"],
      ["interval_days", "3"]
    ],
    "content": "Backup provider invitation",
    "sig": "signature_hex"
  }
}
```

### Invite Response (Provider → Client)

```json
{
  "type": "backup_invite_response",
  "event": {
    "pubkey": "provider_hex_pubkey",
    "created_at": 1733923500,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "backup_invite_response"],
      ["callsign", "X2BCDE"],
      ["target", "X1ABCD"]
    ],
    "content": "",
    "sig": "signature_hex"
  },
  "accepted": true,
  "provider_npub": "npub1xyz789...",
  "max_storage_bytes": 10737418240,
  "max_snapshots": 10
}
```

### Backup Start (Client → Provider)

```json
{
  "type": "backup_start",
  "event": {
    "pubkey": "client_hex_pubkey",
    "created_at": 1733923600,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "backup_start"],
      ["callsign", "X1ABCD"],
      ["target", "X2BCDE"],
      ["snapshot_id", "2025-12-12"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

Note: There is no explicit backup-start acknowledgment. After sending the `backup_start` message, the client begins file uploads immediately.

### File Upload (Client → Provider)

Files are uploaded via HTTP PUT to the upload URL:

```
PUT /api/backup/clients/X1ABCD/snapshots/2025-12-12/files/a94a8fe5.enc
Content-Type: application/octet-stream
Authorization: Nostr <base64_encoded_event>

<encrypted file bytes>
```

### Backup Complete (Client → Provider)

```json
{
  "type": "backup_complete",
  "event": {
    "pubkey": "client_hex_pubkey",
    "created_at": 1733927100,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "backup_complete"],
      ["callsign", "X1ABCD"],
      ["target", "X2BCDE"],
      ["snapshot_id", "2025-12-12"],
      ["total_files", "1234"],
      ["total_bytes", "524288000"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

The encrypted manifest is uploaded separately via `PUT /api/backup/clients/{callsign}/snapshots/{date}`.

### Status Change (Either → Either)

```json
{
  "type": "backup_status_change",
  "event": {
    "pubkey": "sender_hex_pubkey",
    "created_at": 1733930000,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "backup_status_change"],
      ["callsign", "X1ABCD"],
      ["target", "X2BCDE"],
      ["status", "paused"]
    ],
    "content": "Pausing backup relationship",
    "sig": "signature_hex"
  }
}
```

## API Endpoints

### Authentication

All backup API requests in this section require a NOSTR-signed event (including reads like availability and snapshot/file transfers):

- `Authorization: Nostr <base64_encoded_event_json>`
- or `{"event": { ...signed_event... }, "payload": { ... } }`

The server verifies signature, `created_at` freshness, and callsign/npub tags before processing.
After successful authentication, binary transfers are preferred for large payloads.
Requests sent to other devices or the station directory MUST be signed to prevent impersonation.

### Provider Endpoints

All provider endpoints require backup owner authentication (signed by the provider's NSEC).

#### GET /api/backup/settings

Get provider backup settings.

**Response:**
```json
{
  "enabled": true,
  "max_total_storage_bytes": 107374182400,
  "used_storage_bytes": 52428800000,
  "available_storage_bytes": 54946382400,
  "client_count": 5,
  "default_max_client_storage_bytes": 10737418240,
  "default_max_snapshots": 10
}
```

#### PUT /api/backup/settings

Update provider backup settings.

**Request:**
```json
{
  "enabled": true,
  "max_total_storage_bytes": 214748364800,
  "default_max_client_storage_bytes": 21474836480,
  "default_max_snapshots": 15
}
```

#### GET /api/backup/availability

Lightweight provider availability response for LAN queries.
Requires NOSTR-signed authorization.

**Response:**
```json
{
  "enabled": true,
  "callsign": "X2BCDE",
  "npub": "npub1xyz789...",
  "max_total_storage_bytes": 10737418240,
  "default_max_client_storage_bytes": 1073741824,
  "default_max_snapshots": 10,
  "updated_at": "2026-01-04T10:00:00Z"
}
```

#### GET /api/backup/clients

List all backup clients.

**Response:**
```json
{
  "clients": [
    {
      "callsign": "X1ABCD",
      "npub": "npub1abc123...",
      "status": "active",
      "max_storage_bytes": 10737418240,
      "current_storage_bytes": 524288000,
      "snapshot_count": 3,
      "last_backup_at": "2025-12-12T15:30:00Z"
    }
  ]
}
```

#### GET /api/backup/clients/{callsign}

Get specific client info.

#### DELETE /api/backup/clients/{callsign}

Remove client and optionally delete their backups.

**Query Parameters:**
- `delete_data=true` - Also delete all backup data

#### GET /api/backup/clients/{callsign}/snapshots

List client's snapshots.

Requires client authentication for the `callsign` in the URL.

**Response:**
```json
{
  "snapshots": [
    {
      "snapshot_id": "2025-12-12",
      "status": "complete",
      "total_files": 1234,
      "total_bytes": 524288000,
      "started_at": "2025-12-12T15:30:00Z",
      "completed_at": "2025-12-12T16:45:00Z"
    }
  ]
}
```

#### GET /api/backup/clients/{callsign}/snapshots/{date}

Get snapshot manifest (encrypted).

Requires client authentication for the `callsign` in the URL.

Response after authentication:

- `Content-Type: application/octet-stream`
- Response body is raw encrypted manifest bytes

#### PUT /api/backup/clients/{callsign}/snapshots/{date}

Upload encrypted manifest (requires NOSTR auth).

Requires client authentication for the `callsign` in the URL.

Request (preferred):

- `Content-Type: application/octet-stream`
- Body is raw encrypted manifest bytes

Server also accepts JSON/base64 payloads for compatibility.

#### GET /api/backup/clients/{callsign}/snapshots/{date}/files/{name}

Download encrypted file.

Requires client authentication for the `callsign` in the URL.

Response after authentication:

- `Content-Type: application/octet-stream`
- Response body is raw encrypted file bytes

#### PUT /api/backup/clients/{callsign}/snapshots/{date}/files/{name}

Upload encrypted file (requires NOSTR auth).

Requires client authentication for the `callsign` in the URL.

Request (preferred):

- `Content-Type: application/octet-stream`
- Body is raw encrypted file bytes

Server also accepts JSON/base64 payloads for compatibility.

### Client Endpoints

All client endpoints require backup owner authentication (signed by the local user's NSEC).

#### GET /api/backup/providers

List configured backup providers.

**Response:**
```json
{
  "providers": [
    {
      "callsign": "X2BCDE",
      "npub": "npub1xyz789...",
      "status": "active",
      "max_storage_bytes": 10737418240,
      "backup_interval_days": 3,
      "last_successful_backup": "2025-12-12T15:30:00Z",
      "next_scheduled_backup": "2025-12-15T15:30:00Z"
    }
  ]
}
```

#### POST /api/backup/providers

Send backup invite to a device.

**Request:**
```json
{
  "callsign": "X2BCDE",
  "backup_interval_days": 3
}
```

#### PUT /api/backup/providers/{callsign}

Update provider settings (e.g., backup interval).

#### DELETE /api/backup/providers/{callsign}

Remove provider relationship.

#### POST /api/backup/start

Start manual backup to a provider.

**Request:**
```json
{
  "provider_callsign": "X2BCDE"
}
```

**Response:**
```json
{
  "success": true,
  "status": {
    "provider_callsign": "X2BCDE",
    "snapshot_id": "2025-12-12",
    "status": "in_progress",
    "progress_percent": 0,
    "files_transferred": 0,
    "files_total": 0,
    "bytes_transferred": 0,
    "bytes_total": 0,
    "started_at": "2025-12-12T15:30:00Z"
  }
}
```

#### GET /api/backup/status

Get current backup status.

**Response:**
```json
{
  "provider_callsign": "X2BCDE",
  "snapshot_id": "2025-12-12",
  "status": "in_progress",
  "progress_percent": 45,
  "files_transferred": 567,
  "files_total": 1234,
  "bytes_transferred": 234567890,
  "bytes_total": 524288000,
  "started_at": "2025-12-12T15:30:00Z"
}
```

#### POST /api/backup/restore

Start restore from a provider snapshot.

**Request:**
```json
{
  "provider_callsign": "X2BCDE",
  "snapshot_id": "2025-12-12"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Restore started"
}
```

### Station Directory Endpoints

#### GET /api/backup/providers/available

Return only online providers that have advertised availability to the station.
Requires NOSTR-signed authorization.
Requester must be connected to the station; provider entries expire after ~90 seconds without refresh.

**Response:**
```json
{
  "providers": [
    {
      "callsign": "X2BCDE",
      "npub": "npub1xyz789...",
      "max_total_storage_bytes": 10737418240,
      "default_max_client_storage_bytes": 1073741824,
      "default_max_snapshots": 10,
      "last_seen": "2026-01-04T10:00:30Z",
      "connection_method": "station"
    }
  ]
}
```

## Backup Process

### Current Backup Flow

1. **Schedule or Manual Start**: Client triggers backup when scheduled or on demand.
2. **Relationship Check**: Client verifies provider relationship is `active`.
3. **Start Notification**: Client sends `backup_start` message (notification only).
4. **File Enumeration**: Client scans the working folder recursively.
5. **Exclusions**: The following directories are skipped: `backups`, `updates`, `.dart_tool`, `build`.
6. **Encryption + Upload**: Each file is hashed (SHA1), encrypted with the client's NPUB, and uploaded via HTTP PUT to the provider (LAN preferred, station proxy fallback).
7. **Manifest Upload**: Client writes and encrypts the manifest, then uploads it via HTTP PUT.
8. **Completion**: Client sends `backup_complete` and provider records `status.json`.

### Current Limitations

- Backups are full snapshots (no incremental or deduplicated uploads).
- Transfers are sequential (no parallelization or chunked resume).
- Provider quotas and max snapshot limits are stored but not strictly enforced yet.
- Snapshot retention cleanup is not automatic.

## Restore Process

### Full Restore Flow

1. **Snapshot List**: Client fetches snapshots from the provider.
2. **Request**: Client initiates restore via API with `provider_callsign` and `snapshot_id`.
3. **Manifest Download**: Client downloads and decrypts the manifest.
4. **Download Loop**: For each manifest entry, the client downloads the encrypted file, decrypts it with NSEC, and verifies SHA1.
5. **Write to Disk**: Files are written to the working folder (overwriting existing files).
6. **Completion**: Restore completes when all files are written.

### Integrity Verification

For each file during restore:

```
1. Download encrypted file
2. Decrypt file using client's NSEC
3. Calculate SHA1 hash of decrypted content
4. Compare with SHA1 in manifest
5. If match: write file to disk
6. If mismatch: abort restore and report error
```

### Restore Notes

- Restore is additive/overwrite only; files not present in the snapshot are not deleted.
- A failure during download, decryption, or hash verification stops the restore. Files already written remain.

## Automatic Provider Discovery

When restoring an account on a newly installed device, the local device may not know which remote devices are its backup providers. This section describes the automatic discovery mechanism that allows a device to find its backup providers without leaking information about the backup relationship to third parties.

### Use Case: Account Restoration

1. User installs Geogram on a new/wiped device
2. User imports their NSEC (private key) to restore their identity
3. Device needs to discover which remote devices hold their backups
4. Discovery must be privacy-preserving: only the legitimate owner can identify providers

### Discovery Protocol

The discovery protocol uses challenge-response authentication to ensure:
- Only the NPUB owner can query for their own backup providers
- Remote devices don't reveal backup relationships to unauthorized parties
- No replay attacks are possible
- The station cannot determine who is a backup provider for whom

#### Step 1: Get Connected Devices via Station

The newly restored device connects to a station and receives the list of connected devices:

```
GET /api/devices
→ Returns list of {callsign, npub, is_online, ...}
```

#### Step 2: Generate Discovery Challenge

For each potentially online device, the client generates a unique, time-bound challenge:

```json
{
  "type": "backup_discovery_challenge",
  "event": {
    "pubkey": "client_hex_pubkey",
    "created_at": 1733923456,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "discovery_query"],
      ["challenge", "random_32_byte_hex"],
      ["target", "provider_npub"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

| Field | Description |
|-------|-------------|
| `pubkey` | Client's public key (hex) - the NPUB being restored |
| `challenge` | Random 32-byte hex string, unique per query |
| `target` | The NPUB of the device being queried |
| `created_at` | Current Unix timestamp (validated within 5-minute window) |
| `sig` | BIP-340 Schnorr signature proving ownership of the NPUB |

#### Step 3: Provider Response

The remote device receives the discovery query and checks:

1. **Signature valid?** Verify the NOSTR signature using the `pubkey`
2. **Timestamp fresh?** Reject if `created_at` is more than 5 minutes old
3. **Am I a provider?** Check if `pubkey` matches any client in `backups/*/config.json`
4. **Target correct?** Verify `target` tag matches my own NPUB

If all checks pass AND the device IS a backup provider for this NPUB:

```json
{
  "type": "backup_discovery_response",
  "event": {
    "pubkey": "provider_hex_pubkey",
    "created_at": 1733923460,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "discovery_response"],
      ["challenge", "same_challenge_from_request"],
      ["client", "client_npub"],
      ["is_provider", "true"]
    ],
    "content": "{\"max_storage_bytes\":10737418240,\"snapshot_count\":5,\"latest_snapshot\":\"2025-12-10\"}",
    "sig": "signature_hex"
  }
}
```

If NOT a provider, respond with:

```json
{
  "type": "backup_discovery_response",
  "event": {
    "pubkey": "provider_hex_pubkey",
    "created_at": 1733923460,
    "kind": 30000,
    "tags": [
      ["t", "backup"],
      ["action", "discovery_response"],
      ["challenge", "same_challenge_from_request"],
      ["client", "client_npub"],
      ["is_provider", "false"]
    ],
    "content": "",
    "sig": "signature_hex"
  }
}
```

#### Step 4: Client Verification

The client validates each response:

1. **Signature valid?** Verify provider's NOSTR signature
2. **Challenge matches?** The `challenge` tag must match what was sent
3. **Timestamp fresh?** Response must be within reasonable time window
4. **Client tag correct?** Must match my NPUB

### Security Considerations

#### Replay Attack Prevention

- Each discovery query includes a unique random `challenge`
- Provider response must echo the exact `challenge` back
- Challenges are never reused; responses to old challenges are rejected
- Timestamp validation ensures queries can't be stored and replayed later

#### Privacy Protection

- **No broadcast**: Queries are sent directly to each device, not broadcast
- **Indistinguishable responses**: All devices respond (true or false), so an observer cannot tell which devices are providers based on whether they respond
- **Encrypted channel**: Discovery queries/responses travel through station relay but are signed end-to-end; station cannot forge responses
- **No correlation**: Different challenges per device prevent correlation attacks

#### Why Only the NPUB Owner Can Discover

1. Discovery query must be signed with the NSEC corresponding to the NPUB
2. Without the NSEC, an attacker cannot generate valid signatures
3. Providers only respond positively to properly signed queries
4. Even if an attacker intercepts a query, they cannot replay it (timestamp + challenge)

### API Endpoints

#### POST /api/backup/discover

Initiate automatic provider discovery.

**Request:**
```json
{
  "timeout_seconds": 30
}
```

**Response (immediate):**
```json
{
  "discovery_id": "abc123",
  "status": "in_progress",
  "devices_to_query": 42
}
```

#### GET /api/backup/discover/{discovery_id}

Poll discovery status.

**Response:**
```json
{
  "discovery_id": "abc123",
  "status": "complete",
  "devices_queried": 42,
  "devices_responded": 38,
  "providers_found": [
    {
      "callsign": "X2BCDE",
      "npub": "npub1xyz789...",
      "max_storage_bytes": 10737418240,
      "snapshot_count": 5,
      "latest_snapshot": "2025-12-10"
    },
    {
      "callsign": "X3CDEF",
      "npub": "npub1abc456...",
      "max_storage_bytes": 5368709120,
      "snapshot_count": 3,
      "latest_snapshot": "2025-12-08"
    }
  ]
}
```

### Discovery Flow Diagram

```
┌─────────────────┐         ┌─────────────┐         ┌──────────────────┐
│  Restored       │         │   Station   │         │  Remote Device   │
│  Client         │         │   (Relay)   │         │  (Potential      │
│                 │         │             │         │   Provider)      │
└────────┬────────┘         └──────┬──────┘         └────────┬─────────┘
         │                         │                          │
         │  1. GET /api/devices    │                          │
         │────────────────────────>│                          │
         │                         │                          │
         │  List of online devices │                          │
         │<────────────────────────│                          │
         │                         │                          │
         │  2. For each device:    │                          │
         │     backup_discovery_   │                          │
         │     challenge (signed)  │                          │
         │────────────────────────>│─────────────────────────>│
         │                         │                          │
         │                         │  3. Verify signature     │
         │                         │     Check if provider    │
         │                         │     Sign response        │
         │                         │                          │
         │  4. backup_discovery_   │                          │
         │     response (signed)   │<─────────────────────────│
         │<────────────────────────│                          │
         │                         │                          │
         │  5. Verify response     │                          │
         │     If is_provider=true │                          │
         │     → Add to providers  │                          │
         │                         │                          │
```

### Multiple Providers

When multiple backup providers are discovered:

1. Client presents list to user with snapshot information
2. User can select which provider(s) to restore from
3. Restore proceeds with selected provider
4. Client can re-establish relationships with all discovered providers

### Handling Offline Providers

If a backup provider is offline during discovery:

1. Discovery completes with available providers
2. User can retry discovery later to find additional providers
3. User can manually add known providers by callsign
4. Offline providers are not forgotten; discovery can be re-run anytime

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `provider_offline` | Cannot reach provider | Retry when provider online or use LAN |
| `snapshot_not_found` | Requested snapshot doesn't exist | Fetch snapshot list and retry |
| `auth_failed` | Invalid or expired NOSTR signature | Regenerate auth header and retry |
| `hash_mismatch` | File integrity verification failed | Re-run restore |
| `relationship_not_active` | Backup relationship paused/terminated | Re-activate the relationship |
| `encryption_failed` | Encryption error | Check key availability |
| `decryption_failed` | Decryption error (invalid auth tag) | Verify using correct NSEC |

### Current Behavior

- Backups stop on the first failed upload and report `failed`.
- Restores stop on the first failed download, decryption, or SHA1 mismatch.
- There is no resume or partial-restore retry flow yet; re-run the operation.

## Security Considerations

### End-to-End Encryption

- All file content encrypted before leaving client device
- Provider cannot decrypt backup data (no access to client's NSEC)
- Manifest also encrypted to hide file names and structure
- Ephemeral keys used for each file (forward secrecy per file)

### Authentication

- All API requests requiring authentication use NOSTR-signed events
- Event timestamps validated (5-minute freshness window)
- Public keys verified against relationship configuration
- Replay attack prevention via timestamp + action tags

### Key Management

- Client NSEC never transmitted or shared
- Client NPUB used for file encryption key derivation
- Manifest encryption key derived from client NSEC + context string
- Provider only stores encrypted data and client's NPUB
- Key compromise requires re-encrypting all backups

### Data Integrity

- SHA1 hash stored for every file in manifest
- Hash calculated on original (unencrypted) content
- Verified during restore before file is written
- Tampered files detected and rejected

### Privacy

- File names and paths encrypted in manifest
- Directory structure hidden from provider
- File sizes visible only in encrypted form (slightly larger)
- Backup timing metadata visible to provider

### Provider Trust

Even though data is encrypted, consider:
- Provider can see backup timing patterns
- Provider can see approximate data sizes
- Provider can delete backups (denial of service)
- Use multiple providers for redundancy

## Related Documentation

- [NOSTR Integration](./chat-format-specification.md#nostr-integration) - Signature verification
- [API Documentation](../API.md) - General API patterns
- [Device Discovery](../devices.md) - How devices find each other
- [Data Transmission](../data-transmission.md) - Transport priority and offline routing

## Change Log

### Version 1.3 (2026-01-04)
- Updated manifest schema and encryption key derivation
- Documented binary HTTP transfers and transport constraints
- Aligned protocol message actions with current implementation
- Clarified backup/restore flow limitations and overwrite behavior
- Added optional snapshot notes persisted in `status.json` and exposed via API
- Documented history/restore UI expectations and EventBus notifications for backup lifecycle
- Moved client config into `{data_dir}/backups/config/` to keep a single backup app folder
- Snapshot folders now include time + random suffix (`YYYY-MM-DD_HHMMSS-rrrr`) so multiple daily snapshots are retained

### Version 1.2 (2026-01-04)
- Added provider availability and discovery flow (LAN priority + station directory)
- Defined provider announce message for station availability index
- Added LAN availability endpoint with NOSTR auth

### Version 1.1 (2025-12-12)
- Added Automatic Provider Discovery section
- Challenge-response protocol for privacy-preserving provider identification
- Replay attack prevention via unique challenges and timestamp validation
- Support for multiple backup providers during account restoration
- New API endpoints: POST /api/backup/discover, GET /api/backup/discover/{id}

### Version 1.0 (2025-12-12)
- Initial specification
- Core backup/restore functionality
- E2E encryption using NOSTR keys
- Provider quota management
- Snapshot versioning
- SHA1 integrity verification

---

*This specification is part of the Geogram project.*
*License: Apache-2.0*
