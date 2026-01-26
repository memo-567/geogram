# Reusable Widgets and Components

This document catalogs reusable UI components available in the Geogram codebase. These widgets are designed to be used across multiple features and pages.

## Index

### Picker Widgets
- [UserPickerWidget](#userpickerwidget) - Select users from devices
- [CurrencyPickerWidget](#currencypickerwidget) - Select currencies
- [TypeSelectorWidget](#typeselectorwidget) - Select inventory types

### Notification Helpers
- [BackupNotificationService](#backupnotificationservice) - Backup event notifications
- [Notification Tap Handling Pattern](#notification-tap-handling-pattern) - Handle notification taps

### Viewer Pages
- [PhotoViewerPage](#photoviewerpage) - Image & video gallery
- [LocationPickerPage](#locationpickerpage) - Map location selection
- [PlacePickerPage](#placepickerpage) - Place selection with sorting
- [ContactPickerPage](#contactpickerpage) - Contact selection with sorting
- [DocumentViewerEditorPage](#documentviewereditorpage) - PDF, text, markdown viewer
- [ContractDocumentPage](#contractdocumentpage) - Markdown document viewer

### Player Widgets
- [VoicePlayerWidget](#voiceplayerwidget) - Voice messages
- [MusicPlayerWidget](#musicplayerwidget) - Music tracks
- [VoiceRecorderWidget](#voicerecorderwidget) - Record voice

### Dialog Widgets
- [NewChannelDialog](#newchanneldialog) - Create chat channels
- [NewThreadDialog](#newthreaddialog) - Create forum threads
- [AddTrackableDialog](#addtrackabledialog) - Add exercise or measurement entries

### Selector Widgets
- [CallsignSelectorWidget](#callsignselectorwidget) - Profile switching
- [ProfileSwitcher](#profileswitcher) - App bar profile

### Map Widgets
- [TrackerMapCard](#trackermapcard) - Reusable satellite map miniature

### Tree Widgets
- [FolderTreeWidget](#foldertreewidget) - Folder navigation

### Message Widgets
- [MessageBubbleWidget](#messagebubblewidget) - Chat bubbles
- [MessageInputWidget](#messageinputwidget) - Message composer

### Services
- [LocationService](#locationservice) - City lookup from coordinates
- [LocationProviderService](#locationproviderservice) - Shared GPS positioning for all apps
- [PathRecordingService](#pathrecordingservice) - GPS path recording (uses LocationProviderService)
- [PlaceService.findPlacesWithinRadius](#placeservicefindplaceswithinradius) - Find places within GPS radius
- [CollectionService.generateBlogCache](#collectionservicegenerateblogcache) - Generate blog posts cache
- [StunServerService](#stunserverservice) - Self-hosted STUN server for WebRTC NAT traversal
- [VideoMetadataExtractor](#videometadataextractor) - Video metadata and thumbnail generation using media_kit
- [DirectMessageService Message Cache](#directmessageservice-message-cache) - DM message caching for performance
- [ChatFileDownloadManager](#chatfiledownloadmanager) - Connection-aware file downloads with progress and resume
- [TransferService](#transferservice) - Centralized multi-transport transfers with caching and resume
- [MirrorSyncService](#mirrorsyncservice) - Simple one-way folder sync with NOSTR authentication
- [GeogramApi](#geogramapi) - Unified transport-agnostic API facade

### USB/Transport Services
- [UsbAoaService](#usbaoapservice) - Cross-platform USB AOA service layer
- [UsbAoaLinux](#usbaoaplinux) - Linux USB host FFI implementation
- [UsbAoaTransport](#usbaoapransport) - USB transport for message delivery

### Reader Services
- [RssService](#rssservice) - RSS/Atom feed parsing and HTML-to-Markdown conversion
- [MangaService](#mangaservice) - CBZ extraction and chapter creation
- [SourceService](#sourceservice) - Source.js discovery and parsing
- [ReaderService](#readerservice) - Main reader service orchestrating all content types

### Flasher Components
- [FlasherService](#flasherservice) - Main service for flash operations
- [FlasherStorageService](#flasherstorageservice) - Device definitions storage (v1.0 and v2.0)
- [FirmwareTreeWidget](#firmwaretreewidget) - Hierarchical firmware library tree view
- [SelectedFirmwareCard](#selectedfirmwarecard) - Selected firmware display card
- [FirmwareVersion](#firmwareversion) - Firmware version model with metadata
- [ProtocolRegistry](#protocolregistry) - Protocol factory
- [DeviceCard](#devicecard-widget) - Device selection card
- [FlashProgressWidget](#flashprogresswidget) - Progress display

### API Common Utilities
- [GeometryUtils](#geometryutils) - Haversine distance calculation between coordinates
- [FileTreeBuilder](#filetreebuilder) - Recursive file tree for sync operations
- [StationInfo](#stationinfo) - Station metadata for API responses

### Server Chat Models
- [ServerChatRoom](#serverchatroom) - Server-side chat room management
- [ServerChatMessage](#serverchatmessage) - Server-side message with NOSTR signatures

### CLI/Console Abstractions
- [ConsoleIO](#consoleio) - Platform-agnostic console I/O interface
- [ConsoleHandler](#consolehandler) - Shared command logic for CLI/UI/Telegram
- [ConsoleCompleter](#consolecompleter) - Shared TAB completion logic
- [LogService Isolate Reading](#logservice-isolate-reading) - Read large logs off UI thread

### Web Theme Components
- [WebNavigation](#webnavigation) - Reusable navigation menu generator (shared library)
- [getChatPageScripts](#getchatpagescripts) - Reusable chat page JavaScript (shared library)

### QR Widgets
- [QrShareReceiveWidget](#qrsharereceivewidget) - Share/receive data via QR

### Speech Input Widgets
- [TranscribeButtonWidget](#transcribebuttonwidget) - Voice-to-text for text fields
- [TtsPlayerWidget](#ttsplayerwidget) - Text-to-speech playback

### Constants
- [App Constants](#app-constants) - Centralized app type definitions
- [App Type Theme](#app-type-theme) - Centralized icons and gradients for app types

---

## Picker Widgets

### UserPickerWidget

**File:** `lib/widgets/user_picker_widget.dart`

Select a user from known devices organized by folders with search functionality.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `excludeNpub` | String? | No | Npub to exclude from selection (e.g., current user) |

**Returns:** `UserPickerResult` with `callsign`, `npub`, and `displayName`

**Usage:**
```dart
final result = await showModalBottomSheet<UserPickerResult>(
  context: context,
  isScrollControlled: true,
  builder: (_) => UserPickerWidget(
    i18n: widget.i18n,
    excludeNpub: currentUserNpub,
  ),
);

if (result != null) {
  print('Selected: ${result.callsign} (${result.npub})');
}
```

**Features:**
- Users organized by device folders
- Search by callsign, display name, or npub
- Auto-expands single folder
- Filters out users without npub
- DraggableScrollableSheet UI

---

### CurrencyPickerWidget

**File:** `lib/widgets/wallet/currency_picker_widget.dart`

Select from available currencies including crypto, fiat, time-based, and custom currencies.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `selectedCurrency` | String? | No | Currently selected currency code |
| `showTime` | bool | No | Show time-based currencies (default: true) |
| `showCrypto` | bool | No | Show cryptocurrencies (default: true) |
| `showFiat` | bool | No | Show fiat currencies (default: true) |
| `showCustom` | bool | No | Show custom currencies (default: true) |

**Returns:** Currency code as `String`

**Usage:**
```dart
final currency = await showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => CurrencyPickerWidget(
    i18n: widget.i18n,
    selectedCurrency: 'EUR',
    showCrypto: true,
    showFiat: true,
  ),
);
```

**Features:**
- Categorized list (Time, Crypto, Fiat, Custom)
- Color-coded category badges
- Currency symbols display
- Checkmark for selected currency

---

### TypeSelectorWidget

**File:** `lib/widgets/inventory/type_selector_widget.dart`

Select an item type from the inventory catalog with category filtering.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `selectedType` | String | Yes | Currently selected type ID |
| `scrollController` | ScrollController? | No | External scroll controller |

**Returns:** Type ID as `String`

**Usage:**
```dart
final typeId = await showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => TypeSelectorWidget(
    i18n: widget.i18n,
    selectedType: currentTypeId,
  ),
);
```

**Features:**
- 16 item categories (food, electronics, tools, etc.)
- Category tabs for quick navigation
- Search with category filtering
- Icons for each category

---

## Notification Helpers

### BackupNotificationService

**File:** `lib/services/backup_notification_service.dart`

Lightweight local notification handler for backup events (invite received/accepted/declined, backup/restore start/complete/fail, snapshot note updates). It listens to `BackupEvent` on `EventBus` and shows platform notifications on Android/iOS when allowed by `NotificationService` settings.

**Initialization (mobile only):**
```dart
// After NotificationService/DMNotificationService setup
await BackupNotificationService().initialize(skipPermissionRequest: firstLaunch);
```

**How it works:**
- Subscribes to `BackupEvent` (types in `lib/util/event_bus.dart`).
- Respects notification preferences (`enableNotifications`, `notifySystemAlerts`).
- Uses `flutter_local_notifications` with channel `geogram_backup`.

**Reuse in other apps/features:**
1. Fire `BackupEvent` with a relevant `BackupEventType` from your flow (e.g., for a new app that piggybacks on backup transfers). Example:
   ```dart
   EventBus().fire(BackupEvent(
     type: BackupEventType.backupCompleted,
     role: 'client',
     counterpartCallsign: providerCallsign,
     snapshotId: snapshotId,
     totalFiles: totalFiles,
     totalBytes: totalBytes,
   ));
   ```
2. Ensure `BackupNotificationService().initialize()` is called during app startup (already wired in `main.dart`).
3. Add any new `BackupEventType` variants to `lib/util/event_bus.dart` and handle them in `_handleEvent` if you want notifications.

**Notes:**
- No notifications on desktop/web (mobile-only guard).
- Honors OS permission prompts; set `skipPermissionRequest` during onboarding as needed.
- Uses plain title/body; extend `_handleEvent` for richer payloads if your app needs it.

---

### Notification Tap Handling Pattern

**Files:** `lib/services/dm_notification_service.dart`, `lib/main.dart`

Handle navigation when users tap on notifications. This pattern works reliably across all app states (foreground, background, terminated).

#### Why Not EventBus for Notification Taps?

When a notification is tapped on Android, the callback may run in a **separate Dart isolate**. Each isolate has its own memory, so `EventBus()` returns a different singleton instance. Events fired in the notification isolate never reach the main UI isolate.

**Use EventBus for:** Creating notifications when events occur (same isolate)
**Don't use EventBus for:** Handling notification taps (cross-isolate)

#### The Pattern: Static Pending Action + Lifecycle Check

1. **Define a static pending action variable** in the notification service
2. **Set it in notification tap callbacks** (both foreground and background)
3. **Check it on app resume** via `WidgetsBindingObserver.didChangeAppLifecycleState`

#### Payload Format

Use a standardized payload format: `type:data`

| Type | Format | Example | Action |
|------|--------|---------|--------|
| dm | `dm:CALLSIGN` | `dm:ALPHA1` | Open DM chat with ALPHA1 |
| chat | `chat:ROOM_ID` | `chat:general` | Open chat room |
| alert | `alert:ALERT_ID` | `alert:abc123` | Open alert details |
| backup | `backup:SNAPSHOT_ID` | `backup:xyz789` | Open backup details |

#### Implementation

**In notification service (e.g., `dm_notification_service.dart`):**

```dart
/// Notification action from tap - stored statically to persist across isolates
class NotificationAction {
  final String type;
  final String data;
  NotificationAction({required this.type, required this.data});
}

class DMNotificationService {
  /// Pending action from notification tap - checked on app resume
  static NotificationAction? pendingAction;

  // In notification tap callback:
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final colonIndex = payload.indexOf(':');
    if (colonIndex > 0) {
      pendingAction = NotificationAction(
        type: payload.substring(0, colonIndex),
        data: payload.substring(colonIndex + 1),
      );
    }
  }
}
```

**In main.dart:**

```dart
class _GeogramAppState extends State<GeogramApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check on startup too (handles cold start)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingNotification());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingNotification();
    }
  }

  void _checkPendingNotification() {
    final action = DMNotificationService.pendingAction;
    if (action == null) return;
    DMNotificationService.pendingAction = null; // Clear it

    switch (action.type) {
      case 'dm':
        _navigateToDMChat(action.data);
        break;
      case 'chat':
        _navigateToChatRoom(action.data);
        break;
      // Add more types as needed
    }
  }
}
```

#### Adding New Notification Types

1. Define the payload format: `newtype:DATA`
2. Create notifications with that payload in your service
3. Add case to `_checkPendingNotification()` switch in main.dart
4. Implement the navigation method

---

## Viewer Pages

### PhotoViewerPage

**File:** `lib/pages/photo_viewer_page.dart`

Full-screen media viewer for photos and videos with zoom, pan, and navigation.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `imagePaths` | List\<String\> | Yes | List of local or network media paths (images and videos) |
| `initialIndex` | int | No | Starting media index (default: 0) |

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => PhotoViewerPage(
      imagePaths: ['/path/to/image.jpg', '/path/to/video.mp4'],
      initialIndex: 0,
    ),
  ),
);
```

**Features:**
- **Images:** Zoom (0.5x to 4.0x) with pinch gesture, pan support
- **Videos:** Tap to play/pause, progress bar with scrubbing, duration display
- Swipe navigation between media items
- Keyboard navigation (arrows, escape)
- Media counter display
- Page indicator dots
- Save/download button (images and videos)
- Network and local file support
- Black background (cinema mode)

**Supported Video Formats:**
`.mp4`, `.avi`, `.mkv`, `.mov`, `.wmv`, `.flv`, `.webm`

---

### LocationPickerPage

**File:** `lib/pages/location_picker_page.dart`

Interactive map-based location picker or viewer.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `initialPosition` | LatLng? | No | Starting coordinates |
| `viewOnly` | bool | No | Read-only mode (default: false) |

**Returns:** `LatLng` (selected position)

**Usage:**
```dart
final position = await Navigator.push<LatLng>(
  context,
  MaterialPageRoute(
    builder: (_) => LocationPickerPage(
      initialPosition: LatLng(38.7223, -9.1393),
      viewOnly: false,
    ),
  ),
);

if (position != null) {
  print('Selected: ${position.latitude}, ${position.longitude}');
}
```

**Features:**
- Map tap to select location
- Manual latitude/longitude input
- Auto-detect current location
- Zoom in/out controls
- Layer toggle (Standard/Satellite)
- Reset north compass
- Tile caching for offline use
- 6 decimal precision coordinates

---

### PlacePickerPage

**File:** `lib/pages/place_picker_page.dart`

Full-screen place picker with sortable results. Shows all places from the user's place collections with distance calculation and flexible sorting options.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `initialPosition` | Position? | No | Override GPS position for distance calculation |

**Returns:** `PlacePickerResult` with `place`, `collectionTitle`, and `distance`

**Usage:**
```dart
final result = await Navigator.push<PlacePickerResult>(
  context,
  MaterialPageRoute(
    builder: (context) => PlacePickerPage(i18n: widget.i18n),
  ),
);

if (result != null) {
  print('Selected: ${result.place.getName('EN')}');
  print('Distance: ${result.distance?.toStringAsFixed(1)} km');
  print('Collection: ${result.collectionTitle}');
}
```

**Features:**
- **Sort toggle:** Switch between sorting by distance or by time (newest first)
- **GPS-based sorting:** Places sorted by distance from user's current position
- **Time-based sorting:** Places sorted by creation date (newest first)
- **Distance display:** Shows formatted distance next to each place (e.g., "2.2km", "350m")
- **Fallback location:** Uses IP-based geolocation on desktop/web or when GPS is unavailable
- **Full-text search:** Filter places by name, address, description, type, history, region, and collection name (searches all language variants)
- **Location status:** Visual indicators for GPS status (loading, available, unavailable)
- **Multiple collections:** Loads places from all configured place collections

**Sort Modes:**
| Mode | Description |
|------|-------------|
| Distance | Places sorted by proximity to user (closest first) |
| Time | Places sorted by creation date (newest first) |

**Search Fields:**
The search box filters across all of these fields:
- Place name (all language variants)
- Address
- Description (all language variants)
- Type/category
- History
- Region path
- Collection name

**Location Detection Priority:**
1. GPS (mobile with permission)
2. Browser Geolocation API (web)
3. IP-based geolocation (fallback)
4. Alphabetical sort (when location unavailable)

**PlacePickerResult Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `place` | Place | The selected place object |
| `collectionTitle` | String? | Name of the collection the place belongs to |
| `distance` | double? | Distance from user in kilometers (null if location unavailable) |

**Dependencies:**
- `geolocator: ^13.0.2` - GPS location access
- `LocationService` - Distance calculation and IP geolocation

**Required i18n Keys:**
- `choose_place` - Page title
- `search_places` - Search hint
- `no_places_found` - Empty state message
- `sorted_by_distance` - Status text when sorting by distance
- `sorted_by_time` - Status text when sorting by time
- `location_unavailable` - Status when GPS unavailable

---

### ContactPickerPage

**File:** `lib/pages/contact_picker_page.dart`

Full-screen contact picker with search and sorting. Shows all contacts from the user's contact collections with flexible sorting options.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `multiSelect` | bool | No | Enable multiple selection (default: false) |
| `initialSelection` | Set\<String\>? | No | Pre-selected callsigns for multi-select mode |

**Returns:**
- Single select: `ContactPickerResult` with `contact` and `collectionTitle`
- Multi-select: `List<ContactPickerResult>`

**Usage (Single Select):**
```dart
final result = await Navigator.push<ContactPickerResult>(
  context,
  MaterialPageRoute(
    builder: (context) => ContactPickerPage(i18n: widget.i18n),
  ),
);

if (result != null) {
  print('Selected: ${result.contact.displayName}');
  print('Callsign: ${result.contact.callsign}');
  print('Collection: ${result.collectionTitle}');
}
```

**Usage (Multi-Select):**
```dart
final results = await Navigator.push<List<ContactPickerResult>>(
  context,
  MaterialPageRoute(
    builder: (context) => ContactPickerPage(
      i18n: widget.i18n,
      multiSelect: true,
      initialSelection: {'ALPHA1', 'BRAVO2'},
    ),
  ),
);

if (results != null) {
  for (final result in results) {
    print('Selected: ${result.contact.callsign}');
  }
}
```

**Features:**
- **Sort toggle:** Switch between alphabetical (A-Z) and recent (newest first)
- **Full-text search:** Filter contacts by name, callsign, group path, collection, emails, phones, tags, notes
- **Multi-select mode:** Optional checkbox selection for multiple contacts
- **Multiple collections:** Loads contacts from all configured contact collections
- **Visual feedback:** Avatar initials, selected state indicators

**Sort Modes:**
| Mode | Description |
|------|-------------|
| Alphabetical | Contacts sorted A-Z by display name |
| Recent | Contacts sorted by firstSeen date (newest first) |

**Search Fields:**
The search box filters across:
- Display name
- Callsign
- Group path
- Collection name
- Emails
- Phones
- Tags
- Notes

**ContactPickerResult Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `contact` | Contact | The selected contact object |
| `collectionTitle` | String? | Name of the collection the contact belongs to |

**Required i18n Keys:**
- `select_contact` - Page title
- `search_contacts` - Search hint
- `no_contacts_found` - Empty state message
- `sorted_alphabetically` - Status text when sorting A-Z
- `sorted_by_recent` - Status text when sorting by recent

---

### DocumentViewerEditorPage

**File:** `lib/pages/document_viewer_editor_page.dart`

Universal document viewer with auto-detection for text, markdown, and PDF files. Uses continuous vertical scrolling.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filePath` | String | Yes | Path to the document file |
| `viewerType` | DocumentViewerType | No | Force viewer type (default: auto) |
| `title` | String? | No | Custom app bar title (default: filename) |
| `readOnly` | bool | No | Read-only mode (default: true) |

**Viewer Types:**
- `DocumentViewerType.auto` - Detect from file extension (default)
- `DocumentViewerType.text` - Plain text (.txt, .log, .json, .xml, etc.)
- `DocumentViewerType.markdown` - Markdown (.md, .markdown)
- `DocumentViewerType.pdf` - PDF documents
- `DocumentViewerType.cbz` - Comic book archives (future)

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => DocumentViewerEditorPage(
      filePath: '/path/to/document.pdf',
      // viewerType: DocumentViewerType.auto, // optional
      // title: 'My Document', // optional
    ),
  ),
);
```

**Features:**
- Auto-detection from file extension
- Continuous vertical scroll (webtoon-style)
- PDF pages rendered as images for smooth scrolling
- Markdown with styled headings, code blocks, blockquotes
- Plain text with monospace font
- Selectable text
- Page count display for PDFs
- Error handling with retry button

---

### ContractDocumentPage

**File:** `lib/pages/contract_document_page.dart`

Display raw contract/debt document with markdown rendering.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `collectionPath` | String | Yes | Path to the wallet collection |
| `debtId` | String | Yes | ID of the debt to display |
| `i18n` | I18nService | Yes | Localization service |

**Usage:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ContractDocumentPage(
      collectionPath: '/path/to/collection',
      debtId: 'debt-123',
      i18n: widget.i18n,
    ),
  ),
);
```

**Features:**
- Full markdown rendering
- Signature status indicators in app bar
- Selectable text
- Styled headings, blockquotes, code blocks
- Shadow box document container

---

## Player Widgets

### VoicePlayerWidget

**File:** `lib/widgets/voice_player_widget.dart`

Play voice messages with download support.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filePath` | String | Yes | Local file path or remote URL |
| `durationSeconds` | int? | No | Metadata duration for display |
| `isLocal` | bool | No | Whether file is local (default: true) |
| `onDownloadRequested` | Future\<String?\> Function()? | No | Download callback for remote files |
| `backgroundColor` | Color? | No | Background color for widget |

**Usage:**
```dart
VoicePlayerWidget(
  filePath: '/path/to/voice.opus',
  durationSeconds: 15,
  isLocal: true,
  backgroundColor: Colors.blue.shade100,
)
```

**Features:**
- Play/pause/stop controls
- Elapsed/total time display
- Download progress indicator
- Loading state with spinner
- Automatic playback end detection

---

### MusicPlayerWidget

**File:** `lib/widgets/music_player_widget.dart`

Display and play generated music tracks.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `track` | MusicTrack | Yes | Music track object |
| `showGenre` | bool | No | Display genre label (default: true) |
| `showModel` | bool | No | Display model used label (default: true) |
| `backgroundColor` | Color? | No | Bubble background color |
| `onDelete` | VoidCallback? | No | Delete callback |

**Usage:**
```dart
MusicPlayerWidget(
  track: musicTrack,
  showGenre: true,
  showModel: true,
  onDelete: () => deleteTrack(musicTrack.id),
)
```

**Features:**
- Play/pause/stop controls
- Progress bar with seek
- Track info (genre, model, duration)
- Delete button

---

### VoiceRecorderWidget

**File:** `lib/widgets/voice_recorder_widget.dart`

Record and preview voice messages before sending.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `onSend` | void Function(String filePath, int durationSeconds) | Yes | Send callback |
| `onCancel` | VoidCallback | Yes | Cancel callback |

**Usage:**
```dart
VoiceRecorderWidget(
  onSend: (filePath, duration) {
    sendVoiceMessage(filePath, duration);
  },
  onCancel: () {
    setState(() => _showRecorder = false);
  },
)
```

**Features:**
- Recording state with animated dot
- Duration timer (max 30 seconds)
- Preview playback with progress
- Seek during preview
- Cancel/Delete and Send buttons

---

## Dialog Widgets

### NewChannelDialog

**File:** `lib/widgets/new_channel_dialog.dart`

Create new chat channels (direct message or group).

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `existingChannelIds` | List\<String\> | Yes | Existing IDs for validation |
| `knownCallsigns` | List\<String\> | Yes | Available participants for groups |

**Returns:** `ChatChannel` object

**Usage:**
```dart
final channel = await showDialog<ChatChannel>(
  context: context,
  builder: (_) => NewChannelDialog(
    existingChannelIds: existingIds,
    knownCallsigns: callsigns,
  ),
);

if (channel != null) {
  createChannel(channel);
}
```

**Features:**
- Toggle between Direct Message and Group
- Form validation
- Participant selection with FilterChips
- Duplicate ID detection

---

### NewThreadDialog

**File:** `lib/widgets/new_thread_dialog.dart`

Create new forum threads with title and content.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `existingThreadTitles` | List\<String\> | Yes | For duplicate detection |
| `maxTitleLength` | int | No | Max title length (default: 100) |
| `maxContentLength` | int | No | Max content length (default: 5000) |

**Returns:** `Map<String, String>` with 'title' and 'content' keys

**Usage:**
```dart
final result = await showDialog<Map<String, String>>(
  context: context,
  builder: (_) => NewThreadDialog(
    existingThreadTitles: titles,
    maxTitleLength: 100,
  ),
);

if (result != null) {
  createThread(result['title']!, result['content']!);
}
```

**Features:**
- Title and content validation
- Duplicate title detection
- Character counters
- Helpful tip box

---

### AddTrackableDialog

**File:** `lib/tracker/dialogs/add_trackable_dialog.dart`

Unified dialog for adding exercise or measurement entries. Replaces separate AddExerciseDialog and AddMeasurementDialog with a single implementation.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `service` | TrackerService | Yes | Tracker service for saving entries |
| `i18n` | I18nService | Yes | Localization service |
| `kind` | TrackableKind | Yes | Type: exercise or measurement |
| `preselectedTypeId` | String? | No | Pre-select a specific type (hides dropdown) |
| `year` | int | Yes | Year for storage |

**Static Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `showExercise(context, ...)` | `Future<bool?>` | Show dialog for exercise entry |
| `showMeasurement(context, ...)` | `Future<bool?>` | Show dialog for measurement entry |

**Usage (Exercise):**
```dart
final saved = await AddTrackableDialog.showExercise(
  context,
  service: trackerService,
  i18n: widget.i18n,
  year: DateTime.now().year,
  preselectedTypeId: 'pushups', // Optional: pre-select type
);

if (saved == true) {
  // Entry was saved, refresh data
  await loadExercises();
}
```

**Usage (Measurement):**
```dart
final saved = await AddTrackableDialog.showMeasurement(
  context,
  service: trackerService,
  i18n: widget.i18n,
  year: DateTime.now().year,
  preselectedTypeId: 'weight', // Optional: pre-select type
);

if (saved == true) {
  await loadMeasurements();
}
```

**Supported Types:**

Exercises (TrackableKind.exercise):
| ID | Name | Unit | Max | Category |
|----|------|------|-----|----------|
| pushups | Push-ups | reps | 100 | Strength |
| abdominals | Abdominals | reps | 100 | Strength |
| squats | Squats | reps | 100 | Strength |
| pullups | Pull-ups | reps | 100 | Strength |
| lunges | Lunges | reps | 100 | Strength |
| planks | Planks | seconds | 300 | Strength |
| running | Running | meters | 50000 | Cardio |
| walking | Walking | meters | 50000 | Cardio |
| cycling | Cycling | meters | 100000 | Cardio |
| swimming | Swimming | meters | 10000 | Cardio |

Measurements (TrackableKind.measurement):
| ID | Name | Unit | Range | Decimals |
|----|------|------|-------|----------|
| weight | Weight | kg | 0-500 | 1 |
| height | Height | cm | 0-300 | 1 |
| heart_rate | Heart Rate | bpm | 0-300 | 0 |
| blood_glucose | Blood Glucose | mg/dL | 0-600 | 0 |
| body_fat | Body Fat | % | 0-100 | 1 |
| body_temperature | Temperature | °C | 30-45 | 1 |
| body_water | Body Water | % | 0-100 | 1 |
| muscle_mass | Muscle Mass | kg | 0-200 | 1 |
| blood_pressure | Blood Pressure | mmHg | Special | N/A |

**Input Modes:**

1. **Integer Dropdown** (exercises, heart_rate, blood_glucose):
   - Dropdown from 1 to maxCount
   - Remembers last selected value per type
   - Stored in ConfigService: `tracker.lastValue.{typeId}`

2. **Decimal Field** (weight, body_fat, etc.):
   - Text field with decimal keyboard
   - Validates min/max range
   - Shows unit suffix

3. **Blood Pressure** (special case):
   - Separate systolic/diastolic fields (required)
   - Optional heart rate field
   - Validates: systolic 50-300, diastolic 30-200

**Features:**
- Type dropdown (hidden when preselectedTypeId is set)
- Duration field for cardio exercises (minutes)
- Notes field with voice-to-text transcription button
- Remembers last value for integer types
- Form validation with localized error messages
- Loading state with spinner during save

**Related Models:**

`TrackableTypeConfig` (lib/tracker/models/trackable_type.dart):
```dart
enum TrackableKind { exercise, measurement }
enum TrackableCategory { strength, cardio, flexibility, health }

class TrackableTypeConfig {
  final String id;
  final String displayName;
  final String unit;
  final TrackableKind kind;
  final TrackableCategory category;
  final int decimalPlaces;    // 0 for integers
  final double? minValue;
  final double? maxValue;
  final int? maxCount;        // For dropdown max

  bool get isExercise;
  bool get isMeasurement;
  bool get isInteger;
  bool get isCardio;

  static Map<String, TrackableTypeConfig> builtInTypes;
  static Map<String, TrackableTypeConfig> exerciseTypes;
  static Map<String, TrackableTypeConfig> measurementTypes;
}
```

**Required i18n Keys:**
- `tracker_add_exercise`, `tracker_add_measurement`
- `tracker_exercise_type`, `tracker_measurement_type`
- `tracker_count`, `tracker_distance_meters`, `tracker_duration_minutes`
- `tracker_value`, `tracker_notes`
- `tracker_required_field`, `tracker_invalid_number`
- `tracker_required`, `tracker_invalid`
- `tracker_systolic`, `tracker_diastolic`, `tracker_heart_rate_optional`
- `tracker_min`, `tracker_max`
- `tracker_blood_pressure`
- `tracker_exercise_{id}` for each exercise type
- `tracker_measurement_{id}` for each measurement type
- `save`, `cancel`

---

## Selector Widgets

### CallsignSelectorWidget

**File:** `lib/widgets/callsign_selector_widget.dart`

Switch between multiple callsigns/profiles.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `onProfileSwitch` | Function(Profile)? | No | Callback on profile switch |
| `onCreateNewProfile` | VoidCallback? | No | Custom create handler |
| `showCreateOption` | bool | No | Show "add new callsign" option |
| `compact` | bool | No | Compact chip vs full list mode |

**Usage:**
```dart
// Full mode
CallsignSelectorWidget(
  onProfileSwitch: (profile) => switchTo(profile),
  showCreateOption: true,
  compact: false,
)

// Compact mode (for tight spaces)
CallsignSelectorWidget(
  compact: true,
)
```

**Features:**
- Two display modes: compact (dropdown chip) and full (expandable list)
- Profile avatar display
- Active profile indicator
- Create new profile dialog
- Relay profile badge

---

### ProfileSwitcher

**File:** `lib/widgets/profile_switcher.dart`

App bar widget for profile switching with popup menu.

**Usage:**
```dart
AppBar(
  title: const Text('App Title'),
  actions: [
    ProfileSwitcher(),
  ],
)
```

**Features:**
- Popup menu on tap
- Profile avatar with custom images
- Nickname and callsign display
- Navigate to profile management

---

## Map Widgets

### TrackerMapCard

**File:** `lib/tracker/widgets/tracker_map_card.dart`

Reusable satellite map card widget for the Tracker feature. Displays a map with optional markers, polylines, and overlays. Supports auto-fitting to bounds and fullscreen expansion.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `points` | List\<LatLng\> | Yes | Points used to calculate map bounds (auto-fit camera) |
| `markers` | List\<Marker\> | No | Markers to display on the map (default: []) |
| `polylines` | List\<Polyline\>? | No | Optional polylines to draw (paths, routes) |
| `height` | double | No | Card height in pixels (default: 260) |
| `onTap` | VoidCallback? | No | Callback when map is tapped (not on marker) |
| `onFullscreen` | VoidCallback? | No | Callback for fullscreen button press |
| `bottomLeftOverlay` | Widget? | No | Optional overlay widget at bottom-left (e.g., city label) |
| `showTransportLabels` | bool | No | Show transport/road labels (default: false) |
| `boundsPadding` | EdgeInsets | No | Padding around bounds (default: EdgeInsets.all(32)) |
| `fallbackCenter` | LatLng | No | Fallback center when no points (default: LatLng(0, 0)) |
| `fallbackZoom` | double | No | Fallback zoom level (default: 14) |

**Usage:**
```dart
TrackerMapCard(
  points: [
    LatLng(40.7128, -74.0060),
    LatLng(40.7580, -73.9855),
  ],
  markers: [
    Marker(
      point: LatLng(40.7128, -74.0060),
      width: 40,
      height: 40,
      child: Icon(Icons.location_on, color: Colors.red),
    ),
  ],
  height: 300,
  showTransportLabels: true,
  onFullscreen: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => FullscreenMapPage()),
  ),
  bottomLeftOverlay: MapLabelOverlay(text: 'New York'),
)
```

**Features:**
- **Satellite tiles** with borders and labels overlay
- **Auto-fit camera** to show all points with padding
- **Fullscreen button** (optional, top-right)
- **Marker layer** for custom markers
- **Polyline layer** for paths/routes
- **Transport labels** for road names (optional)
- **Offline tile handling** with warning indicator
- **MapLabelOverlay helper** for styled bottom-left labels

**MapLabelOverlay Helper:**
```dart
// Use for consistent styled labels on the map
TrackerMapCard(
  points: points,
  bottomLeftOverlay: MapLabelOverlay(text: 'Lisbon → Madrid'),
)
```

**Example: Path Display:**
```dart
// Display a recorded path with start/end markers
TrackerMapCard(
  points: pathPoints.map((p) => LatLng(p.lat, p.lon)).toList(),
  markers: [
    Marker(
      point: LatLng(pathPoints.first.lat, pathPoints.first.lon),
      child: Icon(Icons.trip_origin, color: Colors.green),
    ),
    Marker(
      point: LatLng(pathPoints.last.lat, pathPoints.last.lon),
      child: Icon(Icons.flag, color: Colors.red),
    ),
  ],
  polylines: [
    Polyline(
      points: pathPoints.map((p) => LatLng(p.lat, p.lon)).toList(),
      strokeWidth: 3,
      color: Colors.blue,
    ),
  ],
  onTap: () => openFullscreenMap(),
)
```

**Example: Proximity Contacts:**
```dart
// Display contact locations with tap handlers
TrackerMapCard(
  points: clusters.map((c) => LatLng(c.lat, c.lon)).toList(),
  markers: clusters.map((cluster) => Marker(
    point: LatLng(cluster.lat, cluster.lon),
    width: 40,
    height: 40,
    child: GestureDetector(
      onTap: () => showClusterDetails(cluster),
      child: CircleAvatar(
        backgroundColor: Colors.blue,
        child: Text('${cluster.count}'),
      ),
    ),
  )).toList(),
  height: 300,
  showTransportLabels: true,
)
```

**Tile Layers:**
The widget uses these tile layers in order:
1. Satellite base layer (MapTileService)
2. Borders overlay with enhanced contrast
3. Labels layer (place names)
4. Transport labels (road names) - optional

**Dependencies:**
- `flutter_map: ^7.0.0` - Map widget
- `latlong2: ^0.9.1` - Coordinates
- `MapTileService` - Tile management and caching

---

## Tree Widgets

### FolderTreeWidget

**File:** `lib/widgets/inventory/folder_tree_widget.dart`

Display hierarchical folder structure for navigation.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `selectedPath` | List\<String\> | Yes | Current selected path |
| `onFolderSelected` | ValueChanged\<List\<String\>\> | Yes | Selection callback |
| `onCreateFolder` | VoidCallback? | No | Create folder action |
| `onItemDropped` | OnItemDropped? | No | Drag & drop callback |
| `onFolderAction` | OnFolderAction? | No | Context menu actions |

**Usage:**
```dart
FolderTreeWidget(
  i18n: widget.i18n,
  selectedPath: ['folder1', 'subfolder'],
  onFolderSelected: (path) {
    setState(() => _currentPath = path);
  },
  onCreateFolder: () => showCreateFolderDialog(),
)
```

**Features:**
- Recursive folder expansion
- Lazy loading of subfolders
- Drag & drop support
- Context menu for folder actions
- Auto-expand selected path

---

## Message Widgets

### MessageBubbleWidget

**File:** `lib/widgets/message_bubble_widget.dart`

Display individual chat messages with rich content support.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `message` | ChatMessage | Yes | Message object |
| `isGroupChat` | bool | No | Group vs DM display |
| `onFileOpen` | VoidCallback? | No | File open callback |
| `onLocationView` | VoidCallback? | No | Location view callback |
| `onDelete` | VoidCallback? | No | Delete callback |
| `onQuote` | VoidCallback? | No | Quote/reply callback |
| `onReact` | Function(String)? | No | Reaction callback |
| `voiceFilePath` | String? | No | Voice file path |
| `canDelete` | bool | No | Permission to delete |

**Features:**
- Text message display
- File attachments
- Voice message playback
- Image display
- Location map preview
- Reaction emoji system (7 reactions)
- Quote/reply preview
- Hide/unhide messages

---

### MessageInputWidget

**File:** `lib/widgets/message_input_widget.dart`

Text input for composing chat messages.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `onSend` | Function(String, String?) | Yes | Send callback (content, filePath) |
| `maxLength` | int | No | Max message length (default: 500) |
| `allowFiles` | bool | No | Enable file attachments |
| `onMicPressed` | VoidCallback? | No | Microphone button callback |
| `quotedMessage` | ChatMessage? | No | Quote/reply context |
| `onClearQuote` | VoidCallback? | No | Clear quote callback |

**Usage:**
```dart
MessageInputWidget(
  onSend: (content, filePath) {
    sendMessage(content, filePath);
  },
  maxLength: 500,
  allowFiles: true,
  onMicPressed: () => showVoiceRecorder(),
  quotedMessage: _replyingTo,
  onClearQuote: () => setState(() => _replyingTo = null),
)
```

**Features:**
- Text input with max length
- File/image attachment
- Quote preview
- Mic button for voice
- Character counter

---

## Services

### LocationService

**File:** `lib/services/location_service.dart`

Find nearest cities and country information from GPS coordinates using the worldcities database (~44,000 cities).

**Initialization:**
```dart
final locationService = LocationService();
await locationService.init();
```

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `findNearestCity(lat, lng)` | `NearestCityResult?` | Find the single nearest city |
| `findNearestCities(lat, lng, {count})` | `List<NearestCityResult>` | Find N nearest cities (default: 5) |
| `findCityByName(name)` | `CityEntry?` | Search city by name (case-insensitive) |
| `getNearestCityEntry(lat, lng)` | `CityEntry?` | Get full city data for nearest city |
| `detectJurisdiction(lat, lng)` | `JurisdictionInfo?` | Get jurisdiction info for legal docs |
| `calculateDistance(lat1, lng1, lat2, lng2)` | `double` | Distance in km (Haversine formula) |
| `getAllCountries()` | `List<String>` | All unique countries sorted |

**NearestCityResult Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `country` | String | Country name |
| `iso2` | String | ISO 3166-1 alpha-2 code (e.g., "US", "PT") |
| `iso3` | String | ISO 3166-1 alpha-3 code (e.g., "USA", "PRT") |
| `adminName` | String | Region/state/province name |
| `city` | String | City name (ASCII) |
| `capital` | String | "primary", "admin", or empty |
| `distance` | double | Distance in kilometers |
| `folderPath` | String | Sanitized path: Country/Region/City |

**CityEntry Fields:**
All of the above plus: `lat`, `lng`, `population`, `id`

**JurisdictionInfo Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `country` | String | Country name |
| `region` | String? | Region/state/province name |
| `city` | String? | City name |
| `countryCode` | String? | ISO2 country code |
| `fullJurisdiction` | String | Formatted: "Region, Country" or "Country" |

**Usage Examples:**

```dart
// Find nearest city to coordinates
final result = await LocationService().findNearestCity(38.7223, -9.1393);
if (result != null) {
  print('${result.city}, ${result.country} (${result.iso2})');
  print('Distance: ${result.distance.toStringAsFixed(1)} km');
  print('Folder path: ${result.folderPath}');
}

// Find 10 nearest cities
final cities = await LocationService().findNearestCities(
  38.7223, -9.1393,
  count: 10,
);
for (final city in cities) {
  print('${city.city}: ${city.distance.toStringAsFixed(1)} km');
}

// Search city by name
final tokyo = await LocationService().findCityByName('Tokyo');
if (tokyo != null) {
  print('${tokyo.city}, ${tokyo.country}');
  print('Population: ${tokyo.population}');
  print('Coordinates: ${tokyo.lat}, ${tokyo.lng}');
}

// Calculate distance between two points
final distance = LocationService().calculateDistance(
  38.7223, -9.1393,  // Lisbon
  40.4168, -3.7038,  // Madrid
);
print('Distance: ${distance.toStringAsFixed(0)} km');

// Detect jurisdiction for legal documents
final jurisdiction = await LocationService().detectJurisdiction(38.7223, -9.1393);
if (jurisdiction != null) {
  print('Jurisdiction: ${jurisdiction.fullJurisdiction}');
  print('Country code: ${jurisdiction.countryCode}');
}
```

**Database:** `assets/worldcities.csv` (SimpleMaps World Cities Database)

---

### LocationProviderService

**File:** `lib/services/location_provider_service.dart`

Singleton service that maintains a GPS lock and provides positions to multiple consumers. Instead of each app/feature acquiring its own GPS lock, they can request the already-locked position from this shared service.

**Key Benefits:**
- **Battery efficient:** Single GPS lock shared across all consumers
- **Already locked position:** Get accurate GPS immediately without waiting for lock
- **Consumer management:** Auto-starts when first consumer registers, auto-stops when last one unregisters
- **Cross-app sharing:** Write position to shared file for external app access

**Initialization:**
```dart
final service = LocationProviderService();

// Option 1: Register as a consumer (recommended)
final dispose = await service.registerConsumer(
  intervalSeconds: 30,
  onPosition: (pos) => print('Got position: $pos'),
);

// When done, call dispose to unregister
dispose();

// Option 2: Manual start/stop
await service.start(
  intervalSeconds: 30,
  sharedFilePath: '/path/to/shared/location.json', // optional
);
service.stop();
```

**Getting the Current Locked Position:**
```dart
final service = LocationProviderService();

// Check if we have a valid, fresh position
if (service.hasValidPosition) {
  final pos = service.currentPosition!;
  print('Using locked position: ${pos.latitude}, ${pos.longitude}');
  print('Accuracy: ${pos.accuracy}m');
  print('Age: ${DateTime.now().difference(pos.timestamp).inSeconds}s');
}

// Or request an immediate position (blocks until GPS lock)
final pos = await service.requestImmediatePosition();
if (pos != null) {
  print('Got position: $pos');
}
```

**Listening to Position Updates (EventBus - Recommended):**
```dart
import '../util/event_bus.dart';

// Subscribe to PositionUpdatedEvent via EventBus (decoupled, no loops)
final subscription = EventBus().on<PositionUpdatedEvent>((event) {
  print('New position: ${event.latitude}, ${event.longitude}');
  print('Source: ${event.source}'); // 'gps', 'network', 'ip'
  print('Accuracy: ${event.accuracy}m');
});

// Cancel when done
subscription.cancel();
```

**Alternative: Stream or ChangeNotifier**
```dart
// Real-time stream of positions
service.positionStream.listen((pos) {
  print('New position: ${pos.latitude}, ${pos.longitude}');
  print('Source: ${pos.source}'); // 'gps', 'network', 'ip'
});

// Or use ChangeNotifier
service.addListener(() {
  final pos = service.currentPosition;
  if (pos != null) updateUI(pos);
});
```

**Cross-App Position Sharing:**
```dart
// App A: Start service with shared file
await LocationProviderService().start(
  intervalSeconds: 30,
  sharedFilePath: '/data/shared/current_location.json',
);

// App B: Read the shared position (static method, no service needed)
final pos = await LocationProviderService.readSharedPosition(
  '/data/shared/current_location.json',
);
if (pos != null && pos.isFresh()) {
  print('Got shared position: $pos');
}
```

**LockedPosition Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `latitude` | double | Latitude in degrees |
| `longitude` | double | Longitude in degrees |
| `altitude` | double | Altitude in meters |
| `accuracy` | double | Horizontal accuracy in meters |
| `speed` | double | Speed in m/s |
| `heading` | double | Heading in degrees |
| `timestamp` | DateTime | When position was acquired |
| `source` | String | Position source: 'gps', 'network', 'ip', 'browser' |

**LockedPosition Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `isFresh({maxAge})` | bool | Check if position is within maxAge (default: 5 min) |
| `isHighAccuracy` | bool | True if accuracy < 50m |
| `toJson()` | Map | Serialize for storage/sharing |

**Service Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `isRunning` | bool | Service is actively acquiring positions |
| `currentPosition` | LockedPosition? | Latest position (may be null) |
| `hasValidPosition` | bool | Has a fresh, valid position |
| `consumerCount` | int | Number of active consumers |
| `positionStream` | Stream | Real-time position updates |

**Platform Support:**

| Platform | Method | Background Support |
|----------|--------|-------------------|
| Android | Foreground Service | Yes - persistent notification |
| iOS | Position Stream | Yes - background location indicator |
| Desktop | Timer + Geolocator | Limited - foreground only |
| Web | Timer + Browser API | Limited - tab must be active |

**Example: Multiple Features Sharing GPS:**
```dart
// Feature 1: Path recording
final disposeForPath = await LocationProviderService().registerConsumer(
  intervalSeconds: 60,
  onPosition: (pos) => recordPathPoint(pos),
);

// Feature 2: Proximity detection (same GPS, different interval ignored)
final disposeForProximity = await LocationProviderService().registerConsumer(
  intervalSeconds: 30,
  onPosition: (pos) => checkNearbyUsers(pos),
);

// Feature 3: Just needs current position occasionally
void shareLocation() {
  final pos = LocationProviderService().currentPosition;
  if (pos != null && pos.isFresh()) {
    sendLocationToContact(pos);
  }
}

// When features are done
disposeForPath();
disposeForProximity();
// Service auto-stops when all consumers unregister
```

**Dependencies:**
- `geolocator: ^13.0.2` - GPS location access
- Location permissions required (handled automatically)

---

### PathRecordingService

**File:** `lib/tracker/services/path_recording_service.dart`

GPS path recording service with crash recovery and platform-specific optimizations. Uses [LocationProviderService](#locationproviderservice) for GPS positioning, so it shares the GPS lock with other consumers.

**Initialization:**
```dart
final recordingService = PathRecordingService();
recordingService.initialize(trackerService);
recordingService.addListener(_onRecordingChanged);

// Check for active recording from app restart/crash
await recordingService.checkAndResumeRecording();
```

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `startRecording(pathType, title, ...)` | `Future<TrackerPath?>` | Start new GPS recording |
| `pauseRecording()` | `Future<bool>` | Pause current recording |
| `resumeRecording()` | `Future<bool>` | Resume paused recording |
| `stopRecording()` | `Future<TrackerPath?>` | Stop and complete recording |
| `cancelRecording()` | `Future<bool>` | Cancel and discard recording |
| `checkAndResumeRecording()` | `Future<bool>` | Resume from crash recovery |

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `isRecording` | bool | Currently recording GPS points |
| `isPaused` | bool | Recording is paused |
| `hasActiveRecording` | bool | Has an active (recording or paused) session |
| `activePathId` | String? | Current path ID |
| `pointCount` | int | Number of recorded GPS points |
| `totalDistance` | double | Total distance in meters |
| `elapsedTime` | Duration | Time since recording started |
| `recordingState` | TrackerRecordingState? | Full state object |

**StartRecording Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pathType` | TrackerPathType | Yes | Type of path (walk, run, bicycle, etc.) |
| `title` | String | Yes | Path title |
| `description` | String? | No | Optional description |
| `intervalSeconds` | int | No | GPS capture interval (default: 60) |

**Path Types:**

| Type | ID | Icon | Description |
|------|----|------|-------------|
| walk | walk | directions_walk | Walking path |
| run | run | directions_run | Running/jogging |
| bicycle | bicycle | directions_bike | Bicycle ride |
| car | car | directions_car | Car trip |
| train | train | train | Train journey |
| airplane | airplane | flight | Flight path |
| hike | hike | terrain | Hiking trail |
| other | other | route | Generic path |

**Usage Example:**

```dart
// Start recording
final path = await recordingService.startRecording(
  pathType: TrackerPathType.walk,
  title: 'Morning Walk - Jan 8',
  description: 'Around the park',
  intervalSeconds: 60,  // Record every minute
);

if (path != null) {
  print('Recording started: ${path.id}');
}

// Monitor recording state
recordingService.addListener(() {
  print('Points: ${recordingService.pointCount}');
  print('Distance: ${recordingService.totalDistance / 1000} km');
  print('Time: ${recordingService.elapsedTime}');
});

// Pause/resume
await recordingService.pauseRecording();
await recordingService.resumeRecording();

// Stop and save
final completedPath = await recordingService.stopRecording();
if (completedPath != null) {
  print('Recording complete: ${completedPath.totalDistanceMeters}m');
}
```

**Platform Support:**

| Platform | Method | Background Support | Notes |
|----------|--------|-------------------|-------|
| Android | Foreground Service + Geolocator | Yes | Persistent notification shows recording status |
| iOS | Geolocator position stream | Yes | Background location indicator, requires `allowBackgroundLocationUpdates` |
| Desktop | Timer + Geolocator | Limited | Falls back to IP geolocation when GPS unavailable |
| Web | Timer + Browser Geolocation | Limited | Uses browser Geolocation API via geolocator_web |

**Android Foreground Service:**

The service uses Geolocator's built-in foreground notification on Android:

```dart
AndroidSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 0,
  intervalDuration: Duration(seconds: intervalSeconds),
  foregroundNotificationConfig: ForegroundNotificationConfig(
    notificationTitle: 'Recording Path',
    notificationText: 'GPS tracking is active',
    enableWakeLock: true,
  ),
)
```

**iOS Background Settings:**

```dart
AppleSettings(
  accuracy: LocationAccuracy.high,
  activityType: ActivityType.fitness,
  pauseLocationUpdatesAutomatically: false,
  allowBackgroundLocationUpdates: true,
  showBackgroundLocationIndicator: true,
)
```

**Crash Recovery:**

Recording state is persisted to disk, allowing recovery after app crashes or restarts:

```dart
// State stored at: {collection}/recording_state.json
class TrackerRecordingState {
  final String activePathId;
  final int activePathYear;
  final RecordingStatus status;
  final int intervalSeconds;
  final String startedAt;
  final String? lastPointTimestamp;
  final int pointCount;
}

// On app startup, check for active recording:
final resumed = await recordingService.checkAndResumeRecording();
if (resumed) {
  print('Resumed recording from crash recovery');
}
```

**GPS Unavailable Handling:**

When GPS/Internet is unavailable, the service skips recording points rather than saving empty values. Recording continues automatically when position data becomes available again.

**Storage Format:**

Paths are stored in year-based folders:
```
{collection}/paths/{YYYY}/{pathId}/
  ├── path.json      # Path metadata (title, status, tags, etc.)
  └── points.json    # GPS points array
```

**Point Data Structure:**

```dart
class TrackerPoint {
  final int index;
  final String timestamp;
  final double lat;
  final double lon;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
}
```

**Dependencies:**
- `geolocator: ^13.0.2` - GPS location access with platform-specific settings
- Requires location permissions: `ACCESS_FINE_LOCATION` (Android), `NSLocationWhenInUseUsageDescription` (iOS)
- For background on Android: `FOREGROUND_SERVICE_LOCATION` permission
- For background on iOS: `NSLocationAlwaysAndWhenInUseUsageDescription`

**Integration with UI:**

Use with `StartPathDialog` and `ActiveRecordingBanner`:

```dart
// Show start dialog
final path = await StartPathDialog.show(
  context,
  recordingService: _recordingService,
  i18n: widget.i18n,
);

// Show recording banner in your UI
if (_recordingService.hasActiveRecording)
  ActiveRecordingBanner(
    recordingService: _recordingService,
    i18n: widget.i18n,
    onStop: _loadPaths,
  ),
```

**Required i18n Keys:**
- `tracker_start_path`, `tracker_stop_path`, `tracker_pause_path`, `tracker_resume_path`
- `tracker_path_type`, `tracker_path_title`, `tracker_path_description`
- `tracker_gps_interval`, `tracker_recording_in_progress`, `tracker_recording_paused`
- `tracker_path_type_walk/run/bicycle/car/train/airplane/hike/other`
- `tracker_interval_30s/1m/2m/5m`
- `tracker_gps_permission_required`, `tracker_gps_disabled`
- `tracker_morning`, `tracker_afternoon`, `tracker_evening`, `tracker_night`
- `tracker_confirm_stop`, `tracker_confirm_stop_message`

---

### PlaceService.findPlacesWithinRadius

**File:** `lib/services/place_service.dart`

Find all saved places within a given radius from GPS coordinates. Uses disk cache for fast lookups that auto-updates when places change.

**Static Method:**
```dart
static Future<List<PlaceWithDistance>> findPlacesWithinRadius({
  required double lat,
  required double lon,
  required double radiusMeters,
})
```

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `lat` | double | Yes | Latitude of search center |
| `lon` | double | Yes | Longitude of search center |
| `radiusMeters` | double | Yes | Search radius in meters |

**Returns:** `List<PlaceWithDistance>` - Places found within the radius

**PlaceWithDistance Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Place name |
| `lat` | double | Place latitude |
| `lon` | double | Place longitude |
| `folderPath` | String | Full path to the place folder |
| `distanceMeters` | double | Distance from search center |

**Usage:**
```dart
final nearbyPlaces = await PlaceService.findPlacesWithinRadius(
  lat: 52.428919,
  lon: 10.800239,
  radiusMeters: 100,
);

for (final place in nearbyPlaces) {
  print('${place.name} is ${place.distanceMeters.toStringAsFixed(0)}m away');
  print('Location: ${place.lat}, ${place.lon}');
  print('Folder: ${place.folderPath}');
}
```

**Caching:**
- Cache stored at `{baseDir}/places/cache.json`
- Automatically updates when places are added/removed (compares folder paths)
- First call scans all device folders and creates cache
- Subsequent calls use cache (faster)
- Call `PlaceService.refreshPlacesCache()` to force refresh

**Debug Logging:**
The function logs detailed information for troubleshooting:
```
PlaceService.findPlacesWithinRadius: Searching at (52.43, 10.80) with radius 100m
PlaceService.findPlacesWithinRadius: Loaded 15 places from cache
PlaceService.findPlacesWithinRadius: "My Place" is 45m away (within range)
PlaceService.findPlacesWithinRadius: Found 2 places within 100m
```

**Directory Structure Supported:**
The function scans both directory structures:
- `{devicesDir}/{callsign}/places/places/...` (nested structure)
- `{devicesDir}/{callsign}/places/...` (flat structure)

**Force Refresh Cache:**
```dart
// Force rescan all places and update cache
await PlaceService.refreshPlacesCache();
```

**CachedPlaceEntry Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Place name |
| `lat` | double | Place latitude |
| `lon` | double | Place longitude |
| `folderPath` | String | Full path to place folder |

**Cache File Format:**
```json
{
  "updated": "2026-01-12T10:30:00.000Z",
  "places": [
    {
      "name": "My Place",
      "lat": 52.428919,
      "lon": 10.800239,
      "folderPath": "/data/.../places/Germany/Lower_Saxony/Wolfsburg/my_place"
    }
  ]
}
```

**Algorithm:** Uses Haversine formula for accurate distance calculation on Earth's surface.

**Example: Proximity Detection in Tracker:**
```dart
// Check for nearby places every scan
Future<void> _checkNearbyPlaces(double lat, double lon) async {
  final nearbyPlaces = await PlaceService.findPlacesWithinRadius(
    lat: lat,
    lon: lon,
    radiusMeters: 100, // 100 meter radius
  );

  for (final place in nearbyPlaces) {
    // Record proximity detection for each nearby place
    await recordPlaceProximity(place);
  }
}
```

---

### CollectionService.generateBlogCache

**File:** `lib/services/collection_service.dart`

Scans a blog collection folder and generates a `cache.json` file containing metadata for all blog posts. This cache is used by the www homepage to display links to available blogs.

**Signature:**
```dart
Future<Map<String, dynamic>> generateBlogCache(String blogCollectionPath) async
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `blogCollectionPath` | String | Absolute path to the blog collection folder |

**Returns:** `Map<String, dynamic>` containing all posts metadata

**Output File:** `{blogCollectionPath}/cache.json`

**Cache JSON Structure:**
```json
{
  "generated": "2025-01-12T10:30:00.000Z",
  "totalPosts": 5,
  "publishedCount": 3,
  "draftCount": 2,
  "posts": [
    {
      "id": "2025-01-10_my-first-post",
      "title": "My First Post",
      "author": "CR7BBQ",
      "created": "2025-01-10 10:00_00",
      "edited": null,
      "description": "A short description",
      "status": "published",
      "tags": ["welcome", "intro"],
      "year": "2025",
      "path": "2025/2025-01-10_my-first-post/post.md"
    }
  ]
}
```

**Post Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Post folder name |
| `title` | string | Post title from `# BLOG: <title>` |
| `author` | string | Author callsign |
| `created` | string | Creation timestamp |
| `edited` | string? | Edit timestamp (null if never edited) |
| `description` | string? | Post description |
| `status` | string | "published" or "draft" |
| `tags` | string[] | Post tags |
| `year` | string | Year subdirectory |
| `path` | string | Relative path to post.md |

**Usage:**
```dart
final collectionService = CollectionService();
final cache = await collectionService.generateBlogCache('/path/to/blog');

// Get published posts only
final published = (cache['posts'] as List)
    .where((p) => p['status'] == 'published')
    .toList();
print('Found ${published.length} published posts');
```

**Blog Folder Structure:**
```
blog/
├── cache.json              # Generated cache file
├── collection.js
├── 2024/
│   └── 2024-12-20_year-review/
│       └── post.md
└── 2025/
    └── 2025-01-10_my-first-post/
        └── post.md
```

**Notes:**
- Cache is regenerated on each call
- Only folders containing `post.md` are included
- Posts sorted by created date (newest first)
- Used by www homepage to display blog links

---

### StunServerService

**File:** `lib/services/stun_server_service.dart`

Self-hosted STUN server implementing RFC 5389 Binding method for WebRTC NAT traversal. Replaces external STUN servers (Google, Twilio, Mozilla) with privacy-respecting self-hosted capability on station servers.

**Key Methods:**
```dart
Future<bool> start({int port = 3478}) async  // Start UDP server
Future<void> stop() async                     // Stop server
Map<String, dynamic> getStatus()              // Get server status for API
```

**Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `isRunning` | bool | Whether STUN server is running |
| `port` | int | Current UDP port (valid when running) |
| `requestsHandled` | int | Requests handled since start |

**Protocol Flow:**
1. Client sends UDP Binding Request to port 3478
2. Server responds with XOR-MAPPED-ADDRESS (client's public IP:port)
3. WebRTC uses this reflexive address for NAT traversal

**Integration with Station:**
```dart
// In StationServerSettings (station_server_service.dart)
bool stunServerEnabled = true;  // Default: enabled
int stunServerPort = 3478;      // Standard STUN port

// In hello_ack response to clients
'stun_server': {
  'enabled': true,
  'port': 3478,
}
```

**Client Usage:**
```dart
// websocket_service.dart stores STUN info from hello_ack
StationStunInfo? get connectedStationStunInfo

// webrtc_peer_manager.dart uses station STUN
WebRTCConfig.withStationStun(
  stationHost: 'station.example.com',
  stunPort: 3478,
)
```

**Test Script:**
```bash
dart run bin/stun_test.dart localhost 3478
```

**Privacy Benefits:**
- No client IPs logged by STUN server
- No external dependencies or third-party contacts
- No Google/Twilio/Mozilla STUN servers
- LAN connections work without any external servers

---

### VideoMetadataExtractor

**File:** `lib/util/video_metadata_extractor.dart`

Cross-platform video metadata extraction and thumbnail generation using `media_kit`. Works on all platforms (Windows, Linux, macOS, Android, iOS) without requiring FFmpeg CLI installation.

**Key Methods:**
```dart
// Extract video metadata (duration, resolution, file size)
static Future<VideoMetadata?> extract(String videoPath) async

// Generate thumbnail at specific timestamp
static Future<String?> generateThumbnail(
  String videoPath,
  String outputPath, {
  int atSeconds = 1,
  int width = 1280,  // ignored - media_kit returns native resolution
}) async

// Get recommended thumbnail time (10% of duration)
static int getRecommendedThumbnailTime(int durationSeconds)
```

**VideoMetadata Class:**
| Property | Type | Description |
|----------|------|-------------|
| `duration` | int | Duration in seconds |
| `width` | int | Video width in pixels |
| `height` | int | Video height in pixels |
| `fileSize` | int | File size in bytes |
| `mimeType` | String | MIME type (e.g., "video/mp4") |
| `frameRate` | double? | Frame rate (from CLI fallback) |
| `bitrate` | int? | Bitrate (from CLI fallback) |
| `videoCodec` | String? | Video codec (from CLI fallback) |
| `audioCodec` | String? | Audio codec (from CLI fallback) |

**Thumbnail Generation Pattern (using media_kit):**
```dart
// The core pattern for taking screenshots with media_kit:
Player? player;
try {
  player = Player();
  // VideoController is REQUIRED for screenshot() to work
  final videoController = VideoController(player);

  // Wait for duration to confirm media is loaded
  final completer = Completer<Duration>();
  late StreamSubscription sub;
  sub = player.stream.duration.listen((duration) {
    if (duration > Duration.zero && !completer.isCompleted) {
      completer.complete(duration);
      sub.cancel();
    }
  });

  // Open media without playing
  await player.open(Media(videoPath), play: false);

  // Wait for load with timeout
  final duration = await completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => Duration.zero,
  );

  if (duration == Duration.zero) return null;

  // Seek to desired position
  await player.seek(Duration(seconds: atSeconds));
  await Future.delayed(const Duration(milliseconds: 300));

  // Play briefly to decode frames, then pause
  player.play();
  await Future.delayed(const Duration(milliseconds: 200));
  player.pause();
  await Future.delayed(const Duration(milliseconds: 200));

  // Take screenshot (returns PNG bytes)
  final bytes = await player.screenshot();

  await player.dispose();

  if (bytes == null || bytes.isEmpty) return null;

  // Save to file (media_kit outputs PNG format)
  await File(outputPath).writeAsBytes(bytes, flush: true);
  return outputPath;
} catch (e) {
  await player?.dispose();
  return null;
}
```

**Usage Example:**
```dart
import 'package:geogram/util/video_metadata_extractor.dart';

// Extract metadata
final metadata = await VideoMetadataExtractor.extract('/path/to/video.mp4');
if (metadata != null) {
  print('Duration: ${metadata.duration}s');
  print('Resolution: ${metadata.resolution}');
}

// Generate thumbnail
final thumbnailTime = VideoMetadataExtractor.getRecommendedThumbnailTime(metadata.duration);
final thumbnailPath = await VideoMetadataExtractor.generateThumbnail(
  '/path/to/video.mp4',
  '/path/to/thumbnail.png',  // Use .png extension - media_kit outputs PNG
  atSeconds: thumbnailTime,
);
```

**Notes:**
- media_kit `screenshot()` requires `VideoController` to be attached (for frame decoding)
- Output format is always PNG regardless of file extension
- Use `.png` file extension for thumbnails (see `VideoFolderUtils.buildThumbnailPath()`)
- Falls back to CLI ffprobe for detailed metadata (codec info, bitrate) on desktop

---

## Web Theme Components

### WebNavigation

**File:** `lib/util/web_navigation.dart`

Generates combined breadcrumb-style navigation headers for web pages. This is a shared pure Dart library (no Flutter dependencies) that creates consistent navigation across:
- Station server pages (`pure_station.dart`) - CLI mode
- Remote device pages (`collection_service.dart`) - Flutter apps

**Format:** `stationName > home | chat | blog`

**Purpose:**
Navigation should only show links to apps that actually exist. For example, a station may have "home" and "chat" but no "blog", while a device might have "home", "blog", "chat", and "events".

**Classes:**

```dart
class NavItem {
  final String id;
  final String label;
  final String path;
}

class WebNavigation {
  static String generateCombinedHeader({...});
  static String generateStationHeader({...});
  static String generateDeviceHeader({...});
}
```

**Methods:**

**generateStationHeader** - For station server pages (absolute paths like `/chat/`)
```dart
static String generateStationHeader({
  required String name,
  required String activeApp,
  bool hasBlog = false,
  bool hasChat = true,
  bool hasEvents = false,
  bool hasPlaces = false,
  bool hasFiles = false,
  bool hasAlerts = false,
  bool hasDownload = false,
})
```

**generateDeviceHeader** - For device/collection pages (relative paths like `../chat/`)
```dart
static String generateDeviceHeader({
  required String name,
  required String activeApp,
  bool hasBlog = false,
  bool hasChat = true,
  bool hasEvents = false,
  bool hasPlaces = false,
  bool hasFiles = false,
  bool hasAlerts = false,
  bool hasDownload = false,
})
```

**Usage in Station Server (CLI mode):**
```dart
import '../util/web_navigation.dart';

final headerNav = WebNavigation.generateStationHeader(
  name: stationName,
  activeApp: 'chat',
  hasChat: true,
  hasBlog: false,  // Station doesn't have blog
);

// Pass to template
final variables = {
  'HEADER_NAV': headerNav,
  // ... other variables
};
```

**Usage in Collection Service (Flutter apps):**
```dart
import '../util/web_navigation.dart';

// Check which apps exist
final hasBlog = await Directory('$collectionPath/blog').exists();
final hasEvents = await Directory('$collectionPath/events').exists();

final headerNav = WebNavigation.generateDeviceHeader(
  name: callsign,
  activeApp: 'chat',
  hasChat: true,
  hasBlog: hasBlog,
  hasEvents: hasEvents,
);

// Pass to template
final html = themeService.processTemplate(template, {
  'HEADER_NAV': headerNav,
  // ... other variables
});
```

**Template Integration:**
Templates should use `{{HEADER_NAV}}` placeholder:
```html
<header class="header">
  <div class="header__inner">
    <nav class="header-nav">
      {{HEADER_NAV}}
    </nav>
  </div>
</header>
```

**Output Example:**
```html
<a href="/" class="nav-name">p2p.radio</a>
<span class="nav-separator"> > </span>
<a href="/" class="nav-item">home</a>
<span class="nav-pipe"> | </span>
<span class="nav-item active">chat</span>
```

**Supported Apps:**
| ID | Label | Station Path | Device Path |
|----|-------|--------------|-------------|
| home | home | / | ../ |
| blog | blog | /blog/ | ../blog/ |
| chat | chat | /chat/ | ../chat/ |
| events | events | /events/ | ../events/ |
| places | places | /places/ | ../places/ |
| files | files | /files/ | ../files/ |
| alerts | alerts | /alerts/ | ../alerts/ |
| download | download | /download/ | ../download/ |

**CSS Classes (in themes/default/styles.css):**
```css
.header-nav { }           /* Container for navigation */
.header-nav .nav-name { } /* Station/device name link */
.header-nav .nav-separator { } /* The ">" separator */
.header-nav .nav-pipe { } /* The "|" between items */
.header-nav .nav-item { } /* Navigation links */
.header-nav .nav-item.active { } /* Current page (not a link) */
```

**Consumers:**
| Location | Method | Purpose |
|----------|--------|---------|
| `lib/cli/pure_station.dart` | `generateStationHeader()` | Station chat page |
| `lib/services/collection_service.dart` | `generateDeviceHeader()` | Device chat page |

---

### getChatPageScripts

**File:** `lib/util/chat_scripts.dart`

Provides reusable JavaScript for chat page interactivity. This is a shared pure Dart library (no Flutter dependencies) used by:
- Station server (`pure_station.dart`) - CLI mode, imports directly
- Remote device chat pages via `WebThemeService.getChatScripts()` - Flutter apps

**Function:**
```dart
String getChatPageScripts()
```

**Returns:** JavaScript code as a string for chat page interactivity

**Usage in Template Processing:**
```dart
final themeService = WebThemeService();
await themeService.init();

final html = themeService.processTemplate(template, {
  'GLOBAL_STYLES': await themeService.getGlobalStyles() ?? '',
  'APP_STYLES': await themeService.getAppStyles('chat') ?? '',
  'COLLECTION_NAME': stationName,
  'CHANNELS_LIST': channelsHtml.toString(),
  'CONTENT': messagesHtml.toString(),
  'DATA_JSON': dataJson,
  'SCRIPTS': themeService.getChatScripts(),  // <- Reusable scripts
});
```

**Required HTML Elements:**
The scripts expect these DOM elements to exist:
- `.channel-item` - Channel/room buttons with `data-room-id` attribute
- `#current-room` - Element to display current room name
- `#messages` - Container for messages

**Required GEOGRAM_DATA:**
The scripts read from `window.GEOGRAM_DATA`:
```javascript
window.GEOGRAM_DATA = {
  channels: [{ id: 'room1', name: 'Room 1' }],
  currentRoom: 'room1',
  apiBasePath: '/api/chat/rooms'  // or '../api/chat/rooms' for relative
};
```

**Features:**
- Channel switching with active state updates
- Message loading with date separators
- 5-second polling for new messages
- Auto-scroll to bottom on new messages
- HTML escaping for XSS prevention
- Error states for failed loads

**API Endpoints Used:**
- `GET {apiBasePath}/{roomId}/messages` - Load messages for a room
- `GET {apiBasePath}/{roomId}/messages?after={timestamp}` - Poll for new messages

**Message Format Expected:**
```json
{
  "messages": [
    {
      "timestamp": "2025-01-12 10:30_00",
      "author": "USER1",
      "content": "Hello world"
    }
  ]
}
```

**Consumers:**
| Location | Purpose |
|----------|---------|
| `lib/cli/pure_station.dart` `_handleChatPage()` | Station server chat page at `/chat` |
| `lib/services/collection_service.dart` `generateChatIndex()` | Remote device chat pages |

**Template File:**
`themes/default/chat/index.html` - HTML template with placeholders

**CSS File:**
`themes/default/chat/styles.css` - Chat-specific styles including:
- `.chat-layout` - Grid layout with sidebar
- `.channels-sidebar` - Channel list sidebar
- `.channel-item` - Individual channel buttons
- `.messages-area` - Message container
- `.message` - Individual message styling
- `.date-separator` - Date dividers between messages

**Example: Full Chat Page Generation:**
```dart
Future<void> _handleChatPage(HttpRequest request) async {
  final themeService = WebThemeService();
  await themeService.init();

  // Get styles
  final globalStyles = await themeService.getGlobalStyles() ?? '';
  final appStyles = await themeService.getAppStyles('chat') ?? '';

  // Build channel list HTML
  final channelsHtml = StringBuffer();
  for (final room in chatRooms) {
    channelsHtml.writeln('''
<div class="channel-item" data-room-id="${room.id}">
  <span class="channel-name">#${room.name}</span>
</div>''');
  }

  // Build data JSON
  final dataJson = jsonEncode({
    'channels': chatRooms.map((r) => {'id': r.id, 'name': r.name}).toList(),
    'currentRoom': chatRooms.first.id,
    'apiBasePath': '/api/chat/rooms',
  });

  // Get template and process
  final template = await themeService.getTemplate('chat');
  final html = themeService.processTemplate(template!, {
    'GLOBAL_STYLES': globalStyles,
    'APP_STYLES': appStyles,
    'COLLECTION_NAME': 'My Station',
    'CHANNELS_LIST': channelsHtml.toString(),
    'CONTENT': '', // Initial messages loaded by JS
    'DATA_JSON': dataJson,
    'SCRIPTS': themeService.getChatScripts(),
  });

  request.response.headers.contentType = ContentType.html;
  request.response.write(html);
}
```

---

## QR Widgets

### QrShareReceiveWidget

**File:** `lib/widgets/qr_share_receive_widget.dart`

Generic, reusable QR code share and receive widget with tabs. Designed to work with any data type through configuration.

**Generic Type Parameter:** `T` - The type of data being shared/received

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `dataToShare` | T? | No | Data to display as QR code (null shows empty state) |
| `config` | QrShareReceiveConfig\<T\> | Yes | Configuration for encoding/decoding |
| `i18n` | I18nService | Yes | Localization service |
| `initialTab` | int | No | Initial tab (0=Send, 1=Receive) |
| `onDataReceived` | void Function(T)? | No | Callback when data is received |

**QrShareReceiveConfig Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `shareTabTitle` | String | Yes | Tab title for send/share |
| `receiveTabTitle` | String | Yes | Tab title for receive/scan |
| `appBarTitle` | String | Yes | App bar title |
| `getFields` | List\<QrShareField\> Function(T) | Yes | Get selectable fields from data |
| `encode` | String Function(T, List\<QrShareField\>) | Yes | Encode data to JSON string |
| `decode` | QrScanResult\<T\> Function(String) | Yes | Decode JSON string to data |
| `onSave` | Future\<bool\> Function(T) | Yes | Save scanned data |
| `buildPreview` | Widget Function(BuildContext, T) | Yes | Build preview for scanned data |
| `validate` | Future\<String?\> Function(T)? | No | Validate before saving |
| `formatVersion` | String | No | Format version identifier (default: '1.0') |
| `maxRecommendedSize` | int | No | Max QR size in bytes (default: 1500) |
| `warningThreshold` | int | No | Warning threshold in bytes (default: 1000) |

**QrShareField Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `id` | String | Unique field identifier |
| `label` | String | Display label |
| `icon` | IconData | Icon to display |
| `isRequired` | bool | Cannot be deselected if true |
| `isSelected` | bool | Currently selected state |
| `subFields` | List\<QrShareSubField\>? | Individual items for multi-value fields |
| `estimatedSize` | int | Estimated size in bytes |

**QrShareSubField Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `id` | String | Unique identifier |
| `value` | String | Display value |
| `parentId` | String | Parent field ID |
| `isSelected` | bool | Selection state |

**Usage Example (Contacts):**
```dart
// Create configuration for contacts
final config = QrShareReceiveConfig<Contact>(
  shareTabTitle: 'Send',
  receiveTabTitle: 'Receive',
  appBarTitle: 'QR Code',
  getFields: (contact) => [
    QrShareField(
      id: 'displayName',
      label: 'Name',
      icon: Icons.person,
      isRequired: true,
    ),
    QrShareField(
      id: 'emails',
      label: 'Emails',
      icon: Icons.email,
      subFields: contact.emails.asMap().entries.map((e) =>
        QrShareSubField(
          id: 'email_${e.key}',
          value: e.value,
          parentId: 'emails',
        ),
      ).toList(),
    ),
  ],
  encode: (contact, fields) => jsonEncode({
    'type': 'contact',
    'name': contact.displayName,
    'emails': _getSelectedEmails(fields, contact.emails),
  }),
  decode: (json) {
    try {
      final data = jsonDecode(json);
      if (data['type'] != 'contact') {
        return QrScanResult(error: 'Invalid QR code');
      }
      return QrScanResult(data: Contact.fromJson(data));
    } catch (e) {
      return QrScanResult(error: 'Invalid format');
    }
  },
  onSave: (contact) async {
    await contactService.saveContact(contact);
    return true;
  },
  buildPreview: (context, contact) => ListTile(
    leading: const Icon(Icons.person),
    title: Text(contact.displayName),
    subtitle: Text('${contact.emails.length} emails'),
  ),
);

// Use the widget
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => QrShareReceiveWidget<Contact>(
      dataToShare: selectedContact,
      config: config,
      i18n: i18n,
      initialTab: 0, // Send tab
      onDataReceived: (contact) {
        print('Received: ${contact.displayName}');
      },
    ),
  ),
);
```

**Features:**
- **Send Tab:**
  - QR code generation with real-time updates
  - Field selection with checkboxes
  - Sub-field selection for multi-value fields (e.g., individual emails)
  - "Select All" and "Minimal" quick actions
  - Size indicator (OK/Warning/Too Large)
  - Copy JSON to clipboard
- **Receive Tab:**
  - Camera-based QR code scanning
  - Permission handling (request, denied, permanently denied)
  - Preview dialog before saving
  - Validation support
  - Error handling with user feedback
- **General:**
  - Fully generic - works with any data type
  - Localization support
  - Material 3 styling

**Platform Support:**
| Platform | Send (QR Generation) | Receive (Camera Scan) | Notes |
|----------|---------------------|----------------------|-------|
| Android | ✅ | ✅ | CameraX/ML Kit |
| iOS | ✅ | ✅ | AVFoundation/Apple Vision |
| macOS | ✅ | ✅ | AVFoundation/Apple Vision |
| Web | ✅ | ✅ | QR generation works everywhere; scanning uses browser camera API (ZXing) |
| Windows | ✅ | ❌ | QR generation only - no native camera support |
| Linux | ✅ | ❌ | QR generation only - no native camera support |

**Dependencies:**
- `qr_flutter: ^4.1.0` - QR code generation (cross-platform)
- `mobile_scanner: ^7.1.4` - Camera-based QR scanning (Android, iOS, macOS, Web)

**Web Camera Notes:**
- Uses browser's `getUserMedia` API for camera access
- User must grant camera permission in browser
- Works in Chrome, Firefox, Safari, Edge
- HTTPS required for camera access (except localhost)

**Required i18n Keys:**
- `qr_size_ok`, `qr_size_warning`, `qr_size_too_large`
- `copied_to_clipboard`, `qr_size`
- `minimal`, `select_all`, `select_fields_to_share`
- `field_required`, `no_data_to_share`
- `camera_permission_required`, `camera_permission_denied`
- `camera_not_supported`, `initializing_camera`, `scanning_qr`
- `open_settings`, `try_again`
- `data_scanned`, `saved_successfully`, `save_failed`
- `save`, `cancel`

---

## Speech Input Widgets

### TranscribeButtonWidget

**File:** `lib/widgets/transcribe_button_widget.dart`

Voice-to-text button for text fields. Shows an audio waveform icon that opens a recording/transcription dialog.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | I18nService | Yes | Localization service |
| `onTranscribed` | void Function(String) | Yes | Callback with transcribed text |
| `enabled` | bool | No | Enable/disable button (default: true) |
| `iconSize` | double | No | Icon size (default: 24) |

**Usage:**
```dart
TextFormField(
  controller: _descriptionController,
  decoration: InputDecoration(
    labelText: 'Description',
    suffixIcon: TranscribeButtonWidget(
      i18n: widget.i18n,
      onTranscribed: (text) {
        if (_descriptionController.text.isEmpty) {
          _descriptionController.text = text;
        } else {
          _descriptionController.text += ' $text';
        }
      },
    ),
  ),
)
```

**Features:**
- Auto-downloads Whisper model on first use (~465 MB)
- 30-second maximum recording duration
- Offline processing (no internet required after model download)
- Progress indicators for download and transcription
- Automatic platform detection (hides on unsupported platforms)
- Resume support for interrupted downloads

**Platform Support:**
| Platform | Supported | Notes |
|----------|-----------|-------|
| Android 5.0+ | Yes | |
| iOS 13+ | Yes | |
| macOS 11+ | Yes | |
| Windows | No | Icon hidden |
| Linux | No | Icon hidden |
| Web | No | Icon hidden |

**Dialog States:**
1. **Checking model** - Verifies if speech model is downloaded
2. **Downloading** - Auto-downloads Whisper Small model with progress bar
3. **Idle** - Ready to record, tap Start button
4. **Recording** - Animated waveform, timer, max 30 seconds
5. **Processing** - Transcribing audio (runs in background)
6. **Error** - Shows error with retry option

**Dependencies:**
- `whisper_flutter_new: ^1.3.0` - Offline speech recognition

**Model Storage:**
- Location: `{data-root}/bot/models/whisper/`
- Default model: Whisper Small (~465 MB)
- Downloaded from HuggingFace (ggerganov/whisper.cpp)

**Required i18n Keys:**
- `voice_to_text` - Tooltip
- `tap_to_start_recording` - Idle state hint
- `listening` - Recording title
- `recording` - Recording state label
- `processing_speech` - Processing title
- `transcribing_audio` - Processing state
- `downloading_speech_model` - Download title
- `first_time_download` - First-time hint
- `max_duration_seconds` - Duration hint with placeholder
- `microphone_permission_required` - Permission error
- `transcription_failed` - Error message
- `no_speech_detected` - Empty result message

### TtsPlayerWidget

**File:** `lib/widgets/tts_player_widget.dart`

Text-to-speech player using Supertonic for on-device voice synthesis.
Automatically uses the app's selected language (English or Portuguese).

**Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | String | Yes | - | Text to synthesize |
| `autoPlay` | bool | No | false | Play immediately on mount |
| `showControls` | bool | No | true | Show play/loading indicator |
| `voice` | TtsVoice | No | f3 | Voice style (m3-m5, f3-f5) |
| `onAudioGenerated` | Function? | No | null | Callback with audio samples |
| `child` | Widget? | No | null | Custom trigger widget |
| `iconSize` | double | No | 24.0 | Icon size for default controls |
| `iconColor` | Color? | No | null | Icon color |

**Usage:**
```dart
// Simple - shows play button
TtsPlayerWidget(
  text: 'Hello, welcome to Geogram!',
)

// Auto-play notification
TtsPlayerWidget(
  text: notification.message,
  autoPlay: true,
  showControls: false,
)

// Custom trigger with male voice
TtsPlayerWidget(
  text: article.content,
  voice: TtsVoice.m4,
  child: IconButton(
    icon: Icon(Icons.volume_up),
    onPressed: null, // Widget handles tap
  ),
)

// Generate audio samples
TtsPlayerWidget(
  text: script,
  onAudioGenerated: (samples) {
    // samples is Float32List at 24kHz
    // Save or process audio...
  },
)
```

**Features:**
- Auto-downloads Supertonic model from station server on first use (~66 MB)
- Falls back to HuggingFace if no station connected
- Offline processing (no internet required after model download)
- Language matches app's I18n setting (en_US = English, pt_PT = Portuguese)
- Progress indicator during model download
- Multiple voice options (male/female variants)

**Platform Support:**
| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Tested | Full support via flutter_onnxruntime |
| Android | Expected | flutter_onnxruntime supports ARM64 |
| iOS | Expected | flutter_onnxruntime supports iOS |
| Linux | Untested | May need ONNX Runtime build |

**Model Storage:**
- Location: `{data-root}/bot/models/supertonic/`
- Model: supertonic-2.onnx (~66 MB)
- Downloaded from station server or HuggingFace

**Console Integration:**
The TTS service is also available via console commands:
- `say <text>` - Speak text using TTS
- `CTRL+S` - Speak the last command output

---

## Patterns

### Service-Specific Connectivity Checking

**Problem:** Generic internet checks (pinging google.com/cloudflare.com) raise privacy concerns and don't tell you if your specific service is actually reachable.

**Solution:** Each service checks its own endpoint rather than relying on a generic "hasInternet" flag.

**Examples:**

**MapTileService** (`lib/services/map_tile_service.dart`):
```dart
/// Check if tile server is reachable (cached for 30s)
bool get canUseInternet {
  if (_canReachTileServer != null && _lastTileServerCheck != null) {
    if (DateTime.now().difference(_lastTileServerCheck!) < Duration(seconds: 30)) {
      return _canReachTileServer!;
    }
  }
  _checkTileServerReachability(); // async, updates cache
  return _canReachTileServer ?? false;
}

Future<bool> _checkTileServerReachability() async {
  try {
    final response = await httpClient.head(
      Uri.parse('https://tile.openstreetmap.org/0/0/0.png'),
    ).timeout(const Duration(seconds: 5));
    _canReachTileServer = response.statusCode >= 200 && response.statusCode < 400;
    _lastTileServerCheck = DateTime.now();
    return _canReachTileServer!;
  } catch (e) {
    _canReachTileServer = false;
    _lastTileServerCheck = DateTime.now();
    return false;
  }
}
```

**PlaceSharingService** (`lib/services/place_sharing_service.dart`):
```dart
/// Check if relay station is reachable
Future<bool> canReachRelay() async {
  final relayUrls = getRelayUrls();
  for (final relayUrl in relayUrls) {
    try {
      final httpUrl = _stationToHttpUrl(relayUrl);
      final response = await http.head(Uri.parse(httpUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        return true;
      }
    } catch (e) {
      continue;
    }
  }
  return false;
}
```

**Key Benefits:**
- No privacy-concerning pings to big tech companies
- More accurate - tells you if YOUR service works, not just "internet"
- Cached results avoid repeated checks
- Lazy evaluation - only checks when needed

**NetworkMonitorService** (`lib/services/network_monitor_service.dart`) now only monitors:
- LAN availability (has private IP address)
- No longer checks generic internet connectivity

---

### BLE Connection Retry with Exponential Backoff

**Problem:** BLE connections on Linux (BlueZ) are unreliable - connections may fail, service discovery may return empty, and notification subscriptions may not take effect immediately.

**Solution:** Wrap BLE operations in retry loops with exponential backoff, and use platform-specific timeouts.

**File:** `lib/services/ble_discovery_service.dart`

**Connection Retry Pattern:**
```dart
// Platform-specific timeout: Linux/BlueZ needs more time
final connectTimeout = Platform.isLinux
    ? const Duration(seconds: 15)
    : const Duration(seconds: 10);

// Retry connection up to 3 times with exponential backoff
bool connected = false;
for (int attempt = 1; attempt <= 3; attempt++) {
  try {
    LogService().log('Connection attempt $attempt/3');
    await bleDevice.connect(timeout: connectTimeout);
    connected = true;
    break;
  } catch (e) {
    LogService().log('Attempt $attempt failed: $e');
    if (attempt == 3) rethrow;
    // Exponential backoff: 500ms, 1000ms, 1500ms
    await Future.delayed(Duration(milliseconds: 500 * attempt));
  }
}
```

**Service Discovery Retry Pattern:**
```dart
List<BluetoothService> services = [];
for (int attempt = 1; attempt <= 3; attempt++) {
  services = await bleDevice.discoverServices();
  if (services.isNotEmpty) break;
  LogService().log('Discovery attempt $attempt returned empty');
  // Exponential backoff: 300ms, 600ms, 900ms
  await Future.delayed(Duration(milliseconds: 300 * attempt));
}
```

**Safe UUID Matching (handles BlueZ short/long formats):**
```dart
BluetoothService? findGeogramService(List<BluetoothService> services) {
  const shortUUID = 'fff0';
  const fullUUID = '0000fff0-0000-1000-8000-00805f9b34fb';

  for (final service in services) {
    final uuid = service.uuid.toString().toLowerCase();
    if (uuid == fullUUID ||
        uuid == shortUUID ||
        uuid.contains(shortUUID) ||
        uuid.startsWith('0000fff0')) {
      return service;
    }
  }
  return null; // Return null instead of throwing
}
```

**Key Benefits:**
- Handles BlueZ flakiness with retries
- Platform-specific timeouts (15s for Linux vs 10s for mobile)
- Exponential backoff prevents overwhelming the BLE stack
- Safe UUID matching handles both short (fff0) and full UUID formats
- Graceful degradation instead of throwing on first failure

---

## Constants

### App Constants

**File:** `lib/util/app_constants.dart`

Centralized constants for app/collection types. This file has no Flutter dependencies so it can be used in CLI mode.

**Constants:**

| Constant | Type | Description |
|----------|------|-------------|
| `knownAppTypesConst` | `List<String>` | All known app types for URL routing |
| `singleInstanceTypesConst` | `Set<String>` | App types that can only have one instance per profile |

**knownAppTypesConst:**
Used for URL routing and collection management. Contains all app types that can be routed to via URL.

```dart
const List<String> knownAppTypesConst = [
  'www', 'blog', 'chat', 'email', 'forum', 'events', 'alerts',
  'places', 'files', 'contacts', 'groups', 'news', 'postcards',
  'market', 'station', 'documents', 'photos', 'inventory',
  'wallet', 'log', 'backup', 'console', 'tracker',
];
```

**singleInstanceTypesConst:**
App types that can only have a single instance per profile. Used by `CreateCollectionPage` to prevent duplicate creation and by `main.dart` to show default apps.

```dart
const Set<String> singleInstanceTypesConst = {
  'forum', 'chat', 'blog', 'email', 'events', 'news', 'www',
  'postcards', 'places', 'market', 'alerts', 'groups', 'backup',
  'transfer', 'inventory', 'wallet', 'log', 'console', 'tracker',
  'contacts',
};
```

**Usage:**
```dart
import '../util/app_constants.dart';

// Check if a type is single-instance
if (singleInstanceTypesConst.contains(collectionType)) {
  // Only allow one instance
}

// Check if a type is known/routable
if (knownAppTypesConst.contains(urlType)) {
  // Route to the app
}
```

**Notes:**
- `files` is the only multi-instance type (users can create multiple file collections)
- When adding a new app type, add it to both constants if it should be single-instance
- This file is used by both Flutter UI and CLI code

---

### App Type Theme

**File:** `lib/util/app_type_theme.dart`

Centralized theming utilities for app/collection types. This file has Flutter dependencies (for Icons and LinearGradient). For pure Dart constants, use `app_constants.dart`.

**Functions:**

| Function | Returns | Description |
|----------|---------|-------------|
| `getAppTypeIcon(String type)` | `IconData` | Get the icon for an app/collection type |
| `getAppTypeGradient(String type, bool isDark)` | `LinearGradient` | Get the gradient colors for an app/collection type |

**Usage:**
```dart
import '../util/app_type_theme.dart';

// Get icon for a collection type
final icon = getAppTypeIcon('email');  // Returns Icons.email

// Get gradient for a collection type
final gradient = getAppTypeGradient('email', isDark);
```

**Supported Types:**
All types from `knownAppTypesConst` are supported with consistent icons and gradients:
- chat, email, blog, forum, events, alerts, places, contacts
- groups, inventory, wallet, log, backup, console, tracker
- files, news, www, market, postcards, station, transfer

**When adding a new app type:**
1. Add the type to `knownAppTypesConst` in `app_constants.dart`
2. Add to `singleInstanceTypesConst` if it should be single-instance
3. Add icon case to `getAppTypeIcon()` in `app_type_theme.dart`
4. Add gradient case to `getAppTypeGradient()` in `app_type_theme.dart`

---

### DirectMessageService Message Cache

**File:** `lib/services/direct_message_service.dart`

In-memory message caching pattern to avoid repeated file I/O and expensive signature verification. The cache:
- Returns cached messages if fresh (< 5 seconds old) and has enough messages for the request
- Automatically updates cache when new messages are sent/received (incremental updates)
- Invalidates cache when conversation is deleted

**Cache Structure:**
```dart
class _MessageCache {
  List<ChatMessage> messages;
  DateTime lastLoaded;
  String? newestTimestamp;
  bool isComplete; // true if all messages loaded

  bool get isFresh => DateTime.now().difference(lastLoaded).inSeconds < 5;
  bool hasEnoughMessages(int limit) => messages.length >= limit || isComplete;
}

// Cache map: callsign -> cached messages
final Map<String, _MessageCache> _messageCache = {};
```

**Usage Pattern:**
```dart
// Cache-aware message loading
Future<List<ChatMessage>> loadMessages(String callsign, {int limit = 100}) async {
  // Check cache first
  final cache = _messageCache[callsign];
  if (cache != null && cache.isFresh && cache.hasEnoughMessages(limit)) {
    return cache.messages.take(limit).toList();
  }

  // Cache miss - load from disk
  final messages = await _loadMessagesFromDisk(callsign);

  // Update cache
  _messageCache[callsign] = _MessageCache(
    messages: messages,
    lastLoaded: DateTime.now(),
    isComplete: true,
  );

  return messages;
}

// Incremental cache update (avoids full reload)
void _addMessageToCache(String callsign, ChatMessage message) {
  final cache = _messageCache[callsign];
  if (cache != null) {
    cache.messages.add(message);
    cache.messages.sort();
    cache.lastLoaded = DateTime.now();
  }
}
```

**Benefits:**
- Second open of same conversation returns instantly from cache
- Sending/receiving messages updates cache incrementally
- No "Not responding" dialog from Android on large conversations
- Cache auto-expires after 5 seconds for freshness

---

### ChatFileDownloadManager

**File:** `lib/services/chat_file_download_manager.dart`

Unified file download manager for all chat types. Handles connection-aware auto-download thresholds, progress tracking, and resume capability.

**Features:**
- Connection-aware thresholds: BLE (100KB), LAN/WiFi/Internet (5MB)
- Progress tracking with speed display
- Resume capability for partial downloads
- Reusable across DM, remote rooms, and station rooms

**Enums:**
```dart
enum ConnectionBandwidth { ble, lan, internet }
enum ChatDownloadStatus { idle, downloading, paused, completed, failed }
```

**ChatDownload Class:**
```dart
class ChatDownload {
  final String id;              // Unique identifier (sourceId_filename)
  final String sourceId;        // Callsign or room ID
  final String filename;
  final int expectedBytes;
  int bytesTransferred = 0;
  ChatDownloadStatus status;
  double? speedBytesPerSecond;
  String? localPath;            // Final path after completion

  double get progressPercent => (bytesTransferred / expectedBytes * 100);
  String get fileSizeFormatted => _formatBytes(expectedBytes);
  String? get speedFormatted => speedBytesPerSecond != null
      ? '${_formatBytes(speedBytesPerSecond!.toInt())}/s' : null;
}
```

**Usage:**
```dart
final _downloadManager = ChatFileDownloadManager();

// Check if file should auto-download
bool _shouldShowDownloadButton(ChatMessage message) {
  final fileSize = int.tryParse(message.getMeta('file_size') ?? '0') ?? 0;
  final bandwidth = _downloadManager.getDeviceBandwidth(callsign);
  return !_downloadManager.shouldAutoDownload(bandwidth, fileSize);
}

// Start download with progress
await _downloadManager.downloadFile(
  id: '${callsign}_$filename',
  sourceId: callsign,
  filename: filename,
  expectedBytes: fileSize,
  downloadFn: (resumeFrom, onProgress) async {
    return await _dmService.downloadFileWithProgress(
      callsign, filename, resumeFrom: resumeFrom, onProgress: onProgress,
    );
  },
);

// Get current download state
final download = _downloadManager.getDownload(downloadId);

// Subscribe to progress events
EventBus().on<ChatDownloadProgressEvent>((event) {
  if (event.downloadId.startsWith(sourceId)) {
    setState(() {});
    if (event.status == 'completed') _loadMessages();
  }
});
```

**UI Integration (MessageBubbleWidget):**
```dart
MessageBubbleWidget(
  // ... existing props ...
  showDownloadButton: _shouldShowDownloadButton(message),
  fileSize: int.tryParse(message.getMeta('file_size') ?? '0'),
  downloadState: _downloadManager.getDownload(downloadId),
  onDownloadPressed: () => _onDownloadPressed(message),
  onCancelDownload: () => _onCancelDownload(message),
)
```

**Thresholds:**
| Connection | Auto-download threshold |
|------------|------------------------|
| BLE        | < 100 KB               |
| LAN/WiFi   | < 5 MB                 |
| Internet   | < 5 MB                 |

---

### TransferService

**File:** `lib/transfer/services/transfer_service.dart`  
**Spec:** `docs/apps/transfer-format-specification.md`

Centralized hub for uploads, downloads, and streaming with automatic transport switching (BLE/LAN/Internet), resume, and per-transfer records/caching.

**Usage:**
```dart
final transfer = await TransferService().requestDownload(
  const TransferRequest(
    direction: TransferDirection.download,
    callsign: 'X1ABCD',
    remotePath: '/files/photo.jpg',
    localPath: '/downloads/photo.jpg',
    expectedHash: 'sha1:abc...',
    requestingApp: 'gallery',
  ),
);
// HTTP(S) downloads follow the spec's `remoteUrl` locator (add when available).
```

**Notes:**
- Checks the transfer cache first; repeated requests return immediately on a verified cache hit (per-record `cache_hit` is set).
- Records live under `{data_dir}/transfers/records/` and are auto-pruned after 30 days; see the spec for per-transport segment format and fallback order.
- Negotiates SHA-1 with peers when possible; verification gates final file placement.
- Emits `TransferProgressEvent` / `TransferCompletedEvent` on EventBus so UIs can refresh progress and consume cache hits.

**Download helpers**
- HTTP/S: set `remoteUrl` (e.g., `https://p2p.radio/bot/models/whisper/ggml-small.bin`) and `localPath`. `remotePath` is derived automatically.
- Callsign/mesh: set `callsign` + `remotePath` (e.g., `/X1ABCD/files/doc.pdf`) and `localPath`.
- Data strings: write the string to a temp file first (or a memory buffer if you know the bytes) and use the same download/upload calls—transfer tracks bytes regardless of payload type.

**Upload helpers**
```dart
final upload = await TransferService().requestUpload(
  TransferRequest(
    direction: TransferDirection.upload,
    callsign: 'X1ABCD',
    remotePath: '/inbox/photo.jpg', // destination on peer
    localPath: '/tmp/local/photo.jpg', // source on disk
    expectedHash: 'sha1:...',
    requestingApp: 'gallery',
  ),
);
```
- For HTTP uploads to a station URL, include `stationUrl` in the `TransferRequest`.
- For raw data strings, serialize to a temp file and point `localPath` to it.

**Querying queue/cache state**
- `findTransfer(callsign: 'X1ABCD', remotePath: '/files/photo.jpg', remoteUrl: null)` returns the first active/queued/failed/completed match (or `null`).
- `isAlreadyRequested(callsign, remotePath)` is a convenience check for duplicates.
- `getTransfer(transferId)` returns the in-memory instance from active/queue/failed/completed caches.
- Status comes from `transfer.status` (`queued`, `connecting`, `transferring`, `verifying`, `completed`, `failed`, `cancelled`, `paused`, `waiting`).
- Progress: `transfer.bytesTransferred`, `transfer.expectedBytes`, `transfer.progressPercent`, `transfer.speedBytesPerSecond`, `transfer.estimatedTimeRemaining`.
- Transport and origin: `transfer.transportUsed` (e.g., `internet_http`, `ble`) and `remoteUrl`/`sourceCallsign` help other dialogs show the source and path.

**Events for UI/dialogs**
- Subscribe to `TransferProgressEvent` / `TransferCompletedEvent` / `TransferFailedEvent` on `EventBus` to refresh UI badges or dialogs.
- Each event carries `transferId`, `status`, `bytesTransferred`, `totalBytes`, and ETA so dialogs can display live percentage and state (paused/in queue/failed/cancelled/completed).

**Cleaning transfer state**
- Use `TransferService().clearAll()` to purge queue, records, metrics, and cache (also exposed in the Transfers settings UI).

---

### MirrorSyncService

**File:** `lib/services/mirror_sync_service.dart`
**Docs:** `docs/API_synch.md`

Simple one-way folder synchronization between Geogram instances using NOSTR-signed authentication.

**Usage (as source - serving sync requests):**
```dart
final mirrorService = MirrorSyncService.instance;

// Add allowed peer
mirrorService.addAllowedPeer(peerNpub, peerCallsign);

// Verify incoming request
final result = await mirrorService.verifyRequest(nostrEvent, folder);
if (result.allowed) {
  // Token returned for subsequent manifest/file requests
  print('Token: ${result.token}');
}

// Generate folder manifest
final manifest = await mirrorService.generateManifest('/path/to/folder');
```

**Usage (as destination - performing sync):**
```dart
// Sync folder from peer
final result = await mirrorService.syncFolder(
  'http://192.168.1.100:3456',
  'collections/blog',
);

if (result.success) {
  print('Added: ${result.filesAdded}');
  print('Modified: ${result.filesModified}');
  print('Transferred: ${result.bytesTransferred} bytes');
}
```

**Key Features:**
- NOSTR event signature verification for authentication
- SHA1 file hashing for change detection
- One-way sync (source overwrites destination)
- Token-based session management (1 hour expiry)
- Range header support for resumable downloads
- Path traversal protection

---

## CLI/Console Abstractions

### ConsoleIO

**File:** `lib/cli/console_io.dart`

Platform-agnostic interface for console I/O. Allows the same command logic to work across different platforms.

**Implementations:**
- `CliConsoleIO` (`lib/cli/console_io_cli.dart`) - CLI mode using stdin/stdout
- `BufferConsoleIO` (`lib/cli/console_io_buffer.dart`) - Buffer-based for Flutter UI and async platforms

**Interface:**
```dart
abstract class ConsoleIO {
  void writeln([String text = '']);
  void write(String text);
  Future<String?> readLine();
  Future<int> readByte();
  void clear();
  set echoMode(bool value);
  set lineMode(bool value);
  bool get supportsRawMode;
  String? getOutput();
  void clearOutput();
}
```

**Usage - CLI Mode:**
```dart
final io = CliConsoleIO();
io.writeln('Hello, world!');
final input = await io.readLine();
```

**Usage - Flutter/Buffer Mode:**
```dart
final io = BufferConsoleIO();
io.writeln('Hello, world!');
final output = io.getOutput(); // Returns collected output
io.clearOutput();
```

---

### ConsoleHandler

**File:** `lib/cli/console_handler.dart`

Shared command logic for all console interfaces. Platform-agnostic - uses ConsoleIO for I/O.

**Service Interfaces:**
- `ProfileServiceInterface` - Profile management operations
- `StationServiceInterface` - Station server control

**Commands Supported:**
- Navigation: `ls`, `cd`, `pwd`
- Profile: `profile list`, `profile switch`, `profile create`, `profile info`
- Station: `station start`, `station stop`, `station status`, `station port`, `station cache`
- Games: `games list`, `games info`, `play <name>`
- General: `help`, `status`, `clear`, `quit`

**Virtual Filesystem:**
- `/profiles/` - Profile management
- `/config/` - Configuration
- `/logs/` - Log files
- `/station/` - Station control
- `/games/` - Text adventure games

**Usage:**
```dart
final io = BufferConsoleIO();
final handler = ConsoleHandler(
  io: io,
  profileService: MyProfileServiceAdapter(),
  stationService: MyStationServiceAdapter(),
  gameConfig: GameConfig(),
);

// Process command
await handler.processCommand('station status');
final output = io.getOutput();
```

**Adding New Platforms:**
To add support for a new platform (e.g., Telegram):

1. Create a new ConsoleIO implementation:
```dart
class TelegramConsoleIO implements ConsoleIO {
  final TelegramBot bot;
  final int chatId;
  final StringBuffer _output = StringBuffer();

  @override
  void writeln([String text = '']) => _output.writeln(text);

  @override
  String? getOutput() => _output.toString();

  // Implement other methods...
}
```

2. Create service adapters for your platform
3. Instantiate ConsoleHandler with your ConsoleIO

---

### ConsoleCompleter

**File:** `lib/cli/console_completer.dart`

Shared TAB completion logic for console interfaces. Used by both CLI and Flutter UI.

**Key Classes:**
- `Candidate` - Completion candidate with value, display text, and grouping
- `CompletionResult` - Result of a completion operation (completed text, candidates)
- `CompletionDataProvider` - Interface for dynamic data (profiles, devices, chat rooms)
- `ConsoleCompleter` - Main completion logic

**Features:**
- Command completion (global and context-aware)
- Sub-command completion with descriptions
- Virtual filesystem path completion
- Game file completion
- Profile callsign completion

**Usage:**
```dart
final completer = ConsoleCompleter(
  gameConfig: myGameConfig,
  dataProvider: myDataProvider,
  rootDirs: ['profiles', 'config', 'logs', 'station', 'games'],
);

final result = completer.complete('play tu', '/games');
if (result.exactMatch) {
  // Single match - use result.completedText
} else if (result.candidates.isNotEmpty) {
  // Multiple matches - display candidates
  final lines = completer.formatCandidatesForDisplay(result.candidates);
}
```

**Implementing CompletionDataProvider:**
```dart
class MyDataProvider implements CompletionDataProvider {
  @override
  List<String> getConnectedCallsigns() => ['ABC123', 'XYZ789'];

  @override
  Map<String, String> getChatRooms() => {'room1': 'General'};

  @override
  List<({String callsign, String? nickname, bool isStation})> getProfiles() {
    return [(callsign: 'ABC123', nickname: 'Alice', isStation: false)];
  }
}
```

---

### LogService Isolate Reading

**File:** `lib/services/log_service_native.dart`

Read large log files off the UI thread using Flutter's `compute()` function for isolate-based processing.

**Classes:**
- `LogReadResult` - Result containing lines, total count, and truncation status
- `_LogReadParams` - Parameters for the isolate function

**Method:**
```dart
Future<LogReadResult> readTodayLogAsync({int maxLines = 1000})
```

**Usage:**
```dart
// Read log lines in isolate (non-blocking)
final result = await LogService().readTodayLogAsync(maxLines: 1000);

// Access results
print('Lines: ${result.lines.length}');
print('Total: ${result.totalLines}');
print('Truncated: ${result.truncated}');

// Display with ListView.builder for performance
ListView.builder(
  itemCount: result.lines.length,
  itemBuilder: (context, index) => Text(result.lines[index]),
);
```

**Performance Notes:**
- Uses `compute()` to read files in a separate isolate
- Returns only the last N lines (default 1000) to limit memory
- Indicates if log was truncated for UI display
- Combines with `ListView.builder` for efficient rendering of large log files

---

## Summary Table

| Component | Location | Type | Main Use |
|-----------|----------|------|----------|
| UserPickerWidget | widgets/ | Picker | Select users from devices |
| CurrencyPickerWidget | widgets/wallet/ | Picker | Select currencies |
| TypeSelectorWidget | widgets/inventory/ | Picker | Select inventory types |
| PhotoViewerPage | pages/ | Viewer | Image & video gallery |
| DocumentViewerEditorPage | pages/ | Viewer | PDF, text, markdown |
| LocationPickerPage | pages/ | Picker | Map location selection |
| PlacePickerPage | pages/ | Picker | Place selection with distance/time sorting |
| ContactPickerPage | pages/ | Picker | Contact selection with A-Z/recent sorting |
| ContractDocumentPage | pages/ | Viewer | Markdown document |
| VoicePlayerWidget | widgets/ | Player | Voice messages |
| MusicPlayerWidget | widgets/ | Player | Music tracks |
| VoiceRecorderWidget | widgets/ | Recorder | Record voice |
| NewChannelDialog | widgets/ | Dialog | Create chat channels |
| NewThreadDialog | widgets/ | Dialog | Create forum threads |
| AddTrackableDialog | tracker/dialogs/ | Dialog | Add exercise or measurement entries |
| CallsignSelectorWidget | widgets/ | Selector | Profile switching |
| ProfileSwitcher | widgets/ | Selector | App bar profile |
| TrackerMapCard | tracker/widgets/ | Map | Satellite map miniature with markers |
| FolderTreeWidget | widgets/inventory/ | Tree | Folder navigation |
| MessageBubbleWidget | widgets/ | Message | Chat bubbles |
| MessageInputWidget | widgets/ | Input | Message composer |
| LocationService | services/ | Service | City lookup from coordinates |
| LocationProviderService | services/ | Service | Shared GPS positioning for all apps |
| PathRecordingService | tracker/services/ | Service | GPS path recording (uses LocationProviderService) |
| PlaceService.findPlacesWithinRadius | services/ | Service | Find places within GPS radius |
| WebNavigation | util/ | Web Theme | Dynamic navigation menu generator (shared) |
| getChatPageScripts | util/ | Web Theme | Reusable chat page JavaScript (shared) |
| QrShareReceiveWidget | widgets/ | QR | Share/receive data via QR |
| TranscribeButtonWidget | widgets/ | Input | Voice-to-text for text fields |
| App Constants | util/ | Constants | Centralized app type definitions |
| App Type Theme | util/ | Utility | Centralized icons and gradients for app types |
| ConsoleIO | cli/ | Interface | Platform-agnostic console I/O |
| ConsoleHandler | cli/ | Service | Shared command logic for CLI/UI/Telegram |
| ConsoleCompleter | cli/ | Service | Shared TAB completion logic |
| LogService.readTodayLogAsync | services/ | Service | Read logs off UI thread in isolate |
| StunServerService | services/ | Service | Self-hosted STUN server for WebRTC |
| GeoIpService | services/ | Service | Offline IP geolocation using MMDB database |

## GeoIpService

Privacy-preserving offline IP geolocation using DB-IP MMDB database.

**Location**: `lib/services/geoip_service.dart`

### Station API Endpoint

Stations expose `/api/geoip` endpoint that:
1. Extracts client IP from HTTP request
2. Looks up IP in local MMDB database
3. Returns JSON: `{ip, latitude, longitude, city, country, countryCode}`

### Client Usage Pattern

Clients call the connected station's `/api/geoip` endpoint:

```dart
// Get connected station URL and convert to HTTP
final stationUrl = WebSocketService().connectedUrl;
if (stationUrl == null) return null;

final httpUrl = stationUrl
    .replaceFirst('wss://', 'https://')
    .replaceFirst('ws://', 'http://');

final response = await http.get(Uri.parse('$httpUrl/api/geoip'));
if (response.statusCode == 200) {
  final data = json.decode(response.body);
  final lat = (data['latitude'] as num?)?.toDouble();
  final lon = (data['longitude'] as num?)?.toDouble();
  // Use lat, lon, data['city'], data['country']
}
```

### Files Using This Pattern
- `lib/util/geolocation_utils.dart`
- `lib/services/user_location_service.dart`
- `lib/services/location_service.dart`
- `lib/pages/maps_browser_page.dart`
- `lib/pages/location_page.dart`
- `lib/pages/stations_page.dart`
- `lib/cli/cli_location_service.dart`

### Station-Side Initialization
- Flutter station: `GeoIpService().initFromAssets()` (loads from Flutter assets)
- CLI station: `GeoIpService().initFromFile(path)` (loads from filesystem)

## ChatFileUploadManager

Singleton service for tracking file uploads (sender-side progress when serving files to receivers).

**Location**: `lib/services/chat_file_upload_manager.dart`

### Purpose

In the pull model for BLE file transfers:
1. Sender stores file locally and sends message with metadata
2. Receiver sees download button and requests file on demand
3. Sender serves the file when receiver requests it
4. **ChatFileUploadManager tracks the serving progress for sender's UI**

### Upload States

```dart
enum ChatUploadStatus {
  pending,     // File sent, waiting for receiver to request
  uploading,   // Transfer in progress (receiver downloading)
  completed,   // File fully transferred
  failed,      // Transfer failed (can retry)
}
```

### Key Features

1. **Progress Tracking**: Tracks bytes transferred, speed, percentage
2. **Auto-Resume**: Listens for `DeviceStatusChangedEvent` and auto-retries failed uploads when device reconnects
3. **Event Bus Integration**: Fires `ChatUploadProgressEvent` for UI updates
4. **Retry Support**: `requestRetry()` sends notification to receiver to re-request file

### Usage Pattern

**1. Initialize in page state:**
```dart
final ChatFileUploadManager _uploadManager = ChatFileUploadManager();

@override
void initState() {
  _uploadManager.initialize(); // Start listening for device reconnections
}
```

**2. Subscribe to upload events:**
```dart
EventBus().on<ChatUploadProgressEvent>((event) {
  if (event.receiverCallsign == targetCallsign) {
    setState(() {}); // Refresh UI
  }
});
```

**3. Get upload state for a message:**
```dart
ChatUpload? getUploadState(ChatMessage message) {
  if (!message.hasFile) return null;
  return _uploadManager.getUploadForFile(
    receiverCallsign,
    message.attachedFile!,
  );
}
```

**4. Handle retry button:**
```dart
Future<void> onRetryUpload(ChatMessage message) async {
  final success = await _uploadManager.requestRetry(
    receiverCallsign,
    message.attachedFile!,
  );
}
```

### Server-Side Integration

In `log_api_service.dart`, the GET file handler tracks progress:

```dart
// In _handleDMFileGetRequest:
uploadManager.startUpload(receiverCallsign, filename, totalBytes);

Stream<List<int>> fileStream() async* {
  for (var offset = 0; offset < totalBytes; offset += chunkSize) {
    final chunk = fileBytes.sublist(offset, end);
    bytesSent += chunk.length;
    uploadManager.updateProgress(receiverCallsign, filename, bytesSent);
    yield chunk;
  }
  uploadManager.completeUpload(receiverCallsign, filename);
}
```

### ChatUpload Data Model

```dart
class ChatUpload {
  final String id;              // "{receiverCallsign}_{filename}"
  final String messageId;
  final String receiverCallsign;
  final String filename;
  final int totalBytes;
  int bytesTransferred;
  ChatUploadStatus status;
  double? speedBytesPerSecond;
  String? error;
  int retryCount;

  double get progressPercent;
  String get fileSizeFormatted;
  String get bytesTransferredFormatted;
  String? get speedFormatted;
}
```

### Related Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ChatUploadProgressEvent | util/event_bus.dart | Event for UI updates |
| DeviceStatusChangedEvent | util/event_bus.dart | Triggers auto-resume |
| ChatFileDownloadManager | services/ | Similar pattern for downloads |
| MessageBubbleWidget | widgets/ | Shows upload progress UI |
| DMChatPage | pages/ | Integrates upload tracking |

---

## GeogramApi

**Location**: `lib/api/api.dart`

Unified, transport-agnostic API facade for device-to-device communication. All operations require a target callsign and are routed through `ConnectionManager` to the best available transport (LAN, BLE, Station relay).

### Basic Usage

```dart
final api = GeogramApi();

// Get device status
final status = await api.status.get('X3STATION');
if (status.success) {
  print('Device: ${status.data!.callsign}');
}

// List alerts with filtering
final alerts = await api.alerts.list('X3STATION',
  lat: 40.7128,
  lon: -74.0060,
  radius: 10, // km
);

// Send feedback
await api.feedback.pointAlert('X3STATION', alertId, signedEvent);
```

### Available Endpoint Modules

| Module | File | Purpose |
|--------|------|---------|
| `api.status` | endpoints/status_api.dart | Device status, GeoIP |
| `api.chat` | endpoints/chat_api.dart | Chat rooms, messages, files |
| `api.dm` | endpoints/dm_api.dart | Direct messages, sync |
| `api.alerts` | endpoints/alerts_api.dart | Alerts listing, details |
| `api.places` | endpoints/places_api.dart | Places listing, details |
| `api.events` | endpoints/events_api.dart | Events, media uploads |
| `api.blog` | endpoints/blog_api.dart | Blog posts, comments |
| `api.videos` | endpoints/videos_api.dart | Videos, categories |
| `api.feedback` | endpoints/feedback_api.dart | Points, likes, comments |
| `api.backup` | endpoints/backup_api.dart | Backup providers, snapshots |
| `api.updates` | endpoints/updates_api.dart | Version updates |

### Response Handling

All API calls return `ApiResponse<T>` with success/error handling:

```dart
final response = await api.alerts.list('X3STATION');

if (response.success) {
  final alerts = response.data!;
  print('Found ${alerts.length} alerts');
} else {
  print('Error: ${response.error?.message}');
}

// Or use helper methods
final alerts = response.dataOr([]);  // Default if null
final alert = response.dataOrThrow;  // Throws if failed
```

### List Responses with Pagination

```dart
final response = await api.blog.list('X3STATION', limit: 10, offset: 0);

print('Got ${response.count} posts');
print('Total: ${response.total}');
print('Has more: ${response.hasMore}');
```

### Path Utilities (from ChatApi)

The ChatApi includes static path builders (merged from `lib/util/chat_api.dart`):

```dart
// Build paths
final path = ChatApi.messagesPath('general');  // /api/chat/general/messages
final url = ChatApi.remoteMessagesUrl(baseUrl, 'X3ABC', 'general');

// Pattern matching
if (ChatApi.isMessagesPath(request.path)) {
  final roomId = ChatApi.extractRoomId(request.path);
}
```

### Transport-Agnostic Design

The API automatically routes through the best available transport:

1. **LAN** (priority 10) - Direct HTTP on local network
2. **BLE** (priority 20) - Bluetooth mesh for offline
3. **Station** (priority 30) - WebSocket relay via station

```dart
// Check device reachability
final reachable = await api.isReachable('X3DEVICE');
final transports = await api.getAvailableTransports('X3DEVICE');
// Returns: ['lan', 'station']
```

### Direct Messaging via ConnectionManager

For NOSTR-signed messages that need proper transport routing:

```dart
// Send DM (queued if offline)
await api.sendDirectMessage('X1TARGET', signedEvent,
  queueIfOffline: true,
  ttl: Duration(hours: 24),
);

// Send chat message
await api.sendChatMessage('X3STATION', 'general', signedEvent);
```

### Error Handling

```dart
final response = await api.status.get('X3OFFLINE');

if (!response.success) {
  final error = response.error!;

  if (error.isNetworkError) {
    print('Device unreachable');
  } else if (error.isNotFound) {
    print('Resource not found');
  } else if (error.isUnauthorized) {
    print('Auth required');
  }
}
```

### Related Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ConnectionManager | connection/connection_manager.dart | Transport routing |
| Transport | connection/transport.dart | Transport interface |
| TransportResult | connection/transport_message.dart | Result type |
| ApiResponse | api/api_response.dart | Generic response wrapper |
| ApiError | api/api_error.dart | Error types |

---

## API Common Utilities (`lib/api/common/`)

Shared utilities for API handlers to avoid code duplication across alert, place, blog, and feedback handlers.

### GeometryUtils

**File:** `lib/api/common/geometry_utils.dart`

Calculate distances between GPS coordinates using the Haversine formula.

```dart
import 'package:geogram/api/common/geometry_utils.dart';

// Calculate distance in kilometers
final distance = GeometryUtils.calculateDistanceKm(
  40.7128, -74.0060,  // lat1, lon1 (New York)
  34.0522, -118.2437, // lat2, lon2 (Los Angeles)
);
print('Distance: ${distance.toStringAsFixed(2)} km'); // 3935.75 km
```

### FileTreeBuilder

**File:** `lib/api/common/file_tree_builder.dart`

Build recursive file tree structures for sync operations. Used by alert and place APIs to return file metadata.

```dart
import 'package:geogram/api/common/file_tree_builder.dart';

// Build file tree for a directory
final tree = await FileTreeBuilder.build('/path/to/alert/folder');
// Returns:
// {
//   'report.txt': {'size': 1024, 'mtime': 1706000000},
//   'images/': {
//     'photo1.jpg': {'size': 204800, 'mtime': 1706000100},
//   }
// }
```

### StationInfo

**File:** `lib/api/common/station_info.dart`

Station metadata for API responses. Identifies which station served the request.

```dart
import 'package:geogram/api/common/station_info.dart';

final station = StationInfo(
  name: 'My Station',
  callsign: 'X3ABC',
  npub: 'npub1...',
);

// Include in API response
final response = {
  'success': true,
  'station': station.toJson(),
  'data': [...],
};
```

**Also exported from:** `lib/api/handlers/alert_handler.dart` for backward compatibility.

### Usage in Handlers

```dart
// In AlertHandler
final distance = GeometryUtils.calculateDistanceKm(lat, lon, alertLat, alertLon);
final fileTree = await FileTreeBuilder.build(alertDir.path);

// In PlaceHandler
final distance = GeometryUtils.calculateDistanceKm(lat, lon, placeLat, placeLon);
final fileTree = await FileTreeBuilder.build(placePath);
```

---

## Server Chat Models (`lib/server/models/`)

Server-side models for chat room management with WebSocket support. These are distinct from client-side models used for file parsing.

### ServerChatRoom

**File:** `lib/server/models/server_chat_room.dart`

Server-side chat room model for managing chat rooms with WebSocket clients.

```dart
import 'package:geogram/server/models/server_chat_room.dart';

// Create a new room
final room = ServerChatRoom(
  id: 'general',
  name: 'General Chat',
  description: 'Public discussion room',
  creatorCallsign: 'X3ABC',
  isPublic: true,
);

// Add messages
room.messages.add(message);
room.lastActivity = DateTime.now().toUtc();

// Serialize
final json = room.toJson();  // Without messages
final fullJson = room.toJsonWithMessages();  // With messages
```

### ServerChatMessage

**File:** `lib/server/models/server_chat_message.dart`

Server-side chat message model with NOSTR signature verification support.

```dart
import 'package:geogram/server/models/server_chat_message.dart';

// Create a signed message
final message = ServerChatMessage(
  id: eventId,  // NOSTR event ID
  roomId: 'general',
  senderCallsign: 'X3ABC',
  senderNpub: 'npub1...',
  signature: signatureHex,
  content: 'Hello world!',
  timestamp: DateTime.now().toUtc(),
  verified: true,
);

// Parse from API response
final msg = ServerChatMessage.fromJson(json, 'general');

// Serialize
final json = message.toJson();
```

### Model Comparison

| Model | Location | Purpose |
|-------|----------|---------|
| `ServerChatRoom` | lib/server/models/ | Server-side room management |
| `ServerChatMessage` | lib/server/models/ | Server-side message storage |
| `ChatMessage` | lib/models/chat_message.dart | Client-side file parsing |
| `ChatRoom`/`ChatMessage` | lib/api/endpoints/chat_api.dart | API response DTOs |

### Usage in pure_station.dart

```dart
// Type aliases for backward compatibility
typedef ChatRoom = ServerChatRoom;
typedef ChatMessage = ServerChatMessage;

// Room management
final Map<String, ChatRoom> _chatRooms = {};
_chatRooms['general'] = ChatRoom(
  id: 'general',
  name: 'General',
  creatorCallsign: callsign,
);
```

---

## Station Server Base (`lib/server/`)

A unified server architecture that both CLI (PureStationServer) and App (StationServerService) implementations extend. Provides feature parity across platforms through shared base class and mixins.

### Consolidation Progress

The codebase has two parallel station server implementations being consolidated:

| Component | `PureStationServer` | `lib/server/` | Status |
|-----------|---------------------|---------------|--------|
| Alert/Place/Feedback APIs | Uses AlertHandler, PlaceHandler, FeedbackHandler | Uses AlertHandler, PlaceHandler, FeedbackHandler | **Shared** |
| Chat models | Uses ServerChatRoom, ServerChatMessage | Uses ServerChatRoom, ServerChatMessage | **Shared** |
| Rate limit class | Uses IpRateLimit from mixin | Defines IpRateLimit in mixin | **Shared** |
| Geometry utils | Uses GeometryUtils | Uses GeometryUtils | **Shared** |
| File tree builder | Uses FileTreeBuilder | Uses FileTreeBuilder | **Shared** |
| Station info | Uses StationInfo | Uses StationInfo | **Shared** |
| Rate limit logic | Private `_checkRateLimit()` | RateLimitMixin | Duplicate |
| Health watchdog | Private `_runHealthWatchdog()` | HealthWatchdogMixin | Duplicate |
| SSL/HTTPS | Private SSL methods | SslMixin | Duplicate |
| Chat room management | 12+ methods | Not in base | PureStationServer only |

**Migration path:** PureStationServer (12,000+ lines) will incrementally adopt mixins from `lib/server/mixins/` to reduce duplication. Current focus is on sharing data classes and utilities.

**Full plan:** See [docs/consolidation-plan.md](consolidation-plan.md) for detailed phases 4-8 covering:
- Phase 4: Adopt RateLimitMixin and HealthWatchdogMixin (~250 lines)
- Phase 5: Extract HTTP handlers to shared modules (~450 lines)
- Phase 6: Extract update/model mirroring services (~600 lines)
- Phase 7: Consolidate SSL/certificate management (~500 lines)
- Phase 8: WebSocket message routing (~200 lines)

### Directory Structure

```
lib/server/
├── station_settings.dart      # Unified settings class
├── station_client.dart        # Connected client model
├── station_tile_cache.dart    # LRU tile cache
├── station_stats.dart         # Server statistics
├── platform_adapter.dart      # Platform abstraction interface
├── station_server_base.dart   # Abstract base class
├── handlers/                  # HTTP handler modules
│   ├── status_handler.dart    # /api/status endpoints
│   ├── tile_handler.dart      # /tiles/* endpoints
│   ├── update_handler.dart    # /updates/* endpoints
│   └── blossom_handler.dart   # /blossom/* endpoints
├── models/                    # Server-side data models
│   ├── server_chat_room.dart  # Chat room model
│   └── server_chat_message.dart # Chat message model
└── mixins/                    # Feature mixins
    ├── rate_limit_mixin.dart  # IP rate limiting + banning
    ├── health_watchdog_mixin.dart  # Auto-recovery
    ├── ssl_mixin.dart         # HTTPS + Let's Encrypt
    ├── smtp_mixin.dart        # SMTP server
    └── stun_mixin.dart        # WebRTC STUN server
```

### Usage - Extending Base Class

```dart
class MyStationServer extends StationServerBase
    with SslMixin, RateLimitMixin, HealthWatchdogMixin {

  @override
  void log(String level, String message) {
    print('[$level] $message');
  }

  @override
  Future<void> saveSettingsToStorage() async {
    // Save _settings to disk/prefs
  }

  @override
  Future<bool> handlePlatformRoute(HttpRequest request, String path, String method) async {
    // Handle platform-specific routes
    if (path == '/my/special/route') {
      // Handle it
      return true; // Handled
    }
    return false; // Not handled, continue to base routing
  }
}
```

### Unified Settings

```dart
final settings = StationSettings(
  httpPort: 8080,
  httpsPort: 8443,
  enableSsl: true,
  sslDomain: 'mystation.example.com',
  tileServerEnabled: true,
  stunServerEnabled: true,
  maxConnectedDevices: 100,
);

// Save/load via JSON
final json = settings.toJson();
final restored = StationSettings.fromJson(json);
```

### Rate Limiting Mixin

```dart
class MyServer extends StationServerBase with RateLimitMixin {
  void handleRequest(HttpRequest request) {
    final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    if (isIpBanned(ip)) {
      // Return 429
      return;
    }

    if (!checkRateLimit(ip)) {
      banIp(ip); // Exponential backoff: 5min -> 15min -> 1hr -> 24hr
      return;
    }

    // Process request...
  }
}
```

### Health Watchdog Mixin

```dart
class MyServer extends StationServerBase with HealthWatchdogMixin {
  @override
  int get httpPort => settings.httpPort;

  @override
  bool get isServerRunning => _running;

  @override
  int get connectedClientsCount => _clients.length;

  @override
  Future<void> autoRecover() async {
    // Restart HTTP server
    await stopServer();
    await startServer();
  }

  @override
  void logCrash(String reason) {
    log('CRASH', reason);
  }
}

// Watchdog monitors:
// - Self health check (HTTP request to own /api/status)
// - Attack detection (high request/error rates, connection exhaustion)
```

### Tile Handler

```dart
final tileHandler = TileHandler(
  getSettings: () => settings,
  tileCache: tileCache,
  stats: stats,
  tilesDirectory: '/data/tiles',
  log: (level, msg) => print('[$level] $msg'),
);

// Handles:
// - GET /tiles/{z}/{x}/{y}.png
// - Memory cache + disk cache
// - OSM fallback fetch
// - Tile validation (PNG/JPEG headers)
```

### Related Components

| Component | Location | Purpose |
|-----------|----------|---------|
| StationSettings | server/station_settings.dart | Unified configuration |
| StationClient | server/station_client.dart | WebSocket client model |
| StationTileCache | server/station_tile_cache.dart | LRU tile cache |
| RateLimitMixin | server/mixins/rate_limit_mixin.dart | IP rate limiting |
| SslMixin | server/mixins/ssl_mixin.dart | HTTPS support |
| HealthWatchdogMixin | server/mixins/health_watchdog_mixin.dart | Auto-recovery |

---

## Storage Path Helpers

### getChatDir

**Files:**
- `lib/services/storage_config.dart` (App)
- `lib/cli/pure_storage_config.dart` (CLI)

Get the canonical chat directory path for a specific callsign. Ensures consistent paths across App and CLI servers.

**Signature:**
```dart
String getChatDir(String callsign)
```

**Returns:** `{baseDir}/devices/{sanitizedCallsign}/chat`

**Usage:**
```dart
// App mode
final chatPath = StorageConfig().getChatDir('KB1ABC');
// Result: /home/user/.local/share/geogram/devices/KB1ABC/chat

// CLI mode
final chatPath = PureStorageConfig().getChatDir('KB1ABC');
// Result: /opt/geogram/devices/KB1ABC/chat
```

**Canonical Directory Structure:**
```
{baseDir}/
├── config.json
├── station_config.json
├── devices/                    # Per-callsign data
│   └── {CALLSIGN}/
│       ├── alerts/
│       ├── blog/
│       ├── chat/              # Chat rooms stored here
│       ├── events/
│       ├── places/
│       └── videos/
├── tiles/
├── ssl/
├── logs/
├── updates/
└── nostr/
```

**Related Helpers:**
| Helper | Returns |
|--------|---------|
| `getCallsignDir(callsign)` | `{baseDir}/devices/{callsign}` |
| `devicesDir` | `{baseDir}/devices` |
| `tilesDir` | `{baseDir}/tiles` |
| `sslDir` | `{baseDir}/ssl` |
| `logsDir` | `{baseDir}/logs` |

---

## Reader Services (`lib/reader/services/`)

The Reader app provides an e-reader with source-based architecture supporting RSS feeds, Manga, and Books.

### RssService

**File:** `lib/reader/services/rss_service.dart`

Parse RSS 2.0 and Atom feeds, convert HTML content to Markdown.

**Usage:**
```dart
final rssService = RssService();

// Parse feed from URL
final items = await rssService.parseFeed('https://example.com/feed.xml');
for (final item in items) {
  print('${item.title} - ${item.publishedAt}');
}

// Convert HTML to Markdown
final markdown = rssService.htmlToMarkdown('<p>Hello <b>world</b></p>');
// Result: "Hello **world**"

// Download and convert article content
final content = await rssService.fetchArticleContent('https://example.com/article');
```

**RssFeedItem Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier |
| `title` | String | Article title |
| `link` | String | Article URL |
| `description` | String? | Summary/excerpt |
| `content` | String? | Full content (if available) |
| `author` | String? | Author name |
| `publishedAt` | DateTime? | Publish date |
| `categories` | List<String> | Categories/tags |
| `imageUrl` | String? | Featured image |

---

### MangaService

**File:** `lib/reader/services/manga_service.dart`

Handle CBZ (Comic Book ZIP) files: extraction, page caching, chapter creation.

**Usage:**
```dart
final mangaService = MangaService();

// Extract pages from CBZ file
final pages = await mangaService.extractPages('/path/to/chapter.cbz');
for (final page in pages) {
  // page.data is Uint8List of image bytes
  // page.filename is the original filename
  Image.memory(page.data);
}

// Get chapter files from manga folder
final chapters = await mangaService.getChapterFiles('/path/to/manga/series');
// Returns sorted list: ['chapter-001.cbz', 'chapter-002.cbz', ...]

// Create CBZ from downloaded images
await mangaService.createCbz(
  outputPath: '/path/to/chapter-001.cbz',
  images: imageBytesList,  // List<Uint8List>
);

// Clear page cache to free memory
mangaService.clearCache();
```

**MangaPage Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `filename` | String | Original image filename |
| `data` | Uint8List | Image bytes |
| `width` | int? | Image width (if detected) |
| `height` | int? | Image height (if detected) |

**CBZ Format Notes:**
- CBZ is a ZIP archive containing image files
- Images sorted alphanumerically by filename
- Supports: JPG, PNG, GIF, WEBP
- Naming convention: `chapter-001.cbz`, `chapter-002.cbz`

---

### SourceService

**File:** `lib/reader/services/source_service.dart`

Discover and parse source.js configuration files for RSS and Manga sources.

**Usage:**
```dart
final sourceService = SourceService();

// Discover all sources in a category
final rssSources = await sourceService.discoverSources('/path/to/reader/rss');
final mangaSources = await sourceService.discoverSources('/path/to/reader/manga');

for (final source in rssSources) {
  print('${source.name} (${source.type}) - ${source.url}');
}

// Load source configuration
final config = await sourceService.loadSourceConfig('/path/to/reader/rss/hackernews');
print(config.name);       // "Hacker News"
print(config.feedUrl);    // "https://news.ycombinator.com/rss"
```

**Source Configuration (source.js):**
```javascript
// reader/rss/hackernews/source.js
module.exports = {
  name: "Hacker News",
  type: "rss",
  url: "https://news.ycombinator.com/rss",
  settings: {
    maxPosts: 100,
    fetchIntervalHours: 1,
    downloadImages: true
  }
};
```

**Source Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Source folder name |
| `name` | String | Display name |
| `type` | SourceType | rss, manga, or local |
| `url` | String? | Feed/API URL |
| `isLocal` | bool | True for local-only sources |

---

### ReaderService

**File:** `lib/reader/services/reader_service.dart`

Main orchestrating service for the Reader app. Manages sources, content, and reading progress.

**Usage:**
```dart
final readerService = ReaderService();

// Initialize with collection path
await readerService.initialize('/path/to/reader');

// RSS Operations
final rssSources = await readerService.getRssSources();
final posts = await readerService.getPosts('hackernews');
await readerService.markPostRead('hackernews', 'post-slug');
await readerService.togglePostStarred('hackernews', 'post-slug');

// Manga Operations
final mangaSources = await readerService.getMangaSources();
final series = await readerService.getMangaSeries('mangadex');
final chapters = await readerService.getMangaChapters('mangadex', 'one-punch-man');
readerService.markChapterRead('mangadex', 'one-punch-man', 'chapter-001.cbz');

// Book Operations
final folders = await readerService.getBookFolders(['fiction']);
final books = await readerService.getBooks(['fiction', 'sci-fi']);

// Progress Tracking
final bookProgress = readerService.getBookProgress('/path/to/book.epub');
readerService.updateBookProgress('/path/to/book.epub', page: 142, percent: 45.2);

final mangaProgress = readerService.getMangaProgress('mangadex', 'one-punch-man');
readerService.updateMangaProgress('mangadex', 'one-punch-man', 'chapter-003.cbz', page: 12);

// Settings
final settings = readerService.settings;
settings.general.fontSize = 18;
await readerService.saveSettings();
```

**ReaderSettings Fields:**
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `general.fontSize` | int | 16 | Reading font size |
| `general.lineHeight` | double | 1.5 | Line spacing |
| `general.theme` | String | 'system' | Theme preference |
| `rss.autoRefresh` | bool | true | Auto-refresh feeds |
| `rss.refreshIntervalMinutes` | int | 30 | Refresh interval |
| `manga.readingDirection` | String | 'ltr' | Reading direction |
| `manga.webtoonMode` | bool | false | Vertical scroll mode |
| `books.rememberPosition` | bool | true | Save reading position |

---

### ReaderPathUtils

**File:** `lib/reader/utils/reader_path_utils.dart`

Path building utilities for Reader content.

**Usage:**
```dart
// Slugify title for folder names
final slug = ReaderPathUtils.slugify('My Manga Title!');
// Result: 'my-manga-title'

// Build paths
final postPath = ReaderPathUtils.buildPostPath(collectionPath, sourceId, slug);
// Result: '{collection}/rss/{sourceId}/posts/{date}_{slug}'

final mangaPath = ReaderPathUtils.buildMangaPath(collectionPath, sourceId, slug);
// Result: '{collection}/manga/{sourceId}/series/{slug}'

final chapterPath = ReaderPathUtils.buildChapterPath(collectionPath, sourceId, mangaSlug, 'chapter-001.cbz');
// Result: '{collection}/manga/{sourceId}/series/{mangaSlug}/chapter-001.cbz'

// Format date for folder names
final dateStr = ReaderPathUtils.formatDateForFolder(DateTime.now());
// Result: '2026-01-24'
```

---

### Related Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ReaderHomePage | reader/pages/reader_home_page.dart | Main category selection |
| RssSourcesPage | reader/pages/rss_sources_page.dart | RSS sources list |
| RssPostsPage | reader/pages/rss_posts_page.dart | Posts from a source |
| ArticleReaderPage | reader/pages/article_reader_page.dart | Markdown article reader |
| MangaSourcesPage | reader/pages/manga_sources_page.dart | Manga sources list |
| MangaSeriesPage | reader/pages/manga_series_page.dart | Manga series grid/list |
| MangaReaderPage | reader/pages/manga_reader_page.dart | Full-screen chapter reader |
| BookBrowserPage | reader/pages/book_browser_page.dart | Local book file browser |

---

## Flasher Components

The Flasher module provides components for flashing firmware to ESP32 and other USB-connected devices.

### FlasherService

**File:** `lib/flasher/services/flasher_service.dart`

Main service for orchestrating flash operations.

**Usage:**
```dart
import 'package:geogram/flasher/flasher.dart';

// Create service
final service = FlasherService.withPath('flasher');

// List serial ports
final ports = await service.listPorts();

// Auto-detect connected device
final device = await service.autoDetectDevice();

// Flash device
await service.flashDevice(
  device: device!,
  portPath: ports.first.path,
  onProgress: (progress) {
    print('${progress.percentage}% - ${progress.message}');
  },
);
```

---

### FlasherStorageService

**File:** `lib/flasher/services/flasher_storage_service.dart`

Service for loading device definitions from the flasher/ directory. Supports both v1.0 and v2.0 directory structures:
- **v1.0:** `flasher/{family}/{device}.json`
- **v2.0:** `flasher/{project}/{architecture}/{model}/device.json`

**Usage:**
```dart
final storage = FlasherStorageService('flasher');

// Load all devices (both v1.0 and v2.0)
final devices = await storage.loadAllDevices();

// Load devices in hierarchical structure (v2.0)
final hierarchy = await storage.loadDevicesByHierarchy();
// Returns: Map<String, Map<String, List<DeviceDefinition>>>
// Example: hierarchy['geogram']['esp32'] = [device1, device2]

// Load devices grouped by family (v1.0 compatibility)
final byFamily = await storage.loadDevicesByFamily();

// v2.0 specific methods
final projects = await storage.listProjects();
final architectures = await storage.listArchitectures('geogram');
final models = await storage.listModels('geogram', 'esp32');
final versions = await storage.loadVersions('geogram', 'esp32', 'esp32-c3-mini');
final device = await storage.loadDeviceV2('geogram', 'esp32', 'esp32-c3-mini');

// Find device by USB VID/PID
final device = await storage.findDeviceByUsb(0x303A, 0x1001);

// Load specific device (v1.0)
final esp32 = await storage.loadDevice('esp32', 'esp32-c3-mini');
```

---

### FirmwareTreeWidget

**File:** `lib/flasher/widgets/firmware_tree_widget.dart`

Hierarchical tree view for browsing the firmware library. Shows: Project -> Architecture -> Model -> Version.

**Usage:**
```dart
FirmwareTreeWidget(
  hierarchy: _hierarchy, // Map<String, Map<String, List<DeviceDefinition>>>
  selectedDevice: _selectedDevice,
  selectedVersion: _selectedVersion,
  onSelected: (device, version) {
    setState(() {
      _selectedDevice = device;
      _selectedVersion = version;
    });
  },
  isLoading: _isLoading,
)
```

**Features:**
- Expand/collapse folders
- Tap version to select for flashing
- Long-press version to show details (release notes, size, date)
- Auto-expand to current selection
- Visual indicators for latest version

---

### SelectedFirmwareCard

**File:** `lib/flasher/widgets/selected_firmware_card.dart`

Card widget showing the selected firmware with device info, version path, and Change button.

**Usage:**
```dart
SelectedFirmwareCard(
  device: _selectedDevice,
  version: _selectedVersion,
  onChangeTap: () {
    _tabController.animateTo(0); // Switch to Library tab
  },
)

// Compact chip variant
SelectedFirmwareChip(
  device: device,
  version: version,
  onTap: () { ... },
)
```

**Displays:**
- Device photo (or placeholder icon)
- Device title
- Path: project / architecture / version
- Flash info badges (size, protocol)
- Change button to switch selection

---

### ProtocolRegistry

**File:** `lib/flasher/protocols/protocol_registry.dart`

Factory for creating flash protocol instances.

**Usage:**
```dart
import 'package:geogram/flasher/flasher.dart';

// Create protocol by ID
final protocol = ProtocolRegistry.create('esptool');

// List available protocols
final protocols = ProtocolRegistry.availableProtocols;
// ['esptool', 'quansheng']

// Check if protocol is available
if (ProtocolRegistry.isAvailable('esptool')) {
  // Use protocol
}
```

---

### DeviceCard Widget

**File:** `lib/flasher/widgets/device_card.dart`

Card widget for displaying a flashable device with photo and details.

**Usage:**
```dart
DeviceCard(
  device: deviceDefinition,
  isSelected: _selectedDevice?.id == deviceDefinition.id,
  onTap: () {
    setState(() {
      _selectedDevice = deviceDefinition;
    });
  },
)
```

---

### FlashProgressWidget

**File:** `lib/flasher/widgets/flash_progress_widget.dart`

Widget for displaying flash operation progress with status, progress bar, and details.

**Usage:**
```dart
FlashProgressWidget(
  progress: _flashProgress,
  showDetails: true,
)

// Compact version for app bars
CompactFlashProgress(
  progress: _flashProgress,
)
```

---

### FlashProgress Model

**File:** `lib/flasher/models/flash_progress.dart`

Progress state model with factory constructors for each phase.

**Usage:**
```dart
// Create progress states
final connecting = FlashProgress.connecting();
final writing = FlashProgress.writing(
  progress: 0.5,
  bytesWritten: 51200,
  totalBytes: 102400,
  currentChunk: 50,
  totalChunks: 100,
);
final error = FlashProgress.error('Device disconnected');
final completed = FlashProgress.completed(Duration(seconds: 30));

// Check state
if (progress.isInProgress) { ... }
if (progress.isCompleted) { ... }
if (progress.isError) { ... }
```

---

### DeviceDefinition Model

**File:** `lib/flasher/models/device_definition.dart`

Model for device definitions loaded from JSON files. Supports both v1.0 and v2.0 formats.

**Key Classes:**
- `DeviceDefinition` - Main device model
- `FirmwareVersion` - Version with metadata (checksum, size, release notes)
- `FlashConfig` - Flash configuration (protocol, baud rate, etc.)
- `UsbIdentifier` - USB VID/PID
- `DeviceFamily` - Family metadata (v1.0)
- `FlasherProject` - Project metadata (v2.0)
- `FlasherMetadata` - Collection metadata

**Usage:**
```dart
// Parse from JSON
final json = jsonDecode(content) as Map<String, dynamic>;
final device = DeviceDefinition.fromJson(json);

// Access properties (both v1.0 and v2.0)
print(device.title);                     // "ESP32-C3-mini"
print(device.flash.protocol);            // "esptool"
print(device.usb?.vidInt);               // 0x303A

// v2.0 hierarchical properties
print(device.effectiveProject);          // "geogram"
print(device.effectiveArchitecture);     // "esp32"
print(device.effectiveModel);            // "esp32-c3-mini"

// Firmware versions
for (final version in device.versions) {
  print('v${version.version}: ${version.size} bytes');
}
print(device.latestFirmwareVersion?.version);

// Create copy with selected version
final withVersion = device.withSelectedVersion(version);

// Get translated description
final desc = device.getDescription('pt');
```

### FirmwareVersion

**File:** `lib/flasher/models/device_definition.dart`

Model for firmware version metadata.

**Properties:**
- `version` - Version string (e.g., "1.2.0")
- `releaseNotes` - Optional release notes
- `releaseDate` - Optional release date
- `checksum` - Optional SHA256 checksum
- `size` - Optional file size in bytes

**Usage:**
```dart
final version = FirmwareVersion(
  version: '1.2.0',
  releaseNotes: 'Bug fixes and improvements',
  releaseDate: '2026-01-24',
  checksum: 'abc123...',
  size: 524288,
);

// Get firmware path relative to device folder
print(version.firmwarePath);  // "1.2.0/firmware.bin"
```

---

### Related Components

| Component | Location | Purpose |
|-----------|----------|---------|
| FlasherPage | flasher/pages/flasher_page.dart | Main UI for device flashing |
| DeviceCard | flasher/widgets/device_card.dart | Device selection card |
| FlashProgressWidget | flasher/widgets/flash_progress_widget.dart | Progress display |
| EspToolProtocol | flasher/protocols/esptool_protocol.dart | ESP32 flashing protocol |
| SerialPort | flasher/serial/serial_port.dart | Cross-platform USB serial (native APIs) |
| Esp32UsbIdentifiers | flasher/serial/serial_port.dart | ESP32 VID/PID matching utilities |
| NativeSerialAndroid | flasher/serial/native_serial_android.dart | Android USB Host API wrapper |
| NativeSerialLinux | flasher/serial/native_serial_linux.dart | Linux libc termios wrapper |
| UsbSerialPlugin | android/.../UsbSerialPlugin.kt | Android USB CDC-ACM plugin |

---

## Native Serial Port (Pure Platform APIs)

### Overview

Pure-Dart serial port implementation using native OS APIs - **no third-party dependencies**.

| Platform | Backend | Library |
|----------|---------|---------|
| **Android** | USB Host API (`android.hardware.usb.*`) | Built into Android SDK |
| **Linux** | libc termios | Built into Linux kernel |
| **macOS** | libc termios | Built into macOS (TODO) |
| **Windows** | kernel32 | Built into Windows (TODO) |

### NativeSerialLinux

**File:** `lib/flasher/serial/native_serial_linux.dart`

Pure-Dart FFI implementation for Linux serial ports.

**Key Features:**
- Uses libc termios (always available on Linux)
- Scans `/sys/class/tty/` for USB serial devices (ttyACM*, ttyUSB*)
- Reads VID/PID from sysfs
- Non-blocking I/O with poll()

**Usage:**
```dart
// List ports
final ports = await NativeSerialLinux.listPorts();
for (final port in ports) {
  print('${port.path}: VID=${port.vidHex}, PID=${port.pidHex}');
}

// Open and use
final serial = NativeSerialLinux();
if (await serial.open('/dev/ttyACM0', 115200)) {
  serial.setDTR(false);
  serial.setRTS(true);
  await Future.delayed(Duration(milliseconds: 100));
  serial.setDTR(true);

  await serial.write(Uint8List.fromList([0x7F])); // Sync byte
  final response = await serial.read(100, timeoutMs: 1000);
  print('Received: ${response.length} bytes');

  await serial.close();
}
```

**FFI Bindings (libc.so.6):**
```dart
// File operations
int open(const char* path, int flags);
int close(int fd);
ssize_t read(int fd, void* buf, size_t count);
ssize_t write(int fd, const void* buf, size_t count);

// Terminal control
int tcgetattr(int fd, struct termios* t);
int tcsetattr(int fd, int action, const struct termios* t);
int cfsetispeed(struct termios* t, speed_t speed);
int cfsetospeed(struct termios* t, speed_t speed);
int tcflush(int fd, int queue);
int tcdrain(int fd);

// DTR/RTS control via ioctl
int ioctl(int fd, TIOCMBIS/TIOCMBIC, &bits);
```

### NativeSerialAndroid

**File:** `lib/flasher/serial/native_serial_android.dart`

Dart wrapper for the Android USB Serial plugin (method channel).

**Usage:**
```dart
// List devices
final devices = await NativeSerialAndroid.listDevices();
for (final d in devices) {
  print('${d['deviceName']}: ${d['productName']} (ESP32: ${d['isEsp32']})');
}

// Request permission (shows system dialog)
final deviceName = devices.first['deviceName'] as String;
if (!await NativeSerialAndroid.hasPermission(deviceName)) {
  await NativeSerialAndroid.requestPermission(deviceName);
}

// Open and use
await NativeSerialAndroid.open(deviceName, baudRate: 115200);
await NativeSerialAndroid.setDTR(deviceName, false);
await NativeSerialAndroid.setRTS(deviceName, true);
await Future.delayed(Duration(milliseconds: 100));
await NativeSerialAndroid.setDTR(deviceName, true);

await NativeSerialAndroid.write(deviceName, Uint8List.fromList([0x7F]));
final data = await NativeSerialAndroid.read(deviceName, maxBytes: 100);
await NativeSerialAndroid.close(deviceName);
```

### UsbSerialPlugin (Kotlin)

**File:** `android/app/src/main/kotlin/dev/geogram/UsbSerialPlugin.kt`

Android plugin implementing CDC-ACM USB serial via Android USB Host API.

**CDC-ACM Control Requests:**
```kotlin
// Set baud rate, parity, stop bits
val lineCoding = ByteArray(7)  // 7-byte structure
connection.controlTransfer(0x21, SET_LINE_CODING, 0, 0, lineCoding, 7, 1000)

// Set DTR/RTS signals
val value = (if (dtr) 0x01 else 0x00) or (if (rts) 0x02 else 0x00)
connection.controlTransfer(0x21, SET_CONTROL_LINE_STATE, value, 0, null, 0, 1000)
```

**Method Channel API:**
- `listDevices` - List USB serial devices
- `requestPermission` - Show Android permission dialog
- `hasPermission` - Check permission status
- `open` - Open device connection
- `close` - Close device connection
- `read` - Read via bulk transfer
- `write` - Write via bulk transfer
- `setDTR` / `setRTS` - Control line signals
- `setBaudRate` - Change baud rate
- `flush` - Clear buffers

### UsbAttachmentService

**File:** `lib/services/usb_attachment_service.dart`

Dart service that handles USB device attachment events from Android. Listens to native MethodChannel and triggers navigation to Flasher Monitor tab when an ESP32 device is connected via USB OTG.

**Architecture:**
1. Android `AndroidManifest.xml` declares `USB_DEVICE_ATTACHED` intent filter with `device_filter.xml`
2. `MainActivity.kt` receives the intent, extracts VID/PID, checks against known ESP32 identifiers
3. Sends event to Dart via MethodChannel `dev.geogram/usb_attach`
4. `UsbAttachmentService` receives the event and triggers `DebugController.openFlasherMonitor`
5. HomePage listens for the action and navigates to FlasherPage with Monitor tab

**Usage:**
```dart
// Initialize once in main.dart (Android only)
if (Platform.isAndroid) {
  UsbAttachmentService().initialize();
}

// The service automatically handles USB attachment events
// No manual interaction required - it's event-driven
```

**Known ESP32 USB Identifiers (in device_filter.xml and MainActivity.kt):**
| Description | VID | PID |
|-------------|------|------|
| Espressif native USB (ESP32-C3/S2/S3) | 0x303A | 0x1001 |
| Espressif USB Bridge | 0x303A | 0x0002 |
| CP210x USB-UART | 0x10C4 | 0xEA60 |
| CH340 USB-UART | 0x1A86 | 0x7523 |
| CH9102 USB-UART | 0x1A86 | 0x55D4 |
| FTDI FT232 | 0x0403 | 0x6001 |
| FTDI FT231X | 0x0403 | 0x6015 |

**DebugController Integration:**
```dart
// Trigger flasher monitor navigation programmatically
DebugController().triggerOpenFlasherMonitor(devicePath: '/dev/bus/usb/001/002');

// Listen for the action in UI
_debugController.actionStream.listen((event) {
  if (event.action == DebugAction.openFlasherMonitor) {
    // Navigate to FlasherPage with initialTab: 2 (Monitor)
  }
});
```

### UsbAoaService

**File:** `lib/services/usb_aoa_service.dart`

Dart service for USB AOA (Android Open Accessory) device-to-device communication. Enables zero-config bidirectional communication between two Android phones connected via USB-C cable.

**Key Features:**
- Method channel bridge to native `UsbAoaPlugin.kt`
- Connection state stream for tracking USB connection status
- Data stream for receiving messages from connected device
- Android-only (USB AOA is an Android protocol)

**Usage:**
```dart
final usbService = UsbAoaService();
await usbService.initialize();

// Listen for connection changes
usbService.connectionStateStream.listen((state) {
  print('USB state: $state');
});

// Listen for incoming data
usbService.dataStream.listen((data) {
  final message = utf8.decode(data);
  print('Received: $message');
});

// Write data to connected device
await usbService.write(Uint8List.fromList(utf8.encode('Hello')));
```

### UsbAoaTransport

**File:** `lib/connection/transports/usb_aoa_transport.dart`

Transport implementation for USB AOA communication. Highest priority transport (5) - faster and more reliable than all other transports.

**Transport Priority:** 5 (USB) > 10 (LAN) > 15 (WebRTC) > 30 (Station) > 35 (BT Classic) > 40 (BLE)

**Message Format:**
```json
{
  "channel": "_api|_api_response|_dm|_system|<room_id>",
  "content": "<message JSON>",
  "timestamp": 1706000000000
}
```

Messages are length-prefixed (4 bytes big-endian) for reliable framing over the USB byte stream.

**Platform Support:**
- Android: Accessory mode (receives connection from Linux/Android host)
- Linux: Host mode (initiates AOA handshake to Android device)
- Other platforms: Not supported

### UsbAoaLinux

**File:** `lib/services/usb_aoa_linux.dart`

Pure Dart FFI implementation for Linux USB AOA host mode. Uses libc and kernel usbdevfs ioctls - no external dependencies.

**Key Features:**
- Device enumeration via `/sys/bus/usb/devices/`
- AOA handshake (GET_PROTOCOL, SEND_STRING, START)
- Bulk transfer I/O via `USBDEVFS_BULK` ioctl
- No libusb dependency - uses kernel APIs directly

**FFI Pattern (reusable for other USB implementations):**
```dart
// Load libc
final lib = DynamicLibrary.open('libc.so.6');

// Get function pointers
final open = lib.lookupFunction<OpenNative, OpenDart>('open');
final ioctl = lib.lookupFunction<IoctlPtrNative, IoctlPtrDart>('ioctl');

// USB control transfer structure
final class UsbCtrlTransfer extends Struct {
  @Uint8() external int bRequestType;
  @Uint8() external int bRequest;
  @Uint16() external int wValue;
  @Uint16() external int wIndex;
  @Uint16() external int wLength;
  @Uint32() external int timeout;
  external Pointer<Void> data;
}

// Perform control transfer
final ctrl = calloc<UsbCtrlTransfer>();
ctrl.ref.bRequestType = 0xC0; // IN, vendor, device
ctrl.ref.bRequest = 51; // AOA_GET_PROTOCOL
ctrl.ref.wLength = 2;
ctrl.ref.timeout = 1000;
ctrl.ref.data = buffer.cast();
ioctl(fd, USBDEVFS_CONTROL, ctrl.cast());
```

**USB Constants (from linux/usbdevice_fs.h):**
```dart
const USBDEVFS_CONTROL = 0xC0185500;
const USBDEVFS_BULK = 0xC0185502;
const USBDEVFS_CLAIMINTERFACE = 0x8004550F;
const USBDEVFS_RELEASEINTERFACE = 0x80045510;
const USBDEVFS_CLEAR_HALT = 0x80045515;
```

**IMPORTANT: poll() doesn't work reliably with USB device file descriptors on Linux**

When reading data from USB devices opened via `/dev/bus/usb/xxx/yyy`, the `poll()` system call may not properly signal data availability. The solution is to try a bulk read with a short timeout even when poll returns timeout:

```dart
// Read loop pattern for Linux USB
while (isReading && isConnected) {
  // Poll for incoming data (may not work reliably on USB)
  final pollResult = poll(pollFd.cast(), 1, 100);

  if (pollResult == 0) {
    // Timeout - but poll() may miss USB data!
    // Try a non-blocking bulk read anyway
    bulk.ref.ep = epIn;
    bulk.ref.len = bufferSize;
    bulk.ref.timeout = 50; // Short timeout for non-blocking check
    bulk.ref.data = buffer.cast();

    final bytesRead = ioctl(fd, USBDEVFS_BULK, bulk.cast());
    if (bytesRead > 0) {
      // Data was available even though poll() didn't report it!
      processData(buffer, bytesRead);
    }
    continue;
  }

  // Handle POLLIN, POLLERR, POLLHUP as normal
}
```

This pattern is used in `UsbAoaLinux._readLoopAsync()` to reliably receive data from Android devices.
