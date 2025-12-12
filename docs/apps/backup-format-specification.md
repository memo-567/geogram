# Backup Format Specification

**Version**: 1.1
**Last Updated**: 2025-12-12
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Terminology](#terminology)
- [File Organization](#file-organization)
- [Configuration Files](#configuration-files)
- [Backup Relationship Lifecycle](#backup-relationship-lifecycle)
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
- **Snapshot versioning**: Multiple snapshots retained based on provider-defined limits
- **Integrity verification**: SHA1 hashes for all files to ensure download correctness
- **Full restore**: Complete working folder restoration from any snapshot

### Key Features

1. **Invitation-based trust**: Providers must explicitly accept backup requests
2. **Provider-controlled quotas**: Storage limits and max snapshots per client
3. **Client-controlled scheduling**: Backup frequency determined by the client
4. **Bidirectional control**: Either party can pause or terminate the relationship
5. **Multi-transport support**: Works over LAN (fast) and Station relay (remote)

## Terminology

| Term | Definition |
|------|------------|
| **Backup Client** | The device that wants to backup its data to a remote device |
| **Backup Provider** | The device that stores encrypted backup data for one or more clients |
| **Snapshot** | A point-in-time copy of the client's working folder, identified by start date |
| **Manifest** | JSON file listing all files in a snapshot with their SHA1 hashes |
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
    ├── 2025-12-12/                  # Snapshot folder (start date)
    │   ├── manifest.json            # File list with SHA1 hashes
    │   ├── status.json              # Snapshot status (in_progress/complete/failed)
    │   └── files/                   # Encrypted file blobs
    │       ├── a94a8fe5.enc
    │       ├── b2c3d4e5.enc
    │       └── ...
    ├── 2025-12-09/
    │   ├── manifest.json
    │   ├── status.json
    │   └── files/
    └── 2025-12-06/
        ├── manifest.json
        ├── status.json
        └── files/
```

### Client Storage Structure

Clients store backup configuration locally:

```
{data_dir}/backup-config/
├── settings.json                    # Client global settings
└── providers/
    └── {provider_callsign}/
        └── config.json              # Per-provider configuration
```

### Naming Conventions

- **Snapshot folders**: Named by start date `YYYY-MM-DD` (even if backup spans multiple days)
- **Encrypted files**: Named by first 8 characters of SHA1 hash with `.enc` extension
- **Only one snapshot per day**: If a second backup is requested on the same day, it overwrites the existing snapshot

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

`{data_dir}/backup-config/settings.json`:

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

### Client-Provider Config

`{data_dir}/backup-config/providers/{provider_callsign}/config.json`:

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

`manifest.json` contains the complete file list with integrity hashes:

```json
{
  "version": "1.0",
  "snapshot_id": "2025-12-12",
  "client_callsign": "X1ABCD",
  "client_npub": "npub1abc123...",
  "started_at": "2025-12-12T15:30:00Z",
  "completed_at": "2025-12-12T16:45:00Z",
  "status": "complete",
  "total_files": 1234,
  "total_bytes_original": 524288000,
  "total_bytes_encrypted": 528482304,
  "files": [
    {
      "path": "chat/general/2025/2025-12-12_chat.txt",
      "sha1": "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3",
      "size": 4096,
      "encrypted_size": 4128,
      "encrypted_name": "a94a8fe5.enc",
      "modified_at": "2025-12-12T14:30:00Z"
    },
    {
      "path": "devices/X2BCDE/status.json",
      "sha1": "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1",
      "size": 512,
      "encrypted_size": 544,
      "encrypted_name": "b2c3d4e5.enc",
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
| `status` | string | `in_progress`, `complete`, `partial`, `failed` |
| `total_files` | integer | Number of files in snapshot |
| `total_bytes_original` | integer | Total unencrypted size |
| `total_bytes_encrypted` | integer | Total encrypted size |
| `files` | array | List of file entries |

### File Entry

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Relative path from working folder |
| `sha1` | string | SHA1 hash of original (unencrypted) file |
| `size` | integer | Original file size in bytes |
| `encrypted_size` | integer | Encrypted file size in bytes |
| `encrypted_name` | string | Filename in `files/` directory |
| `modified_at` | string | File modification timestamp |

### Status File

`status.json` tracks snapshot progress:

```json
{
  "snapshot_id": "2025-12-12",
  "status": "in_progress",
  "files_total": 1234,
  "files_transferred": 567,
  "bytes_total": 524288000,
  "bytes_transferred": 234567890,
  "started_at": "2025-12-12T15:30:00Z",
  "last_activity_at": "2025-12-12T15:45:00Z",
  "error": null
}
```

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

The manifest file is also encrypted, but uses a deterministic key derived from the client's NPUB so the client can always decrypt it:

```
manifest_key = HKDF(ECDH(client_nsec, client_npub), "geogram-backup-manifest")
```

## Protocol Messages

All protocol messages are sent as JSON over WebSocket or HTTP, depending on connectivity. Messages requiring authentication include a NOSTR-signed event.

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
      ["action", "invite"],
      ["callsign", "X1ABCD"]
    ],
    "content": "Requesting backup provider relationship",
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
      ["action", "invite_response"],
      ["client", "npub1abc123..."]
    ],
    "content": "{\"accepted\":true,\"max_storage_bytes\":10737418240,\"max_snapshots\":10}",
    "sig": "signature_hex"
  }
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
      ["action", "start"],
      ["snapshot_id", "2025-12-12"]
    ],
    "content": "{\"total_files\":1234,\"total_bytes\":524288000}",
    "sig": "signature_hex"
  }
}
```

### Backup Acknowledgment (Provider → Client)

```json
{
  "type": "backup_start_ack",
  "accepted": true,
  "snapshot_id": "2025-12-12",
  "upload_url": "/api/backup/clients/X1ABCD/upload"
}
```

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
      ["action", "complete"],
      ["snapshot_id", "2025-12-12"]
    ],
    "content": "{\"status\":\"complete\",\"total_files\":1234,\"total_bytes\":524288000}",
    "sig": "signature_hex"
  },
  "manifest": "<encrypted_manifest_json>"
}
```

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
      ["action", "status_change"],
      ["new_status", "paused"]
    ],
    "content": "Pausing backup relationship",
    "sig": "signature_hex"
  }
}
```

## API Endpoints

### Provider Endpoints

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

#### GET /api/backup/clients/{callsign}/snapshots/{date}/files/{name}

Download encrypted file.

#### PUT /api/backup/clients/{callsign}/snapshots/{date}/files/{name}

Upload encrypted file (requires NOSTR auth).

### Client Endpoints

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
  "snapshot_id": "2025-12-12",
  "status": "in_progress"
}
```

#### GET /api/backup/status

Get current backup status.

**Response:**
```json
{
  "active_backup": {
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
  "status": "downloading",
  "total_files": 1234,
  "total_bytes": 524288000
}
```

## Backup Process

### Automatic Backup Flow

1. **Schedule Check**: Client checks if `backup_interval_days` has elapsed since last backup
2. **Connectivity Check**: Verify provider is reachable (LAN or Station relay)
3. **Start Notification**: Send `backup_start` message to provider
4. **Acknowledgment**: Provider responds with upload URL and confirms space available
5. **File Enumeration**: Client scans working folder, calculates SHA1 hashes
6. **Incremental Check**: Compare with last snapshot manifest to find changed files
7. **Encryption**: Encrypt each file with client's NPUB
8. **Upload**: Transfer encrypted files to provider
9. **Manifest Upload**: Send encrypted manifest
10. **Completion**: Send `backup_complete` message
11. **Cleanup**: Provider deletes oldest snapshot if `max_snapshots` exceeded

### File Transfer Optimization

- **Incremental backups**: Only transfer files that changed since last snapshot
- **Chunked uploads**: Large files split into chunks for resume capability
- **Parallel transfers**: Multiple files uploaded concurrently when bandwidth allows
- **Compression**: Optional gzip compression before encryption for text files

### Quota Management

When disk space fills before backup completes:

1. Provider detects quota would be exceeded
2. Provider sends `backup_quota_exceeded` message
3. Client receives notification of partial backup
4. Snapshot marked as `partial` in status.json
5. Both parties notified via UI
6. Client can retry with smaller selection or request more quota

## Restore Process

### Full Restore Flow

1. **Request**: Client initiates restore via API
2. **Manifest Download**: Client downloads and decrypts manifest
3. **Verification**: Client reviews file list
4. **Warning**: Client acknowledges working folder will be overwritten
5. **Download**: Client downloads all encrypted files
6. **Decryption**: Client decrypts files using NSEC
7. **Verification**: Client verifies SHA1 hash for each file
8. **Replacement**: Working folder contents replaced with restored files
9. **Completion**: Restore complete notification

### Integrity Verification

For each file during restore:

```
1. Download encrypted file
2. Decrypt file using client's NSEC
3. Calculate SHA1 hash of decrypted content
4. Compare with SHA1 in manifest
5. If match: write file to disk
6. If mismatch: report error, skip file, continue restore
```

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
| `quota_exceeded` | Backup would exceed storage limit | Request more quota or delete old snapshots |
| `provider_offline` | Cannot reach provider | Retry when provider online |
| `snapshot_not_found` | Requested snapshot doesn't exist | List available snapshots |
| `auth_failed` | Invalid NOSTR signature | Check keys, retry |
| `hash_mismatch` | File integrity verification failed | Re-download file |
| `relationship_not_active` | Backup relationship paused/terminated | Check status, resume if paused |
| `encryption_failed` | Encryption error | Check key availability |
| `decryption_failed` | Decryption error | Verify using correct NSEC |

### Partial Backup Handling

When backup fails partway:

1. Snapshot status set to `partial`
2. Successfully uploaded files are retained
3. Manifest updated with actual files transferred
4. Client notified of incomplete backup
5. Next backup attempts full sync again

### Connection Loss Recovery

- File uploads support resume from last chunk
- Interrupted backups can be continued
- Provider tracks partially uploaded files
- Client can query upload progress and resume

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
- Client NPUB used for encryption key derivation
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

## Change Log

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
