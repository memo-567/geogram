/// Flash progress model for the Flasher app.
///
/// Represents the current state and progress of a flashing operation.

/// Flash operation status
enum FlashStatus {
  /// Idle, not flashing
  idle,

  /// Connecting to device
  connecting,

  /// Syncing with bootloader
  syncing,

  /// Erasing flash memory
  erasing,

  /// Writing firmware
  writing,

  /// Verifying firmware
  verifying,

  /// Resetting device
  resetting,

  /// Flash completed successfully
  completed,

  /// Flash failed with error
  error,
}

/// Flash progress information
class FlashProgress {
  /// Current status
  final FlashStatus status;

  /// Progress percentage (0.0 to 1.0)
  final double progress;

  /// Current operation message
  final String message;

  /// Bytes written so far
  final int bytesWritten;

  /// Total bytes to write
  final int totalBytes;

  /// Current chunk/sector being written
  final int currentChunk;

  /// Total chunks/sectors
  final int totalChunks;

  /// Error message if status is error
  final String? error;

  /// Elapsed time since flash started
  final Duration? elapsed;

  const FlashProgress({
    this.status = FlashStatus.idle,
    this.progress = 0.0,
    this.message = '',
    this.bytesWritten = 0,
    this.totalBytes = 0,
    this.currentChunk = 0,
    this.totalChunks = 0,
    this.error,
    this.elapsed,
  });

  /// Create connecting progress
  factory FlashProgress.connecting() {
    return const FlashProgress(
      status: FlashStatus.connecting,
      message: 'Connecting to device...',
    );
  }

  /// Create syncing progress
  factory FlashProgress.syncing() {
    return const FlashProgress(
      status: FlashStatus.syncing,
      message: 'Syncing with bootloader...',
    );
  }

  /// Create erasing progress
  factory FlashProgress.erasing(double progress) {
    return FlashProgress(
      status: FlashStatus.erasing,
      progress: progress,
      message: 'Erasing flash memory...',
    );
  }

  /// Create writing progress
  factory FlashProgress.writing({
    required double progress,
    required int bytesWritten,
    required int totalBytes,
    required int currentChunk,
    required int totalChunks,
  }) {
    return FlashProgress(
      status: FlashStatus.writing,
      progress: progress,
      message: 'Writing firmware...',
      bytesWritten: bytesWritten,
      totalBytes: totalBytes,
      currentChunk: currentChunk,
      totalChunks: totalChunks,
    );
  }

  /// Create verifying progress
  factory FlashProgress.verifying(double progress) {
    return FlashProgress(
      status: FlashStatus.verifying,
      progress: progress,
      message: 'Verifying firmware...',
    );
  }

  /// Create resetting progress
  factory FlashProgress.resetting() {
    return const FlashProgress(
      status: FlashStatus.resetting,
      progress: 1.0,
      message: 'Resetting device...',
    );
  }

  /// Create completed progress
  factory FlashProgress.completed(Duration elapsed) {
    return FlashProgress(
      status: FlashStatus.completed,
      progress: 1.0,
      message: 'Flash completed successfully',
      elapsed: elapsed,
    );
  }

  /// Create error progress
  factory FlashProgress.error(String error) {
    return FlashProgress(
      status: FlashStatus.error,
      message: 'Flash failed',
      error: error,
    );
  }

  /// Get percentage as integer (0-100)
  int get percentage => (progress * 100).round();

  /// Get formatted bytes written
  String get formattedProgress {
    if (totalBytes == 0) return '';
    return '${_formatBytes(bytesWritten)} / ${_formatBytes(totalBytes)}';
  }

  /// Get formatted elapsed time
  String get formattedElapsed {
    if (elapsed == null) return '';
    final seconds = elapsed!.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  /// Check if operation is in progress
  bool get isInProgress =>
      status != FlashStatus.idle &&
      status != FlashStatus.completed &&
      status != FlashStatus.error;

  /// Check if operation completed successfully
  bool get isCompleted => status == FlashStatus.completed;

  /// Check if operation failed
  bool get isError => status == FlashStatus.error;

  /// Format bytes for display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Copy with modified fields
  FlashProgress copyWith({
    FlashStatus? status,
    double? progress,
    String? message,
    int? bytesWritten,
    int? totalBytes,
    int? currentChunk,
    int? totalChunks,
    String? error,
    Duration? elapsed,
  }) {
    return FlashProgress(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      totalBytes: totalBytes ?? this.totalBytes,
      currentChunk: currentChunk ?? this.currentChunk,
      totalChunks: totalChunks ?? this.totalChunks,
      error: error ?? this.error,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}
