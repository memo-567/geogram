# Contacts Format Specification

**Version**: 1.2
**Last Updated**: 2026-01-07
**Status**: Active

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Contact Format](#contact-format)
- [Profile Pictures](#profile-pictures)
- [Groups (Folders)](#groups-folders)
- [Identity Management](#identity-management)
- [Date Reminders](#date-reminders)
- [Location Tracking](#location-tracking)
- [Duplicate Prevention](#duplicate-prevention)
- [Reactions System](#reactions-system)
- [Contact Metrics](#contact-metrics)
- [Permissions and Roles](#permissions-and-roles)
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

This document specifies the text-based format used for storing contacts in the Geogram system. The contacts collection type provides a decentralized address book for managing people, machines, and other entities with their identities, communication details, and locations.

**Note**: While primarily used for people, contacts can represent any entity with a NOSTR identity - IoT devices, servers, bots, or autonomous systems.

### Key Features

- **Decentralized Identity**: Track contacts by callsign and NOSTR public key (npub)
- **Group Organization**: Organize contacts into folders (groups)
- **No Duplicates**: Each contact exists in only one location
- **Profile Pictures**: Store profile photos with each contact
- **Multiple Communication Channels**: Email, phone, physical addresses, external links
- **Location Tracking**: Record typical locations for postcard delivery
- **Identity Revocation**: Handle compromised keys and identity changes
- **Successor Tracking**: Link to new identities when contacts migrate
- **First Seen Tracking**: Record when contact was first added
- **NOSTR Integration**: Cryptographic signatures for authenticity
- **Simple Text Format**: Plain text contact cards

### Use Cases

- **Mesh Network Roster**: Maintain list of network participants
- **Postcard Address Book**: Store recipient locations for sneakernet delivery
- **Emergency Contacts**: Keep contact information for disaster scenarios
- **Community Directory**: Build decentralized community member lists
- **Identity Verification**: Track trusted identities and detect compromises

## File Organization

### Directory Structure

```
collection_name/
└── contacts/
    ├── CR7BBQ.txt                      # Contact file (root level)
    ├── X135AS.txt
    ├── BRAVO2.txt
    ├── fast.json                       # Contact summaries cache (all contacts)
    ├── .contact_metrics.txt            # Usage metrics (hidden)
    ├── .favorites.json                 # Quick Access favorites (hidden)
    ├── family/                         # Group folder
    │   ├── ALICE1.txt
    │   ├── BOB42.txt
    │   └── group.txt                   # Group metadata
    ├── work/                           # Another group
    │   ├── CHARLIE.txt
    │   ├── DELTA5.txt
    │   └── group.txt
    ├── emergency/
    │   ├── MEDIC1.txt
    │   ├── RESCUE2.txt
    │   └── group.txt
    ├── profile-pictures/               # Profile photos storage
    │   ├── CR7BBQ.jpg
    │   ├── X135AS.jpg
    │   ├── ALICE1.jpg
    │   ├── BOB42.jpg
    │   └── CHARLIE.jpg
    └── .reactions/
        ├── CR7BBQ.txt
        └── family.txt
```

### Contact File Naming

**Pattern**: `{CALLSIGN}.txt`

**Characteristics**:
- Filename matches the contact's callsign exactly
- Case-sensitive (callsign convention: uppercase)
- Extension: `.txt`
- One file per contact (no duplicates allowed)

**Examples**:
```
CR7BBQ.txt           # Contact with callsign CR7BBQ
X135AS.txt           # Contact with callsign X135AS
ALICE1.txt           # Contact with callsign ALICE1
```

### Group Folders

**Purpose**: Organize contacts into categories

**Structure**:
- Groups are subdirectories under `contacts/`
- Contact files inside group folders
- Optional `group.txt` metadata file
- Groups can be nested (one level recommended)

**Examples**:
```
family/              # Family members
work/                # Work colleagues
emergency/           # Emergency contacts
ham-radio/          # Amateur radio operators
mesh-network/       # Mesh network participants
```

### Profile Pictures Folder

**Location**: `contacts/profile-pictures/`

**Purpose**: Centralized storage for contact photos

**File Naming**: `{CALLSIGN}.{ext}` (matches contact callsign)

**Supported Formats**: JPG, JPEG, PNG, GIF, WebP

**Examples**:
```
profile-pictures/CR7BBQ.jpg
profile-pictures/X135AS.png
profile-pictures/ALICE1.jpg
```

## Contact Format

### Main Contact File

Every contact must have a `.txt` file named after their callsign.

**Complete Structure**:
```
# CONTACT: Display Name

CALLSIGN: CR7BBQ
NPUB: npub1abc123...
CREATED: YYYY-MM-DD HH:MM_ss
FIRST_SEEN: YYYY-MM-DD HH:MM_ss

EMAIL: user@example.com (optional)
PHONE: +1-555-0123 (optional)
ADDRESS: 123 Main St, City, Country (optional)
WEBSITE: https://example.com (optional)
LOCATIONS: location1, location2 (optional)
PROFILE_PICTURE: CR7BBQ.jpg (optional)

REVOKED: false (optional, default: false)
REVOCATION_REASON: (optional, if revoked)
SUCCESSOR: CALLSIGN or npub (optional)
SUCCESSOR_SINCE: YYYY-MM-DD HH:MM_ss (optional, required if successor set)
PREVIOUS_IDENTITY: CALLSIGN or npub (optional)
PREVIOUS_IDENTITY_SINCE: YYYY-MM-DD HH:MM_ss (optional, required if previous_identity set)

Notes about this contact.
Additional information here.
Can include multiple paragraphs.

--> npub: npub1...
--> signature: hex_signature
```

### Header Section

1. **Title Line** (required)
   - **Format**: `# CONTACT: <display-name>`
   - **Example**: `# CONTACT: Alice Smith`
   - **Purpose**: Human-readable name for this person

2. **Blank Line** (required)

3. **Callsign** (required)
   - **Format**: `CALLSIGN: <callsign>`
   - **Example**: `CALLSIGN: CR7BBQ`
   - **Constraints**: Alphanumeric, matches filename

4. **NPUB** (required)
   - **Format**: `NPUB: <npub-key>`
   - **Example**: `NPUB: npub1abc123...`
   - **Purpose**: NOSTR public key for cryptographic identity
   - **Note**: Required for all contacts (people and machines)

5. **Created Timestamp** (required)
   - **Format**: `CREATED: YYYY-MM-DD HH:MM_ss`
   - **Example**: `CREATED: 2025-11-21 10:00_00`
   - **Purpose**: When contact file was created

6. **First Seen** (required)
   - **Format**: `FIRST_SEEN: YYYY-MM-DD HH:MM_ss`
   - **Example**: `FIRST_SEEN: 2024-06-15 14:30_00`
   - **Purpose**: When this person was first encountered

7. **Blank Line** (required)

### Contact Information Section

All fields in this section are optional:

8. **Email** (optional, multiple allowed)
   - **Format**: `EMAIL: <email-address>`
   - **Example**: `EMAIL: alice@example.com`
   - **Multiple**: Use multiple EMAIL lines for multiple addresses

9. **Phone** (optional, multiple allowed)
   - **Format**: `PHONE: <phone-number>`
   - **Example**: `PHONE: +1-555-0123`
   - **Multiple**: Use multiple PHONE lines

10. **Address** (optional, multiple allowed)
    - **Format**: `ADDRESS: <full-address>`
    - **Example**: `ADDRESS: 123 Main Street, Lisbon, Portugal`
    - **Multiple**: Use multiple ADDRESS lines

11. **Website** (optional, multiple allowed)
    - **Format**: `WEBSITE: <url>`
    - **Example**: `WEBSITE: https://alice.example.com`
    - **Multiple**: Use multiple WEBSITE lines

12. **Locations** (optional)
    - **Format**: `LOCATIONS: <location1>, <location2>, ...`
    - **Example**: `LOCATIONS: Home (38.7223,-9.1393), Office (40.7128,-74.0060)`
    - **Purpose**: Typical locations for postcard delivery
    - **Format**: Name (lat,lon) or just place names

13. **Profile Picture** (optional)
    - **Format**: `PROFILE_PICTURE: <filename>`
    - **Example**: `PROFILE_PICTURE: CR7BBQ.jpg`
    - **Path**: Relative to `profile-pictures/` folder

14. **Date Reminders** (optional, multiple allowed)
    - **Format**: `DATE_REMINDER: <type>|<MM-DD>|<year>` or `DATE_REMINDER: other:<label>|<MM-DD>|<year>`
    - **Purpose**: Recurring annual dates to remember (birthdays, anniversaries, etc.)
    - **Types**: `birthday`, `deceased`, `married`, `relation_start`, `relation_end`, `other`
    - **Year**: Optional (omit for unknown/not applicable)
    - **Examples**:
      ```
      DATE_REMINDER: birthday|12-25|1990
      DATE_REMINDER: married|06-15|2010
      DATE_REMINDER: deceased|01-20|2023
      DATE_REMINDER: other:First meeting|03-10
      DATE_REMINDER: relation_start|08-14
      ```

15. **Blank Line** (required if identity section follows)

### Identity Management Section

16. **Revoked** (optional, default: false)
    - **Format**: `REVOKED: <true|false>`
    - **Example**: `REVOKED: true`
    - **Purpose**: Mark identity as compromised/invalid

17. **Revocation Reason** (optional, required if revoked)
    - **Format**: `REVOCATION_REASON: <explanation>`
    - **Example**: `REVOCATION_REASON: Private key leaked on 2025-10-15`

18. **Successor** (optional)
    - **Format**: `SUCCESSOR: <callsign or npub>`
    - **Example**: `SUCCESSOR: CR7BBQ2` or `SUCCESSOR: npub1xyz...`
    - **Purpose**: Link to new identity

19. **Successor Since** (required if successor is set)
    - **Format**: `SUCCESSOR_SINCE: YYYY-MM-DD HH:MM_ss`
    - **Example**: `SUCCESSOR_SINCE: 2025-10-16 12:00_00`
    - **Purpose**: Date when successor identity became valid

20. **Previous Identity** (optional)
    - **Format**: `PREVIOUS_IDENTITY: <callsign or npub>`
    - **Example**: `PREVIOUS_IDENTITY: CR7BBQ` or `PREVIOUS_IDENTITY: npub1old...`
    - **Purpose**: Link to old/replaced identity

21. **Previous Identity Since** (required if previous_identity is set)
    - **Format**: `PREVIOUS_IDENTITY_SINCE: YYYY-MM-DD HH:MM_ss`
    - **Example**: `PREVIOUS_IDENTITY_SINCE: 2025-10-16 12:00_00`
    - **Purpose**: Date when this identity replaced the previous one

22. **Blank Line** (required before notes)

### Notes Section

Free-form text notes about the contact:

```
Met at HAM radio conference in 2024.

Experienced mesh network operator.
Reliable carrier for postcard delivery.

Speaks English, Portuguese, and Spanish.
```

**Characteristics**:
- Plain text only (no markdown)
- Multiple paragraphs allowed
- Blank lines separate paragraphs

### Contact Metadata

```
--> npub: npub1abc123...
--> signature: hex_signature_string...
```

- **npub**: NOSTR public key of contact file creator (optional)
- **signature**: NOSTR signature, must be last if present

## Profile Pictures

### Storage Location

**Directory**: `contacts/profile-pictures/`

**Purpose**:
- Centralized photo storage
- Easy to locate all profile pictures
- Prevents duplication

### File Naming Convention

**Pattern**: `{CALLSIGN}.{extension}`

**Must match**: Contact's callsign exactly

**Examples**:
```
profile-pictures/CR7BBQ.jpg          # For contact CR7BBQ
profile-pictures/ALICE1.png          # For contact ALICE1
profile-pictures/BOB42.jpeg          # For contact BOB42
```

### Supported Formats

- **JPG/JPEG**: Recommended for photos
- **PNG**: Recommended for avatars/logos
- **GIF**: Animated avatars
- **WebP**: Modern format, good compression

### Referencing in Contact File

**In contact file**: `PROFILE_PICTURE: CR7BBQ.jpg`

**Full path**: `contacts/profile-pictures/CR7BBQ.jpg`

### Updating Profile Picture

1. Replace old image file with new one (same name)
2. Or rename and update `PROFILE_PICTURE:` field
3. Old image removed/archived

## Groups (Folders)

### Group Purpose

Organize contacts into logical categories without duplication.

**Use Cases**:
- Family, friends, work colleagues
- Emergency contacts
- HAM radio operators
- Mesh network participants
- By geographic region
- By trust level

### Group Structure

```
contacts/
├── family/
│   ├── group.txt            # Group metadata (optional)
│   ├── ALICE1.txt           # Contact files
│   ├── BOB42.txt
│   └── CAROL3.txt
└── work/
    ├── group.txt
    ├── CHARLIE.txt
    └── DELTA5.txt
```

### Group Metadata File

**Filename**: `group.txt` (optional)

**Format**:
```
# GROUP: Family

CREATED: 2025-11-21 10:00_00
AUTHOR: CR7BBQ

Description of this group.

Members are immediate family members for emergency
contact purposes.

--> npub: npub1...
--> signature: hex_sig
```

**Fields**:
1. `# GROUP: <name>` (required)
2. `CREATED:` timestamp (required)
3. `AUTHOR:` creator callsign (required)
4. Description (optional)
5. Metadata (npub, signature)

### Nested Groups

**Supported**: Yes (one level recommended)

**Example**:
```
contacts/
└── work/
    ├── group.txt
    ├── engineering/
    │   ├── group.txt
    │   ├── DEV1.txt
    │   └── DEV2.txt
    └── management/
        ├── group.txt
        └── MGR1.txt
```

**Recommendation**: Keep hierarchy shallow for simplicity

## Identity Management

### Identity Revocation

**When to Revoke**:
- Private key (nsec) was leaked or compromised
- Identity was stolen or impersonated
- Person wants to retire this identity
- Security audit reveals vulnerability

**Revocation Process**:

1. **Set REVOKED field**:
   ```
   REVOKED: true
   REVOCATION_REASON: Private key leaked on 2025-10-15
   ```

2. **Set SUCCESSOR with date**:
   ```
   SUCCESSOR: CR7BBQ2
   SUCCESSOR_SINCE: 2025-10-16 12:00_00
   ```
   or
   ```
   SUCCESSOR: npub1new_key...
   SUCCESSOR_SINCE: 2025-10-16 12:00_00
   ```

3. **Keep original contact file**: Do not delete
4. **Create new contact**: If successor is a new callsign
5. **Link bidirectionally**: Old → New (SUCCESSOR) and New → Old (PREVIOUS_IDENTITY with dates)

### Successor Tracking

**Purpose**: Maintain contact continuity when identity changes

**Example**:
```
# Old identity (CR7BBQ.txt)
REVOKED: true
REVOCATION_REASON: Key rotation for security
SUCCESSOR: CR7BBQ2
SUCCESSOR_SINCE: 2025-10-16 12:00_00

# New identity (CR7BBQ2.txt)
PREVIOUS_IDENTITY: CR7BBQ
PREVIOUS_IDENTITY_SINCE: 2025-10-16 12:00_00
```

### Displaying Revoked Contacts

**UI Recommendations**:
- Show "REVOKED" badge prominently
- Display revocation reason
- Show link to successor if available
- Gray out or mark as inactive
- Warn before using revoked identity

## Date Reminders

### Purpose

Store recurring annual dates associated with a contact (birthdays, anniversaries, memorial dates, etc.) for notification and calendar integration. These are dates that repeat yearly.

### Format

**Field**: `DATE_REMINDER:`

**Pattern**: `<type>|<MM-DD>|<year>` or `<type>:<label>|<MM-DD>|<year>`

Where:
- `type`: One of `birthday`, `deceased`, `married`, `relation_start`, `relation_end`, `other`
- `MM-DD`: Month and day (e.g., `12-25` for December 25)
- `year`: Optional year (e.g., `1990`)
- `label`: Custom label for `other` type

### Reminder Types

| Type | Purpose | Example Use |
|------|---------|-------------|
| `birthday` | Contact's birthday | Annual birthday celebration |
| `deceased` | Memorial date | Annual remembrance |
| `married` | Wedding anniversary | Annual anniversary |
| `relation_start` | Relationship/friendship start | Anniversary of meeting |
| `relation_end` | Relationship end | Memorial of past relationship |
| `other` | Custom reminder | Any other annual event |

### Examples

```
# Basic birthday (December 25, 1990)
DATE_REMINDER: birthday|12-25|1990

# Wedding anniversary (June 15, 2010)
DATE_REMINDER: married|06-15|2010

# Memorial date (January 20, 2023)
DATE_REMINDER: deceased|01-20|2023

# Custom reminder without year
DATE_REMINDER: other:First meeting|03-10

# Relationship start without year
DATE_REMINDER: relation_start|08-14
```

### Parsing Rules

1. Split line by `|` to get up to 3 parts: type, date, year
2. Parse type - if contains `:`, extract custom label
3. Parse date as `MM-DD` format
4. Year is optional (may be empty or missing)
5. Validate month is 1-12, day is 1-31

### Integration Notes

Date reminders are designed for integration with:
- **Notification apps**: Query all contacts for upcoming reminders
- **Calendar apps**: Sync reminders as recurring annual events
- **Dashboard widgets**: Show "upcoming birthdays this week"

To query all reminders programmatically:
1. Read all contact files
2. Extract all `DATE_REMINDER:` lines
3. Parse and filter by upcoming dates
4. Sort by next occurrence

## Location Tracking

### Purpose

Store typical locations where contact can be found, primarily for **postcard delivery** via sneakernet.

### Format

**Field**: `LOCATIONS:`

**Pattern**: `<name> (<lat>,<lon>), <name2> (<lat2>,<lon2>), ...`

**Examples**:
```
LOCATIONS: Home (38.7223,-9.1393), Office (40.7128,-74.0060)

LOCATIONS: Lisbon Portugal, Porto Portugal

LOCATIONS: HAM Club (38.7169,-9.1399), Makerspace (38.7250,-9.1500)
```

### Location Components

**Name** (optional):
- Human-readable label
- Examples: "Home", "Office", "HAM Club"

**Coordinates** (optional):
- Latitude, longitude
- Format: `(lat,lon)`
- 6 decimal places recommended

### Use in Postcard System

When sending a postcard:
1. Select recipient from contacts
2. System shows their typical LOCATIONS
3. Carrier routes postcard toward those coordinates
4. Increases delivery success probability

## Duplicate Prevention

### Core Principle

**Each contact exists in exactly one location** - no copying allowed.

### Enforcement

**Dual-level uniqueness check**:
- Callsign determines filename: `{CALLSIGN}.txt`
- NPUB must also be unique across all contacts
- Cannot have duplicate callsigns OR duplicate npubs

**Search before create**:
```
1. User wants to add contact with CALLSIGN and NPUB
2. System searches all folders for:
   a. {CALLSIGN}.txt (callsign uniqueness)
   b. Any contact with matching NPUB (identity uniqueness)
3. If either found: Error - contact already exists
   - Show location of duplicate
   - Show conflicting field (callsign or npub)
4. If neither found: Create contact in requested location
```

**Why check both**:
- **Callsign uniqueness**: Prevents filesystem conflicts
- **NPUB uniqueness**: Prevents same person/machine with different callsigns
- **Together**: Ensures one entity = one contact

### Moving Contacts Between Groups

**Allowed**: Yes (move operation, not copy)

**Process**:
```
1. User selects contact
2. User selects new group (folder)
3. System moves file from old location to new location
4. Original file removed from old location
5. Only one instance remains
```

**Example**:
```
Before:
contacts/family/ALICE1.txt

User moves ALICE1 to work group

After:
contacts/work/ALICE1.txt
```

### Multi-Group Membership (Virtual)

**Physical**: Contact file in one folder only

**Virtual**: Tags or categories in contact notes

**Example**:
```
# Contact file in: contacts/friends/ALICE1.txt

# CONTACT: Alice Smith
...
TAGS: friend, work-colleague, emergency-contact
```

## Reactions System

### Overview

Contacts can have likes and comments just like other collection types.

### Reaction Targets

**Contact Reactions** (`.reactions/{CALLSIGN}.txt`):
- Likes and comments on a specific contact
- Example: `.reactions/CR7BBQ.txt`

**Group Reactions** (`.reactions/{group-name}.txt`):
- Reactions on a group as a whole
- Example: `.reactions/family.txt`

### Reaction File Format

```
LIKES: X135AS, BRAVO2, ALPHA1

> 2025-11-21 14:00_00 -- X135AS
Great contact! Very reliable carrier.
--> npub: npub1xyz...
--> signature: hex_sig

> 2025-11-21 16:00_00 -- BRAVO2
Helped me deliver important postcard.
```

### Reaction Locations

**Contact reactions**:
- File: `.reactions/{CALLSIGN}.txt`
- Path: `contacts/.reactions/CR7BBQ.txt`
- Or: `contacts/family/.reactions/ALICE1.txt`

**Group reactions**:
- File: `.reactions/{folder-name}.txt`
- Path: `contacts/.reactions/family.txt`

## Contact Metrics

### Purpose

The contact metrics system tracks usage patterns to identify frequently accessed and interacted contacts. This enables features like:

- **Quick Access**: Show most popular contacts at the top of lists
- **Favorites**: Automatically identify favorite contacts without manual curation
- **Smart Sorting**: Sort contact pickers by relevance (most used first)
- **Event Suggestions**: Prioritize contacts frequently associated with events

### File Location

**Path**: `contacts/.contact_metrics.txt`

**Characteristics**:
- Hidden file (starts with `.`)
- Plain text format
- One contact per line
- Auto-generated and maintained by the application
- Safe to delete (will be rebuilt from usage)

### File Format

```
# CONTACT METRICS
# Format: CALLSIGN|views|total_interactions|last_accessed|method_interactions|events

CR7BBQ|15|8|2025-11-21 14:30_00|phone:0=3,email:0=5|4
ALICE1|10|5|2025-11-20 09:15_00|phone:0=2,phone:1=1,email:0=2|2
BOB42|3|1|2025-11-19 16:45_00|email:bob@work.com=1|0
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `CALLSIGN` | string | Contact identifier (matches filename) |
| `views` | int | Number of times contact detail was viewed |
| `total_interactions` | int | Total count of all interactions |
| `last_accessed` | timestamp | When contact was last viewed or interacted with |
| `method_interactions` | map | Interaction counts per communication method |
| `events` | int | Number of times contact was added to events |

### Method Interactions Format

The `method_interactions` field tracks how often each communication method was used:

**Format**: `type:index=count,type:value=count,...`

**Examples**:
```
phone:0=5              # First phone number used 5 times
phone:+1-555-0123=5    # Same phone tracked by value
email:0=3              # First email used 3 times
email:alice@ex.com=3   # Same email tracked by value
```

**Tracked Types**:
- `phone` - Phone calls or SMS
- `email` - Email sent
- `message` - Short messages
- `website` - Website visited

### Popularity Score Calculation

The **totalScore** determines contact ranking:

```
totalScore = views + (totalInteractions × 2) + (events × 3)
```

**Weights**:
- Views: ×1 (passive engagement)
- Interactions: ×2 (active engagement)
- Events: ×3 (strong association indicator)

**Example**:
```
Contact with: 10 views, 5 interactions, 2 events
Score = 10 + (5 × 2) + (2 × 3) = 10 + 10 + 6 = 26
```

### When Metrics Are Recorded

| Action | Metric Updated |
|--------|----------------|
| Open contact detail page | `views++`, `lastAccessed` |
| Tap phone number | `totalInteractions++`, `methodInteractions[phone:N]++` |
| Tap email address | `totalInteractions++`, `methodInteractions[email:N]++` |
| Send short message | `totalInteractions++`, `methodInteractions[message:N]++` |
| Add contact to event | `events++`, `lastAccessed` |

### Contact Summaries Cache (fast.json)

For instant contact list loading, a summaries cache is maintained:

**Path**: `contacts/fast.json`

**Purpose**: Pre-computed summaries of all contacts for instant UI rendering

**Format**:
```json
[
  {
    "callsign": "CR7BBQ",
    "displayName": "Carlos Rodriguez",
    "profilePicture": "CR7BBQ.jpg",
    "groupPath": "family",
    "filePath": "/path/to/contacts/family/CR7BBQ.txt",
    "popularityScore": 26
  },
  {
    "callsign": "ALICE1",
    "displayName": "Alice Smith",
    "profilePicture": "ALICE1.png",
    "filePath": "/path/to/contacts/ALICE1.txt",
    "popularityScore": 20
  }
]
```

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `callsign` | string | Contact identifier |
| `displayName` | string | Human-readable name |
| `profilePicture` | string? | Profile picture filename (optional) |
| `groupPath` | string? | Group folder path (optional) |
| `filePath` | string | Full path to contact file |
| `popularityScore` | int | Calculated from metrics |

**Characteristics**:
- JSON array of contact summaries
- Sorted by popularity score (descending), then alphabetically
- Contains essential display data only
- Rebuilt when contacts are added, modified, or deleted
- Enables instant UI rendering without parsing all contact files

**When Rebuilt**:
- Contact created
- Contact updated
- Contact deleted
- Contact moved between groups
- On first load if file missing

### Favorites Cache (.favorites.json)

For Quick Access feature, a favorites cache is maintained:

**Path**: `contacts/.favorites.json`

**Purpose**: Pre-computed list of top contacts for Quick Access panel

**Format**:
```json
[
  {"callsign": "CR7BBQ", "displayName": "Carlos", "popularityScore": 26},
  {"callsign": "ALICE1", "displayName": "Alice", "popularityScore": 20}
]
```

**Characteristics**:
- JSON array of contact summaries
- Sorted by popularity score (descending)
- Limited to top 30 contacts by default
- Only includes contacts with score > 0
- Rebuilt automatically when metrics change

### Quick Access Feature

The Quick Access panel displays frequently used contacts for one-tap access.

**Display Location**: Top of Contacts browser page

**Data Source**: `contacts/.favorites.json`

**Behavior**:
1. Loads favorites from `.favorites.json` (instant)
2. Displays contacts as clickable cards/avatars
3. Shows display name and profile picture
4. Tapping opens contact detail page
5. Updates automatically as usage patterns change

**When Empty**:
- Shows hint: "View or interact with contacts to see your favorites here"
- Encourages users to use the app to build their favorites

**Update Triggers**:
- Contact viewed → metrics updated → favorites rebuilt
- Contact interaction (call, email, message) → metrics updated → favorites rebuilt
- Contact added to event → metrics updated → favorites rebuilt

### Usage in Contact Picker

When selecting contacts for events, the picker can use metrics for smart sorting:

**Default Sort** (sortByEvents: false):
1. Favorites first (from `.favorites.json`)
2. Then alphabetically

**Event Sort** (sortByEvents: true):
1. Contacts with highest `events` count first
2. Then favorites
3. Then alphabetically

### File Operations

**Rebuild Metrics**:
```
1. Scan all contact files
2. Load existing metrics (if any)
3. Preserve existing counts
4. Remove metrics for deleted contacts
5. Save updated metrics file
```

**Rebuild Favorites Cache**:
```
1. Load metrics file
2. Filter contacts with score > 0
3. Sort by totalScore descending
4. Take top N contacts (default: 30)
5. Load display names from contact files
6. Save to .favorites.json
```

### Best Practices

1. **Don't Edit Manually**: Let the application manage metrics
2. **Safe to Delete**: Both files can be deleted; they'll rebuild over time
3. **Privacy**: Metrics reveal usage patterns; keep contacts collection private
4. **Performance**: Use `.favorites.json` for instant access to top contacts

## Permissions and Roles

### Collection Owner

The user who created the contacts collection.

**Permissions**:
- Create/edit/delete any contact
- Create/rename/delete groups
- Move contacts between groups
- Manage all reactions

### Public/Private Contacts

**Private Collection** (default recommended):
- Only owner can view/edit
- Personal address book
- Contact details kept confidential

**Group/Restricted Collection**:
- Selected users can view
- Shared team contacts
- Emergency contact directory

**Public Collection**:
- Anyone can view
- Community directory
- Public mesh network roster

## NOSTR Integration

### Identity Verification

**Contact's npub**:
```
NPUB: npub1abc123...
```

**Verifies**: This is the contact's NOSTR public key

### Signature Verification

**Contact file signature**:
```
--> npub: npub1creator...
--> signature: hex_sig
```

**Verifies**: Who created/edited this contact file

**Process**:
1. Extract npub and signature
2. Reconstruct signable message
3. Verify Schnorr signature
4. Display verification badge if valid

## Complete Examples

### Example 1: Simple Contact

```
# CONTACT: Alice Smith

CALLSIGN: ALICE1
NPUB: npub1abc123def456...
CREATED: 2025-11-21 10:00_00
FIRST_SEEN: 2024-06-15 14:30_00

EMAIL: alice@example.com
PHONE: +1-555-0123
WEBSITE: https://alice.example.com
PROFILE_PICTURE: ALICE1.jpg

Met at HAM radio conference in 2024.
Experienced mesh network operator.

--> npub: npub1creator...
--> signature: 0123456789abcdef...
```

### Example 2: Contact with Multiple Details

```
# CONTACT: Bob Martinez

CALLSIGN: BOB42
NPUB: npub1bob999aaa...
CREATED: 2025-11-21 11:00_00
FIRST_SEEN: 2023-03-10 09:00_00

EMAIL: bob@work.com
EMAIL: bob.personal@gmail.com
PHONE: +1-555-0456
PHONE: +34-600-123-456
ADDRESS: 456 Oak Avenue, Madrid, Spain
WEBSITE: https://bob-martinez.net
LOCATIONS: Home (40.4168,-3.7038), Office (40.4200,-3.7100)
PROFILE_PICTURE: BOB42.jpg

Emergency contact for Spain region.

Speaks English and Spanish fluently.
Reliable postcard carrier with extensive travel routes.
Active in amateur radio community.

--> npub: npub1creator...
--> signature: fedcba987654...
```

### Example 3: Revoked Identity with Successor

```
# CONTACT: Charlie (OLD IDENTITY)

CALLSIGN: CHARLIE
NPUB: npub1old_compromised...
CREATED: 2024-01-15 08:00_00
FIRST_SEEN: 2023-01-15 08:00_00

EMAIL: charlie@example.com
PROFILE_PICTURE: CHARLIE.jpg

REVOKED: true
REVOCATION_REASON: Private key leaked on 2025-10-15. Identity compromised.
SUCCESSOR: CHARLIE2
SUCCESSOR_SINCE: 2025-10-16 12:00_00

DO NOT USE THIS IDENTITY.
Please contact via new identity CHARLIE2.

--> npub: npub1old_compromised...
--> signature: old_signature...
```

```
# CONTACT: Charlie (NEW IDENTITY)

CALLSIGN: CHARLIE2
NPUB: npub1new_secure...
CREATED: 2025-10-16 12:00_00
FIRST_SEEN: 2023-01-15 08:00_00

EMAIL: charlie@example.com
PROFILE_PICTURE: CHARLIE2.jpg

PREVIOUS_IDENTITY: CHARLIE
PREVIOUS_IDENTITY_SINCE: 2025-10-16 12:00_00

New secure identity after key rotation.
All previous contact information transferred.

--> npub: npub1new_secure...
--> signature: new_signature...
```

### Example 4: Group Organization

```
Folder structure:
contacts/
├── emergency/
│   ├── group.txt
│   ├── MEDIC1.txt
│   ├── RESCUE2.txt
│   └── FIRE3.txt
└── profile-pictures/
    ├── MEDIC1.jpg
    ├── RESCUE2.jpg
    └── FIRE3.jpg

=== emergency/group.txt ===
# GROUP: Emergency Contacts

CREATED: 2025-11-20 09:00_00
AUTHOR: CR7BBQ

Critical emergency contacts for disaster response.

All members trained in emergency communications
and available 24/7 for urgent situations.

--> npub: npub1creator...
--> signature: group_sig...

=== emergency/MEDIC1.txt ===
# CONTACT: Dr. Sarah Johnson

CALLSIGN: MEDIC1
NPUB: npub1medic...
CREATED: 2025-11-20 09:30_00
FIRST_SEEN: 2024-02-20 10:00_00

PHONE: +1-555-EMERGENCY
EMAIL: dr.johnson@hospital.org
LOCATIONS: City Hospital (38.7200,-9.1400)
PROFILE_PICTURE: MEDIC1.jpg

Emergency medical coordinator.
Available for medical emergencies 24/7.
HAM radio operator, emergency frequency monitor.

--> npub: npub1creator...
--> signature: medic_sig...
```

## Parsing Implementation

### Contact File Parsing

```
1. Read {CALLSIGN}.txt as UTF-8 text
2. Verify first line starts with "# CONTACT: "
3. Extract display name from first line
4. Parse header lines:
   - CALLSIGN: (required)
   - NPUB: (required)
   - CREATED: timestamp (required)
   - FIRST_SEEN: timestamp (required)
5. Parse contact information lines (all optional):
   - EMAIL: (can have multiple)
   - PHONE: (can have multiple)
   - ADDRESS: (can have multiple)
   - WEBSITE: (can have multiple)
   - LOCATIONS:
   - PROFILE_PICTURE:
6. Parse identity management lines (optional):
   - REVOKED:
   - REVOCATION_REASON: (required if REVOKED is true)
   - SUCCESSOR:
   - SUCCESSOR_SINCE: (required if SUCCESSOR is set)
   - PREVIOUS_IDENTITY:
   - PREVIOUS_IDENTITY_SINCE: (required if PREVIOUS_IDENTITY is set)
7. Parse notes section
8. Extract metadata (npub, signature)
9. Verify callsign in filename matches CALLSIGN: field
10. Verify NPUB is valid bech32 format
11. Verify conditional field dependencies (successor dates, etc.)
```

### Profile Picture Resolution

```
1. Check PROFILE_PICTURE field in contact
2. Build path: contacts/profile-pictures/{filename}
3. Verify file exists
4. Load and display image
5. If missing: Use default avatar placeholder
```

### Duplicate Detection

```
1. When creating contact with CALLSIGN and NPUB
2. Recursively search contacts/ for:
   a. {CALLSIGN}.txt (check filename)
   b. Any contact file with matching NPUB (parse and check)
3. Check all subfolders (groups)
4. If callsign duplicate found:
   - Return error: "Contact with callsign already exists at {path}"
5. If npub duplicate found:
   - Return error: "Contact with this NPUB already exists at {path}"
6. If neither found: Allow creation
```

## File Operations

### Creating a Contact

```
1. Verify callsign is unique (search all folders for {CALLSIGN}.txt)
2. Verify npub is unique (search all contact files for matching NPUB)
3. If either duplicate found, reject creation with error
4. Choose location (root or group folder)
5. Create {CALLSIGN}.txt file
6. Write contact data with required fields (CALLSIGN, NPUB, CREATED, FIRST_SEEN)
7. Optionally upload profile picture to profile-pictures/
8. Set file permissions (644)
9. Update search indexes with callsign and npub
```

### Moving Contact to Different Group

```
1. Verify user has permission
2. Locate source file: {old_path}/{CALLSIGN}.txt
3. Verify destination doesn't have duplicate
4. Move file to: {new_path}/{CALLSIGN}.txt
5. Profile picture stays in profile-pictures/ (no move needed)
6. Update UI/indexes
```

### Revoking an Identity

```
1. Open contact file
2. Add/update fields:
   REVOKED: true
   REVOCATION_REASON: <explanation>
   SUCCESSOR: <new_callsign or npub> (optional)
3. Save contact file
4. If successor specified:
   a. Create/update successor contact
   b. Add PREVIOUS_IDENTITY: <old_callsign> to new contact
5. Update UI to show revoked status
```

### Deleting a Contact

```
1. Verify user has permission
2. Locate contact file: {CALLSIGN}.txt
3. Delete profile picture: profile-pictures/{CALLSIGN}.{ext}
4. Delete reaction file: .reactions/{CALLSIGN}.txt (if exists)
5. Delete contact file
6. Update indexes
```

## Validation Rules

### Contact File Validation

- [ ] First line must start with `# CONTACT: `
- [ ] Display name must not be empty
- [ ] CALLSIGN field required and matches filename
- [ ] NPUB field required and valid npub format
- [ ] CREATED timestamp valid format
- [ ] FIRST_SEEN timestamp valid format
- [ ] If REVOKED is true, REVOCATION_REASON should be present
- [ ] If SUCCESSOR is set, SUCCESSOR_SINCE timestamp required
- [ ] If PREVIOUS_IDENTITY is set, PREVIOUS_IDENTITY_SINCE timestamp required
- [ ] SUCCESSOR_SINCE and PREVIOUS_IDENTITY_SINCE must be valid timestamps
- [ ] PROFILE_PICTURE file must exist in profile-pictures/ if specified
- [ ] No duplicate callsigns across all folders
- [ ] No duplicate npubs across all folders
- [ ] Signature must be last metadata if present

### Callsign Validation

**Pattern**: `^[A-Z0-9]{3,10}(-[A-Z0-9]{1,3})?$`

**Valid**:
- CR7BBQ (6 chars, alphanumeric, uppercase)
- ALICE1 (6 chars)
- BOB42 (5 chars)
- X135AS (6 chars)

**Invalid**:
- ab (too short)
- lowercase (must be uppercase)
- TOOLONG12345 (too long)

### NPUB Validation

**Format**: `npub1` followed by bech32-encoded data

**Validation**:
1. Starts with "npub1"
2. Valid bech32 encoding
3. Correct length

## Best Practices

### For Users

1. **Valid NPUB Required**: Ensure every contact has a valid NOSTR npub
2. **Keep Updated**: Regularly update contact information
3. **Organize Groups**: Use meaningful group names for categorization
4. **Profile Pictures**: Add photos for easy recognition
5. **Add Locations**: Include locations for postcard delivery routing
6. **Sign Contacts**: Use npub/signature for file authenticity
7. **Handle Revocations**: Mark compromised identities with reason and dates
8. **Link Successors**: Maintain identity continuity with timestamps
9. **Document Machines**: Add descriptive notes for non-human contacts

### For Developers

1. **Enforce Dual Uniqueness**: Check both callsign and npub before creating
2. **Validate Callsigns**: Use regex pattern validation
3. **Validate NPUB**: Verify bech32 format and require in all contacts
4. **Verify Signatures**: Always verify NOSTR signatures
5. **Handle Revocations**: Show warnings for revoked identities
6. **Validate Date Dependencies**: Ensure SUCCESSOR_SINCE when SUCCESSOR is set
7. **Lazy Load Pictures**: Load profile images on demand
8. **Index Both Keys**: Build search index for callsign and npub
9. **Backup Regularly**: Contacts are critical data

## Security Considerations

### Privacy

**Default Private**:
- Contacts collection should be private by default
- Contains sensitive personal information
- Email, phone, addresses are PII

**Sharing Considerations**:
- Only share with trusted users
- Use group/restricted permissions
- Avoid public contacts collections with personal data

### Identity Security

**Key Management**:
- NPUB is public, safe to share
- Never store nsec (private keys) in contacts
- Verify signatures to prevent impersonation

**Revocation Handling**:
- Mark revoked identities prominently
- Prevent use of revoked identities
- Follow successor chains carefully
- Verify successor authenticity

### Data Integrity

**File Security**:
- Contacts folders: 755 (rwxr-xr-x)
- Contact files: 644 (rw-r--r--)
- Validate all inputs
- Sanitize filenames

**Backup Strategy**:
- Regular backups of contacts/
- Include profile-pictures/ folder
- Export to encrypted archive
- Test restore procedures

## Related Documentation

- [Postcards Format Specification](postcards-format-specification.md) - Uses contacts for addressing
- [Places Format Specification](places-format-specification.md) - Similar structure
- [Collection Security Model](../others/security-model.md)
- [NOSTR Protocol](https://github.com/nostr-protocol/nostr)

## Change Log

### Version 1.2 (2026-01-07)

**Date Reminders Feature**:
- Added `DATE_REMINDER:` field for recurring annual dates
- Supported types: `birthday`, `deceased`, `married`, `relation_start`, `relation_end`, `other`
- Custom labels supported for `other` type via `other:<label>` syntax
- Optional year field for historical dates
- Format: `TYPE|MM-DD|YEAR` (year optional)
- Designed for integration with notification and calendar apps

### Version 1.1 (2026-01-06)

**Contact Metrics System**:
- Added usage metrics tracking (`.contact_metrics.txt`)
- Fields: views, totalInteractions, events, lastAccessed, methodInteractions
- Popularity score calculation: `views + (interactions × 2) + (events × 3)`
- Contact summaries cache (`fast.json`) for instant UI loading
- Favorites cache (`.favorites.json`) for Quick Access feature
- Quick Access panel documentation
- Smart sorting in Contact Picker based on event associations

### Version 1.0 (2025-11-21)

**Initial Specification**:
- Callsign-based contact files
- **Required NOSTR npub** for all contacts (people and machines)
- Group (folder) organization
- **Dual-level duplicate prevention** (callsign + npub uniqueness)
- Centralized profile picture management in `profile-pictures/` folder
- Multiple contact channels (email, phone, address, web)
- Location tracking for postcard delivery (supports postcard system)
- Identity revocation system with REVOKED flag and reason
- **Successor tracking with timestamps** (SUCCESSOR, SUCCESSOR_SINCE)
- **Previous identity tracking with timestamps** (PREVIOUS_IDENTITY, PREVIOUS_IDENTITY_SINCE)
- First seen timestamp tracking
- Reactions system (likes and comments)
- Simple text format (no markdown)
- NOSTR signature integration
- Support for non-human entities (machines, IoT devices, bots)

**Design Decisions**:
- Profile pictures: Centralized folder for easy management
- Locations format: Comma-separated with optional coordinates
- Identity chains: Bidirectional linking with timestamps
- Group membership: Physical folder only (no virtual tags)
- Duplicate prevention: Check both callsign and npub
- Collection name: "contacts" (not "people") to support machines
