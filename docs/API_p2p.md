# P2P File Transfer API

This document describes the peer-to-peer file transfer protocol used for sending files directly between Geogram devices.

## Table of Contents

- [Overview](#overview)
- [Protocol Flow](#protocol-flow)
- [Message Types](#message-types)
  - [Transfer Offer](#transfer-offer)
  - [Transfer Response](#transfer-response)
  - [Transfer Progress](#transfer-progress)
  - [Transfer Complete](#transfer-complete)
- [HTTP Endpoints](#http-endpoints)
  - [GET /api/p2p/offer/{offerId}/manifest](#get-apip2pofferofferidmanifest)
  - [GET /api/p2p/offer/{offerId}/file](#get-apip2pofferofferidfile)
- [Service API](#service-api)
- [Events](#events)
- [Error Handling](#error-handling)
- [Security](#security)

---

## Overview

P2P file transfer enables direct file sharing between Geogram devices without requiring a central server. The sender initiates an offer, the receiver accepts and selects a destination, then downloads files directly from the sender's HTTP API.

Key features:
- **Direct transfer**: Files are sent directly between devices via the Connection Manager
- **Offer-based flow**: Sender creates an offer, receiver must accept before download begins
- **Progress tracking**: Both sides receive real-time progress updates
- **Resumable**: Supports Range headers for interrupted downloads
- **SHA1 verification**: Files are verified using SHA1 hashes

---

## Protocol Flow

```
SENDER                                    RECEIVER
   │                                          │
   │ 1. User selects files + recipient        │
   │    Press "Send"                          │
   │                                          │
   │ 2. Create manifest with SHA1 hashes      │
   │    Generate offer ID and serve token     │
   │    Send OFFER via DM ──────────────────► │
   │                                          │
   │ 3. Show "Pending acceptance"             │ 4. Show incoming request dialog
   │    Files registered for serving          │    User selects destination folder
   │                                          │
   │                         ◄──────────────── │ 5. Send RESPONSE (accept/reject)
   │                                          │
   │ 6. Update status to "Uploading"          │ 7. Fetch manifest from sender
   │    Start serving files via HTTP          │    Begin downloading files
   │                                          │
   │ 8. Receive progress updates ◄─────────── │    Send PROGRESS updates
   │    Update upload progress bar            │    (every 64KB or per file)
   │                                          │
   │ 9. Receive completion ◄───────────────── │ 10. Send COMPLETE notification
   │    Show "Complete" status                │     Verify SHA1 hashes
   │    Clean up serve token                  │     Save files to destination
```

---

## Message Types

All P2P messages are sent as NOSTR kind-4 encrypted DMs via the Connection Manager. The message content is JSON with a `type` field indicating the message type.

### Transfer Offer

Sent from sender to receiver when initiating a transfer.

```json
{
  "type": "transfer_offer",
  "offerId": "tr_abc123def456",
  "senderCallsign": "X1ALICE",
  "senderNpub": "npub1...",
  "timestamp": 1706000000,
  "expiresAt": 1706003600,
  "manifest": {
    "totalFiles": 3,
    "totalBytes": 15360,
    "files": [
      {
        "path": "photo.jpg",
        "name": "photo.jpg",
        "size": 10240,
        "sha1": "a1b2c3d4e5f6..."
      },
      {
        "path": "docs/readme.txt",
        "name": "readme.txt",
        "size": 2048,
        "sha1": "b2c3d4e5f6g7..."
      },
      {
        "path": "docs/report.pdf",
        "name": "report.pdf",
        "size": 3072,
        "sha1": "c3d4e5f6g7h8..."
      }
    ]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"transfer_offer"` |
| `offerId` | string | Unique offer identifier (format: `tr_<timestamp><random>`) |
| `senderCallsign` | string | Sender's callsign (e.g., `X1ALICE`) |
| `senderNpub` | string | Sender's NOSTR public key |
| `timestamp` | int | Unix timestamp when offer was created |
| `expiresAt` | int | Unix timestamp when offer expires (default: 1 hour) |
| `manifest.totalFiles` | int | Total number of files in the offer |
| `manifest.totalBytes` | int | Total size of all files in bytes |
| `manifest.files` | array | Array of file objects |
| `manifest.files[].path` | string | Relative path including subdirectories |
| `manifest.files[].name` | string | File name only |
| `manifest.files[].size` | int | File size in bytes |
| `manifest.files[].sha1` | string | SHA1 hash for verification |

### Transfer Response

Sent from receiver to sender to accept or reject an offer.

```json
{
  "type": "transfer_response",
  "offerId": "tr_abc123def456",
  "accepted": true,
  "receiverCallsign": "X1BOB"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"transfer_response"` |
| `offerId` | string | Offer ID being responded to |
| `accepted` | boolean | `true` to accept, `false` to reject |
| `receiverCallsign` | string | Receiver's callsign |

### Transfer Progress

Sent from receiver to sender during file download.

```json
{
  "type": "transfer_progress",
  "offerId": "tr_abc123def456",
  "bytesReceived": 8192,
  "totalBytes": 15360,
  "filesCompleted": 1,
  "currentFile": "docs/readme.txt"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"transfer_progress"` |
| `offerId` | string | Offer ID |
| `bytesReceived` | int | Total bytes downloaded so far |
| `totalBytes` | int | Total bytes to download |
| `filesCompleted` | int | Number of files fully downloaded |
| `currentFile` | string | File currently being downloaded |

Progress updates are sent:
- At the start of each file download
- Every 64KB during download
- When each file completes

### Transfer Complete

Sent from receiver to sender when transfer finishes.

```json
{
  "type": "transfer_complete",
  "offerId": "tr_abc123def456",
  "success": true,
  "bytesReceived": 15360,
  "filesReceived": 3
}
```

On failure:
```json
{
  "type": "transfer_complete",
  "offerId": "tr_abc123def456",
  "success": false,
  "bytesReceived": 8192,
  "filesReceived": 1,
  "error": "SHA1 mismatch for docs/report.pdf"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"transfer_complete"` |
| `offerId` | string | Offer ID |
| `success` | boolean | `true` if all files downloaded and verified |
| `bytesReceived` | int | Total bytes downloaded |
| `filesReceived` | int | Number of files successfully downloaded |
| `error` | string | Error message (only present on failure) |

---

## HTTP Endpoints

The sender exposes HTTP endpoints for the receiver to download files. These endpoints are protected by a serve token included in the manifest response.

### GET /api/p2p/offer/{offerId}/manifest

Get the offer manifest with the serve token.

**Path Parameters:**
- `offerId`: The offer ID (required)

**Response (200 OK):**
```json
{
  "offerId": "tr_abc123def456",
  "totalFiles": 3,
  "totalBytes": 15360,
  "token": "random_serve_token_here",
  "files": [
    {
      "path": "photo.jpg",
      "name": "photo.jpg",
      "size": 10240,
      "sha1": "a1b2c3d4e5f6..."
    }
  ]
}
```

**Response (404 Not Found):**
```json
{
  "success": false,
  "error": "Offer not found or expired",
  "code": "OFFER_NOT_FOUND"
}
```

### GET /api/p2p/offer/{offerId}/file

Download a specific file from the offer.

**Path Parameters:**
- `offerId`: The offer ID (required)

**Query Parameters:**
- `path`: File path relative to offer root (required)
- `token`: Serve token from manifest (required)

**Headers (Optional):**
- `Range`: Byte range for resumable downloads (e.g., `bytes=1024-`)

**Response (200 OK):**
- Body: Raw file content
- Headers:
  - `Content-Type`: MIME type based on file extension
  - `Content-Length`: File size in bytes
  - `X-SHA1`: SHA1 hash for verification

**Response (206 Partial Content):**
For Range requests:
- Body: Requested byte range
- Headers:
  - `Content-Range`: `bytes start-end/total`
  - `X-SHA1`: Full file SHA1 hash

**Response (401 Unauthorized):**
```json
{
  "success": false,
  "error": "Invalid or expired token",
  "code": "INVALID_TOKEN"
}
```

**Response (404 Not Found):**
```json
{
  "success": false,
  "error": "File not found in offer",
  "code": "FILE_NOT_FOUND"
}
```

**Response (416 Range Not Satisfiable):**
```json
{
  "success": false,
  "error": "Range not satisfiable",
  "code": "RANGE_NOT_SATISFIABLE"
}
```

---

## Service API

The `P2PTransferService` provides methods for managing transfers.

### Sender Methods

```dart
// Send a transfer offer
final offer = await P2PTransferService().sendOffer(
  recipientCallsign: 'X1BOB',
  items: [
    SendItem(path: '/path/to/file.jpg', name: 'file.jpg', isDirectory: false),
    SendItem(path: '/path/to/folder', name: 'folder', isDirectory: true),
  ],
);

// Cancel a pending offer
await P2PTransferService().cancelOffer(offerId);

// Get all outgoing offers
final offers = P2PTransferService().outgoingOffers;
```

### Receiver Methods

```dart
// Accept an offer and start download
await P2PTransferService().acceptOffer(
  offerId,
  '/path/to/destination/folder',
);

// Reject an offer
await P2PTransferService().rejectOffer(offerId);

// Get all incoming offers
final offers = P2PTransferService().incomingOffers;
```

### Common Methods

```dart
// Get an offer by ID (incoming or outgoing)
final offer = P2PTransferService().getOffer(offerId);

// Clean up expired offers
P2PTransferService().cleanupExpired();
```

---

## Events

The P2P transfer system fires events via the `EventBus` for UI updates.

### TransferOfferReceivedEvent

Fired when an incoming offer is received.

```dart
EventBus().on<TransferOfferReceivedEvent>((event) {
  print('Offer from ${event.senderCallsign}');
  print('Files: ${event.totalFiles}, Size: ${event.totalBytes}');
  print('Expires: ${event.expiresAt}');
  // Show incoming offer dialog
});
```

### TransferOfferResponseEvent

Fired when a receiver responds to your offer.

```dart
EventBus().on<TransferOfferResponseEvent>((event) {
  if (event.accepted) {
    print('Offer ${event.offerId} accepted by ${event.receiverCallsign}');
  } else {
    print('Offer ${event.offerId} rejected');
  }
});
```

### P2PUploadProgressEvent

Fired on the sender side as the receiver downloads.

```dart
EventBus().on<P2PUploadProgressEvent>((event) {
  print('Progress: ${event.progressPercent.toStringAsFixed(1)}%');
  print('Files: ${event.filesCompleted}/${event.totalFiles}');
  print('Current: ${event.currentFile}');
});
```

### P2PTransferCompleteEvent

Fired when a transfer completes (success or failure).

```dart
EventBus().on<P2PTransferCompleteEvent>((event) {
  if (event.success) {
    print('Transfer complete: ${event.filesReceived} files');
  } else {
    print('Transfer failed: ${event.error}');
  }
});
```

### TransferOfferStatusChangedEvent

Fired when an offer's status changes.

```dart
EventBus().on<TransferOfferStatusChangedEvent>((event) {
  print('Offer ${event.offerId} status: ${event.status}');
  if (event.error != null) {
    print('Error: ${event.error}');
  }
});
```

---

## Error Handling

### Offer Expiry

Offers expire after 1 hour by default. Check `offer.isExpired` or `offer.timeUntilExpiry` before attempting operations.

### Sender Offline

If the sender goes offline after the offer is accepted:
1. The receiver will see a connection error when fetching manifest/files
2. The receiver can retry later (offer remains valid until expiry)
3. If using Range headers, partial downloads can be resumed

### Transfer Failures

Common failure scenarios:

| Scenario | Behavior |
|----------|----------|
| SHA1 mismatch | Transfer marked as failed, error includes file path |
| Network timeout | Connection error, can retry |
| Disk full | Transfer fails, error indicates disk space issue |
| Token invalid | 401 error, offer may have been cancelled |

---

## Security

### Token-Based Access

- Each offer generates a unique serve token
- Token is included in the manifest response
- Token must be provided for all file download requests
- Token is invalidated when:
  - Offer is cancelled
  - Offer expires
  - Transfer completes

### Path Traversal Protection

The file serving endpoint validates that requested paths:
- Are registered in the offer's file list
- Do not escape the offer's file mapping

### NOSTR Signing

All P2P messages are sent as NOSTR kind-4 DMs:
- Messages are signed with the sender's nsec
- Message authenticity is verified on receipt
- Replay attacks are prevented by unique offer IDs

---

## Status Reference

### TransferOfferStatus

| Status | Description |
|--------|-------------|
| `pending` | Offer created, waiting for receiver response |
| `accepted` | Receiver accepted, transfer starting |
| `rejected` | Receiver declined the offer |
| `expired` | Offer expired before response |
| `cancelled` | Sender cancelled the offer |
| `transferring` | Files being transferred |
| `completed` | All files transferred successfully |
| `failed` | Transfer failed (see error field) |

---

## Example Usage

### Sending Files

```dart
// 1. User selects files and recipient
final items = [
  SendItem(path: '/home/user/photo.jpg', name: 'photo.jpg', isDirectory: false),
];
final recipient = 'X1BOB';

// 2. Send offer
final offer = await P2PTransferService().sendOffer(
  recipientCallsign: recipient,
  items: items,
);

if (offer != null) {
  print('Offer sent: ${offer.offerId}');
  // Navigate to transfer page to see pending offer
}
```

### Receiving Files

```dart
// 1. Listen for incoming offers
EventBus().on<TransferOfferReceivedEvent>((event) async {
  final offer = P2PTransferService().getOffer(event.offerId);
  if (offer == null) return;

  // 2. Show dialog to user
  final accepted = await IncomingTransferDialog.show(context, offer);

  // Dialog calls acceptOffer/rejectOffer internally
});
```

### Tracking Progress

```dart
// On sender side
EventBus().on<P2PUploadProgressEvent>((event) {
  setState(() {
    uploadProgress = event.progressPercent;
    currentFile = event.currentFile;
  });
});

// On receiver side - progress is shown in TransferPage
```
