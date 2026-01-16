/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/i18n_service.dart';
import '../util/video_metadata_extractor.dart';

/// Dialog for selecting a thumbnail from video frames
class ThumbnailSelectorDialog extends StatefulWidget {
  final String videoPath;
  final int durationSeconds;
  final I18nService i18n;

  const ThumbnailSelectorDialog({
    super.key,
    required this.videoPath,
    required this.durationSeconds,
    required this.i18n,
  });

  /// Show dialog and return selected timestamp (in seconds), or null if cancelled
  static Future<int?> show({
    required BuildContext context,
    required String videoPath,
    required int durationSeconds,
    required I18nService i18n,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => ThumbnailSelectorDialog(
        videoPath: videoPath,
        durationSeconds: durationSeconds,
        i18n: i18n,
      ),
    );
  }

  @override
  State<ThumbnailSelectorDialog> createState() => _ThumbnailSelectorDialogState();
}

class _ThumbnailSelectorDialogState extends State<ThumbnailSelectorDialog> {
  final List<_ThumbnailPreview> _previews = [];
  bool _isLoading = true;
  String? _error;
  String? _tempDir;

  @override
  void initState() {
    super.initState();
    _generatePreviews();
  }

  @override
  void dispose() {
    _cleanupTempFiles();
    super.dispose();
  }

  /// Calculate timestamps for preview extraction
  List<int> _calculateTimestamps() {
    final duration = widget.durationSeconds;

    if (duration <= 5) {
      // Very short video: just use 1 second
      return [1];
    } else if (duration <= 15) {
      // Short video: 1s, middle, 2/3
      return [
        1,
        (duration * 0.5).round(),
        (duration * 0.66).round(),
      ];
    } else {
      // Normal video: 6 frames distributed across first 15 seconds and key points
      final timestamps = <int>[
        1,
        5,
        10,
        15,
        (duration * 0.25).round(),
        (duration * 0.5).round(),
      ];
      // Remove duplicates and sort
      return timestamps.toSet().toList()..sort();
    }
  }

  Future<void> _generatePreviews() async {
    try {
      // Check if FFmpeg is available
      final ffmpegAvailable = await VideoMetadataExtractor.isFFmpegAvailable();
      if (!ffmpegAvailable) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'FFmpeg not available. Please install FFmpeg.';
          });
        }
        return;
      }

      // Check if video file exists
      final videoFile = File(widget.videoPath);
      if (!await videoFile.exists()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Video file not found';
          });
        }
        return;
      }

      // Create temp directory for preview images
      final tempDir = await getTemporaryDirectory();
      _tempDir = '${tempDir.path}/thumbnail_previews_${DateTime.now().millisecondsSinceEpoch}';
      await Directory(_tempDir!).create(recursive: true);

      final timestamps = _calculateTimestamps();

      for (int i = 0; i < timestamps.length; i++) {
        final timestamp = timestamps[i];
        final outputPath = '$_tempDir/preview_$i.jpg';

        final result = await VideoMetadataExtractor.generateThumbnail(
          widget.videoPath,
          outputPath,
          atSeconds: timestamp,
          width: 320, // Smaller for preview grid
        );

        if (result != null && mounted) {
          setState(() {
            _previews.add(_ThumbnailPreview(
              path: result,
              timestamp: timestamp,
            ));
          });
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_previews.isEmpty) {
            _error = 'FFmpeg failed to extract frames';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  Future<void> _cleanupTempFiles() async {
    if (_tempDir != null) {
      try {
        final dir = Directory(_tempDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  String _formatTimestamp(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.i18n.t('select_thumbnail')),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _buildContent(theme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.i18n.t('cancel')),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading && _previews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(widget.i18n.t('generating_previews')),
          ],
        ),
      );
    }

    if (_error != null && _previews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Show grid of previews
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: _previews.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _previews.length) {
          // Loading indicator for remaining previews
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final preview = _previews[index];
        return _buildPreviewTile(preview, theme);
      },
    );
  }

  Widget _buildPreviewTile(_ThumbnailPreview preview, ThemeData theme) {
    return InkWell(
      onTap: () => Navigator.pop(context, preview.timestamp),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image
            Image.file(
              File(preview.path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image),
              ),
            ),
            // Timestamp badge
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatTimestamp(preview.timestamp),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Hover/focus overlay
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context, preview.timestamp),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailPreview {
  final String path;
  final int timestamp;

  _ThumbnailPreview({
    required this.path,
    required this.timestamp,
  });
}
