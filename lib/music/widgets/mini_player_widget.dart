/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_playback_service.dart';

/// Mini player bar shown at bottom of screen
class MiniPlayerWidget extends StatelessWidget {
  final MusicPlaybackService playback;
  final VoidCallback? onTap;

  const MiniPlayerWidget({
    super.key,
    required this.playback,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<MusicTrack?>(
      stream: playback.trackStream,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data ?? playback.currentTrack;
        if (track == null) {
          return const SizedBox.shrink();
        }

        return Material(
          elevation: 8,
          color: colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar
                  StreamBuilder<Duration>(
                    stream: playback.positionStream,
                    builder: (context, posSnapshot) {
                      return StreamBuilder<Duration>(
                        stream: playback.durationStream,
                        builder: (context, durSnapshot) {
                          final position = posSnapshot.data ?? playback.position;
                          final duration = durSnapshot.data ?? playback.duration;
                          final progress = duration.inMilliseconds > 0
                              ? position.inMilliseconds / duration.inMilliseconds
                              : 0.0;

                          return LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                          );
                        },
                      );
                    },
                  ),
                  // Player controls
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        // Artwork
                        _buildArtwork(track, colorScheme),
                        // Track info
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
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
                        ),
                        // Play/pause button
                        StreamBuilder<MusicPlaybackState>(
                          stream: playback.stateStream,
                          builder: (context, stateSnapshot) {
                            final state = stateSnapshot.data ?? playback.state;
                            final isPlaying = state == MusicPlaybackState.playing;

                            return IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 32,
                              ),
                              onPressed: () {
                                if (isPlaying) {
                                  playback.pause();
                                } else {
                                  playback.play();
                                }
                              },
                            );
                          },
                        ),
                        // Next button
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          onPressed: playback.hasNext ? playback.next : null,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtwork(MusicTrack track, ColorScheme colorScheme) {
    // Try to get album artwork
    Widget placeholder = Container(
      width: 64,
      height: 64,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    // For now, just show placeholder
    // TODO: Load album artwork from track.albumId
    return placeholder;
  }
}
