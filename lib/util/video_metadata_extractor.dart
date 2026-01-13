/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

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
/// Uses FFmpeg/FFprobe on desktop (Windows/Linux/macOS) and
/// ffmpeg_kit_flutter on mobile (Android/iOS).
class VideoMetadataExtractor {
  VideoMetadataExtractor._();

  /// Check if FFmpeg is available on the system
  static Future<bool> isFFmpegAvailable() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile requires ffmpeg_kit_flutter package
      // For now, return false - implement when package is added
      return false;
    }

    // Desktop: check if ffprobe is in PATH
    try {
      final result = await Process.run('ffprobe', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Extract metadata from a video file
  ///
  /// Returns null if extraction fails or FFmpeg is not available
  static Future<VideoMetadata?> extract(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;

    // Get file size
    final stat = await file.stat();
    final fileSize = stat.size;

    // Get MIME type from extension
    final mimeType = _getMimeType(videoPath);

    if (Platform.isAndroid || Platform.isIOS) {
      return _extractWithFFmpegKit(videoPath, fileSize, mimeType);
    } else {
      return _extractWithFFmpegCli(videoPath, fileSize, mimeType);
    }
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
        print('FFprobe error: ${result.stderr}');
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
      print('Error extracting video metadata: $e');
      return null;
    }
  }

  /// Extract metadata using ffmpeg_kit_flutter (mobile)
  ///
  /// Note: Requires ffmpeg_kit_flutter package to be added
  static Future<VideoMetadata?> _extractWithFFmpegKit(
    String videoPath,
    int fileSize,
    String mimeType,
  ) async {
    // TODO: Implement when ffmpeg_kit_flutter is added
    // For now, return basic metadata based on file
    print('FFmpeg Kit not implemented yet for mobile');
    return null;
  }

  /// Generate thumbnail from video file
  ///
  /// [videoPath] - Source video file path
  /// [outputPath] - Output thumbnail path (should end in .jpg or .png)
  /// [atSeconds] - Time position to capture (default: 1 second)
  /// [width] - Output width (default: 1280, height scaled proportionally)
  ///
  /// Returns output path on success, null on failure
  static Future<String?> generateThumbnail(
    String videoPath,
    String outputPath, {
    int atSeconds = 1,
    int width = 1280,
  }) async {
    if (!await File(videoPath).exists()) return null;

    if (Platform.isAndroid || Platform.isIOS) {
      return _thumbnailWithFFmpegKit(videoPath, outputPath, atSeconds, width);
    } else {
      return _thumbnailWithFFmpegCli(videoPath, outputPath, atSeconds, width);
    }
  }

  /// Generate thumbnail using FFmpeg CLI (desktop)
  static Future<String?> _thumbnailWithFFmpegCli(
    String videoPath,
    String outputPath,
    int atSeconds,
    int width,
  ) async {
    try {
      // Delete existing output file
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      // Use ffmpeg to extract frame
      final result = await Process.run('ffmpeg', [
        '-ss',
        atSeconds.toString(),
        '-i',
        videoPath,
        '-vframes',
        '1',
        '-vf',
        'scale=$width:-1',
        '-q:v',
        '2', // High quality JPEG
        '-y', // Overwrite output
        outputPath,
      ]);

      if (result.exitCode != 0) {
        print('FFmpeg thumbnail error: ${result.stderr}');
        return null;
      }

      // Verify output was created
      if (await outputFile.exists()) {
        return outputPath;
      }

      return null;
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }

  /// Generate thumbnail using ffmpeg_kit_flutter (mobile)
  static Future<String?> _thumbnailWithFFmpegKit(
    String videoPath,
    String outputPath,
    int atSeconds,
    int width,
  ) async {
    // TODO: Implement when ffmpeg_kit_flutter is added
    print('FFmpeg Kit thumbnail not implemented yet for mobile');
    return null;
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
