/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../models/music_models.dart';
import '../services/music_services.dart';
import '../widgets/music_widgets.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';
import 'music_settings_page.dart';

/// Main music app home page
class MusicHomePage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;
  final I18nService i18n;

  const MusicHomePage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
    required this.i18n,
  });

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late MusicStorageService _storage;
  late MusicLibraryService _libraryService;
  late MusicPlaybackService _playbackService;

  MusicSettings _settings = MusicSettings();
  MusicLibrary _library = MusicLibrary();
  bool _isLoading = true;
  bool _isScanning = false;
  String? _scanStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _storage = MusicStorageService(basePath: widget.collectionPath);
    _libraryService = MusicLibraryService(storage: _storage);
    _playbackService = MusicPlaybackService(storage: _storage);

    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _playbackService.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Load settings
    _settings = await _storage.loadSettings();

    // Ensure cache directories
    await _storage.ensureCacheDirectories();

    // Load library
    _library = await _libraryService.loadLibrary();

    // Initialize playback
    await _playbackService.initialize(_library);

    setState(() {
      _isLoading = false;
    });

    // Auto-scan if needed
    if (_library.isEmpty && _settings.sourceFolders.isNotEmpty) {
      _scanLibrary();
    }
  }

  Future<void> _scanLibrary() async {
    if (_isScanning || _settings.sourceFolders.isEmpty) return;

    setState(() {
      _isScanning = true;
      _scanStatus = 'Starting scan...';
    });

    try {
      _library = await _libraryService.scanFolders(
        _settings.sourceFolders,
        onProgress: (scanned, total, currentFile) {
          setState(() {
            _scanStatus = 'Scanning: $scanned/$total';
          });
        },
      );

      // Re-initialize playback with new library
      await _playbackService.initialize(_library);
    } finally {
      setState(() {
        _isScanning = false;
        _scanStatus = null;
      });
    }
  }

  void _openSettings() async {
    final result = await Navigator.of(context).push<MusicSettings>(
      MaterialPageRoute(
        builder: (context) => MusicSettingsPage(
          settings: _settings,
          storage: _storage,
          i18n: widget.i18n,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _settings = result;
      });

      // Rescan if source folders changed
      if (result.sourceFolders != _settings.sourceFolders) {
        _scanLibrary();
      }
    }
  }

  void _openNowPlaying() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: NowPlayingWidget(
            playback: _playbackService,
            library: _library,
          ),
        ),
      ),
    );
  }

  void _openAlbum(MusicAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AlbumDetailPage(
          album: album,
          library: _library,
          playback: _playbackService,
          i18n: widget.i18n,
        ),
      ),
    );
  }

  void _openArtist(MusicArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ArtistDetailPage(
          artist: artist,
          library: _library,
          playback: _playbackService,
          i18n: widget.i18n,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collectionTitle),
        actions: [
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _scanLibrary,
              tooltip: 'Rescan library',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Artists'),
            Tab(text: 'Albums'),
            Tab(text: 'Tracks'),
            Tab(text: 'Playlists'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Status bar
                if (_scanStatus != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: colorScheme.primaryContainer,
                    child: Text(
                      _scanStatus!,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                // Main content
                Expanded(
                  child: _library.isEmpty
                      ? _buildEmptyState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildArtistsTab(),
                            _buildAlbumsTab(),
                            _buildTracksTab(),
                            _buildPlaylistsTab(),
                          ],
                        ),
                ),
                // Mini player
                MiniPlayerWidget(
                  playback: _playbackService,
                  onTap: _openNowPlaying,
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            const Text(
              'No music found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _settings.sourceFolders.isEmpty
                  ? 'Add a music folder in settings to get started'
                  : 'Tap the refresh button to scan your music folders',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (_settings.sourceFolders.isEmpty)
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.folder_open),
                label: const Text('Add Music Folder'),
              )
            else
              FilledButton.icon(
                onPressed: _scanLibrary,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan Library'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistsTab() {
    final artists = _library.artists;

    if (artists.isEmpty) {
      return const Center(child: Text('No artists found'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ArtistCardWidget(
          artist: artist,
          onTap: () => _openArtist(artist),
        );
      },
    );
  }

  Widget _buildAlbumsTab() {
    final albums = _library.albums;

    if (albums.isEmpty) {
      return const Center(child: Text('No albums found'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return AlbumCardWidget(
          album: album,
          onTap: () => _openAlbum(album),
        );
      },
    );
  }

  Widget _buildTracksTab() {
    final tracks = _library.tracks;

    if (tracks.isEmpty) {
      return const Center(child: Text('No tracks found'));
    }

    final currentTrackId = _playbackService.currentTrack?.id;

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return TrackTileWidget(
          track: track,
          showAlbum: true,
          showTrackNumber: false,
          isPlaying: track.id == currentTrackId,
          onTap: () {
            _playbackService.playTracks(tracks, startIndex: index);
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab() {
    // TODO: Implement playlists
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.playlist_play, size: 64),
          SizedBox(height: 16),
          Text('Playlists coming soon'),
        ],
      ),
    );
  }
}
