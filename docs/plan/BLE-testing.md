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
