# Centralized Feedback API

**Version**: 1.0
**Status**: Proposal
**Last Updated**: 2025-12-22

## Table of Contents

- [Introduction & Overview](#introduction--overview)
- [Content Type System](#content-type-system)
- [Folder Structure Specification](#folder-structure-specification)
- [Feedback Types](#feedback-types)
- [File Format Specifications](#file-format-specifications)
- [API Endpoints](#api-endpoints)
- [NOSTR Message Format](#nostr-message-format)
- [Authentication & Authorization](#authentication--authorization)
- [Request/Response Examples](#requestresponse-examples)
- [Error Handling](#error-handling)
- [Migration Guide](#migration-guide)
- [Implementation Notes](#implementation-notes)

---

## Introduction & Overview

### Problem Statement

Currently, multiple Geogram apps implement feedback features independently:

- **Alerts**: Has points/likes (`points.txt`), comments, verifications, and subscriptions
- **Blog**: Has only comments, no likes or reactions
- **Forum**: Needs comments, likes, and reactions (not yet implemented)
- **Events**: Will need RSVPs, comments, and reactions (future)

This leads to:
- Code duplication across apps
- Inconsistent file structures (alert `points.txt` vs blog comments)
- Maintenance overhead
- Difficulty adding new feedback types

### Solution

A **centralized feedback API** that:
- Works across all content types (alerts, blog posts, forum threads, events, etc.)
- Uses a consistent folder structure: `{contentPath}/feedback/`
- Provides generic utilities and API endpoints
- Supports NOSTR-signed messages for authentication
- Enables incremental adoption by existing apps

### Benefits

1. **Code Reuse**: Write feedback logic once, use everywhere
2. **Consistency**: Same API and folder structure across all apps
3. **NOSTR Native**: Built for cryptographic authentication and future interoperability
4. **Extensibility**: Easy to add new feedback types (e.g., new emoji reactions)
5. **Maintainability**: Single source of truth for feedback operations

---

## Content Type System

### Supported Content Types

The feedback system is content-type agnostic. It works with:

| Content Type | Description | Example ID |
|--------------|-------------|------------|
| `alert` | Emergency reports and incident alerts | `2025-12-14_15-32_broken-sidewalk` |
| `blog` | Personal blog posts | `2025-12-04_hello-everyone` |
| `forum` | Forum threads and discussions | `2025-12-01_thread-title` |
| `event` | Community events and meetups | `2025-01-15_community-meetup` |
| `place` | Points of interest | `38.7223_-9.1393_cafe-central` |
| `market` | Marketplace listings | `2025-12-10_laptop-for-sale` |
| `custom:{appName}` | Custom app-specific content | `custom:myapp_{id}` |

### Content Identification

Each piece of content is uniquely identified by three components:

1. **Content Type**: The app/category (e.g., `blog`, `alert`)
2. **Content ID**: Unique identifier within that type (e.g., `2025-12-04_hello-everyone`)
3. **Owner Callsign**: The device/user who created it (e.g., `X1ABCD`)

### Path Resolution Examples

Feedback is stored relative to the content's base path:

```
Alert:
devices/X1ABCD/alerts/active/38.7_-9.1/2025-12-14_broken-sidewalk/feedback/

Blog:
devices/X1ABCD/blog/2025/2025-12-04_hello-everyone/feedback/

Forum:
devices/X1ABCD/forum/general/2025-12-01_thread-title/feedback/

Event:
devices/X1ABCD/events/2025/2025-01-15_community-meetup/feedback/
```

---

## Folder Structure Specification

### Standard Feedback Folder

All content types use the same feedback folder structure:

```
{contentPath}/
├── {content-file}                 # Main content (report.txt, post.md, etc.)
├── files/                          # Attachments (optional)
└── feedback/                       # NEW: Centralized feedback folder
    ├── likes.txt                   # One npub per line
    ├── points.txt                  # One npub per line
    ├── dislikes.txt                # One npub per line
    ├── subscribe.txt               # One npub per line
    ├── verifications.txt           # One npub per line (for verifiable content)
    ├── heart.txt                   # Emoji reaction: one npub per line
    ├── thumbs-up.txt               # Emoji reaction: one npub per line
    ├── fire.txt                    # Emoji reaction: one npub per line
    ├── celebrate.txt               # Emoji reaction: one npub per line
    ├── laugh.txt                   # Emoji reaction: one npub per line
    ├── sad.txt                     # Emoji reaction: one npub per line
    ├── surprise.txt                # Emoji reaction: one npub per line
    └── comments/
        └── YYYY-MM-DD_HH-MM-SS_XXXXXX.txt
```

### Key Principles

1. **Flat Structure**: All feedback files stored directly in `feedback/` folder (no nested subfolders except comments)
2. **One npub per line**: All feedback files (except comments) use the same simple format
3. **Auto-cleanup**: Empty feedback files are automatically deleted
4. **Backwards Compatible**: Existing alert and blog structures can migrate gradually

### Example: Blog Post with Feedback

```
devices/X1ABCD/blog/2025/2025-12-04_hello-everyone/
├── post.md                         # Main blog post content
├── files/                          # Optional attachments
│   └── abc123_document.pdf
└── feedback/
    ├── likes.txt                   # 15 npubs (15 likes)
    ├── heart.txt                   # 8 npubs (8 heart reactions)
    ├── thumbs-up.txt               # 12 npubs (12 thumbs up)
    ├── subscribe.txt               # 5 npubs (5 subscribers)
    ├── views.txt                   # 342 view events (87 unique viewers)
    └── comments/
        ├── 2025-12-04_15-30-45_A1B2C3.txt
        ├── 2025-12-04_16-20-12_X9Y8Z7.txt
        └── 2025-12-05_09-15-00_K5L6M7.txt
```

---

## Feedback Types

All feedback files (except comments) use the same format: **one npub per line**.

### Standard Feedback Types

#### 1. Likes (likes.txt)
- **Purpose**: Express general approval, support, or agreement
- **Use Case**: "I like this blog post" or "Good information"
- **UI**: Heart icon or "Like" button
- **Toggleable**: Yes (user can like/unlike)

#### 2. Points (points.txt)
- **Purpose**: Call attention to important content, flag for review
- **Use Case**: "This alert needs immediate attention" (primarily for alerts)
- **UI**: Flag icon or "Point" button
- **Toggleable**: Yes (user can point/unpoint)

#### 3. Dislikes (dislikes.txt)
- **Purpose**: Express disapproval or disagreement
- **Use Case**: "I disagree with this" or "Not helpful"
- **UI**: Thumbs down icon or "Dislike" button
- **Toggleable**: Yes (user can dislike/undislike)

#### 4. Subscribe (subscribe.txt)
- **Purpose**: Follow content for notifications about updates
- **Use Case**: "Notify me when someone comments" or "Follow this discussion"
- **UI**: Bell icon or "Subscribe" button
- **Toggleable**: Yes (user can subscribe/unsubscribe)

#### 5. Verifications (verifications.txt)
- **Purpose**: Confirm truth/validity of content (for verifiable content like alerts)
- **Use Case**: "I can verify this report is accurate"
- **UI**: Checkmark icon or "Verify" button
- **Toggleable**: No (once verified, cannot be unverified)
- **Applicable To**: Alerts, reports, factual content

### Metric Feedback Types

#### 6. Page Views (views.txt)
- **Purpose**: Track page views and content engagement metrics
- **Use Case**: "Track how many times this blog post has been viewed"
- **Behavior**: Multiple entries allowed (not a toggle)
- **Format**: One signed NOSTR event per line (JSON)
- **Tracking**:
  - Total view count (all views including repeats)
  - Unique viewer count (distinct npubs)
  - View timestamps for analytics
- **Applicable To**: Blog posts, forum threads, events, alerts, any content
- **Privacy**: Requires user authentication (npub/nsec) to record

**Key Differences from Toggle Feedback:**
- **Not Toggleable**: Each page view is recorded as a new event
- **Multiple Entries**: Same user can have multiple view events
- **Timestamped**: Each view includes Unix timestamp for analytics
- **Append-Only**: Views are never removed, only added
- **Analytics**: Supports metrics like view trends over time

**File Format** (views.txt):
```
{"id":"abc123...","pubkey":"def456...","created_at":1734912345,"kind":1,"tags":[["e","post-id"],["type","view"]],"content":"view","sig":"789xyz..."}
{"id":"ghi789...","pubkey":"jkl012...","created_at":1734912456,"kind":1,"tags":[["e","post-id"],["type","view"]],"content":"view","sig":"345mno..."}
{"id":"pqr345...","pubkey":"def456...","created_at":1734913567,"kind":1,"tags":[["e","post-id"],["type","view"]],"content":"view","sig":"678stu..."}
```

**View Statistics Available:**
- `total_views`: Total number of view events (including repeat views)
- `unique_viewers`: Number of distinct npubs who viewed
- `first_view`: Unix timestamp of first recorded view
- `latest_view`: Unix timestamp of most recent view

**Example Metrics:**
```
Total Views: 342
Unique Viewers: 87
First View: 2025-12-10 14:23:00 UTC
Latest View: 2025-12-23 09:45:12 UTC
Average Views per Viewer: 3.93
```

### Emoji Reactions

All emoji reactions follow the same pattern: one npub per line in `{emoji-name}.txt`

| Emoji | File | Purpose | Icon |
|-------|------|---------|------|
| Heart | `heart.txt` | Love, care, appreciation | ❤️ |
| Thumbs Up | `thumbs-up.txt` | Approval, agreement | 👍 |
| Fire | `fire.txt` | Excitement, impressive | 🔥 |
| Celebrate | `celebrate.txt` | Celebration, achievement | 🎉 |
| Laugh | `laugh.txt` | Humor, amusement | 😂 |
| Sad | `sad.txt` | Sympathy, sadness | 😢 |
| Surprise | `surprise.txt` | Surprise, shock | 😮 |

**Properties:**
- Users can have multiple different emoji reactions on the same content
- Each emoji type is toggleable independently
- Emoji reactions are additive (not mutually exclusive)

### Comments

**Storage**: `feedback/comments/` subdirectory
**Filename Format**: `YYYY-MM-DD_HH-MM-SS_XXXXXX.txt`
- `YYYY-MM-DD`: Date of comment creation
- `HH-MM-SS`: Time of comment creation (24-hour format)
- `XXXXXX`: 6-character random alphanumeric ID (uppercase A-Z, 0-9)

**Example Filenames**:
```
comments/2025-12-14_15-30-45_A1B2C3.txt
comments/2025-12-14_16-20-12_X9Y8Z7.txt
comments/2025-12-15_09-15-00_K5L6M7.txt
```

**Purpose**: Detailed text feedback with NOSTR signatures
**Properties**: Flat structure (no threading), chronologically ordered

---

## File Format Specifications

### Feedback File Format (likes.txt, points.txt, etc.)

**Encoding**: UTF-8
**Line Ending**: Unix (`\n`)
**Format**: One npub per line

**Example** (`likes.txt`):
```
npub1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890
npub1xyz987wvu654tsr321qpo098nml765kji432hgf210edc098ba765
npub1qwe456rty789uio012asd345fgh678jkl901zxc234vbn567mnb890
```

**Rules**:
- No blank lines
- No comments or metadata
- Each line is a complete npub (63 characters: `npub1` + 58 bech32 characters)
- File is deleted automatically if it becomes empty
- Maximum file size: 1 MB (~15,000 npubs)

### Comment File Format

**File**: `feedback/comments/YYYY-MM-DD_HH-MM-SS_XXXXXX.txt`

**Structure**:
```
AUTHOR: {CALLSIGN}
CREATED: YYYY-MM-DD HH:MM_ss

{Comment content here.
Can span multiple lines.}

--> npub: npub1...
--> signature: {hex_signature}
```

**Fields**:
1. **AUTHOR** (required): Callsign of comment author
2. **CREATED** (required): Timestamp in format `YYYY-MM-DD HH:MM_ss`
3. **Blank line** (required): Separates header from content
4. **Content** (required): Plain text comment (no markdown)
5. **Blank line** (optional): Separates content from signature
6. **npub** (optional): NOSTR public key for verification
7. **signature** (optional): Hex-encoded Schnorr signature

**Example**:
```
AUTHOR: X1ABCD
CREATED: 2025-12-14 15:30_45

This is a great blog post! I really enjoyed reading about your experience.

--> npub: npub1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890
--> signature: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

### NOSTR Signature Format

**npub Format**: `npub1` + 58 bech32 characters (total 63 characters)
**Signature Format**: 128-character hex string (64-byte Schnorr signature)

**Content to Sign** (for comments):
```
SHA256(AUTHOR + "\n" + CREATED + "\n" + content_text)
```

**Verification**:
```dart
final contentToSign = SHA256(author + "\n" + created + "\n" + content);
final isValid = NostrCrypto.schnorrVerify(contentToSign, signature, npub);
```

---

## API Endpoints

### Base Pattern

All feedback endpoints follow this pattern:

```
POST /api/feedback/{contentType}/{contentId}/{action}
GET  /api/feedback/{contentType}/{contentId}
```

### Endpoint: Toggle Feedback

**Pattern**: `POST /api/feedback/{contentType}/{contentId}/{feedbackType}`

Supported feedback types: `like`, `point`, `dislike`, `subscribe`, `verify`, `react/{emoji}`

#### Like Content

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/like`

**Request Body**:
```json
{
  "npub": "npub1abc123...",
  "action": "toggle"
}
```

**Response** (Success - 200):
```json
{
  "success": true,
  "action": "added",
  "liked": true,
  "like_count": 42,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

**Response** (Removed):
```json
{
  "success": true,
  "action": "removed",
  "liked": false,
  "like_count": 41,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### Point Content

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/point`

Same format as `/like`, returns `pointed` and `point_count`.

#### Dislike Content

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/dislike`

Same format as `/like`, returns `disliked` and `dislike_count`.

#### Subscribe to Content

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/subscribe`

**Request Body**:
```json
{
  "npub": "npub1abc123...",
  "action": "subscribe"
}
```

**Response**:
```json
{
  "success": true,
  "subscribed": true,
  "subscriber_count": 8,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### React with Emoji

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/react/{emoji}`

Supported emojis: `heart`, `thumbs-up`, `fire`, `celebrate`, `laugh`, `sad`, `surprise`

**Request Body**:
```json
{
  "npub": "npub1abc123...",
  "action": "toggle"
}
```

**Response**:
```json
{
  "success": true,
  "action": "added",
  "reacted": true,
  "reaction": "heart",
  "reaction_count": 15,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### Verify Content

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/verify`

**Request Body**:
```json
{
  "npub": "npub1abc123...",
  "comment": "I can confirm this report is accurate"
}
```

**Response**:
```json
{
  "success": true,
  "verified": true,
  "verification_count": 5,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

**Note**: Verifications are immutable - once verified, cannot be unverified.

### Endpoint: Record Page View

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/view`

**Purpose**: Track page views for analytics and engagement metrics.

**Request Body**:
```json
{
  "id": "abc123...",
  "pubkey": "def456...",
  "created_at": 1734912345,
  "kind": 1,
  "tags": [
    ["e", "2025-12-04_hello-everyone"],
    ["type", "view"]
  ],
  "content": "view",
  "sig": "789xyz..."
}
```

**Response** (Success - 200):
```json
{
  "success": true,
  "view_recorded": true,
  "total_views": 343,
  "unique_viewers": 87,
  "timestamp": "2025-12-23T10:30:00Z"
}
```

**Response** (Invalid Signature - 401):
```json
{
  "error": "Invalid signature",
  "message": "NOSTR event signature verification failed"
}
```

**Key Differences from Toggle Feedback:**
- Multiple views from same user are allowed (append-only)
- No "toggle" or "remove" action - views are permanent
- Returns both total views and unique viewer count
- Uses NOSTR event format (not just npub) for full auditability

**Example Flow**:
```dart
// Client side: Create and sign view event
final pubkeyHex = NostrCrypto.decodeNpub(npub);
final viewEvent = NostrEvent(
  pubkey: pubkeyHex,
  createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  kind: 1,
  tags: [
    ['e', postId],
    ['type', 'view'],
  ],
  content: 'view',
);
viewEvent.calculateId();
viewEvent.signWithNsec(nsec);

// Send to API
final response = await http.post(
  Uri.parse('http://localhost:17000/api/feedback/blog/$postId/view'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode(viewEvent.toJson()),
);
```

**View Statistics Endpoint**:

**Endpoint**: `GET /api/feedback/{contentType}/{contentId}/stats`

**Response**:
```json
{
  "total_views": 342,
  "unique_viewers": 87,
  "first_view": 1733846580,
  "latest_view": 1734912345,
  "likes": 15,
  "comments": 3,
  "reactions": {
    "heart": 8,
    "thumbs-up": 12,
    "fire": 5
  }
}
```

### Endpoint: Add Comment

**Endpoint**: `POST /api/feedback/{contentType}/{contentId}/comment`

**Request Body**:
```json
{
  "author": "X1ABCD",
  "content": "This is my comment...",
  "npub": "npub1abc123...",
  "signature": "1234567890abcdef..."
}
```

**Response**:
```json
{
  "success": true,
  "comment_id": "2025-12-22_10-30-45_A1B2C3",
  "timestamp": "2025-12-22T10:30:45Z"
}
```

### Endpoint: Get All Feedback

**Endpoint**: `GET /api/feedback/{contentType}/{contentId}`

**Query Parameters**:
- `npub` (optional): User's npub to get personalized state
- `include_comments` (optional): Set to `true` to include comment list (default: `false`)
- `comment_limit` (optional): Max comments to return (default: 20)
- `comment_offset` (optional): Comment pagination offset (default: 0)

**Response**:
```json
{
  "success": true,
  "content_id": "2025-12-04_hello-everyone",
  "content_type": "blog",
  "counts": {
    "likes": 42,
    "points": 8,
    "dislikes": 2,
    "subscribe": 15,
    "verifications": 0,
    "heart": 23,
    "thumbs_up": 18,
    "fire": 12,
    "celebrate": 5,
    "laugh": 3,
    "sad": 0,
    "surprise": 1,
    "comments": 27
  },
  "user_state": {
    "liked": true,
    "pointed": false,
    "disliked": false,
    "subscribed": true,
    "verified": false,
    "heart": true,
    "thumbs_up": false,
    "fire": false,
    "celebrate": false,
    "laugh": false,
    "sad": false,
    "surprise": false
  },
  "comments": [
    {
      "id": "2025-12-22_10-30-45_A1B2C3",
      "author": "X1ABCD",
      "created": "2025-12-22 10:30_45",
      "content": "Great post!",
      "npub": "npub1abc123...",
      "has_signature": true
    }
  ],
  "timestamp": "2025-12-22T10:30:00Z"
}
```

---

## NOSTR Message Format

Feedback actions can optionally be wrapped in NOSTR events for cryptographic verification and relay propagation.

### Event Kinds

| Action | NOSTR Kind | Description |
|--------|------------|-------------|
| Like, Point, Dislike | 7 | Reaction event (NIP-25) |
| Comment | 1 | Text note (NIP-01) |
| Subscribe, Verify | 30078 | Application-specific data (NIP-78) |

### Event Structure for Reactions

**Kind 7** (Reaction):

```json
{
  "kind": 7,
  "pubkey": "{hex_pubkey}",
  "created_at": 1734864600,
  "tags": [
    ["e", "{content_event_id}", "", "root"],
    ["content_type", "blog"],
    ["content_id", "2025-12-04_hello-everyone"],
    ["action", "like"],
    ["owner", "X1ABCD"]
  ],
  "content": "+",
  "sig": "{hex_signature}"
}
```

### Event Structure for Comments

**Kind 1** (Text Note):

```json
{
  "kind": 1,
  "pubkey": "{hex_pubkey}",
  "created_at": 1734864600,
  "tags": [
    ["content_type", "blog"],
    ["content_id", "2025-12-04_hello-everyone"],
    ["owner", "X1ABCD"]
  ],
  "content": "This is my comment...",
  "sig": "{hex_signature}"
}
```

### Event Structure for Subscribe/Verify

**Kind 30078** (Application Data):

```json
{
  "kind": 30078,
  "pubkey": "{hex_pubkey}",
  "created_at": 1734864600,
  "tags": [
    ["d", "feedback:blog:2025-12-04_hello-everyone"],
    ["content_type", "blog"],
    ["content_id", "2025-12-04_hello-everyone"],
    ["action", "subscribe"],
    ["owner", "X1ABCD"]
  ],
  "content": "",
  "sig": "{hex_signature}"
}
```

### Required Tags

All feedback events MUST include these tags:

- `["content_type", "{type}"]` - The content type (blog, alert, etc.)
- `["content_id", "{id}"]` - The content identifier
- `["owner", "{callsign}"]` - The content owner's callsign

Optional tags:
- `["action", "{action}"]` - The feedback action (like, subscribe, etc.)
- `["e", "{event_id}"]` - Reference to original content event (if available)

---

## Authentication & Authorization

### Permission Levels

| Permission Level | Can Do |
|------------------|--------|
| **Public** (any authenticated user) | Add likes, points, dislikes, emoji reactions, comments, subscriptions |
| **Author** (comment author) | Delete own comments |
| **Content Owner** (content creator) | Delete any comment on their content |
| **Admin** (system admin) | All permissions, bulk operations |

### NOSTR Signature Verification

**All feedback operations SHOULD include NOSTR signatures** for:
- Audit trail and accountability
- Spam prevention
- Future relay synchronization
- Cryptographic proof of authorship

**Signature Verification Process**:
1. Extract `npub` and `signature` from request
2. Reconstruct the signed content (varies by feedback type)
3. Convert npub to hex public key
4. Verify using BIP-340 Schnorr signature verification
5. Accept if valid, reject with 422 if invalid

### Rate Limiting

| Action | Limit |
|--------|-------|
| **Comments** | 10 per hour, 100 per day per user |
| **Likes/Reactions** | Unlimited toggles |
| **Points** | Unlimited toggles |
| **Subscriptions** | Unlimited toggles |
| **Verifications** | 1 per content per user (immutable) |

### Authorization Rules

1. **Anyone** can add feedback to published content
2. **Only the author** can delete their own comments
3. **Only the content owner** can delete comments on their content
4. **Verifications are immutable** - cannot be removed once added
5. **Rate limits apply** to prevent spam

---

## Request/Response Examples

### Example 1: Like a Blog Post

**Request**:
```http
POST /api/feedback/blog/2025-12-04_hello-everyone/like
Content-Type: application/json

{
  "npub": "npub1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890",
  "action": "toggle"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "action": "added",
  "liked": true,
  "like_count": 43,
  "timestamp": "2025-12-22T10:30:00Z"
}
```

### Example 2: Add Heart Reaction

**Request**:
```http
POST /api/feedback/alert/2025-12-14_broken-sidewalk/react/heart
Content-Type: application/json

{
  "npub": "npub1xyz987wvu654tsr321qpo098nml765kji432hgf210edc098ba765",
  "action": "toggle"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "action": "added",
  "reacted": true,
  "reaction": "heart",
  "reaction_count": 16,
  "timestamp": "2025-12-22T10:31:00Z"
}
```

### Example 3: Add Comment with Signature

**Request**:
```http
POST /api/feedback/blog/2025-12-04_hello-everyone/comment
Content-Type: application/json

{
  "author": "X1ABCD",
  "content": "Great insights! I especially liked the part about mesh networking.",
  "npub": "npub1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890",
  "signature": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "comment_id": "2025-12-22_10-32-15_K9M2N5",
  "timestamp": "2025-12-22T10:32:15Z"
}
```

### Example 4: Subscribe to Content

**Request**:
```http
POST /api/feedback/forum/2025-12-01_discussion-thread/subscribe
Content-Type: application/json

{
  "npub": "npub1qwe456rty789uio012asd345fgh678jkl901zxc234vbn567mnb890",
  "action": "subscribe"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "subscribed": true,
  "subscriber_count": 24,
  "timestamp": "2025-12-22T10:33:00Z"
}
```

### Example 5: Record Page View

**Request**:
```http
POST /api/feedback/blog/2025-12-04_hello-everyone/view
Content-Type: application/json

{
  "id": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2",
  "pubkey": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
  "created_at": 1734912345,
  "kind": 1,
  "tags": [
    ["e", "2025-12-04_hello-everyone"],
    ["type", "view"]
  ],
  "content": "view",
  "sig": "30440220abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890abc123de"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "view_recorded": true,
  "total_views": 343,
  "unique_viewers": 87,
  "timestamp": "2025-12-23T10:30:00Z"
}
```

**Notes**:
- Page views are append-only (no toggle behavior)
- Same user can record multiple views
- Each view must be a signed NOSTR event
- Returns both total views and unique viewer count
- Useful for analytics and engagement tracking

### Example 6: Get All Feedback

**Request**:
```http
GET /api/feedback/blog/2025-12-04_hello-everyone?npub=npub1abc123...&include_comments=true&comment_limit=5
```

**Response** (200 OK):
```json
{
  "success": true,
  "content_id": "2025-12-04_hello-everyone",
  "content_type": "blog",
  "counts": {
    "likes": 43,
    "points": 8,
    "dislikes": 1,
    "subscribe": 16,
    "verifications": 0,
    "heart": 24,
    "thumbs_up": 19,
    "fire": 13,
    "celebrate": 6,
    "laugh": 4,
    "sad": 0,
    "surprise": 2,
    "comments": 28
  },
  "user_state": {
    "liked": true,
    "pointed": false,
    "disliked": false,
    "subscribed": true,
    "verified": false,
    "heart": true,
    "thumbs_up": false,
    "fire": false,
    "celebrate": false,
    "laugh": false,
    "sad": false,
    "surprise": false
  },
  "comments": [
    {
      "id": "2025-12-22_10-32-15_K9M2N5",
      "author": "X1ABCD",
      "created": "2025-12-22 10:32_15",
      "content": "Great insights! I especially liked the part about mesh networking.",
      "npub": "npub1abc123...",
      "has_signature": true
    },
    {
      "id": "2025-12-21_14-20-30_A5B6C7",
      "author": "Y2EFGH",
      "created": "2025-12-21 14:20_30",
      "content": "Thanks for sharing!",
      "npub": "npub1xyz987...",
      "has_signature": true
    }
  ],
  "timestamp": "2025-12-22T10:35:00Z"
}
```

---

## Error Handling

### Standard Error Codes

| Code | Error Type | Description |
|------|------------|-------------|
| 400 | Bad Request | Missing required fields or invalid parameters |
| 401 | Unauthorized | Missing authentication (npub required) |
| 403 | Forbidden | Insufficient permissions for this action |
| 404 | Not Found | Content not found |
| 422 | Unprocessable Entity | Invalid NOSTR signature or malformed data |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server-side error |

### Error Response Format

All errors return this structure:

```json
{
  "success": false,
  "error": "error_type",
  "message": "Human-readable error message",
  "details": {
    "field": "Additional context",
    "suggestion": "How to fix this error"
  },
  "timestamp": "2025-12-22T10:30:00Z"
}
```

### Example Error Responses

#### 400 Bad Request (Missing Field)

```json
{
  "success": false,
  "error": "missing_field",
  "message": "Required field 'npub' is missing",
  "details": {
    "field": "npub",
    "suggestion": "Include 'npub' field in request body"
  },
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### 404 Not Found

```json
{
  "success": false,
  "error": "content_not_found",
  "message": "Content 'blog/2025-12-99_nonexistent' not found",
  "details": {
    "content_type": "blog",
    "content_id": "2025-12-99_nonexistent"
  },
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### 422 Invalid Signature

```json
{
  "success": false,
  "error": "invalid_signature",
  "message": "NOSTR signature verification failed",
  "details": {
    "npub": "npub1abc123...",
    "suggestion": "Ensure signature was created for this exact content"
  },
  "timestamp": "2025-12-22T10:30:00Z"
}
```

#### 429 Rate Limit Exceeded

```json
{
  "success": false,
  "error": "rate_limit_exceeded",
  "message": "Comment rate limit exceeded: 10 per hour",
  "details": {
    "limit": "10 per hour",
    "retry_after": "2025-12-22T11:30:00Z",
    "suggestion": "Wait 25 minutes before posting another comment"
  },
  "timestamp": "2025-12-22T10:30:00Z"
}
```

---

## Migration Guide

### Overview

Existing apps can migrate incrementally without breaking changes:

**Phase 1** (Months 1-3): Dual-read support, write to new structure
**Phase 2** (Months 3-6): Run migration scripts, continue dual-read
**Phase 3** (Month 6+): New structure only, remove dual-read code

### Migration from Alert System

Current alert structure:
```
alerts/active/38.7_-9.1/2025-12-14_broken-sidewalk/
├── report.txt
├── points.txt                    # Old location
├── comments/                     # Old location
│   └── 2025-12-14_22-15-23_CALLSIGN.txt
└── .reactions/
    └── report.txt
```

New structure:
```
alerts/active/38.7_-9.1/2025-12-14_broken-sidewalk/
├── report.txt
└── feedback/                     # NEW
    ├── points.txt                # Moved from root
    ├── verifications.txt         # Extracted from report.txt VERIFIED_BY field
    ├── subscribe.txt             # Extracted from report.txt SUBSCRIBERS field
    └── comments/                 # Moved from root
        └── 2025-12-14_22-15-23_CALLSIGN.txt
```

**Migration Script**:
```bash
#!/bin/bash
# migrate-alert-feedback.sh

ALERT_PATH="$1"

# Create feedback folder
mkdir -p "$ALERT_PATH/feedback"

# Move points.txt
if [ -f "$ALERT_PATH/points.txt" ]; then
  mv "$ALERT_PATH/points.txt" "$ALERT_PATH/feedback/points.txt"
fi

# Move comments folder
if [ -d "$ALERT_PATH/comments" ]; then
  mv "$ALERT_PATH/comments" "$ALERT_PATH/feedback/comments"
fi

# Extract VERIFIED_BY from report.txt to verifications.txt
if [ -f "$ALERT_PATH/report.txt" ]; then
  grep "^VERIFIED_BY:" "$ALERT_PATH/report.txt" | \
    sed 's/^VERIFIED_BY: //' | \
    tr ',' '\n' | \
    tr -d ' ' | \
    grep -v '^$' > "$ALERT_PATH/feedback/verifications.txt"
fi

# Extract SUBSCRIBERS from report.txt to subscribe.txt
if [ -f "$ALERT_PATH/report.txt" ]; then
  grep "^SUBSCRIBERS:" "$ALERT_PATH/report.txt" | \
    sed 's/^SUBSCRIBERS: //' | \
    tr ',' '\n' | \
    tr -d ' ' | \
    grep -v '^$' > "$ALERT_PATH/feedback/subscribe.txt"
fi

echo "Migration complete for $ALERT_PATH"
```

### Migration from Blog System

Current blog structure:
```
blog/2025/2025-12-04_hello-everyone/
├── post.md
└── comments/                     # Old location
    └── 2025-12-04_15-30-45_CALLSIGN.txt
```

New structure:
```
blog/2025/2025-12-04_hello-everyone/
├── post.md
└── feedback/                     # NEW
    ├── likes.txt                 # NEW (not in old structure)
    ├── heart.txt                 # NEW
    └── comments/                 # Moved from root
        └── 2025-12-04_15-30-45_CALLSIGN.txt
```

**Migration Script**:
```bash
#!/bin/bash
# migrate-blog-feedback.sh

BLOG_PATH="$1"

# Create feedback folder
mkdir -p "$BLOG_PATH/feedback"

# Move comments folder
if [ -d "$BLOG_PATH/comments" ]; then
  mv "$BLOG_PATH/comments" "$BLOG_PATH/feedback/comments"
fi

echo "Migration complete for $BLOG_PATH"
```

### Dual-Read Implementation

During migration, implement dual-read to support both old and new structures:

```dart
// Example: Read points with backwards compatibility
Future<List<String>> readPoints(String contentPath) async {
  // Try new location first
  final newPath = '$contentPath/feedback/points.txt';
  if (await File(newPath).exists()) {
    return FeedbackFolderUtils.readFeedbackFile(contentPath, 'points');
  }

  // Fall back to old location (alerts only)
  final oldPath = '$contentPath/points.txt';
  if (await File(oldPath).exists()) {
    final content = await File(oldPath).readAsString();
    return content.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  return [];
}
```

### Migration Timeline

| Phase | Duration | Actions |
|-------|----------|---------|
| **Phase 1** | Months 1-3 | - Deploy dual-read code<br>- Write new feedback to `feedback/` folder<br>- Continue reading from old locations |
| **Phase 2** | Months 3-6 | - Run migration scripts on all content<br>- Continue dual-read for safety<br>- Monitor for issues |
| **Phase 3** | Month 6+ | - Remove dual-read code<br>- Read only from `feedback/` folder<br>- Delete old feedback files after verification |

---

## Implementation Notes

### Concurrency & Race Condition Prevention

**Problem**: Multiple concurrent HTTP requests can create race conditions in feedback operations, allowing duplicate feedback from the same user.

#### The Race Condition Vulnerability

When multiple requests attempt to add feedback from the same user simultaneously:

```
Timeline:
T0: Request A reads file (user not found)
T1: Request B reads file (user not found) ← Same state!
T2: Request A adds npub, writes file
T3: Request B adds npub, writes file ← DUPLICATE!
```

**Result**: User's npub appears twice in the file, inflating counts and violating the design requirement that users cannot send multiple likes/dislikes to the same content.

#### Solution: File-Based Locking

The `FeedbackFolderUtils` class implements file-based locking to make read-modify-write operations atomic:

```dart
/// Simple file-based lock for atomic feedback operations.
class _FileLock {
  final String lockFilePath;
  static const int maxWaitMs = 5000;
  static const int retryDelayMs = 50;

  _FileLock(String feedbackFilePath) : lockFilePath = '$feedbackFilePath.lock';

  Future<bool> acquire() async {
    final lockFile = File(lockFilePath);
    final startTime = DateTime.now();

    while (true) {
      try {
        // Try to create lock file exclusively (fails if exists)
        await lockFile.create(exclusive: true);
        return true; // Lock acquired
      } catch (e) {
        // Lock file exists, wait and retry
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsed > maxWaitMs) {
          return false; // Timeout
        }
        await Future.delayed(Duration(milliseconds: retryDelayMs));
      }
    }
  }

  Future<void> release() async {
    final lockFile = File(lockFilePath);
    try {
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    } catch (e) {
      // Lock file already deleted, ignore
    }
  }
}
```

#### Protected Operations

All feedback modification methods use locking:

1. **toggleFeedbackEvent()** - Add/remove feedback atomically
2. **addFeedbackEvent()** - Add feedback only if not present
3. **removeFeedbackEvent()** - Remove feedback atomically

Example usage:

```dart
static Future<bool?> toggleFeedbackEvent(
  String contentPath,
  String feedbackType,
  NostrEvent event,
) async {
  // Verify signature before processing
  if (!event.verify()) {
    return null;
  }

  // Acquire lock to prevent race conditions
  final feedbackFilePath = buildFeedbackFilePath(contentPath, feedbackType);
  final lock = _FileLock(feedbackFilePath);

  if (!await lock.acquire()) {
    return null; // Lock timeout, treat as error
  }

  try {
    // CRITICAL SECTION - atomic read-modify-write
    final events = await readFeedbackEvents(contentPath, feedbackType);
    final npub = event.npub;

    // Check if this npub already has feedback
    final existingIndex = events.indexWhere((e) => e.npub == npub);

    if (existingIndex >= 0) {
      // Remove existing feedback
      events.removeAt(existingIndex);
      await writeFeedbackEvents(contentPath, feedbackType, events);
      return false; // Removed
    } else {
      // Add new feedback
      events.add(event);
      await writeFeedbackEvents(contentPath, feedbackType, events);
      return true; // Added
    }
  } finally {
    // Always release lock
    await lock.release();
  }
}
```

#### Test Verification

The race condition fix is validated by `tests/feedback_race_condition_test.dart`:

**Test 1: Concurrent Duplicate Prevention**
- Launches 10 concurrent requests to add the same user's like
- **Expected**: Only 1 succeeds (9 are blocked by locking)
- **Result**: File contains exactly 1 npub (no duplicates)

**Test 2: Concurrent Toggle**
- Launches 20 concurrent toggle requests from same user
- **Expected**: Final state is 0 or 1 npub (no duplicates)
- **Result**: Toggle count matches file state (integrity maintained)

**Test 3: Multiple Users Concurrent**
- 5 different users add feedback simultaneously
- **Expected**: All 5 succeed (different users don't block each other)
- **Result**: File contains 5 unique npubs

#### Lock File Behavior

- **Lock file location**: `{feedbackFilePath}.lock` (e.g., `feedback/likes.txt.lock`)
- **Acquisition timeout**: 5 seconds (returns null on timeout)
- **Retry interval**: 50ms between lock attempts
- **Cleanup**: Lock file automatically deleted in `finally` block
- **Stale locks**: If process crashes, lock file may persist (manual cleanup needed)

#### Performance Implications

- **Best case**: No contention, lock acquired immediately (~1ms overhead)
- **Average case**: 2-3 concurrent requests, wait ~50-100ms
- **Worst case**: Lock timeout at 5 seconds (very unlikely in normal usage)
- **Throughput**: Sequential processing of feedback for same content item

**Note**: Lock contention only occurs when multiple requests modify the **same** feedback file (e.g., `likes.txt` for post X). Different posts or different feedback types are not affected.

---

### Best Practices

1. **Atomic Writes**: Always write to temporary file first, then rename
   ```dart
   final tempFile = File('$path.tmp');
   await tempFile.writeAsString(content);
   await tempFile.rename(path);
   ```

2. **UTF-8 Encoding**: Always use UTF-8 for all text files
   ```dart
   await file.writeAsString(content, encoding: utf8, flush: true);
   ```

3. **File Locks**: Use file locking for concurrent write operations to prevent race conditions

4. **Validation**: Always validate npub format before writing
   ```dart
   bool isValidNpub(String npub) {
     return npub.startsWith('npub1') && npub.length == 63;
   }
   ```

5. **Auto-Cleanup**: Delete empty feedback files automatically
   ```dart
   if (npubs.isEmpty && await file.exists()) {
     await file.delete();
   }
   ```

### Performance Optimization

1. **Caching Counts**: Cache feedback counts in memory with 5-minute TTL
   ```dart
   final cache = <String, CachedCount>{};

   Future<int> getCachedCount(String path, String type) async {
     final key = '$path/$type';
     final cached = cache[key];
     if (cached != null && DateTime.now().difference(cached.timestamp) < Duration(minutes: 5)) {
       return cached.count;
     }
     final count = await FeedbackFolderUtils.getFeedbackCount(path, type);
     cache[key] = CachedCount(count, DateTime.now());
     return count;
   }
   ```

2. **Pagination**: Always paginate comment listings (20-50 per page)

3. **Lazy Loading**: Don't load comment content until needed, only load metadata for lists

4. **File Size Proxy**: Use file size as count proxy without reading
   ```dart
   final fileSize = await file.length();
   final approxCount = fileSize ~/ 65; // Each npub ≈ 65 bytes (63 + newline + rounding)
   ```

### Storage Efficiency

**Estimated Storage per Content**:
- 1,000 likes: ~65 KB (likes.txt)
- 100 comments: ~50 KB (comment files)
- All reactions: ~500 KB (with 1,000 users)
- 10,000 page views: ~2.5 MB (views.txt with full NOSTR events)
- **Total**: ~3-5 MB per popular content item

**Limits**:
- Max 15,000 npubs per feedback file (~1 MB)
- Max 10,000 comments per content (UX limit, not technical)
- Max 100,000 page views per content (~25 MB)
- Total feedback: <50 MB per content item

**Cleanup**:
- Delete empty feedback files automatically
- Archive old subscriptions after 1 year
- Remove comments from deleted content
- Archive old page views (keep only last 90 days for analytics)

### Page View Tracking Usage

Page views are a special metric feedback type that allows multiple entries per user (append-only). Use the `FeedbackFolderUtils` library to record and analyze page views.

#### Recording Page Views

**Client-Side Implementation:**

```dart
import 'package:geogram_desktop/util/feedback_folder_utils.dart';
import 'package:geogram_desktop/util/nostr_event.dart';
import 'package:geogram_desktop/util/nostr_crypto.dart';

/// Record a page view when user opens a blog post
Future<void> recordPageView(String postId, String npub, String nsec) async {
  // Get content path
  final contentPath = BlogFolderUtils.buildPostPath(postId);

  // Create signed view event
  final pubkeyHex = NostrCrypto.decodeNpub(npub);
  final viewEvent = NostrEvent(
    pubkey: pubkeyHex,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    kind: 1, // Text note (NIP-01)
    tags: [
      ['e', postId],  // Reference to content
      ['type', 'view'],  // Tag as view event
    ],
    content: 'view',
  );

  // Calculate ID and sign
  viewEvent.calculateId();
  viewEvent.signWithNsec(nsec);

  // Record view
  final success = await FeedbackFolderUtils.recordViewEvent(
    contentPath,
    viewEvent,
  );

  if (success) {
    print('Page view recorded for post $postId');
  } else {
    print('Failed to record page view (invalid signature)');
  }
}
```

#### Retrieving View Statistics

```dart
/// Get view statistics for a blog post
Future<void> showViewStats(String postId) async {
  final contentPath = BlogFolderUtils.buildPostPath(postId);

  // Get comprehensive view statistics
  final stats = await FeedbackFolderUtils.getViewStats(contentPath);

  print('Total Views: ${stats['total_views']}');
  print('Unique Viewers: ${stats['unique_viewers']}');

  if (stats['first_view'] != null) {
    final firstView = DateTime.fromMillisecondsSinceEpoch(
      stats['first_view'] * 1000,
    );
    print('First View: $firstView');
  }

  if (stats['latest_view'] != null) {
    final latestView = DateTime.fromMillisecondsSinceEpoch(
      stats['latest_view'] * 1000,
    );
    print('Latest View: $latestView');
  }

  // Calculate engagement rate
  if (stats['unique_viewers'] > 0) {
    final viewsPerUser = stats['total_views'] / stats['unique_viewers'];
    print('Average Views per User: ${viewsPerUser.toStringAsFixed(2)}');
  }
}
```

#### Checking User View History

```dart
/// Check if a user has viewed a post
Future<bool> hasUserViewedPost(String postId, String npub) async {
  final contentPath = BlogFolderUtils.buildPostPath(postId);
  return await FeedbackFolderUtils.hasUserViewed(contentPath, npub);
}

/// Get how many times a user viewed a post
Future<int> getUserViewCount(String postId, String npub) async {
  final contentPath = BlogFolderUtils.buildPostPath(postId);
  return await FeedbackFolderUtils.getUserViewCount(contentPath, npub);
}
```

#### View Analytics Example

```dart
/// Generate view analytics for content dashboard
Future<void> generateViewAnalytics(String postId) async {
  final contentPath = BlogFolderUtils.buildPostPath(postId);

  // Get all view events with timestamps
  final viewEvents = await FeedbackFolderUtils.getViewEvents(contentPath);

  // Group views by day
  final viewsByDay = <String, int>{};
  for (final event in viewEvents) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000);
    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    viewsByDay[dateKey] = (viewsByDay[dateKey] ?? 0) + 1;
  }

  // Find peak viewing day
  var peakDay = '';
  var peakViews = 0;
  viewsByDay.forEach((day, count) {
    if (count > peakViews) {
      peakDay = day;
      peakViews = count;
    }
  });

  print('Peak Viewing Day: $peakDay with $peakViews views');

  // Identify most engaged viewers (top 10)
  final viewCountByUser = <String, int>{};
  for (final event in viewEvents) {
    final npub = event.npub;
    viewCountByUser[npub] = (viewCountByUser[npub] ?? 0) + 1;
  }

  final topViewers = viewCountByUser.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('\nTop 10 Most Engaged Viewers:');
  for (var i = 0; i < 10 && i < topViewers.length; i++) {
    final entry = topViewers[i];
    print('${i + 1}. ${entry.key.substring(0, 20)}... : ${entry.value} views');
  }
}
```

#### Best Practices for Page Views

1. **When to Record**: Record a view when the user:
   - Opens the content detail page
   - Spends more than 5 seconds on the page (debounce rapid navigation)
   - Scrolls past 25% of the content (for long posts)

2. **Privacy Considerations**:
   - Page views require authentication (npub/nsec)
   - Anonymous viewing is not tracked
   - Users can see they are being tracked

3. **Performance**:
   - Record views asynchronously (fire-and-forget)
   - Don't block UI on view recording
   - Cache view statistics with 5-minute TTL

4. **Analytics Retention**:
   - Keep detailed view events for 90 days
   - Archive to summary statistics after 90 days
   - Retain total/unique counts indefinitely

### Security Considerations

1. **Input Validation**: Always validate npub format and content length
2. **Signature Verification**: Verify NOSTR signatures for audit trail
3. **Rate Limiting**: Enforce rate limits to prevent spam
4. **Path Traversal**: Sanitize contentId to prevent directory traversal attacks
   ```dart
   String sanitizeContentId(String id) {
     return id.replaceAll('..', '').replaceAll('/', '_');
   }
   ```

5. **File Permissions**: Set appropriate file permissions (644 for files, 755 for directories)

---

## Comment Signing and Verification

### Overview

All comments in the Geogram system **MUST** be cryptographically signed using NOSTR (NIP-01) to prevent forgery and ensure authenticity. A generic `CommentUtils` library (`lib/util/comment_utils.dart`) provides reusable methods for creating, signing, and verifying comments across all apps (blog, alerts, forum, events, etc.).

### Why NOSTR Signatures are Required

1. **Authentication**: Cryptographically proves the comment author's identity
2. **Non-Repudiation**: Author cannot deny writing the comment
3. **Tamper Detection**: Any modification invalidates the signature
4. **Spam Prevention**: Requires valid NOSTR keys to comment
5. **Future Interoperability**: Enables relay synchronization and federation

### CommentUtils Library

#### Location

```
lib/util/comment_utils.dart
```

#### Core Methods

##### 1. Create and Sign a Comment

```dart
import 'package:geogram_desktop/util/comment_utils.dart';
import 'package:geogram_desktop/util/nostr_event.dart';

// Create a signed comment event
final event = CommentUtils.createSignedCommentEvent(
  content: "This is my comment text",
  author: "X1ABCD",
  npub: "npub1abc123...",
  nsec: "nsec1xyz789...",
  contentType: "blog",  // or "alert", "forum", "event", etc.
  contentId: "2025-12-04_hello-everyone",
);

if (event == null) {
  // Invalid keys or signing failed
  return;
}

// Event is now signed and ready to be stored
```

##### 2. Write Comment to Disk

```dart
// Write the signed comment
final commentId = await CommentUtils.writeSignedComment(
  contentPath: "/path/to/blog/2025/2025-12-04_hello-everyone",
  signedEvent: event,
  author: "X1ABCD",
);

if (commentId == null) {
  // Write failed
  return;
}

// Comment stored at:
// /path/to/blog/2025/2025-12-04_hello-everyone/comments/2025-12-23_10-30-45_A1B2C3.txt
```

##### 3. Load and Verify Comments

```dart
// Load all comments (automatically verifies signatures)
final comments = await CommentUtils.loadComments(contentPath);

for (final comment in comments) {
  print('Author: ${comment.author}');
  print('Content: ${comment.content}');
  print('Verified: ${comment.verified}');  // true if signature valid
  print('Has Signature: ${comment.signature != null}');
}
```

##### 4. Get Specific Comment

```dart
final comment = await CommentUtils.getComment(contentPath, commentId);

if (comment != null && comment.verified) {
  // Comment exists and signature is valid
  print(comment.content);
}
```

##### 5. Delete Comment

```dart
final deleted = await CommentUtils.deleteComment(contentPath, commentId);

if (deleted) {
  print('Comment deleted successfully');
}
```

### File Format

Comments are stored as individual text files with this structure:

```
AUTHOR: X1ABCD
CREATED: 2025-12-23 10:30_45
CREATED_AT: 1734954645

This is the comment content.
It can span multiple lines.

---> npub: npub1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890
---> signature: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
```

**Fields**:
- `AUTHOR`: Commenter's callsign (required)
- `CREATED`: Human-readable timestamp in format `YYYY-MM-DD HH:MM_ss` (required)
- `CREATED_AT`: Unix timestamp in seconds - used for exact signature verification (optional but recommended)
- `npub`: NOSTR public key (bech32 encoded, 63 characters) (required)
- `signature`: BIP-340 Schnorr signature (128-character hex string) (required)

**Signature Metadata MUST be last** in the file.

### NOSTR Event Structure for Comments

Comments use **NIP-01 text notes** (kind 1):

```json
{
  "kind": 1,
  "pubkey": "abc123...",
  "created_at": 1734954645,
  "tags": [
    ["e", "2025-12-04_hello-everyone"],
    ["t", "blog-comment"],
    ["callsign", "X1ABCD"],
    ["content_type", "blog"]
  ],
  "content": "This is my comment text",
  "id": "def456...",
  "sig": "789abc..."
}
```

**Tags Explained**:
- `["e", contentId]`: References the content being commented on
- `["t", "{contentType}-comment"]`: Tags it as a comment for this content type
- `["callsign", author]`: Associates comment with callsign
- `["content_type", type]`: Specifies the content type (blog, alert, etc.)

### API Integration

#### Server-Side Verification

When receiving a comment via API, verify the signature:

```dart
import 'package:geogram_desktop/util/nostr_event.dart';
import 'package:geogram_desktop/util/nostr_crypto.dart';

Future<bool> verifyCommentSignature({
  required String content,
  required String npub,
  required String signature,
  required String author,
  required String contentId,
  required String contentType,
  int? createdAt,
}) async {
  try {
    final pubkeyHex = NostrCrypto.decodeNpub(npub);

    // Reconstruct the NOSTR event
    final event = NostrEvent(
      pubkey: pubkeyHex,
      createdAt: createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      kind: 1,  // Text note
      tags: [
        ['e', contentId],
        ['t', '$contentType-comment'],
        ['callsign', author],
        ['content_type', contentType],
      ],
      content: content,
      sig: signature,
    );

    event.calculateId();

    // Verify signature
    return event.verify();
  } catch (e) {
    return false;
  }
}
```

#### API Endpoint Pattern

```dart
// POST /api/blog/{postId}/comment
Future<Map<String, dynamic>> addComment(
  String postId,
  String author,
  String content, {
  required String npub,
  required String signature,
  int? createdAt,
}) async {
  // Verify signature
  final isValid = await verifyCommentSignature(
    content: content,
    npub: npub,
    signature: signature,
    author: author,
    contentId: postId,
    contentType: 'blog',
    createdAt: createdAt,
  );

  if (!isValid) {
    return {
      'error': 'Invalid signature',
      'message': 'Comment signature verification failed',
      'http_status': 401,
    };
  }

  // Create signed event and store
  final event = NostrEvent(
    pubkey: NostrCrypto.decodeNpub(npub),
    createdAt: createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    kind: 1,
    tags: [
      ['e', postId],
      ['t', 'blog-comment'],
      ['callsign', author],
      ['content_type', 'blog'],
    ],
    content: content,
    sig: signature,
  );

  event.calculateId();

  final commentId = await CommentUtils.writeSignedComment(
    contentPath: blogPostPath,
    signedEvent: event,
    author: author,
  );

  return {
    'success': true,
    'comment_id': commentId,
  };
}
```

### Client-Side Integration

#### UI Example

```dart
Future<void> _addComment() async {
  final profile = _profileService.getProfile();

  // Require NOSTR keys
  if (profile.npub.isEmpty || profile.nsec.isEmpty) {
    showError('NOSTR key required to add comments');
    return;
  }

  // Create signed comment event
  final event = CommentUtils.createSignedCommentEvent(
    content: _commentController.text.trim(),
    author: profile.callsign,
    npub: profile.npub,
    nsec: profile.nsec,
    contentType: 'blog',
    contentId: postId,
  );

  if (event == null) {
    showError('Failed to sign comment');
    return;
  }

  // Send to service layer
  final commentId = await _blogService.addComment(
    postId: postId,
    signedEvent: event,
  );

  if (commentId != null) {
    showSuccess('Comment added');
    _reloadComments();
  }
}
```

### Service Layer Pattern

```dart
// BlogService, AlertService, ForumService, etc.
class BlogService {
  Future<String?> addComment({
    required String postId,
    required NostrEvent signedEvent,
  }) async {
    // Verify the event is signed
    if (signedEvent.sig == null || !signedEvent.verify()) {
      return null;
    }

    // Write using generic CommentUtils
    return await CommentUtils.writeSignedComment(
      contentPath: getPostPath(postId),
      signedEvent: signedEvent,
      author: extractAuthorFromEvent(signedEvent),
    );
  }
}
```

### Security Guarantees

✅ **Prevents Forgery**: Cannot create a comment from another user without their private key
✅ **Detects Tampering**: Any modification to content invalidates the signature
✅ **Audit Trail**: All comments have cryptographic proof of authorship
✅ **Future-Proof**: Compatible with NOSTR relays for federation

### Migration from Unsigned Comments

Legacy comments without signatures:
1. Are still loaded and displayed
2. Show as "unverified" in the UI
3. Should be re-signed if edited
4. New comments MUST be signed

```dart
final comment = await CommentUtils.getComment(contentPath, commentId);

if (!comment.verified) {
  // Display warning: "This comment is not cryptographically verified"
  showWarningBadge();
}
```

### Content Type Support

The same `CommentUtils` library works across all content types:

| Content Type | Example Path | Comment Path |
|--------------|--------------|--------------|
| Blog | `blog/2025/post-id/` | `blog/2025/post-id/comments/` |
| Alert | `alerts/active/38.7_-9.1/alert-id/` | `alerts/active/38.7_-9.1/alert-id/comments/` |
| Forum | `forum/general/thread-id/` | `forum/general/thread-id/comments/` |
| Event | `events/2025/event-id/` | `events/2025/event-id/comments/` |

**Same API, same verification, different content types.**

---

## Related Documentation

- [Alert Format Specification](apps/alert-format-specification.md) - Current alert feedback system
- [Blog Format Specification](apps/blog-format-specification.md) - Current blog comment system
- [Chat Format Specification](apps/chat-format-specification.md) - NOSTR signature patterns
- [API Documentation](API.md) - Main API overview

---

## Changelog

### Version 1.1 (2025-12-23)
- Added Comment Signing and Verification section
- Documented CommentUtils library (`lib/util/comment_utils.dart`)
- Specified NOSTR signature requirements for comments
- Provided integration examples for all content types
- Added security guarantees and migration path from unsigned comments

### Version 1.0 (2025-12-22)
- Initial specification
- Designed feedback folder structure
- Defined API endpoints
- NOSTR message format integration
- Migration guide for alerts and blog

---

*This feedback system is part of the Geogram project.*
*License: Apache-2.0*
