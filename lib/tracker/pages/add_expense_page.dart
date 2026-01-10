import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/tracker_models.dart';
import '../../services/config_service.dart';
import '../../services/i18n_service.dart';
import '../../widgets/transcribe_button_widget.dart';

/// Full-screen page for adding or editing an expense
class AddExpensePage extends StatefulWidget {
  final I18nService i18n;
  final TrackerPath path;
  final TrackerPathPoints? points;
  final TrackerExpense? existing;

  const AddExpensePage({
    super.key,
    required this.i18n,
    required this.path,
    this.points,
    this.existing,
  });

  static Future<TrackerExpense?> show(
    BuildContext context, {
    required I18nService i18n,
    required TrackerPath path,
    TrackerPathPoints? points,
    TrackerExpense? existing,
  }) {
    return Navigator.push<TrackerExpense>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpensePage(
          i18n: i18n,
          path: path,
          points: points,
          existing: existing,
        ),
      ),
    );
  }

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _litersController = TextEditingController();
  final _noteController = TextEditingController();
  final _configService = ConfigService();

  late ExpenseType _type;
  late String _currency;
  late FuelType _fuelType;
  late DateTime _timestamp;
  double? _lat;
  double? _lon;
  bool _saving = false;
  String? _locationWarning;

  @override
  void initState() {
    super.initState();

    if (widget.existing != null) {
      // Editing existing expense
      _type = widget.existing!.type;
      _currency = widget.existing!.currency;
      _fuelType = widget.existing!.fuelType ?? FuelType.diesel;
      _timestamp = widget.existing!.timestampDateTime;
      _lat = widget.existing!.lat;
      _lon = widget.existing!.lon;
      _amountController.text = widget.existing!.amount.toString();
      if (widget.existing!.liters != null) {
        _litersController.text = widget.existing!.liters.toString();
      }
      if (widget.existing!.note != null) {
        _noteController.text = widget.existing!.note!;
      }
    } else {
      // New expense - load defaults
      _type = ExpenseType.fuel;
      _currency = _configService.getNestedValue(
        'tracker.expenses.defaultCurrency',
        'EUR',
      ) as String;
      final fuelTypeStr = _configService.getNestedValue(
        'tracker.expenses.defaultFuelType',
        'diesel',
      ) as String;
      _fuelType = FuelType.values.firstWhere(
        (f) => f.name == fuelTypeStr,
        orElse: () => FuelType.diesel,
      );
      // Default to now, but clamp to path time range
      final now = DateTime.now();
      final pathEnd = widget.path.endedAtDateTime ?? now;
      _timestamp = now.isAfter(pathEnd) ? pathEnd : now;
      _inferLocationFromTimestamp();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _litersController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _inferLocationFromTimestamp() {
    if (widget.points == null || widget.points!.points.isEmpty) {
      _locationWarning = widget.i18n.t('tracker_expense_no_points');
      return;
    }

    final points = widget.points!.points;
    final firstTime = points.first.timestampDateTime;
    final lastTime = points.last.timestampDateTime;

    // Check if timestamp is within path time range (with 30 min buffer)
    final buffer = const Duration(minutes: 30);
    if (_timestamp.isBefore(firstTime.subtract(buffer)) ||
        _timestamp.isAfter(lastTime.add(buffer))) {
      _locationWarning = widget.i18n.t('tracker_expense_time_outside_path');
      _lat = null;
      _lon = null;
      return;
    }

    // Find nearest point by time
    TrackerPoint? nearest;
    Duration? minDiff;
    for (final point in points) {
      final diff = (point.timestampDateTime.difference(_timestamp)).abs();
      if (minDiff == null || diff < minDiff) {
        minDiff = diff;
        nearest = point;
      }
    }

    if (nearest != null) {
      _lat = nearest.lat;
      _lon = nearest.lon;
      _locationWarning = null;
    }
  }

  void _onTimestampChanged(DateTime newTimestamp) {
    setState(() {
      _timestamp = newTimestamp;
      _inferLocationFromTimestamp();
    });
  }

  Future<void> _pickDate() async {
    final firstDate = widget.path.startedAtDateTime.subtract(const Duration(days: 1));
    final lastDate = widget.path.endedAtDateTime ?? DateTime.now();
    // Ensure initialDate is within the valid range
    var initialDate = _timestamp;
    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    } else if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date != null && mounted) {
      _onTimestampChanged(DateTime(
        date.year,
        date.month,
        date.day,
        _timestamp.hour,
        _timestamp.minute,
      ));
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (time != null && mounted) {
      _onTimestampChanged(DateTime(
        _timestamp.year,
        _timestamp.month,
        _timestamp.day,
        time.hour,
        time.minute,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing
            ? widget.i18n.t('tracker_edit_expense')
            : widget.i18n.t('tracker_add_expense')),
        actions: [
          TextButton(
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Expense type dropdown
              DropdownButtonFormField<ExpenseType>(
                value: _type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_expense_type'),
                  border: const OutlineInputBorder(),
                ),
                items: ExpenseType.values
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Icon(_getExpenseIcon(type), size: 20),
                              const SizedBox(width: 8),
                              Text(widget.i18n.t('tracker_expense_${type.name}')),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _type = value);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Amount + Currency row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: widget.i18n.t('tracker_expense_amount'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return widget.i18n.t('tracker_required_field');
                        }
                        if (double.tryParse(value) == null) {
                          return widget.i18n.t('tracker_invalid_number');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: supportedCurrencies.entries
                          .map((entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.key),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _currency = value);
                          // Remember the choice
                          _configService.setNestedValue(
                            'tracker.expenses.defaultCurrency',
                            value,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Fuel-specific fields
              if (_type == ExpenseType.fuel) ...[
                DropdownButtonFormField<FuelType>(
                  value: _fuelType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_fuel_type'),
                    border: const OutlineInputBorder(),
                  ),
                  items: FuelType.values
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(widget.i18n.t('tracker_fuel_${type.name}')),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _fuelType = value);
                      // Remember the choice
                      _configService.setNestedValue(
                        'tracker.expenses.defaultFuelType',
                        value.name,
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _litersController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_fuel_liters'),
                    border: const OutlineInputBorder(),
                    suffixText: 'L',
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (double.tryParse(value) == null) {
                        return widget.i18n.t('tracker_invalid_number');
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],

              // Date and Time pickers in a row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        await _pickDate();
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: widget.i18n.t('tracker_expense_date'),
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(DateFormat.yMMMd().format(_timestamp)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        await _pickTime();
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: widget.i18n.t('tracker_expense_time'),
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.access_time),
                        ),
                        child: Text(DateFormat.Hm().format(_timestamp)),
                      ),
                    ),
                  ),
                ],
              ),

              // Location warning or info
              if (_locationWarning != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationWarning!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                            ),
                      ),
                    ),
                  ],
                ),
              ] else if (_lat != null && _lon != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.i18n.t('tracker_expense_location_inferred'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Note field with transcription button
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_expense_note'),
                  border: const OutlineInputBorder(),
                  suffixIcon: TranscribeButtonWidget(
                    i18n: widget.i18n,
                    onTranscribed: (text) {
                      final current = _noteController.text;
                      final needsSpace = current.isNotEmpty && !current.endsWith(' ');
                      final appended = '$current${needsSpace ? ' ' : ''}$text';
                      _noteController
                        ..text = appended
                        ..selection = TextSelection.collapsed(offset: appended.length);
                    },
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getExpenseIcon(ExpenseType type) {
    return switch (type) {
      ExpenseType.fuel => Icons.local_gas_station,
      ExpenseType.toll => Icons.toll,
      ExpenseType.food => Icons.restaurant,
      ExpenseType.drink => Icons.local_cafe,
      ExpenseType.sleep => Icons.hotel,
      ExpenseType.ticket => Icons.confirmation_number,
      ExpenseType.fine => Icons.gavel,
    };
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final expense = TrackerExpense(
      id: widget.existing?.id ?? _generateExpenseId(),
      type: _type,
      amount: double.parse(_amountController.text),
      currency: _currency,
      timestamp: _timestamp.toIso8601String(),
      lat: _lat,
      lon: _lon,
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null,
      fuelType: _type == ExpenseType.fuel ? _fuelType : null,
      liters: _type == ExpenseType.fuel && _litersController.text.isNotEmpty
          ? double.tryParse(_litersController.text)
          : null,
    );

    Navigator.of(context).pop(expense);
  }

  String _generateExpenseId() {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final suffix = String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
    return 'exp_${dateStr}_$suffix';
  }
}
