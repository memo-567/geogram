/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../../util/app_constants.dart';
import '../models/story.dart';
import '../services/sound_clips_service.dart';
import 'sound_picker_widget.dart';

/// Dialog for editing story metadata (title, description, categories, background music)
class StorySettingsDialog extends StatefulWidget {
  final Story story;
  final I18nService i18n;
  final String? currentBackgroundMusic;

  const StorySettingsDialog({
    super.key,
    required this.story,
    required this.i18n,
    this.currentBackgroundMusic,
  });

  /// Shows the dialog and returns updated story data or null if cancelled
  static Future<StorySettingsResult?> show(
    BuildContext context, {
    required Story story,
    required I18nService i18n,
    String? currentBackgroundMusic,
  }) {
    return showDialog<StorySettingsResult>(
      context: context,
      builder: (context) => StorySettingsDialog(
        story: story,
        i18n: i18n,
        currentBackgroundMusic: currentBackgroundMusic,
      ),
    );
  }

  @override
  State<StorySettingsDialog> createState() => _StorySettingsDialogState();
}

class _StorySettingsDialogState extends State<StorySettingsDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late Set<String> _selectedCategories;
  String? _backgroundMusic;
  final _soundService = SoundClipsService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.story.title);
    _descController = TextEditingController(text: widget.story.description ?? '');
    _selectedCategories = Set<String>.from(widget.story.tags);
    _backgroundMusic = widget.currentBackgroundMusic;
    _initSoundService();
  }

  Future<void> _initSoundService() async {
    await _soundService.init();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.get('story_settings', 'stories')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: widget.i18n.get('story_title', 'stories'),
                hintText: widget.i18n.get('story_title_hint', 'stories'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: widget.i18n.get('story_description', 'stories'),
                hintText: widget.i18n.get('story_description_hint', 'stories'),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.get('story_categories', 'stories'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: storyCategoriesConst.map((category) {
                final isSelected = _selectedCategories.contains(category);
                return FilterChip(
                  label: Text(widget.i18n.get('category_$category', 'stories')),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedCategories.add(category);
                      } else {
                        _selectedCategories.remove(category);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.get('background_music', 'stories'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildBackgroundMusicSection(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _titleController.text.isNotEmpty
              ? () => Navigator.pop(
                    context,
                    StorySettingsResult(
                      title: _titleController.text,
                      description: _descController.text.isNotEmpty
                          ? _descController.text
                          : null,
                      categories: _selectedCategories.toList(),
                      backgroundMusic: _backgroundMusic,
                      backgroundMusicChanged: _backgroundMusic != widget.currentBackgroundMusic,
                    ),
                  )
              : null,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _buildBackgroundMusicSection(BuildContext context) {
    final track = _backgroundMusic != null && _backgroundMusic!.isNotEmpty
        ? _soundService.findTrack(_backgroundMusic!)
        : null;

    return Row(
      children: [
        Expanded(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              track != null ? Icons.music_note : Icons.music_off,
              color: track != null ? Theme.of(context).colorScheme.primary : null,
            ),
            title: Text(
              track?.displayTitle ?? widget.i18n.get('no_music', 'stories'),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: track != null
                ? Text('${track.mood} - ${track.durationApprox}')
                : null,
            onTap: _selectBackgroundMusic,
          ),
        ),
        if (_backgroundMusic != null && _backgroundMusic!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _backgroundMusic = null),
            tooltip: widget.i18n.get('no_music', 'stories'),
          ),
      ],
    );
  }

  Future<void> _selectBackgroundMusic() async {
    final selected = await SoundPickerWidget.show(
      context,
      i18n: widget.i18n,
      currentTrack: _backgroundMusic,
    );

    // null = cancelled (keep current), SoundTrack.none() = "None" selected, otherwise = track selected
    if (selected != null && mounted) {
      setState(() {
        _backgroundMusic = selected.isNone ? null : selected.file;
      });
    }
  }
}

/// Result from the story settings dialog
class StorySettingsResult {
  final String title;
  final String? description;
  final List<String> categories;
  final String? backgroundMusic;
  final bool backgroundMusicChanged;

  const StorySettingsResult({
    required this.title,
    this.description,
    required this.categories,
    this.backgroundMusic,
    this.backgroundMusicChanged = false,
  });
}
