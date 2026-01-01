# Technical Documentation

This document provides an overview of Geogram's architecture with links to detailed specifications.

## Core Architecture

### [API](API.md)

The Station API provides HTTP and WebSocket endpoints for device communication. Stations act as optional relay points that bridge devices across the internet while preserving the ability to operate without them.

Key capabilities:
- **Connection Manager**: Transport-agnostic routing that selects the best available path (LAN, WebRTC, Station, Bluetooth) automatically
- **Device Proxy**: Forward requests to devices through the station when direct connection isn't possible
- **Chat API**: Room management, message posting, and WebSocket subscriptions for real-time updates
- **Direct Messages**: End-to-end encrypted messaging between specific callsigns
- **Software Updates**: Offline distribution of application updates for devices without internet
- **Map Tiles**: Cached OpenStreetMap and satellite imagery for offline mapping
- **Debug API**: Diagnostic endpoints for testing and troubleshooting (toggleable for security)

The API uses NOSTR-signed events for authentication, eliminating passwords and enabling cryptographic verification of all requests.

### [Data Transmission](data-transmission.md)

Geogram implements a transport-agnostic architecture where applications send messages without knowing which physical layer will deliver them. The Connection Manager handles transport selection and failover automatically.

**Transport Priority** (lower is preferred):
| Priority | Transport | Use Case |
|----------|-----------|----------|
| 10 | LAN | Direct HTTP on same network, fastest option |
| 15 | WebRTC | Peer-to-peer across NAT, no relay needed |
| 30 | Station | Internet relay when P2P fails |
| 35 | Bluetooth Classic | Fast offline transfers (paired devices) |
| 40 | BLE | Slow offline fallback, no pairing needed |

**Key Concepts**:
- **Automatic Fallback**: When one transport fails, the next priority is attempted
- **Message Queueing**: Messages can queue locally for later delivery to offline devices
- **TransportResult**: All sends return success/failure, transport used, and latency metrics
- **Platform Adaptation**: Desktop platforms are GATT clients only; mobile platforms can also serve

### [EventBus](EventBus.md)

The EventBus provides publish/subscribe communication between application components. Services fire events when state changes; UI and other services subscribe to react.

**Core Events**:
- `ChatMessageEvent`: New message in a room
- `DirectMessageReceivedEvent`: DM arrived (local or via sync)
- `ConnectionStateChangedEvent`: Transport availability changed (internet, LAN, station, bluetooth)
- `ClientConnectedEvent` / `ClientDisconnectedEvent`: Device presence changes
- `ProfileChangedEvent`: User identity updated
- `CollectionUpdatedEvent`: Files or data changed

**Usage Pattern**:
```dart
// Subscribe
final subscription = EventBus().on<ChatMessageEvent>((event) {
  // Handle new message
});

// Fire
EventBus().fire(ChatMessageEvent(roomId: 'general', content: 'Hello'));

// Cleanup
subscription.cancel();
```

The EventBus decouples components: the chat service fires message events without knowing what consumes them, while the UI subscribes without knowing the message source.

### [BLE](BLE.md)

Bluetooth Low Energy enables offline communication between devices within radio range. Geogram uses GATT (Generic Attribute Profile) with custom service and characteristics.

**Platform Capabilities**:
| Platform | GATT Server | GATT Client | Discoverable |
|----------|-------------|-------------|--------------|
| Android/iOS | Yes | Yes | Yes |
| Linux/macOS/Windows | No | Yes | No |

Desktop devices can discover and connect to mobile devices, but not the reverse. Mobile-to-mobile discovery uses periodic background scanning.

**GATT Structure**:
- Service UUID: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Write Characteristic (0xFFF1): Client sends to server
- Notify Characteristic (0xFFF2): Server responds to client
- Large messages split into 280-byte parcels with reassembly

### [Chat API](chat-api.md)

REST and WebSocket endpoints for room-based messaging. Rooms contain chronological messages with optional metadata (location, files, signatures).

**Endpoints**:
- `GET /api/chat/{roomId}/messages` - Retrieve messages with pagination
- `POST /api/chat/{roomId}/messages` - Post new message
- `WebSocket /ws` - Real-time subscriptions with `UPDATE:{callsign}/chat/{roomId}` notifications

Messages can include NOSTR signatures for verification. The API accepts both signed and unsigned messages, allowing communities to choose their authentication requirements.

### [Feedback API](API_feedback.md)

Centralized reaction system shared across all apps. Every content type (posts, events, places, alerts) uses the same feedback endpoints for consistency.

**Feedback Types**:
- Likes (simple appreciation)
- Points (weighted endorsement)
- Dislikes (disagreement)
- Verifications (confirming accuracy)
- Emoji reactions (expressive responses)
- Comments (threaded discussion)
- Subscriptions (follow for updates)

All feedback is NOSTR-signed for authentication. The feedback folder structure (`feedback/likes.txt`, `feedback/comments/`) appears consistently across all app types.

## Security and Configuration

### [Security Settings](security-settings.md)

Runtime-configurable security options that balance accessibility with protection.

**Toggles**:
- HTTP API enable/disable
- Debug API enable/disable (diagnostic endpoints)
- Location granularity (coordinate rounding for privacy)

Location privacy rounds coordinates before sharing, preventing precise tracking while maintaining regional relevance.

### [Command Line Switches](command-line-switches.md)

CLI arguments for different execution modes. Options include:
- Port configuration for station server
- Station URL for relay connections
- Callsign override
- Debug and logging flags
- Headless operation for servers

## Connection and Discovery

### [Device Connection Labels](device-connection-labels.md)

The UI displays connection paths for each discovered device. Labels indicate how you can reach a device and update dynamically as network conditions change.

**Label Types**:
- WiFi: Same local network
- Internet: Reachable via station relay
- Bluetooth: Within BLE range
- LoRa: Via radio gateway (future)

Labels add when connections become available and remove when lost, giving users clear visibility into communication options.

## App Format Specifications

Each app stores data in text-based formats designed for human readability, git compatibility, and offline-first operation. See the [apps/](apps/) folder for detailed specifications:

### Implemented Apps

- [chat-format-specification.md](apps/chat-format-specification.md) - Room messages with timestamps, callsigns, and metadata
- [blog-format-specification.md](apps/blog-format-specification.md) - Markdown posts with drafts and comments
- [events-format-specification.md](apps/events-format-specification.md) - Calendar entries with location and media
- [places-format-specification.md](apps/places-format-specification.md) - Geographic points of interest
- [groups-format-specification.md](apps/groups-format-specification.md) - Moderation hierarchy and membership
- [alert-format-specification.md](apps/alert-format-specification.md) - Geographic alerts with severity levels
- [inventory-format-specification.md](apps/inventory-format-specification.md) - Asset tracking with borrowing
- [transfer-format-specification.md](apps/transfer-format-specification.md) - Unified file transfer queue
- [bot-format-specification.md](apps/bot-format-specification.md) - Offline AI assistant configuration

### Upcoming Apps

- [forum-format-specification.md](apps/forum-format-specification.md) - Threaded discussions with sections
- [market-format-specification.md](apps/market-format-specification.md) - Shops, items, orders, reviews
- [news-format-specification.md](apps/news-format-specification.md) - Short announcements with geographic targeting
- [contacts-format-specification.md](apps/contacts-format-specification.md) - Identity directory with NOSTR keys
- [postcards-format-specification.md](apps/postcards-format-specification.md) - Sneakernet delivery with carrier stamps

### Infrastructure

- [relay-format-specification.md](apps/relay-format-specification.md) - Station configuration
- [backup-format-specification.md](apps/backup-format-specification.md) - User data backup format
- [service-format-specification.md](apps/service-format-specification.md) - Service provider listings

## Bridges

### [IRC Bridge](bridges/IRC.md)

Connect IRC clients to Geogram chat rooms. Users connect with standard IRC clients (irssi, WeeChat, HexChat) and participate in Geogram channels.

Channel mapping, authentication, and bidirectional message flow enable legacy IRC communities to bridge into Geogram infrastructure.

## Development Plans

The [plan/](plan/) folder contains implementation designs for upcoming features:

- [irc-bridge-implementation.md](plan/irc-bridge-implementation.md) - IRC server integration
- [chat-with-voice-messages.md](plan/chat-with-voice-messages.md) - Voice recording in DMs
- [app-alert-fix.md](plan/app-alert-fix.md) - Alert folder structure standardization

## Station Architecture

### [Station Implementation Plan](station-implementation-plan.md)

Comprehensive design for station functionality including:
- Root and node station hierarchy
- Channel bridging between stations
- Points/reputation system
- Authority management for content moderation

Stations are optional infrastructure that enhance connectivity without becoming required dependencies.

## Tutorials

### [Publish New Version](tutorials/publish-new-version.md)

Step-by-step release process: version numbering, changelog updates, git tagging, and automated builds through GitHub Actions.

## Installation and Building

### Supported Platforms

| Platform | Status |
|----------|--------|
| Android | Stable |
| Linux | Stable |
| Windows | Available but untested |
| macOS | Available but untested |
| iOS | Available but untested |
| Web | Available but untested |

### Prerequisites

- Flutter SDK 3.38.3+ with Dart 3.10+
- Platform-specific dependencies:
  - **Linux**: GTK development libraries (`ninja-build`, `clang`, `libgtk-3-dev`, `liblzma-dev`)
  - **Windows**: Visual Studio 2022 with C++ tools
  - **macOS**: Xcode
  - **Android**: Android Studio and SDK
  - **iOS**: Xcode (macOS only)
  - **Web**: Chrome or another browser

### Quick Setup (Linux)

Run the automated setup script:

```bash
./setup.sh
```

This installs system dependencies, downloads Flutter, and verifies the installation.

For component-by-component installation:

```bash
./install-linux-deps.sh   # System dependencies
./install-flutter.sh      # Flutter SDK (with resume support)
```

### Manual Setup

1. Install Flutter SDK 3.38.3+ from https://docs.flutter.dev/get-started/install
2. Verify Dart SDK version is 3.10.0+ with `flutter --version`
3. Install platform-specific dependencies

### Building

**Quick Start Scripts**:
- Linux: `./rebuild-desktop.sh` or `./launch-desktop.sh`
- Windows: `build-windows.bat` or `build-windows.sh`
- Web: `./launch-web.sh`
- Android: `./launch-android.sh`

**Manual Build**:

```bash
# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Run on platform
flutter run -d linux
flutter run -d macos
flutter run -d chrome
flutter run -d android
flutter run -d ios

# Build for deployment
flutter build linux
flutter build web
flutter build apk
```

### Detailed Build Guides

- [Linux Installation](installation/INSTALL.md)
- [Windows Installation](installation/INSTALL_WINDOWS.md)
- [Windows Build Guide](build/BUILD_WINDOWS.md)
- [Release Process](build/RELEASE.md)

### Project Structure

```
geogram/
├── lib/                    # Dart/Flutter application code
│   ├── bot/                # AI assistant services
│   ├── cli/                # Command-line interface
│   ├── connection/         # Transport layer (LAN, BLE, WebRTC)
│   ├── models/             # Data models
│   ├── pages/              # UI screens
│   ├── services/           # Business logic
│   └── widgets/            # Reusable UI components
├── android/                # Android platform code
├── ios/                    # iOS platform code
├── linux/                  # Linux platform code
├── macos/                  # macOS platform code
├── windows/                # Windows platform code
├── web/                    # Web platform code
├── docs/                   # Documentation
│   ├── apps/               # App format specifications
│   ├── bridges/            # Bridge documentation
│   ├── plan/               # Implementation plans
│   └── tutorials/          # How-to guides
└── test/                   # Tests
```

### Development

**Hot Reload**: Press `r` in terminal while running to reload changes, `R` to restart.

**Check Devices**:
```bash
flutter devices
```

**Run Tests**:
```bash
flutter test
```

### Log Files

Application logs write to `~/Documents/geogram/log.txt`. Read with:

```bash
./read-log.sh           # Last 100 lines
./read-log.sh -n 50     # Last 50 lines
./read-log.sh -f        # Follow in real-time
```
