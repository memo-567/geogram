# Email Format Specification

**Version**: 1.1
**Last Updated**: 2026-01-13
**Status**: Draft

**Changes in 1.1:**
- Added Station Email Setup Guide with step-by-step instructions
- Added DKIM signing implementation details
- Added troubleshooting section for common email delivery issues
- Documented standalone SMTP client and DKIM signer APIs

## Overview

Geogram Email provides decentralized email functionality using NOSTR-based identity for cryptographic signatures. The station server acts as a relay (not storage), delivering messages between connected clients via WebSocket.

## Multi-Station Architecture

A Geogram client can connect to multiple stations simultaneously. Each station represents a different email domain, giving users multiple email identities.

### Example: User Connected to 3 Stations

```
User "alice" connected to:
  - p2p.radio      → alice@p2p.radio
  - community.net  → alice@community.net
  - local.mesh     → alice@local.mesh
```

### Email Identity Selection

When composing an email, the client must select which station/identity to send from:

```
┌─────────────────────────────────────────────────┐
│ Compose Email                                   │
├─────────────────────────────────────────────────┤
│ From: [alice@p2p.radio        ▼]               │
│       ┌──────────────────────────┐              │
│       │ alice@p2p.radio       ✓ │              │
│       │ alice@community.net     │              │
│       │ alice@local.mesh        │              │
│       └──────────────────────────┘              │
│ To:   [bob@gmail.com                ]           │
│ Subject: [                          ]           │
└─────────────────────────────────────────────────┘
```

### Station-Aware Storage

Emails are organized by the station they were sent/received through:

```
email/
├── stations/
│   ├── p2p.radio/
│   │   ├── inbox/
│   │   ├── outbox/
│   │   ├── sent/
│   │   └── ...
│   ├── community.net/
│   │   ├── inbox/
│   │   ├── outbox/
│   │   ├── sent/
│   │   └── ...
│   └── local.mesh/
│       ├── inbox/
│       └── ...
├── unified/                    # Optional: aggregated view
│   ├── inbox/                  # Symlinks to all station inboxes
│   └── sent/
├── drafts/                     # Drafts are local (not station-specific)
├── garbage/                    # Deleted from any station
├── labels/
└── config.json
```

### Thread Header: STATION Field

Each email thread includes the station it belongs to:

```markdown
# EMAIL: Project Update

STATION: p2p.radio
FROM: alice@p2p.radio
TO: bob@gmail.com
...
```

### Multi-Station Considerations

| Aspect | Handling |
|--------|----------|
| **Sending** | User selects which identity/station to send from |
| **Receiving** | Email routed to correct station folder based on recipient address |
| **Reply** | Auto-select the station that received the original email |
| **Forward** | User can choose different station than original |
| **Drafts** | Stored locally until station is selected for sending |
| **Offline** | Queue per-station; send when that station reconnects |
| **Contacts** | Associate contacts with preferred station for sending |

### WebSocket: Station-Specific Messages

Email messages include the station identifier:

```json
{
  "type": "email_send",
  "station": "p2p.radio",
  "from": "alice@p2p.radio",
  "to": ["bob@gmail.com"],
  "thread_id": "abc123",
  ...
}
```

### Client Implementation Notes

```dart
class EmailAccount {
  final String station;        // "p2p.radio"
  final String localPart;      // "alice"
  final String email;          // "alice@p2p.radio"
  final bool isConnected;
  final WebSocket? connection;

  String get domain => station;
}

class EmailService {
  final Map<String, EmailAccount> _accounts = {};

  /// Get all connected email identities
  List<EmailAccount> get accounts => _accounts.values.toList();

  /// Get account for specific station
  EmailAccount? getAccount(String station) => _accounts[station];

  /// Send email through specific station
  Future<bool> send(String station, EmailThread thread) async {
    final account = _accounts[station];
    if (account == null || !account.isConnected) {
      // Queue for later or return error
      return false;
    }
    // Send via account's WebSocket connection
    return await _sendViaStation(account, thread);
  }

  /// Auto-select station for reply
  String? getReplyStation(EmailThread original) {
    // Use the station that received the original email
    return original.station;
  }
}
```

---

## Directory Structure

```
email/
├── stations/
│   ├── p2p.radio/                              # Station 1
│   │   ├── inbox/
│   │   │   └── 2025/
│   │   │       ├── 2025-01-15_from-alice_project-update/
│   │   │       │   ├── thread.md
│   │   │       │   └── files/
│   │   │       │       └── {sha1}_attachment.pdf
│   │   │       └── 2025-01-16_from-bob_meeting-notes/
│   │   │           └── thread.md
│   │   ├── outbox/
│   │   │   └── 2025-01-15_to-bob_pending-message/
│   │   │       └── thread.md
│   │   ├── sent/
│   │   │   └── 2025/
│   │   │       └── 2025-01-15_to-charlie_project-update/
│   │   │           └── thread.md
│   │   └── spam/
│   │       └── 2025/
│   │
│   ├── community.net/                          # Station 2
│   │   ├── inbox/
│   │   ├── outbox/
│   │   ├── sent/
│   │   └── spam/
│   │
│   └── local.mesh/                             # Station 3
│       ├── inbox/
│       ├── outbox/
│       ├── sent/
│       └── spam/
│
├── drafts/                                     # Local (not station-specific)
│   └── 2025-01-15_draft-proposal/
│       └── thread.md
├── garbage/                                    # Deleted from any station
│   └── 2025/
├── labels/                                     # Cross-station labels
│   ├── work/
│   │   └── refs.json
│   ├── personal/
│   └── important/
└── config.json
```

### Folder Purposes

| Folder | Status | Description |
|--------|--------|-------------|
| stations/{domain}/inbox | `received` | Emails received via that station |
| stations/{domain}/outbox | `pending` | Emails waiting to be delivered via that station |
| stations/{domain}/sent | `sent` | Emails successfully sent via that station |
| stations/{domain}/spam | `spam` | Spam received via that station |
| drafts | `draft` | Unsent compositions (station selected on send) |
| garbage | `deleted` | Deleted emails (auto-cleanup after 30 days) |
| labels | - | Cross-station categories (references to emails) |

### Folder Naming Convention

Email thread folders use the pattern:
```
YYYY-MM-DD_direction-contact_subject-slug/
```

Examples:
- `2025-01-15_from-alice_project-update/`
- `2025-01-15_to-bob_meeting-request/`

---

## Email Thread Format

Each email thread is stored as a `thread.md` file in markdown format, following the same pattern as the chat app.

### Example Thread File

```markdown
# EMAIL: Project Update Discussion

STATION: p2p.radio
FROM: alice@p2p.radio
TO: bob@example.com
CC: charlie@p2p.radio
SUBJECT: Project Update
CREATED: 2025-01-15 14:30_00
STATUS: received
THREAD_ID: abc123def456
LABELS: work, important

> 2025-01-15 14:30_00 -- X1ALICE
Hi Bob,

Here's the project update you requested.
See the attached document for details.

Best regards,
Alice
--> file: {sha1}_project-report.pdf
--> npub: npub1alice...
--> signature: hex_signature_here

> 2025-01-15 15:45_00 -- X1BOB
Thanks Alice!

I've reviewed the document. Looks good.
--> npub: npub1bob...
--> signature: hex_signature_here

> 2025-01-15 16:00_00 -- X1ALICE
Great! Let me know if you need anything else.
--> npub: npub1alice...
--> signature: hex_signature_here
```

### Header Fields

| Field | Required | Description |
|-------|----------|-------------|
| STATION | Yes | Station domain this email belongs to (e.g., `p2p.radio`) |
| FROM | Yes | Sender email/NIP-05 identifier |
| TO | Yes | Primary recipient(s), comma-separated |
| CC | No | Carbon copy recipients |
| BCC | No | Blind carbon copy (stored locally only, never transmitted) |
| SUBJECT | Yes | Email subject line |
| CREATED | Yes | First message timestamp (YYYY-MM-DD HH:MM_ss) |
| STATUS | Yes | `draft`, `pending`, `sent`, `received`, `failed`, `spam`, `deleted` |
| THREAD_ID | Yes | Unique thread identifier |
| LABELS | No | User-defined labels, comma-separated |
| PRIORITY | No | `low`, `normal`, `high` |
| IN_REPLY_TO | No | Parent thread ID for replies |

**Note:** For drafts, STATION may be empty or `local` until the user selects a station to send from.

### Message Format

Messages within a thread follow the chat format:

```
> YYYY-MM-DD HH:MM_ss -- CALLSIGN
Message content here.
Can span multiple lines.
--> metadata_key: metadata_value
--> npub: npub1...
--> signature: hex_signature (MUST be last)
```

### Metadata Fields

| Field | Description |
|-------|-------------|
| file | Attachment filename: `{sha1}_{original_name}` |
| image | Image attachment |
| voice | Voice message with duration |
| duration | Voice/audio duration in seconds |
| lat, lon | Location coordinates |
| npub | Sender's NOSTR public key (bech32) |
| signature | Schnorr signature of message content |
| created_at | Unix timestamp (optional) |
| edited_at | Edit timestamp for modified messages |

---

## Delivery Architecture

### Station as Relay

The station server does NOT store emails permanently. It only:
1. Maintains WebSocket connections to clients
2. Routes messages between connected clients
3. Sends delivery status notifications (DSN)
4. Queues messages temporarily for offline recipients

```
┌─────────────┐     WebSocket     ┌─────────────┐     WebSocket     ┌─────────────┐
│  Client A   │◄──────────────────│   Station   │──────────────────►│  Client B   │
│  (Sender)   │                   │   (Relay)   │                   │ (Recipient) │
│             │                   │             │                   │             │
│ email/sent/ │                   │ Memory only │                   │email/inbox/ │
└─────────────┘                   └─────────────┘                   └─────────────┘
```

### Delivery Flow

1. **Compose**: User writes email → saved to `email/drafts/`
2. **Send**: User clicks send → moves to `email/outbox/`, STATUS = `pending`
3. **Transmit**: Client sends to station via WebSocket
4. **Route**: Station checks recipient connection:
   - **Online**: Forward immediately → move to `email/sent/`, STATUS = `sent`
   - **Offline**: Queue in memory, send `delayed` DSN to sender
5. **Receive**: Recipient client saves to `email/inbox/`

### Delivery Status Notifications (DSN)

Following [RFC 3461](https://datatracker.ietf.org/doc/html/rfc3461) and [RFC 3464](https://datatracker.ietf.org/doc/html/rfc3464):

| Action | Description |
|--------|-------------|
| `delivered` | Message successfully delivered to recipient |
| `delayed` | Recipient offline, station will retry |
| `failed` | Permanent failure (invalid recipient, rejected, timeout) |
| `relayed` | Forwarded to external email system |

#### DSN Message Format

```json
{
  "type": "email_dsn",
  "action": "delayed",
  "thread_id": "abc123def456",
  "recipient": "bob@p2p.radio",
  "reason": "Recipient device offline",
  "will_retry_until": "2025-01-16T14:30:00Z",
  "retry_after": 300
}
```

#### Station Retry Behavior

- Pending emails queued in memory (not persisted to disk)
- Default: retry every 5 minutes for up to 24 hours
- Send `delayed` DSN to sender on first failure
- Send `delivered` DSN when recipient connects and receives
- Send `failed` DSN after timeout expires
- Sender's email remains in `outbox/` until `delivered` or `failed`

### External Email Moderation

**Critical for Spam Prevention**: Emails to external addresses (non-Geogram recipients) require station operator approval before SMTP delivery.

#### Why Moderation is Required

Sending unmoderated emails to external addresses poses serious risks:
- **Domain Blacklisting**: Major email providers will blacklist domains that send spam
- **IP Reputation**: Station's IP address could be added to blocklists
- **Legal Liability**: Station operator may be liable for spam sent through their server
- **Resource Abuse**: Malicious users could abuse the station for spam campaigns

#### Internal vs External Routing

| Recipient Type | Example | Routing |
|----------------|---------|---------|
| Internal (same station) | `bob@p2p.radio` | Direct WebSocket delivery |
| Internal (offline) | `bob@p2p.radio` (offline) | Queue for later delivery |
| External | `someone@gmail.com` | Queue for approval → SMTP |

#### Approval Workflow

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Client    │      │   Station   │      │   Admin     │
│  (Sender)   │      │   Server    │      │  Interface  │
└──────┬──────┘      └──────┬──────┘      └──────┬──────┘
       │                    │                    │
       │ email_send         │                    │
       │ (to: ext@mail.com) │                    │
       ├───────────────────>│                    │
       │                    │                    │
       │                    │ Queue in           │
       │                    │ approval_queue     │
       │                    │                    │
       │ DSN: pending_      │                    │
       │ approval           │                    │
       │<───────────────────┤                    │
       │                    │                    │
       │                    │ Pending emails     │
       │                    │ notification       │
       │                    ├───────────────────>│
       │                    │                    │
       │                    │      approve/      │
       │                    │      reject        │
       │                    │<───────────────────┤
       │                    │                    │
       │                    │ [If approved]      │
       │                    │ Send via SMTP      │
       │                    │                    │
       │ DSN: delivered     │                    │
       │ (or: failed)       │                    │
       │<───────────────────┤                    │
       │                    │                    │
```

#### DSN Actions for External Emails

| Action | Description |
|--------|-------------|
| `pending_approval` | Email queued, awaiting station operator review |
| `delivered` | Email approved and sent via SMTP |
| `failed` | Email rejected by operator (with reason) |
| `blocked` | Sender is on blocklist, email auto-rejected |

#### Allowlist and Blocklist

Station operators can manage trusted/untrusted senders:

- **Allowlist**: Senders who can send external emails without approval
- **Blocklist**: Senders permanently banned from external emails

```dart
// Allowlist a trusted user
emailRelay.addToAllowlist('X1ALICE');

// Block a spammer
emailRelay.addToBlocklist('X1SPAMMER');
```

#### Implementation Status

| Feature | Status |
|---------|--------|
| Internal email routing | ✅ Implemented |
| External email queue | ✅ Implemented |
| Approval/Reject API | ✅ Implemented |
| Allowlist/Blocklist | ✅ Implemented |
| SMTP delivery | ✅ Implemented |
| DKIM signing | ✅ Implemented |
| Admin UI for review | ⏳ TODO |
| Rate limiting | ⏳ TODO |
| Content filtering | ⏳ TODO |

---

## Email Authentication

### NOSTR Signature (Geogram-to-Geogram)

All emails between Geogram clients include cryptographic proof using NOSTR keys:

```markdown
--> npub: npub1abc123...
--> signature: {schnorr_signature}
--> created_at: 1705330200
```

#### Signing Process

1. Extract message content (from `>` header to before first `-->` line)
2. Create NOSTR event with content hash
3. Sign using BIP-340 Schnorr signature with user's nsec
4. Include npub and signature in message metadata

#### Verification Process

1. Extract message content and signature
2. Reconstruct the signed data
3. Verify Schnorr signature against npub using secp256k1
4. Check npub matches sender's registered identity (NIP-05)

#### Verification States

| State | Icon | Description |
|-------|------|-------------|
| Verified | Shield check | Valid NOSTR signature, npub matches sender |
| Unverified | Shield outline | No signature (external email) |
| Invalid | Shield alert | Signature verification failed |
| Mismatch | Shield warning | Signature valid but npub doesn't match From address |

### Traditional Email Authentication

For interoperability with external email systems, Geogram implements these standards:

#### SPF (Sender Policy Framework)

DNS TXT record listing authorized sending IPs:
```
v=spf1 ip4:93.184.216.34 include:_spf.p2p.radio ~all
```
- Validates sending server IP is authorized for domain
- Receiving server checks SPF record in DNS

#### DKIM (DomainKeys Identified Mail)

Cryptographic signature in email headers:
```
DKIM-Signature: v=1; a=rsa-sha256; d=p2p.radio; s=selector1;
    h=from:to:subject:date;
    bh=base64_body_hash;
    b=base64_signature
```
- Private key signs message headers and body
- Public key published in DNS for verification
- Proves message wasn't altered in transit

#### DMARC (Domain-based Message Authentication)

Policy for handling authentication failures:
```
v=DMARC1; p=reject; rua=mailto:dmarc@p2p.radio
```
- Policies: `none` (monitor), `quarantine` (spam folder), `reject` (block)
- Requires SPF OR DKIM to pass with domain alignment
- Provides aggregate reports of authentication results

**Implementation Status:**
- NOSTR signatures: ✅ Implemented (Geogram-to-Geogram)
- DKIM signing: ✅ Implemented (outgoing external email)
- SPF verification: ✅ Supported via DNS
- DMARC policy: ✅ Supported via DNS
- DKIM verification (inbound): ⏳ Planned

---

## WebSocket Protocol

### Email Message Types

#### Send Email

```json
{
  "type": "email_send",
  "thread_id": "abc123def456",
  "to": ["bob@p2p.radio", "charlie@p2p.radio"],
  "subject": "Project Update",
  "content": "base64_encoded_thread_md",
  "attachments": [
    {"name": "report.pdf", "sha1": "abc123...", "size": 102400}
  ],
  "event": {
    "pubkey": "hex_pubkey",
    "created_at": 1705330200,
    "kind": 4,
    "sig": "hex_signature"
  }
}
```

#### Receive Email

```json
{
  "type": "email_receive",
  "from": "alice@p2p.radio",
  "thread_id": "abc123def456",
  "subject": "Project Update",
  "content": "base64_encoded_thread_md",
  "attachments": [
    {"name": "report.pdf", "sha1": "abc123...", "size": 102400}
  ],
  "event": { ... }
}
```

#### Delivery Confirmation

```json
{
  "type": "email_delivered",
  "thread_id": "abc123def456",
  "recipient": "bob@p2p.radio",
  "delivered_at": "2025-01-15T14:35:00Z"
}
```

### Attachment Transfer

Large attachments use chunked transfer to avoid WebSocket message size limits:

1. **Metadata**: Sender includes attachment list with SHA1 hashes
2. **Request**: Station/recipient requests attachment chunks
3. **Transfer**: Sender sends chunks (default 64KB each)
4. **Verify**: Recipient verifies SHA1 hash matches
5. **Deduplicate**: Files with same SHA1 are stored once

```json
{
  "type": "email_attachment_chunk",
  "thread_id": "abc123",
  "sha1": "abc123...",
  "chunk_index": 0,
  "total_chunks": 16,
  "data": "base64_chunk_data"
}
```

---

## File Attachments

### Storage

Attachments are stored in a `files/` subdirectory within each thread folder:
```
email/inbox/2025/2025-01-15_from-alice_update/
├── thread.md
└── files/
    ├── a1b2c3d4_project-report.pdf
    └── e5f6g7h8_screenshot.png
```

### Naming Convention

```
{sha1_first_8_chars}_{original_filename}
```

This enables:
- Deduplication across threads (same SHA1 = same file)
- Human-readable filenames
- Collision avoidance

### Reference in Thread

```markdown
--> file: a1b2c3d4_project-report.pdf
--> image: e5f6g7h8_screenshot.png
```

---

## Labels System

Labels provide flexible organization without duplicating email files.

### Label Folders

```
email/labels/
├── work/
│   └── refs.json
├── personal/
│   └── refs.json
└── important/
    └── refs.json
```

### refs.json Format

```json
{
  "label": "work",
  "color": "#4285f4",
  "threads": [
    "inbox/2025/2025-01-15_from-alice_project-update",
    "sent/2025/2025-01-14_to-bob_meeting-request"
  ]
}
```

### Applying Labels

Labels are stored both in thread metadata and label refs:

1. **In thread.md**: `LABELS: work, important`
2. **In refs.json**: Thread path added to threads array

---

## Configuration

### config.json

```json
{
  "version": "1.0",
  "created": "2025-01-15T10:00:00Z",
  "settings": {
    "signature": "Best regards,\nAlice",
    "default_labels": ["inbox"],
    "garbage_retention_days": 30,
    "spam_auto_delete_days": 7,
    "sync_enabled": true
  },
  "filters": [
    {
      "name": "Work emails",
      "conditions": {"from_contains": "@company.com"},
      "actions": {"add_label": "work"}
    }
  ]
}
```

---

## Code Reuse

The email app reuses components from the chat app per `docs/reusable.md`:

| Component | File | Usage |
|-----------|------|-------|
| ChatFormat | `lib/util/chat_format.dart` | Base parser for thread.md |
| MessageBubbleWidget | `lib/widgets/message_bubble_widget.dart` | Display email messages |
| MessageInputWidget | `lib/widgets/message_input_widget.dart` | Compose replies |
| PhotoViewerPage | `lib/pages/photo_viewer_page.dart` | View image attachments |
| DocumentViewerEditorPage | `lib/pages/document_viewer_editor_page.dart` | View PDF/text attachments |
| FolderTreeWidget | `lib/widgets/inventory/folder_tree_widget.dart` | Navigate folders/labels |

---

## Related Files

| File | Purpose |
|------|---------|
| `lib/services/email_service.dart` | Email CRUD operations |
| `lib/models/email_thread.dart` | Thread data model |
| `lib/models/email_message.dart` | Message data model |
| `lib/util/email_format.dart` | Parse/write thread.md |
| `lib/pages/email_list_page.dart` | Inbox/folder list view |
| `lib/pages/email_thread_page.dart` | Thread conversation view |
| `lib/pages/email_compose_page.dart` | Compose new email |
| `lib/cli/pure_station.dart` | Station email relay handlers |

---

## Dart Email Libraries

Geogram is an off-grid platform that carries everything needed to send and receive email. The station server acts as a complete SMTP server.

### Primary Library: enough_mail

The [enough_mail](https://pub.dev/packages/enough_mail) package provides full IMAP, POP3, and SMTP support for Dart.

```yaml
dependencies:
  enough_mail: ^2.1.7
```

**Supported Protocols:**
| Protocol | RFC | Purpose |
|----------|-----|---------|
| IMAP4 rev1 | RFC 3501 | Read/manage mailboxes |
| SMTP | RFC 5321 | Send emails |
| POP3 | RFC 1939 | Download emails |
| MIME | RFC 2045 | Message format |

**Key Features:**
- High-level API with auto-reconnection
- Low-level protocol access
- DKIM message signing
- OAuth2 token refresh
- Email provider auto-discovery
- Mailbox watching (IMAP IDLE)

**Platforms:** Android, iOS, Linux, macOS, Windows

### Alternative: mailer (SMTP only)

The [mailer](https://pub.dev/packages/mailer) package is simpler for send-only scenarios.

```yaml
dependencies:
  mailer: ^6.6.0
```

**Note:** Does not work on Flutter Web (SMTP requires TCP sockets).

### Related Packages

| Package | Purpose |
|---------|---------|
| [enough_mail_html](https://pub.dev/packages/enough_mail_html) | Generate HTML from MimeMessage |
| [enough_mail_flutter](https://pub.dev/packages/enough_mail_flutter) | Flutter widgets for mail apps |
| [enough_mail_icalendar](https://pub.dev/packages/enough_mail_icalendar) | Calendar invites in emails |

---

## Self-Hosted SMTP Server

The station server operates as a complete, self-contained SMTP server for off-grid email capability.

### Architecture

```
                                    ┌─────────────────────────────────┐
                                    │      Station Server             │
┌──────────────┐                    │  ┌───────────────────────────┐  │
│ External     │◄──── SMTP :25 ────►│  │ SMTP Server (Inbound)    │  │
│ Mail Server  │                    │  │ - Accept connections      │  │
│ (gmx.net)    │                    │  │ - Validate DKIM/SPF       │  │
└──────────────┘                    │  │ - Queue for delivery      │  │
       ▲                            │  └───────────────────────────┘  │
       │                            │              │                   │
       │                            │              ▼                   │
       │                            │  ┌───────────────────────────┐  │
       └──── SMTP (outbound) ◄─────│  │ SMTP Client (Outbound)    │  │
                                    │  │ - MX lookup               │  │
                                    │  │ - DKIM signing            │  │
                                    │  │ - Deliver to external     │  │
                                    │  └───────────────────────────┘  │
                                    │              │                   │
                                    │              ▼                   │
                                    │  ┌───────────────────────────┐  │
┌──────────────┐                    │  │ WebSocket Bridge          │  │
│ Geogram      │◄── WebSocket ─────►│  │ - Route to/from clients   │  │
│ Client       │                    │  │ - DSN notifications       │  │
└──────────────┘                    │  └───────────────────────────┘  │
                                    └─────────────────────────────────┘
```

### Inbound SMTP Server

Receive emails from external servers:

```dart
import 'dart:io';
import 'package:enough_mail/enough_mail.dart';

class StationSmtpServer {
  ServerSocket? _server;

  Future<void> start({int port = 25}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print('SMTP server listening on port $port');

    _server!.listen((socket) {
      _handleConnection(socket);
    });
  }

  Future<void> _handleConnection(Socket socket) async {
    // Send greeting
    socket.write('220 p2p.radio ESMTP Geogram\r\n');

    String? mailFrom;
    List<String> rcptTo = [];
    StringBuffer data = StringBuffer();
    bool inData = false;

    await for (final chunk in socket) {
      final line = String.fromCharCodes(chunk).trim();

      if (inData) {
        if (line == '.') {
          // End of DATA - process email
          await _processInboundEmail(mailFrom!, rcptTo, data.toString());
          socket.write('250 OK\r\n');
          inData = false;
          data.clear();
        } else {
          data.writeln(line);
        }
        continue;
      }

      if (line.startsWith('EHLO') || line.startsWith('HELO')) {
        socket.write('250-p2p.radio\r\n');
        socket.write('250-STARTTLS\r\n');
        socket.write('250 OK\r\n');
      } else if (line.startsWith('MAIL FROM:')) {
        mailFrom = _extractAddress(line);
        socket.write('250 OK\r\n');
      } else if (line.startsWith('RCPT TO:')) {
        rcptTo.add(_extractAddress(line));
        socket.write('250 OK\r\n');
      } else if (line == 'DATA') {
        socket.write('354 Start mail input\r\n');
        inData = true;
      } else if (line == 'QUIT') {
        socket.write('221 Bye\r\n');
        await socket.close();
      }
    }
  }

  Future<void> _processInboundEmail(
    String from,
    List<String> recipients,
    String rawMessage
  ) async {
    final message = MimeMessage.parseFromText(rawMessage);

    // Verify DKIM signature if present
    final dkimValid = await _verifyDkim(message);

    // Verify SPF
    final spfValid = await _verifySPF(from);

    // Route to local Geogram users via WebSocket
    for (final recipient in recipients) {
      await _deliverToLocalUser(recipient, message, dkimValid, spfValid);
    }
  }
}
```

### Outbound SMTP Client

Send emails to external domains:

```dart
import 'package:enough_mail/enough_mail.dart';

class StationSmtpClient {
  final String _domain = 'p2p.radio';
  final DkimSigner _dkimSigner;

  StationSmtpClient(String dkimPrivateKey)
    : _dkimSigner = DkimSigner(
        domain: 'p2p.radio',
        selector: 'mail',
        privateKey: dkimPrivateKey,
      );

  Future<bool> sendToExternal(
    String fromLocal,
    String toExternal,
    String subject,
    String body,
    {List<String>? attachmentPaths}
  ) async {
    // 1. Build MIME message
    final builder = MessageBuilder()
      ..from = [MailAddress(fromLocal, _domain)]
      ..to = [MailAddress(toExternal)]
      ..subject = subject
      ..text = body;

    // Add attachments
    if (attachmentPaths != null) {
      for (final path in attachmentPaths) {
        await builder.addFile(File(path), MediaType.guessFromFileName(path));
      }
    }

    final message = builder.buildMimeMessage();

    // 2. Sign with DKIM
    _dkimSigner.sign(message);

    // 3. Lookup MX record for recipient domain
    final recipientDomain = toExternal.split('@').last;
    final mxRecords = await DnsUtil.lookupMxRecords(recipientDomain);

    if (mxRecords.isEmpty) {
      throw Exception('No MX records for $recipientDomain');
    }

    // 4. Try each MX server in priority order
    for (final mx in mxRecords) {
      try {
        final client = SmtpClient(_domain, isLogEnabled: true);

        // Connect to recipient's mail server
        await client.connectToServer(mx.host, 25, isSecure: false);
        await client.ehlo();

        // Upgrade to TLS if available
        if (client.serverInfo.supportsStartTls) {
          await client.startTls();
        }

        // Send message
        await client.sendMessage(message);
        await client.quit();

        return true; // Success
      } catch (e) {
        print('Failed to send via ${mx.host}: $e');
        continue; // Try next MX
      }
    }

    return false; // All MX servers failed
  }
}
```

### DNS Requirements

For the station to send/receive external email, configure these DNS records:

#### MX Record (Receive)
```
p2p.radio.    IN  MX  10 mail.p2p.radio.
mail.p2p.radio. IN A   <station-ip>
```

#### SPF Record (Authorize sending)
```
p2p.radio.    IN  TXT  "v=spf1 a mx ip4:<station-ip> -all"
```

#### DKIM Record (Public key)
```
mail._domainkey.p2p.radio. IN TXT "v=DKIM1; k=rsa; p=<base64-public-key>"
```

#### DMARC Record (Policy)
```
_dmarc.p2p.radio. IN TXT "v=DMARC1; p=reject; rua=mailto:dmarc@p2p.radio"
```

#### PTR Record (Reverse DNS)
```
<reverse-ip>.in-addr.arpa. IN PTR mail.p2p.radio.
```

### DKIM Key Generation

Generate DKIM keys for the station:

```dart
import 'package:enough_mail/enough_mail.dart';
import 'dart:io';

Future<void> generateDkimKeys(String outputDir) async {
  // Generate RSA key pair (2048-bit recommended)
  final keyPair = await RsaKeyGenerator.generate(2048);

  // Save private key (keep secure on station)
  await File('$outputDir/dkim_private.pem')
    .writeAsString(keyPair.privateKey);

  // Save public key (publish in DNS)
  await File('$outputDir/dkim_public.pem')
    .writeAsString(keyPair.publicKey);

  // Generate DNS TXT record value
  final dnsRecord = 'v=DKIM1; k=rsa; p=${keyPair.publicKeyBase64}';
  await File('$outputDir/dkim_dns.txt').writeAsString(dnsRecord);

  print('DKIM keys generated. Add this TXT record to DNS:');
  print('mail._domainkey.p2p.radio. IN TXT "$dnsRecord"');
}
```

### Email Flow Summary

| Direction | Protocol | Port | Authentication |
|-----------|----------|------|----------------|
| External → Station | SMTP | 25/587 | Verify sender's DKIM/SPF |
| Station → External | SMTP | 25 | Sign with station's DKIM |
| Client → Station | WebSocket | 80/443 | NOSTR signature |
| Station → Client | WebSocket | 80/443 | NOSTR signature |

### Port Requirements

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 25 | SMTP | Inbound | Receive from external servers |
| 25 | SMTP | Outbound | Send to external servers |
| 587 | SMTP/TLS | Inbound | Submission (authenticated users) |
| 465 | SMTPS | Inbound | Implicit TLS (legacy) |
| 993 | IMAPS | Inbound | IMAP access (optional) |
| 995 | POP3S | Inbound | POP3 access (optional) |

**Note:** Many ISPs block outbound port 25. The station may need a VPS or dedicated server with unblocked ports.

---

## Station Email Setup Guide

This section provides step-by-step instructions for setting up email on your Geogram station.

### Prerequisites

Before setting up email, ensure you have:

1. **A domain name** pointed to your station's IP address
2. **SSL configured** on your station (`ssl domain yourdomain.com`)
3. **Port 25 accessible** (check with your hosting provider)
4. **Access to DNS management** for your domain

### Step 1: Configure SSL Domain

First, configure your station's SSL domain if not already done:

```bash
# Connect to your station CLI
geogram-cli --data-dir=/var/geogram

# In the console, set your domain
> ssl domain yourdomain.com
```

This stores the domain in `station_config.json` and is used as the email domain.

### Step 2: Run Email DNS Diagnostics

The `--email-dns` command checks your DNS configuration and generates DKIM keys:

```bash
# Auto-detect domain from station config
geogram-cli --email-dns

# Or specify domain explicitly
geogram-cli --email-dns=yourdomain.com

# With custom data directory
geogram-cli --email-dns --data-dir=/var/geogram
```

This command:
1. Reads the SSL domain from `station_config.json`
2. Generates a 1024-bit RSA DKIM key pair (if not already present)
3. Saves the private key to `station_config.json`
4. Checks all required DNS records
5. Outputs DNS records you need to create

### Step 3: Configure DNS Records

Based on the `--email-dns` output, configure these DNS records:

#### MX Record (Required - Receive Email)

Tells other mail servers where to deliver email for your domain:

```
yourdomain.com.    IN  MX  10  yourdomain.com.
```

Or if using a subdomain for mail:
```
yourdomain.com.    IN  MX  10  mail.yourdomain.com.
mail.yourdomain.com. IN  A   YOUR_SERVER_IP
```

#### SPF Record (Required - Authorize Sending)

Authorizes your server to send email for your domain:

```
yourdomain.com.    IN  TXT  "v=spf1 ip4:YOUR_SERVER_IP mx -all"
```

The `-all` means reject email from unauthorized servers. Use `~all` (soft fail) during testing.

#### DKIM Record (Required - Email Signing)

Publishes your public key for signature verification:

```
geogram._domainkey.yourdomain.com.  IN  TXT  "v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY"
```

The `--email-dns` command outputs the exact record value to use. The public key is approximately 175 characters for a 1024-bit key.

**Important:** Some DNS providers require the TXT value to be split or have length limits. The `--email-dns` output shows the properly formatted record.

#### DMARC Record (Recommended - Policy)

Defines what to do with emails that fail authentication:

```
_dmarc.yourdomain.com.  IN  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com"
```

DMARC policies:
- `p=none` - Monitor only (good for initial setup)
- `p=quarantine` - Send to spam folder
- `p=reject` - Reject failed emails

#### PTR Record (Recommended - Reverse DNS)

Maps your IP back to your domain. This must be configured by your hosting provider:

```
X.X.X.X.in-addr.arpa.  IN  PTR  yourdomain.com.
```

Contact your hosting provider to set up reverse DNS (PTR record) for your server IP.

### Step 4: Verify DNS Configuration

After adding DNS records, wait 5-30 minutes for propagation, then verify:

```bash
geogram-cli --email-dns
```

Expected output:
```
══════════════════════════════════════════════════════════════
  EMAIL DNS DIAGNOSTICS
══════════════════════════════════════════════════════════════

  Domain:    yourdomain.com
  Server IP: 93.184.216.34

──────────────────────────────────────────────────────────────
  RECORD CHECKS
──────────────────────────────────────────────────────────────

  MX     [OK]
         Value: 10 yourdomain.com.

  SPF    [OK]
         Value: v=spf1 ip4:93.184.216.34 mx -all

  DKIM   [OK]
         Value: v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3D...

  DMARC  [OK]
         Value: v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com

  PTR    [WARN]
         Reverse DNS not configured (contact hosting provider)

  SMTP   [OK]
         Value: 220 yourdomain.com ESMTP Geogram

══════════════════════════════════════════════════════════════
```

### Step 5: Enable SMTP

Enable SMTP in your station configuration:

```bash
# In station console
> smtp enable
> smtp port 25
```

Or via API:
```bash
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "smtp_enable"}'
```

### Step 6: Test Email Delivery

Send a test email to verify everything works:

```bash
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{
    "action": "email_send",
    "to": "your-test@gmail.com",
    "subject": "Test from Geogram Station",
    "content": "This is a test email from my Geogram station."
  }'
```

Check the recipient's inbox (and spam folder). If properly configured with DKIM, the email should:
1. Show `dkim=pass` in email headers
2. Show `spf=pass` in email headers
3. Land in inbox (not spam)

### Troubleshooting

#### Email Goes to Spam

Common causes:
1. **Missing DKIM signature** - Verify DKIM key is in `station_config.json`
2. **SPF misconfigured** - Check IP address matches your server
3. **No PTR record** - Contact hosting provider for reverse DNS
4. **New domain** - Reputation builds over time; start with `p=none` DMARC

Check email headers for authentication results:
```
Authentication-Results: mx.google.com;
       dkim=pass header.d=yourdomain.com;
       spf=pass smtp.mailfrom=yourdomain.com;
       dmarc=pass
```

#### DKIM Record Too Long

If your DNS provider rejects the DKIM record:
1. Geogram uses 1024-bit keys (~175 chars) which most providers accept
2. If still too long, check for extra whitespace
3. Some providers require splitting into multiple quoted strings

#### Port 25 Blocked

Many residential ISPs and cloud providers block port 25. Solutions:
1. Use a VPS with unblocked ports (Hetzner, OVH, Vultr)
2. Request port 25 unblock from your provider
3. Use a mail relay service (reduces self-hosting benefits)

#### MX Lookup Fails

If the SMTP client can't find MX records:
1. Verify DNS propagation: `dig MX recipient-domain.com`
2. Check firewall allows outbound DNS (port 53)
3. The SMTP client has hardcoded MX for common domains (Gmail, Yahoo, Proton, etc.)

---

## Implementation Details

### Standalone SMTP Client

Geogram includes a standalone SMTP client (`lib/services/smtp_client.dart`) that doesn't require external mail servers:

```dart
final client = SMTPClient(
  localDomain: 'yourdomain.com',
  timeout: Duration(seconds: 60),
  dkimConfig: DkimConfig(
    privateKeyPem: privateKey,
    selector: 'geogram',
  ),
);

final result = await client.send(
  from: 'user@yourdomain.com',
  to: ['recipient@gmail.com'],
  subject: 'Hello',
  body: 'Message content',
);
```

Features:
- Direct SMTP delivery to recipient mail servers
- Automatic MX record lookup
- DKIM signing of outgoing emails
- Support for attachments
- Hardcoded MX for common domains (Gmail, Yahoo, Outlook, ProtonMail)

### DKIM Signer

The DKIM signer (`lib/util/dkim_signer.dart`) implements RFC 6376:

```dart
final signer = DkimSigner(
  domain: 'yourdomain.com',
  selector: 'geogram',
  privateKeyPem: privateKey,
);

final signature = signer.sign(
  from: 'user@yourdomain.com',
  to: 'recipient@example.com',
  subject: 'Test',
  date: 'Mon, 13 Jan 2026 10:00:00 +0000',
  messageId: '<abc123@yourdomain.com>',
  body: 'Email body content',
);
```

Features:
- RSA-SHA256 algorithm
- Relaxed canonicalization (headers and body)
- Signs: From, To, Subject, Date, Message-ID headers
- Outputs properly formatted DKIM-Signature header

### DKIM Key Generator

Generate DKIM keys using the `DkimKeyGenerator` class:

```dart
import 'package:geogram/services/email_dns_service.dart';

// Generate 1024-bit RSA key pair
final keyPair = DkimKeyGenerator.generate(bitLength: 1024);

// Private key (store securely in station_config.json)
print(keyPair.privateKeyPem);

// Public key for DNS record
print(keyPair.publicKeyBase64);

// Complete DNS record
print(keyPair.dnsRecord);  // v=DKIM1; k=rsa; p=...
```

**Note:** 1024-bit keys are used for DNS compatibility. While 2048-bit is more secure, many DNS providers have TXT record length limits that prevent using longer keys.

### Configuration Storage

DKIM private key is stored in `station_config.json`:

```json
{
  "sslDomain": "yourdomain.com",
  "smtpEnabled": true,
  "smtpPort": 25,
  "dkimPrivateKey": "-----BEGIN RSA PRIVATE KEY-----\nMIIC...\n-----END RSA PRIVATE KEY-----"
}
```

The key is automatically loaded when the station starts and passed to the SMTP client for signing outgoing emails.

### Email Relay Service

The `EmailRelayService` (`lib/services/email_relay_service.dart`) handles email routing:

```dart
// Configuration
final settings = EmailRelaySettings(
  stationDomain: 'yourdomain.com',
  smtpPort: 25,
  smtpEnabled: true,
  dkimPrivateKey: privateKey,
  dkimSelector: 'geogram',
);

final relay = EmailRelayService();
relay.settings = settings;
```

Features:
- Routes internal emails via WebSocket
- Queues external emails for approval
- Sends approved emails via SMTP with DKIM signing
- Handles delivery status notifications (DSN)

---

## Security Considerations

### DKIM Key Security

- **Never share your private key** - It's stored only in `station_config.json`
- **Backup your key** - If lost, you'll need to generate a new one and update DNS
- **Key rotation** - Consider rotating keys annually for security

### External Email Moderation

All emails to external addresses require station operator approval:
- Prevents spam from damaging domain reputation
- Protects against abuse by malicious users
- Station operator can allowlist trusted senders

### Rate Limiting

Consider implementing rate limits to prevent abuse:
- Per-sender limits (e.g., 10 external emails/day)
- Per-recipient limits
- Overall station limits

---

## References

- [RFC 3461 - SMTP DSN Extension](https://datatracker.ietf.org/doc/html/rfc3461)
- [RFC 3464 - DSN Message Format](https://datatracker.ietf.org/doc/html/rfc3464)
- [RFC 5321 - SMTP Protocol](https://datatracker.ietf.org/doc/html/rfc5321)
- [RFC 6376 - DKIM Signatures](https://datatracker.ietf.org/doc/html/rfc6376)
- [RFC 7208 - SPF](https://datatracker.ietf.org/doc/html/rfc7208)
- [RFC 7489 - DMARC](https://datatracker.ietf.org/doc/html/rfc7489)
- [NIP-01 - Basic NOSTR Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-04 - Encrypted Direct Messages](https://github.com/nostr-protocol/nips/blob/master/04.md)
- [NIP-05 - DNS-based Identity](https://github.com/nostr-protocol/nips/blob/master/05.md)
- [enough_mail - Dart Package](https://pub.dev/packages/enough_mail)
- [mailer - Dart Package](https://pub.dev/packages/mailer)
- [Cloudflare - DMARC, DKIM, SPF](https://www.cloudflare.com/learning/email-security/dmarc-dkim-spf/)
