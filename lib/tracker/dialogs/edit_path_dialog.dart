import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../../services/i18n_service.dart';
import '../../widgets/transcribe_button_widget.dart';

class EditPathResult {
  final String title;
  final String? description;
  final List<String> tags;

  const EditPathResult({
    required this.title,
    this.description,
    this.tags = const [],
  });
}

/// Dialog for editing a path title/description/tags.
class EditPathDialog extends StatefulWidget {
  final TrackerPath path;
  final I18nService i18n;

  const EditPathDialog({
    super.key,
    required this.path,
    required this.i18n,
  });

  static Future<EditPathResult?> show(
    BuildContext context, {
    required TrackerPath path,
    required I18nService i18n,
  }) {
    return showDialog<EditPathResult>(
      context: context,
      builder: (context) => EditPathDialog(
        path: path,
        i18n: i18n,
      ),
    );
  }

  @override
  State<EditPathDialog> createState() => _EditPathDialogState();
}

class _EditPathDialogState extends State<EditPathDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagController;
  late List<String> _currentTags;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.path.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.path.description ?? '');
    _tagController = TextEditingController();
    _currentTags = List<String>.from(widget.path.userTags);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final normalized = tag.toLowerCase().trim().replaceAll('#', '');
    if (normalized.isEmpty) return;
    if (_currentTags.contains(normalized)) return;

    setState(() {
      _currentTags.add(normalized);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _currentTags.remove(tag);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.t('tracker_edit_path')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_path_title'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return widget.i18n.t('tracker_required_field');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_path_description'),
                  border: const OutlineInputBorder(),
                  suffixIcon: TranscribeButtonWidget(
                    i18n: widget.i18n,
                    onTranscribed: (text) {
                      final current = _descriptionController.text;
                      final needsSpace =
                          current.isNotEmpty && !current.endsWith(' ');
                      final appended = '$current${needsSpace ? ' ' : ''}$text';
                      _descriptionController
                        ..text = appended
                        ..selection = TextSelection.collapsed(
                          offset: appended.length,
                        );
                    },
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tagController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_tags'),
                  hintText: widget.i18n.t('tracker_add_tag'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addTag(_tagController.text),
                  ),
                ),
                onSubmitted: _addTag,
              ),
              if (_currentTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _currentTags.map((tag) {
                    return Chip(
                      label: Text('#$tag'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () => _removeTag(tag),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(widget.i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.i18n.t('save')),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      EditPathResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _currentTags,
      ),
    );
  }
}
