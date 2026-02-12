# Mirror Sync Feature - Implementation Plan

## Overview

The Mirror feature enables two or more devices running the same account to stay synchronized. Devices sync directly with each other (P2P) over LAN, BLE, or through the station as relay. No central coordination - each device manages its own sync relationships.

## Key Requirements

1. **P2P Sync**: Devices sync directly, station is just a relay option
2. **Mirror Wizard**: Setup wizard to pair devices and choose apps
3. **Sync Styles** (like Syncthing):
   - **Send & Receive**: Full two-way sync
   - **Receive Only**: Passive mirror, only receives updates
   - **Send Only**: Source device, doesn't receive changes
4. **Per-App Settings**: Each app can have different sync style
5. **Connection Quality**: Prefer WiFi/LAN over cellular
6. **Offline Support**: Queue changes, sync when reconnected

---

## Architecture

### P2P Model (Syncthing-style)

```
┌─────────────────────┐              ┌─────────────────────┐
│  DEVICE A (Home)    │              │  DEVICE B (Phone)   │
│  ┌───────────────┐  │              │  ┌───────────────┐  │
│  │ MirrorService │  │◄────────────►│  │ MirrorService │  │
│  │  - Peers list │  │   LAN/BLE    │  │  - Peers list │  │
│  │  - Sync queue │  │   Station    │  │  - Sync queue │  │
│  │  - Mergers    │  │   Relay      │  │  - Mergers    │  │
│  └───────────────┘  │              │  └───────────────┘  │
│                     │              │                     │
│  Apps:              │              │  Apps:              │
│  - Blog: Send&Recv  │              │  - Blog: Send&Recv  │
│  - Chat: Send&Recv  │              │  - Chat: Recv Only  │
│  - Places: Send     │              │  - Places: Recv     │
└─────────────────────┘              └─────────────────────┘
```

### Discovery & Connection

Devices find each other through:
1. **LAN Discovery**: mDNS/UDP broadcast on local network
2. **BLE Proximity**: Bluetooth Low Energy when nearby
3. **Station Relay**: Through connected station when not on same network
4. **Manual**: Enter device URL/address

---

## Data Models

### 1. MirrorPeer

```dart
/// A paired mirror device
/// File: lib/models/mirror_peer.dart
class MirrorPeer {
  /// Unique peer ID (matches remote device's mirrorDeviceId)
  final String peerId;

  /// Friendly name
  String name;

  /// Callsign (should match ours for same account)
  String callsign;

  /// Known addresses (LAN IPs, station relay, etc.)
  List<String> addresses;

  /// Per-app sync configuration
  Map<String, AppSyncConfig> apps;

  /// Connection state
  PeerConnectionState state;

  /// Last successful sync
  DateTime? lastSyncAt;

  /// Last seen online
  DateTime? lastSeenAt;

  /// Connection quality when last seen
  ConnectionQuality? lastQuality;
}

enum PeerConnectionState {
  disconnected,  // Not connected
  connecting,    // Attempting connection
  connected,     // Active connection
  syncing,       // Currently syncing
}
```

### 2. AppSyncConfig

```dart
/// Per-app sync configuration for a peer
/// File: lib/models/app_sync_config.dart
class AppSyncConfig {
  /// App ID (collection type)
  final String appId;

  /// Sync style
  SyncStyle style;

  /// Is sync enabled for this app?
  bool enabled;

  /// Last sync state
  SyncState state;

  /// Sync statistics
  SyncStats stats;
}

enum SyncStyle {
  /// Full two-way sync - both sides send and receive
  sendReceive,

  /// Receive only - passive mirror, don't send changes
  receiveOnly,

  /// Send only - source device, don't accept changes
  sendOnly,

  /// Paused - temporarily disabled
  paused,
}

enum SyncState {
  idle,           // Up to date
  scanning,       // Checking for changes
  syncing,        // Transferring files
  error,          // Sync failed
  outOfSync,      // Changes pending
}

class SyncStats {
  int filesInSync;
  int filesOutOfSync;
  int bytesTotal;
  int bytesNeeded;
  DateTime? lastScan;
}
```

### 3. MirrorConfig (Device-wide)

```dart
/// Device-wide mirror configuration
/// File: lib/models/mirror_config.dart
class MirrorConfig {
  /// Enable mirror feature
  bool enabled;

  /// This device's unique ID
  String deviceId;

  /// This device's friendly name
  String deviceName;

  /// Paired peers
  List<MirrorPeer> peers;

  /// Connection preferences
  ConnectionPreferences preferences;

  /// Default sync style for new apps
  SyncStyle defaultSyncStyle;
}

class ConnectionPreferences {
  /// Sync over metered connections (cellular)?
  bool allowMetered;

  /// Maximum bandwidth on metered (KB/s, 0 = unlimited)
  int meteredBandwidthLimit;

  /// Sync when on battery?
  bool allowOnBattery;

  /// Minimum battery level to sync
  int minBatteryLevel;

  /// Announce on LAN for discovery?
  bool lanDiscovery;

  /// Announce via BLE?
  bool bleDiscovery;
}
```

### 4. SyncManifest

```dart
/// State snapshot for an app
/// File: lib/models/sync_manifest.dart
class SyncManifest {
  String appId;
  String deviceId;

  /// Lamport clock / version for this device
  int localVersion;

  /// Known versions from other devices
  Map<String, int> knownVersions;

  /// Files in this app
  List<SyncFileEntry> files;

  /// Last modified timestamp
  DateTime modifiedAt;
}

class SyncFileEntry {
  String path;
  String hash;  // SHA256
  int size;
  DateTime modifiedAt;
  int version;  // Lamport clock when last modified
}
```

---

## Services

### 1. MirrorService

```dart
/// Main mirror sync service
/// File: lib/services/mirror_service.dart
class MirrorService {
  /// Singleton instance
  static final instance = MirrorService._();

  /// Configuration
  late MirrorConfig _config;

  /// Active peer connections
  final Map<String, PeerConnection> _connections = {};

  /// App-specific mergers
  final Map<String, AppMerger> _mergers = {};

  /// Initialize mirror service
  Future<void> initialize();

  /// Add a new peer (from wizard)
  Future<void> addPeer(MirrorPeer peer);

  /// Remove a peer
  Future<void> removePeer(String peerId);

  /// Update peer app configuration
  Future<void> updatePeerApp(String peerId, AppSyncConfig config);

  /// Connect to a peer
  Future<PeerConnection> connectToPeer(String peerId);

  /// Disconnect from a peer
  Future<void> disconnectPeer(String peerId);

  /// Trigger sync with a peer
  Future<SyncResult> syncWithPeer(String peerId, {String? appId});

  /// Trigger sync for all connected peers
  Future<void> syncAll();

  /// Get current sync status
  Stream<MirrorStatus> get statusStream;

  /// Handle incoming sync request from peer
  Future<void> handleSyncRequest(String peerId, SyncRequest request);

  /// Register app merger
  void registerMerger(String appId, AppMerger merger);
}
```

### 2. PeerConnection

```dart
/// Active connection to a peer
/// File: lib/services/peer_connection.dart
class PeerConnection {
  final MirrorPeer peer;
  final Transport transport;  // LAN, BLE, Station relay

  /// Connection state
  PeerConnectionState state;

  /// Latency in ms
  int? latency;

  /// Send a message to peer
  Future<void> send(SyncMessage message);

  /// Request manifest for an app
  Future<SyncManifest> requestManifest(String appId);

  /// Request file from peer
  Future<Uint8List> requestFile(String appId, String path);

  /// Send manifest to peer
  Future<void> sendManifest(SyncManifest manifest);

  /// Send file to peer
  Future<void> sendFile(String appId, String path, Uint8List data);

  /// Close connection
  Future<void> close();
}
```

### 3. PeerDiscoveryService

```dart
/// Discover mirror peers on network
/// File: lib/services/peer_discovery_service.dart
class PeerDiscoveryService {
  /// Start LAN discovery (mDNS)
  Future<void> startLanDiscovery();

  /// Start BLE discovery
  Future<void> startBleDiscovery();

  /// Stop all discovery
  Future<void> stopDiscovery();

  /// Stream of discovered peers
  Stream<DiscoveredPeer> get discoveredPeers;

  /// Announce this device on LAN
  Future<void> announceLan();

  /// Announce via BLE
  Future<void> announceBle();
}

class DiscoveredPeer {
  String deviceId;
  String deviceName;
  String callsign;
  String address;
  DiscoveryMethod method;  // lan, ble, manual
  int? signalStrength;
}
```

### 4. AppMerger (Abstract)

```dart
/// Abstract merger for app-specific sync logic
/// File: lib/services/merge/app_merger.dart
abstract class AppMerger {
  String get appId;

  /// Generate manifest of current state
  Future<SyncManifest> generateManifest();

  /// Compare local and remote manifests
  Future<SyncDiff> computeDiff(
    SyncManifest local,
    SyncManifest remote,
    SyncStyle style,
  );

  /// Merge changes based on sync style
  Future<MergeResult> merge(
    SyncDiff diff,
    SyncStyle style,
    PeerConnection peer,
  );

  /// Apply received changes
  Future<void> applyChanges(List<SyncChange> changes);
}

class SyncDiff {
  List<SyncFileEntry> toDownload;  // Files we need from peer
  List<SyncFileEntry> toUpload;    // Files peer needs from us
  List<SyncConflict> conflicts;    // Both modified
}
```

---

## UI Components

### 1. Mirror Wizard

```dart
/// Setup wizard for adding a mirror peer
/// File: lib/pages/mirror_wizard_page.dart
class MirrorWizardPage extends StatefulWidget {
  // Steps:
  // 1. Introduction - explain mirror feature
  // 2. Device Discovery - find peers on LAN/BLE
  // 3. Pairing - exchange device IDs, verify same account
  // 4. Select Apps - choose which apps to sync
  // 5. Sync Style - per-app: Send&Receive, Receive Only, Send Only
  // 6. Initial Sync - download existing data or start fresh
  // 7. Complete - show summary, start sync
}
```

**Wizard Steps Detail:**

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Introduction                                            │
│                                                                 │
│  Mirror keeps your apps synchronized between devices.           │
│                                                                 │
│  - Changes on one device appear on the other                    │
│  - Works over WiFi, Bluetooth, or internet                      │
│  - Choose which apps to sync                                    │
│  - Control sync direction per app                               │
│                                                                 │
│                                          [Next]                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Find Device                                             │
│                                                                 │
│  Searching for devices...                                       │
│                                                                 │
│  📱 Phone (192.168.1.45)                    [Pair]             │
│     Same account • WiFi • 12ms                                  │
│                                                                 │
│  💻 Laptop (via BLE)                        [Pair]             │
│     Same account • Nearby                                       │
│                                                                 │
│  ─────────────────────────────────────────────                 │
│  Or enter address manually:                                     │
│  [                                        ] [Connect]           │
│                                                                 │
│                                [Back]     [Next]                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Select Apps                                             │
│                                                                 │
│  Choose apps to synchronize:                                    │
│                                                                 │
│  ☑ Blog                    [Send & Receive ▾]                  │
│    Posts, comments, likes                                       │
│                                                                 │
│  ☑ Chat                    [Receive Only ▾]                    │
│    Messages, conversations                                      │
│                                                                 │
│  ☑ Places                  [Send & Receive ▾]                  │
│    Saved locations                                              │
│                                                                 │
│  ☐ Tracker                 [Paused ▾]                          │
│    GPS tracks (large files)                                     │
│                                                                 │
│                                [Back]     [Next]                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Initial Sync                                            │
│                                                                 │
│  The other device has existing data. How should we proceed?     │
│                                                                 │
│  ○ Download all existing data (recommended)                     │
│    Get everything from the other device                         │
│                                                                 │
│  ○ Start fresh, sync only new changes                           │
│    Keep current data, merge going forward                       │
│                                                                 │
│  ○ Replace other device's data with mine                        │
│    Upload my data, overwrite theirs                             │
│                                                                 │
│                                [Back]     [Start Sync]          │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Mirror Settings Page

```dart
/// Mirror settings and peer management
/// File: lib/pages/mirror_settings_page.dart
class MirrorSettingsPage extends StatefulWidget {
  // Sections:
  // 1. This Device
  //    - Device name (editable)
  //    - Device ID (readonly)
  //    - Connection quality indicator
  //
  // 2. Paired Devices
  //    - List of peers with status
  //    - Tap to edit peer settings
  //    - Swipe to remove
  //    - Add new peer button
  //
  // 3. Connection Preferences
  //    - Allow metered connections
  //    - Bandwidth limit
  //    - Battery settings
  //    - Discovery settings
  //
  // 4. Sync Status
  //    - Overall sync state
  //    - Per-app status
  //    - Manual sync button
}
```

### 3. Peer Settings Page

```dart
/// Settings for a specific peer
/// File: lib/pages/peer_settings_page.dart
class PeerSettingsPage extends StatefulWidget {
  final MirrorPeer peer;

  // Sections:
  // 1. Peer Info
  //    - Name, callsign, device ID
  //    - Connection status
  //    - Last sync time
  //
  // 2. Apps
  //    - List of apps with sync style dropdown
  //    - Enable/disable per app
  //    - Last sync status per app
  //
  // 3. Actions
  //    - Sync now button
  //    - View sync history
  //    - Remove peer
}
```

### 4. Mirror Status Widget

```dart
/// Status indicator for app bar
/// File: lib/widgets/mirror_status_widget.dart
class MirrorStatusWidget extends StatelessWidget {
  // Shows:
  // - Icon: synced ✓, syncing ↻, pending ⋯, error ⚠
  // - Connected peers count
  // - Tap to open mirror settings
}
```

---

## Sync Protocol

### Message Types

```dart
enum SyncMessageType {
  // Discovery
  hello,           // Initial handshake
  helloAck,        // Handshake response

  // Manifest exchange
  manifestRequest, // Request app manifest
  manifestResponse,// Send app manifest

  // File transfer
  fileRequest,     // Request specific file
  fileResponse,    // Send file content

  // Change notification
  changeNotify,    // Notify of local changes

  // Sync control
  syncStart,       // Begin sync session
  syncComplete,    // End sync session
  syncError,       // Report sync error
}
```

### Sync Flow (Two-way)

```
Device A                           Device B
   │                                  │
   │──── hello ──────────────────────►│
   │◄─── helloAck ───────────────────│
   │                                  │
   │──── syncStart(blog) ───────────►│
   │                                  │
   │──── manifestRequest ───────────►│
   │◄─── manifestResponse ───────────│
   │                                  │
   │  (compute diff)                  │
   │                                  │
   │──── fileRequest(post1.md) ─────►│
   │◄─── fileResponse(data) ─────────│
   │                                  │
   │◄─── fileRequest(post2.md) ──────│
   │──── fileResponse(data) ─────────►│
   │                                  │
   │──── syncComplete ──────────────►│
   │◄─── syncComplete ───────────────│
```

### Sync Flow (Receive Only)

```
Device A (Source)                  Device B (Receive Only)
   │                                  │
   │──── changeNotify(blog) ────────►│
   │                                  │
   │◄─── syncStart(blog) ────────────│
   │◄─── manifestRequest ────────────│
   │──── manifestResponse ──────────►│
   │                                  │
   │◄─── fileRequest(post1.md) ──────│
   │──── fileResponse(data) ─────────►│
   │                                  │
   │◄─── syncComplete ───────────────│
```

---

## Implementation Phases

### Phase 1: Foundation
1. Create data models (MirrorPeer, AppSyncConfig, MirrorConfig)
2. Create MirrorConfigService for settings persistence
3. Create basic MirrorSettingsPage UI
4. Device ID generation and storage

### Phase 2: Mirror Wizard
1. Create MirrorWizardPage with step flow
2. Implement peer discovery (LAN via existing NetworkMonitor)
3. Implement manual peer entry
4. App selection UI with sync style picker

### Phase 3: Sync Engine
1. Implement MirrorService core
2. Implement PeerConnection using existing transports
3. Implement manifest generation/comparison
4. Basic file sync (send/receive)

### Phase 4: App Mergers
1. Create abstract AppMerger interface
2. Implement DefaultMerger (file-level, newest wins)
3. Implement BlogMerger (posts/comments union)
4. Implement ChatMerger (messages union)

### Phase 5: Polish
1. Background sync support
2. Conflict resolution UI
3. Sync history/logs
4. Battery/bandwidth optimizations

---

## File Structure

```
lib/
├── models/
│   ├── mirror_config.dart
│   ├── mirror_peer.dart
│   ├── app_sync_config.dart
│   └── sync_manifest.dart
├── services/
│   ├── mirror_service.dart
│   ├── mirror_config_service.dart
│   ├── peer_connection.dart
│   ├── peer_discovery_service.dart
│   └── merge/
│       ├── app_merger.dart
│       ├── default_merger.dart
│       ├── blog_merger.dart
│       └── chat_merger.dart
├── pages/
│   ├── mirror_wizard_page.dart
│   ├── mirror_settings_page.dart
│   └── peer_settings_page.dart
└── widgets/
    └── mirror_status_widget.dart
```

---

## Next Steps

Start with Phase 1 + 2 (Foundation + Wizard):
1. Create data models
2. Create MirrorConfigService
3. Build MirrorWizardPage UI
4. Implement peer discovery using existing LAN detection
5. Build MirrorSettingsPage

This gives us a working UI for pairing devices and configuring sync, which we can then wire up to the actual sync engine.
