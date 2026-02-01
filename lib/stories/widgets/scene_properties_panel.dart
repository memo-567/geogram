/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../services/i18n_service.dart';
import '../models/story_scene.dart';
import '../services/sound_clips_service.dart';
import 'sound_picker_widget.dart';

/// Panel for editing scene-level properties
class ScenePropertiesPanel extends StatefulWidget {
  final StoryScene scene;
  final List<StoryScene> allScenes;
  final I18nService i18n;
  final ValueChanged<StoryScene> onSceneChanged;
  final VoidCallback? onSelectBackgroundImage;
  final ValueChanged<String?>? onSceneTitleChanged;
  final ValueChanged<String?>? onSceneDescriptionChanged;

  const ScenePropertiesPanel({
    super.key,
    required this.scene,
    required this.allScenes,
    required this.i18n,
    required this.onSceneChanged,
    this.onSelectBackgroundImage,
    this.onSceneTitleChanged,
    this.onSceneDescriptionChanged,
  });

  @override
  State<ScenePropertiesPanel> createState() => _ScenePropertiesPanelState();
}

class _ScenePropertiesPanelState extends State<ScenePropertiesPanel> {
  final _soundService = SoundClipsService();

  @override
  void initState() {
    super.initState();
    _initSoundService();
  }

  Future<void> _initSoundService() async {
    await _soundService.init();
    if (mounted) setState(() {});
  }

  I18nService get i18n => widget.i18n;
  StoryScene get scene => widget.scene;
  List<StoryScene> get allScenes => widget.allScenes;
  void onSceneChanged(StoryScene s) => widget.onSceneChanged(s);
  VoidCallback? get onSelectBackgroundImage => widget.onSelectBackgroundImage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildTitleSection(context),
          const SizedBox(height: 16),
          _buildDescriptionSection(context),
          const SizedBox(height: 16),
          _buildBackgroundSection(context),
          const SizedBox(height: 16),
          _buildBackgroundMusicSection(context),
          const SizedBox(height: 16),
          _buildNavigationSection(context),
          const SizedBox(height: 16),
          _buildAutoAdvanceSection(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Icon(Icons.layers, size: 20),
        const SizedBox(width: 8),
        Text(
          i18n.get('scene', 'stories'),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _buildTitleSection(BuildContext context) {
    final defaultTitle = '${i18n.get('scene', 'stories')} ${scene.index + 1}';
    return _Section(
      title: i18n.get('scene_title', 'stories'),
      child: TextField(
        controller: TextEditingController(text: scene.title ?? ''),
        decoration: InputDecoration(
          hintText: defaultTitle,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final newTitle = value.isEmpty ? null : value;
          onSceneChanged(scene.copyWith(title: newTitle));
          // Notify about title change for auto-managed element
          widget.onSceneTitleChanged?.call(
            _isDefaultTitle(value, scene.index) ? null : value,
          );
        },
      ),
    );
  }

  /// Check if title matches the default "Scene N" pattern
  bool _isDefaultTitle(String title, int index) {
    if (title.isEmpty) return true;
    final defaultPattern = '${i18n.get('scene', 'stories')} ${index + 1}';
    return title == defaultPattern;
  }

  Widget _buildDescriptionSection(BuildContext context) {
    return _Section(
      title: i18n.get('scene_description', 'stories'),
      child: TextField(
        controller: TextEditingController(text: scene.description ?? ''),
        decoration: InputDecoration(
          hintText: i18n.get('scene_description_hint', 'stories'),
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
        onChanged: (value) {
          final newDescription = value.isEmpty ? null : value;
          onSceneChanged(scene.copyWith(
            description: newDescription,
            clearDescription: value.isEmpty,
          ));
          // Notify about description change for auto-managed element
          widget.onSceneDescriptionChanged?.call(newDescription);
        },
      ),
    );
  }

  Widget _buildBackgroundSection(BuildContext context) {
    final bg = scene.background;

    return _Section(
      title: i18n.get('scene_background', 'stories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image selection (required)
          Row(
            children: [
              Expanded(
                child: bg.hasImage
                    ? Row(
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.get('scene_background_image', 'stories'),
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(Icons.warning, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.get('media_select', 'stories'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.orange.shade700,
                                  ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.image, size: 18),
                label: Text(bg.hasImage
                    ? i18n.get('scene_background_image', 'stories')
                    : i18n.get('media_select', 'stories')),
                onPressed: onSelectBackgroundImage,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Letterbox/placeholder color
          _ColorPickerRow(
            label: i18n.get('scene_background_color', 'stories'),
            color: _parseColor(bg.placeholder),
            onColorChanged: (color) {
              final newBg = bg.copyWith(placeholder: _colorToHex(color));
              onSceneChanged(scene.copyWith(background: newBg));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundMusicSection(BuildContext context) {
    // null = use story music, "" = silence, "path" = override
    final hasOverride = scene.backgroundMusic != null;
    final isSilence = scene.backgroundMusic == '';
    final track = hasOverride && !isSilence
        ? _soundService.findTrack(scene.backgroundMusic!)
        : null;

    return _Section(
      title: i18n.get('background_music', 'stories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle for override
          SwitchListTile(
            title: Text(i18n.get('scene_music_override', 'stories')),
            subtitle: Text(
              i18n.get('scene_music_override_hint', 'stories'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: hasOverride,
            onChanged: (value) {
              if (value) {
                // Enable override with silence by default
                onSceneChanged(scene.copyWith(backgroundMusic: ''));
              } else {
                // Disable override - use story music
                onSceneChanged(scene.copyWith(clearBackgroundMusic: true));
              }
            },
            contentPadding: EdgeInsets.zero,
          ),

          if (hasOverride) ...[
            const SizedBox(height: 8),

            // Silence option
            CheckboxListTile(
              title: Text(i18n.get('scene_music_silence', 'stories')),
              value: isSilence,
              onChanged: (value) {
                if (value == true) {
                  onSceneChanged(scene.copyWith(backgroundMusic: ''));
                } else {
                  // Clear to null temporarily, user will select a track
                  onSceneChanged(scene.copyWith(clearBackgroundMusic: true));
                }
              },
              contentPadding: EdgeInsets.zero,
            ),

            if (!isSilence) ...[
              const SizedBox(height: 8),

              // Track selector
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  track != null ? Icons.music_note : Icons.music_off,
                  color: track != null ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(
                  track?.displayTitle ?? i18n.get('select_music', 'stories'),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: track != null
                    ? Text('${track.mood} - ${track.durationApprox}')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _selectSceneMusic(context),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _selectSceneMusic(BuildContext context) async {
    final selected = await SoundPickerWidget.show(
      context,
      i18n: i18n,
      currentTrack: scene.backgroundMusic,
    );

    if (mounted && selected != null) {
      onSceneChanged(scene.copyWith(backgroundMusic: selected.file));
    }
  }

  Widget _buildNavigationSection(BuildContext context) {
    return _Section(
      title: i18n.get('position', 'stories'),
      child: SwitchListTile(
        title: Text(i18n.get('scene_allow_back', 'stories')),
        value: scene.allowBack ?? true,
        onChanged: (value) {
          onSceneChanged(scene.copyWith(allowBack: value));
        },
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildAutoAdvanceSection(BuildContext context) {
    final autoAdvance = scene.autoAdvance;
    final hasAutoAdvance = autoAdvance != null;

    return _Section(
      title: i18n.get('auto_advance', 'stories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text(i18n.get('auto_advance_enabled', 'stories')),
            value: hasAutoAdvance,
            onChanged: (value) {
              if (value) {
                // Enable with default values
                final targetScene = allScenes
                    .where((s) => s.id != scene.id)
                    .firstOrNull;
                if (targetScene != null) {
                  onSceneChanged(scene.copyWith(
                    autoAdvance: AutoAdvance(
                      delay: 5000,
                      targetSceneId: targetScene.id,
                    ),
                  ));
                }
              } else {
                // Disable - need to create a new scene without autoAdvance
                final newScene = StoryScene(
                  id: scene.id,
                  index: scene.index,
                  title: scene.title,
                  allowBack: scene.allowBack,
                  background: scene.background,
                  elements: scene.elements,
                  triggers: scene.triggers,
                  autoAdvance: null,
                );
                onSceneChanged(newScene);
              }
            },
            contentPadding: EdgeInsets.zero,
          ),

          if (hasAutoAdvance) ...[
            const SizedBox(height: 8),

            // Delay slider
            Text('${i18n.get('auto_advance_delay', 'stories')}: ${autoAdvance.delaySeconds}s'),
            Slider(
              value: autoAdvance.delay.toDouble(),
              min: 1000,
              max: 60000,
              divisions: 59,
              label: '${autoAdvance.delaySeconds}s',
              onChanged: (value) {
                onSceneChanged(scene.copyWith(
                  autoAdvance: AutoAdvance(
                    delay: value.round(),
                    targetSceneId: autoAdvance.targetSceneId,
                    showCountdown: autoAdvance.showCountdown,
                  ),
                ));
              },
            ),

            const SizedBox(height: 8),

            // Target scene
            DropdownButtonFormField<String>(
              initialValue: autoAdvance.targetSceneId,
              decoration: InputDecoration(
                labelText: i18n.get('auto_advance_target', 'stories'),
                border: const OutlineInputBorder(),
              ),
              items: allScenes
                  .where((s) => s.id != scene.id)
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.title ?? '${i18n.get('scene', 'stories')} ${s.index + 1}'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                onSceneChanged(scene.copyWith(
                  autoAdvance: AutoAdvance(
                    delay: autoAdvance.delay,
                    targetSceneId: value,
                    showCountdown: autoAdvance.showCountdown,
                  ),
                ));
              },
            ),

            const SizedBox(height: 8),

            // Show countdown
            SwitchListTile(
              title: Text(i18n.get('auto_advance_countdown', 'stories')),
              value: autoAdvance.showCountdown,
              onChanged: (value) {
                onSceneChanged(scene.copyWith(
                  autoAdvance: AutoAdvance(
                    delay: autoAdvance.delay,
                    targetSceneId: autoAdvance.targetSceneId,
                    showCountdown: value,
                  ),
                ));
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      final hex = colorString.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return Colors.black;
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const _ColorPickerRow({
    required this.label,
    required this.color,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        GestureDetector(
          onTap: () => _showColorPicker(context),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context) {
    Color selectedColor = color;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: color,
            onColorChanged: (newColor) => selectedColor = newColor,
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onColorChanged(selectedColor);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
