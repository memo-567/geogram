# Video Format Specification

**Version**: 1.0
**Last Updated**: 2026-01-13
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Video Format](#video-format)
- [Video Categories Reference](#video-categories-reference)
- [Thumbnails](#thumbnails)
- [Folder Organization](#folder-organization)
- [Remote Videos](#remote-videos)
- [Feedback System](#feedback-system)
- [WebRTC Streaming](#webrtc-streaming)
- [NOSTR Integration](#nostr-integration)
- [Complete Examples](#complete-examples)
- [Parsing Implementation](#parsing-implementation)
- [File Operations](#file-operations)
- [Validation Rules](#validation-rules)
- [Best Practices](#best-practices)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

This document specifies the text-based format used for storing video information in the Geogram system. The videos collection type provides a decentralized video sharing platform where videos are hosted on individual devices and streamed directly via WebRTC.

Unlike centralized platforms like YouTube, video files remain on the source device. Only metadata (title, description, thumbnail) is synced to stations, enabling discovery and search across the network.

### Key Features

- **Decentralized Storage**: Video files stay on source device, not uploaded to servers
- **Metadata Sync**: Only video.txt and thumbnail synced to stations
- **WebRTC Streaming**: Direct peer-to-peer video streaming from source device
- **Multilingual Support**: Titles and descriptions in multiple languages
- **Folder Organization**: Up to 5 levels of subfolders for content organization
- **Optional Location**: Record where video was filmed (coordinates)
- **Rich Metadata**: Author info, social links, websites, tags, categories
- **NOSTR Integration**: Cryptographic signatures for authenticity
- **Save to Device**: Download remote videos for offline viewing
- **No Distance Filter**: Global reach (unlike Places/Alerts)

### Key Differences from Places/Alerts

| Feature | Places | Alerts | Videos |
|---------|--------|--------|--------|
| Distance filtering | Yes (radius slider) | Yes (radius slider) | No |
| Location required | Yes | Yes | Optional |
| File sync | All files | All files | Metadata only |
| Playback | N/A | N/A | WebRTC streaming |
| Organization | Geographic | Geographic + Time | Folders (5 levels) |

## File Organization

### Directory Structure

```
videos/
├── {callsign}/                           # Current user's videos
│   ├── video.txt                         # Optional: channel/profile metadata
│   ├── my-first-video/
│   │   ├── video.txt                     # Video metadata
│   │   ├── thumbnail.jpg                 # Preview image
│   │   └── video.mp4                     # Actual video file (local only)
│   ├── travel/                           # Level 1 folder
│   │   ├── folder.txt                    # Optional: folder metadata
│   │   ├── portugal/                     # Level 2 folder
│   │   │   ├── lisbon-tour/
│   │   │   │   ├── video.txt
│   │   │   │   ├── thumbnail.jpg
│   │   │   │   └── video.mp4
│   │   │   └── sintra-palace/
│   │   │       ├── video.txt
│   │   │       ├── thumbnail.jpg
│   │   │       └── video.mp4
│   │   └── spain/                        # Level 2 folder
│   │       └── madrid-visit/
│   │           ├── video.txt
│   │           ├── thumbnail.jpg
│   │           └── video.mp4
│   └── tutorials/                        # Another level 1 folder
│       └── cooking/                      # Level 2
│           └── pasta-recipe/
│               ├── video.txt
│               ├── thumbnail.jpg
│               └── video.mp4
├── {remote-callsign}/                    # Saved videos from remote device
│   └── saved-video/
│       ├── video.txt                     # Metadata only (no video file)
│       └── thumbnail.jpg
└── cache.json                            # Video metadata cache
```

### Folder Depth Limits

- **Maximum depth**: 5 levels of subfolders
- **Level 0**: `videos/{callsign}/` (root)
- **Level 1-5**: User-created folders for organization
- **Videos**: Can be placed at any level

**Example paths**:
```
videos/CR7BBQ/my-video/                           # Level 0
videos/CR7BBQ/travel/portugal-trip/               # Level 1
videos/CR7BBQ/travel/europe/portugal/lisbon/      # Level 3
videos/CR7BBQ/a/b/c/d/e/deep-video/               # Level 5 (maximum)
```

### Video Folder Naming

**Pattern**: `{sanitized-title}/`

**Sanitization Rules**:
1. Convert to lowercase
2. Replace spaces and underscores with hyphens
3. Remove non-alphanumeric characters (except hyphens)
4. Collapse multiple consecutive hyphens
5. Remove leading/trailing hyphens
6. Truncate to 50 characters

**Examples**:
```
"My First Video!" → my-first-video/
"Travel Vlog #123" → travel-vlog-123/
"Cooking: Pasta Recipe" → cooking-pasta-recipe/
```

## Video Format

### Main Video File

Every video must have a `video.txt` file in the video folder.

**Complete Structure (Single Language)**:
```
# VIDEO: Video Title

CREATED: YYYY-MM-DD HH:MM_ss
EDITED: YYYY-MM-DD HH:MM_ss (optional)
AUTHOR: CALLSIGN

DURATION: seconds
RESOLUTION: widthxheight
FILE_SIZE: bytes
MIME_TYPE: video/mp4

COORDINATES: lat,lon (optional)
TAGS: tag1, tag2, tag3
CATEGORY: entertainment
VISIBILITY: public

ALLOWED_GROUPS: group1, group2 (only if VISIBILITY: restricted)
ALLOWED_USERS: npub1..., npub2... (only if VISIBILITY: restricted)

WEBSITES: https://example.com, https://another.com (optional)
SOCIAL: @twitter, youtube.com/channel (optional)
CONTACT: email@example.com (optional)

Video description goes here.
Simple plain text format.
No markdown formatting.

Can include multiple paragraphs.
Each paragraph separated by blank line.

--> npub: npub1...
--> signature: hex_signature
```

**Complete Structure (Multilingual)**:
```
# VIDEO_EN: Video Title in English
# VIDEO_PT: Titulo do Video em Portugues
# VIDEO_ES: Titulo del Video en Espanol

CREATED: YYYY-MM-DD HH:MM_ss
EDITED: YYYY-MM-DD HH:MM_ss (optional)
AUTHOR: CALLSIGN

DURATION: 180
RESOLUTION: 1920x1080
FILE_SIZE: 52428800
MIME_TYPE: video/mp4

COORDINATES: 38.7223,-9.1393
TAGS: travel, portugal, lisbon
CATEGORY: travel
VISIBILITY: public

WEBSITES: https://myblog.com
SOCIAL: @myhandle, youtube.com/@mychannel

[EN]
Video description in English.
Multiple paragraphs allowed.

[PT]
Descricao do video em Portugues.
Varios paragrafos permitidos.

[ES]
Descripcion del video en Espanol.
Se permiten multiples parrafos.

--> npub: npub1...
--> signature: hex_signature
```

### Header Section

1. **Title Line** (required)
   - **Single Language**: `# VIDEO: <title>`
   - **Multilingual**: `# VIDEO_XX: <title>` (XX = language code)
   - **Examples**:
     - Single: `# VIDEO: My Portugal Trip`
     - Multi: `# VIDEO_EN: My Portugal Trip`
     - Multi: `# VIDEO_PT: Minha Viagem a Portugal`
   - **Constraints**: Any length, truncated in folder name to 50 chars
   - **Fallback**: Requested language → English (EN) → First available

2. **Blank Line** (required)
   - Separates title from metadata

3. **Created Timestamp** (required)
   - **Format**: `CREATED: YYYY-MM-DD HH:MM_ss`
   - **Example**: `CREATED: 2026-01-13 10:00_00`
   - **Note**: Underscore before seconds

4. **Edited Timestamp** (optional)
   - **Format**: `EDITED: YYYY-MM-DD HH:MM_ss`
   - **Example**: `EDITED: 2026-01-14 15:30_00`
   - **Purpose**: Track when metadata was last modified

5. **Author Line** (required)
   - **Format**: `AUTHOR: <callsign>`
   - **Example**: `AUTHOR: CR7BBQ`
   - **Constraints**: Alphanumeric callsign

### Video Metadata Section

6. **Duration** (required)
   - **Format**: `DURATION: <seconds>`
   - **Example**: `DURATION: 180` (3 minutes)
   - **Constraints**: Positive integer

7. **Resolution** (required)
   - **Format**: `RESOLUTION: <width>x<height>`
   - **Examples**: `RESOLUTION: 1920x1080`, `RESOLUTION: 3840x2160`
   - **Common values**: 640x480, 1280x720, 1920x1080, 3840x2160

8. **File Size** (required)
   - **Format**: `FILE_SIZE: <bytes>`
   - **Example**: `FILE_SIZE: 52428800` (50 MB)
   - **Constraints**: Positive integer in bytes

9. **MIME Type** (required)
   - **Format**: `MIME_TYPE: <type>`
   - **Examples**: `video/mp4`, `video/webm`, `video/quicktime`
   - **Supported types**: video/mp4, video/webm, video/quicktime, video/x-msvideo, video/x-matroska

### Optional Metadata

10. **Coordinates** (optional)
    - **Format**: `COORDINATES: <lat>,<lon>`
    - **Example**: `COORDINATES: 38.7223,-9.1393`
    - **Purpose**: Where video was recorded
    - **Precision**: Up to 6 decimal places

11. **Tags** (optional)
    - **Format**: `TAGS: <tag1>, <tag2>, <tag3>`
    - **Example**: `TAGS: travel, portugal, lisbon, tourism`
    - **Constraints**: Comma-separated, lowercase recommended
    - **Purpose**: Enable search and filtering

12. **Category** (required)
    - **Format**: `CATEGORY: <category>`
    - **Example**: `CATEGORY: travel`
    - **Purpose**: Primary categorization
    - **Note**: See [Video Categories Reference](#video-categories-reference)

13. **Visibility** (required)
    - **Format**: `VISIBILITY: <level>`
    - **Values**:
      - `public` - Visible to everyone, appears in listings and search
      - `private` - Only visible to the author
      - `unlisted` - Not shown in listings, but accessible via direct link
      - `restricted` - Only visible to specified groups or users
    - **Default**: `public`
    - **Examples**:
      - `VISIBILITY: public`
      - `VISIBILITY: unlisted`
      - `VISIBILITY: restricted`

14. **Allowed Groups** (conditional)
    - **Format**: `ALLOWED_GROUPS: <group1>, <group2>`
    - **Example**: `ALLOWED_GROUPS: family, close-friends`
    - **Required when**: `VISIBILITY: restricted`
    - **Purpose**: Specify which groups can view the video

15. **Allowed Users** (conditional)
    - **Format**: `ALLOWED_USERS: <npub1>, <npub2>`
    - **Example**: `ALLOWED_USERS: npub1abc..., npub1xyz...`
    - **Required when**: `VISIBILITY: restricted` (if no groups specified)
    - **Purpose**: Specify individual users who can view the video
    - **Note**: Use NOSTR public keys (npub format)

16. **Websites** (optional)
    - **Format**: `WEBSITES: <url1>, <url2>`
    - **Example**: `WEBSITES: https://myblog.com, https://myportfolio.com`
    - **Purpose**: Author's websites or related links

17. **Social** (optional)
    - **Format**: `SOCIAL: <account1>, <account2>`
    - **Examples**:
      - `SOCIAL: @twitter_handle`
      - `SOCIAL: youtube.com/@channel, instagram.com/user`
    - **Purpose**: Author's social media presence

18. **Contact** (optional)
    - **Format**: `CONTACT: <contact info>`
    - **Example**: `CONTACT: contact@example.com`
    - **Purpose**: How to reach the author

### Content Section

The content section contains the video description.

**Single Language Format**:
```
Description text here.
Multiple paragraphs allowed.

Each paragraph separated by blank line.
```

**Multilingual Format**:
```
[EN]
Description in English.
Multiple paragraphs allowed.

[PT]
Descricao em Portugues.
Varios paragrafos permitidos.
```

**Language Codes**:
- **EN**: English
- **PT**: Portugues (Portuguese)
- **ES**: Espanol (Spanish)
- **FR**: Francais (French)
- **DE**: Deutsch (German)
- **IT**: Italiano (Italian)
- **NL**: Nederlands (Dutch)
- **RU**: Russkij (Russian)
- **ZH**: Zhongwen (Chinese)
- **JA**: Nihongo (Japanese)
- **AR**: Arabiya (Arabic)

**Fallback Behavior**:
1. Display content in requested language
2. If not available, fall back to English (EN)
3. If English not available, use first available language

### Video Metadata Footer

```
--> npub: npub1abc123...
--> signature: hex_signature_string...
```

- **npub**: NOSTR public key (optional)
- **signature**: NOSTR signature (must be last if present)

## Video Categories Reference

### Entertainment
- **entertainment**: General entertainment
- **comedy**: Comedy and humor
- **music**: Music videos, performances
- **gaming**: Video game content
- **movies**: Movie clips, reviews
- **shows**: TV show content
- **animation**: Animated content

### Education
- **education**: General educational content
- **tutorial**: How-to guides and tutorials
- **course**: Educational courses
- **lecture**: Academic lectures
- **documentary**: Documentaries
- **science**: Science content
- **history**: Historical content
- **language**: Language learning

### Lifestyle
- **travel**: Travel vlogs and guides
- **food**: Cooking, recipes, food reviews
- **fitness**: Workout and fitness content
- **fashion**: Fashion and style
- **beauty**: Beauty and makeup
- **home**: Home improvement, DIY
- **garden**: Gardening content
- **pets**: Pet-related content

### Technology
- **tech**: General technology
- **programming**: Coding and software
- **hardware**: Computer hardware
- **gadgets**: Device reviews
- **apps**: Application reviews
- **ai**: Artificial intelligence

### News & Information
- **news**: News coverage
- **politics**: Political content
- **business**: Business and finance
- **sports**: Sports coverage
- **weather**: Weather reports

### Creative
- **art**: Art and creative content
- **photography**: Photography content
- **film**: Filmmaking
- **design**: Design content
- **craft**: Crafts and handmade

### Personal
- **vlog**: Personal video blogs
- **family**: Family content
- **events**: Event recordings
- **memories**: Personal memories

### Other
- **other**: Uncategorized content

## Thumbnails

### Requirements

- **Filename**: `thumbnail.jpg` or `thumbnail.png`
- **Location**: Same folder as `video.txt`
- **Format**: JPEG (preferred) or PNG
- **Aspect ratio**: 16:9 recommended (matches video)
- **Resolution**: 1280x720 recommended, minimum 640x360
- **File size**: Under 500 KB recommended

### Auto-Generation

When adding a new video, the system can auto-generate a thumbnail:
1. Extract frame at 10% of video duration
2. Scale to 1280x720
3. Save as `thumbnail.jpg`

### Manual Override

Users can replace auto-generated thumbnails with custom images.

## Folder Organization

### Folder Metadata

Folders can optionally have a `folder.txt` file:

```
# FOLDER: Folder Name

CREATED: YYYY-MM-DD HH:MM_ss
AUTHOR: CALLSIGN

Optional folder description.
```

### Folder Naming

Same sanitization rules as video folders:
- Lowercase
- Hyphens instead of spaces
- Alphanumeric only
- Max 50 characters

### Navigation

- Users can browse folders like a file system
- Breadcrumb navigation shows current path
- Videos can be moved between folders

## Remote Videos

### Station Sync

When publishing a video to stations:
1. **Synced**: `video.txt`, `thumbnail.jpg`
2. **NOT synced**: Actual video file (`.mp4`, `.webm`, etc.)

The video file remains on the source device.

### Discovery

Other users discover videos through:
1. Station search (searches metadata)
2. Browsing remote callsigns
3. Tag/category filtering

### Save to Device

When a user "saves" a remote video:
1. Downloads `video.txt` and `thumbnail.jpg`
2. Stores in `videos/{remote-callsign}/{video-folder}/`
3. Video file is NOT downloaded (streams on demand)

### Optional Full Download

Users can optionally download the full video:
1. Request video file via station proxy
2. Download stored locally
3. Mark as "downloaded" in metadata

## Feedback System

### Video-Level Feedback

Stored under `feedback/` directory:

```
videos/{callsign}/{video-folder}/
├── video.txt
├── thumbnail.jpg
├── video.mp4
└── feedback/
    ├── likes.txt
    ├── points.txt
    └── comments/
        └── YYYY-MM-DD_HH-MM-SS_AUTHOR.txt
```

### Likes Format

```
# LIKES

CALLSIGN1: 2026-01-13 10:00_00
--> npub: npub1...
--> signature: hex...

CALLSIGN2: 2026-01-13 11:30_00
--> npub: npub1...
--> signature: hex...
```

### Comments Format

Individual files per comment:

```
# COMMENT

CREATED: 2026-01-13 10:00_00
AUTHOR: CALLSIGN

Comment text here.
Can have multiple paragraphs.

--> npub: npub1...
--> signature: hex...
```

## WebRTC Streaming

### Architecture

```
┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│   Viewer     │────▶│   Station   │────▶│  Video Host  │
│ (Consumer)   │◀────│  (Signal)   │◀────│  (Provider)  │
└──────────────┘     └─────────────┘     └──────────────┘
                           │
                           ▼
                    WebRTC Signaling
                    (offer/answer/ICE)
```

### Flow

1. **Discovery**: Viewer finds video via station search
2. **Request**: Viewer requests stream through station
3. **Signaling**: Station relays WebRTC offer/answer
4. **Connection**: Direct peer-to-peer connection established
5. **Streaming**: Video streams directly from host to viewer

### Web Browser Support

Web browsers can also stream videos:
1. Station provides WebRTC endpoint
2. Browser connects via JavaScript
3. Same peer-to-peer streaming

### Fallback

If WebRTC fails:
1. Attempt HTTP progressive download
2. If host allows, download full file

## NOSTR Integration

### Event Signing

Video metadata can be signed using NOSTR:

```
--> npub: npub1abc123...
--> signature: hex_signature_of_content
```

### Verification

1. Extract content before `-->` lines
2. Verify signature matches npub
3. Display verification badge in UI

### Event Types

- **Video publish**: kind 30078 (NIP-78)
- **Like/reaction**: kind 7
- **Comment**: kind 1

## Complete Examples

### Minimal Video

```
# VIDEO: Quick Test

CREATED: 2026-01-13 10:00_00
AUTHOR: CR7BBQ

DURATION: 30
RESOLUTION: 1280x720
FILE_SIZE: 5242880
MIME_TYPE: video/mp4

CATEGORY: other

A quick test video.
```

### Full Featured Video (Single Language)

```
# VIDEO: Lisbon Walking Tour - Historic Downtown

CREATED: 2026-01-13 10:00_00
EDITED: 2026-01-14 15:30_00
AUTHOR: CR7BBQ

DURATION: 1800
RESOLUTION: 3840x2160
FILE_SIZE: 2147483648
MIME_TYPE: video/mp4

COORDINATES: 38.7223,-9.1393
TAGS: travel, portugal, lisbon, walking-tour, 4k, downtown
CATEGORY: travel

WEBSITES: https://mytravelblog.com, https://patreon.com/mytravels
SOCIAL: @mytravels, youtube.com/@mytravels, instagram.com/mytravels
CONTACT: hello@mytravelblog.com

Join me on a walking tour through Lisbon's historic downtown area.
We'll explore the famous Baixa district, visit Praca do Comercio,
and walk up to the iconic Santa Justa Elevator.

This video was filmed in 4K resolution using a gimbal stabilizer.
Perfect for anyone planning a trip to Lisbon or just wanting to
experience the city from home.

Timestamps:
- 0:00 Introduction
- 2:30 Rossio Square
- 8:00 Rua Augusta
- 15:00 Praca do Comercio
- 22:00 Santa Justa Elevator
- 28:00 Conclusion

--> npub: npub1abc123def456...
--> signature: 3045022100...
```

### Multilingual Video

```
# VIDEO_EN: Portuguese Cuisine: Traditional Bacalhau Recipe
# VIDEO_PT: Cozinha Portuguesa: Receita Tradicional de Bacalhau

CREATED: 2026-01-13 10:00_00
AUTHOR: CR7BBQ

DURATION: 900
RESOLUTION: 1920x1080
FILE_SIZE: 524288000
MIME_TYPE: video/mp4

COORDINATES: 38.7223,-9.1393
TAGS: cooking, portuguese, bacalhau, recipe, traditional
CATEGORY: food

WEBSITES: https://portuguesecuisine.com
SOCIAL: @ptcuisine

[EN]
Learn how to prepare traditional Portuguese Bacalhau a Bras.
This classic dish combines salted cod with eggs, potatoes,
and onions for a delicious meal.

Ingredients:
- 400g salted cod (desalted)
- 4 eggs
- 500g potatoes
- 2 onions
- Olive oil
- Parsley

[PT]
Aprenda a preparar o tradicional Bacalhau a Bras.
Este prato classico combina bacalhau com ovos, batatas,
e cebolas para uma refeicao deliciosa.

Ingredientes:
- 400g de bacalhau (demolhado)
- 4 ovos
- 500g de batatas
- 2 cebolas
- Azeite
- Salsa

--> npub: npub1abc123def456...
--> signature: 3045022100...
```

### Private Family Video

```
# VIDEO: Birthday Party 2026

CREATED: 2026-01-13 14:00_00
AUTHOR: CR7BBQ

DURATION: 3600
RESOLUTION: 1920x1080
FILE_SIZE: 1073741824
MIME_TYPE: video/mp4

TAGS: family, birthday, celebration
CATEGORY: family
VISIBILITY: restricted

ALLOWED_GROUPS: family
ALLOWED_USERS: npub1abc123..., npub1def456...

Recording of grandma's 80th birthday party.
Only shared with family members.

--> npub: npub1abc123def456...
--> signature: 3045022100...
```

### Unlisted Video (Shareable Link)

```
# VIDEO: Project Demo for Client

CREATED: 2026-01-13 09:00_00
AUTHOR: CR7BBQ

DURATION: 600
RESOLUTION: 1920x1080
FILE_SIZE: 314572800
MIME_TYPE: video/mp4

TAGS: demo, project, presentation
CATEGORY: business
VISIBILITY: unlisted

Demo video for client review.
Not listed publicly, but anyone with the link can view.

--> npub: npub1abc123def456...
--> signature: 3045022100...
```

## Parsing Implementation

### Dart Parser (Pseudo-code)

```dart
Video? parseVideoContent({
  required String content,
  required String filePath,
  required String folderPath,
}) {
  final lines = content.split('\n');

  // Parse titles (single or multilingual)
  final titles = <String, String>{};
  String? singleTitle;

  for (final line in lines) {
    if (line.startsWith('# VIDEO:')) {
      singleTitle = line.substring(9).trim();
    } else if (line.startsWith('# VIDEO_')) {
      final langCode = line.substring(8, 10);
      final title = line.substring(12).trim();
      titles[langCode] = title;
    }
  }

  // Parse metadata fields
  final metadata = <String, String>{};
  for (final line in lines) {
    if (line.contains(':') && !line.startsWith('#') && !line.startsWith('[')) {
      final colonIndex = line.indexOf(':');
      final key = line.substring(0, colonIndex).trim().toUpperCase();
      final value = line.substring(colonIndex + 1).trim();
      metadata[key] = value;
    }
  }

  // Parse descriptions (single or multilingual)
  final descriptions = parseDescriptions(content);

  // Build Video object
  return Video(
    title: singleTitle ?? titles['EN'] ?? titles.values.first,
    titles: titles.isEmpty ? {'EN': singleTitle!} : titles,
    created: metadata['CREATED'] ?? '',
    author: metadata['AUTHOR'] ?? '',
    durationSeconds: int.tryParse(metadata['DURATION'] ?? '0') ?? 0,
    resolution: metadata['RESOLUTION'] ?? '',
    fileSizeBytes: int.tryParse(metadata['FILE_SIZE'] ?? '0') ?? 0,
    mimeType: metadata['MIME_TYPE'] ?? 'video/mp4',
    // ... other fields
  );
}
```

## File Operations

### Create Video

1. Validate required fields
2. Generate sanitized folder name from title
3. Create video folder at specified path (respecting 5-level limit)
4. Extract/generate thumbnail
5. Copy video file
6. Write `video.txt`
7. Sign with NOSTR if available

### Update Video

1. Read existing `video.txt`
2. Update metadata fields
3. Update EDITED timestamp
4. Re-sign with NOSTR
5. Write updated `video.txt`

### Delete Video

1. Remove entire video folder
2. Update cache if exists

### Publish to Station

1. Read `video.txt`
2. Read `thumbnail.jpg`
3. Upload to station API (metadata + thumbnail only)
4. Do NOT upload video file

## Validation Rules

### Required Fields

- Title (at least one language)
- CREATED timestamp
- AUTHOR callsign
- DURATION (positive integer)
- RESOLUTION (format: WxH)
- FILE_SIZE (positive integer)
- MIME_TYPE (valid video MIME)
- CATEGORY (from allowed list)
- VISIBILITY (public, private, unlisted, or restricted)

### Field Constraints

| Field | Constraint |
|-------|------------|
| Title | Non-empty, any length |
| Created | Format: YYYY-MM-DD HH:MM_ss |
| Author | Alphanumeric callsign |
| Duration | Positive integer (seconds) |
| Resolution | Format: WxH (e.g., 1920x1080) |
| File Size | Positive integer (bytes) |
| MIME Type | Valid video MIME type |
| Coordinates | Valid lat,lon (-90 to 90, -180 to 180) |
| Tags | Comma-separated strings |
| Category | From allowed list |
| Visibility | public, private, unlisted, or restricted |
| Allowed Groups | Required if visibility=restricted (unless Allowed Users set) |
| Allowed Users | NOSTR npub format, comma-separated |
| Folder depth | Maximum 5 levels |

### Thumbnail Validation

- Must be JPEG or PNG
- Minimum 640x360 pixels
- Maximum 10 MB file size

## Best Practices

### Organization

1. **Use folders**: Organize videos into logical categories
2. **Consistent naming**: Use descriptive, consistent folder names
3. **Tag thoroughly**: Add relevant tags for discoverability
4. **Choose correct category**: Helps users find your content

### Metadata

1. **Multilingual**: Add translations if your audience is international
2. **Good thumbnails**: Custom thumbnails increase engagement
3. **Timestamps**: Include timestamps in description for long videos
4. **Contact info**: Make it easy for viewers to reach you

### Performance

1. **Compress videos**: Use efficient codecs (H.264, H.265)
2. **Multiple resolutions**: Consider providing multiple quality options
3. **Optimize thumbnails**: Keep under 500 KB

## Security Considerations

### Video Files

- Video files never leave source device unless explicitly downloaded
- WebRTC streaming is peer-to-peer (no server storage)
- Viewer cannot save stream without explicit download option

### Metadata

- Sign metadata with NOSTR for authenticity
- Station verifies signatures before displaying
- Users can verify author identity

### Privacy

- Coordinates are optional (don't reveal filming location if unwanted)
- Contact info is optional
- Social links are optional

### Moderation

- Station operators can hide inappropriate content
- Users can report videos
- Authors can delete their own videos

## Related Documentation

- [Places Format Specification](places-format-specification.md) - Similar multilingual pattern
- [Alerts Format Specification](alert-format-specification.md) - Similar feedback system
- [Blog Format Specification](blog-format-specification.md) - Similar content structure

## Change Log

### Version 1.0 (2026-01-13)
- Initial specification
- Core video metadata format
- Folder organization (5 levels)
- WebRTC streaming architecture
- Multilingual support
- NOSTR integration
- Feedback system
