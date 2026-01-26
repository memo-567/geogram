# Geogram USB AOA Zero-Config Communication

## Context

Geogram needs to enable devices running Geogram to communicate over USB without any user configuration. Standard USB tethering/RNDIS requires manual user setup, which violates Geogram's zero-config philosophy.

## Solution: Android Open Accessory Protocol (AOA)

AOA enables true zero-config USB communication. It works automatically without user intervention.

### Supported Platforms

| Platform | Role | Implementation |
|----------|------|----------------|
| Android | Accessory (receives connection) | `UsbAoaPlugin.kt` via MethodChannel |
| Linux | Host (initiates connection) | `usb_aoa_linux.dart` via libc FFI |

### How It Works

```
Host Device (Linux/Android OTG)         Android Accessory
        │                                     │
    Geogram                               Geogram
        │                                     │
   detects USB ──────────────────────────► receives AOA
   connection                              handshake
        │                                     │
   sends AOA control ◄───────────────────► Android switches
   transfers                               to accessory mode
        │                                     │
   bulk endpoint ◄═══════════════════════► bulk endpoint
   read/write                              read/write
```

### Linux Host Mode (New)

```
Linux Host                               Android Accessory
       │                                        │
  Dart FFI + libc                        UsbAoaPlugin.kt
  (usbdevfs ioctl)                              │
       │                                        │
  Enumerate /sys/bus/usb ──────────────────► Normal mode
       │
  Open /dev/bus/usb/XXX/YYY
       │
  ioctl(USBDEVFS_CONTROL):
   - GET_PROTOCOL (51) ────────────────────► Check AOA support
   - SEND_STRING (52) x6 ──────────────────► Send ID strings
   - START (53) ───────────────────────────► Re-enumerate
       │                                        │
  Watch for VID:0x18D1 ◄────────────────── Device re-enumerates
  PID:0x2D00/0x2D01                         as Google AOA
       │                                        │
  ioctl(USBDEVFS_BULK) ◄═════════════════► accessory_filter.xml
  IN/OUT transfer                            matches & connects
```

### Role Assignment

| Scenario | Result |
|----------|--------|
| Phone A (OTG) plugs into Phone B | A becomes host, B becomes accessory |
| Phone B (no OTG) plugs into Phone A (OTG) | A becomes host |
| Both have OTG | First to enumerate becomes host |
| Neither has OTG | Won't work - need at least one OTG-capable device |

## Implementation

### AndroidManifest.xml

```xml
<!-- Accessory mode intent filter -->
<activity android:name=".MainActivity">
    <intent-filter>
        <action android:name="android.hardware.usb.action.USB_ACCESSORY_ATTACHED"/>
    </intent-filter>
    <meta-data
        android:name="android.hardware.usb.action.USB_ACCESSORY_ATTACHED"
        android:resource="@xml/accessory_filter"/>
</activity>

<!-- Host mode permission -->
<uses-feature android:name="android.hardware.usb.host" android:required="false"/>
```

### res/xml/accessory_filter.xml

```xml
<resources>
    <usb-accessory
        manufacturer="Geogram"
        model="MeshLink"
        version="1.0"/>
</resources>
```

### Host-Side Kotlin (Device with OTG)

```kotlin
class UsbAoaHost(private val context: Context) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    
    // AOA protocol constants
    private val AOA_GET_PROTOCOL = 51
    private val AOA_SEND_STRING = 52
    private val AOA_START = 53
    
    fun tryConnectAsAccessoryHost(device: UsbDevice): UsbDeviceConnection? {
        val connection = usbManager.openDevice(device) ?: return null
        
        // Check if device supports AOA
        val protocol = getAoaProtocol(connection)
        if (protocol < 1) {
            connection.close()
            return null
        }
        
        // Send accessory identification strings
        sendAoaString(connection, 0, "Geogram")           // manufacturer
        sendAoaString(connection, 1, "MeshLink")          // model
        sendAoaString(connection, 2, "Mesh USB Link")     // description
        sendAoaString(connection, 3, "1.0")               // version
        sendAoaString(connection, 4, "https://geogram.app") // uri
        sendAoaString(connection, 5, "geogram-${device.serialNumber}") // serial
        
        // Start accessory mode - device will re-enumerate
        connection.controlTransfer(0x40, AOA_START, 0, 0, null, 0, 1000)
        connection.close()
        
        // Device re-enumerates with new VID/PID, reconnect via broadcast receiver
        return null
    }
    
    private fun getAoaProtocol(conn: UsbDeviceConnection): Int {
        val buffer = ByteArray(2)
        val result = conn.controlTransfer(0xC0, AOA_GET_PROTOCOL, 0, 0, buffer, 2, 1000)
        return if (result == 2) buffer[0].toInt() or (buffer[1].toInt() shl 8) else 0
    }
    
    private fun sendAoaString(conn: UsbDeviceConnection, index: Int, str: String) {
        val bytes = str.toByteArray(Charsets.UTF_8)
        conn.controlTransfer(0x40, AOA_SEND_STRING, 0, index, bytes, bytes.size, 1000)
    }
}
```

### Bulk Transfer Channel (Both Sides)

```kotlin
class UsbMeshChannel(
    private val connection: UsbDeviceConnection, 
    private val epIn: UsbEndpoint, 
    private val epOut: UsbEndpoint
) {
    private val buffer = ByteArray(16384)
    
    fun send(data: ByteArray): Int {
        return connection.bulkTransfer(epOut, data, data.size, 1000)
    }
    
    fun receive(): ByteArray? {
        val length = connection.bulkTransfer(epIn, buffer, buffer.size, 1000)
        return if (length > 0) buffer.copyOf(length) else null
    }
}
```

### Dart Platform Channel Bridge

```dart
class UsbMeshTransport {
  static const _channel = MethodChannel('geogram/usb_mesh');
  static const _dataChannel = EventChannel('geogram/usb_mesh_data');
  
  Stream<Uint8List> get incomingData => 
      _dataChannel.receiveBroadcastStream().map((d) => d as Uint8List);
  
  Future<bool> send(Uint8List data) async {
    return await _channel.invokeMethod('send', data);
  }
  
  Future<bool> get isConnected async {
    return await _channel.invokeMethod('isConnected');
  }
}
```

## Key Points

- **Zero-config**: Host probes with AOA handshake, accessory side registers intent filter - Android handles the rest automatically
- **Speed**: USB 2.0 High-Speed gives ~30-40 MB/s practical throughput
- **Protocol**: Once connected, you get a bidirectional byte stream - run existing NOSTR/mesh protocols directly over it
- **Limitation**: Requires at least one device with USB OTG capability

## Implementation Status

**Android Accessory Mode (Completed):**

1. &#x2713; Created accessory filter XML (`android/app/src/main/res/xml/accessory_filter.xml`)
2. &#x2713; Updated AndroidManifest.xml with USB accessory feature and intent filter
3. &#x2713; Created native Kotlin plugin (`UsbAoaPlugin.kt`)
4. &#x2713; Integrated with MainActivity for intent handling
5. &#x2713; Created Dart service layer (`lib/services/usb_aoa_service.dart`)
6. &#x2713; Created transport implementation (`lib/connection/transports/usb_aoa_transport.dart`)
7. &#x2713; Added USB connection method label and color in UI
8. &#x2713; Registered transport in main.dart with priority 5 (highest)

**Linux Host Mode (Completed):**

1. &#x2713; Created pure Dart FFI implementation (`lib/services/usb_aoa_linux.dart`)
2. &#x2713; Device enumeration via `/sys/bus/usb/devices/`
3. &#x2713; AOA handshake (GET_PROTOCOL, SEND_STRING, START)
4. &#x2713; Bulk transfer I/O via `USBDEVFS_BULK` ioctl
5. &#x2713; Updated `usb_aoa_service.dart` with Linux integration
6. &#x2713; Updated `usb_aoa_transport.dart` with Linux support
7. &#x2713; No external dependencies (uses libc + kernel APIs only)

## Files Created/Modified

| File | Status | Platform |
|------|--------|----------|
| `android/app/src/main/res/xml/accessory_filter.xml` | Created | Android |
| `android/app/src/main/AndroidManifest.xml` | Modified | Android |
| `android/app/src/main/kotlin/dev/geogram/UsbAoaPlugin.kt` | Created | Android |
| `android/app/src/main/kotlin/dev/geogram/MainActivity.kt` | Modified | Android |
| `lib/services/usb_aoa_linux.dart` | Created | Linux |
| `lib/services/usb_aoa_service.dart` | Created/Modified | Cross-platform |
| `lib/connection/transports/usb_aoa_transport.dart` | Created/Modified | Cross-platform |
| `lib/models/device_source.dart` | Modified | Cross-platform |
| `lib/services/devices_service.dart` | Modified | Cross-platform |
| `lib/pages/devices_browser_page.dart` | Modified | Cross-platform |
| `lib/main.dart` | Modified | Cross-platform |

## Message Protocol

JSON envelope format over USB (same as BLE):
```json
{
  "channel": "_api|_api_response|_dm|_system|<room_id>",
  "content": "<message JSON>",
  "timestamp": 1706000000000
}
```

Messages are length-prefixed (4 bytes big-endian) for reliable framing.

## Testing

### Android-to-Android

1. Connect two Android phones via USB-C OTG cable
2. Verify both devices launch Geogram (or one shows permission dialog)
3. Verify connected device appears in Devices panel with "USB" label (orange tag)
4. Send a direct message between devices
5. Verify message delivery uses USB transport (check logs)
6. Disconnect cable and verify device goes offline/removes USB tag

### Linux-to-Android

1. Build Geogram for Linux: `flutter build linux`
2. Connect Android phone (with Geogram running) via USB to Linux
3. Linux initiates AOA handshake → Android shows permission dialog
4. Accept → device appears in Devices panel with "USB" tag (orange)
5. Send DM between devices
6. Check logs for `UsbAoaTransport:` and `UsbAoaLinux:` messages
7. Disconnect cable → device goes offline

### Linux Permissions

If you get `errno=13 (EACCES)`, you need udev rules:

```bash
# Create udev rule for Android devices
sudo tee /etc/udev/rules.d/51-android.rules << 'EOF'
# Google (AOA mode)
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
# Samsung
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"
# Add other vendors as needed...
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Or run Geogram with sudo for testing.

## Future Enhancements

- ~~Add host-side AOA handshake for initiating connections~~ ✓ Done (Linux)
- Implement automatic callsign exchange on USB connect
- Add USB connection status indicator in the UI
- Support USB connection persistence across app restarts
- Add macOS host support (IOKit FFI)
- Add Windows host support (WinUSB FFI)
