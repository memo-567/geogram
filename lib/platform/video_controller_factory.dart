/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Video player wrapper for media_kit (non-web platforms)
class VideoPlayerWrapper {
  final Player player;
  final VideoController controller;
  final String videoPath;

  VideoPlayerWrapper._({
    required this.player,
    required this.controller,
    required this.videoPath,
  });

  /// Create a video player for a local file path
  static VideoPlayerWrapper? create(String videoPath) {
    final file = File(videoPath);
    if (!file.existsSync()) return null;

    final player = Player();
    final controller = VideoController(player);

    return VideoPlayerWrapper._(
      player: player,
      controller: controller,
      videoPath: videoPath,
    );
  }

  /// Initialize and open the media
  Future<void> initialize() async {
    await player.open(Media(videoPath), play: false);
  }

  /// Play the video
  void play() => player.play();

  /// Pause the video
  void pause() => player.pause();

  /// Toggle play/pause
  void playOrPause() => player.playOrPause();

  /// Seek to position
  void seek(Duration position) => player.seek(position);

  /// Set volume (0.0 to 1.0)
  void setVolume(double volume) => player.setVolume(volume * 100);

  /// Get current state streams
  PlayerStream get stream => player.stream;

  /// Dispose the player
  void dispose() {
    player.dispose();
  }
}

/// Creates a VideoPlayerWrapper from a file path (non-web platforms)
VideoPlayerWrapper? createVideoController(String videoPath) {
  return VideoPlayerWrapper.create(videoPath);
}
