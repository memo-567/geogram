/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Repeat mode options
enum RepeatMode {
  off, // Stop at end of queue
  all, // Loop entire queue
  one, // Loop current track
}

/// The current playback queue
class PlaybackQueue {
  final String version;
  final int currentIndex;
  final double positionSeconds;
  final bool shuffle;
  final RepeatMode repeat;
  final List<String> trackIds;
  final List<String> originalOrder;
  final DateTime? updatedAt;

  PlaybackQueue({
    this.version = '1.0',
    this.currentIndex = 0,
    this.positionSeconds = 0.0,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    List<String>? trackIds,
    List<String>? originalOrder,
    this.updatedAt,
  })  : trackIds = trackIds ?? [],
        originalOrder = originalOrder ?? [];

  factory PlaybackQueue.fromJson(Map<String, dynamic> json) {
    return PlaybackQueue(
      version: json['version'] as String? ?? '1.0',
      currentIndex: json['current_index'] as int? ?? 0,
      positionSeconds: (json['position_seconds'] as num?)?.toDouble() ?? 0.0,
      shuffle: json['shuffle'] as bool? ?? false,
      repeat: RepeatMode.values.firstWhere(
        (r) => r.name == json['repeat'],
        orElse: () => RepeatMode.off,
      ),
      trackIds: (json['tracks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      originalOrder: (json['original_order'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'current_index': currentIndex,
      'position_seconds': positionSeconds,
      'shuffle': shuffle,
      'repeat': repeat.name,
      'tracks': trackIds,
      'original_order': originalOrder,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  PlaybackQueue copyWith({
    String? version,
    int? currentIndex,
    double? positionSeconds,
    bool? shuffle,
    RepeatMode? repeat,
    List<String>? trackIds,
    List<String>? originalOrder,
    DateTime? updatedAt,
  }) {
    return PlaybackQueue(
      version: version ?? this.version,
      currentIndex: currentIndex ?? this.currentIndex,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      trackIds: trackIds ?? this.trackIds,
      originalOrder: originalOrder ?? this.originalOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if queue is empty
  bool get isEmpty => trackIds.isEmpty;

  /// Check if queue has tracks
  bool get isNotEmpty => trackIds.isNotEmpty;

  /// Get number of tracks in queue
  int get length => trackIds.length;

  /// Get current track ID (null if empty)
  String? get currentTrackId {
    if (trackIds.isEmpty || currentIndex < 0 || currentIndex >= trackIds.length) {
      return null;
    }
    return trackIds[currentIndex];
  }

  /// Check if there's a next track
  bool get hasNext {
    if (repeat == RepeatMode.one || repeat == RepeatMode.all) return true;
    return currentIndex < trackIds.length - 1;
  }

  /// Check if there's a previous track
  bool get hasPrevious {
    if (repeat == RepeatMode.one || repeat == RepeatMode.all) return true;
    return currentIndex > 0;
  }

  /// Get next track index
  int getNextIndex() {
    if (trackIds.isEmpty) return 0;

    if (repeat == RepeatMode.one) {
      return currentIndex;
    }

    if (currentIndex >= trackIds.length - 1) {
      // At end of queue
      return repeat == RepeatMode.all ? 0 : currentIndex;
    }

    return currentIndex + 1;
  }

  /// Get previous track index
  int getPreviousIndex() {
    if (trackIds.isEmpty) return 0;

    if (repeat == RepeatMode.one) {
      return currentIndex;
    }

    if (currentIndex <= 0) {
      // At start of queue
      return repeat == RepeatMode.all ? trackIds.length - 1 : 0;
    }

    return currentIndex - 1;
  }

  /// Create queue with shuffled order
  PlaybackQueue shuffled() {
    if (trackIds.isEmpty) return this;

    final shuffledIds = List<String>.from(trackIds);
    final currentTrack = currentTrackId;

    // Remove current track before shuffling
    if (currentTrack != null) {
      shuffledIds.remove(currentTrack);
    }

    // Shuffle remaining tracks
    shuffledIds.shuffle();

    // Put current track at the front
    if (currentTrack != null) {
      shuffledIds.insert(0, currentTrack);
    }

    return copyWith(
      shuffle: true,
      trackIds: shuffledIds,
      originalOrder: trackIds,
      currentIndex: 0,
      updatedAt: DateTime.now(),
    );
  }

  /// Create queue with original order restored
  PlaybackQueue unshuffled() {
    if (originalOrder.isEmpty) return this;

    final currentTrack = currentTrackId;
    final newIndex = currentTrack != null
        ? originalOrder.indexOf(currentTrack)
        : 0;

    return copyWith(
      shuffle: false,
      trackIds: originalOrder,
      originalOrder: [],
      currentIndex: newIndex >= 0 ? newIndex : 0,
      updatedAt: DateTime.now(),
    );
  }

  /// Cycle through repeat modes
  PlaybackQueue cycleRepeat() {
    final modes = RepeatMode.values;
    final currentModeIndex = modes.indexOf(repeat);
    final nextMode = modes[(currentModeIndex + 1) % modes.length];

    return copyWith(
      repeat: nextMode,
      updatedAt: DateTime.now(),
    );
  }
}
