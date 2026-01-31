/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import 'animated_equalizer_widget.dart';

/// A list tile for displaying a track
class TrackTileWidget extends StatelessWidget {
  final MusicTrack track;
  final bool showTrackNumber;
  final bool showAlbum;
  /// Whether this is the current track (shows equalizer icon)
  final bool isPlaying;
  /// Whether playback is actually playing (animates the equalizer)
  final bool isActuallyPlaying;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const TrackTileWidget({
    super.key,
    required this.track,
    this.showTrackNumber = true,
    this.showAlbum = false,
    this.isPlaying = false,
    this.isActuallyPlaying = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      selected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: _buildLeading(colorScheme),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        showAlbum && track.album != null
            ? '${track.artist} - ${track.album}'
            : track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isPlaying ? colorScheme.primary.withOpacity(0.7) : null,
        ),
      ),
      trailing: trailing ??
          Text(
            track.formattedDuration,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
    );
  }

  Widget _buildLeading(ColorScheme colorScheme) {
    if (isPlaying) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: AnimatedEqualizerWidget(
            size: 24,
            color: colorScheme.primary,
            isPlaying: isActuallyPlaying,
          ),
        ),
      );
    }

    if (showTrackNumber && track.trackNumber != null) {
      return Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Text(
          '${track.trackNumber}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A compact track tile for queue display
class CompactTrackTile extends StatelessWidget {
  final MusicTrack track;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const CompactTrackTile({
    super.key,
    required this.track,
    this.isPlaying = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isPlaying ? colorScheme.primaryContainer.withOpacity(0.3) : null,
        child: Row(
          children: [
            if (isPlaying)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.play_arrow,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.formattedDuration,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}
