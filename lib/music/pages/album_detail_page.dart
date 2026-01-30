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
class AlbumDetailPage extends StatefulWidget {
  final MusicAlbum album;
  final MusicLibrary library;
  final MusicPlaybackService playback;
  final I18nService i18n;
  final FetchArtworkCallback? onFetchArtwork;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.library,
    required this.playback,
    required this.i18n,
    this.onFetchArtwork,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  String? _artworkPath;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _artworkPath = widget.album.artwork;
    _tryFetchArtwork();
  }

  void _tryFetchArtwork() {
    if (_artworkPath == null && !_isFetching && widget.onFetchArtwork != null) {
      setState(() => _isFetching = true);
      widget.onFetchArtwork!(widget.album).then((path) {
        if (mounted) {
          setState(() {
            _artworkPath = path;
            _isFetching = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracks = widget.library.getAlbumTracks(widget.album.id);
    final currentTrackId = widget.playback.currentTrack?.id;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with album artwork
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.album.title,
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
                  if (_artworkPath != null)
                    Image.file(
                      File(_artworkPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholder(colorScheme);
                      },
                    )
                  else if (_isFetching)
                    _buildLoadingPlaceholder(colorScheme)
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
                  widget.playback.playTracks(tracks);
                  widget.playback.toggleShuffle();
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
                    widget.album.artist,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (widget.album.year != null) '${widget.album.year}',
                      '${widget.album.trackCount} tracks',
                      widget.album.formattedDuration,
                    ].join(' - '),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.album.genre != null) ...[
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
                        widget.album.genre!,
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
                          widget.playback.playAlbum(widget.album.id);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          // Add all tracks to queue
                          for (final track in tracks) {
                            widget.playback.addToQueue(track.id);
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
                  stream: widget.playback.trackStream,
                  builder: (context, snapshot) {
                    final isPlaying = (snapshot.data?.id ?? currentTrackId) == track.id;
                    return TrackTileWidget(
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () {
                        widget.playback.playAlbum(widget.album.id, startIndex: index);
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'queue':
                              widget.playback.addToQueue(track.id);
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
        playback: widget.playback,
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
                  playback: widget.playback,
                  library: widget.library,
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

  Widget _buildLoadingPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
