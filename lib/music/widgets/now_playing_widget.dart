/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/music_models.dart';
import '../services/music_playback_service.dart';

/// Full-screen now playing view
class NowPlayingWidget extends StatelessWidget {
  final MusicPlaybackService playback;
  final MusicLibrary? library;
  final VoidCallback? onClose;

  const NowPlayingWidget({
    super.key,
    required this.playback,
    this.library,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: onClose ?? () => Navigator.of(context).pop(),
        ),
        title: const Text('Now Playing'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              _showQueue(context);
            },
          ),
        ],
      ),
      body: StreamBuilder<MusicTrack?>(
        stream: playback.trackStream,
        builder: (context, trackSnapshot) {
          final track = trackSnapshot.data ?? playback.currentTrack;
          if (track == null) {
            return const Center(
              child: Text('No track playing'),
            );
          }

          final album = library?.getAlbum(track.albumId ?? '');

          return SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 1),
                // Album artwork
                Container(
                  width: screenSize.width * 0.75,
                  height: screenSize.width * 0.75,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildArtwork(album, colorScheme),
                  ),
                ),
                const Spacer(flex: 1),
                // Track info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (album != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _buildProgressBar(context),
                ),
                const SizedBox(height: 16),
                // Playback controls
                _buildControls(context),
                const Spacer(flex: 2),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtwork(MusicAlbum? album, ColorScheme colorScheme) {
    if (album?.artwork != null) {
      final file = File(album!.artwork!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(colorScheme);
        },
      );
    }
    return _buildPlaceholder(colorScheme);
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 80,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
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

            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: colorScheme.surfaceContainerHighest,
                    thumbColor: colorScheme.primary,
                    overlayColor: colorScheme.primary.withOpacity(0.2),
                  ),
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      final newPosition = Duration(
                        milliseconds: (value * duration.inMilliseconds).round(),
                      );
                      playback.seek(newPosition);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlaybackQueue>(
      stream: playback.queueStream,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? playback.queue;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle button
            IconButton(
              icon: Icon(
                Icons.shuffle,
                color: queue.shuffle
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: playback.toggleShuffle,
            ),
            const SizedBox(width: 16),
            // Previous button
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: playback.previous,
            ),
            const SizedBox(width: 8),
            // Play/Pause button
            StreamBuilder<MusicPlaybackState>(
              stream: playback.stateStream,
              builder: (context, stateSnapshot) {
                final state = stateSnapshot.data ?? playback.state;
                final isPlaying = state == MusicPlaybackState.playing;
                final isLoading = state == MusicPlaybackState.loading;

                return Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: colorScheme.onPrimary,
                            size: 40,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              playback.pause();
                            } else {
                              playback.play();
                            }
                          },
                        ),
                );
              },
            ),
            const SizedBox(width: 8),
            // Next button
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: playback.next,
            ),
            const SizedBox(width: 16),
            // Repeat button
            IconButton(
              icon: Icon(
                queue.repeat == RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: queue.repeat != RepeatMode.off
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: playback.cycleRepeat,
            ),
          ],
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return _QueueSheet(
            playback: playback,
            library: library,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _QueueSheet extends StatelessWidget {
  final MusicPlaybackService playback;
  final MusicLibrary? library;
  final ScrollController scrollController;

  const _QueueSheet({
    required this.playback,
    this.library,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<PlaybackQueue>(
      stream: playback.queueStream,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? playback.queue;

        if (queue.isEmpty) {
          return const Center(
            child: Text('Queue is empty'),
          );
        }

        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Queue (${queue.length} tracks)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: playback.clearQueue,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Queue list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: queue.trackIds.length,
                itemBuilder: (context, index) {
                  final trackId = queue.trackIds[index];
                  final track = library?.getTrack(trackId);
                  final isCurrent = index == queue.currentIndex;

                  if (track == null) {
                    return ListTile(
                      title: Text('Unknown track: $trackId'),
                    );
                  }

                  return ListTile(
                    leading: isCurrent
                        ? Icon(Icons.equalizer, color: colorScheme.primary)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : null,
                        color: isCurrent ? colorScheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurrent
                            ? colorScheme.primary.withOpacity(0.7)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Text(
                      track.formattedDuration,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () {
                      // Play this track
                      playback.playTrack(trackId);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
