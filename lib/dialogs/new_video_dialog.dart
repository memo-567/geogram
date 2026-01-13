/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/video.dart';
import '../services/i18n_service.dart';
import '../pages/location_picker_page.dart';
import '../util/video_metadata_extractor.dart';

/// Full-screen dialog for creating or editing a video
class NewVideoDialog extends StatefulWidget {
  final List<String> existingTags;
  final Video? video;

  const NewVideoDialog({
    Key? key,
    this.existingTags = const [],
    this.video,
  }) : super(key: key);

  bool get isEditing => video != null;

  @override
  State<NewVideoDialog> createState() => _NewVideoDialogState();
}

class _NewVideoDialogState extends State<NewVideoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _i18n = I18nService();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  final _tagsFocusNode = FocusNode();

  List<String> _filteredTags = [];
  bool _showTagSuggestions = false;

  String? _videoFilePath;
  VideoMetadata? _videoMetadata;
  bool _isLoadingMetadata = false;
  LatLng? _location;
  VideoCategory _category = VideoCategory.other;
  VideoVisibility _visibility = VideoVisibility.public;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video?.getTitle() ?? '');
    _descriptionController = TextEditingController(text: widget.video?.getDescription() ?? '');
    _tagsController = TextEditingController(text: widget.video?.tags.join(', ') ?? '');
    _tagsController.addListener(_onTagsChanged);
    _tagsFocusNode.addListener(_onTagsFocusChanged);

    if (widget.video != null) {
      _videoFilePath = widget.video!.videoFilePath;
      _category = widget.video!.category;
      _visibility = widget.video!.visibility;
      if (widget.video!.hasLocation) {
        _location = LatLng(widget.video!.latitude!, widget.video!.longitude!);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.removeListener(_onTagsChanged);
    _tagsController.dispose();
    _tagsFocusNode.removeListener(_onTagsFocusChanged);
    _tagsFocusNode.dispose();
    super.dispose();
  }

  void _onTagsFocusChanged() {
    if (_tagsFocusNode.hasFocus) {
      _updateTagSuggestions();
    } else {
      setState(() {
        _showTagSuggestions = false;
      });
    }
  }

  void _onTagsChanged() {
    _updateTagSuggestions();
  }

  void _updateTagSuggestions() {
    final text = _tagsController.text;
    final currentTags = text.split(',').map((t) => t.trim().toLowerCase()).toSet();

    final lastCommaIndex = text.lastIndexOf(',');
    final currentInput = lastCommaIndex >= 0
        ? text.substring(lastCommaIndex + 1).trim().toLowerCase()
        : text.trim().toLowerCase();

    final suggestions = widget.existingTags.where((tag) {
      final tagLower = tag.toLowerCase();
      final isAlreadyAdded = currentTags.contains(tagLower);
      final matchesInput = currentInput.isEmpty || tagLower.contains(currentInput);
      return !isAlreadyAdded && matchesInput;
    }).toList();

    setState(() {
      _filteredTags = suggestions;
      _showTagSuggestions = _tagsFocusNode.hasFocus && suggestions.isNotEmpty;
    });
  }

  void _addTag(String tag) {
    final text = _tagsController.text;
    final lastCommaIndex = text.lastIndexOf(',');

    String newText;
    if (lastCommaIndex >= 0) {
      newText = '${text.substring(0, lastCommaIndex + 1)} $tag, ';
    } else {
      newText = '$tag, ';
    }

    _tagsController.text = newText;
    _tagsController.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );
    _updateTagSuggestions();
  }

  List<String> _parseTags() {
    if (_tagsController.text.trim().isEmpty) return [];
    return _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        setState(() {
          _videoFilePath = path;
          _isLoadingMetadata = true;
        });

        // Extract metadata
        final metadata = await VideoMetadataExtractor.extract(path);
        setState(() {
          _videoMetadata = metadata;
          _isLoadingMetadata = false;
        });

        // Auto-populate title from filename if empty
        if (_titleController.text.isEmpty) {
          final filename = path.split('/').last;
          final nameWithoutExt = filename.contains('.')
              ? filename.substring(0, filename.lastIndexOf('.'))
              : filename;
          _titleController.text = nameWithoutExt.replaceAll(RegExp(r'[_-]'), ' ');
        }
      }
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialPosition: _location,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _location = result;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _location = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_videoFilePath == null && !widget.isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_i18n.t('select_video_file')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      'tags': _parseTags(),
      'videoFilePath': _videoFilePath,
      'category': _category,
      'visibility': _visibility,
      'latitude': _location?.latitude,
      'longitude': _location?.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? _i18n.t('edit_video') : _i18n.t('new_video')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(
              widget.isEditing ? _i18n.t('save') : _i18n.t('create'),
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Video file picker (only for new videos)
            if (!widget.isEditing) ...[
              _buildVideoFilePicker(theme),
              const SizedBox(height: 16),
            ],

            // Video metadata preview
            if (_videoMetadata != null || _isLoadingMetadata) ...[
              _buildMetadataPreview(theme),
              const SizedBox(height: 16),
            ],

            // Title field
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _i18n.t('title'),
                hintText: _i18n.t('enter_video_title'),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _i18n.t('title_required');
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // Description field
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: _i18n.t('description'),
                hintText: _i18n.t('enter_video_description'),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 16),

            // Category dropdown
            _buildCategoryDropdown(theme),
            const SizedBox(height: 16),

            // Visibility dropdown
            _buildVisibilityDropdown(theme),
            const SizedBox(height: 16),

            // Tags field
            _buildTagsField(theme),
            const SizedBox(height: 16),

            // Location picker
            _buildLocationPicker(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFilePicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _i18n.t('video_file'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickVideoFile,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                color: _videoFilePath != null
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: _videoFilePath != null ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _videoFilePath != null ? Icons.videocam : Icons.video_file,
                  size: 48,
                  color: _videoFilePath != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _videoFilePath != null
                            ? _videoFilePath!.split('/').last
                            : _i18n.t('tap_to_select_video'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: _videoFilePath != null ? FontWeight.bold : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_videoFilePath != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _i18n.t('tap_to_change'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataPreview(ThemeData theme) {
    if (_isLoadingMetadata) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(_i18n.t('extracting_metadata')),
          ],
        ),
      );
    }

    if (_videoMetadata == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _i18n.t('video_info'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildMetadataChip(theme, Icons.timelapse, _formatDuration(_videoMetadata!.duration)),
              _buildMetadataChip(theme, Icons.aspect_ratio, _videoMetadata!.resolution),
              _buildMetadataChip(theme, Icons.storage, _formatFileSize(_videoMetadata!.fileSize)),
              if (_videoMetadata!.videoCodec != null)
                _buildMetadataChip(theme, Icons.video_settings, _videoMetadata!.videoCodec!.toUpperCase()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataChip(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCategoryDropdown(ThemeData theme) {
    return DropdownButtonFormField<VideoCategory>(
      value: _category,
      decoration: InputDecoration(
        labelText: _i18n.t('category'),
        border: const OutlineInputBorder(),
      ),
      items: VideoCategory.values.map((cat) {
        return DropdownMenuItem(
          value: cat,
          child: Text(cat.displayName),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _category = value;
          });
        }
      },
    );
  }

  Widget _buildVisibilityDropdown(ThemeData theme) {
    return DropdownButtonFormField<VideoVisibility>(
      value: _visibility,
      decoration: InputDecoration(
        labelText: _i18n.t('visibility'),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: VideoVisibility.public,
          child: Row(
            children: [
              const Icon(Icons.public, size: 18),
              const SizedBox(width: 8),
              Text(_i18n.t('public')),
            ],
          ),
        ),
        DropdownMenuItem(
          value: VideoVisibility.unlisted,
          child: Row(
            children: [
              const Icon(Icons.link_off, size: 18),
              const SizedBox(width: 8),
              Text(_i18n.t('unlisted')),
            ],
          ),
        ),
        DropdownMenuItem(
          value: VideoVisibility.private,
          child: Row(
            children: [
              const Icon(Icons.lock, size: 18),
              const SizedBox(width: 8),
              Text(_i18n.t('private')),
            ],
          ),
        ),
        DropdownMenuItem(
          value: VideoVisibility.restricted,
          child: Row(
            children: [
              const Icon(Icons.group, size: 18),
              const SizedBox(width: 8),
              Text(_i18n.t('restricted')),
            ],
          ),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _visibility = value;
          });
        }
      },
    );
  }

  Widget _buildTagsField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _tagsController,
          focusNode: _tagsFocusNode,
          decoration: InputDecoration(
            labelText: _i18n.t('tags'),
            hintText: _i18n.t('enter_tags_comma_separated'),
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        if (_showTagSuggestions && _filteredTags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _filteredTags.take(10).map((tag) {
              return ActionChip(
                label: Text('#$tag'),
                onPressed: () => _addTag(tag),
                backgroundColor: theme.colorScheme.surfaceVariant,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _i18n.t('location'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_location != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _pickLocation,
                  tooltip: _i18n.t('change_location'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearLocation,
                  tooltip: _i18n.t('remove_location'),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.add_location),
            label: Text(_i18n.t('add_location')),
          ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
