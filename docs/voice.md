# Voice Recognition

Offline speech-to-text using [Whisper](https://github.com/openai/whisper) AI models via the `whisper_flutter_new` package.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TranscribeButtonWidget                        │
│                  (lib/widgets/transcribe_button_widget.dart)     │
│                                                                  │
│  - Waveform icon button for text fields                         │
│  - Hidden on unsupported platforms                              │
│  - Opens TranscriptionDialog on tap                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TranscriptionDialog                          │
│                  (lib/widgets/transcription_dialog.dart)         │
│                                                                  │
│  State Machine:                                                  │
│  checkingModel → downloadingModel → idle → recording →          │
│  processing → [success/error]                                   │
│                                                                  │
│  - Manages model download progress                              │
│  - Records audio in WAV format (16kHz mono)                     │
│  - Handles transcription and returns result                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│   WhisperModelManager    │  │   SpeechToTextService    │
│ (lib/bot/services/       │  │ (lib/bot/services/       │
│  whisper_model_manager)  │  │  speech_to_text_service) │
│                          │  │                          │
│ - Model download         │  │ - Model loading          │
│ - Storage management     │  │ - Transcription          │
│ - Progress streaming     │  │ - Platform detection     │
└──────────────────────────┘  └──────────────────────────┘
              │                         │
              ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      WhisperModelInfo                            │
│                (lib/bot/models/whisper_model_info.dart)          │
│                                                                  │
│  Model definitions: tiny, base, small, medium, large-v2         │
└─────────────────────────────────────────────────────────────────┘
```

## Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| Android 5.0+ | Yes | Primary target |
| iOS 13+ | Yes | |
| macOS 11+ | Yes | |
| Windows | No | Icon hidden automatically |
| Linux | No | Icon hidden automatically |
| Web | No | Icon hidden automatically |

## Usage

### Adding to a Text Field

```dart
import 'package:geogram/widgets/transcribe_button_widget.dart';

TextFormField(
  controller: _controller,
  decoration: InputDecoration(
    labelText: 'Description',
    suffixIcon: TranscribeButtonWidget(
      i18n: i18n,
      onTranscribed: (text) {
        if (_controller.text.isEmpty) {
          _controller.text = text;
        } else {
          _controller.text += ' $text';
        }
      },
    ),
  ),
)
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `i18n` | `I18n` | Yes | Internationalization service for UI text |
| `onTranscribed` | `Function(String)` | Yes | Callback with transcribed text |
| `enabled` | `bool` | No | Enable/disable button (default: true) |
| `iconSize` | `double` | No | Icon size (default: 24.0) |
| `maxRecordingDuration` | `Duration` | No | Max recording time (default: 30s) |

## Whisper Models

Models are downloaded from HuggingFace on first use.

| Model ID | Size | Speed | Quality | Default |
|----------|------|-------|---------|---------|
| `whisper-tiny` | ~39 MB | 32x realtime | Low | |
| `whisper-base` | ~145 MB | 16x realtime | Good | **Yes** |
| `whisper-small` | ~465 MB | 6x realtime | Better | |
| `whisper-medium` | ~1.5 GB | 2x realtime | High | |
| `whisper-large-v2` | ~3 GB | 1x realtime | Best | |

### Download Source

Models are downloaded directly from HuggingFace:
```
https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{model}.bin
```

## File Locations

### Model Storage

```
{app-data}/geogram/bot/models/whisper/
├── ggml-tiny.bin      # ~39 MB
├── ggml-base.bin      # ~145 MB (default)
├── ggml-small.bin     # ~465 MB
├── ggml-medium.bin    # ~1.5 GB
└── ggml-large-v2.bin  # ~3 GB
```

On Android: `/data/user/0/dev.geogram/app_flutter/geogram/bot/models/whisper/`

### Temporary Recording Files

Audio recordings are stored temporarily during transcription:
```
{cache-dir}/transcription_{timestamp}.wav
```

Files are automatically cleaned up after transcription completes.

## Audio Format

The transcription dialog records directly in WAV format for Whisper compatibility:

- **Format**: WAV (PCM)
- **Sample Rate**: 16000 Hz
- **Channels**: 1 (mono)
- **Bit Depth**: 16-bit

This avoids the need for audio format conversion (FFmpeg) which would add significant app size.

## Performance

### Startup Preloading

The app preloads the Whisper model in the background during startup (Phase 2 deferred initialization in `main.dart`). This ensures the first transcription is fast:

1. App starts → UI renders immediately
2. Background: Model loads silently (~20-30s, non-blocking)
3. User opens transcription dialog → Model already in memory
4. Recording + transcription: **2-5 seconds**

The preload only runs if:
- Platform supports speech-to-text (Android, iOS, macOS)
- The preferred model has already been downloaded

### CPU Optimization

Transcription uses multiple CPU threads for faster processing:
- Uses `Platform.numberOfProcessors` to detect available cores
- Reserves 2 cores for system tasks (if more than 4 cores available)
- Falls back to all cores on devices with 4 or fewer

### Performance Expectations

| Scenario | Time |
|----------|------|
| First transcription (model preloaded) | 2-5 seconds |
| First transcription (model not preloaded) | 20-30 seconds |
| Subsequent transcriptions | 2-5 seconds |
| 10s audio with whisper-base | ~0.6 seconds transcription |

### Model Size vs Speed

- **Smaller models** (tiny, base): Faster transcription, lower accuracy
- **Larger models** (small, medium, large): Better accuracy, slower processing
- **Default (whisper-base)**: Best balance of speed and accuracy for mobile devices

## Changing the Default Model

To change the default model, modify `WhisperModels.defaultModelId` in:
```
lib/bot/models/whisper_model_info.dart
```

```dart
static const String defaultModelId = 'whisper-tiny'; // Fastest, lowest accuracy
// or
static const String defaultModelId = 'whisper-base'; // Fast with good accuracy (default)
// or
static const String defaultModelId = 'whisper-small'; // Slower, better accuracy
```

## i18n Keys

The following keys are used (defined in `languages/{locale}/bot.json`):

- `voice_to_text` - Button tooltip
- `checking_speech_model` - Checking model status
- `downloading_speech_model` - Download in progress
- `first_time_download` - First-time download notice
- `max_duration_seconds` - Recording duration limit
- `tap_to_record` - Idle state instruction
- `listening` - Recording state
- `processing_speech` - Transcription in progress
- `transcribing_audio` - Transcription in progress (alternative)
- `please_wait` - Wait message
- `transcription_failed` - Error message
- `no_audio_recorded` - No audio error
- `microphone_permission_required` - Permission error
- `recording_failed` - Recording error
- `cancel` - Cancel button
- `stop` - Stop button
- `retry` - Retry button

## Dependencies

```yaml
# pubspec.yaml
dependencies:
  whisper_flutter_new: ^1.0.1  # Whisper bindings
  record: ^6.0.0               # Audio recording (WAV)
```

### Android Configuration

The `whisper_flutter_new` package requires a specific NDK version. This is configured in `android/build.gradle.kts`:

```kotlin
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            if (project.name == "whisper_flutter_new") {
                android.ndkVersion = "27.0.12077973"
            }
        }
    }
}
```

## See Also

- [Reusable Widgets](reusable.md) - TranscribeButtonWidget documentation
- [Downloads](downloads.md) - Model download management
