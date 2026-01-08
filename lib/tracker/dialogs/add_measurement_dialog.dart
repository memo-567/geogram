import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tracker_models.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';

/// Dialog for adding a new measurement entry
class AddMeasurementDialog extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final String? preselectedTypeId;
  final int year;

  const AddMeasurementDialog({
    super.key,
    required this.service,
    required this.i18n,
    this.preselectedTypeId,
    required this.year,
  });

  static Future<bool?> show(
    BuildContext context, {
    required TrackerService service,
    required I18nService i18n,
    String? preselectedTypeId,
    required int year,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddMeasurementDialog(
        service: service,
        i18n: i18n,
        preselectedTypeId: preselectedTypeId,
        year: year,
      ),
    );
  }

  @override
  State<AddMeasurementDialog> createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<AddMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();

  // Blood pressure specific controllers
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heartRateController = TextEditingController();

  late String _selectedTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.preselectedTypeId ??
        MeasurementTypeConfig.builtInTypes.keys.first;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _heartRateController.dispose();
    super.dispose();
  }

  MeasurementTypeConfig? get _selectedConfig =>
      MeasurementTypeConfig.builtInTypes[_selectedTypeId];

  bool get _isBloodPressure => _selectedTypeId == 'blood_pressure';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.t('tracker_add_measurement')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Measurement type dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedTypeId,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_measurement_type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'blood_pressure',
                    child: Text(widget.i18n.t('tracker_blood_pressure')),
                  ),
                  ...MeasurementTypeConfig.builtInTypes.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(widget.i18n.t('tracker_measurement_${e.key}')),
                          )),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedTypeId = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Blood pressure fields
              if (_isBloodPressure) ...[
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
              ] else ...[
                // Regular measurement value
                TextFormField(
                  controller: _valueController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_value'),
                    suffixText: _selectedConfig?.unit ?? '',
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
                    final config = _selectedConfig;
                    if (config != null) {
                      if (config.minValue != null && num < config.minValue!) {
                        return '${widget.i18n.t('tracker_min')}: ${config.minValue}';
                      }
                      if (config.maxValue != null && num > config.maxValue!) {
                        return '${widget.i18n.t('tracker_max')}: ${config.maxValue}';
                      }
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),

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
      if (_isBloodPressure) {
        await _saveBloodPressure();
      } else {
        await _saveMeasurement();
      }

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
