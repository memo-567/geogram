/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../models/form_content.dart';

/// Widget for rendering a form field based on its type
class FormFieldWidget extends StatefulWidget {
  final NdfFormField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool readOnly;
  final String? error;

  const FormFieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.error,
  });

  @override
  State<FormFieldWidget> createState() => _FormFieldWidgetState();
}

class _FormFieldWidgetState extends State<FormFieldWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(FormFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update controller text if the field changed (different field ID)
    // or if value changed externally (not from typing)
    if (oldWidget.field.id != widget.field.id) {
      _textController.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              Text(
                widget.field.label,
                style: theme.textTheme.titleSmall,
              ),
              if (widget.field.required)
                Text(
                  ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
          // Description
          if (widget.field.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.field.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Field input
          _buildField(context, theme),
          // Error
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, ThemeData theme) {
    switch (widget.field.type) {
      case FormFieldType.text:
        return _buildTextField(theme);
      case FormFieldType.textarea:
        return _buildTextArea(theme);
      case FormFieldType.number:
        return _buildNumberField(theme);
      case FormFieldType.select:
        return _buildSelect(theme);
      case FormFieldType.selectMultiple:
        return _buildMultiSelect(theme);
      case FormFieldType.radio:
        return _buildRadio(theme);
      case FormFieldType.checkbox:
        return _buildCheckbox(theme);
      case FormFieldType.checkboxGroup:
        return _buildCheckboxGroup(theme);
      case FormFieldType.date:
        return _buildDateField(context, theme);
      case FormFieldType.time:
        return _buildTimeField(context, theme);
      case FormFieldType.datetime:
        return _buildDateTimeField(context, theme);
      case FormFieldType.rating:
        return _buildRating(theme);
      case FormFieldType.scale:
        return _buildScale(theme);
      case FormFieldType.signature:
        return _buildSignature(theme);
      case FormFieldType.section:
        return _buildSection(theme);
      case FormFieldType.location:
        return _buildLocation(theme);
      case FormFieldType.file:
      case FormFieldType.image:
        return _buildFileField(theme);
      case FormFieldType.hidden:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextField(ThemeData theme) {
    return TextField(
      controller: _textController,
      readOnly: widget.readOnly,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }

  Widget _buildTextArea(ThemeData theme) {
    return TextField(
      controller: _textController,
      readOnly: widget.readOnly,
      textCapitalization: TextCapitalization.sentences,
      maxLines: widget.field.rows ?? 4,
      decoration: InputDecoration(
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: widget.onChanged,
    );
  }

  Widget _buildNumberField(ThemeData theme) {
    return TextField(
      controller: _textController,
      readOnly: widget.readOnly,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.field.step != null && widget.field.step! < 1,
      ),
      decoration: InputDecoration(
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) {
        final num? number = num.tryParse(text);
        widget.onChanged(number);
      },
    );
  }

  Widget _buildSelect(ThemeData theme) {
    return DropdownButtonFormField<String>(
      value: widget.value as String?,
      decoration: InputDecoration(
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
      ),
      items: widget.field.options?.map((opt) {
        return DropdownMenuItem(
          value: opt.value,
          child: Text(opt.label),
        );
      }).toList() ?? [],
      onChanged: widget.readOnly ? null : (val) => widget.onChanged(val),
    );
  }

  Widget _buildMultiSelect(ThemeData theme) {
    final selected = (widget.value as List<String>?) ?? [];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.field.options?.map((opt) {
        final isSelected = selected.contains(opt.value);
        return FilterChip(
          label: Text(opt.label),
          selected: isSelected,
          onSelected: widget.readOnly ? null : (sel) {
            final newList = List<String>.from(selected);
            if (sel) {
              newList.add(opt.value);
            } else {
              newList.remove(opt.value);
            }
            widget.onChanged(newList);
          },
        );
      }).toList() ?? [],
    );
  }

  Widget _buildRadio(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.field.options?.map((opt) {
        return RadioListTile<String>(
          value: opt.value,
          groupValue: widget.value as String?,
          title: Text(opt.label),
          contentPadding: EdgeInsets.zero,
          onChanged: widget.readOnly ? null : (val) => widget.onChanged(val),
        );
      }).toList() ?? [],
    );
  }

  Widget _buildCheckbox(ThemeData theme) {
    return CheckboxListTile(
      value: widget.value == true,
      title: Text(widget.field.label),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: widget.readOnly ? null : (val) => widget.onChanged(val),
    );
  }

  Widget _buildCheckboxGroup(ThemeData theme) {
    final selected = (widget.value as List<String>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.field.options?.map((opt) {
        return CheckboxListTile(
          value: selected.contains(opt.value),
          title: Text(opt.label),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: widget.readOnly ? null : (sel) {
            final newList = List<String>.from(selected);
            if (sel == true) {
              newList.add(opt.value);
            } else {
              newList.remove(opt.value);
            }
            widget.onChanged(newList);
          },
        );
      }).toList() ?? [],
    );
  }

  Widget _buildDateField(BuildContext context, ThemeData theme) {
    final dateStr = widget.value as String?;
    DateTime? date;
    if (dateStr != null) {
      date = DateTime.tryParse(dateStr);
    }

    return InkWell(
      onTap: widget.readOnly ? null : () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          widget.onChanged(picked.toIso8601String().split('T')[0]);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: widget.field.placeholder ?? 'Select date',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(
          date != null
              ? '${date.day}/${date.month}/${date.year}'
              : '',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildTimeField(BuildContext context, ThemeData theme) {
    final timeStr = widget.value as String?;
    TimeOfDay? time;
    if (timeStr != null) {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    return InkWell(
      onTap: widget.readOnly ? null : () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time ?? TimeOfDay.now(),
        );
        if (picked != null) {
          widget.onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: widget.field.placeholder ?? 'Select time',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.access_time),
        ),
        child: Text(
          time != null ? time.format(context) : '',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildDateTimeField(BuildContext context, ThemeData theme) {
    final dateTimeStr = widget.value as String?;
    DateTime? dateTime;
    if (dateTimeStr != null) {
      dateTime = DateTime.tryParse(dateTimeStr);
    }

    return InkWell(
      onTap: widget.readOnly ? null : () async {
        final date = await showDatePicker(
          context: context,
          initialDate: dateTime ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (date == null) return;

        if (context.mounted) {
          final time = await showTimePicker(
            context: context,
            initialTime: dateTime != null
                ? TimeOfDay.fromDateTime(dateTime)
                : TimeOfDay.now(),
          );
          if (time != null) {
            final dt = DateTime(
              date.year,
              date.month,
              date.day,
              time.hour,
              time.minute,
            );
            widget.onChanged(dt.toIso8601String());
          }
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: widget.field.placeholder ?? 'Select date and time',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.event),
        ),
        child: Text(
          dateTime != null
              ? '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
              : '',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildRating(ThemeData theme) {
    final rating = (widget.value as num?)?.toInt() ?? 0;
    final maxRating = widget.field.maxRating?.toInt() ?? 5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starValue = index + 1;
        return IconButton(
          icon: Icon(
            starValue <= rating ? Icons.star : Icons.star_border,
            color: starValue <= rating ? Colors.amber : theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: widget.readOnly ? null : () => widget.onChanged(starValue),
        );
      }),
    );
  }

  Widget _buildScale(ThemeData theme) {
    final min = widget.field.minRating?.toDouble() ?? 1;
    final max = widget.field.maxRating?.toDouble() ?? 10;
    final current = (widget.value as num?)?.toDouble() ?? min;

    return Column(
      children: [
        Slider(
          value: current.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          label: current.round().toString(),
          onChanged: widget.readOnly ? null : (val) => widget.onChanged(val.round()),
        ),
        if (widget.field.labels != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.field.labels!['min'] ?? min.round().toString(),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                widget.field.labels!['max'] ?? max.round().toString(),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSignature(ThemeData theme) {
    final hasSig = widget.value != null;

    return Container(
      height: 150,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: hasSig
          ? Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.check_circle,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (!widget.readOnly)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => widget.onChanged(null),
                    ),
                  ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.draw,
                    size: 32,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to sign',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.field.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.field.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.field.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Divider(color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }

  Widget _buildLocation(ThemeData theme) {
    final loc = widget.value as Map<String, dynamic>?;

    return InkWell(
      onTap: widget.readOnly ? null : () {
        // TODO: Open location picker
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: widget.field.placeholder ?? 'Select location',
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.location_on),
        ),
        child: Text(
          loc != null
              ? '${loc['lat']?.toStringAsFixed(4)}, ${loc['lng']?.toStringAsFixed(4)}'
              : '',
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildFileField(ThemeData theme) {
    final files = widget.value as List<Map<String, dynamic>>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.readOnly)
          OutlinedButton.icon(
            icon: Icon(widget.field.type == FormFieldType.image ? Icons.add_photo_alternate : Icons.attach_file),
            label: Text(widget.field.type == FormFieldType.image ? 'Add Image' : 'Add File'),
            onPressed: () {
              // TODO: Open file picker
            },
          ),
        if (files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: files.map((file) {
                return Chip(
                  label: Text(file['asset'] ?? 'File'),
                  onDeleted: widget.readOnly ? null : () {
                    final newFiles = List<Map<String, dynamic>>.from(files);
                    newFiles.remove(file);
                    widget.onChanged(newFiles);
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
