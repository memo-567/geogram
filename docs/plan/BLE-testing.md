# BLE Transport Testing & Fix Plan

## Overview

This plan outlines how to diagnose, fix, and test BLE communication between two Android devices (TANK2 and C61) to achieve the same level of data exchange as LAN/Internet transports.

## Current State

**Connected Devices (via ADB):**
| Device | Serial | Model | USB Port |
|--------|--------|-------|----------|
| OUKITEL C61 | C61000000004616 | C61 | 1-5 |
| OUKITEL TANK2 | TANK200000007933 | TANK2 | 1-3 |

**Working Transports:** LAN, Station (Internet)
**Broken Transport:** BLE

---

## Root Cause Analysis

The exploration identified **5 critical issues** preventing BLE from working:

### Issue 1: BleTransport Never Initializes BLEMessageService
**File:** `lib/connection/transports/ble_transport.dart:59-72`

`BleTransport.initialize()` only subscribes to incoming messages but never calls `_messageService.initialize()`. The actual initialization happens separately in DevicesService.

### Issue 2: Race Condition - Initialization Order
**File:** `lib/main.dart:366-463`

```
Line 372: ConnectionManager.initialize() → BleTransport.initialize() (incomplete)
Lines 417-462: DevicesService.initialize() → BLEMessageService initialized (too late)
```

When BleTransport is initialized, BLEMessageService isn't ready yet.

### Issue 3: Fire-and-Forget API Requests
**File:** `lib/connection/transports/ble_transport.dart:176-219`

BLE sends API requests but returns success immediately without waiting for responses:
```dart
// NOTE: BLE API requests are fire-and-forget by nature
// The response would come back as a separate incoming message
```

Compare with LAN transport which gets real HTTP responses.

### Issue 4: Response Routing Lost
**File:** `lib/connection/connection_manager.dart:415-475`

When receiving API requests via BLE, ConnectionManager forwards to local HTTP API but **discards the response** - never sends it back to the requesting device.

### Issue 5: No API_RESPONSE Message Type
**File:** `lib/models/ble_message.dart:9-15`

Protocol only defines: `hello`, `helloAck`, `chat`, `chatAck`, `error`
No `api_request` or `api_response` types exist.

---

## Testing Strategy

### Phase 1: Diagnostic Testing (No Code Changes)

**Goal:** Verify current BLE state and identify exactly where communication breaks down.

#### Step 1.1: Get Device Callsigns
Use ADB to check the callsigns of both devices (needed for DM targeting):

```bash
# On each device, check logs or use debug API
adb -s TANK200000007933 shell "cat /data/data/dev.geogram/files/profile.json 2>/dev/null | grep callsign"
adb -s C61000000004616 shell "cat /data/data/dev.geogram/files/profile.json 2>/dev/null | grep callsign"
```

Or via debug API if HTTP API is running on the devices.

#### Step 1.2: Check BLE Discovery
Verify devices can discover each other via BLE:

```bash
# On TANK2 - trigger BLE scan
adb -s TANK200000007933 shell am broadcast -a dev.geogram.DEBUG_ACTION --es action ble_scan

# Check logcat for discovery results
adb -s TANK200000007933 logcat -d | grep -i "BLE\|discovery\|GATT"
```

#### Step 1.3: Verify HELLO Handshake
Check if HELLO messages are exchanged:

```bash
# Monitor BLE messages on both devices
adb -s TANK200000007933 logcat -d | grep -i "HELLO\|handshake\|BLEMessage"
adb -s C61000000004616 logcat -d | grep -i "HELLO\|handshake\|BLEMessage"
```

#### Step 1.4: Test DM via Debug API
Attempt to send a DM and observe where it fails:

```bash
# If device has debug API running on port 3456:
# From laptop, forward ports
adb -s TANK200000007933 forward tcp:3456 tcp:3456

# Send DM (replace CALLSIGN with actual C61 callsign)
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "send_dm", "callsign": "XXXXXX", "content": "BLE test message"}'
```

### Phase 2: Minimal Fixes for DM Delivery

**Goal:** Get DMs working over BLE with minimal code changes.

#### Fix 2.1: Ensure BLEMessageService is Initialized
**File:** `lib/connection/transports/ble_transport.dart`

Add initialization call in `BleTransport.initialize()`:
```dart
@override
Future<void> initialize() async {
  // NEW: Ensure message service is initialized
  final profile = ProfileService().getProfile();
  if (profile.callsign.isNotEmpty) {
    await _messageService.initialize(
      callsign: profile.callsign,
      npub: profile.npub,
    );
  }
  // ... rest of existing code
}
```

#### Fix 2.2: Wait for Device Discovery
**File:** `lib/connection/transports/ble_transport.dart`

Improve `canReach()` to wait briefly for discovery:
```dart
@override
Future<bool> canReach(String callsign) async {
  if (!isInitialized) return false;

  // Check if already discovered
  var devices = _discoveryService.getAllDevices();
  if (devices.any((d) => d.callsign?.toUpperCase() == callsign.toUpperCase())) {
    return true;
  }

  // Wait briefly for ongoing scan
  await Future.delayed(const Duration(seconds: 2));
  devices = _discoveryService.getAllDevices();
  return devices.any((d) => d.callsign?.toUpperCase() == callsign.toUpperCase());
}
```

### Phase 3: Full API Request/Response Support

**Goal:** Make BLE work exactly like LAN for API requests (with async response).

#### Fix 3.1: Add Request ID Tracking
Track pending requests waiting for responses.

#### Fix 3.2: Route Responses Back
In ConnectionManager, after forwarding API request to local server, send response back via BLE.

#### Fix 3.3: Add API_RESPONSE Message Type
Extend BLEMessageType enum to include API request/response types.

---

## Implementation Order

1. **Diagnostic testing** - Understand current failure points
2. **Fix 2.1** - Initialize BLEMessageService in BleTransport
3. **Re-test** - Verify improvement
4. **Fix 2.2** - Improve device discovery timing
5. **Re-test** - Verify DM delivery
6. **Fix 3.x** - Full API request/response (if needed for DMs)

---

## Files to Modify

| Priority | File | Changes |
|----------|------|---------|
| HIGH | `lib/connection/transports/ble_transport.dart` | Initialize BLEMessageService, improve canReach() |
| MEDIUM | `lib/connection/connection_manager.dart` | Route API responses back via BLE |
| LOW | `lib/models/ble_message.dart` | Add API message types |
| LOW | `lib/main.dart` | Consider initialization order |

---

## Verification Checklist

- [ ] Both devices discover each other via BLE
- [ ] HELLO handshake completes successfully
- [ ] DM sent from TANK2 arrives on C61

---

## Linux Desktop BLE Implementation (Updated 2026-01-19)

### Current Status: WORKING (Partial)

**What works:**
- ✅ BLE scanning via flutter_blue_plus - discovers Android Geogram devices
- ✅ BlueZ D-Bus advertisement registration (ActiveInstances = 1)
- ✅ GATT service registration (FFE0 with FFF1/FFF2/FFF3 characteristics)
- ✅ Adapter alias set to callsign (visible device name)
- ✅ ServiceData with Geogram marker (0x3E) - detected by some Android devices
- ✅ Linux laptop visible on BLE scanner apps (nRF Connect, etc.)

**Discovery Confirmed Working (2026-01-19):**
```
BLEDiscovery: [DEBUG] Device 98:AF:65:73:B9:EA "X14YN5" serviceData keys: [ffe0]
BLEDiscovery: [DEBUG]   ffe0 -> [0x3e 0x00 0x0a 0x58 0x31 0x34 0x59 0x4e 0x35...] (9 bytes)
BLEDiscovery: Found Geogram device via serviceData: 98:AF:65:73:B9:EA
```
- ServiceData format: `[0x3E marker][DeviceID 2 bytes][Callsign]`
- Short UUID `ffe0` correctly maps to full UUID `0000ffe0-...`

**What needs investigation:**
- ⚠️ Device visibility varies between Android phones
  - Some Android devices see Linux laptop ✓
  - Other Android devices may not see it
  - Possible causes: Linux geogram not running, BLE caching, different Bluetooth stacks, scan timing

### Key Implementation Files

| File | Purpose |
|------|---------|
| `lib/services/ble_linux_peripheral.dart` | BlueZ D-Bus peripheral implementation |
| `lib/services/ble_message_service.dart` | Initializes Linux peripheral with callsign/deviceId |
| `lib/services/ble_gatt_server_service.dart` | Fallback initialization path |
| `lib/services/ble_discovery_service.dart` | BLE scanning and device detection |

### BlueZ Advertisement Properties

The Linux peripheral advertises with:
```
Type: peripheral
ServiceUUIDs: [0000ffe0-0000-1000-8000-00805f9b34fb]
LocalName: <callsign>  (e.g., "X14YN5")
ServiceData: {
  "0000ffe0-0000-1000-8000-00805f9b34fb": [0x3E, deviceId_hi, deviceId_lo, callsign_bytes...]
}
```

The ServiceData format matches what Android Geogram expects:
- First byte: 0x3E (Geogram marker '>')
- Bytes 2-3: Device ID (16-bit)
- Remaining bytes: Callsign (up to 17 bytes)

### Service UUID Change (2026-01-18)

Changed from 0xFFF0 to 0xFFE0 to avoid conflict with Android's PKOC (Physical Key Ownership Check) which reserves 0xFFF0.

### Testing Commands

**Start Linux test instance (persistent identity):**
```bash
./build/linux/x64/release/bundle/geogram --port=5599 --data-dir=/tmp/geogram-ble-test9 --debug-api
```

**Check advertisement registration:**
```bash
dbus-send --system --dest=org.bluez --print-reply /org/bluez/hci0 \
  org.freedesktop.DBus.Properties.Get \
  string:"org.bluez.LEAdvertisingManager1" string:"ActiveInstances"
# Should return: variant byte 1
```

**Check adapter alias (device name):**
```bash
dbus-send --system --dest=org.bluez --print-reply /org/bluez/hci0 \
  org.freedesktop.DBus.Properties.Get \
  string:"org.bluez.Adapter1" string:"Alias"
# Should return: variant string "<callsign>"
```

**Check Bluetooth adapter status:**
```bash
echo "show" | bluetoothctl
# Look for: Powered: yes, Discoverable: yes, UUID: 0000ffe0-...
```

### Troubleshooting Android Discovery Issues

If Android Geogram doesn't see the Linux laptop:

1. **Toggle Bluetooth off/on** on the Android device (clears BLE cache)
2. **Force close and reopen** Geogram app
3. **Pull down in Devices tab** to trigger fresh scan
4. **Wait 45+ seconds** for periodic scan cycle
5. **Check Android version** - newer Android may have stricter BLE filtering

### Architecture Notes

```
Linux Desktop                          Android Device
┌─────────────────────┐               ┌─────────────────────┐
│ BleLinuxPeripheral  │               │ flutter_blue_plus   │
│   └─ BlueZ D-Bus    │◄──── BLE ────►│   └─ Android BLE    │
│       └─ hci0       │               │       └─ Scan/GATT  │
│                     │               │                     │
│ Advertisement:      │               │ Discovery:          │
│  - ServiceUUID FFE0 │               │  - Check serviceData│
│  - ServiceData 0x3E │               │  - Check mfgData    │
│  - LocalName        │               │  - Check advName    │
└─────────────────────┘               └─────────────────────┘
```

### Previous Notes (Historical)

What we originally had:
- Linux selects a `BleLinuxPeripheral` that registers LEAdvertisement1 (FFE0) and a GATT app with FFF1 (write), FFF2 (notify), FFF3 (status). ObjectManager/Properties are implemented; Notifying updates are emitted.
- Build passes: `flutter build linux --release`.
- Diagnostics log bluetoothd state and adapters; start/stop unregisters cleanly.

Current behavior on Linux:
- BLE scanning works (flutter_blue_plus).
- Advertising works with ServiceData containing Geogram marker.
- Android BLE remains unchanged.
- [ ] DM sent from C61 arrives on TANK2
- [ ] Messages appear in DM conversation UI
- [ ] No crashes or "Player disposed" errors

---

## RAM Considerations

- **No Flutter build** - Use existing APKs on devices
- **ADB commands lightweight** - logcat with grep is OK
- **Debug API over HTTP** - Low overhead
- **One device at a time** - If needed, test sequentially

---

## Debug API Reference

### Send DM
```bash
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "send_dm", "callsign": "TARGET_CALLSIGN", "content": "Message text"}'
```

### Trigger BLE Scan
```bash
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "ble_scan"}'
```

### Send BLE HELLO
```bash
curl -X POST http://localhost:3456/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "ble_hello", "device_id": "MAC_ADDRESS"}'
```

### Get Discovered Devices
```bash
curl http://localhost:3456/api/devices
```

### Check Status
```bash
curl http://localhost:3456/api/status
```

### Browse Remote Device Apps
```bash
# Test if Tank2 can see C61's shared apps
curl -X POST http://localhost:3457/api/debug \
  -H "Content-Type: application/json" \
  -d '{"action": "device_browse_apps", "callsign": "X1L3W3"}'
```

---

## Current Issue: Remote Device Apps Not Visible (2026-01-18)

### Problem
When clicking on a remote device in the Devices UI panel, shared apps (blog, chat) are not visible. Direct 1:1 chat works over BLE, but API requests for discovering apps fail.

### Difference Between Working and Failing Paths

| Feature | Direct Chat | API Request (Blog) |
|---------|-------------|-------------------|
| Type | One-way message | Round-trip request/response |
| Response needed | No | Yes - must match by request ID |
| Status | WORKS | FAILS |

### Code Flow for Remote Device Apps

**Request Path (Tank2 → C61):**
```
DeviceDetailPage._loadApps()
  → DeviceAppsService._checkBlogAvailable()
    → DevicesService.makeDeviceApiRequest(path: '/api/blog')
      → ConnectionManager.apiRequest()
        → BleTransport._handleApiRequest()
          → Creates Completer, stores in _pendingRequests[requestId]
          → BLEMessageService.sendChatToCallsign(channel: '_api')
          → Waits on completer.future with 30s timeout
```

**Response Path (C61 → Tank2):**
```
C61 GATT server receives write
  → Processes API request locally
  → Sends response via BleTransport._handleApiResponse()
    → BLEMessageService.sendChatToCallsign(channel: '_api_response')
      → sendRawToClient() → GATT notification to Tank2

Tank2 receives notification:
  → _BLEConnection._handleNotification()
    → Parses JSON, forwards via onChatReceived callback
      → _incomingChatsController stream
        → BleTransport._handleClientNotification()
          → Matches _pendingRequests[requestId], completes completer
```

### Bug #1: JSON Completeness Detection (HIGH PRIORITY)

**File:** `lib/services/ble_discovery_service.dart` lines 1109-1117

**Problem:** Brace-counting logic to detect complete JSON doesn't handle braces inside strings:
```dart
for (final char in jsonStr.codeUnits) {
  if (char == 123) openBraces++; // '{'
  if (char == 125) closeBraces++; // '}'
}
```

If blog response contains `{"content": "{something}"}` or HTML with curly braces, this causes premature/incorrect parsing.

**Fix:** Replace brace counting with try-catch JSON parsing:
```dart
try {
  final response = json.decode(jsonStr) as Map<String, dynamic>;
  _receiveBuffer.clear();
  // Continue with handling...
} on FormatException {
  // JSON incomplete, wait for more chunks
  return;
}
```

### Critical Files for This Fix

1. `lib/services/ble_discovery_service.dart` - Fix `_handleNotification()` JSON parsing
2. `lib/connection/transports/ble_transport.dart` - Verify `_handleClientNotification()` receives messages
3. `lib/connection/connection_manager.dart` - Review response encoding

### Verification for Remote Apps Fix

1. On Tank2, go to Devices panel
2. Click on C61 (X1L3W3)
3. Blog app should show with 1 post
4. Should be able to open and read the blog post

### Debug Logging Added

Key log messages to look for:
- `DevicesService: [API] makeDeviceApiRequest` - Request initiated
- `DevicesService: [API] Available transports:` - Shows which transports will be tried
- `BleTransport: [API-REQ] START` - BLE transport handling request
- `BleTransport: [API-REQ] sendChatToCallsign returned:` - Send success/failure
- `BLEDiscovery: [NOTIF] Complete JSON:` - Notification received and parsed
- `BleTransport: [STREAM] Received message from incomingChatsFromClient` - Message reached transport
- `BleTransport: Completed pending API request` - Request successfully completed
