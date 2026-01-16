# Text-to-Voice Integration with Supertonic

## Overview

Integrate [Supertonic](https://github.com/supertone-inc/supertonic), a lightning-fast on-device text-to-speech (TTS) system, into Geogram. This enables offline voice synthesis with complete privacy.

**Key Benefits:**
- **Speed**: Up to 167x faster than real-time on consumer hardware
- **Offline**: No cloud APIs, zero latency, full privacy
- **Lightweight**: 66M parameters, optimized for edge deployment
- **Multi-language**: English, Korean, Spanish, Portuguese, French

## Current State

Geogram already has:
- `flutter_onnxruntime: ^1.6.1` - Required for Supertonic inference
- `just_audio: ^0.9.36` - Audio playback (non-Linux)
- `AudioService` - Existing audio recording/playback service
- `I18nService` - Language selection (en_US, pt_PT)
- `WhisperModelManager` - Reference pattern for model downloads
- Console command system in `lib/cli/console_handler.dart`

## Language Matching

Supertonic voices will automatically match Geogram's selected language:

| Geogram Language | Supertonic Language |
|------------------|---------------------|
| `en_US` | `en` (English) |
| `pt_PT` | `pt` (Portuguese) |

```dart
String _getTtsLanguage() {
  final lang = I18nService().currentLanguage;
  switch (lang) {
    case 'pt_PT': return 'pt';
    case 'en_US':
    default: return 'en';
  }
}
```

## Model Download Architecture

Following the Whisper pattern: **Station server downloads from HuggingFace, clients download from station.**

### Station Server Flow

```
Station Startup
    ↓
_downloadSupertonic() in station_server_service.dart
    ↓
Download from HuggingFace: huggingface.co/Supertone/supertonic-2
    ↓
Store in: {STATION_BASE_DIR}/bot/models/supertonic/
    ↓
Serve via HTTP: /bot/models/supertonic/{filename}
```

### Client Flow

```
TtsService.load()
    ↓
TtsModelManager.ensureModel()
    ↓
Check local: {CLIENT_BASE_DIR}/bot/models/supertonic/
    ↓
If missing → Download from connected station
    ↓
Load ONNX model via flutter_onnxruntime
```

## Files to Create

### 1. `lib/services/tts_service.dart`

Main TTS service (singleton):

```dart
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  OrtSession? _session;
  bool _isLoaded = false;
  final TtsModelManager _modelManager = TtsModelManager();

  /// Get TTS language matching current app language
  String get _language {
    final lang = I18nService().currentLanguage;
    return lang.startsWith('pt') ? 'pt' : 'en';
  }

  /// Load Supertonic model (lazy, downloads if needed)
  Future<void> load() async {
    if (_isLoaded) return;

    // Ensure model is downloaded
    await for (final progress in _modelManager.ensureModel()) {
      LogService().log('TTS model download: ${(progress * 100).toStringAsFixed(1)}%');
    }

    final modelPath = await _modelManager.getModelPath();
    _session = await OrtSession.create(modelPath);
    _isLoaded = true;
  }

  /// Synthesize text to WAV audio bytes
  Future<Uint8List> synthesize(
    String text, {
    TtsVoice voice = TtsVoice.f3,
    String? language,
  }) async {
    await load();
    final lang = language ?? _language;
    // Run ONNX inference with voice and language
    // Return WAV bytes
  }

  /// Speak text immediately using app's selected language
  Future<void> speak(String text, {TtsVoice? voice}) async {
    final audio = await synthesize(text, voice: voice ?? TtsVoice.f3);
    await AudioService().playBytes(audio);
  }

  /// Save synthesized audio to file
  Future<File> saveToFile(String text, String path, {TtsVoice? voice}) async {
    final audio = await synthesize(text, voice: voice ?? TtsVoice.f3);
    final file = File(path);
    await file.writeAsBytes(audio);
    return file;
  }
}

enum TtsVoice { m3, m4, m5, f3, f4, f5 }
```

### 2. `lib/bot/services/tts_model_manager.dart`

Model download manager (following Whisper pattern):

```dart
class TtsModelManager {
  static const String _modelFileName = 'supertonic-2.onnx';
  static const int _expectedSize = 66 * 1024 * 1024; // ~66MB
  static const double _sizeTolerance = 0.05; // 5%

  /// Check if model is downloaded
  Future<bool> isDownloaded() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;

    final size = await file.length();
    return size >= _expectedSize * (1 - _sizeTolerance);
  }

  /// Get local model path
  Future<String> getModelPath() async {
    final baseDir = await StorageConfig.getBaseDirectory();
    return '$baseDir/bot/models/supertonic/$_modelFileName';
  }

  /// Ensure model is downloaded, yields progress 0.0 to 1.0
  Stream<double> ensureModel() async* {
    if (await isDownloaded()) {
      yield 1.0;
      return;
    }

    // Try downloading from connected station first
    final stationUrl = WebSocketService().connectedStationUrl;
    if (stationUrl != null) {
      yield* _downloadFromStation(stationUrl);
    } else {
      // Fallback to direct HuggingFace download
      yield* _downloadFromHuggingFace();
    }
  }

  Stream<double> _downloadFromStation(String stationUrl) async* {
    final url = '$stationUrl/bot/models/supertonic/$_modelFileName';
    yield* _downloadFile(url);
  }

  Stream<double> _downloadFromHuggingFace() async* {
    const url = 'https://huggingface.co/Supertone/supertonic-2/resolve/main/supertonic-2.onnx';
    yield* _downloadFile(url);
  }

  Stream<double> _downloadFile(String url) async* {
    // HTTP download with progress tracking
    // Support resume via Range headers
    // Write to temp file, rename on completion
  }
}
```

### 3. `lib/widgets/tts_player_widget.dart`

Reusable TTS widget (documented in reusable.md):

```dart
class TtsPlayerWidget extends StatefulWidget {
  final String text;
  final bool autoPlay;
  final bool showControls;
  final TtsVoice voice;
  final void Function(Uint8List audio)? onAudioGenerated;
  final Widget? child;

  const TtsPlayerWidget({
    required this.text,
    this.autoPlay = false,
    this.showControls = true,
    this.voice = TtsVoice.f3,
    this.onAudioGenerated,
    this.child,
  });
}
```

## Files to Modify

### 1. `lib/services/station_server_service.dart`

Add Supertonic model download (like Whisper):

```dart
// Model info
static const List<Map<String, dynamic>> _supertonicModels = [
  {
    'id': 'supertonic-2',
    'filename': 'supertonic-2.onnx',
    'size': 66 * 1024 * 1024,
    'url': 'https://huggingface.co/Supertone/supertonic-2/resolve/main/supertonic-2.onnx',
  },
];

Set<String> _availableSupertonic = {};

/// Download Supertonic models from HuggingFace
Future<void> _downloadSupertonicModels() async {
  final modelsDir = Directory('$_baseDir/bot/models/supertonic');
  if (!await modelsDir.exists()) {
    await modelsDir.create(recursive: true);
  }

  for (final model in _supertonicModels) {
    final file = File('${modelsDir.path}/${model['filename']}');
    if (await file.exists()) {
      final size = await file.length();
      if (size >= model['size'] * 0.9) {
        _availableSupertonic.add(model['id']);
        continue;
      }
    }

    // Download from HuggingFace
    LogService().log('Downloading Supertonic model: ${model['filename']}');
    await _downloadFile(model['url'], file.path);
    _availableSupertonic.add(model['id']);
  }
}

/// Serve Supertonic model files
// Add route: GET /bot/models/supertonic/:filename
```

### 2. `lib/cli/console_handler.dart`

Add "say" command:

```dart
// In _dispatchCommand() switch
case 'say':
  final text = args.join(' ');
  if (text.isEmpty) {
    _io.writeln('Usage: say <text>');
    return;
  }
  _io.writeln('Speaking...');
  try {
    await TtsService().speak(text);
  } catch (e) {
    _io.writeln('TTS error: $e');
  }
  break;
```

### 3. `lib/pages/console_terminal_page.dart`

Add CTRL+S shortcut:

```dart
// Track last command output
String _lastOutput = '';

// In keyboard shortcuts (~line 290)
LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): _SayIntent(),

// Intent and Action
class _SayIntent extends Intent {}

// In Actions widget
_SayIntent: CallbackAction<_SayIntent>(
  onInvoke: (_) {
    if (_lastOutput.isNotEmpty) {
      TtsService().speak(_lastOutput);
    }
    return null;
  },
),

// Update _lastOutput after each command execution
```

### 4. `lib/services/audio_service.dart`

Add `playBytes()` method:

```dart
/// Play audio from WAV bytes
Future<void> playBytes(Uint8List audioBytes) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/tts_output.wav');
  await tempFile.writeAsBytes(audioBytes);
  await play(tempFile.path);
}
```

### 5. `docs/reusable.md`

Add TtsPlayerWidget documentation (see section below).

## Reusable Widget Documentation

Add to `docs/reusable.md`:

```markdown
### TtsPlayerWidget

**File:** `lib/widgets/tts_player_widget.dart`

Text-to-speech player using Supertonic for on-device voice synthesis.
Automatically uses the app's selected language (English or Portuguese).

**Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | String | Yes | - | Text to synthesize |
| `autoPlay` | bool | No | false | Play immediately on mount |
| `showControls` | bool | No | true | Show play/save buttons |
| `voice` | TtsVoice | No | f3 | Voice style (m3-m5, f3-f5) |
| `onAudioGenerated` | Function? | No | null | Callback with audio bytes |
| `child` | Widget? | No | null | Custom trigger widget |

**Usage:**
```dart
// Simple - shows play button
TtsPlayerWidget(
  text: 'Hello, welcome to Geogram!',
)

// Auto-play notification
TtsPlayerWidget(
  text: notification.message,
  autoPlay: true,
  showControls: false,
)

// Custom trigger with male voice
TtsPlayerWidget(
  text: article.content,
  voice: TtsVoice.m4,
  child: IconButton(
    icon: Icon(Icons.volume_up),
    onPressed: null,
  ),
)

// Save audio file
TtsPlayerWidget(
  text: script,
  onAudioGenerated: (bytes) async {
    final file = File('narration.wav');
    await file.writeAsBytes(bytes);
  },
)
```

**Notes:**
- Model downloads automatically from station server on first use
- Falls back to HuggingFace if no station connected
- Language matches app's I18n setting (en_US → English, pt_PT → Portuguese)
```

## Implementation Steps

### Phase 1: Model Infrastructure
1. Add `_downloadSupertonicModels()` to station_server_service.dart
2. Add HTTP route to serve model files
3. Create `tts_model_manager.dart` with download logic
4. Test station download and client fetch

### Phase 2: Core Service
1. Create `tts_service.dart` with synthesis logic
2. Add `playBytes()` to AudioService
3. Implement ONNX inference with Supertonic
4. Test synthesis on macOS/Android

### Phase 3: Console Integration
1. Add "say" command to console_handler.dart
2. Add CTRL+S shortcut to console_terminal_page.dart
3. Track last command output for CTRL+S

### Phase 4: Reusable Widget
1. Create `TtsPlayerWidget`
2. Add documentation to `docs/reusable.md`
3. Test in sample page

## Console Usage

```
> say Hello world
Speaking...
[Audio plays in selected language]

> say Olá mundo
Speaking...
[Audio plays - Portuguese if pt_PT selected]

> help
Available commands: ...

[User presses CTRL+S]
[Audio reads the help output in selected language]
```

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Tested | Full support via flutter_onnxruntime |
| Android | Expected | flutter_onnxruntime supports ARM64 |
| iOS | Expected | flutter_onnxruntime supports iOS |
| Linux | Untested | May need ONNX Runtime build |
| Web | Limited | WebGPU/WASM, model size concern |

## Verification

1. Start station server, verify Supertonic model downloads
2. Connect client, verify model fetches from station
3. Run `say hello` in console - should hear English audio
4. Switch to Portuguese, run `say olá` - should hear Portuguese
5. Press CTRL+S after command - should read output
6. Use TtsPlayerWidget in test page

## Resources

- [Supertonic GitHub](https://github.com/supertone-inc/supertonic)
- [Supertonic HuggingFace](https://huggingface.co/Supertone/supertonic-2)
- [flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime)
- [Supertonic Flutter Example](https://github.com/supertone-inc/supertonic/tree/main/flutter)
