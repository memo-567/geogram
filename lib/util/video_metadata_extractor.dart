/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/log_service.dart';

/// Video metadata extracted from a video file
class VideoMetadata {
  final int duration; // Seconds
  final int width;
  final int height;
  final int fileSize; // Bytes
  final String mimeType;
  final double? frameRate;
  final int? bitrate;
  final String? videoCodec;
  final String? audioCodec;

  VideoMetadata({
    required this.duration,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.mimeType,
    this.frameRate,
    this.bitrate,
    this.videoCodec,
    this.audioCodec,
  });

  /// Get resolution as string (e.g., "1920x1080")
  String get resolution => '${width}x$height';

  /// Convert to map for video.txt fields
  Map<String, dynamic> toMap() {
    return {
      'duration': duration,
      'resolution': resolution,
      'fileSize': fileSize,
      'mimeType': mimeType,
      if (frameRate != null) 'frameRate': frameRate,
      if (bitrate != null) 'bitrate': bitrate,
      if (videoCodec != null) 'videoCodec': videoCodec,
      if (audioCodec != null) 'audioCodec': audioCodec,
    };
  }
}

/// Cross-platform video metadata extractor
///
/// Uses media_kit for metadata extraction and thumbnail generation.
/// Falls back to ffprobe CLI on desktop if available.
class VideoMetadataExtractor {
  VideoMetadataExtractor._();

  /// Check if video extraction is available (always true with media_kit)
  static Future<bool> isFFmpegAvailable() async {
    // media_kit is always bundled with the app
    return true;
  }

  /// Extract metadata from a video file
  ///
  /// Returns null if extraction fails
  static Future<VideoMetadata?> extract(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;

    // Get file size
    final stat = await file.stat();
    final fileSize = stat.size;

    // Get MIME type from extension
    final mimeType = _getMimeType(videoPath);

    // Try media_kit first, then fall back to CLI ffprobe
    final result = await _extractWithMediaKit(videoPath, fileSize, mimeType);
    if (result != null) return result;

    // Fall back to CLI ffprobe (if available on system)
    return _extractWithFFmpegCli(videoPath, fileSize, mimeType);
  }

  /// Extract metadata using FFmpeg CLI (desktop)
  static Future<VideoMetadata?> _extractWithFFmpegCli(
    String videoPath,
    int fileSize,
    String mimeType,
  ) async {
    try {
      // Use ffprobe to get video metadata in JSON format
      final result = await Process.run('ffprobe', [
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        videoPath,
      ]);

      if (result.exitCode != 0) {
        LogService().log('FFprobe CLI error: ${result.stderr}');
        return null;
      }

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;

      // Parse format info
      final format = json['format'] as Map<String, dynamic>?;
      final streams = json['streams'] as List<dynamic>?;

      // Find video stream
      Map<String, dynamic>? videoStream;
      Map<String, dynamic>? audioStream;

      if (streams != null) {
        for (final stream in streams) {
          final codecType = stream['codec_type'] as String?;
          if (codecType == 'video' && videoStream == null) {
            videoStream = stream as Map<String, dynamic>;
          } else if (codecType == 'audio' && audioStream == null) {
            audioStream = stream as Map<String, dynamic>;
          }
        }
      }

      if (videoStream == null && format == null) {
        return null;
      }

      // Extract duration
      int duration = 0;
      if (format != null && format['duration'] != null) {
        duration = double.tryParse(format['duration'].toString())?.round() ?? 0;
      } else if (videoStream != null && videoStream['duration'] != null) {
        duration = double.tryParse(videoStream['duration'].toString())?.round() ?? 0;
      }

      // Extract dimensions
      int width = 0;
      int height = 0;
      if (videoStream != null) {
        width = videoStream['width'] as int? ?? 0;
        height = videoStream['height'] as int? ?? 0;
      }

      // Extract frame rate
      double? frameRate;
      if (videoStream != null && videoStream['r_frame_rate'] != null) {
        final rateStr = videoStream['r_frame_rate'] as String;
        final parts = rateStr.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0]);
          final den = double.tryParse(parts[1]);
          if (num != null && den != null && den > 0) {
            frameRate = num / den;
          }
        }
      }

      // Extract bitrate
      int? bitrate;
      if (format != null && format['bit_rate'] != null) {
        bitrate = int.tryParse(format['bit_rate'].toString());
      }

      // Extract codecs
      String? videoCodec;
      String? audioCodec;
      if (videoStream != null) {
        videoCodec = videoStream['codec_name'] as String?;
      }
      if (audioStream != null) {
        audioCodec = audioStream['codec_name'] as String?;
      }

      return VideoMetadata(
        duration: duration,
        width: width,
        height: height,
        fileSize: fileSize,
        mimeType: mimeType,
        frameRate: frameRate,
        bitrate: bitrate,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
      );
    } catch (e) {
      LogService().log('Error extracting video metadata with CLI: $e');
      return null;
    }
  }

  /// Extract metadata using media_kit (all platforms)
  static Future<VideoMetadata?> _extractWithMediaKit(
    String videoPath,
    int fileSize,
    String mimeType,
  ) async {
    Player? player;
    try {
      player = Player();
      // VideoController is needed for proper media loading
      final videoController = VideoController(player);

      // Wait for duration to be set (indicates file is loaded)
      final completer = Completer<Duration>();
      late StreamSubscription sub;
      sub = player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !completer.isCompleted) {
          completer.complete(duration);
          sub.cancel();
        }
      });

      // Open the media file without playing
      await player.open(Media(videoPath), play: false);

      // Wait for duration with timeout
      final duration = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => Duration.zero,
      );

      if (duration == Duration.zero) {
        LogService().log('media_kit: Failed to get duration for $videoPath');
        await player.dispose();
        // Keep reference for lint
        videoController.hashCode;
        return null;
      }

      // Get dimensions from player state
      final width = player.state.width ?? 0;
      final height = player.state.height ?? 0;

      await player.dispose();

      return VideoMetadata(
        duration: duration.inSeconds,
        width: width,
        height: height,
        fileSize: fileSize,
        mimeType: mimeType,
        // media_kit doesn't provide these directly - use CLI fallback if needed
        frameRate: null,
        bitrate: null,
        videoCodec: null,
        audioCodec: null,
      );
    } catch (e) {
      LogService().log('media_kit error extracting metadata: $e');
      await player?.dispose();
      return null;
    }
  }

  /// Generate thumbnail from video file using media_kit
  ///
  /// [videoPath] - Source video file path
  /// [outputPath] - Output thumbnail path (will be .png format from media_kit)
  /// [atSeconds] - Time position to capture (default: 1 second)
  /// [width] - Output width (ignored - media_kit returns native resolution)
  ///
  /// Returns output path on success, null on failure
  static Future<String?> generateThumbnail(
    String videoPath,
    String outputPath, {
    int atSeconds = 1,
    int width = 1280, // Ignored - media_kit returns native resolution
  }) async {
    if (!await File(videoPath).exists()) {
      LogService().log('generateThumbnail: Video file not found: $videoPath');
      return null;
    }

    // Use media_kit for all platforms
    return _thumbnailWithMediaKit(videoPath, outputPath, atSeconds);
  }

  /// Generate thumbnail using media_kit (all platforms)
  ///
  /// This method creates a Player, seeks to the desired position,
  /// takes a screenshot, and saves it to disk.
  static Future<String?> _thumbnailWithMediaKit(
    String videoPath,
    String outputPath,
    int atSeconds,
  ) async {
    Player? player;
    try {
      // Delete existing output file
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      // Ensure output directory exists
      await outputFile.parent.create(recursive: true);

      // Create player and attach VideoController (required for screenshot)
      player = Player();
      final videoController = VideoController(player);

      // Wait for duration to confirm media is loaded
      final completer = Completer<Duration>();
      late StreamSubscription sub;
      sub = player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !completer.isCompleted) {
          completer.complete(duration);
          sub.cancel();
        }
      });

      // Open the media file without playing
      await player.open(Media(videoPath), play: false);

      // Wait for media to load with timeout
      final duration = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => Duration.zero,
      );

      if (duration == Duration.zero) {
        LogService().log('media_kit thumbnail: Failed to load video $videoPath');
        await player.dispose();
        videoController.hashCode; // Keep reference for lint
        return null;
      }

      // Seek to desired position
      final seekPosition = Duration(seconds: atSeconds);
      await player.seek(seekPosition);
      await Future.delayed(const Duration(milliseconds: 300));

      // Play briefly to ensure frames are decoded, then pause
      player.play();
      await Future.delayed(const Duration(milliseconds: 200));
      player.pause();
      await Future.delayed(const Duration(milliseconds: 200));

      // Take screenshot (returns PNG bytes)
      final bytes = await player.screenshot();

      await player.dispose();

      if (bytes == null || bytes.isEmpty) {
        LogService().log('media_kit thumbnail: Screenshot returned null/empty');
        return null;
      }

      // Save to file (media_kit returns PNG format)
      // If outputPath expects .jpg, we still save PNG data - caller should use .png extension
      await outputFile.writeAsBytes(bytes, flush: true);

      if (await outputFile.exists()) {
        final stat = await outputFile.stat();
        LogService().log('media_kit thumbnail created: $outputPath (${stat.size} bytes)');
        return outputPath;
      }

      LogService().log('media_kit thumbnail: Output file not created');
      return null;
    } catch (e) {
      LogService().log('media_kit thumbnail error: $e');
      await player?.dispose();
      return null;
    }
  }

  /// Get recommended thumbnail time based on video duration
  ///
  /// Returns time at 10% of video duration (as per specification)
  static int getRecommendedThumbnailTime(int durationSeconds) {
    if (durationSeconds <= 10) {
      return 1; // For short videos, use 1 second
    }
    return (durationSeconds * 0.1).round();
  }

  /// Get MIME type from file extension
  static String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'video/mp4';
    }
  }

  /// Validate video file format
  static Future<bool> isValidVideoFile(String videoPath) async {
    if (!await File(videoPath).exists()) return false;

    final ext = videoPath.split('.').last.toLowerCase();
    final validExtensions = ['mp4', 'webm', 'mov', 'avi', 'mkv'];

    return validExtensions.contains(ext);
  }

  /// Get basic metadata without FFmpeg (fallback)
  ///
  /// Only returns file size and MIME type
  static Future<Map<String, dynamic>?> getBasicMetadata(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;

    final stat = await file.stat();

    return {
      'fileSize': stat.size,
      'mimeType': _getMimeType(videoPath),
    };
  }
}
