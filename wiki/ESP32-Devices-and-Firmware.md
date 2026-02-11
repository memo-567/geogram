# ESP32 Devices and Firmware

Geogram runs on several ESP32 boards. Each board runs the same station firmware, with features enabled or disabled based on the hardware available.

ESP32 stations serve as **infrastructure nodes** in the Geogram network:

- **Bridge networks** — connect BLE mesh to WiFi/Internet
- **Relay messages** — store-and-forward delivery for offline scenarios
- **Provide local services** — HTTP portal, map tiles, sensor data
- **Act as beacons** — broadcast presence to nearby devices

---

## Status Overview

| Device | Status | WiFi | LoRa | Display | Sensors | SD Card |
|--------|--------|:----:|:----:|:-------:|:-------:|:-------:|
| **ESP32-C3 Mini** | **Ready** | yes | -- | -- | -- | -- |
| Heltec WiFi LoRa 32 V3 | Under development | yes | SX1262 | OLED | -- | -- |
| Heltec WiFi LoRa 32 V2 | Under development | yes | SX1276 | OLED | -- | -- |
| Heltec WiFi LoRa 32 V1 | Under development | yes | SX1276 | OLED | -- | -- |
| ESP32-S3 ePaper 1.54" | Under development | yes | -- | E-Paper | Temp/Humidity, RTC | yes |
| Generic ESP32 | Under development | yes | -- | -- | -- | -- |

> Only the **ESP32-C3 Mini** is currently usable. All other boards are under active development and not yet ready for end users.

---

## Supported Devices

### Heltec WiFi LoRa 32 V3 (ESP32-S3)

> **Status: Under development**

A LoRa mesh networking board.

| Spec | Details |
|------|---------|
| MCU | ESP32-S3, 240 MHz dual-core |
| Flash | 8 MB (QIO) |
| Display | SSD1306 OLED 128x64 |
| LoRa | SX1262, 868 MHz (EU band) |
| WiFi | 2.4 GHz b/g/n |
| Battery | ADC monitoring, Vext power control |
| LED | PWM dimmable (GPIO 35) |

### Heltec WiFi LoRa 32 V2 (ESP32)

> **Status: Under development**

Previous generation Heltec board. Same form factor as V3 but with the older SX1276 LoRa chip.

| Spec | Details |
|------|---------|
| MCU | ESP32, 240 MHz dual-core |
| Flash | 4 MB (DIO) |
| Display | SSD1306 OLED 128x64 |
| LoRa | SX1276, 868 MHz (EU band) |
| WiFi | 2.4 GHz b/g/n |
| Battery | ADC monitoring, Vext power control |
| LED | PWM dimmable (GPIO 25) |

### Heltec WiFi LoRa 32 V1 (ESP32)

> **Status: Under development**

The original Heltec LoRa board. No longer manufactured.

| Spec | Details |
|------|---------|
| MCU | ESP32, 240 MHz dual-core |
| Flash | 4 MB (DIO) |
| Display | SSD1306 OLED 128x64 |
| LoRa | SX1276, 868 MHz (EU band) |
| WiFi | 2.4 GHz b/g/n |
| Battery | ADC monitoring, Vext power control |
| LED | PWM dimmable (GPIO 25) |

### ESP32-S3 ePaper 1.54" (Waveshare)

> **Status: Under development**

A sensor-rich board with an e-paper display, ideal for environmental monitoring stations.

| Spec | Details |
|------|---------|
| MCU | ESP32-S3, 240 MHz dual-core |
| Flash | 4 MB (QIO) |
| PSRAM | Yes (Quad SPI) |
| Display | 1.54" e-paper, 200x200 pixels (LVGL graphics) |
| Sensors | SHTC3 temperature/humidity, PCF85063 RTC |
| Storage | SD card (FAT, 1-bit SDMMC) |
| WiFi | 2.4 GHz b/g/n |
| Battery | ADC monitoring |
| Buttons | Boot + Power (wake from deep sleep) |

### ESP32-C3 Mini

> **Status: Ready**

A minimal, low-cost board for WiFi-only relay nodes. No display, no LoRa.

| Spec | Details |
|------|---------|
| MCU | ESP32-C3, 160 MHz single-core |
| Flash | 4 MB |
| WiFi | 2.4 GHz b/g/n |
| BLE | 5.0 |
| LED | RGB (GPIO 8) |

### Generic ESP32

> **Status: Under development**

A skeleton target for any plain ESP32 dev board. WiFi only, no peripherals.

| Spec | Details |
|------|---------|
| MCU | ESP32, 240 MHz dual-core |
| Flash | 4 MB |
| WiFi | 2.4 GHz b/g/n |

---

## Feature Comparison

| Feature | Heltec V3 | Heltec V2 | Heltec V1 | S3 ePaper | ESP32-C3 | Generic |
|---------|:---------:|:---------:|:---------:|:---------:|:--------:|:-------:|
| WiFi | yes | yes | yes | yes | yes | yes |
| LoRa (868 MHz) | SX1262 | SX1276 | SX1276 | -- | -- | -- |
| OLED Display | yes | yes | yes | -- | -- | -- |
| E-Paper Display | -- | -- | -- | yes | -- | -- |
| BLE | -- | -- | -- | -- | yes | -- |
| Temperature/Humidity | -- | -- | -- | SHTC3 | -- | -- |
| Real-Time Clock | -- | -- | -- | PCF85063 | -- | -- |
| SD Card | -- | -- | -- | yes | -- | -- |
| PSRAM | -- | -- | -- | yes | -- | -- |
| Battery Monitoring | yes | yes | yes | yes | -- | -- |
| LED | yes | yes | yes | backlight | RGB | -- |
| Mesh Networking | yes | yes | yes | yes | limited | yes |

---

## Firmware Features

All boards share the same firmware codebase. Features are compiled in or out based on hardware capability.

### Network Services

- **WiFi** — station mode (connect to your router) + AP mode ("Geogram-Setup") for first-time configuration
- **HTTP Server** (port 80) — web-based configuration portal and Station API
- **Telnet Server** (port 23) — remote CLI access over the network
- **FTP Server** (port 21) — SD card file management (on boards with SD cards)
- **SSH Server** — secure remote access
- **DNS Server** — captive portal for AP mode configuration
- **ESP-MESH** — self-organizing tree-topology mesh between ESP32 nodes

### Station Services

- **Station API** — JSON-based device status and control endpoints
- **OTA Updates** — polls GitHub releases for new firmware versions
- **IP Geolocation** — automatic location detection via ip-api.com
- **NTP Sync** — time synchronization when connected to the internet
- **NOSTR Keys** — generates unique callsigns using NOSTR key pairs
- **Map Tile Caching** — fetches and caches OpenStreetMap tiles to SD card

### Sensors and Display

- **E-paper UI** — shows temperature, humidity, time, WiFi status, and location (ePaper board)
- **OLED UI** — shows connection status and basic info (Heltec boards)
- **Environmental Monitoring** — temperature and humidity readings every 30 seconds
- **Battery Monitoring** — voltage readings via ADC

### CLI Commands

The firmware provides an interactive command-line interface via USB serial (115200 baud) or Telnet:

| Command | Description |
|---------|-------------|
| `help` | List all available commands |
| `status` | Show system status (WiFi, memory, uptime) |
| `reboot` | Restart the device |
| `wifi status` | Show WiFi connection info |
| `wifi scan` | Scan for available networks |
| `wifi connect <ssid> <pass>` | Connect to a network |
| `display refresh` | Force display refresh |
| `ftp status` / `ftp start` / `ftp stop` | FTP server control |
| `config show` | Show device configuration |
| `config password <pass>` | Set device password |

---

## First Boot

1. Power on the device — it starts in AP mode
2. Connect to WiFi network **Geogram-Setup** (open network)
3. Open `http://192.168.4.1` in your browser
4. Enter your WiFi network credentials
5. The device connects and displays its new IP address

After configuration, the device will auto-connect on future boots.

---

## Flashing Firmware

### Prerequisites

- [PlatformIO](https://platformio.org/) CLI installed
- USB cable (USB-C for most boards)

### Build and Flash

```bash
cd esp32/

# Build for your board
pio run -e heltec_v3          # Heltec V3
pio run -e heltec_v2          # Heltec V2
pio run -e heltec_v1          # Heltec V1
pio run -e esp32s3_epaper_1in54  # ePaper board
pio run -e esp32c3_mini       # C3 Mini
pio run -e esp32_generic      # Generic ESP32

# Flash to the connected board
pio run -e heltec_v3 -t upload

# Monitor serial output
pio device monitor -b 115200
```

Pre-built firmware binaries are also available in `esp32/firmware/` and on the [releases page](https://github.com/geograms/geogram/releases).

### Flashing from the App

The Geogram app includes a built-in flasher that can detect connected ESP32 boards via USB and flash them directly. Open the **Flasher** app from the main screen.
