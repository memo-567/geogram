/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../services/i18n_service.dart';
import '../services/sound_clips_service.dart';

/// A reusable bottom sheet widget for picking sound tracks
///
/// Features:
/// - Categories displayed as expansion tiles
/// - Each track shows play/stop preview, title, mood, duration
/// - Current selection highlighted
/// - "None" option to clear music
///
/// Usage:
/// ```dart
/// final track = await SoundPickerWidget.show(
///   context,
///   i18n: i18n,
///   currentTrack: currentMusicPath,
/// );
/// ```
class SoundPickerWidget extends StatefulWidget {
  final I18nService i18n;
  final String? currentTrack;

  const SoundPickerWidget({
    super.key,
    required this.i18n,
    this.currentTrack,
  });

  /// Shows the sound picker and returns the selected track, or null if cancelled
  /// Returns empty string "" if "None" is selected
  static Future<SoundTrack?> show(
    BuildContext context, {
    required I18nService i18n,
    String? currentTrack,
  }) {
    return showModalBottomSheet<SoundTrack?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SoundPickerWidget(
        i18n: i18n,
        currentTrack: currentTrack,
      ),
    );
  }

  @override
  State<SoundPickerWidget> createState() => _SoundPickerWidgetState();
}

class _SoundPickerWidgetState extends State<SoundPickerWidget> {
  final _soundService = SoundClipsService();
  AudioPlayer? _previewPlayer;
  String? _playingTrack;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _soundService.init();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _stopPreview();
    _previewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(SoundTrack track) async {
    if (_playingTrack == track.file) {
      await _stopPreview();
    } else {
      await _playPreview(track);
    }
  }

  Future<void> _playPreview(SoundTrack track) async {
    await _stopPreview();

    _previewPlayer ??= AudioPlayer();

    try {
      final path = _soundService.getTrackPath(track.file);
      await _previewPlayer!.setFilePath(path);
      await _previewPlayer!.play();
      setState(() => _playingTrack = track.file);

      _previewPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() => _playingTrack = null);
          }
        }
      });
    } catch (e) {
      debugPrint('SoundPickerWidget: Failed to play preview: $e');
    }
  }

  Future<void> _stopPreview() async {
    await _previewPlayer?.stop();
    if (mounted) {
      setState(() => _playingTrack = null);
    }
  }

  void _selectTrack(SoundTrack? track) {
    _stopPreview();
    Navigator.pop(context, track);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.music_note),
                    const SizedBox(width: 8),
                    Text(
                      widget.i18n.get('select_music', 'stories'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          // "None" option
                          _buildNoneOption(theme),

                          // Categories
                          ..._soundService.categories.map(
                            (category) => _buildCategoryTile(category, theme),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoneOption(ThemeData theme) {
    final isSelected = widget.currentTrack == null || widget.currentTrack!.isEmpty;

    return ListTile(
      leading: Icon(
        Icons.music_off,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        widget.i18n.get('no_music', 'stories'),
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : null,
          color: isSelected ? theme.colorScheme.primary : null,
        ),
      ),
      selected: isSelected,
      onTap: () => _selectNone(),
    );
  }

  void _selectNone() {
    _stopPreview();
    // Return a special "none" marker to distinguish from cancel
    Navigator.pop(context, SoundTrack.none());
  }

  Widget _buildCategoryTile(SoundCategory category, ThemeData theme) {
    // Check if any track in this category is selected
    final hasSelectedTrack = category.tracks.any((t) => t.file == widget.currentTrack);

    return ExpansionTile(
      leading: Icon(_getCategoryIcon(category.id)),
      title: Text(
        _capitalizeFirst(category.id),
        style: TextStyle(
          fontWeight: hasSelectedTrack ? FontWeight.bold : null,
          color: hasSelectedTrack ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        category.description,
        style: theme.textTheme.bodySmall,
      ),
      initiallyExpanded: hasSelectedTrack,
      children: category.tracks.map((track) => _buildTrackTile(track, theme)).toList(),
    );
  }

  Widget _buildTrackTile(SoundTrack track, ThemeData theme) {
    final isSelected = track.file == widget.currentTrack;
    final isPlaying = track.file == _playingTrack;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: IconButton(
        icon: Icon(
          isPlaying ? Icons.stop : Icons.play_arrow,
          color: isPlaying ? theme.colorScheme.primary : null,
        ),
        onPressed: () => _togglePreview(track),
      ),
      title: Text(
        track.displayTitle,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : null,
          color: isSelected ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        '${track.mood} - ${track.durationApprox}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: isSelected,
      onTap: () => _selectTrack(track),
    );
  }

  IconData _getCategoryIcon(String categoryId) {
    switch (categoryId) {
      case 'acoustic':
        return Icons.music_note;
      case 'ambient':
        return Icons.cloud;
      case 'chill':
        return Icons.spa;
      case 'cinematic':
        return Icons.movie;
      case 'electronic':
        return Icons.electric_bolt;
      case 'jazz':
        return Icons.piano;
      case 'upbeat':
        return Icons.flash_on;
      case 'world':
        return Icons.public;
      default:
        return Icons.music_note;
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
