import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';
import '../../services/config_service.dart';
import '../../widgets/transcribe_button_widget.dart';

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
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  final _configService = ConfigService();

  late String _selectedExerciseId;
  int _selectedCount = 10;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedExerciseId = widget.preselectedExerciseId ??
        ExerciseTypeConfig.builtInTypes.keys.first;
    _loadLastCount();
  }

  void _loadLastCount() {
    final lastCount = _configService.getNestedValue(
      'tracker.exerciseLastCount.$_selectedExerciseId',
    );
    if (lastCount is int && lastCount >= 1 && lastCount <= 100) {
      _selectedCount = lastCount;
    } else {
      _selectedCount = 10; // Default
    }
  }

  void _saveLastCount() {
    _configService.setNestedValue(
      'tracker.exerciseLastCount.$_selectedExerciseId',
      _selectedCount,
    );
  }

  @override
  void dispose() {
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
              // Exercise type dropdown (only show if not preselected)
              if (widget.preselectedExerciseId == null) ...[
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
                      setState(() {
                        _selectedExerciseId = value;
                        _loadLastCount();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Count dropdown (1-100)
              DropdownButtonFormField<int>(
                value: _selectedCount,
                decoration: InputDecoration(
                  labelText: _isCardio
                      ? widget.i18n.t('tracker_distance_meters')
                      : widget.i18n.t('tracker_count'),
                  suffixText: _selectedConfig.unit,
                  border: const OutlineInputBorder(),
                ),
                items: List.generate(100, (i) => i + 1)
                    .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCount = value);
                  }
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
                  suffixIcon: TranscribeButtonWidget(
                    i18n: widget.i18n,
                    onTranscribed: (text) {
                      if (_notesController.text.isEmpty) {
                        _notesController.text = text;
                      } else {
                        _notesController.text += ' $text';
                      }
                    },
                  ),
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
      final duration = _durationController.text.isNotEmpty
          ? int.parse(_durationController.text) * 60 // Convert to seconds
          : null;

      await widget.service.addExerciseEntry(
        exerciseId: _selectedExerciseId,
        count: _selectedCount,
        durationSeconds: duration,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        year: widget.year,
      );

      // Remember the selected count for this exercise
      _saveLastCount();

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
