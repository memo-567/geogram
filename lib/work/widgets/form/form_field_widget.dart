/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../models/form_content.dart';

/// Widget for rendering a form field based on its type
class FormFieldWidget extends StatelessWidget {
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
                field.label,
                style: theme.textTheme.titleSmall,
              ),
              if (field.required)
                Text(
                  ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
          // Description
          if (field.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                field.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Field input
          _buildField(context, theme),
          // Error
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
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
    switch (field.type) {
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
      controller: TextEditingController(text: value?.toString() ?? ''),
      readOnly: readOnly,
      decoration: InputDecoration(
        hintText: field.placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildTextArea(ThemeData theme) {
    return TextField(
      controller: TextEditingController(text: value?.toString() ?? ''),
      readOnly: readOnly,
      maxLines: field.rows ?? 4,
      decoration: InputDecoration(
        hintText: field.placeholder,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField(ThemeData theme) {
    return TextField(
      controller: TextEditingController(text: value?.toString() ?? ''),
      readOnly: readOnly,
      keyboardType: TextInputType.numberWithOptions(
        decimal: field.step != null && field.step! < 1,
      ),
      decoration: InputDecoration(
        hintText: field.placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) {
        final num? number = num.tryParse(text);
        onChanged(number);
      },
    );
  }

  Widget _buildSelect(ThemeData theme) {
    return DropdownButtonFormField<String>(
      value: value as String?,
      decoration: InputDecoration(
        hintText: field.placeholder,
        border: const OutlineInputBorder(),
      ),
      items: field.options?.map((opt) {
        return DropdownMenuItem(
          value: opt.value,
          child: Text(opt.label),
        );
      }).toList() ?? [],
      onChanged: readOnly ? null : (val) => onChanged(val),
    );
  }

  Widget _buildMultiSelect(ThemeData theme) {
    final selected = (value as List<String>?) ?? [];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: field.options?.map((opt) {
        final isSelected = selected.contains(opt.value);
        return FilterChip(
          label: Text(opt.label),
          selected: isSelected,
          onSelected: readOnly ? null : (sel) {
            final newList = List<String>.from(selected);
            if (sel) {
              newList.add(opt.value);
            } else {
              newList.remove(opt.value);
            }
            onChanged(newList);
          },
        );
      }).toList() ?? [],
    );
  }

  Widget _buildRadio(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: field.options?.map((opt) {
        return RadioListTile<String>(
          value: opt.value,
          groupValue: value as String?,
          title: Text(opt.label),
          contentPadding: EdgeInsets.zero,
          onChanged: readOnly ? null : (val) => onChanged(val),
        );
      }).toList() ?? [],
    );
  }

  Widget _buildCheckbox(ThemeData theme) {
    return CheckboxListTile(
      value: value == true,
      title: Text(field.label),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: readOnly ? null : (val) => onChanged(val),
    );
  }

  Widget _buildCheckboxGroup(ThemeData theme) {
    final selected = (value as List<String>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: field.options?.map((opt) {
        return CheckboxListTile(
          value: selected.contains(opt.value),
          title: Text(opt.label),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: readOnly ? null : (sel) {
            final newList = List<String>.from(selected);
            if (sel == true) {
              newList.add(opt.value);
            } else {
              newList.remove(opt.value);
            }
            onChanged(newList);
          },
        );
      }).toList() ?? [],
    );
  }

  Widget _buildDateField(BuildContext context, ThemeData theme) {
    final dateStr = value as String?;
    DateTime? date;
    if (dateStr != null) {
      date = DateTime.tryParse(dateStr);
    }

    return InkWell(
      onTap: readOnly ? null : () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onChanged(picked.toIso8601String().split('T')[0]);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: field.placeholder ?? 'Select date',
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
    final timeStr = value as String?;
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
      onTap: readOnly ? null : () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time ?? TimeOfDay.now(),
        );
        if (picked != null) {
          onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: field.placeholder ?? 'Select time',
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
    final dateTimeStr = value as String?;
    DateTime? dateTime;
    if (dateTimeStr != null) {
      dateTime = DateTime.tryParse(dateTimeStr);
    }

    return InkWell(
      onTap: readOnly ? null : () async {
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
            onChanged(dt.toIso8601String());
          }
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: field.placeholder ?? 'Select date and time',
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
    final rating = (value as num?)?.toInt() ?? 0;
    final maxRating = field.maxRating?.toInt() ?? 5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starValue = index + 1;
        return IconButton(
          icon: Icon(
            starValue <= rating ? Icons.star : Icons.star_border,
            color: starValue <= rating ? Colors.amber : theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: readOnly ? null : () => onChanged(starValue),
        );
      }),
    );
  }

  Widget _buildScale(ThemeData theme) {
    final min = field.minRating?.toDouble() ?? 1;
    final max = field.maxRating?.toDouble() ?? 10;
    final current = (value as num?)?.toDouble() ?? min;

    return Column(
      children: [
        Slider(
          value: current.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          label: current.round().toString(),
          onChanged: readOnly ? null : (val) => onChanged(val.round()),
        ),
        if (field.labels != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                field.labels!['min'] ?? min.round().toString(),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                field.labels!['max'] ?? max.round().toString(),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSignature(ThemeData theme) {
    final hasSig = value != null;

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
                if (!readOnly)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => onChanged(null),
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
            field.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (field.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                field.description!,
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
    final loc = value as Map<String, dynamic>?;

    return InkWell(
      onTap: readOnly ? null : () {
        // TODO: Open location picker
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: field.placeholder ?? 'Select location',
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
    final files = value as List<Map<String, dynamic>>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!readOnly)
          OutlinedButton.icon(
            icon: Icon(field.type == FormFieldType.image ? Icons.add_photo_alternate : Icons.attach_file),
            label: Text(field.type == FormFieldType.image ? 'Add Image' : 'Add File'),
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
                  onDeleted: readOnly ? null : () {
                    final newFiles = List<Map<String, dynamic>>.from(files);
                    newFiles.remove(file);
                    onChanged(newFiles);
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
