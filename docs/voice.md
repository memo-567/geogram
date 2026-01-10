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

### Implementation (cached + warm-up)

- `whisper_flutter_new` is vendored at `third_party/whisper_flutter_new` with a dependency override in `pubspec.yaml`.
- Native code now caches the Whisper context and reuses it across calls (reloads only when the model path changes).
- `SpeechToTextService.loadModel` + `ensureModelWarm` load the model and run a short silent WAV transcription (~400 ms) to fully initialize the context.
- `TranscriptionDialog` starts background load + warm-up when opened; if the user taps Start before it is ready, a wait dialog is shown.

### Warm-up triggers

- **Transcription dialog opened:** If the preferred model is already downloaded, the dialog kicks off a background load + warm-up immediately (UI stays responsive).
- **First download:** After the download completes, the dialog starts background load + warm-up before recording is allowed.
- **Model changes:** Calls to `ensureModelReady` also warm the newly loaded model when needed.

### Performance Expectations

| Scenario | Time | Notes |
|----------|------|-------|
| Warm-up (one-time per model) | ~20–30 seconds | Happens when opening the transcription dialog if the model is present or immediately after first download; runs on a silent transcribe and caches the native context. |
| First real transcription after warm-up | <5 seconds | No model load; uses cached context. |
| Subsequent transcriptions | 2–5 seconds | Cached context reused. |
| 10s audio with whisper-base | ~0.6 seconds transcription | Inference speed unchanged; only load latency moved earlier. |

### CPU Optimization

Transcription uses multiple CPU threads for faster processing:
- Uses `Platform.numberOfProcessors` to detect available cores
- Reserves 2 cores for system tasks (if more than 4 cores available)
- Falls back to all cores on devices with 4 or fewer

### Android Notes

- The Android native layer supports `speed_up` and `whisper_full_parallel`, but they are currently disabled because they caused slower performance on real devices.
- If you want to experiment with them, set `speedUp`/`nProcessors` in `SpeechToTextService` and measure `infer_ms` from logcat.

### Model Size vs Speed

- **whisper-tiny** (39MB): 32x realtime, lowest accuracy
- **whisper-base** (145MB): 16x realtime, good accuracy (default)
- **whisper-small** (465MB): 6x realtime, better accuracy
- **whisper-medium** (1.5GB): 2x realtime, high accuracy
- **whisper-large-v2** (3GB): 1x realtime, best accuracy

### Future Improvements

Potential optimizations (not yet implemented):
- Use `whisper-tiny` for faster load time (~10-15s reduction)
- Show "Loading Model..." progress indicator in dialog
- Two-tier strategy: tiny for speed, base for re-transcription

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
