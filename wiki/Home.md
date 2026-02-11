# Geogram Wiki

Welcome to the Geogram wiki — the documentation hub for users and contributors.

Geogram is an offline-first communication platform that connects smartphones, ESP32 stations, and Linux servers into a decentralized mesh network. Messages travel over BLE, LoRa, and WiFi — no internet required.

## What is Geogram?

Geogram lets you communicate without relying on centralized infrastructure. It works by creating a network of devices that relay messages to each other:

- **Smartphones** run the Geogram app (Android, Linux desktop) and communicate via BLE and WiFi
- **ESP32 stations** act as bridge nodes — they connect BLE mesh networks to WiFi and provide local services like map tile caching and environmental sensors
- **CLI stations** run on Linux servers and provide NOSTR relay, WebSocket hub, tile caching, STUN server, and file hosting for the network

```
Smartphones ──BLE──► ESP32 Stations ──WiFi──► CLI Station ──Internet──► Other Stations
                           │
                      LoRa mesh
                           │
                     Other ESP32s
```

## Pages

| Page | Description |
|------|-------------|
| [ESP32 Devices and Firmware](ESP32-Devices-and-Firmware) | Supported boards, features per device, and firmware overview |
| [CLI Station Installation](CLI-Station-Installation) | How to deploy a Geogram station on a Linux server |
| [Community and Support](Community-and-Support) | Where to get help and connect with other users |

## Quick Links

- [Download Geogram](https://geogram.radio/#downloads) — prebuilt binaries for Android, Linux, and ESP32
- [Source Code](https://github.com/geograms/geogram) — main repository
- [Report a Bug](https://github.com/geograms/geogram/issues) — issue tracker
