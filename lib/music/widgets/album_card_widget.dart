/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/music_album.dart';

/// A card for displaying an album
class AlbumCardWidget extends StatelessWidget {
  final MusicAlbum album;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AlbumCardWidget({
    super.key,
    required this.album,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected ? colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork - Expanded to fill available space
            Expanded(
              child: _buildArtwork(colorScheme),
            ),
            // Album info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artist + (album.year != null ? ' (${album.year})' : ''),
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
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(ColorScheme colorScheme) {
    if (album.artwork != null) {
      final file = File(album.artwork!);
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
          Icons.album,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A list tile variant for album display
class AlbumListTile extends StatelessWidget {
  final MusicAlbum album;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const AlbumListTile({
    super.key,
    required this.album,
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
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: _buildArtwork(colorScheme),
        ),
      ),
      title: Text(
        album.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${album.artist}${album.year != null ? ' (${album.year})' : ''}'
        ' - ${album.trackCount} tracks',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildArtwork(ColorScheme colorScheme) {
    if (album.artwork != null) {
      final file = File(album.artwork!);
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
      child: Icon(
        Icons.album,
        size: 24,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
