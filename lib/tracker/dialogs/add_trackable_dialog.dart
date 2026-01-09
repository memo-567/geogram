import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trackable_type.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';
import '../../services/config_service.dart';
import '../../widgets/transcribe_button_widget.dart';

/// Unified dialog for adding exercise or measurement entries.
/// Replaces both AddExerciseDialog and AddMeasurementDialog.
class AddTrackableDialog extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final TrackableKind kind;
  final String? preselectedTypeId;
  final int year;

  const AddTrackableDialog({
    super.key,
    required this.service,
    required this.i18n,
    required this.kind,
    this.preselectedTypeId,
    required this.year,
  });

  /// Show dialog for adding an exercise entry
  static Future<bool?> showExercise(
    BuildContext context, {
    required TrackerService service,
    required I18nService i18n,
    String? preselectedTypeId,
    required int year,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddTrackableDialog(
        service: service,
        i18n: i18n,
        kind: TrackableKind.exercise,
        preselectedTypeId: preselectedTypeId,
        year: year,
      ),
    );
  }

  /// Show dialog for adding a measurement entry
  static Future<bool?> showMeasurement(
    BuildContext context, {
    required TrackerService service,
    required I18nService i18n,
    String? preselectedTypeId,
    required int year,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddTrackableDialog(
        service: service,
        i18n: i18n,
        kind: TrackableKind.measurement,
        preselectedTypeId: preselectedTypeId,
        year: year,
      ),
    );
  }

  @override
  State<AddTrackableDialog> createState() => _AddTrackableDialogState();
}

class _AddTrackableDialogState extends State<AddTrackableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  final _configService = ConfigService();

  // Blood pressure specific controllers
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heartRateController = TextEditingController();

  late String _selectedTypeId;
  int _selectedIntValue = 10;
  bool _saving = false;

  Map<String, TrackableTypeConfig> get _availableTypes =>
      widget.kind == TrackableKind.exercise
          ? TrackableTypeConfig.exerciseTypes
          : TrackableTypeConfig.measurementTypes;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.preselectedTypeId ?? _availableTypes.keys.first;
    _loadLastValue();
  }

  void _loadLastValue() {
    final config = _selectedConfig;
    if (config == null) return;

    if (config.isInteger) {
      final lastValue = _configService.getNestedValue(
        'tracker.lastValue.$_selectedTypeId',
      );
      final maxCount = config.maxCount ?? 100;
      if (lastValue is int && lastValue >= 1 && lastValue <= maxCount) {
        _selectedIntValue = lastValue;
      } else {
        _selectedIntValue = 10;
      }
    }
  }

  void _saveLastValue() {
    final config = _selectedConfig;
    if (config == null) return;

    if (config.isInteger) {
      _configService.setNestedValue(
        'tracker.lastValue.$_selectedTypeId',
        _selectedIntValue,
      );
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _heartRateController.dispose();
    super.dispose();
  }

  TrackableTypeConfig? get _selectedConfig =>
      TrackableTypeConfig.builtInTypes[_selectedTypeId];

  bool get _isBloodPressure => _selectedTypeId == 'blood_pressure';
  bool get _isCardio => _selectedConfig?.isCardio ?? false;
  bool get _isExercise => widget.kind == TrackableKind.exercise;

  String get _dialogTitle => _isExercise
      ? widget.i18n.t('tracker_add_exercise')
      : widget.i18n.t('tracker_add_measurement');

  String get _typeLabel => _isExercise
      ? widget.i18n.t('tracker_exercise_type')
      : widget.i18n.t('tracker_measurement_type');

  String _getTypeName(String typeId) {
    if (typeId == 'blood_pressure') {
      return widget.i18n.t('tracker_blood_pressure');
    }
    final prefix = _isExercise ? 'tracker_exercise_' : 'tracker_measurement_';
    return widget.i18n.t('$prefix$typeId');
  }

  @override
  Widget build(BuildContext context) {
    final config = _selectedConfig;

    return AlertDialog(
      title: Text(_dialogTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type dropdown (only show if not preselected)
              if (widget.preselectedTypeId == null) ...[
                DropdownButtonFormField<String>(
                  value: _selectedTypeId,
                  decoration: InputDecoration(
                    labelText: _typeLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    // Add blood pressure option for measurements
                    if (!_isExercise)
                      DropdownMenuItem(
                        value: 'blood_pressure',
                        child: Text(widget.i18n.t('tracker_blood_pressure')),
                      ),
                    ..._availableTypes.entries.map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(_getTypeName(e.key)),
                        )),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedTypeId = value;
                        _loadLastValue();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Value input - varies by type
              if (_isBloodPressure)
                _buildBloodPressureFields()
              else if (config != null && config.isInteger)
                _buildIntegerDropdown(config)
              else if (config != null)
                _buildDecimalField(config),

              const SizedBox(height: 16),

              // Duration field (for cardio exercises)
              if (_isCardio) ...[
                TextFormField(
                  controller: _durationController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_duration_minutes'),
                    suffixText: 'min',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
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

  Widget _buildIntegerDropdown(TrackableTypeConfig config) {
    final maxCount = config.maxCount ?? 100;
    final valueLabel = _isCardio
        ? widget.i18n.t('tracker_distance_meters')
        : widget.i18n.t('tracker_count');

    return DropdownButtonFormField<int>(
      value: _selectedIntValue.clamp(1, maxCount),
      decoration: InputDecoration(
        labelText: valueLabel,
        suffixText: config.unit,
        border: const OutlineInputBorder(),
      ),
      items: List.generate(maxCount, (i) => i + 1)
          .map((n) => DropdownMenuItem(
                value: n,
                child: Text('$n'),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedIntValue = value);
        }
      },
    );
  }

  Widget _buildDecimalField(TrackableTypeConfig config) {
    return TextFormField(
      controller: _valueController,
      decoration: InputDecoration(
        labelText: widget.i18n.t('tracker_value'),
        suffixText: config.unit,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      validator: (value) {
        if (value == null || value.isEmpty) {
          return widget.i18n.t('tracker_required_field');
        }
        final num = double.tryParse(value);
        if (num == null) {
          return widget.i18n.t('tracker_invalid_number');
        }
        if (config.minValue != null && num < config.minValue!) {
          return '${widget.i18n.t('tracker_min')}: ${config.minValue}';
        }
        if (config.maxValue != null && num > config.maxValue!) {
          return '${widget.i18n.t('tracker_max')}: ${config.maxValue}';
        }
        return null;
      },
    );
  }

  Widget _buildBloodPressureFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _systolicController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_systolic'),
                  suffixText: 'mmHg',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return widget.i18n.t('tracker_required');
                  }
                  final num = int.tryParse(value);
                  if (num == null || num < 50 || num > 300) {
                    return widget.i18n.t('tracker_invalid');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            const Text('/'),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _diastolicController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_diastolic'),
                  suffixText: 'mmHg',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return widget.i18n.t('tracker_required');
                  }
                  final num = int.tryParse(value);
                  if (num == null || num < 30 || num > 200) {
                    return widget.i18n.t('tracker_invalid');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _heartRateController,
          decoration: InputDecoration(
            labelText: widget.i18n.t('tracker_heart_rate_optional'),
            suffixText: 'bpm',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      if (_isBloodPressure) {
        await _saveBloodPressure();
      } else if (_isExercise) {
        await _saveExercise();
      } else {
        await _saveMeasurement();
      }

      _saveLastValue();

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

  Future<void> _saveExercise() async {
    final duration = _durationController.text.isNotEmpty
        ? int.parse(_durationController.text) * 60
        : null;

    await widget.service.addExerciseEntry(
      exerciseId: _selectedTypeId,
      count: _selectedIntValue,
      durationSeconds: duration,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      year: widget.year,
    );
  }

  Future<void> _saveMeasurement() async {
    final value = double.parse(_valueController.text);

    await widget.service.addMeasurementEntry(
      typeId: _selectedTypeId,
      value: value,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      year: widget.year,
    );
  }

  Future<void> _saveBloodPressure() async {
    final systolic = int.parse(_systolicController.text);
    final diastolic = int.parse(_diastolicController.text);
    final heartRate = _heartRateController.text.isNotEmpty
        ? int.parse(_heartRateController.text)
        : null;

    await widget.service.addBloodPressureEntry(
      systolic: systolic,
      diastolic: diastolic,
      heartRate: heartRate,
      notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      year: widget.year,
    );
  }
}
