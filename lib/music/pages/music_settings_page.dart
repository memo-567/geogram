/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/i18n_service.dart';
import '../models/music_settings.dart';
import '../services/music_storage_service.dart';

/// Music app settings page
class MusicSettingsPage extends StatefulWidget {
  final MusicSettings settings;
  final MusicStorageService storage;
  final I18nService i18n;

  const MusicSettingsPage({
    super.key,
    required this.settings,
    required this.storage,
    required this.i18n,
  });

  @override
  State<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends State<MusicSettingsPage> {
  late MusicSettings _settings;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _updateSettings(MusicSettings Function(MusicSettings) updater) {
    setState(() {
      _settings = updater(_settings);
      _hasChanges = true;
    });
  }

  Future<void> _saveSettings() async {
    await widget.storage.saveSettings(_settings);
    if (mounted) {
      Navigator.of(context).pop(_settings);
    }
  }

  Future<void> _addSourceFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Music Folder',
    );

    if (result != null) {
      final dir = Directory(result);
      if (await dir.exists()) {
        if (!_settings.sourceFolders.contains(result)) {
          _updateSettings((s) => s.copyWith(
                sourceFolders: [...s.sourceFolders, result],
              ));
          // Auto-save when folder is added
          await widget.storage.saveSettings(_settings);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Folder already added')),
            );
          }
        }
      }
    }
  }

  Future<void> _removeSourceFolder(String folder) async {
    _updateSettings((s) => s.copyWith(
          sourceFolders: s.sourceFolders.where((f) => f != folder).toList(),
        ));
    // Auto-save when folder is removed
    await widget.storage.saveSettings(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Settings'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveSettings,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        children: [
          // Source Folders Section
          _buildSectionHeader('Music Folders'),
          if (_settings.sourceFolders.isEmpty)
            ListTile(
              leading: Icon(Icons.info_outline, color: colorScheme.primary),
              title: const Text('No music folders added'),
              subtitle: const Text('Add a folder to scan for music'),
            )
          else
            ..._settings.sourceFolders.map((folder) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(
                    folder.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeSourceFolder(folder),
                  ),
                )),
          ListTile(
            leading: Icon(Icons.add, color: colorScheme.primary),
            title: Text(
              'Add Music Folder',
              style: TextStyle(color: colorScheme.primary),
            ),
            onTap: _addSourceFolder,
          ),
          const Divider(),

          // Scanning Section
          _buildSectionHeader('Library'),
          SwitchListTile(
            title: const Text('Scan on startup'),
            subtitle: const Text('Automatically scan folders when app opens'),
            value: _settings.scanOnStartup,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(scanOnStartup: value));
            },
          ),
          SwitchListTile(
            title: const Text('Watch for changes'),
            subtitle: const Text('Detect new files automatically'),
            value: _settings.watchFolders,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(watchFolders: value));
            },
          ),
          SwitchListTile(
            title: const Text('Group compilations'),
            subtitle: const Text('Group albums with multiple artists'),
            value: _settings.library.groupCompilations,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    library: s.library.copyWith(groupCompilations: value),
                  ));
            },
          ),
          const Divider(),

          // Playback Section
          _buildSectionHeader('Playback'),
          SwitchListTile(
            title: const Text('Gapless playback'),
            subtitle: const Text('Seamless transitions between tracks'),
            value: _settings.playback.gapless,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    playback: s.playback.copyWith(gapless: value),
                  ));
            },
          ),
          ListTile(
            title: const Text('Crossfade'),
            subtitle: Text('${_settings.playback.crossfadeSeconds} seconds'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _settings.playback.crossfadeSeconds.toDouble(),
                min: 0,
                max: 12,
                divisions: 12,
                label: '${_settings.playback.crossfadeSeconds}s',
                onChanged: (value) {
                  _updateSettings((s) => s.copyWith(
                        playback:
                            s.playback.copyWith(crossfadeSeconds: value.round()),
                      ));
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Replay Gain'),
            subtitle: Text(_settings.playback.replayGain),
            trailing: DropdownButton<String>(
              value: _settings.playback.replayGain,
              items: const [
                DropdownMenuItem(value: 'off', child: Text('Off')),
                DropdownMenuItem(value: 'track', child: Text('Track')),
                DropdownMenuItem(value: 'album', child: Text('Album')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateSettings((s) => s.copyWith(
                        playback: s.playback.copyWith(replayGain: value),
                      ));
                }
              },
            ),
          ),
          const Divider(),

          // Display Section
          _buildSectionHeader('Display'),
          ListTile(
            title: const Text('Album sort order'),
            trailing: DropdownButton<AlbumSortOrder>(
              value: _settings.display.albumSort,
              items: const [
                DropdownMenuItem(
                  value: AlbumSortOrder.artist,
                  child: Text('Artist'),
                ),
                DropdownMenuItem(
                  value: AlbumSortOrder.name,
                  child: Text('Name'),
                ),
                DropdownMenuItem(
                  value: AlbumSortOrder.year,
                  child: Text('Year'),
                ),
                DropdownMenuItem(
                  value: AlbumSortOrder.added,
                  child: Text('Date Added'),
                ),
                DropdownMenuItem(
                  value: AlbumSortOrder.mostPlayed,
                  child: Text('Most Played'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateSettings((s) => s.copyWith(
                        display: s.display.copyWith(albumSort: value),
                      ));
                }
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Show track numbers'),
            value: _settings.display.showTrackNumbers,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    display: s.display.copyWith(showTrackNumbers: value),
                  ));
            },
          ),
          const Divider(),

          // Online Features Section
          _buildSectionHeader('Online Features'),
          SwitchListTile(
            title: const Text('Auto-download cover art'),
            subtitle: const Text('Fetch missing artwork from online sources'),
            value: _settings.online.autoFetchCovers,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    online: s.online.copyWith(autoFetchCovers: value),
                  ));
            },
          ),
          if (_settings.online.autoFetchCovers)
            ListTile(
              title: const Text('Cover art quality'),
              trailing: DropdownButton<String>(
                value: _settings.online.coverSize,
                items: const [
                  DropdownMenuItem(value: 'small', child: Text('Small (250px)')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium (500px)')),
                  DropdownMenuItem(value: 'large', child: Text('Large (1200px)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateSettings((s) => s.copyWith(
                          online: s.online.copyWith(coverSize: value),
                        ));
                  }
                },
              ),
            ),
          SwitchListTile(
            title: const Text('Auto-detect genre'),
            subtitle: const Text('Use audio fingerprinting to identify genre'),
            value: _settings.online.autoDetectGenre,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    online: s.online.copyWith(autoDetectGenre: value),
                  ));
            },
          ),
          SwitchListTile(
            title: const Text('Auto-fetch lyrics'),
            subtitle: const Text('Download lyrics for tracks'),
            value: _settings.online.autoFetchLyrics,
            onChanged: (value) {
              _updateSettings((s) => s.copyWith(
                    online: s.online.copyWith(autoFetchLyrics: value),
                  ));
            },
          ),
          const Divider(),

          // Cache Section
          _buildSectionHeader('Cache'),
          ListTile(
            title: const Text('Artwork quality'),
            subtitle: Text('${_settings.cache.artworkQuality}%'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _settings.cache.artworkQuality.toDouble(),
                min: 50,
                max: 100,
                divisions: 10,
                label: '${_settings.cache.artworkQuality}%',
                onChanged: (value) {
                  _updateSettings((s) => s.copyWith(
                        cache:
                            s.cache.copyWith(artworkQuality: value.round()),
                      ));
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Max cache size'),
            subtitle: Text('${_settings.cache.maxCacheSizeMb} MB'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _settings.cache.maxCacheSizeMb.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                label: '${_settings.cache.maxCacheSizeMb} MB',
                onChanged: (value) {
                  _updateSettings((s) => s.copyWith(
                        cache:
                            s.cache.copyWith(maxCacheSizeMb: value.round()),
                      ));
                },
              ),
            ),
          ),
          ListTile(
            title: const Text('Clear artwork cache'),
            leading: const Icon(Icons.delete_outline),
            onTap: () async {
              await widget.storage.clearArtworkCache();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Artwork cache cleared')),
                );
              }
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
