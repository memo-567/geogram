# BlueZ-Backed BLE Peripheral Plan (Linux Desktop)

Goal: Enable Geogram on Linux desktops to advertise and host GATT (FFE0/FFF1/FFF2/FFF3) so phones can reach the laptop over BLE. This avoids relying on mobile-only plugins and removes the current placeholder.

## Constraints & Requirements
- Must work offline (no package downloads at runtime).
- Use BlueZ (system bluetoothd) via D-Bus; do not require additional system services beyond bluez.
- Keep Android/iOS BLE unchanged.
- Maintain scanning via flutter_blue_plus (already works on Linux).
- Export the existing protocol:
  - Service UUID: 0xFFE0 (changed from 0xFFF0 to avoid conflict with Android's PKOC)
  - Write characteristic: 0xFFF1 (JSON writes)
  - Notify characteristic: 0xFFF2 (JSON notifications)
  - Status characteristic: 0xFFF3 (ready/clients)

## Phased Implementation (testable steps)

### Phase 1: Minimal BlueZ Advert + GATT Skeleton (smoke test)
- Deliverable: Laptop advertises 0xFFE0, GATT service shows up in `bluetoothctl` (`menu gatt` / `list-attributes`), phones can see the service.
- Approach: Use BlueZ D-Bus directly (package:dbus) or a small bundled helper binary that registers LEAdvertisement1 + GattManager1.
- Tasks:
  1. Add a BlueZ helper (option A: Dart/dbus; option B: bundled native helper). Option B is safer for timing; Option A keeps everything Dart.
  2. Register LE advertisement with service UUID 0xFFE0.
  3. Register GATT application with FFE0 + dummy read/notify/write handlers.
  4. Add logging of adapter state, registration success/failure.
- Tests:
  - `bluetoothctl info` shows advertising service UUID 0xFFE0.
  - `bluetoothctl` on another device sees the service (no data yet).

### Phase 2: Wire Protocol Handlers (FFF1/FFF2/FFF3)
- Deliverable: Writes on FFF1 arrive in Geogram; notifications on FFF2 carry responses; FFF3 reports ready/clients.
- Tasks:
  1. Hook FFF1 WriteValue → `_handleIncomingMessage` (existing BLEMessageService handler).
  2. Hook responses/notifications to FFF2 (JSON), chunk if needed.
  3. FFF3 ReadValue returns `{status: "ready", clients: <count>}`.
- Tests:
  - Use `bluetoothctl` or a phone BLE scanner to write JSON to FFF1 and see responses on FFF2.
  - Verify existing debug API can route messages via BLE on Linux.

### Phase 3: Integrate with App Lifecycle
- Deliverable: Linux build starts/stops advertising with the app and reflects adapter state in UI/logs.
- Tasks:
  1. Start BlueZ peripheral on app launch (Linux only), stop on exit.
  2. Surface adapter/advertising status in logs (and optionally in UI badge).
  3. Handle errors gracefully (bluetoothd not running, permissions, no adapter) without crashing.
- Tests:
  - Start app: logs show advertising success or clear diagnostic error.
  - Kill app: advertisement/GATT unregisters cleanly.

### Phase 4: Hardening
- Deliverable: Robust on common desktop setups.
- Tasks:
  1. Check user in `bluetooth` group; log actionable hints if not.
  2. Power on adapter if powered off (via D-Bus property if permitted).
  3. Timeouts/retries on register/unregister.
  4. Optional: capability bit to disable advertising if bluez missing.
- Tests:
  - Simulate missing bluetoothd → logs an actionable message, app continues.
  - Simulate adapter off → attempt to power on; log result.

## Option A vs B
- **Option A (all Dart/dbus):** Keep dependencies simple, but requires precise mapping of BlueZ D-Bus APIs. More dev time/risk.
- **Option B (bundled helper binary):** Use a small native helper (e.g., built from BlueZ `gatt-server` example or a minimal Go/Rust tool) that we ship and spawn. Lower risk for BlueZ interoperability; slightly more packaging complexity.

## Recommended Path (guaranteed sooner)
1. Start with Option B: bundle a tiny helper that registers the service/characteristics and proxies stdin/stdout to Geogram for FFF1/FFF2 payloads. Proven pattern; avoids dbus API quirks in Dart.
2. Keep Option A as long-term refactor if we want pure Dart later.

## Progress (Option A)

### Phase 1 (Complete)
- Implemented a first-pass BlueZ D-Bus peripheral in Dart (`lib/services/ble_linux_peripheral.dart`): LEAdvertisement1 (FFE0), GATT service/characteristics (FFF1 write → `_handleIncomingMessage`, FFF2 notify, FFF3 status) with ObjectManager/Properties wiring, Notifying updates, and clean unregister. Linux build (`flutter build linux --release`) passes.

### Phase 2 (Complete)
Implemented wire protocol handlers and error handling:

1. **Error handling & graceful degradation**:
   - Added `_advertisingRegistered` and `_gattRegistered` state tracking
   - Added `isFullyOperational` and `isPartialMode` getters
   - Added `_logRegistrationError()` that parses D-Bus errors and logs actionable hints:
     - `NotReady` → "Check: systemctl status bluetooth"
     - `NotPermitted/AccessDenied` → "sudo usermod -aG bluetooth $USER"
     - `AlreadyExists` → Treated as success
     - `DoesNotExist` → "Check: hciconfig"
     - `InvalidLength` → "Try shorter callsign"
   - Added `_logGenericHints()` for troubleshooting checklist
   - App continues in scan-only mode if both registrations fail

2. **Adapter power check**:
   - Added `_ensureAdapterPowered()` that checks `org.bluez.Adapter1.Powered` property
   - Attempts to power on adapter if off, with 500ms delay for initialization

3. **Receive buffer for chunked writes (FFF1)**:
   - Added `_receiveBuffers` and `_lastReceiveTime` maps per device
   - Accumulates bytes until valid JSON parses successfully
   - 10-second timeout for stale partial messages
   - Cleanup of stale buffers on each write

4. **Device ID extraction from D-Bus options**:
   - Parses WriteValue options dict for `device` key
   - Extracts MAC address from D-Bus object path (e.g., `/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF` → `AA:BB:CC:DD:EE:FF`)
   - Falls back to `linux-peer` if extraction fails

5. **Chunked notifications (FFF2)**:
   - Added `_maxChunkSize = 480` (matches Android/iOS pattern)
   - Messages > 480 bytes split into chunks with 50ms delay between
   - Logs chunk count for debugging

6. **Async sendNotification**:
   - Updated `sendNotification()` to await the now-async `notify()` method

### Phase 3 (In Progress - 2026-01-19)

**Runtime Validation Results:**

1. **Advertisement Registration: ✅ WORKING**
   - `ActiveInstances = 1` confirmed via D-Bus query
   - Adapter alias set to callsign (e.g., "X14YN5")
   - Device visible on BLE scanner apps (nRF Connect)

2. **GATT Registration: ✅ WORKING**
   - Service UUID FFE0 listed in `bluetoothctl show`
   - Characteristics FFF1/FFF2/FFF3 registered

3. **ServiceData Advertisement: ✅ WORKING**
   - Using `a{sv}` format (dict string → variant)
   - Contains: `{ "0000ffe0-...": [0x3E, deviceId_hi, deviceId_lo, callsign...] }`
   - Geogram marker 0x3E correctly included

4. **Android Discovery: ⚠️ PARTIAL**
   - Some Android devices discover the Linux laptop ✓
   - Other Android devices don't see it ✗
   - This appears to be device-specific behavior, not a code issue
   - Possible causes: BLE caching, Bluetooth stack differences, scan timing

**Test Instance:**
```bash
# Persistent test instance (keeps same callsign)
./build/linux/x64/release/bundle/geogram --port=5599 --data-dir=/tmp/geogram-ble-test9 --debug-api

# Current test callsign: X14YN5
```

**Verification Commands:**
```bash
# Check advertisement is registered
dbus-send --system --dest=org.bluez --print-reply /org/bluez/hci0 \
  org.freedesktop.DBus.Properties.Get \
  string:"org.bluez.LEAdvertisingManager1" string:"ActiveInstances"
# Expected: variant byte 1

# Check adapter alias
dbus-send --system --dest=org.bluez --print-reply /org/bluez/hci0 \
  org.freedesktop.DBus.Properties.Get \
  string:"org.bluez.Adapter1" string:"Alias"
# Expected: variant string "X14YN5"

# Check full adapter status
echo "show" | bluetoothctl
# Look for: Powered: yes, Discoverable: yes, UUID: 0000ffe0-...
```

**Open Issues:**
- Investigate why some Android devices don't discover the Linux laptop
- May need to test with different Android versions / Bluetooth stacks
- Consider adding ManufacturerData as fallback (in addition to ServiceData)

### Next: Phase 4 (Hardening)
- Test GATT communication (FFF1 write, FFF2 notify)
- Test with multiple Android devices to understand discovery variance
- Add ManufacturerData as backup discovery method if ServiceData inconsistent

## Acceptance Criteria
- Linux build runs: laptop advertises 0xFFE0; phones can see/connect.
- FFF1 writes deliver to Geogram `_handleIncomingMessage`; FFF2 notifications carry responses.
- App does not crash if bluetoothd/adapter is missing; logs actionable hints.

## Option A (Pure Dart/dbus) - Detailed Steps

Objective: Implement LEAdvertisement1 + GattManager1 in Dart using `package:dbus` so the Linux desktop advertises and serves GATT without external helpers.

### Prereqs
- bluez/bluetoothd running (`systemctl is-active bluetooth`).
- User in `bluetooth` group (or permissions to access DBus BlueZ interfaces).
- Adapter present at `/org/bluez/hci0` (or detect first adapter dynamically).

### Step-by-Step
1) **DBus objects**
   - Implement DBusObject subclasses for:
     - Advertisement: LEAdvertisement1 with properties Type=peripheral, ServiceUUIDs=[FFE0], LocalName=callsign; method Release.
     - Application root: ObjectManager implementation (or minimal stub if not needed).
     - Service: GattService1 (UUID=FFE0, Primary=true).
     - Characteristics:
       - FFF1 write: GattCharacteristic1 (Flags: write, write-without-response); handle WriteValue → feed bytes to `_handleIncomingMessage`.
       - FFF2 notify: GattCharacteristic1 (Flags: notify); implement StartNotify/StopNotify; use emitPropertiesChanged with Value to push notifications.
       - FFF3 status: GattCharacteristic1 (Flags: read); handle ReadValue to return JSON status (ready/clients).
   - Ensure introspect(), getProperty(), handleMethodCall() match `dbus` signatures: constructors use positional args (no const DBusObjectPath in super), WriteValue args are two inputs, ReadValue has one input dict and one output array, emitPropertiesChanged uses changedProperties map.

2) **Registration**
   - Create DBusClient.system().
   - Register advertisement with `org.bluez.LEAdvertisingManager1.RegisterAdvertisement(advertPath, {})`.
   - Register GATT application with `org.bluez.GattManager1.RegisterApplication(appPath, {})`.
   - Log and fail gracefully if registration throws (bluetoothd missing, adapter off).

3) **Integration hooks**
   - Expose start/stop in `BleLinuxPeripheral` (Linux-only) to call register/unregister.
   - Wire FFF1 handler to `_handleIncomingMessage` and FFF2 notifications to send responses (chunk if > MTU; start with single-chunk).
   - Return status on FFF3 read: `{"status":"ready","clients":<count>}`.

4) **Adapter/permission checks**
   - Log `systemctl is-active bluetooth` result and `hciconfig` adapters.
   - If adapter is powered off, attempt to set `org.bluez.Adapter1.Powered = true` via DBus (ignore errors).
   - If RegisterAdvertisement fails with permission, log actionable message.

5) **Unregister/cleanup**
   - On stop/dispose, call UnregisterApplication and UnregisterAdvertisement; ignore errors but log.
   - Close DBusClient.

6) **Testing**
   - `bluetoothctl` on another device: `scan on` → see FFE0 in service data.
   - `bluetoothctl` → `menu gatt` → `list-attributes` shows service/characteristics.
   - Write JSON to FFF1 (from phone BLE scanner) and observe response on FFF2.

### Notes
- Keep Android/iOS paths untouched.
- If dbus API evolves, prefer Option B helper to avoid blocking builds.

## Step 2 Plan (Wire Protocol + Validate)
- Validate runtime:
  - Start app on Linux; confirm logs: "advertisement registered", "GATT application registered".
  - From another device or `bluetoothctl`: `scan on` → see FFE0; `menu gatt` → `list-attributes` shows FFE0/FFF1/FFF2/FFF3.
  - Write JSON to FFF1; observe that `_handleIncomingMessage` is called and notifications emitted on FFF2; FFF3 read returns status.
- Code tasks:
  - Ensure FFF1 handler invokes existing message path and captures responses for notify.
  - Implement chunking if payloads exceed BLE MTU (start with single-chunk, add size guard/logs).
  - Keep status FFF3 returning `{status:"ready", clients:<count>}`.
- Error handling:
  - If registration fails, log actionable hints (bluetoothd status, permissions, adapter power).
  - Don’t crash; continue in scan-only mode if needed.
