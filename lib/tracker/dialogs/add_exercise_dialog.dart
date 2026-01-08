import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';

/// Dialog for adding a new exercise entry
class AddExerciseDialog extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final String? preselectedExerciseId;
  final int year;

  const AddExerciseDialog({
    super.key,
    required this.service,
    required this.i18n,
    this.preselectedExerciseId,
    required this.year,
  });

  static Future<bool?> show(
    BuildContext context, {
    required TrackerService service,
    required I18nService i18n,
    String? preselectedExerciseId,
    required int year,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddExerciseDialog(
        service: service,
        i18n: i18n,
        preselectedExerciseId: preselectedExerciseId,
        year: year,
      ),
    );
  }

  @override
  State<AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<AddExerciseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();

  late String _selectedExerciseId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedExerciseId = widget.preselectedExerciseId ??
        ExerciseTypeConfig.builtInTypes.keys.first;
  }

  @override
  void dispose() {
    _countController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  ExerciseTypeConfig get _selectedConfig =>
      ExerciseTypeConfig.builtInTypes[_selectedExerciseId]!;

  bool get _isCardio => _selectedConfig.category == ExerciseCategory.cardio;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.t('tracker_add_exercise')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Exercise type dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedExerciseId,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_exercise_type'),
                  border: const OutlineInputBorder(),
                ),
                items: ExerciseTypeConfig.builtInTypes.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(widget.i18n.t('tracker_exercise_${e.key}')),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedExerciseId = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Count field
              TextFormField(
                controller: _countController,
                decoration: InputDecoration(
                  labelText: _isCardio
                      ? widget.i18n.t('tracker_distance_meters')
                      : widget.i18n.t('tracker_count'),
                  suffixText: _selectedConfig.unit,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return widget.i18n.t('tracker_required_field');
                  }
                  final count = int.tryParse(value);
                  if (count == null || count <= 0) {
                    return widget.i18n.t('tracker_invalid_number');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Duration field (for cardio)
              if (_isCardio) ...[
                TextFormField(
                  controller: _durationController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_duration_minutes'),
                    suffixText: 'min',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),
              ],

              // Notes field
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_notes'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.i18n.t('save')),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final count = int.parse(_countController.text);
      final duration = _durationController.text.isNotEmpty
          ? int.parse(_durationController.text) * 60 // Convert to seconds
          : null;

      await widget.service.addExerciseEntry(
        exerciseId: _selectedExerciseId,
        count: count,
        durationSeconds: duration,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        year: widget.year,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }
}
