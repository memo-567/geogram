# Flasher Format Specification

**Version**: 1.0
**Last Updated**: 2026-01-24
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Device Definition Format](#device-definition-format)
- [Protocol Plugins](#protocol-plugins)
- [Serial Port Abstraction](#serial-port-abstraction)
- [USB VID/PID Reference](#usb-vidpid-reference)
- [Flashing Workflow](#flashing-workflow)
- [Complete Examples](#complete-examples)
- [Validation Rules](#validation-rules)
- [Security Considerations](#security-considerations)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

This document specifies the format used for the Flasher app in the Geogram system. The Flasher provides a cross-platform solution for flashing firmware to ESP32 and other USB-connected devices from Geogram desktop, CLI, and Android platforms without external drivers.

### Key Features

- **Pure Dart Implementation**: Single codebase for all platforms
- **Protocol Plugins**: Separate protocol classes per device family
- **Platform-Specific Serial Ports**: Desktop (libserialport), Android (usb_serial)
- **Device Definitions**: JSON-based device configuration with translations
- **USB Auto-Detection**: Automatic device matching via VID/PID

### Supported Platforms

| Platform | Serial Backend | Status |
|----------|---------------|--------|
| Linux Desktop | libserialport (FFI) | Planned |
| Windows Desktop | libserialport (FFI) | Planned |
| macOS Desktop | libserialport (FFI) | Planned |
| Android | usb_serial package | Planned |
| CLI | libserialport (FFI) | Planned |

### Supported Device Families

| Family | Protocol | Chips |
|--------|----------|-------|
| ESP32 | esptool | ESP32, ESP32-C3, ESP32-S2, ESP32-S3 |
| Quansheng | quansheng | UV-K5, UV-K6 |

## File Organization

### Directory Structure

Device definitions are organized by family with a flat structure:

```
flasher/
├── metadata.json                    # Collection metadata
├── esp32/                           # ESP32 device family
│   ├── esp32-c3-mini.json          # Device definition
│   ├── esp32-s3-epaper.json
│   └── media/
│       ├── esp32-c3-mini.jpg       # Device photos
│       └── esp32-s3-epaper.jpg
├── quansheng/                       # Quansheng radios
│   ├── uv-k5.json
│   └── media/
│       └── uv-k5.jpg
└── extra/
    └── security.json               # Security metadata
```

### Folder Naming Convention

**Pattern**: `{device-family}/`

- Lowercase
- Alphanumeric with hyphens
- Matches device family identifier

**Examples**:
```
esp32/
quansheng/
stm32/
nrf52/
```

### Device File Naming Convention

**Pattern**: `{device-id}.json`

**Sanitization Rules**:
1. Convert to lowercase
2. Replace spaces with hyphens
3. Remove special characters (except hyphens)
4. Must be unique within the family folder

**Examples**:
```
esp32-c3-mini.json
esp32-s3-epaper.json
uv-k5.json
```

## Device Definition Format

### Complete Device Definition Schema

```json
{
  "id": "esp32-c3-mini",
  "family": "esp32",
  "chip": "ESP32-C3",
  "title": "ESP32-C3-mini",
  "description": "Compact ESP32-C3 development board with WiFi and BLE support",
  "translations": {
    "pt": {
      "description": "Placa de desenvolvimento ESP32-C3 compacta com suporte WiFi e BLE"
    },
    "es": {
      "description": "Placa de desarrollo ESP32-C3 compacta con soporte WiFi y BLE"
    }
  },
  "media": {
    "photo": "esp32-c3-mini.jpg",
    "photo_hash": "a1b2c3d4e5f6..."
  },
  "links": {
    "documentation": "https://docs.espressif.com/...",
    "datasheet": "https://www.espressif.com/...",
    "purchase": [
      {
        "vendor": "AliExpress",
        "url": "https://aliexpress.com/..."
      },
      {
        "vendor": "Amazon",
        "url": "https://amazon.com/..."
      }
    ]
  },
  "flash": {
    "protocol": "esptool",
    "baud_rate": 115200,
    "flash_mode": "dio",
    "flash_freq": "40m",
    "flash_size": "4MB",
    "partitions": "default",
    "firmware_asset": "geogram-esp32-c3-mini.bin",
    "firmware_url": "https://github.com/geograms/geogram/releases/latest/download/geogram-esp32-c3-mini.bin"
  },
  "usb": {
    "vid": "0x303A",
    "pid": "0x1001",
    "description": "ESP32-C3 USB Serial"
  },
  "created_at": "2026-01-24T10:00:00Z",
  "modified_at": "2026-01-24T10:00:00Z"
}
```

### Field Descriptions

| Field | Type | Required | Translatable | Description |
|-------|------|----------|--------------|-------------|
| `id` | string | Yes | No | Unique device identifier (slug format) |
| `family` | string | Yes | No | Device family (e.g., "esp32", "quansheng") |
| `chip` | string | Yes | No | Chip model identifier |
| `title` | string | Yes | No | Display title (technical, not translated) |
| `description` | string | Yes | Yes | Device description |
| `translations` | object | No | - | Localized field overrides |
| `media` | object | No | No | Media file references |
| `links` | object | No | No | External URLs |
| `flash` | object | Yes | No | Flashing configuration |
| `usb` | object | No | No | USB identification |
| `created_at` | ISO 8601 | Yes | No | Creation timestamp |
| `modified_at` | ISO 8601 | Yes | No | Last modification timestamp |

### Flash Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `protocol` | string | Yes | Protocol identifier ("esptool", "quansheng") |
| `baud_rate` | integer | No | Serial baud rate (default: 115200) |
| `flash_mode` | string | No | ESP32 flash mode: "qio", "qout", "dio", "dout" |
| `flash_freq` | string | No | ESP32 flash frequency: "40m", "80m" |
| `flash_size` | string | No | Flash size: "2MB", "4MB", "8MB", "16MB" |
| `partitions` | string | No | Partition scheme: "default", "large", "ota" |
| `firmware_asset` | string | No | Firmware filename in releases |
| `firmware_url` | string | No | Direct firmware download URL |
| `boot_delay_ms` | integer | No | Delay after reset before sync (default: 100) |
| `stub_required` | boolean | No | Whether stub loader is required (default: false) |

### USB Identification Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `vid` | string | Yes | Vendor ID (hex format: "0x303A") |
| `pid` | string | Yes | Product ID (hex format: "0x1001") |
| `description` | string | No | Human-readable USB description |

### Translations Object

Only specific fields can be translated. The translations object uses ISO 639-1 language codes:

```json
{
  "translations": {
    "pt": {
      "description": "Portuguese description"
    },
    "es": {
      "description": "Spanish description"
    },
    "zh": {
      "description": "Chinese description"
    }
  }
}
```

**Translatable fields**:
- `description`

**Non-translatable fields** (universal/technical):
- `id`, `family`, `chip`, `title`
- `media` (file references)
- `links` (URLs)
- `flash` (technical parameters)
- `usb` (identifiers)

### Metadata File Schema

The `flasher/metadata.json` file contains collection-level metadata:

```json
{
  "version": "1.0",
  "name": "Geogram Flasher Devices",
  "description": "Device definitions for the Geogram Flasher app",
  "families": [
    {
      "id": "esp32",
      "name": "ESP32",
      "description": "Espressif ESP32 family of microcontrollers",
      "protocol": "esptool"
    },
    {
      "id": "quansheng",
      "name": "Quansheng",
      "description": "Quansheng handheld radios",
      "protocol": "quansheng"
    }
  ],
  "created_at": "2026-01-24T10:00:00Z",
  "modified_at": "2026-01-24T10:00:00Z"
}
```

## Protocol Plugins

### Protocol Architecture

```
+-------------------------------------------------------------+
|              FlashProtocol (abstract)                       |
|  - connect(SerialPort port)                                 |
|  - flash(Uint8List firmware, FlashConfig config)            |
|  - verify()                                                 |
|  - disconnect()                                             |
|  - onProgress: Stream<FlashProgress>                        |
+-------------------------------------------------------------+
                            |
        +-------------------+-------------------+
        v                   v                   v
+---------------+   +---------------+   +---------------+
| EspToolProto  |   | QuanshengProto|   | FutureProto   |
|               |   |               |   |               |
| - SLIP framing|   | - K5 protocol |   | - ...         |
| - Stub loader |   | - EEPROM write|   |               |
| - Flash write |   | - Verify      |   |               |
+---------------+   +---------------+   +---------------+
```

### Protocol Interface

```dart
abstract class FlashProtocol {
  /// Protocol identifier (e.g., "esptool", "quansheng")
  String get protocolId;

  /// Connect to device via serial port
  Future<bool> connect(SerialPort port, {int baudRate = 115200});

  /// Flash firmware to device
  Future<void> flash(
    Uint8List firmware,
    FlashConfig config, {
    void Function(double progress, String message)? onProgress,
  });

  /// Verify flashed firmware
  Future<bool> verify();

  /// Disconnect from device
  Future<void> disconnect();
}
```

### Protocol Registry

```dart
class ProtocolRegistry {
  static final Map<String, FlashProtocol Function()> _protocols = {
    'esptool': () => EspToolProtocol(),
    'quansheng': () => QuanshengProtocol(),
  };

  static FlashProtocol? create(String protocolId) {
    return _protocols[protocolId]?.call();
  }

  static List<String> get availableProtocols => _protocols.keys.toList();
}
```

### ESP32 Protocol (esptool)

The ESP32 ROM bootloader uses SLIP framing:

**SLIP Encoding**:
- Packets start/end with 0xC0
- Escape sequences: 0xC0 -> 0xDB 0xDC, 0xDB -> 0xDB 0xDD

**Command Opcodes**:
| Opcode | Name | Description |
|--------|------|-------------|
| 0x00 | FLASH_BEGIN | Start flash operation |
| 0x01 | FLASH_DATA | Write flash data |
| 0x02 | FLASH_END | End flash operation |
| 0x03 | MEM_BEGIN | Start memory write |
| 0x04 | MEM_END | End memory write |
| 0x05 | MEM_DATA | Write memory data |
| 0x06 | SYNC | Sync with bootloader |
| 0x07 | WRITE_REG | Write register |
| 0x08 | READ_REG | Read register |

**Packet Structure**:
```
+------+------+------+------+---------+------+
| 0xC0 | DIR  | CMD  | SIZE | PAYLOAD | 0xC0 |
+------+------+------+------+---------+------+
```

### ESP32 Flashing Sequence

1. Reset into bootloader (toggle DTR/RTS)
2. Send SYNC commands until response
3. Detect chip type via READ_REG
4. (Optional) Upload stub loader to RAM for faster flashing
5. Erase flash region with FLASH_BEGIN
6. Write firmware in chunks with FLASH_DATA
7. Verify MD5 checksum
8. Reset to run firmware with FLASH_END

## Serial Port Abstraction

### Serial Port Interface

```dart
abstract class SerialPort {
  /// Open port with specified baud rate
  Future<bool> open(String path, int baudRate);

  /// Read bytes from port
  Future<Uint8List> read(int maxBytes, {Duration? timeout});

  /// Write bytes to port
  Future<int> write(Uint8List data);

  /// Close the port
  Future<void> close();

  /// Set DTR (Data Terminal Ready) signal
  void setDTR(bool value);

  /// Set RTS (Request To Send) signal
  void setRTS(bool value);

  /// List available ports
  static Future<List<PortInfo>> listPorts();
}
```

### Platform Backends

```
+-------------------------------------------------------------+
|              SerialPort (abstract)                          |
|  - open(String path, int baudRate)                          |
|  - read(int bytes) -> Future<Uint8List>                     |
|  - write(Uint8List data)                                    |
|  - close()                                                  |
|  - setDTR(bool value), setRTS(bool value)                   |
+-------------------------------------------------------------+
                            |
        +-------------------+-------------------+
        v                   v                   v
+---------------+   +---------------+   +---------------+
| LinuxSerial   |   | AndroidSerial |   | WindowsSerial |
|               |   |               |   |               |
| libserialport |   | usb_serial    |   | libserialport |
| via dart:ffi  |   | package       |   | via dart:ffi  |
+---------------+   +---------------+   +---------------+
```

### Port Information

```dart
class PortInfo {
  final String path;           // /dev/ttyUSB0, COM3
  final String? description;   // "USB Serial Port"
  final int? vid;              // Vendor ID
  final int? pid;              // Product ID
  final String? manufacturer;  // "Espressif"
  final String? product;       // "ESP32-C3"
  final String? serialNumber;  // Unique serial
}
```

## USB VID/PID Reference

### ESP32 Common USB Identifiers

| Chip/Adapter | VID | PID | Description |
|--------------|-----|-----|-------------|
| Espressif Native | 0x303A | 0x1001 | ESP32-S2/S3/C3 native USB |
| CP210x | 0x10C4 | 0xEA60 | Silicon Labs USB-UART |
| CH340 | 0x1A86 | 0x7523 | WCH CH340/CH341 |
| CH9102 | 0x1A86 | 0x55D4 | WCH CH9102 |
| FTDI | 0x0403 | 0x6001 | FTDI FT232 |
| FTDI | 0x0403 | 0x6015 | FTDI FT231X |

### Quansheng Radio Identifiers

| Radio | VID | PID | Description |
|-------|-----|-----|-------------|
| UV-K5 | 0x1A86 | 0x7523 | CH340 USB-UART |

## Flashing Workflow

### User Interface Flow

```
1. Device Selection
   +------------------+
   | Select Device    |
   | +--------------+ |
   | | ESP32-C3-mini| |  <- Device card with photo
   | | ESP32        | |
   | +--------------+ |
   | +--------------+ |
   | | UV-K5        | |
   | | Quansheng    | |
   | +--------------+ |
   +------------------+

2. Port Selection (or auto-detect)
   +------------------+
   | Select Port      |
   | +- /dev/ttyUSB0 -|  <- Matching VID/PID highlighted
   | |   ESP32-C3    | |
   | +--------------+ |
   +------------------+

3. Firmware Selection
   +------------------+
   | Firmware         |
   | ( ) Latest       |  <- Downloads from firmware_url
   | (*) Local file   |  <- User-selected file
   +------------------+

4. Flashing Progress
   +------------------+
   | Flashing...      |
   | [=========>  ]   |  65%
   | Writing sector 5 |
   +------------------+

5. Complete
   +------------------+
   | Flash Complete!  |
   | Device ready     |
   | [Restart Device] |
   +------------------+
```

### Programmatic Workflow

```dart
// 1. Load device definition
final device = await flasherStorage.loadDevice('esp32', 'esp32-c3-mini');

// 2. Create protocol instance
final protocol = ProtocolRegistry.create(device.flash.protocol);

// 3. Find and open serial port
final ports = await SerialPort.listPorts();
final port = ports.firstWhere((p) =>
    p.vid == device.usb.vid && p.pid == device.usb.pid);
await protocol.connect(port.path, baudRate: device.flash.baudRate);

// 4. Download or load firmware
final firmware = await downloadFirmware(device.flash.firmwareUrl);

// 5. Flash with progress
await protocol.flash(firmware, device.flash, onProgress: (progress, message) {
  print('${(progress * 100).toInt()}% - $message');
});

// 6. Verify and disconnect
final verified = await protocol.verify();
await protocol.disconnect();
```

## Complete Examples

### Example 1: ESP32-C3-mini Device Definition

**File**: `flasher/esp32/esp32-c3-mini.json`

```json
{
  "id": "esp32-c3-mini",
  "family": "esp32",
  "chip": "ESP32-C3",
  "title": "ESP32-C3-mini",
  "description": "Compact ESP32-C3 development board with WiFi and BLE support. Features USB-C connector and onboard antenna.",
  "translations": {
    "pt": {
      "description": "Placa de desenvolvimento ESP32-C3 compacta com suporte WiFi e BLE. Possui conector USB-C e antena integrada."
    }
  },
  "media": {
    "photo": "esp32-c3-mini.jpg"
  },
  "links": {
    "documentation": "https://docs.espressif.com/projects/esp-idf/en/latest/esp32c3/",
    "datasheet": "https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf"
  },
  "flash": {
    "protocol": "esptool",
    "baud_rate": 460800,
    "flash_mode": "dio",
    "flash_freq": "80m",
    "flash_size": "4MB",
    "firmware_url": "https://github.com/geograms/geogram/releases/latest/download/geogram-esp32-c3.bin"
  },
  "usb": {
    "vid": "0x303A",
    "pid": "0x1001",
    "description": "ESP32-C3 USB JTAG/serial debug unit"
  },
  "created_at": "2026-01-24T10:00:00Z",
  "modified_at": "2026-01-24T10:00:00Z"
}
```

### Example 2: Quansheng UV-K5 Device Definition

**File**: `flasher/quansheng/uv-k5.json`

```json
{
  "id": "uv-k5",
  "family": "quansheng",
  "chip": "BK4819",
  "title": "Quansheng UV-K5",
  "description": "Handheld dual-band radio with open firmware support. Flash custom firmware for extended features.",
  "translations": {
    "pt": {
      "description": "Radio portatil dual-band com suporte a firmware aberto. Instale firmware personalizado para recursos extras."
    }
  },
  "media": {
    "photo": "uv-k5.jpg"
  },
  "links": {
    "documentation": "https://github.com/egzumer/uv-k5-firmware-custom",
    "purchase": [
      {
        "vendor": "AliExpress",
        "url": "https://www.aliexpress.com/item/uv-k5"
      }
    ]
  },
  "flash": {
    "protocol": "quansheng",
    "baud_rate": 38400,
    "firmware_url": "https://github.com/egzumer/uv-k5-firmware-custom/releases/latest/download/firmware.bin"
  },
  "usb": {
    "vid": "0x1A86",
    "pid": "0x7523",
    "description": "CH340 USB Serial"
  },
  "created_at": "2026-01-24T10:00:00Z",
  "modified_at": "2026-01-24T10:00:00Z"
}
```

### Example 3: Metadata File

**File**: `flasher/metadata.json`

```json
{
  "version": "1.0",
  "name": "Geogram Flasher Devices",
  "description": "Device definitions for the Geogram Flasher app",
  "families": [
    {
      "id": "esp32",
      "name": "ESP32",
      "description": "Espressif ESP32 family of microcontrollers",
      "protocol": "esptool"
    },
    {
      "id": "quansheng",
      "name": "Quansheng",
      "description": "Quansheng handheld radios",
      "protocol": "quansheng"
    }
  ],
  "created_at": "2026-01-24T10:00:00Z",
  "modified_at": "2026-01-24T10:00:00Z"
}
```

## Validation Rules

### Device Definition Validation

- `id` must be unique within the family
- `id` must match filename (without .json extension)
- `family` must match parent folder name
- `flash.protocol` must be a registered protocol
- `usb.vid` and `usb.pid` must be valid hex strings
- ISO 8601 timestamps must be valid

### Flash Configuration Validation

- `baud_rate` must be a valid baud rate (9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600)
- `flash_mode` for ESP32 must be one of: "qio", "qout", "dio", "dout"
- `flash_freq` for ESP32 must be one of: "40m", "80m"
- `flash_size` must be valid size string

### Media Validation

- Photo files must exist in `media/` subfolder
- Supported formats: JPG, PNG, WebP
- Recommended size: 400x300 pixels
- Max file size: 500 KB

## Security Considerations

### Firmware Verification

- Verify firmware downloads via HTTPS
- Support SHA256 checksums in device definitions
- Warn users when flashing unsigned firmware

### USB Access

- Request only necessary USB permissions on Android
- Release USB devices when not in use
- Handle USB disconnect gracefully during flash

### Device Safety

- Implement proper reset sequences
- Avoid bricking by verifying bootloader presence
- Provide recovery instructions for failed flashes

## Related Documentation

- [Reader Format Specification](reader-format-specification.md) - Similar JSON metadata patterns
- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/) - ESP32 flashing details
- [esptool.py Source](https://github.com/espressif/esptool) - Reference implementation

## Change Log

### Version 1.0 (2026-01-24)

- Initial specification
- Pure Dart implementation with protocol plugins
- ESP32 and Quansheng protocol support
- Device definition JSON format
- Serial port abstraction for desktop and Android
- USB VID/PID auto-detection
