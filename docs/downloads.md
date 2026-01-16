# Geogram Downloads Specification

All files downloaded by Geogram clients and served by station servers.

---

## Path Variables

| Variable | Mobile | Desktop Linux | Desktop macOS | Desktop Windows |
|----------|--------|---------------|---------------|-----------------|
| `{data-root}` | `getApplicationDocumentsDirectory()/geogram` | `~/.local/share/geogram` | `~/.local/share/geogram` | `%USERPROFILE%/.local/share/geogram` |
| `{app-support}` | `getApplicationSupportDirectory()` | `~/.local/share/geogram` | `~/Library/Application Support/geogram` | `%APPDATA%/geogram` |
| `{app-cache}` | `getApplicationCacheDirectory()` | `~/.cache/geogram` | `~/Library/Caches/geogram` | `%LOCALAPPDATA%/geogram/cache` |
| `{temp}` | `getExternalCacheDir()` or `getTemporaryDirectory()` | `/tmp` | `/tmp` | `%TEMP%` |
| `{app-dir}` | N/A | Binary parent directory | App bundle | Exe directory |
| `{cwd}` | N/A | Current working directory | Current working directory | Current working directory |

**Android paths (example):**
- `{data-root}` = `/data/user/0/dev.geogram/app_flutter/geogram/`
- `{app-support}` = `/data/user/0/dev.geogram/files/`
- `{app-cache}` = `/data/user/0/dev.geogram/cache/`

Override: `GEOGRAM_DATA_DIR` env var or `--data-dir` CLI arg changes `{data-root}`.

---

## Client Storage

### 1. Application Updates

**Service:** `lib/services/update_service.dart`

| Platform | Filename | Size |
|----------|----------|------|
| Linux | `geogram-{version}-linux-x64.tar.gz` | ~50-100 MB |
| Windows | `geogram-{version}-windows-x64.exe` | ~50-100 MB |
| Android | `geogram-{version}.apk` | ~50-100 MB |
| macOS | `geogram-{version}-macos.dmg` | ~50-100 MB |

**Sources:**
1. `https://api.github.com/repos/geograms/geogram/releases/latest`
2. `http(s)://{station}/updates/{version}/{filename}`

**Storage:**
| Purpose | Path |
|---------|------|
| Download temp | `{temp}/geogram-update-{version}.{ext}` |
| Linux staging | `{app-dir}/.geogram-update/` |
| Client backups | `{app-support}/updates/{version}/` |
| Station mirror | `{data-root}/updates/{version}/` |

---

### 2. Map Tiles

**Service:** `lib/services/map_tile_service.dart`

PNG images, dynamic based on viewport.

**Sources (per layer):**

| Layer | Station | Fallback |
|-------|---------|----------|
| Standard | `/tiles/{callsign}/{z}/{x}/{y}.png` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` |
| Satellite | `/tiles/{callsign}/satellite/{z}/{x}/{y}.png` | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` |
| Labels | - | `https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}` |
| Transport | - | `https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}` |

**Storage:** `{data-root}/tiles/` (500 MB limit)

---

### 3. Vision AI Models

**Service:** `lib/bot/services/vision_model_manager.dart`

| Model ID | Filename | Size |
|----------|----------|------|
| `mobilenet_v3_large` | `mobilenet_v3_large.tflite` | ~5 MB |
| `mobilenet_v3_small` | `mobilenet_v3_small.tflite` | ~2 MB |
| `mobilenet_v4_medium` | `mobilenet_v4_medium.tflite` | ~15 MB |
| `efficientdet_lite0` | `efficientdet_lite0.tflite` | ~5 MB |
| `llava_7b_q4` | `llava-v1.5-7b-q4_k_m.gguf` | ~4.1 GB |
| `llava_7b_q5` | `llava-v1.5-7b-q5_k_m.gguf` | ~4.8 GB |

**Sources:**
1. `http(s)://{station}/bot/models/vision/{model_id}.{ext}`
2. TensorFlow Hub: `https://tfhub.dev/google/lite-model/{model_path}`
3. HuggingFace: `https://huggingface.co/{repo}/resolve/main/{filename}`

**Storage:** `{data-root}/bot/models/vision/{model_id}/`

---

### 4. Music Generation Models

**Service:** `lib/bot/services/music_model_manager.dart`

Multi-file ONNX packages.

**Source:** `http(s)://{station}/bot/models/music/{model_id}/{filepath}` (station only)

**Storage:** `{data-root}/bot/models/music/{model_id}/`

---

### 5. Whisper Speech Models

**Service:** `lib/bot/services/whisper_model_manager.dart`

Speech-to-text models using OpenAI's Whisper via whisper.cpp.

| Model ID | Filename | Size | Speed |
|----------|----------|------|-------|
| `whisper-tiny` | `ggml-tiny.bin` | ~39 MB | 32x realtime |
| `whisper-base` | `ggml-base.bin` | ~145 MB | 16x realtime |
| `whisper-small` | `ggml-small.bin` | ~465 MB | 6x realtime |
| `whisper-medium` | `ggml-medium.bin` | ~1.5 GB | 2x realtime |
| `whisper-large-v2` | `ggml-large-v2.bin` | ~3 GB | 1x realtime |

**Default:** `whisper-small` (~465 MB) - best balance of speed and accuracy

**Sources:**
1. `http(s)://{station}/bot/models/whisper/{filename}`
2. HuggingFace: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{filename}`

**Storage:** `{data-root}/bot/models/whisper/{filename}`

**Platform Support:** Android 5.0+, iOS 13+, macOS 11+

---

### 6. Music Tracks (Generated)

**Service:** `lib/bot/services/music_storage_service.dart`

**Storage:** `{data-root}/bot/music/tracks/` (500 MB limit, max 50 tracks)

---

### 7. Vision Cache

**Service:** `lib/bot/services/vision_service.dart`

**Storage:** `{data-root}/bot/cache/vision/`

---

### 8. Station Places (Downloaded)

**Service:** `lib/services/station_place_service.dart`

Files: `place.txt`, `images/*.jpg`

**Sources:**
- List: `http(s)://{station}/api/places`
- Details: `http(s)://{station}/{callsign}/api/places/{folder}`
- Files: `http(s)://{station}/{callsign}/api/places/{folder}/files/{path}`

**Storage:** `{data-root}/devices/{callsign}/places/{relative_path}/`

---

### 9. IP Geolocation (Offline)

**Service:** `lib/services/geoip_service.dart`

Privacy-preserving IP geolocation using bundled DB-IP MMDB database.

**Database:** `assets/dbip-city-lite.mmdb` (~127MB, CC BY 4.0, stored via Git LFS)

**API Endpoint:** `GET /api/geoip`

Returns client's public IP and its geolocation (latitude, longitude, city, country).

Clients request their location from the connected station, which extracts the client IP from the HTTP connection and looks it up in the local MMDB database. **No external IP services are called.**

**Attribution:** IP Geolocation by [DB-IP](https://db-ip.com)

---

### 10. Console VM Files

**Service:** `lib/services/console_vm_manager.dart`

TinyEMU/JSLinux files for running Alpine Linux VM.

| File | Description | Size |
|------|-------------|------|
| `jslinux.js` | TinyEMU JavaScript runtime | ~200 KB |
| `x86emu-wasm.wasm` | x86 emulator WASM binary | ~500 KB |
| `riscv64emu-wasm.wasm` | RISC-V emulator WASM binary | ~500 KB |
| `alpine-x86.cfg` | VM configuration template | ~1 KB |
| `alpine-x86-root.bin` | Alpine root filesystem | ~50-100 MB |
| `geogram-cli-alpine` | Geogram CLI for Alpine | ~5-10 MB |

**Sources:**
1. `http(s)://{station}/console/vm/{filename}` (station cache)
2. `https://bellard.org/jslinux/` (upstream)

**Manifest:** `http(s)://{station}/console/vm/manifest.json`

```json
{
  "version": "1.0.0",
  "updated": "2026-01-04T10:00:00Z",
  "files": [
    {"name": "jslinux.js", "size": 204800, "sha256": "..."},
    {"name": "x86emu-wasm.wasm", "size": 524288, "sha256": "..."},
    {"name": "alpine-x86-root.bin", "size": 52428800, "sha256": "..."}
  ]
}
```

**Storage:** `{data-root}/console/vm/`

---

### 11. Application Log File

**Service:** `lib/services/log_service.dart`

Single file containing application debug logs. Can grow large over time.

**Storage:** `{data-root}/log.txt`

**Typical Size:** 10 MB - 200 MB (depending on usage and debug activity)

---

### 12. Collections Data

**Service:** `lib/services/collection_service.dart`

User's synced collections and files, organized by device callsign.

**Storage:** `{data-root}/devices/{callsign}/`

**Contents:**
- Collection metadata and indexes
- Synced files from stations
- Place data and images

**Typical Size:** Variable (depends on synced content)

---

### 13. Chat Data

**Service:** `lib/services/chat_service.dart`

Direct message conversations stored as restricted chat rooms.

**Storage:** `{data-root}/chat/`

**Typical Size:** Variable (depends on chat history)

---

### 14. Backups

**Service:** `lib/services/backup_service.dart`

Profile and data backups created by the user.

**Storage:** `{data-root}/backups/`

**Typical Size:** Variable

---

### 15. Transfers

**Service:** `lib/services/transfer_service.dart`

Pending and in-progress file transfers.

**Storage:** `{data-root}/transfers/`

**Typical Size:** Variable (temporary storage)

---

### 16. System Cache

System-level cache managed by Flutter and WebView components.

**Storage:** `{app-cache}/`

**Contents:**
- WebView cache
- File picker temporary files
- Crash reports

**Typical Size:** 10-50 MB

---

## Station Server Storage

**Service:** `lib/services/station_server_service.dart`

The station server caches and serves content for offline/LAN operation.

### Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/updates/latest` | Latest release info (proxied from GitHub) |
| `GET /updates/{version}/{filename}` | Update binaries |
| `GET /tiles/{callsign}/{z}/{x}/{y}.png` | Map tiles |
| `GET /bot/models/vision/{model_id}.{ext}` | Vision models |
| `GET /bot/models/music/{model_id}/{path}` | Music models |
| `GET /bot/models/whisper/{filename}` | Whisper speech models |
| `GET /api/places` | Station places list |
| `GET /{callsign}/api/places/{folder}` | Place details |
| `GET /{callsign}/api/places/{folder}/files/{path}` | Place files |
| `GET /console/vm/manifest.json` | Console VM files manifest |
| `GET /console/vm/{filename}` | Console VM files |

### Storage Paths

All station server storage uses `StorageConfig` for consistency with client:

| Content | Path |
|---------|------|
| Updates | `{data-root}/updates/{version}/` |
| Tiles | `{data-root}/tiles/{layer}/{z}/{x}/{y}.png` |
| Vision models | `{data-root}/bot/models/vision/{model_id}/` |
| Music models | `{data-root}/bot/models/music/{model_id}/` |
| Whisper models | `{data-root}/bot/models/whisper/` |
| Places | `{data-root}/devices/{callsign}/places/` |
| Console VM | `{data-root}/console/vm/` |

Since the station server can also act as a client, using the same paths ensures downloaded models/tiles are shared between client and server functionality.

---

## Summary

| Category | Source Priority | Storage Path | Size |
|----------|-----------------|--------------|------|
| APK Backups | GitHub > Station | `{app-support}/updates/` | 50-100 MB per version |
| Updates (mirror) | GitHub | `{data-root}/updates/` | 50-100 MB |
| Log File | Local only | `{data-root}/log.txt` | 10-200 MB |
| Tiles | Station > OSM/Esri | `{data-root}/tiles/` | Up to 500 MB |
| Collections | Station sync | `{data-root}/devices/` | Variable |
| Vision Models | Station > TFHub/HF | `{data-root}/bot/models/vision/` | 2 MB - 5 GB |
| Whisper Models | Station > HF | `{data-root}/bot/models/whisper/` | 39 MB - 3 GB |
| Music Models | Station only | `{data-root}/bot/models/music/` | Variable |
| Music Tracks | Local only | `{data-root}/bot/music/tracks/` | Up to 500 MB |
| Vision Cache | Local only | `{data-root}/bot/cache/vision/` | Variable |
| Console VM | Station > Upstream | `{data-root}/console/vm/` | ~60-120 MB |
| Chat Data | Local only | `{data-root}/chat/` | Variable |
| Backups | Local only | `{data-root}/backups/` | Variable |
| Transfers | Local only | `{data-root}/transfers/` | Variable |
| System Cache | Local only | `{app-cache}/` | 10-50 MB |

Most storage is unified under `{data-root}` (the "Working folder" in Security settings).
APK backups and system cache use platform-specific directories (`{app-support}` and `{app-cache}`).

---

## Storage Settings UI

**Page:** `lib/pages/storage_settings_page.dart`

The Storage settings page (Settings > Storage) displays disk usage for all categories
and allows users to clear individual categories to free up space.

Categories are displayed with:
- Icon and color coding
- Translated name and description
- Current size in human-readable format
- Clear button (when data exists)

The page handles three different storage roots:
1. `{data-root}` - Main geogram data folder
2. `{app-support}` - Platform app support directory (APK backups on Android)
3. `{app-cache}` - Platform cache directory
