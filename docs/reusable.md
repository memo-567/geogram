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

### Selector Widgets
- [CallsignSelectorWidget](#callsignselectorwidget) - Profile switching
- [ProfileSwitcher](#profileswitcher) - App bar profile

### Tree Widgets
- [FolderTreeWidget](#foldertreewidget) - Folder navigation

### Message Widgets
- [MessageBubbleWidget](#messagebubblewidget) - Chat bubbles
- [MessageInputWidget](#messageinputwidget) - Message composer

### Services
- [LocationService](#locationservice) - City lookup from coordinates

### QR Widgets
- [QrShareReceiveWidget](#qrsharereceivewidget) - Share/receive data via QR

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
| CallsignSelectorWidget | widgets/ | Selector | Profile switching |
| ProfileSwitcher | widgets/ | Selector | App bar profile |
| FolderTreeWidget | widgets/inventory/ | Tree | Folder navigation |
| MessageBubbleWidget | widgets/ | Message | Chat bubbles |
| MessageInputWidget | widgets/ | Input | Message composer |
| LocationService | services/ | Service | City lookup from coordinates |
| QrShareReceiveWidget | widgets/ | QR | Share/receive data via QR |
