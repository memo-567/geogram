# USB AOA Linux Host - Technical Documentation

This document provides detailed technical information about the Linux USB AOA host implementation in Geogram.

## Overview

The Linux implementation enables Geogram running on a Linux desktop/laptop to act as a USB host and initiate AOA connections to Android devices. It uses pure Dart FFI with libc and kernel usbdevfs APIs - no external dependencies like libusb are required.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Dart Application                         │
├─────────────────────────────────────────────────────────────────┤
│  UsbAoaTransport                                                 │
│  └── UsbAoaService                                               │
│       └── UsbAoaLinux (Linux only)                               │
├─────────────────────────────────────────────────────────────────┤
│                         Dart FFI Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │    open()    │  │   ioctl()    │  │    poll()    │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
├─────────────────────────────────────────────────────────────────┤
│                           libc.so.6                              │
├─────────────────────────────────────────────────────────────────┤
│                         Linux Kernel                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      usbdevfs                             │   │
│  │  /dev/bus/usb/XXX/YYY                                    │   │
│  │  /sys/bus/usb/devices/                                   │   │
│  └──────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│                         USB Hardware                             │
│                              ↓                                   │
│                      Android Device                              │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

| File | Description |
|------|-------------|
| `lib/services/usb_aoa_linux.dart` | Pure Dart FFI implementation (~850 lines) |
| `lib/services/usb_aoa_service.dart` | Cross-platform service layer |
| `lib/connection/transports/usb_aoa_transport.dart` | Transport implementation |

## Key Classes

### UsbAoaLinux

The main Linux implementation class. Handles:
- Device enumeration
- AOA handshake
- Bulk I/O transfers
- Connection management

```dart
class UsbAoaLinux {
  // Connection streams
  Stream<UsbAoaConnectionEvent> get connectionStream;
  Stream<Uint8List> get dataStream;

  // Device management
  Future<List<UsbDeviceInfo>> listDevices();
  Future<bool> connect(UsbDeviceInfo device);
  Future<void> disconnect();

  // Data transfer
  Future<bool> write(Uint8List data);
}
```

### UsbDeviceInfo

Information about a discovered USB device:

```dart
class UsbDeviceInfo {
  final int vid;        // Vendor ID
  final int pid;        // Product ID
  final String devPath; // /dev/bus/usb/XXX/YYY
  final String sysPath; // /sys/bus/usb/devices/X-Y
  final String? manufacturer;
  final String? product;
  final String? serial;

  bool get isAndroidDevice; // Known Android VID
  bool get isAoaDevice;     // Google AOA VID/PID
}
```

## FFI Bindings

### libc Functions Used

| Function | Purpose |
|----------|---------|
| `open()` | Open USB device file |
| `close()` | Close file descriptor |
| `ioctl()` | USB control/bulk transfers |
| `poll()` | Wait for data availability |
| `__errno_location()` | Get errno value |

### USB ioctl Constants

From `linux/usbdevice_fs.h`:

```dart
const USBDEVFS_CONTROL = 0xC0185500;        // Control transfer
const USBDEVFS_BULK = 0xC0185502;           // Bulk transfer
const USBDEVFS_CLAIMINTERFACE = 0x8004550F; // Claim interface
const USBDEVFS_RELEASEINTERFACE = 0x80045510; // Release interface
const USBDEVFS_CLEAR_HALT = 0x80045515;     // Clear endpoint halt/stall
```

### FFI Structures

#### Control Transfer

```dart
final class UsbCtrlTransfer extends Struct {
  @Uint8() external int bRequestType;
  @Uint8() external int bRequest;
  @Uint16() external int wValue;
  @Uint16() external int wIndex;
  @Uint16() external int wLength;
  @Uint32() external int timeout;
  external Pointer<Void> data;
}
```

#### Bulk Transfer

```dart
final class UsbBulkTransfer extends Struct {
  @Uint32() external int ep;      // Endpoint address
  @Uint32() external int len;     // Data length
  @Uint32() external int timeout; // Timeout in ms
  external Pointer<Void> data;    // Data buffer
}
```

## AOA Protocol

### Protocol Flow

```
1. Enumerate devices in /sys/bus/usb/devices/
2. Find Android device (check VID against known list)
3. Open /dev/bus/usb/XXX/YYY
4. GET_PROTOCOL → Check AOA support (version >= 1)
5. SEND_STRING × 6 → Send identification strings
6. START → Device re-enumerates as AOA accessory
7. Wait for device with Google VID (0x18D1) and AOA PID
8. Open new device path
9. Claim interface 0
10. Find bulk endpoints (typically EP1 IN, EP2 OUT)
11. Start read loop
```

### AOA Vendor Requests

| Request | Direction | bRequest | Purpose |
|---------|-----------|----------|---------|
| GET_PROTOCOL | IN (0xC0) | 51 | Get AOA version |
| SEND_STRING | OUT (0x40) | 52 | Send ID string (wIndex = string index) |
| START | OUT (0x40) | 53 | Switch to accessory mode |

### Identification Strings

| Index | Name | Value |
|-------|------|-------|
| 0 | Manufacturer | "Geogram" |
| 1 | Model | "Geogram Device" |
| 2 | Description | "Geogram USB Link" |
| 3 | Version | "1.0" |
| 4 | URI | "https://geogram.dev" |
| 5 | Serial | "geogram-linux" |

### Google AOA VID/PID

After the device switches to AOA mode, it re-enumerates with:

| VID | PID | Description |
|-----|-----|-------------|
| 0x18D1 | 0x2D00 | AOA without ADB |
| 0x18D1 | 0x2D01 | AOA with ADB |

## Device Enumeration

Devices are discovered by scanning `/sys/bus/usb/devices/`:

```dart
Future<List<UsbDeviceInfo>> listDevices() async {
  final sysDir = Directory('/sys/bus/usb/devices');

  for (final entry in sysDir.listSync()) {
    // Skip interface entries (contain ':')
    if (entry.path.contains(':')) continue;

    // Read VID/PID from sysfs
    final vid = readHex('${entry.path}/idVendor');
    final pid = readHex('${entry.path}/idProduct');

    // Build device path
    final busnum = readInt('${entry.path}/busnum');
    final devnum = readInt('${entry.path}/devnum');
    final devPath = '/dev/bus/usb/${busnum.padLeft(3, '0')}/${devnum.padLeft(3, '0')}';
  }
}
```

### Known Android VIDs

```dart
const _androidVids = <int>{
  0x18D1, // Google
  0x04E8, // Samsung
  0x22B8, // Motorola
  0x0BB4, // HTC
  0x12D1, // Huawei
  0x2717, // Xiaomi
  0x1949, // OnePlus
  0x0FCE, // Sony
  0x2A70, // OnePlus (alternate)
  0x05C6, // Qualcomm
  0x1004, // LG
  0x2916, // Realme
  0x2B4C, // Vivo
  0x1782, // Spreadtrum
};
```

## Bulk I/O

### Endpoint Addresses

Standard AOA endpoints on interface 0:

| Endpoint | Address | Direction | Usage |
|----------|---------|-----------|-------|
| EP1 IN   | 0x81    | Device → Host | Read data from Android |
| EP1 OUT  | 0x01    | Host → Device | Write data to Android |

**Note:** In AOA+ADB mode (PID 0x2D01), interface 0 is AOA and interface 1 is ADB. Always use interface 0 for Geogram communication.

### Reading Data

**CRITICAL: `poll()` does not work reliably with USB device file descriptors on Linux.**

When using `/dev/bus/usb/XXX/YYY`, the `poll()` system call may return timeout (0) even when data is available. The workaround is to always try a bulk read with a short timeout when poll times out:

```dart
// Read loop pattern (simplified)
while (isReading && isConnected) {
  // Poll for incoming data
  pollFd.ref.fd = fd;
  pollFd.ref.events = POLLIN;
  final pollResult = poll(pollFd.cast(), 1, 100);

  if (pollResult == 0) {
    // Timeout - but poll() may miss USB data!
    // Try a non-blocking bulk read anyway
    bulk.ref.ep = 0x81;     // EP1 IN
    bulk.ref.len = 16384;   // Buffer size
    bulk.ref.timeout = 50;  // Short timeout for non-blocking check
    bulk.ref.data = buffer.cast();

    final bytesRead = ioctl(fd, USBDEVFS_BULK, bulk.cast());
    if (bytesRead > 0) {
      // Data was available even though poll() didn't report it!
      processData(buffer, bytesRead);
    }
    continue;
  }

  // Handle POLLIN, POLLERR, POLLHUP normally...
  if ((pollFd.ref.revents & POLLIN) != 0) {
    bulk.ref.ep = 0x81;
    bulk.ref.len = 16384;
    bulk.ref.timeout = 1000;
    bulk.ref.data = buffer.cast();
    final bytesRead = ioctl(fd, USBDEVFS_BULK, bulk.cast());
    if (bytesRead > 0) {
      processData(buffer, bytesRead);
    }
  }
}
```

### Clearing Endpoint Stall

Before starting the read loop, clear any stall condition on the IN endpoint:

```dart
final epInPtr = calloc<Uint32>();
epInPtr.value = 0x81; // EP1 IN
ioctl(fd, USBDEVFS_CLEAR_HALT, epInPtr.cast());
calloc.free(epInPtr);
```

### Writing Data

```dart
bulk.ref.ep = 0x01;     // EP1 OUT
bulk.ref.len = data.length;
bulk.ref.timeout = 1000;
bulk.ref.data = dataPtr.cast();

final bytesWritten = ioctl(fd, USBDEVFS_BULK, bulk.cast());
```

## Error Handling

### Common errno Values

| errno | Constant | Meaning |
|-------|----------|---------|
| 4 | EINTR | Interrupted, retry |
| 13 | EACCES | Permission denied (need udev rules) |
| 110 | ETIMEDOUT | Transfer timeout |
| 19 | ENODEV | Device disconnected |

### Permission Issues

If `errno=13`, create udev rules:

```bash
sudo tee /etc/udev/rules.d/51-android.rules << 'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666"
# ... add other vendors
EOF

sudo udevadm control --reload-rules
```

## Integration with UsbAoaService

The service layer (`usb_aoa_service.dart`) abstracts platform differences:

```dart
Future<void> initialize() async {
  if (Platform.isLinux) {
    _linuxImpl = UsbAoaLinux();
    await _linuxImpl!.initialize();

    // Forward connection events
    _linuxImpl!.connectionStream.listen(_handleLinuxConnection);

    // Forward data
    _linuxImpl!.dataStream.listen((data) {
      _dataController.add(data);
    });
  } else if (Platform.isAndroid) {
    // Use MethodChannel for Android
    _channel.setMethodCallHandler(_handleMethodCall);
  }
}
```

## Message Framing

USB provides a raw byte stream. Messages are framed with a 4-byte length prefix:

```
┌────────────────┬──────────────────────────────────┐
│ Length (4 BE)  │ JSON Message                     │
├────────────────┼──────────────────────────────────┤
│ 00 00 00 42    │ {"channel":"_dm","content":...}  │
└────────────────┴──────────────────────────────────┘
```

## Hello Handshake

After the USB AOA connection is established, both sides exchange "hello" messages to identify each other by callsign.

### Protocol Flow

```
Linux (Host)                          Android (Accessory)
     │                                       │
     │──── USB AOA Connection ───────────────│
     │                                       │
     │                    ←── Hello {X1Q22N} │  Android sends hello first
     │                                       │
     │── Hello {X1UEFU} ──→                  │  Linux replies with its callsign
     │                                       │
     │  [Bidirectional communication ready]  │
```

### Hello Message Format

```json
{
  "channel": "_hello",
  "from": "X1UEFU",
  "signature": "..."
}
```

### Callsign Discovery

When a hello is received:
1. `UsbAoaTransport` parses the hello message
2. Extracts the remote callsign from the `from` field
3. Calls `UsbAoaService.setRemoteCallsign(callsign)`
4. `UsbAoaService` publishes to `remoteCallsignStream`
5. `DevicesService` receives the notification and adds/updates the device with `usb` connection method

### Timing Considerations

- Android may send multiple hellos until it receives a reply
- Linux waits 5 seconds after USB connection for Android to open the accessory
- Hello retry interval: ~2 seconds
- DevicesService subscribes to `remoteCallsignStream` for real-time callsign discovery

## Performance

- USB 2.0 High-Speed: ~30-40 MB/s practical throughput
- Buffer size: 16KB (optimal for USB 2.0 HS)
- Poll timeout: 100ms for responsive reads
- Transfer timeout: 1000ms default

## Debugging

All USB AOA components log to `LogService()`. Key log messages to check:

### Connection Establishment

```
UsbAoaLinux: Initialized
UsbAoa: Scanning for Android devices...
UsbAoa: Found 1 device(s)
UsbAoa: Found [Product] (VID:PID)
UsbAoa: Attempting to connect to /dev/bus/usb/XXX/YYY...
UsbAoaLinux: AOA protocol version: 2
UsbAoaLinux: Connected to AOA device (IN=0x81, OUT=0x1)
UsbAoaLinux: Waiting 5s for Android to open accessory...
UsbAoaLinux: Starting read loop
UsbAoaLinux: Cleared halt on IN endpoint
UsbAoa: Connected successfully!
```

### Hello Handshake

```
UsbAoaTransport: Sending hello with callsign X1UEFU
UsbAoaTransport: Hello sent successfully
UsbAoaLinux: Received 88 bytes from USB
UsbAoaLinux: Android connected (data received)
UsbAoaTransport: [RECV] Got 88 bytes from USB
UsbAoa: Remote callsign set to X1Q22N
UsbAoaTransport: Received hello from X1Q22N
DevicesService: USB remote callsign discovered: X1Q22N
DevicesService: Adding USB device: X1Q22N
DevicesService: Added USB to existing device X1Q22N
```

### Error Conditions

```
UsbAoaLinux: Failed to open device, errno=13   # Permission denied
UsbAoaLinux: Poll error, errno=X
UsbAoaLinux: Bulk read error, errno=X
UsbAoaLinux: Waiting for Android to open (POLLERR, attempt N)
UsbAoaLinux: Poll error/hangup after N attempts (POLLERR)
```

## Limitations

1. **Root/udev required**: Need permissions to access USB devices
2. **No hotplug**: Must manually call `listDevices()` to find new devices
3. **Single device**: Only one AOA connection at a time
4. **Re-enumeration delay**: 500ms polling after AOA START command
5. **poll() unreliable**: Must use fallback bulk reads (see Bulk I/O section)

## Android Side (Accessory Mode)

While this document focuses on Linux host mode, the Android accessory implementation is in:

| File | Description |
|------|-------------|
| `android/app/src/main/kotlin/dev/geogram/UsbAoaPlugin.kt` | Native Kotlin plugin |
| `android/app/src/main/res/xml/accessory_filter.xml` | USB accessory filter for intent |
| `android/app/src/main/AndroidManifest.xml` | USB accessory intent declaration |

### Key Android Components

- **UsbManager**: System service for USB accessory access
- **UsbAccessory**: Represents the connected Linux host
- **ParcelFileDescriptor**: File descriptor for reading/writing USB data
- **MethodChannel**: Bridge between Kotlin and Dart

### Android Data Flow

```
USB Data → UsbAoaPlugin (Kotlin) → MethodChannel.invokeMethod("onDataReceived")
         → UsbAoaService (Dart) → _dataController.add(data)
         → UsbAoaTransport → Process message
```

## Future Improvements

- [ ] Add inotify for USB hotplug detection
- [ ] Support multiple simultaneous connections
- [ ] Add USB 3.0 SuperSpeed support
- [ ] macOS port using IOKit FFI
- [ ] Windows port using WinUSB FFI
