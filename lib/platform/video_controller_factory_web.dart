/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Stub class for web platform - video file playback not supported
class VideoPlayerWrapper {
  void dispose() {}
}

/// Creates a VideoPlayerWrapper from a file path (web stub - not supported)
VideoPlayerWrapper? createVideoController(String videoPath) {
  // Video file playback is not supported on web platform
  return null;
}
