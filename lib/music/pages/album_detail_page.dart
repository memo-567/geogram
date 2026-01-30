/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../models/music_models.dart';
import '../services/music_playback_service.dart';
import '../widgets/music_widgets.dart';

/// Album detail page showing tracks
class AlbumDetailPage extends StatelessWidget {
  final MusicAlbum album;
  final MusicLibrary library;
  final MusicPlaybackService playback;
  final I18nService i18n;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.library,
    required this.playback,
    required this.i18n,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracks = library.getAlbumTracks(album.id);
    final currentTrackId = playback.currentTrack?.id;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with album artwork
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                album.title,
                style: const TextStyle(
                  shadows: [
                    Shadow(
                      blurRadius: 10,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Album artwork
                  if (album.artwork != null)
                    Image.file(
                      File(album.artwork!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholder(colorScheme);
                      },
                    )
                  else
                    _buildPlaceholder(colorScheme),
                  // Gradient overlay
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black54,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: () {
                  playback.playTracks(tracks);
                  playback.toggleShuffle();
                },
                tooltip: 'Shuffle play',
              ),
            ],
          ),
          // Album info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.artist,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (album.year != null) '${album.year}',
                      '${album.trackCount} tracks',
                      album.formattedDuration,
                    ].join(' - '),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (album.genre != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        album.genre!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Play all button
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          playback.playAlbum(album.id);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          // Add all tracks to queue
                          for (final track in tracks) {
                            playback.addToQueue(track.id);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added ${tracks.length} tracks to queue',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add to Queue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Divider
          SliverToBoxAdapter(
            child: Divider(color: colorScheme.outlineVariant),
          ),
          // Track list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = tracks[index];
                return StreamBuilder<MusicTrack?>(
                  stream: playback.trackStream,
                  builder: (context, snapshot) {
                    final isPlaying = (snapshot.data?.id ?? currentTrackId) == track.id;
                    return TrackTileWidget(
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () {
                        playback.playAlbum(album.id, startIndex: index);
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'queue':
                              playback.addToQueue(track.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Added to queue'),
                                ),
                              );
                              break;
                            case 'playlist':
                              // TODO: Add to playlist
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'queue',
                            child: ListTile(
                              leading: Icon(Icons.playlist_add),
                              title: Text('Add to queue'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'playlist',
                            child: ListTile(
                              leading: Icon(Icons.playlist_add_check),
                              title: Text('Add to playlist'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              childCount: tracks.length,
            ),
          ),
          // Bottom padding for mini player
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
      bottomNavigationBar: MiniPlayerWidget(
        playback: playback,
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: NowPlayingWidget(
                  playback: playback,
                  library: library,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album,
          size: 80,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
