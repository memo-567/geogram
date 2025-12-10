# Android-to-Android BLE Test Plan

## Goal
Debug and verify BLE communication between two Android devices connected to a laptop via USB/ADB.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      TEST LAPTOP                            │
│   ┌─────────────────────────────────────────────────────┐   │
│   │     tests/ble_android_android.sh (Orchestrator)     │   │
│   │  - ADB device management                            │   │
│   │  - HTTP API calls to both devices                   │   │
│   │  - Log collection and pattern matching              │   │
│   │  - Test result reporting                            │   │
│   └─────────────────────────────────────────────────────┘   │
│              │ USB/ADB                    │ USB/ADB         │
└──────────────┼────────────────────────────┼─────────────────┘
               ▼                            ▼
     ┌─────────────────┐          ┌─────────────────┐
     │   ANDROID A     │◄──BLE───►│   ANDROID B     │
     │   GATT Server   │          │   GATT Server   │
     │   GATT Client   │          │   GATT Client   │
     │   HTTP :3456    │          │   HTTP :3456    │
     └─────────────────┘          └─────────────────┘
```

## Key APIs Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/status` | GET | Get callsign, version |
| `/api/debug` | POST | Trigger: `ble_scan`, `ble_advertise`, `ble_hello`, `ble_send` |
| `/api/log?filter=BLE` | GET | Get BLE-filtered logs |
| `/api/devices` | GET | Get discovered devices |

## Test Phases

### Phase 1: Setup
1. Detect two Android devices via ADB
2. Get WiFi IP addresses
3. Install APK on both devices
4. Grant BLE permissions
5. Launch apps with `--http-api --debug-api --new-identity --skip-intro`
6. Wait for API to be ready

### Phase 2: Discovery Tests
1. Device B starts advertising (`ble_advertise`)
2. Wait 2s for advertising to stabilize
3. Device A starts scanning (`ble_scan`)
4. Wait 15s for scan to complete
5. Verify B appears in A's device list (`/api/devices`)
6. Verify discovery log pattern: `Found device.*{B_CALLSIGN}`

### Phase 3: HELLO Handshake Tests
1. Device A sends HELLO (`ble_hello`)
2. Wait for log: `HELLO handshake successful` (10s timeout)
3. Verify B's logs show: `HELLO from.*{A_CALLSIGN}`

### Phase 4: Data Transfer Tests
1. Device A sends data (`ble_send` with size=2000)
2. Wait for log: `transfer completed` (30s timeout)
3. Verify B received data via logs

### Phase 5: Bidirectional Tests
Repeat phases 2-4 with roles reversed (A advertises, B scans/sends)

## Success Patterns (Logs)

| Event | Success Pattern | Failure Pattern |
|-------|-----------------|-----------------|
| Advertise | `Started advertising` | `Failed to start` |
| Scan | `Starting BLE scan` | `BLE not available` |
| Discovery | `Found device.*{CALLSIGN}` | (timeout) |
| HELLO | `HELLO handshake successful` | `HELLO error`, `timeout` |
| Data | `transfer completed` | `checksum_failed` |

## Timing Constants

| Operation | Timeout |
|-----------|---------|
| App startup | 30s |
| Advertise delay | 2s |
| BLE scan | 15s |
| HELLO handshake | 10s |
| Data transfer | 30s |

## Debug Output on Failure

When a test fails, dump:
1. Recent BLE logs from both devices
2. `/api/devices` output from scanner
3. `/api/status` from both devices
4. Suggested actions for common errors

## Usage

```bash
./tests/ble_android_android.sh              # Full test
./tests/ble_android_android.sh --skip-install  # Skip APK install
./tests/ble_android_android.sh --verbose    # Show all logs
./tests/ble_android_android.sh --cleanup    # Just cleanup
```

## BLE Protocol Reference

### Service UUIDs
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Write Characteristic: `0000FFF1-...` (client writes HELLO here)
- Notify Characteristic: `0000FFF2-...` (server sends responses)
- Status Characteristic: `0000FFF3-...` (read-only status)

### Message Types
- `hello` - Initial handshake with NOSTR-signed event
- `hello_ack` - Server response with capabilities
- `chat` - Chat message
- `chat_ack` - Acknowledgment

### Data Transfer
- Parcel size: 280 bytes max
- Inter-parcel delay: 500ms
- Uses CRC32 for integrity
