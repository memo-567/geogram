# Geogram Downloads Specification

All files downloaded by Geogram clients and served by station servers.

---

## Path Variables

| Variable | Mobile | Desktop Linux | Desktop macOS | Desktop Windows |
|----------|--------|---------------|---------------|-----------------|
| `{data-root}` | `getApplicationDocumentsDirectory()/geogram` | `~/.local/share/geogram` | `~/.local/share/geogram` | `%USERPROFILE%/.local/share/geogram` |
| `{app-support}` | N/A | `~/.local/share/geogram` | `~/Library/Application Support/geogram` | `%APPDATA%/geogram` |
| `{temp}` | `getExternalCacheDir()` or `getTemporaryDirectory()` | `/tmp` | `/tmp` | `%TEMP%` |
| `{app-dir}` | N/A | Binary parent directory | App bundle | Exe directory |
| `{cwd}` | N/A | Current working directory | Current working directory | Current working directory |

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

### 7. Station Places (Downloaded)

**Service:** `lib/services/station_place_service.dart`

Files: `place.txt`, `images/*.jpg`

**Sources:**
- List: `http(s)://{station}/api/places`
- Details: `http(s)://{station}/{callsign}/api/places/{folder}`
- Files: `http(s)://{station}/{callsign}/api/places/{folder}/files/{path}`

**Storage:** `{data-root}/devices/{callsign}/places/{relative_path}/`

---

### 8. IP Geolocation

**Service:** `lib/util/geolocation_utils.dart`

JSON responses (not stored).

**Sources:**
1. `http://ip-api.com/json/?fields=status,lat,lon,city,country`
2. `https://ipinfo.io/json`
3. `https://ipwho.is/`

---

### 9. Console VM Files

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
| Places | `{data-root}/devices/{callsign}/places/` |
| Console VM | `{data-root}/console/vm/` |

Since the station server can also act as a client, using the same paths ensures downloaded models/tiles are shared between client and server functionality.

---

## Summary

| Category | Source Priority | Storage Path | Size |
|----------|-----------------|--------------|------|
| Updates (backups) | GitHub > Station | `{app-support}/updates/` | 50-100 MB |
| Updates (mirror) | GitHub | `{data-root}/updates/` | 50-100 MB |
| Tiles | Station > OSM/Esri | `{data-root}/tiles/` | Up to 500 MB |
| Vision Models | Station > TFHub/HF | `{data-root}/bot/models/vision/` | 2 MB - 5 GB |
| Music Models | Station only | `{data-root}/bot/models/music/` | Variable |
| Music Tracks | Local only | `{data-root}/bot/music/tracks/` | Up to 500 MB |
| Vision Cache | Local only | `{data-root}/bot/cache/vision/` | Variable |
| Places | Station only | `{data-root}/devices/` | Variable |
| Console VM | Station > Upstream | `{data-root}/console/vm/` | ~60-120 MB |

All storage is unified under `{data-root}` (the "Working folder" in Security settings).
