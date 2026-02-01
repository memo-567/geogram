/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/i18n_service.dart';
import '../models/story.dart';
import '../models/story_content.dart';
import '../models/story_element.dart';
import '../models/story_scene.dart';
import '../models/story_trigger.dart';
import '../services/stories_storage_service.dart';
import '../widgets/add_element_dialog.dart';
import '../widgets/element_properties_panel.dart';
import '../widgets/scene_editor_canvas.dart';
import '../widgets/scene_properties_panel.dart';
import 'story_viewer_page.dart';

/// Story Studio - editor for creating and modifying stories
class StoryStudioPage extends StatefulWidget {
  final Story story;
  final StoriesStorageService storage;
  final I18nService i18n;

  const StoryStudioPage({
    super.key,
    required this.story,
    required this.storage,
    required this.i18n,
  });

  @override
  State<StoryStudioPage> createState() => _StoryStudioPageState();
}

class _StoryStudioPageState extends State<StoryStudioPage> {
  StoryContent? _content;
  StoryScene? _selectedScene;
  String? _selectedElementId;
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _showSceneProperties = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);
    try {
      _content = await widget.storage.loadStoryContent(widget.story);
      if (_content != null && _content!.orderedScenes.isNotEmpty) {
        _selectedScene = _content!.orderedScenes.first;
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveContent() async {
    if (_content == null) return;

    await widget.storage.saveStoryContent(widget.story, _content!);
    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _addScene() async {
    if (_content == null) return;

    // Prompt for background image immediately
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return; // User cancelled

    final sceneId = 'scene-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    // Add image to story assets
    final assetRef = await widget.storage.addMedia(widget.story, image.path);

    final newScene = StoryScene(
      id: sceneId,
      index: _content!.sceneCount,
      title: '${widget.i18n.get('scene', 'stories')} ${_content!.sceneCount + 1}',
      background: SceneBackground(asset: assetRef, placeholder: '#000000'),
      elements: [],
      triggers: [],
    );

    setState(() {
      _content = _content!.addScene(newScene);
      _selectedScene = newScene;
      _selectedElementId = null;
      _hasChanges = true;
    });
  }

  Future<void> _deleteScene(StoryScene scene) async {
    if (_content == null || _content!.sceneCount <= 1) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.get('scene_delete', 'stories')),
        content: Text(widget.i18n.get('scene_delete_confirm', 'stories')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.get('scene_delete', 'stories')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _content = _content!.removeScene(scene.id);
        if (_selectedScene?.id == scene.id) {
          _selectedScene = _content!.orderedScenes.firstOrNull;
          _selectedElementId = null;
        }
        _hasChanges = true;
      });
    }
  }

  void _updateScene(StoryScene updatedScene) {
    if (_content == null) return;

    setState(() {
      _content = _content!.updateScene(updatedScene);
      _selectedScene = updatedScene;
      _hasChanges = true;
    });
  }

  void _updateElement(StoryElement updatedElement) {
    if (_selectedScene == null) return;

    final elements = _selectedScene!.elements.map((e) {
      return e.id == updatedElement.id ? updatedElement : e;
    }).toList();

    _updateScene(_selectedScene!.copyWith(elements: elements));
  }

  void _updateTrigger(StoryTrigger? trigger) {
    if (_selectedScene == null || _selectedElementId == null) return;

    // Remove existing trigger for this element
    var triggers = _selectedScene!.triggers
        .where((t) => t.elementId != _selectedElementId)
        .toList();

    // Add new trigger if provided
    if (trigger != null) {
      triggers = [...triggers, trigger];
    }

    _updateScene(_selectedScene!.copyWith(triggers: triggers));
  }

  Future<void> _addElement(ElementType type) async {
    if (_selectedScene == null) return;

    final element = await showAddElementDialog(
      context,
      elementType: type,
      i18n: widget.i18n,
    );

    if (element != null) {
      final elements = [..._selectedScene!.elements, element];
      _updateScene(_selectedScene!.copyWith(elements: elements));
      setState(() => _selectedElementId = element.id);
    }
  }

  void _deleteSelectedElement() {
    if (_selectedScene == null || _selectedElementId == null) return;

    final elements = _selectedScene!.elements
        .where((e) => e.id != _selectedElementId)
        .toList();
    final triggers = _selectedScene!.triggers
        .where((t) => t.elementId != _selectedElementId)
        .toList();

    _updateScene(_selectedScene!.copyWith(
      elements: elements,
      triggers: triggers,
    ));

    setState(() => _selectedElementId = null);
  }

  Future<void> _selectBackgroundImage() async {
    if (_selectedScene == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // Add image to story assets
      final assetRef = await widget.storage.addMedia(widget.story, image.path);

      final newBg = _selectedScene!.background.copyWith(asset: assetRef);
      _updateScene(_selectedScene!.copyWith(background: newBg));
    }
  }

  Future<void> _previewStory() async {
    if (_content == null) return;

    // Save before preview
    if (_hasChanges) {
      await _saveContent();
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryViewerPage(
          story: widget.story,
          storage: widget.storage,
          i18n: widget.i18n,
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveContent();
      return true;
    } else if (result == 'discard') {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.i18n.get('story_studio', 'stories')),
          actions: [
            // Toggle scene properties
            IconButton(
              icon: Icon(_showSceneProperties ? Icons.layers : Icons.layers_outlined),
              onPressed: () {
                setState(() {
                  _showSceneProperties = !_showSceneProperties;
                  if (_showSceneProperties) {
                    _selectedElementId = null;
                  }
                });
              },
              tooltip: widget.i18n.get('scene', 'stories'),
            ),
            // Preview
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _previewStory,
              tooltip: widget.i18n.get('preview', 'stories'),
            ),
            // Save
            IconButton(
              icon: Icon(_hasChanges ? Icons.save : Icons.save_outlined),
              onPressed: _hasChanges ? _saveContent : null,
              tooltip: 'Save',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _content == null
                ? const Center(child: Text('Failed to load story'))
                : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    final isWideScreen = MediaQuery.of(context).size.width > 900;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // Scene list sidebar
              SizedBox(
                width: 180,
                child: _buildSceneList(),
              ),

              const VerticalDivider(width: 1),

              // Main editor area
              Expanded(
                child: _selectedScene != null
                    ? _buildSceneEditor(_selectedScene!)
                    : const Center(child: Text('Select a scene')),
              ),

              // Properties panel (desktop only)
              if (isWideScreen && (_selectedElementId != null || _showSceneProperties)) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 280,
                  child: _buildPropertiesPanel(),
                ),
              ],
            ],
          ),
        ),

        // Bottom toolbar
        _buildToolbar(),
      ],
    );
  }

  Widget _buildSceneList() {
    final scenes = _content?.orderedScenes ?? [];

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                widget.i18n.get('scenes', 'stories'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: _addScene,
                tooltip: widget.i18n.get('scene_add', 'stories'),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Scene list
        Expanded(
          child: ReorderableListView.builder(
            itemCount: scenes.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final newOrder = List<String>.from(_content!.sceneIds);
              final item = newOrder.removeAt(oldIndex);
              newOrder.insert(newIndex, item);
              setState(() {
                _content = _content!.reorderScenes(newOrder);
                _hasChanges = true;
              });
            },
            itemBuilder: (context, index) {
              final scene = scenes[index];
              final isSelected = scene.id == _selectedScene?.id;

              return ListTile(
                key: ValueKey(scene.id),
                selected: isSelected,
                leading: Container(
                  width: 36,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _parseColor(scene.background.placeholder),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: scene.background.hasImage
                      ? const Icon(Icons.image, size: 16, color: Colors.white70)
                      : Icon(Icons.warning, size: 16, color: Colors.orange.shade300),
                ),
                title: Text(
                  scene.title ?? '${widget.i18n.get('scene', 'stories')} ${index + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: scenes.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete, size: 16),
                        onPressed: () => _deleteScene(scene),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () {
                  setState(() {
                    _selectedScene = scene;
                    _selectedElementId = null;
                    _showSceneProperties = false;
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSceneEditor(StoryScene scene) {
    return Container(
      color: Colors.grey.shade800,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SceneEditorCanvas(
            scene: scene,
            story: widget.story,
            storage: widget.storage,
            selectedElementId: _selectedElementId,
            onSelectionChanged: (elementId) {
              setState(() {
                _selectedElementId = elementId;
                _showSceneProperties = false;
              });
            },
            onElementChanged: _updateElement,
            onDeleteSelected: _deleteSelectedElement,
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesPanel() {
    if (_showSceneProperties && _selectedScene != null) {
      return ScenePropertiesPanel(
        scene: _selectedScene!,
        allScenes: _content?.orderedScenes ?? [],
        i18n: widget.i18n,
        onSceneChanged: _updateScene,
        onSelectBackgroundImage: _selectBackgroundImage,
      );
    }

    if (_selectedElementId != null && _selectedScene != null) {
      final element = _selectedScene!.elements
          .cast<StoryElement?>()
          .firstWhere((e) => e?.id == _selectedElementId, orElse: () => null);

      if (element != null) {
        return ElementPropertiesPanel(
          element: element,
          scene: _selectedScene!,
          allScenes: _content?.orderedScenes ?? [],
          i18n: widget.i18n,
          onElementChanged: _updateElement,
          onTriggerChanged: _updateTrigger,
        );
      }
    }

    return const Center(child: Text('Select an element'));
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Add element buttons
          _ToolbarButton(
            icon: Icons.title,
            label: widget.i18n.get('element_title', 'stories'),
            onPressed: () => _addElement(ElementType.title),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.text_fields,
            label: widget.i18n.get('element_text', 'stories'),
            onPressed: () => _addElement(ElementType.text),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.smart_button,
            label: widget.i18n.get('element_button', 'stories'),
            onPressed: () => _addElement(ElementType.button),
          ),

          const Spacer(),

          // Delete button
          if (_selectedElementId != null)
            _ToolbarButton(
              icon: Icons.delete,
              label: widget.i18n.get('element_delete', 'stories'),
              onPressed: _deleteSelectedElement,
              isDestructive: true,
            ),
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      final hex = colorString.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    return Colors.black;
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive ? theme.colorScheme.error : theme.colorScheme.primary;

    return TextButton.icon(
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      onPressed: onPressed,
    );
  }
}
