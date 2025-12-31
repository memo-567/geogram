# Bot Format Specification

**Version**: 1.4
**Last Updated**: 2025-12-31
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Dependencies](#dependencies)
- [Architecture](#architecture)
- [File Organization](#file-organization)
- [Configuration File Format](#configuration-file-format)
- [Supported Models](#supported-models)
- [Voice Input (Whisper)](#voice-input-whisper)
- [Vision / Image Recognition](#vision--image-recognition)
- [Content Crawling](#content-crawling)
- [Built-in Data Sources](#built-in-data-sources)
- [Data Indexing](#data-indexing)
- [Moderation System](#moderation-system)
- [Conversation Format](#conversation-format)
- [API Endpoints](#api-endpoints)
- [User Interface](#user-interface)
- [Hardware Detection](#hardware-detection)
- [Performance Targets](#performance-targets)
- [Security Considerations](#security-considerations)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)
- [Related Documentation](#related-documentation)
- [Change Log](#change-log)

## Overview

The Bot app provides an **offline AI assistant** for Geogram stations using **existing Dart/Flutter LLM libraries**. The bot operates entirely offline without external API calls, adapting its intelligence level based on available device hardware.

### Primary Functions

1. **Q&A Assistant**: Answer questions about station data (places, events, alerts, chat history)
2. **Auto-Moderation**: Monitor chat rooms for spam, harmful content, and policy violations
3. **Data Search**: Semantic and keyword search across all station apps
4. **Voice Input**: Transcribe voice messages using Whisper for hands-free interaction
5. **Content Crawling**: Extract and index metadata from all app folders

### Design Principles

- **Use Existing Libraries**: Leverage battle-tested packages (llm_toolkit, whisper_flutter_new)
- **HuggingFace Models**: Download and use existing GGUF models from HuggingFace
- **Completely Offline**: No external API calls after model download
- **Adaptive Intelligence**: Scale model complexity based on device resources
- **Privacy First**: All data stays on device, no telemetry

### App Availability

The Bot app is a **default app** - it is always available in the bottom navigation bar and does not need to be added from the "Add" menu. Unlike other apps that users can selectively enable, Bot is a core feature of Geogram.

### Data Storage

Bot data is stored in a dedicated `bot/` folder within each device's directory:

```
devices/{callsign}/bot/
├── models/           # Downloaded LLM and Whisper models
├── index/            # Metadata indexes for fast search
├── moderation/       # Moderation logs and hidden content
└── conversations/    # Bot conversation history
```

This folder is automatically created when the bot is first used and contains:
- Downloaded AI models (GGUF format)
- Search indexes for station content
- Conversation history with the bot
- Moderation action logs

## Key Features

| Feature | Description |
|---------|-------------|
| LLM Inference | GGUF models via llama.cpp (GPU accelerated) |
| Voice Input | Whisper speech-to-text (offline) |
| HuggingFace | Download models directly from HuggingFace Hub |
| RAG Support | Built-in retrieval-augmented generation |
| Content Crawling | Extract metadata from all station apps |
| Auto-moderation | Hide spam/harmful content, notify moderators |
| Multi-language | Follows station language settings |
| NOSTR signing | Bot responses can be cryptographically signed |

## Dependencies

### Required Packages

```yaml
# pubspec.yaml
dependencies:
  # LLM Inference + Whisper + HuggingFace integration
  llm_toolkit: ^0.1.0

  # Alternative: Direct llama.cpp binding
  flutter_llama: ^0.1.0
  # or
  llama_cpp: ^0.0.1

  # Whisper speech-to-text (if not using llm_toolkit)
  whisper_flutter_new: ^1.0.0

  # GGUF file parsing (for model metadata)
  gguf: ^0.0.1
```

### Package Descriptions

| Package | Purpose | Link |
|---------|---------|------|
| [llm_toolkit](https://pub.dev/packages/llm_toolkit) | All-in-one: LLM + Whisper + HuggingFace + RAG | Recommended |
| [flutter_llama](https://pub.dev/packages/flutter_llama) | GPU-accelerated GGUF inference | Android/iOS/macOS |
| [llama_cpp](https://pub.dev/packages/llama_cpp) | Pure Dart llama.cpp binding | Cross-platform |
| [whisper_flutter_new](https://pub.dev/packages/whisper_flutter_new) | Offline Whisper ASR | Android/iOS/macOS |
| [gguf](https://pub.dev/packages/gguf) | GGUF file metadata parser | Utility |

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Bot Service                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │  Hardware   │  │   Content    │  │    Moderation     │  │
│  │  Service    │  │   Crawler    │  │     Service       │  │
│  └─────────────┘  └──────────────┘  └───────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │   Index     │  │    Voice     │  │      Model        │  │
│  │  Service    │  │   (Whisper)  │  │    Manager        │  │
│  └─────────────┘  └──────────────┘  └───────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                  External Libraries                         │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  llm_toolkit / flutter_llama / llama_cpp              │ │
│  │  (GGUF inference, HuggingFace, Whisper, RAG)          │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Code Structure

```
lib/bot/
├── models/
│   ├── bot_config.dart           # Bot configuration model
│   ├── bot_response.dart         # Response structure
│   ├── moderation_result.dart    # Moderation decision
│   ├── crawled_content.dart      # Extracted content model
│   └── model_info.dart           # HuggingFace model metadata
├── services/
│   ├── bot_service.dart          # Main orchestration
│   ├── llm_service.dart          # LLM wrapper (llm_toolkit/flutter_llama)
│   ├── whisper_service.dart      # Voice-to-text wrapper
│   ├── model_manager.dart        # Download/manage HuggingFace models
│   ├── content_crawler.dart      # Crawl all app folders
│   ├── index_service.dart        # Build searchable index
│   ├── moderation_service.dart   # Auto-moderation logic
│   └── hardware_service.dart     # Resource detection
├── crawlers/
│   ├── base_crawler.dart         # Abstract crawler interface
│   ├── place_crawler.dart        # Extract from places/
│   ├── event_crawler.dart        # Extract from events/
│   ├── alert_crawler.dart        # Extract from active/, expired/
│   ├── chat_crawler.dart         # Extract from chat/
│   ├── blog_crawler.dart         # Extract from blog/
│   ├── market_crawler.dart       # Extract from market/
│   └── media_crawler.dart        # Extract from media files (EXIF, etc.)
└── util/
    ├── metadata_extractor.dart   # Generic metadata extraction
    └── text_chunker.dart         # Split text for embedding
```

## File Organization

### Directory Structure

```
devices/{callsign}/bot/
├── bot.txt                     # Bot configuration
├── models/                     # Model weight files
│   ├── nano.gbot              # ~5MB (moderation only)
│   ├── micro.gbot             # ~50MB (Q&A + moderation)
│   ├── small.gbot             # ~200MB (full capabilities)
│   └── base.gbot              # ~500MB+ (server-only)
├── vocab/
│   ├── tokenizer.json         # BPE vocabulary
│   └── merges.txt             # BPE merge rules
├── index/
│   ├── config.json            # Index configuration
│   ├── recent/                # Last N days, fully indexed
│   │   ├── embeddings.bin     # Sentence vectors
│   │   └── metadata.json      # Source mappings
│   └── archive/               # Older content
│       └── keywords.json      # Inverted index
├── moderation/
│   ├── log.txt                # Moderation action log
│   ├── hidden/                # Hidden messages
│   │   └── {timestamp}_{room}_{author}.txt
│   └── blocked/               # Temporarily blocked users
│       └── {callsign}.txt
└── conversations/             # User ↔ Bot chat history
    └── {user_callsign}/
        └── history.txt
```

## Configuration File Format

### bot.txt

```
# BOT: Station Assistant

CREATED: 2025-12-31 10:00_00
AUTHOR: X1ABCD
MODEL_TIER: auto
ACTIVE: true
LANGUAGE: en

## SYSTEM_PROMPT
You are a helpful assistant for this Geogram station.
Answer questions about local events, places, alerts, and community discussions.
Be concise, accurate, and helpful.
Do not make up information - only reference data you can find in the station.

## MODERATION_RULES
- Hide messages containing obvious spam patterns
- Flag messages with suspicious external links
- Block users sending repeated identical messages (>3 in 1 minute)
- Flag messages with excessive caps or special characters
- Allow: questions, discussions, announcements, event coordination

## MODERATION_THRESHOLDS
SPAM: 0.7
HARMFUL: 0.8
SUSPICIOUS: 0.5

## MONITORED_ROOMS
main
events
marketplace
announcements

## EXEMPT_USERS
X1ABCD
Y2EFGH

## ADMIN_NOTIFICATIONS
X1ABCD
Y2EFGH
Z3IJKL

## INDEX_SETTINGS
RECENT_DAYS: 7
ARCHIVE_KEYWORDS: true
REINDEX_INTERVAL: 3600

--> npub: npub1...
--> signature: hex_signature
```

### Configuration Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `CREATED` | timestamp | Yes | - | Creation timestamp (YYYY-MM-DD HH:MM_ss) |
| `AUTHOR` | string | Yes | - | Creator's callsign |
| `MODEL_TIER` | enum | No | `auto` | Model tier: `nano`, `micro`, `small`, `base`, `auto` |
| `ACTIVE` | boolean | No | `true` | Whether bot is active |
| `LANGUAGE` | string | No | `en` | Primary language code |
| `SYSTEM_PROMPT` | text | No | default | Bot personality/instructions |
| `MODERATION_RULES` | list | No | default | Natural language moderation rules |
| `MODERATION_THRESHOLDS` | map | No | defaults | Category → confidence thresholds |
| `MONITORED_ROOMS` | list | No | `main` | Chat rooms to moderate |
| `EXEMPT_USERS` | list | No | - | Callsigns exempt from moderation |
| `ADMIN_NOTIFICATIONS` | list | No | author | Callsigns to notify on moderation |
| `INDEX_SETTINGS` | map | No | defaults | Data indexing configuration |
| `npub` | string | No | - | NOSTR public key |
| `signature` | string | No | - | Configuration signature |

## Supported Models

### HuggingFace GGUF Models

The bot uses standard **GGUF format** models from HuggingFace. No custom model format needed.

#### Recommended Models by Hardware

| Target Device | Model | Size | HuggingFace Repo |
|---------------|-------|------|------------------|
| **Low-end phone** | Qwen2.5-0.5B-Instruct | ~400MB | `Qwen/Qwen2.5-0.5B-Instruct-GGUF` |
| **Mid-range phone** | Qwen2.5-1.5B-Instruct | ~1GB | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` |
| **High-end phone** | Llama-3.2-3B-Instruct | ~2GB | `meta-llama/Llama-3.2-3B-Instruct-GGUF` |
| **Tablet/Desktop** | Mistral-7B-Instruct | ~4GB | `mistralai/Mistral-7B-Instruct-v0.3-GGUF` |
| **Server** | Llama-3.1-8B-Instruct | ~5GB | `meta-llama/Llama-3.1-8B-Instruct-GGUF` |

#### Quantization Levels

| Quantization | Quality | Size Reduction | Recommended For |
|--------------|---------|----------------|-----------------|
| Q8_0 | Best | ~50% | Server/Desktop |
| Q6_K | Excellent | ~60% | High-end devices |
| Q5_K_M | Very Good | ~65% | Mid-range devices |
| Q4_K_M | Good | ~70% | Mobile devices |
| Q3_K_M | Acceptable | ~75% | Low-end devices |
| Q2_K | Lower | ~80% | Very constrained |

#### Model Selection Logic

```dart
Future<String> selectBestModel(HardwareInfo hw) async {
  final availableMB = hw.availableRamMB;
  final isServer = hw.platform == 'linux' && hw.cpuCores > 4;

  if (isServer && availableMB > 8000) {
    return 'Llama-3.1-8B-Instruct-Q6_K.gguf';
  } else if (availableMB > 4000) {
    return 'Mistral-7B-Instruct-Q4_K_M.gguf';
  } else if (availableMB > 2000) {
    return 'Llama-3.2-3B-Instruct-Q4_K_M.gguf';
  } else if (availableMB > 1000) {
    return 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf';
  } else {
    return 'Qwen2.5-0.5B-Instruct-Q4_K_M.gguf';
  }
}
```

### Model Download & Management

```dart
class ModelManager {
  /// Download model from HuggingFace
  Future<void> downloadModel(String repoId, String filename) async {
    // Uses llm_toolkit's built-in HuggingFace downloader
    // Supports resume, progress tracking, integrity verification
  }

  /// List available local models
  List<ModelInfo> getLocalModels();

  /// Delete a model to free space
  Future<void> deleteModel(String filename);

  /// Get model info from GGUF metadata
  ModelInfo getModelInfo(String path);
}
```

## Voice Input (Whisper)

### Whisper Models

The bot uses OpenAI Whisper models for speech-to-text, running fully offline.

| Model | Size | Languages | Speed | Quality |
|-------|------|-----------|-------|---------|
| tiny | ~75MB | Multi | Fastest | Good |
| base | ~150MB | Multi | Fast | Better |
| small | ~500MB | Multi | Medium | Great |
| medium | ~1.5GB | Multi | Slow | Excellent |

#### Recommended Whisper Models

| Target Device | Model | Notes |
|---------------|-------|-------|
| Phone | whisper-tiny | Fast, good for short queries |
| Tablet | whisper-base | Better accuracy |
| Desktop/Server | whisper-small | Best balance |

### Voice Input Flow

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Record     │ →  │   Whisper    │ →  │     LLM      │
│   Audio      │    │  Transcribe  │    │   Process    │
└──────────────┘    └──────────────┘    └──────────────┘
       ↓                   ↓                   ↓
   .wav file          Text query          Response
```

### Whisper Service

```dart
class WhisperService {
  /// Initialize Whisper with model
  Future<void> initialize(String modelPath);

  /// Transcribe audio file
  Future<String> transcribe(String audioPath, {String? language});

  /// Transcribe with timestamps
  Future<List<TranscriptSegment>> transcribeWithTimestamps(String audioPath);

  /// Supported formats: .wav (required), max 30s chunks
  /// Longer audio automatically chunked
}

class TranscriptSegment {
  final Duration start;
  final Duration end;
  final String text;
  final double confidence;
}
```

### Audio Requirements

| Requirement | Value |
|-------------|-------|
| Format | WAV (PCM) |
| Sample Rate | 16kHz |
| Channels | Mono |
| Bit Depth | 16-bit |
| Max Duration | 30s per chunk (auto-chunked) |

## Vision / Image Recognition

### Overview

The Bot supports image analysis through on-device vision models, allowing users to:
- Send photos and ask questions about them
- Identify plants, mushrooms, and species
- Extract and translate text from images (OCR)
- Detect objects and describe scenes

### Vision Model Tiers

| Tier | Models | Size | Speed | Capabilities |
|------|--------|------|-------|--------------|
| **Lite** | MobileNet, EfficientDet (TFLite) | 5-100 MB | 100-500ms | Object detection, classification |
| **Standard** | LLaVA-7B Q3 | ~800 MB | 3-5s | General visual Q&A, descriptions |
| **Quality** | LLaVA-7B Q4 | ~1.2 GB | 4-7s | Better accuracy visual Q&A |
| **Premium** | Qwen2-VL-7B Q4 | ~1 GB | 4-6s | Multilingual, translation |

### Vision Dependencies

```yaml
# pubspec.yaml
dependencies:
  tflite_flutter: ^0.11.0     # TensorFlow Lite inference
  image_picker: ^1.1.2         # Camera + gallery picker
  image: ^4.3.0                # Image preprocessing
```

### Vision Code Structure

```
lib/bot/
├── models/
│   ├── vision_result.dart        # Image analysis result model
│   └── vision_model_info.dart    # Vision model metadata
├── services/
│   ├── vision_service.dart       # Main vision orchestration
│   ├── vision_model_manager.dart # Download/manage vision models
│   └── tflite_service.dart       # TensorFlow Lite inference
```

### VisionResult Model

```dart
class VisionResult {
  final String? description;         // Natural language description
  final List<DetectedObject> objects; // Detected objects with bounding boxes
  final String? extractedText;       // OCR result
  final String? transliteration;     // Script conversion (Cyrillic → Latin)
  final String? translation;         // Translated text
  final List<String> labels;         // Classification labels
  final SpeciesIdentification? species; // Plant/mushroom identification
  final double confidence;
  final String modelUsed;
  final int processingTimeMs;
}

class SpeciesIdentification {
  final String scientificName;
  final String? commonName;
  final bool isToxic;
  final String? warning;
  final double confidence;
}
```

### Available Vision Models

| Model ID | Category | Size | Capabilities |
|----------|----------|------|--------------|
| `mobilenet-v3` | Lite | 5 MB | Object classification |
| `efficientdet-lite0` | Lite | 20 MB | Object detection |
| `plant-classifier` | Plant | 80 MB | Plant identification |
| `llava-7b-q3` | General | 800 MB | Visual Q&A |
| `llava-7b-q4` | General | 1.2 GB | Visual Q&A (better) |
| `qwen2-vl-7b-q4` | Multilingual | 1 GB | Translation, OCR |

### Vision Use Cases

#### Plant & Mushroom Identification

```
User: [sends photo of mushroom]
User: "What is this?"

Bot: **Amanita muscaria** (Fly Agaric)

This appears to be a Fly Agaric mushroom based on:
- Red cap with white spots
- White gills and stem
- Ring on stem

⚠️ **Warning**: This mushroom is TOXIC and should not be consumed.

Confidence: 87%
```

#### Text Extraction & Translation

```
User: [sends photo of Russian sign]
User: "What does this say?"

Bot: **Text detected** (Cyrillic):
     "Вход запрещён"

     **Transliteration:** Vkhod zapreshchyon

     **Translation** (English): Entry prohibited
```

#### Object Detection

```
User: [sends photo of street scene]
User: "What's in this photo?"

Bot: I can see a street cafe with outdoor seating.

**Detected:**
- People (3)
- Tables (4)
- Cars (2)
- Sign ("Landmark Cafe")

The cafe appears busy with customers seated outside.
```

### Vision Settings UI

The Bot Settings page includes a Vision Models section:

```
┌─────────────────────────────────────────────────────────────┐
│  VISION MODELS                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Vision storage: 25 MB                              │   │
│  │                                                     │   │
│  │  LITE (FAST DETECTION)                              │   │
│  │  ✓ MobileNet v3 (5 MB)           [Delete]          │   │
│  │  ○ EfficientDet Lite (20 MB)     [Download]        │   │
│  │                                                     │   │
│  │  PLANT & NATURE                                     │   │
│  │  ○ Plant Classifier (80 MB)      [Download]        │   │
│  │                                                     │   │
│  │  GENERAL VISION                                     │   │
│  │  ○ LLaVA 7B Q3 (800 MB)          [Download]        │   │
│  │                                                     │   │
│  │  MULTILINGUAL                                       │   │
│  │  ○ Qwen2-VL 7B Q4 (1 GB)         [Download]        │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│  [Clear Vision Models]                                      │
└─────────────────────────────────────────────────────────────┘
```

### Vision Storage

```
devices/{callsign}/bot/
├── models/
│   ├── llm/                    # LLM models (existing)
│   │   └── qwen-1.5b.gguf
│   └── vision/                 # Vision models
│       ├── mobilenet-v3.tflite
│       ├── plant-classifier.tflite
│       └── llava-7b-q3.gguf
└── cache/
    └── vision/                 # Cached image analysis
        └── {image_hash}.json
```

### Offline-First Model Downloads (Station-First Pattern)

Vision models follow the same **offline-first** download pattern as map tiles. Station servers cache all available models, and clients prefer downloading from the station (over any available transport) before falling back to internet.

#### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  STATION SERVER (has internet access periodically)              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Auto-downloads ALL available vision models at startup   │   │
│  │  Stores in: {appDir}/bot/models/vision/                  │   │
│  │  Serves via HTTP: /bot/models/{modelId}.{ext}            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │                    │                    │
           ▼ (LAN)              ▼ (Station WS)       ▼ (BLE+)
┌─────────────────────────────────────────────────────────────────┐
│  CLIENT DEVICE (may be offline, uses ConnectionManager)         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Check local cache                                    │   │
│  │  2. Use ConnectionManager to check station reachability  │   │
│  │  3. Try station via best available transport             │   │
│  │  4. Fallback: internet (HuggingFace/TFHub)               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

#### Transport Priority

The ConnectionManager automatically selects the best available transport:

| Transport | Priority | Use Case |
|-----------|----------|----------|
| LAN | 10 | Same local network (fastest) |
| WebRTC | 15 | P2P via NAT traversal |
| Station | 30 | Relayed via station WebSocket |
| BLE+ | 35 | Bluetooth Classic (slow for large models) |
| BLE | 40 | Too slow - skip for model downloads |

#### URL Pattern

Station model downloads use the same URL conversion pattern as map tiles:

| Component | Pattern |
|-----------|---------|
| Station URL | From `StationService().getPreferredStation().url` |
| Protocol conversion | `wss://` → `https://`, `ws://` → `http://` |
| Model endpoint | `{station_url}/bot/models/{modelId}.{extension}` |
| Example | `https://station.local/bot/models/mobilenet-v3.tflite` |

#### Download Flow

```dart
/// VisionModelManager.downloadModel() pseudocode
Stream<double> downloadModel(String modelId) async* {
  // 1. Check local cache
  if (await isDownloaded(modelId)) {
    yield 1.0;
    return;
  }

  // 2. Check station reachability via any transport
  if (await ConnectionManager().isReachable(station.callsign)) {
    final stationUrl = _getStationModelUrl(modelId, extension);
    try {
      yield* _downloadFromUrl(stationUrl, modelId);
      return; // Success
    } catch (e) {
      // Station download failed, try internet
    }
  }

  // 3. Fallback to internet (HuggingFace/TFHub)
  yield* _downloadFromUrl(model.url, modelId);
}
```

#### Station Server Auto-Download

Station servers automatically download all vision models at startup, with disk space checking:

```dart
/// Called when station server starts
Future<void> downloadAllVisionModels() async {
  final modelsDir = path.join(_appDir, 'bot', 'models', 'vision');

  for (final model in VisionModels.available) {
    final modelPath = path.join(modelsDir, filename);
    if (await File(modelPath).exists()) continue;

    // Check disk space before each download (1GB minimum buffer)
    final freeSpace = await _getFreeDiskSpace(modelsDir);
    if (freeSpace != null && freeSpace < model.size + _minFreeSpaceBuffer) {
      LogService().log('Skipping ${model.id} - insufficient disk space');
      continue;
    }

    await _downloadModelFromInternet(model.url, modelPath);
  }
}
```

**Disk Space Requirements:**
- Maintains a minimum 1 GB buffer after each download
- Checks available space before each model download
- Logs which models were skipped due to space constraints
- Uses `df` on Linux/macOS and `wmic` on Windows for space detection

#### Files Modified

| File | Changes |
|------|---------|
| `lib/bot/services/vision_model_manager.dart` | Station-first download logic |
| `lib/services/station_server_service.dart` | `/bot/models/` endpoint + auto-download |

### Vision Integration with BotService

```dart
/// Send a message with optional image
Future<void> sendMessage(String content, {String? imagePath}) async {
  if (imagePath != null) {
    // Analyze image first
    final visionResult = await VisionService().analyzeImage(
      imagePath,
      question: content.isNotEmpty ? content : null,
    );

    // Generate response based on vision + query
    return _generateVisionResponse(content, visionResult);
  }

  // Existing text-only processing
  return _processTextQuery(content);
}
```

### Chat UI with Image Picker

```
┌─────────────────────────────────────────────────────────────┐
│  Bot                                              [⚙️]      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                  ┌─────────────────────────────────────┐   │
│                  │ [📷 Image thumbnail]                │   │
│                  │ What plant is this?                 │   │
│                  └─────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🤖 **Lavandula angustifolia** (English Lavender)   │   │
│  │                                                     │   │
│  │    This is a common lavender plant, identifiable   │   │
│  │    by its purple flower spikes and grey-green      │   │
│  │    aromatic foliage.                               │   │
│  │                                                     │   │
│  │    Confidence: 92%                                 │   │
│  │    [📎 plant-classifier]                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [📷] [📸]  [  Ask about this image...           ]  [➤]   │
└─────────────────────────────────────────────────────────────┘
```

### Toxicity Warnings

When identifying potentially dangerous species, the bot includes safety warnings:

```dart
final toxicSpecies = [
  'amanita', 'death cap', 'destroying angel', 'fly agaric',
  'poison', 'deadly', 'toxic', 'hemlock', 'nightshade',
  'oleander', 'ricin', 'foxglove',
];

bool _checkIfToxic(String speciesName) {
  final lower = speciesName.toLowerCase();
  return toxicSpecies.any((t) => lower.contains(t));
}
```

## Content Crawling

### Crawler Architecture

The bot crawls all station app folders to extract metadata for RAG.

```
┌─────────────────────────────────────────────────────────────┐
│                    Content Crawler                          │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐  │
│  │  Places   │ │  Events   │ │  Alerts   │ │   Chat    │  │
│  │  Crawler  │ │  Crawler  │ │  Crawler  │ │  Crawler  │  │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘  │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐  │
│  │   Blog    │ │  Market   │ │   Media   │ │  Services │  │
│  │  Crawler  │ │  Crawler  │ │  Crawler  │ │  Crawler  │  │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘  │
└─────────────────────────────────────────────────────────────┘
                           ↓
                  CrawledContent objects
                           ↓
                    Index Service
                           ↓
                   Embeddings + Keywords
```

### Crawled Content Model

```dart
class CrawledContent {
  final String id;              // Unique identifier
  final String source;          // File path
  final ContentType type;       // places, events, alerts, chat, blog, etc.
  final String title;           // Extracted title
  final String content;         // Main text content
  final Map<String, dynamic> metadata; // Type-specific metadata
  final DateTime lastModified;
  final List<String> tags;      // Extracted tags/categories
  final GeoLocation? location;  // If applicable
  final String? author;         // Creator callsign
}

enum ContentType {
  place,
  event,
  alert,
  chat,
  blog,
  market,
  service,
  media,
  forum,
  news,
}
```

### App-Specific Crawlers

#### Places Crawler
```dart
/// Extracts from: places/{region}/{place}/place.txt
class PlaceCrawler extends BaseCrawler {
  @override
  Future<CrawledContent> crawl(String path) async {
    // Parse place.txt format
    // Extract: name, description, address, category, coordinates
    // Extract multilingual content
    // Count photos
  }
}
```

**Extracted metadata:**
- Name (multilingual)
- Description (multilingual)
- Address
- Coordinates (lat/lon)
- Category
- Phone, email, website
- Opening hours
- Photo count
- Like/comment counts

#### Events Crawler
```dart
/// Extracts from: events/{year}/{event}/event.txt
class EventCrawler extends BaseCrawler {
  @override
  Future<CrawledContent> crawl(String path) async {
    // Parse event.txt format
    // Extract: title, description, date, location, organizer
    // Parse schedule/agenda
    // Extract updates
  }
}
```

**Extracted metadata:**
- Title (multilingual)
- Description
- Date/time (start, end)
- Location (name + coordinates)
- Organizer
- Categories/tags
- Updates timeline
- Contributor count

#### Alerts Crawler
```dart
/// Extracts from: active/{region}/{alert}/report.txt
class AlertCrawler extends BaseCrawler {
  @override
  Future<CrawledContent> crawl(String path) async {
    // Parse report.txt format
    // Extract: title, type, status, description
    // Parse news timeline
    // Get verification count
  }
}
```

**Extracted metadata:**
- Title
- Alert type (traffic, weather, hazard, etc.)
- Status (active/expired)
- Coordinates
- Reported date
- Verification count
- News/update timeline

#### Chat Crawler
```dart
/// Extracts from: main/{year}/*.txt, chat/{room}/*.txt
class ChatCrawler extends BaseCrawler {
  @override
  Future<List<CrawledContent>> crawlRoom(String roomPath) async {
    // Parse chat files
    // Extract messages by date
    // Index public messages only
    // Group by topic/thread
  }
}
```

**Extracted metadata:**
- Room ID
- Message count
- Active participants
- Date range
- Key topics (extracted via keywords)

#### Media Crawler
```dart
/// Extracts metadata from images, audio, video
class MediaCrawler extends BaseCrawler {
  @override
  Future<CrawledContent> crawl(String path) async {
    // Extract EXIF data from images
    // Extract ID3 tags from audio
    // Extract metadata from video
  }
}
```

**Extracted metadata:**
- Filename, size, format
- EXIF: camera, date, GPS coordinates
- Dimensions, duration
- Associated app content (which place/event/etc.)

### Crawl Configuration

```
## CRAWL_SETTINGS
ENABLED_CRAWLERS: places, events, alerts, chat, blog, market
CRAWL_INTERVAL: 3600
INCLUDE_MEDIA_METADATA: true
MAX_CONTENT_AGE_DAYS: 365
EXCLUDE_PATHS: private/, drafts/
```

### Incremental Crawling

```dart
class ContentCrawlerService {
  /// Full crawl - scan all app folders
  Future<int> fullCrawl();

  /// Incremental crawl - only changed files since last crawl
  Future<int> incrementalCrawl();

  /// Watch for file changes (real-time indexing)
  Stream<CrawledContent> watchChanges();

  /// Get crawl statistics
  CrawlStats getStats();
}

class CrawlStats {
  final int totalDocuments;
  final Map<ContentType, int> byType;
  final DateTime lastCrawl;
  final Duration crawlDuration;
}
```

## Built-in Data Sources

### World Cities Database

The bot has access to a comprehensive world cities database (`assets/worldcities.csv`) containing ~45,000 cities with geographic and demographic data. This enables geographic queries without external API calls.

#### Database Schema

| Column | Type | Description |
|--------|------|-------------|
| `city` | string | City name (local script) |
| `city_ascii` | string | City name (ASCII only) |
| `lat` | float | Latitude |
| `lng` | float | Longitude |
| `country` | string | Country name |
| `iso2` | string | 2-letter country code |
| `iso3` | string | 3-letter country code |
| `admin_name` | string | Administrative region (state/province) |
| `capital` | string | Capital type: `primary`, `admin`, `minor`, or empty |
| `population` | int | City population |
| `id` | string | Unique identifier |

#### Sample Data

```csv
"city","city_ascii","lat","lng","country","iso2","iso3","admin_name","capital","population","id"
"Lisbon","Lisbon","38.7167","-9.1333","Portugal","PT","PRT","Lisboa","primary","2927000","1620619017"
"Porto","Porto","41.1496","-8.6109","Portugal","PT","PRT","Porto","admin","1312947","1620179135"
```

#### Supported Geographic Queries

The bot can answer the following types of questions using this database. For location-aware queries, the bot automatically obtains the user's GPS coordinates.

| Query Type | Example Questions |
|------------|-------------------|
| **Distance from me** | "How far are we to Porto?" |
| | "How far am I from Lisbon?" |
| | "What's the distance to Madrid?" |
| | "How many km to the nearest capital?" |
| **Distance between cities** | "How far is Lisbon from Porto?" |
| | "What's the distance between Tokyo and New York?" |
| | "Distance from London to Paris" |
| **Nearest City** | "What's the nearest city?" |
| | "What city am I closest to?" |
| | "Where am I?" |
| | "What city is closest to 38.7, -9.1?" |
| **City Info** | "Tell me about Tokyo" |
| | "What's the population of New York?" |
| | "Is Lisbon a capital city?" |
| **City Search** | "What cities are in Portugal?" |
| | "List capitals in Europe" |
| | "Show me cities with over 10 million people" |
| **Radius Search** | "What cities are within 100km of me?" |
| | "Find cities near me within 50km" |
| | "What cities are within 100km of Madrid?" |
| **Comparison** | "Which is bigger, London or Paris?" |
| | "Compare Tokyo and Seoul" |
| **Travel Context** | "How long to drive to Porto?" |
| | "Can I walk to the nearest city?" |
| **Places (from station)** | "Where is the nearest water fountain?" |
| | "Find cafes near me" |
| | "What restaurants are within 1km?" |
| | "Is there a pharmacy nearby?" |
| **Services (from station)** | "Where is the nearest mechanic?" |
| | "Find a plumber near me" |
| | "Who does electrical work in this area?" |
| | "Any hairdressers within 5km?" |
| **Alerts (from station)** | "Are there any alerts near me?" |
| | "What hazards are in this area?" |
| | "Any road closures nearby?" |

#### Geographic Utilities

```dart
class GeoService {
  /// Calculate distance between two coordinates (Haversine formula)
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371.0; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Find nearest city to given coordinates
  Future<City?> findNearestCity(double lat, double lng);

  /// Find cities within radius (km) of coordinates
  Future<List<City>> findCitiesWithinRadius(double lat, double lng, double radiusKm);

  /// Search cities by name (fuzzy match)
  Future<List<City>> searchCities(String query);

  /// Get cities by country
  Future<List<City>> getCitiesByCountry(String countryCode);

  /// Get current device location
  Future<(double lat, double lng)?> getCurrentLocation();
}
```

#### Location Access

The bot automatically obtains the user's current GPS location (with permission) for proximity queries. The location is fetched once per session or when explicitly requested.

**Example: Distance to a city**
```
User: "How far are we to Porto?"

Bot: Based on your current location near Lisbon (38.7223, -9.1393):

**Porto** is approximately **274 km** north of your current position.

Estimated travel times:
- By car: ~2h 45min (via A1)
- By train: ~2h 30min (Alfa Pendular)
```

**Example: Nearest city**
```
User: "What's the nearest city?"

Bot: Based on your current location (38.7223, -9.1393):

The nearest major city is **Lisbon, Portugal** (2.1 km away)

Other nearby cities:
- Amadora (8.3 km)
- Almada (9.7 km)
- Setúbal (45 km)
```

**Example: Where am I?**
```
User: "Where am I?"

Bot: Based on your GPS coordinates (38.7223, -9.1393):

You are in **Lisbon**, Portugal.
- District: Lisboa
- Country: Portugal (PT)
- Nearest landmark city: Lisbon (capital, pop. 2.9M)
```

**Example: Nearest place query**
```
User: "Where is the nearest water fountain?"

Bot: Based on your location and station places data:

**Nearest water fountain:** Jardim da Estrela Fountain (450m)
- Address: Praça da Estrela, Lisboa
- Status: Working
- [Directions →]

Other fountains nearby:
- Praça do Comércio Fountain (1.2 km)
- Parque das Nações Fountain (4.8 km)

[Sources: places/38.7_-9.1/...]
```

**Example: Nearest service query**
```
User: "Where is the nearest mechanic?"

Bot: Based on your location and station services:

**Nearest mechanic:** Auto Reparações Silva (800m)
- Phone: +351 912 345 678
- Services: General repairs, oil change, brakes
- Rating: 4.5/5 (23 reviews)
- Hours: Mon-Fri 9:00-18:00
- [Call] [Directions →]

Other mechanics nearby:
- Oficina Central (1.4 km) - Specializes in German cars
- Quick Fix Auto (2.1 km) - 24h emergency service

[Sources: services/38.7_-9.1/...]
```

**Example: Nearby alerts query**
```
User: "Are there any alerts near me?"

Bot: ⚠️ **2 active alerts** within 2km of your location:

1. **Road Work** (350m) - Av. da Liberdade
   - Lane closures until Jan 15
   - Expect delays 08:00-18:00

2. **Water Outage** (1.8 km) - Bairro Alto
   - Scheduled maintenance
   - Service restored by 17:00 today

[Sources: active/38.7_-9.1/...]
```

#### City Model

```dart
class City {
  final String name;
  final String nameAscii;
  final double latitude;
  final double longitude;
  final String country;
  final String iso2;
  final String iso3;
  final String adminName;
  final String capital;
  final int population;
  final String id;

  /// Calculate distance to another city
  double distanceTo(City other);

  /// Calculate distance from coordinates
  double distanceFrom(double lat, double lng);
}
```

#### Loading and Caching

```dart
class WorldCitiesService {
  List<City>? _cities;

  /// Load cities from CSV asset
  Future<void> initialize() async {
    final csvData = await rootBundle.loadString('assets/worldcities.csv');
    _cities = _parseCsv(csvData);
  }

  /// Get all cities (lazy load)
  Future<List<City>> getCities() async {
    if (_cities == null) await initialize();
    return _cities!;
  }

  /// Build spatial index for fast proximity queries
  void buildSpatialIndex();
}
```

### App-Specific Data Integration

The bot combines world cities data with station content for richer answers:

```
User: "What events are happening near Lisbon?"

Bot: Based on station data and your proximity to Lisbon:

**Events within 50km of Lisbon:**

1. **Community Market** (Sat 09:00) - Town Square, Cascais (25km)
2. **Live Music Night** (Sat 20:00) - Belém, Lisbon (3km)
3. **Beach Cleanup** (Sun 10:00) - Costa da Caparica (15km)

[Sources: events/2025/..., worldcities.csv]
```

## Data Indexing

### Hybrid Approach

The bot uses a two-tier indexing strategy optimized for storage and query speed:

```
┌─────────────────────────────────────────────────────────┐
│                    Query Flow                           │
├─────────────────────────────────────────────────────────┤
│  User Question                                          │
│       ↓                                                 │
│  1. Check Recent Index (semantic search)               │
│       ↓ (if confidence < 0.7)                          │
│  2. Check Archive Index (keyword match)                │
│       ↓ (if still low confidence)                      │
│  3. Scan Raw Files (last resort)                       │
│       ↓                                                 │
│  Ranked Results → Generate Response                    │
└─────────────────────────────────────────────────────────┘
```

### index/config.json

```json
{
  "version": "1.0",
  "last_updated": "2025-12-31T10:00:00Z",
  "recent_days": 7,
  "recent_documents": 1523,
  "archive_keywords": 45230,
  "indexed_apps": ["places", "events", "alerts", "chat", "blog"],
  "embedding_dim": 256,
  "reindex_interval_seconds": 3600
}
```

### Recent Index (index/recent/)

**embeddings.bin** (binary):
```
Header (16 bytes):
- Magic: "GIDX" (4 bytes)
- Version: uint16
- Embedding dim: uint16
- Document count: uint32
- Reserved: 4 bytes

Embeddings (sequential):
- For each document: [embedding_dim × float32]
```

**metadata.json**:
```json
{
  "documents": [
    {
      "id": 0,
      "source": "places/38.7_-9.1/cafe-landmark/place.txt",
      "type": "place",
      "title": "Landmark Cafe",
      "snippet": "Historic cafe in downtown...",
      "updated": "2025-12-30T15:30:00Z"
    },
    ...
  ]
}
```

### Archive Index (index/archive/)

**keywords.json** (inverted index):
```json
{
  "cafe": [0, 15, 42, 78],
  "restaurant": [0, 23, 56],
  "event": [5, 12, 89, 102, 156],
  "music": [12, 89, 203],
  ...
}
```

### Indexed Content Types

| App | Content Indexed | Fields |
|-----|-----------------|--------|
| Places | place.txt | name, description, address, category |
| Events | event.txt | title, description, date, location |
| Alerts | report.txt | title, description, type, status |
| Chat | messages | content (public rooms only) |
| Blog | post.md | title, content |

## Moderation System

### Classification Pipeline

```
Message
   ↓
┌──────────────┐
│  Tokenize    │
└──────┬───────┘
       ↓
┌──────────────┐
│   Embed      │
└──────┬───────┘
       ↓
┌──────────────┐
│  Classify    │ → Category + Confidence
└──────┬───────┘
       ↓
┌──────────────┐
│   Action     │ → Allow / Hide / Block
└──────────────┘
```

### Categories

| Category | Confidence Range | Action |
|----------|------------------|--------|
| SAFE | 0.0 - 0.3 | Allow through |
| SUSPICIOUS | 0.3 - 0.5 | Log, allow (borderline) |
| SPAM | 0.5 - 0.8 | Auto-hide, notify moderator |
| HARMFUL | 0.8 - 1.0 | Auto-hide, flag for review, consider block |

### Moderation Result

```dart
class ModerationResult {
  final ModerationCategory category;
  final double confidence;
  final String reason;
  final List<String> triggers;
  final ModerationAction action;
  final DateTime timestamp;
  final String messageId;
  final String author;
  final String room;
}

enum ModerationCategory { safe, suspicious, spam, harmful }
enum ModerationAction { allow, hide, hideAndNotify, hideAndBlock }
```

### Hidden Message Format

**moderation/hidden/{timestamp}_{room}_{author}.txt**:
```
# HIDDEN MESSAGE

TIMESTAMP: 2025-12-31 10:30_45
ROOM: marketplace
AUTHOR: Z9SPAM
CATEGORY: spam
CONFIDENCE: 0.85
REASON: Repeated promotional content with external links

## TRIGGERS
- repeated_text: 3 identical messages in 60s
- external_links: suspicious domain
- pattern: buy_now_urgency

## ORIGINAL_MESSAGE
BUY NOW!!! Best deals at example.com/spam
Limited time offer!!!
Don't miss out!!!

## MODERATOR_NOTES
(Space for human moderator to add notes)

--> reviewed_by: X1ABCD
--> reviewed_at: 2025-12-31 11:00_00
--> final_action: confirmed_spam
```

### Moderation Log Format

**moderation/log.txt**:
```
# MODERATION LOG

> 2025-12-31 10:30_45 -- BOT
ACTION: hide
ROOM: marketplace
AUTHOR: Z9SPAM
CATEGORY: spam
CONFIDENCE: 0.85
REASON: Repeated promotional content

> 2025-12-31 10:32_12 -- BOT
ACTION: allow
ROOM: main
AUTHOR: A1USER
CATEGORY: safe
CONFIDENCE: 0.12
REASON: Normal discussion message

> 2025-12-31 10:35_00 -- X1ABCD
ACTION: restore
ROOM: marketplace
AUTHOR: Z9SPAM
REASON: False positive - legitimate promotion
```

### Temporary Block Format

**moderation/blocked/{callsign}.txt**:
```
# BLOCKED USER

CALLSIGN: Z9SPAM
BLOCKED_AT: 2025-12-31 10:30_45
EXPIRES_AT: 2025-12-31 22:30_45
REASON: Repeated spam violations (3 hidden messages in 1 hour)
BLOCKED_BY: BOT

## VIOLATIONS
1. 2025-12-31 10:15_00 - spam (0.82) - marketplace
2. 2025-12-31 10:22_30 - spam (0.78) - events
3. 2025-12-31 10:30_45 - spam (0.85) - marketplace

## NOTES
Automatic 12-hour block after 3 spam violations
```

## Conversation Format

### User ↔ Bot Chat History

**conversations/{callsign}/history.txt**:
```
# BOT: Conversation with A1USER

> 2025-12-31 10:00_00 -- A1USER
What events are happening this weekend?

> 2025-12-31 10:00_02 -- BOT
Based on the station's event listings, here are upcoming weekend events:

1. **Community Market** (Saturday 09:00-14:00)
   Location: Town Square

2. **Live Music Night** (Saturday 20:00)
   Location: Central Park Amphitheater

3. **Sunday Brunch Meetup** (Sunday 11:00)
   Location: Landmark Cafe

Would you like more details about any of these events?
--> sources: events/2025/2025-01-04_community-market, events/2025/2025-01-04_live-music
--> model: micro
--> tokens_in: 8
--> tokens_out: 87
--> latency_ms: 1250

> 2025-12-31 10:00_15 -- A1USER
Tell me more about the music event

> 2025-12-31 10:00_18 -- BOT
**Live Music Night** - Saturday, January 4th at 20:00

Local bands will perform at the Central Park Amphitheater. Featured artists include:
- The Wavelengths (indie rock)
- Maria Santos Quartet (jazz)

Admission is free. Food trucks will be available on site.

The event organizer is Y2MUSIC. Contact them for more information.
--> sources: events/2025/2025-01-04_live-music/event.txt
--> model: micro
--> tokens_in: 6
--> tokens_out: 65
--> latency_ms: 980
```

## API Endpoints

### Bot Query Endpoint

```
POST /api/bot/query
Content-Type: application/json

Request:
{
  "query": "What events are happening this weekend?",
  "conversation_id": "A1USER",  // Optional, for context
  "max_tokens": 200,
  "include_sources": true
}

Response:
{
  "response": "Based on the station's event listings...",
  "sources": [
    {
      "type": "event",
      "path": "events/2025/2025-01-04_community-market",
      "title": "Community Market",
      "relevance": 0.92
    }
  ],
  "model_tier": "micro",
  "tokens_used": 95,
  "latency_ms": 1250
}
```

### Moderation Check Endpoint

```
POST /api/bot/moderate
Content-Type: application/json

Request:
{
  "message": "Check out my amazing deals!!!",
  "author": "Z9USER",
  "room": "marketplace"
}

Response:
{
  "category": "suspicious",
  "confidence": 0.45,
  "action": "allow",
  "triggers": ["promotional_language"],
  "reason": "Borderline promotional content"
}
```

### Index Status Endpoint

```
GET /api/bot/index/status

Response:
{
  "status": "ready",
  "last_updated": "2025-12-31T10:00:00Z",
  "recent_documents": 1523,
  "archive_keywords": 45230,
  "next_reindex": "2025-12-31T11:00:00Z"
}
```

### Reindex Endpoint

```
POST /api/bot/index/rebuild

Response:
{
  "status": "started",
  "estimated_duration_seconds": 120
}
```

## User Interface

### Navigation Integration

The Bot app appears as the **4th item** in the bottom navigation bar:

```
┌─────────────────────────────────────────────────────────────┐
│  Geogram                                        [≡] [🔔]    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                     [ Page Content ]                        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│   [📱]      [🗺️]      [📡]      [🤖]                        │
│   Apps       Map     Devices    Bot                         │
└─────────────────────────────────────────────────────────────┘
```

**Navigation Changes (lib/main.dart):**

| Change | Location | Description |
|--------|----------|-------------|
| Add BotPage import | Top of file | `import 'pages/bot_page.dart';` |
| Add to _pages array | Line ~388 | `BotPage()` at index 3 |
| Add NavigationDestination | Line ~886 | Icon + label for Bot |
| Update selectedIndex constraint | Line ~880 | Change `< 3` to `< 4` |

**Icon:** `Icons.smart_toy` (outlined when unselected, filled when selected)

### Bot Page Design

The Bot page provides a chat interface for interacting with the AI assistant:

```
┌─────────────────────────────────────────────────────────────┐
│  Bot                                              [⚙️]      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🤖 Hello! I'm your station assistant. Ask me about  │   │
│  │    places, events, alerts, or anything on this      │   │
│  │    station.                                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│                  ┌─────────────────────────────────────┐   │
│                  │ What events are happening           │   │
│                  │ this weekend?                       │   │
│                  └─────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🤖 Based on the station data, here are upcoming     │   │
│  │    weekend events:                                  │   │
│  │                                                     │   │
│  │    1. Community Market (Sat 09:00-14:00)           │   │
│  │    2. Live Music Night (Sat 20:00)                 │   │
│  │    3. Sunday Brunch Meetup (Sun 11:00)             │   │
│  │                                                     │   │
│  │    [📎 Sources: events/2025/...]                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [🎤]  [  Type your question...                    ]  [➤]  │
└─────────────────────────────────────────────────────────────┘
```

**Page Components:**

| Component | Description |
|-----------|-------------|
| AppBar | Title "Bot" + settings icon (gear) |
| Message List | Scrollable list of bot/user messages |
| Bot Message | Left-aligned, with robot icon, optional sources |
| User Message | Right-aligned, user's input |
| Input Area | Microphone button + text field + send button |

**Message Widget States:**

| State | Visual |
|-------|--------|
| User message | Right-aligned bubble, primary color |
| Bot message | Left-aligned bubble with 🤖 icon |
| Bot typing | Left-aligned with animated dots (...) |
| Error | Red tinted bubble with error message |
| Sources | Collapsed chip, expandable to show file paths |

### Bot Settings Page Design

Accessed via the gear icon in the Bot page AppBar:

```
┌─────────────────────────────────────────────────────────────┐
│  ←  Bot Settings                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  MODEL SELECTION                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Current: Qwen2.5-1.5B-Instruct (1.2 GB)             │   │
│  │ Status: ✓ Loaded                                    │   │
│  │                                                     │   │
│  │ [Change Model ▼]                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  VOICE INPUT                                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Whisper Model          [tiny (75 MB) ▼]             │   │
│  │ Enable voice input                         [ON]     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  FEATURES                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Auto-moderation                            [ON]     │   │
│  │ Background indexing                        [ON]     │   │
│  │ Index interval           [30 minutes ▼]             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  INDEX STATUS                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Documents indexed: 1,523                            │   │
│  │ Last indexed: 10 minutes ago                        │   │
│  │                                                     │   │
│  │ [Rebuild Index]                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ALERT PROXIMITY                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Enable proximity alerts                    [ON]     │   │
│  │ Alert distance            [500 meters ▼]            │   │
│  │ Alert types               [All ▼]                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  STORAGE                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Models: 1.8 GB                                      │   │
│  │ Index: 45 MB                                        │   │
│  │ Conversations: 2.3 MB                               │   │
│  │                                                     │   │
│  │ [Clear Cache]                                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Settings Sections:**

| Section | Controls |
|---------|----------|
| Model Selection | Dropdown to choose LLM, shows size + status |
| Voice Input | Whisper model dropdown, enable/disable toggle |
| Features | Auto-moderation toggle, background indexing toggle, interval selector |
| Index Status | Document count, last indexed time, rebuild button |
| Alert Proximity | Enable/disable toggle, distance threshold (100-1000m), alert type filter |
| Storage | Disk usage breakdown, clear cache button |

### Background Indexing Service

The bot uses a `Timer.periodic()` pattern consistent with other services in the codebase:

```dart
class BotIndexService {
  Timer? _indexTimer;
  bool _isIndexing = false;
  DateTime? _lastIndexTime;

  // Default: index every 30 minutes when app is idle
  static const Duration _defaultIndexInterval = Duration(minutes: 30);
  Duration _indexInterval = _defaultIndexInterval;

  /// Start background indexing timer
  void startBackgroundIndexing() {
    _indexTimer?.cancel();
    _indexTimer = Timer.periodic(_indexInterval, (_) {
      if (_shouldIndex()) {
        incrementalIndex();
      }
    });
    LogService().log('BotIndexService: Background indexing started (interval: $_indexInterval)');
  }

  /// Stop background indexing
  void stopBackgroundIndexing() {
    _indexTimer?.cancel();
    _indexTimer = null;
    LogService().log('BotIndexService: Background indexing stopped');
  }

  /// Check if indexing should run
  bool _shouldIndex() {
    // Don't index if already indexing
    if (_isIndexing) return false;

    // Don't index if app is actively being used
    if (!_isAppIdle()) return false;

    // Don't index too frequently
    if (_lastIndexTime != null) {
      final elapsed = DateTime.now().difference(_lastIndexTime!);
      if (elapsed < _indexInterval) return false;
    }

    return true;
  }

  /// Check if app is idle (user not actively using)
  bool _isAppIdle() {
    // Check app lifecycle state
    // Check if user is interacting with UI
    // Check if device is on battery saver
    return true; // Simplified
  }

  /// Perform incremental index update
  Future<void> incrementalIndex() async {
    if (_isIndexing) return;

    _isIndexing = true;
    try {
      // Get files modified since last index
      final changedFiles = await _getChangedFiles(_lastIndexTime);

      // Crawl and re-index changed files
      for (final file in changedFiles) {
        await _indexFile(file);
      }

      _lastIndexTime = DateTime.now();
      LogService().log('BotIndexService: Indexed ${changedFiles.length} files');
    } finally {
      _isIndexing = false;
    }
  }

  /// Update index interval from settings
  void setIndexInterval(Duration interval) {
    _indexInterval = interval;
    // Restart timer with new interval
    if (_indexTimer != null) {
      startBackgroundIndexing();
    }
  }
}
```

### Alert Proximity Monitor

The bot includes a separate background service that monitors the user's location and warns when approaching active alerts. This runs more frequently than indexing (every 30 seconds when location is available).

```dart
class AlertProximityService {
  Timer? _locationTimer;
  final Set<String> _notifiedAlerts = {}; // Alert IDs already notified

  // Proximity threshold for alert notifications
  static const double _alertProximityMeters = 500.0;

  // Check location every 30 seconds
  static const Duration _checkInterval = Duration(seconds: 30);

  /// Start monitoring location for nearby alerts
  void startMonitoring() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(_checkInterval, (_) {
      _checkNearbyAlerts();
    });
    LogService().log('AlertProximityService: Started monitoring');
  }

  /// Stop monitoring
  void stopMonitoring() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  /// Check for alerts within proximity threshold
  Future<void> _checkNearbyAlerts() async {
    // Get current location
    final location = await GeoService().getCurrentLocation();
    if (location == null) return;

    final (lat, lng) = location;

    // Get all active alerts from index
    final activeAlerts = await _getActiveAlerts();

    for (final alert in activeAlerts) {
      // Skip if already notified
      if (_notifiedAlerts.contains(alert.id)) continue;

      // Calculate distance to alert
      final distance = GeoService().calculateDistance(
        lat, lng,
        alert.latitude, alert.longitude,
      );

      // Convert to meters
      final distanceMeters = distance * 1000;

      // Check if within proximity threshold
      if (distanceMeters <= _alertProximityMeters) {
        await _notifyAlert(alert, distanceMeters);
        _notifiedAlerts.add(alert.id);
      }
    }
  }

  /// Send notification for nearby alert
  Future<void> _notifyAlert(Alert alert, double distanceMeters) async {
    final distanceText = distanceMeters < 100
        ? '${distanceMeters.round()}m'
        : '${(distanceMeters / 100).round() * 100}m';

    await NotificationService().showNotification(
      title: '⚠️ Alert nearby: ${alert.title}',
      body: '${alert.type} - $distanceText away\n${alert.description}',
      payload: 'alert:${alert.id}',
      channelId: 'bot_alerts',
      importance: Importance.high,
    );

    LogService().log('AlertProximityService: Notified user of ${alert.id} at $distanceText');
  }

  /// Clear notification history (e.g., when user leaves area)
  void clearNotificationHistory() {
    _notifiedAlerts.clear();
  }

  /// Remove specific alert from history (e.g., when alert expires)
  void removeFromHistory(String alertId) {
    _notifiedAlerts.remove(alertId);
  }
}
```

#### Alert Proximity Configuration

```
## ALERT_PROXIMITY
ENABLED: true
DISTANCE_METERS: 500
CHECK_INTERVAL_SECONDS: 30
NOTIFY_ONCE: true
ALERT_TYPES: traffic, hazard, weather, emergency
```

| Setting | Default | Description |
|---------|---------|-------------|
| `ENABLED` | `true` | Enable/disable proximity alerts |
| `DISTANCE_METERS` | `500` | Distance threshold for notifications |
| `CHECK_INTERVAL_SECONDS` | `30` | How often to check location |
| `NOTIFY_ONCE` | `true` | Only notify once per alert |
| `ALERT_TYPES` | all | Which alert types to monitor |

#### Notification Example

When user approaches an alert within 500m:

```
┌─────────────────────────────────────────┐
│ ⚠️ Alert nearby: Road Work              │
│                                         │
│ Construction - 350m away                │
│ Lane closures on Av. da Liberdade       │
│ until Jan 15. Expect delays.            │
│                                         │
│ [View Alert]  [Dismiss]                 │
└─────────────────────────────────────────┘
```

#### Notification Storage

Notified alerts are persisted to avoid duplicate notifications:

**bot/proximity_notifications.json:**
```json
{
  "notified_alerts": [
    {
      "alert_id": "alert_2025-01-02_roadwork_av-liberdade",
      "notified_at": "2025-01-02T14:30:00Z",
      "distance_meters": 345,
      "location": [38.7223, -9.1393]
    }
  ],
  "last_check": "2025-01-02T14:35:00Z"
}
```

### Bot Actions & Commands

The bot can execute actions beyond answering questions, including modifying settings and navigating to specific UI panels.

#### Action Types

| Action Type | Description | Example Commands |
|-------------|-------------|------------------|
| **Navigate** | Open a specific page or panel | "Open settings", "Show the map" |
| **Open Chat** | Open chat with specific user | "I want to talk with Joe Rogan" |
| **Open Place** | Show place details | "Show me Landmark Cafe" |
| **Open Event** | Show event details | "Open the music festival event" |
| **Open Alert** | Show alert details | "Show me that road work alert" |
| **Modify Setting** | Change app or system setting | "Enable dark mode" |
| **Toggle Feature** | Enable/disable a feature | "Turn off notifications" |

#### Settings Control

The bot can read and modify settings through natural language:

**Example: Query settings**
```
User: "What are my notification settings?"

Bot: Here are your current notification settings:

- Notifications: **Enabled**
- Sound: **Enabled**
- Vibration: **Enabled**
- New messages: **Enabled**
- Nearby alerts: **Enabled** (500m)

Would you like to change any of these?
```

**Example: Modify settings**
```
User: "Disable notification sounds"

Bot: ✓ Notification sounds have been **disabled**.

Your updated settings:
- Notifications: Enabled
- Sound: **Disabled** ← Changed
- Vibration: Enabled
```

**Example: App-specific settings**
```
User: "Change the map to satellite view"

Bot: ✓ Map view changed to **satellite**.

[The map page will update when you open it]
```

#### Supported Settings Commands

| Category | Commands |
|----------|----------|
| **Notifications** | "Enable/disable notifications" |
| | "Turn on/off sound" |
| | "Mute vibration" |
| | "Set alert distance to 1km" |
| **Appearance** | "Enable dark mode" |
| | "Switch to light theme" |
| | "Increase font size" |
| **Map** | "Change to satellite view" |
| | "Show/hide traffic" |
| | "Enable offline maps" |
| **Privacy** | "Hide my location" |
| | "Enable/disable analytics" |
| **Bot** | "Change AI model to small" |
| | "Disable auto-moderation" |
| | "Set index interval to 1 hour" |

#### UI Navigation

The bot can open specific pages and panels:

**Example: Open chat with user**
```
User: "I want to talk with Joe Rogan"

Bot: Opening chat with **Joe Rogan** (JR1234)...

[Action: Navigate to DirectMessagePage(callsign: "JR1234")]
```

**Example: Open place**
```
User: "Show me the Landmark Cafe"

Bot: Opening **Landmark Cafe**...

[Action: Navigate to PlaceDetailPage(placeId: "38.7_-9.1/landmark-cafe")]
```

**Example: Open settings panel**
```
User: "Open notification settings"

Bot: Opening notification settings...

[Action: Navigate to SettingsPage(section: "notifications")]
```

#### Navigation Commands

| Command Pattern | Action |
|-----------------|--------|
| "Open settings" | Navigate to SettingsPage |
| "Show the map" | Navigate to MapsBrowserPage |
| "Go to devices" | Navigate to DevicesBrowserPage |
| "Open apps" | Navigate to CollectionsPage |
| "Talk to {name}" | Navigate to DirectMessagePage |
| "Chat with {name}" | Navigate to DirectMessagePage |
| "Message {callsign}" | Navigate to DirectMessagePage |
| "Show {place name}" | Navigate to PlaceDetailPage |
| "Open {event name}" | Navigate to EventDetailPage |
| "View alert {title}" | Navigate to AlertDetailPage |
| "Open chat room {name}" | Navigate to ChatRoomPage |
| "Show my profile" | Navigate to ProfilePage |
| "Open bot settings" | Navigate to BotSettingsPage |

#### Action Execution Model

```dart
abstract class BotAction {
  final String description;
  Future<void> execute(BuildContext context);
}

class NavigateAction extends BotAction {
  final String routeName;
  final Map<String, dynamic> arguments;

  @override
  Future<void> execute(BuildContext context) async {
    Navigator.pushNamed(context, routeName, arguments: arguments);
  }
}

class ModifySettingAction extends BotAction {
  final String settingKey;
  final dynamic newValue;

  @override
  Future<void> execute(BuildContext context) async {
    await SettingsService().set(settingKey, newValue);
  }
}

class BotResponse {
  final String text;
  final List<String> sources;
  final BotAction? action; // Optional action to execute
}
```

#### User Lookup for Chat Navigation

When user says "talk to Joe Rogan", the bot needs to find the matching user:

```dart
class UserLookupService {
  /// Find user by name (fuzzy match against profiles)
  Future<UserProfile?> findUserByName(String name) async {
    // Search local contacts
    // Search station profiles
    // Return best match or null
  }

  /// Find user by callsign (exact match)
  Future<UserProfile?> findUserByCallsign(String callsign);

  /// Get recent conversations for suggestions
  Future<List<UserProfile>> getRecentContacts();
}
```

**Example: Ambiguous user lookup**
```
User: "Message John"

Bot: I found multiple users named John:

1. **John Smith** (JS1234) - Last chat: 2 days ago
2. **John Doe** (JD5678) - Last chat: 1 week ago
3. **Johnny B** (JB9012) - Never chatted

Which John would you like to message?
```

#### Permission Checks

Before executing actions, the bot verifies permissions:

```dart
class ActionPermissionService {
  /// Check if action is allowed
  Future<bool> canExecute(BotAction action) async {
    // Check if setting is user-modifiable
    // Check if navigation target exists
    // Check if user has permission to access target
    return true;
  }

  /// Get reason if action is denied
  String? getDenialReason(BotAction action);
}
```

**Example: Permission denied**
```
User: "Disable all moderation"

Bot: ⚠️ I can't disable moderation completely - that setting is
controlled by station administrators.

I can adjust these moderation settings for you:
- Change moderation sensitivity
- Adjust spam thresholds
- Modify your exempt users list

Would you like to change any of these instead?
```

**Index Interval Options:**

| Setting | Duration | Use Case |
|---------|----------|----------|
| 15 minutes | `Duration(minutes: 15)` | Active stations with frequent updates |
| 30 minutes | `Duration(minutes: 30)` | Default, balanced |
| 1 hour | `Duration(hours: 1)` | Low-traffic stations |
| 2 hours | `Duration(hours: 2)` | Battery-constrained devices |
| Manual only | Disabled | User triggers index manually |

### Language Strings

**languages/en_US.json:**

```json
{
  "bot": "Bot",
  "bot_settings": "Bot Settings",
  "bot_greeting": "Hello! I'm your station assistant. Ask me about places, events, alerts, or anything on this station.",
  "bot_model": "AI Model",
  "bot_model_select": "Select Model",
  "bot_model_current": "Current",
  "bot_model_status": "Status",
  "bot_model_loaded": "Loaded",
  "bot_model_loading": "Loading...",
  "bot_model_not_loaded": "Not loaded",
  "bot_model_downloading": "Downloading...",
  "bot_voice_input": "Voice Input",
  "bot_whisper_model": "Whisper Model",
  "bot_enable_voice": "Enable voice input",
  "bot_features": "Features",
  "bot_auto_moderation": "Auto-moderation",
  "bot_background_indexing": "Background Indexing",
  "bot_index_interval": "Index Interval",
  "bot_index_status": "Index Status",
  "bot_documents_indexed": "Documents indexed",
  "bot_last_indexed": "Last indexed",
  "bot_rebuild_index": "Rebuild Index",
  "bot_rebuilding_index": "Rebuilding index...",
  "bot_storage": "Storage",
  "bot_storage_models": "Models",
  "bot_storage_index": "Index",
  "bot_storage_conversations": "Conversations",
  "bot_clear_cache": "Clear Cache",
  "bot_clear_cache_confirm": "Clear all bot cache data?",
  "bot_ask_placeholder": "Type your question...",
  "bot_sources": "Sources",
  "bot_error_model_load": "Failed to load model",
  "bot_error_generation": "Failed to generate response",
  "bot_minutes_ago": "{count} minutes ago",
  "bot_hours_ago": "{count} hours ago",
  "bot_just_now": "Just now",
  "bot_interval_15min": "15 minutes",
  "bot_interval_30min": "30 minutes",
  "bot_interval_1hour": "1 hour",
  "bot_interval_2hours": "2 hours",
  "bot_interval_manual": "Manual only",
  "bot_location_permission": "Location permission needed for nearby queries",
  "bot_location_unavailable": "Unable to get current location",
  "bot_nearest_city": "Nearest city",
  "bot_distance_km": "{distance} km",
  "bot_distance_m": "{distance} m",
  "bot_population": "Population",
  "bot_country": "Country",
  "bot_capital": "Capital",
  "bot_no_cities_found": "No cities found matching your query",
  "bot_no_places_found": "No places found matching your query",
  "bot_no_services_found": "No services found matching your query",
  "bot_alert_proximity": "Alert Proximity",
  "bot_alert_proximity_enabled": "Enable proximity alerts",
  "bot_alert_proximity_distance": "Alert distance",
  "bot_alert_proximity_meters": "{distance} meters",
  "bot_alert_nearby": "Alert nearby",
  "bot_alert_away": "{distance} away",
  "bot_view_alert": "View Alert",
  "bot_dismiss": "Dismiss",
  "bot_opening": "Opening {name}...",
  "bot_setting_changed": "{setting} has been {action}",
  "bot_enabled": "enabled",
  "bot_disabled": "disabled",
  "bot_multiple_matches": "I found multiple matches",
  "bot_which_one": "Which one would you like?",
  "bot_no_user_found": "I couldn't find a user named {name}",
  "bot_permission_denied": "I can't change that setting",
  "bot_last_chat": "Last chat",
  "bot_never_chatted": "Never chatted",
  "bot_open_settings": "Open settings",
  "bot_open_chat": "Open chat",
  "bot_show_map": "Show map",
  "bot_show_profile": "Show profile"
}
```

**languages/pt_PT.json:**

```json
{
  "bot": "Bot",
  "bot_settings": "Definições do Bot",
  "bot_greeting": "Olá! Sou o assistente da estação. Pergunte-me sobre locais, eventos, alertas ou qualquer coisa nesta estação.",
  "bot_model": "Modelo IA",
  "bot_model_select": "Selecionar Modelo",
  "bot_model_current": "Atual",
  "bot_model_status": "Estado",
  "bot_model_loaded": "Carregado",
  "bot_model_loading": "A carregar...",
  "bot_model_not_loaded": "Não carregado",
  "bot_model_downloading": "A descarregar...",
  "bot_voice_input": "Entrada de Voz",
  "bot_whisper_model": "Modelo Whisper",
  "bot_enable_voice": "Ativar entrada de voz",
  "bot_features": "Funcionalidades",
  "bot_auto_moderation": "Auto-moderação",
  "bot_background_indexing": "Indexação em Segundo Plano",
  "bot_index_interval": "Intervalo de Indexação",
  "bot_index_status": "Estado do Índice",
  "bot_documents_indexed": "Documentos indexados",
  "bot_last_indexed": "Última indexação",
  "bot_rebuild_index": "Reconstruir Índice",
  "bot_rebuilding_index": "A reconstruir índice...",
  "bot_storage": "Armazenamento",
  "bot_storage_models": "Modelos",
  "bot_storage_index": "Índice",
  "bot_storage_conversations": "Conversas",
  "bot_clear_cache": "Limpar Cache",
  "bot_clear_cache_confirm": "Limpar todos os dados de cache do bot?",
  "bot_ask_placeholder": "Escreva a sua pergunta...",
  "bot_sources": "Fontes",
  "bot_error_model_load": "Falha ao carregar modelo",
  "bot_error_generation": "Falha ao gerar resposta",
  "bot_minutes_ago": "há {count} minutos",
  "bot_hours_ago": "há {count} horas",
  "bot_just_now": "Agora mesmo",
  "bot_interval_15min": "15 minutos",
  "bot_interval_30min": "30 minutos",
  "bot_interval_1hour": "1 hora",
  "bot_interval_2hours": "2 horas",
  "bot_interval_manual": "Apenas manual",
  "bot_location_permission": "Permissão de localização necessária para consultas próximas",
  "bot_location_unavailable": "Não foi possível obter a localização atual",
  "bot_nearest_city": "Cidade mais próxima",
  "bot_distance_km": "{distance} km",
  "bot_distance_m": "{distance} m",
  "bot_population": "População",
  "bot_country": "País",
  "bot_capital": "Capital",
  "bot_no_cities_found": "Nenhuma cidade encontrada para a sua pesquisa",
  "bot_no_places_found": "Nenhum local encontrado para a sua pesquisa",
  "bot_no_services_found": "Nenhum serviço encontrado para a sua pesquisa",
  "bot_alert_proximity": "Proximidade de Alertas",
  "bot_alert_proximity_enabled": "Ativar alertas de proximidade",
  "bot_alert_proximity_distance": "Distância de alerta",
  "bot_alert_proximity_meters": "{distance} metros",
  "bot_alert_nearby": "Alerta próximo",
  "bot_alert_away": "a {distance}",
  "bot_view_alert": "Ver Alerta",
  "bot_dismiss": "Dispensar",
  "bot_opening": "A abrir {name}...",
  "bot_setting_changed": "{setting} foi {action}",
  "bot_enabled": "ativado",
  "bot_disabled": "desativado",
  "bot_multiple_matches": "Encontrei várias correspondências",
  "bot_which_one": "Qual pretende?",
  "bot_no_user_found": "Não encontrei um utilizador chamado {name}",
  "bot_permission_denied": "Não posso alterar essa definição",
  "bot_last_chat": "Última conversa",
  "bot_never_chatted": "Nunca conversou",
  "bot_open_settings": "Abrir definições",
  "bot_open_chat": "Abrir conversa",
  "bot_show_map": "Mostrar mapa",
  "bot_show_profile": "Mostrar perfil"
}
```

### Files to Create

| File | Purpose |
|------|---------|
| `lib/pages/bot_page.dart` | Main Bot chat interface |
| `lib/pages/bot_settings_page.dart` | Model selection, feature toggles |
| `lib/bot/services/bot_index_service.dart` | Background indexing with Timer.periodic |
| `lib/bot/services/alert_proximity_service.dart` | Alert proximity monitoring (500m threshold) |
| `lib/bot/services/geo_service.dart` | Geographic utilities (Haversine, city lookup) |
| `lib/bot/services/world_cities_service.dart` | World cities database access |
| `lib/bot/services/bot_action_service.dart` | Execute bot actions (navigate, modify settings) |
| `lib/bot/services/user_lookup_service.dart` | Find users by name for chat navigation |
| `lib/bot/models/bot_action.dart` | Action classes (NavigateAction, ModifySettingAction) |
| `lib/widgets/bot_chat_widget.dart` | Chat message bubble widget |
| `lib/widgets/bot_input_widget.dart` | Text/voice input widget |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/main.dart` | Add BotPage to navigation |
| `languages/en_US.json` | Add bot-related strings |
| `languages/pt_PT.json` | Add bot-related strings |
| `lib/services/chat_service.dart` | Add moderation hook |

### Implementation Order

1. **Language strings** - Add to en_US.json and pt_PT.json
2. **Bot page** - Create basic chat UI (`lib/pages/bot_page.dart`)
3. **Bot settings page** - Create settings UI (`lib/pages/bot_settings_page.dart`)
4. **Index service** - Create background indexing (`lib/bot/services/bot_index_service.dart`)
5. **Navigation** - Add Bot to bottom nav in `lib/main.dart`
6. **Chat widgets** - Create message bubbles and input (`lib/widgets/bot_*.dart`)
7. **LLM integration** - Wire up to llm_toolkit service

## Hardware Detection

### Resource Detection

```dart
class HardwareInfo {
  final int totalRamMB;
  final int availableRamMB;
  final int cpuCores;
  final bool isServer;  // Detected via platform
  final String platform; // android, ios, linux, windows, macos, web
}

Future<HardwareInfo> detectHardware() async {
  // Platform-specific implementation
  // Falls back to conservative estimates if unavailable
}
```

### Platform Considerations

| Platform | RAM Detection | CPU Detection | Notes |
|----------|---------------|---------------|-------|
| Android | Available | Limited | Use system info APIs |
| iOS | Limited | Limited | Memory warnings only |
| Linux | Full | Full | /proc/meminfo, nproc |
| Windows | Full | Full | Win32 APIs |
| macOS | Full | Full | sysctl |
| Web | None | None | Use smallest model |

## Performance Targets

### Latency Targets (by operation)

| Operation | Nano | Micro | Small | Base |
|-----------|------|-------|-------|------|
| Tokenize 100 chars | <5ms | <5ms | <5ms | <5ms |
| Embed sentence | <10ms | <50ms | <200ms | <500ms |
| Classify (moderation) | <20ms | <100ms | <300ms | <1s |
| Generate 50 tokens | N/A | <2s | <5s | <15s |
| Index 1000 docs | <1s | <5s | <10s | <30s |

### Memory Targets

| Model | Peak RAM | Sustained RAM |
|-------|----------|---------------|
| Nano | <100MB | <50MB |
| Micro | <300MB | <200MB |
| Small | <700MB | <500MB |
| Base | <2GB | <1.5GB |

## Security Considerations

### Data Privacy

- All processing occurs locally - no external API calls
- Conversation history stored locally per user
- Index contains only public/accessible data
- No cross-user data leakage

### Moderation Safety

- Exempt users list to prevent false positives on admins
- Human review available for all moderation decisions
- Appeal mechanism via moderator restore action
- Audit trail in moderation log

### Model Security

- Model weights verified by checksum
- No code execution from model outputs
- Input sanitization before tokenization
- Output length limits enforced

## Error Handling

### Error Codes

| Code | Description | Recovery |
|------|-------------|----------|
| BOT_MODEL_NOT_FOUND | Model file missing | Download or use lower tier |
| BOT_MODEL_CORRUPT | Checksum mismatch | Re-download model |
| BOT_INDEX_STALE | Index too old | Trigger reindex |
| BOT_OOM | Out of memory | Use lower tier model |
| BOT_TOKENIZER_ERROR | Tokenization failed | Use fallback tokenizer |

### Graceful Degradation

```
Model Load Failed → Try lower tier → Disable bot if all fail
Index Corrupt → Rebuild index → Use keyword-only search
Moderation Error → Log error → Allow message through
Generation Timeout → Return partial → Suggest retry
```

## Best Practices

### Configuration

1. Start with `MODEL_TIER: auto` and adjust based on performance
2. Set `MODERATION_THRESHOLDS` conservatively at first
3. Include station admins in `EXEMPT_USERS`
4. Monitor `moderation/log.txt` for false positives

### Performance

1. Keep `RECENT_DAYS` under 14 for mobile devices
2. Run reindex during low-activity periods
3. Use `nano` tier for moderation-only deployments
4. Clear old conversations periodically

### Moderation

1. Review hidden messages regularly
2. Adjust thresholds based on false positive rate
3. Use `EXEMPT_USERS` for trusted contributors
4. Document moderation decisions in log

## Related Documentation

- [Chat Format Specification](./chat-format-specification.md) - Chat message format
- [API Feedback Specification](../API_feedback.md) - Centralized feedback system
- [Place Format Specification](./place-format-specification.md) - Place data format
- [Event Format Specification](./event-format-specification.md) - Event data format

## Change Log

### v1.4 (2025-12-31)
- Added Vision / Image Recognition section with full documentation
- Added Vision model tiers (Lite, Standard, Quality, Premium)
- Added VisionResult, DetectedObject, SpeciesIdentification models
- Added VisionService, VisionModelManager, TFLiteService services
- Added vision model download/management in BotSettingsPage
- Added image picker (gallery + camera) in BotPage
- Added plant/mushroom identification with toxicity warnings
- Added text extraction and translation (OCR) capabilities
- Added Debug API integration for internal commands
- Added EventBus integration for real-time updates
- Added vision-related language strings (en_US.json, pt_PT.json)

### v1.3 (2025-12-31)
- Added App Availability section clarifying Bot is a default app (not from "Add" menu)
- Added Data Storage section with `bot/` folder structure overview
- Clarified that Bot data folder is created automatically on first use

### v1.2 (2025-12-31)
- Added User Interface section with navigation integration details
- Added Bot page chat UI design with ASCII wireframes
- Added Bot settings page design (model selection, voice, features, storage, alert proximity)
- Added background indexing service pattern using Timer.periodic()
- Added language strings for en_US.json and pt_PT.json
- Added files to create/modify list and implementation order
- Added Built-in Data Sources section with World Cities database
- Added geographic query capabilities (distance, nearest city, radius search)
- Added GeoService and WorldCitiesService code examples
- Added automatic location access for proximity queries
- Added language strings for geographic features
- Added Places/Services proximity queries ("Where is the nearest mechanic?")
- Added Alert Proximity Monitor service (500m threshold notifications)
- Added alert proximity configuration options (distance, types, notify once)
- Added notification persistence to avoid duplicate alerts
- Added conversational location queries ("How far are we to Porto?")
- Added Bot Actions & Commands section for settings control and UI navigation
- Added settings modification via natural language ("Enable dark mode", "Disable sounds")
- Added UI navigation commands ("I want to talk with Joe Rogan", "Open settings")
- Added UserLookupService for fuzzy name matching when opening chats
- Added action execution model (NavigateAction, ModifySettingAction)
- Added permission checks for sensitive settings
- Added language strings for bot actions

### v1.1 (2025-12-31)
- **Major revision**: Use existing libraries instead of custom implementation
- Added llm_toolkit, flutter_llama, llama_cpp as recommended packages
- Added Whisper integration for voice input (whisper_flutter_new)
- Added HuggingFace model support (GGUF format)
- Added comprehensive content crawling system for all apps
- Added app-specific crawlers (places, events, alerts, chat, blog, market, media)
- Added model recommendations by device type
- Removed custom transformer engine (use libraries instead)
- Removed custom model format (use GGUF)

### v1.0 (2025-12-31)
- Initial specification
- Pure Dart transformer architecture (superseded in v1.1)
- Four model tiers (nano/micro/small/base)
- Hybrid data indexing (semantic + keyword)
- Auto-moderation with human oversight
- Conversation history format
- API endpoint definitions
