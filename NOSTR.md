# NOSTR Relay + Blossom Implementation Notes

This document summarizes what is implemented in Geogram for the local NOSTR relay and Blossom storage, and what is still missing.

## Overview

Geogram now includes a basic NOSTR relay and Blossom storage layer:

- SQLite-backed relay storage for NIP-01 events.
- Optional NIP-42 authentication for writes (default ON).
- Write acceptance restricted to profile user + followed contacts.
- Open relay behavior for root paths (`wss://p2p.radio`) with unrestricted writes.
- Blossom file storage with SQLite metadata + on-disk blobs.
- Blossom replication for followed authors based on event tags.
- Shared relay/blossom storage path under `nostr/` in the repo root when running from the repo, otherwise under app data dir.

Both the GUI station server (`StationServerService`) and the CLI/Android station server (`PureStationServer`) use the same relay + Blossom services.

## Storage Layout

- Relay DB: `nostr/relay.sqlite3`
- Blossom DB: `nostr/blossom.sqlite3`
- Blossom blob files: `nostr/blossom/`

Path logic:
- If running from the repo (detected via `pubspec.yaml` + `lib/`), storage is rooted at `<repo>/nostr/`.
- Otherwise uses `StorageConfig.baseDir` (GUI) or `PureStorageConfig.baseDir` (CLI), then `/nostr`.

## Relay Protocol Support

### Implemented

- **NIP-01** core relay protocol:
  - `EVENT` (write)
  - `REQ` + filters (read)
  - `CLOSE`
  - `EOSE` end of stored events
- **NIP-09** deletion:
  - Kind `5` events mark target events as deleted.
- **NIP-16** replaceable + parameterized replaceable:
  - Replaceable kinds are tracked via `replaced_by`.
- **NIP-25** reactions:
  - Kind `7` stored and queryable like any event.
- **NIP-42** authentication:
  - Relay sends `["AUTH", <challenge>]`.
  - Writes are blocked unless auth succeeds (default ON).
  - Auth is optional via settings.

### Missing / Not Implemented

- NIP-11 relay info document (`/.well-known/nostr.json` exists for NIP-05, but no relay info response yet).
- NIP-65 relay list metadata handling.
- NIP-57 zaps (invoices, zap receipts).
- NIP-19 bech32 IDs in queries.
- NIP-42 auth for reads (writes only).
- Event streaming backpressure or rate limiting by subscription.

## Relay Acceptance Rules

### Restricted relay (callsign path)

Paths with callsign (example: `wss://p2p.radio/x1abcd`) are treated as restricted relay endpoints:

- Only the profile user and followed contacts are allowed to write.
- If NIP-42 is enabled, writes require `AUTH` and the `AUTH` pubkey must match the event author.

### Open relay (root path)

Root paths without a callsign (example: `wss://p2p.radio`) are treated as open relay endpoints:

- Writes are accepted from any author.
- Auth is bypassed even if enabled globally.

## Blossom Support

### Implemented

- HTTP endpoints:
  - `POST /blossom/upload`
    - Accepts raw bytes or multipart form-data (`file` field).
  - `GET /blossom/<hash>`
  - `HEAD /blossom/<hash>`
- Storage:
  - SQLite metadata + filesystem blob files.
  - Configurable max disk usage (`blossomMaxStorageMb`).
  - Configurable max file size (`blossomMaxFileMb`, default 10MB).
- Replication:
  - For followed authors, event tags are scanned for URLs.
  - Supported tag patterns: `["url", "https://..."]` and `["imeta", "url https://..."]`.
  - Matching blobs are replicated into local Blossom.

### Missing / Not Implemented

- Blossom JSON API responses beyond basic upload response.
- Authentication of Blossom reads (currently open).
- Content-addressed URLs or signed manifests.
- Deduplication/replication via Blossom protocol spec (only plain HTTP fetch).

## SQLite Schema Summary

### Relay DB (`relay.sqlite3`)

- `events`:
  - `id`, `pubkey`, `created_at`, `kind`, `content`, `sig`, `raw`, `deleted_at`, `replaced_by`
- `event_tags`:
  - `event_id`, `idx`, `tag`, `value`, `other`
- `event_refs`:
  - `event_id`, `ref_type`, `ref`

Indexes:
- `events_kind_created_at_idx`
- `events_pubkey_created_at_idx`
- `events_deleted_idx`
- `event_tags_tag_value_idx`
- `event_refs_ref_idx`

### Blossom DB (`blossom.sqlite3`)

- `blobs`:
  - `hash`, `size`, `mime`, `created_at`, `path`, `owner_pubkey`
- `blob_refs`:
  - `hash`, `event_id`, `pubkey`, `created_at`
- `settings`:
  - `key`, `value`

Indexes:
- `blobs_created_at_idx`
- `blobs_owner_idx`
- `blob_refs_event_idx`

## Settings

Available in Station settings (GUI) and station config (CLI/Android):

- `nostrRequireAuthForWrites` (bool, default `true`)
- `blossomMaxStorageMb` (int, default `1024`)
- `blossomMaxFileMb` (int, default `10`)

## Known Limitations

- Relay writes are validated but there is no global rate limiting at the relay layer (beyond server IP limits).
- Relay does not implement advanced query filters (e.g., `search`).
- Blossom pruning is oldest-first and may delete referenced blobs if over cap.
- Followed authors list is derived from contacts (callsign contact entries with `npub`).
- No migration framework yet (tables are created on open).

## Files Added/Modified

New:
- `lib/services/nostr_storage_paths.dart`
- `lib/services/nostr_relay_storage.dart`
- `lib/services/nostr_relay_service.dart`
- `lib/services/nostr_blossom_service.dart`

Modified:
- `lib/services/station_server_service.dart`
- `lib/cli/pure_station.dart`
- `lib/models/station_node.dart`
- `lib/pages/station_settings_page.dart`
- `lib/services/station_node_service.dart`
- `pubspec.yaml`

## How to Test (Manual)

1) Run station server.
2) Connect via WebSocket:
   - `wss://<host>` (open relay)
   - `wss://<host>/<callsign>` (restricted relay)
3) Send:
   - `["REQ","sub",{"kinds":[1],"limit":1}]`
   - `["EVENT",{...}]` (signed)
4) Upload blob:
   - `POST /blossom/upload`
   - `GET /blossom/<hash>`

