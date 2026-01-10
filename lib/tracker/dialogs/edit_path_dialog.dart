import 'package:flutter/material.dart';

import '../models/tracker_models.dart';
import '../../services/i18n_service.dart';
import '../../widgets/transcribe_button_widget.dart';

class EditPathResult {
  final String title;
  final String? description;

  const EditPathResult({
    required this.title,
    this.description,
  });
}

/// Dialog for editing a path title/description.
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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.path.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.path.description ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
      ),
    );
  }
}
