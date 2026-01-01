/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'music_track.dart';

/// Phases of music generation
enum MusicPhase {
  /// Request queued, waiting to start
  queued,

  /// Downloading AI model (if needed)
  downloading,

  /// Playing FM synthesis while AI generates
  fmPlaying,

  /// AI model is generating music
  generating,

  /// Post-processing audio (encoding, normalizing)
  postProcessing,

  /// Saving track to storage
  saving,

  /// Generation completed successfully
  completed,

  /// Generation failed
  failed,

  /// Generation was cancelled
  cancelled,
}

/// Current state of music generation process
class MusicGenerationState {
  /// Current phase
  final MusicPhase phase;

  /// Progress within current phase (0.0 - 1.0)
  final double progress;

  /// Human-readable status message
  final String? message;

  /// Estimated time remaining
  final Duration? eta;

  /// The resulting track (only set when completed)
  final MusicTrack? result;

  /// Error message (only set when failed)
  final String? error;

  /// Currently playing FM track (while AI generates in background)
  final MusicTrack? fmTrack;

  const MusicGenerationState({
    required this.phase,
    this.progress = 0.0,
    this.message,
    this.eta,
    this.result,
    this.error,
    this.fmTrack,
  });

  /// Check if generation is in progress
  bool get isInProgress =>
      phase == MusicPhase.queued ||
      phase == MusicPhase.downloading ||
      phase == MusicPhase.fmPlaying ||
      phase == MusicPhase.generating ||
      phase == MusicPhase.postProcessing ||
      phase == MusicPhase.saving;

  /// Check if generation is complete (success or failure)
  bool get isDone =>
      phase == MusicPhase.completed ||
      phase == MusicPhase.failed ||
      phase == MusicPhase.cancelled;

  /// Check if generation succeeded
  bool get isSuccess => phase == MusicPhase.completed && result != null;

  /// Check if generation failed
  bool get isFailed => phase == MusicPhase.failed;

  /// Check if FM is currently playing while AI generates
  bool get isFMPlaying => phase == MusicPhase.fmPlaying && fmTrack != null;

  /// Get phase display name
  String get phaseDisplayName {
    switch (phase) {
      case MusicPhase.queued:
        return 'Queued';
      case MusicPhase.downloading:
        return 'Downloading model';
      case MusicPhase.fmPlaying:
        return 'Playing (generating better quality)';
      case MusicPhase.generating:
        return 'Generating music';
      case MusicPhase.postProcessing:
        return 'Processing audio';
      case MusicPhase.saving:
        return 'Saving track';
      case MusicPhase.completed:
        return 'Completed';
      case MusicPhase.failed:
        return 'Failed';
      case MusicPhase.cancelled:
        return 'Cancelled';
    }
  }

  /// Get progress as percentage string
  String get progressString => '${(progress * 100).round()}%';

  /// Get ETA as formatted string
  String? get etaString {
    if (eta == null) return null;
    final seconds = eta!.inSeconds;
    if (seconds < 60) {
      return '~${seconds}s remaining';
    }
    final minutes = (seconds / 60).round();
    return '~${minutes}m remaining';
  }

  /// Create initial queued state
  factory MusicGenerationState.queued({String? message}) {
    return MusicGenerationState(
      phase: MusicPhase.queued,
      message: message ?? 'Preparing to generate music...',
    );
  }

  /// Create downloading state
  factory MusicGenerationState.downloading({
    required double progress,
    String? modelName,
  }) {
    return MusicGenerationState(
      phase: MusicPhase.downloading,
      progress: progress,
      message: modelName != null
          ? 'Downloading $modelName...'
          : 'Downloading model...',
    );
  }

  /// Create FM playing state (while AI generates in background)
  factory MusicGenerationState.fmPlaying({
    required MusicTrack fmTrack,
    double aiProgress = 0.0,
    Duration? eta,
  }) {
    return MusicGenerationState(
      phase: MusicPhase.fmPlaying,
      progress: aiProgress,
      message: 'Playing FM synthesis while generating AI music...',
      fmTrack: fmTrack,
      eta: eta,
    );
  }

  /// Create generating state
  factory MusicGenerationState.generating({
    required double progress,
    Duration? eta,
    String? message,
  }) {
    return MusicGenerationState(
      phase: MusicPhase.generating,
      progress: progress,
      eta: eta,
      message: message ?? 'Generating music...',
    );
  }

  /// Create post-processing state
  factory MusicGenerationState.postProcessing({double progress = 0.0}) {
    return MusicGenerationState(
      phase: MusicPhase.postProcessing,
      progress: progress,
      message: 'Processing audio...',
    );
  }

  /// Create saving state
  factory MusicGenerationState.saving() {
    return const MusicGenerationState(
      phase: MusicPhase.saving,
      progress: 0.9,
      message: 'Saving track...',
    );
  }

  /// Create completed state
  factory MusicGenerationState.completed(MusicTrack track) {
    return MusicGenerationState(
      phase: MusicPhase.completed,
      progress: 1.0,
      message: 'Music generated successfully!',
      result: track,
    );
  }

  /// Create failed state
  factory MusicGenerationState.failed(String error) {
    return MusicGenerationState(
      phase: MusicPhase.failed,
      error: error,
      message: 'Generation failed: $error',
    );
  }

  /// Create cancelled state
  factory MusicGenerationState.cancelled() {
    return const MusicGenerationState(
      phase: MusicPhase.cancelled,
      message: 'Generation cancelled',
    );
  }

  MusicGenerationState copyWith({
    MusicPhase? phase,
    double? progress,
    String? message,
    Duration? eta,
    MusicTrack? result,
    String? error,
    MusicTrack? fmTrack,
  }) {
    return MusicGenerationState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      eta: eta ?? this.eta,
      result: result ?? this.result,
      error: error ?? this.error,
      fmTrack: fmTrack ?? this.fmTrack,
    );
  }
}

/// Request for music generation
class MusicGenerationRequest {
  /// Original user prompt
  final String prompt;

  /// Requested duration
  final Duration duration;

  /// Detected/preferred genre
  final String genre;

  /// Whether to allow FM synthesis fallback
  final bool allowFMFallback;

  /// Whether to use hybrid mode (FM plays while AI generates)
  final bool useHybridMode;

  /// Preferred model ID (null = auto-select)
  final String? preferredModelId;

  const MusicGenerationRequest({
    required this.prompt,
    required this.duration,
    required this.genre,
    this.allowFMFallback = true,
    this.useHybridMode = true,
    this.preferredModelId,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'durationMs': duration.inMilliseconds,
        'genre': genre,
        'allowFMFallback': allowFMFallback,
        'useHybridMode': useHybridMode,
        if (preferredModelId != null) 'preferredModelId': preferredModelId,
      };

  factory MusicGenerationRequest.fromJson(Map<String, dynamic> json) {
    return MusicGenerationRequest(
      prompt: json['prompt'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      genre: json['genre'] as String,
      allowFMFallback: json['allowFMFallback'] as bool? ?? true,
      useHybridMode: json['useHybridMode'] as bool? ?? true,
      preferredModelId: json['preferredModelId'] as String?,
    );
  }
}
