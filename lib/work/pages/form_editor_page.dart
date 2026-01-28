/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/form_content.dart';
import '../models/spreadsheet_content.dart';
import '../services/ndf_service.dart';
import '../widgets/form/form_field_widget.dart';
import '../widgets/spreadsheet/sheet_grid_widget.dart';

/// Form editor page - design forms and view responses
class FormEditorPage extends StatefulWidget {
  final String filePath;
  final String? title;

  const FormEditorPage({
    super.key,
    required this.filePath,
    this.title,
  });

  @override
  State<FormEditorPage> createState() => _FormEditorPageState();
}

class _FormEditorPageState extends State<FormEditorPage>
    with SingleTickerProviderStateMixin {
  final I18nService _i18n = I18nService();
  final NdfService _ndfService = NdfService();

  NdfDocument? _metadata;
  FormContent? _form;
  List<FormResponse> _responses = [];
  SpreadsheetSheet? _responsesSheet;
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _error;

  late TabController _tabController;

  // Form preview state
  Map<String, dynamic> _previewValues = {};
  Map<String, String?> _previewErrors = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // Rebuild to update FAB visibility
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadDocument();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load metadata
      final metadata = await _ndfService.readMetadata(widget.filePath);
      if (metadata == null) {
        throw Exception('Could not read document metadata');
      }

      // Load form content
      final form = await _ndfService.readFormContent(widget.filePath);
      if (form == null) {
        throw Exception('Could not read form content');
      }

      // Load responses
      final responses = await _ndfService.readFormResponses(widget.filePath);

      // Load or create responses spreadsheet
      var responsesSheet = await _ndfService.readResponsesSpreadsheet(widget.filePath);
      if (responsesSheet == null && responses.isNotEmpty) {
        // Build spreadsheet from existing responses
        responsesSheet = _buildResponsesSpreadsheet(form, responses);
      }

      // Initialize preview values with defaults
      final previewValues = <String, dynamic>{};
      for (final field in form.fields) {
        previewValues[field.id] = field.defaultValue;
      }

      setState(() {
        _metadata = metadata;
        _form = form;
        _responses = responses;
        _responsesSheet = responsesSheet;
        _previewValues = previewValues;
        _previewErrors = {};
        _isLoading = false;
      });
    } catch (e) {
      LogService().log('FormEditorPage: Error loading document: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_form == null || _metadata == null) return;

    try {
      // Update metadata modified time
      _metadata!.touch();

      // Save form content
      await _ndfService.saveFormContent(widget.filePath, _form!);

      // Save responses spreadsheet if it exists
      if (_responsesSheet != null) {
        await _ndfService.saveResponsesSpreadsheet(widget.filePath, _responsesSheet!);
      }

      // Update metadata
      await _ndfService.updateMetadata(widget.filePath, _metadata!);

      setState(() {
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('document_saved'))),
        );
      }
    } catch (e) {
      LogService().log('FormEditorPage: Error saving document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  void _addField(FormFieldType type) {
    if (_form == null) return;

    final id = 'field-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final label = _getDefaultLabel(type);

    List<FormOption>? options;
    if (type == FormFieldType.select ||
        type == FormFieldType.selectMultiple ||
        type == FormFieldType.radio ||
        type == FormFieldType.checkboxGroup) {
      options = [
        FormOption(value: 'option1', label: 'Option 1'),
        FormOption(value: 'option2', label: 'Option 2'),
        FormOption(value: 'option3', label: 'Option 3'),
      ];
    }

    final field = NdfFormField(
      id: id,
      type: type,
      label: label,
      options: options,
      rows: type == FormFieldType.textarea ? 4 : null,
      minRating: type == FormFieldType.rating ? 1 : (type == FormFieldType.scale ? 1 : null),
      maxRating: type == FormFieldType.rating ? 5 : (type == FormFieldType.scale ? 10 : null),
    );

    setState(() {
      _form!.fields.add(field);
      _previewValues[id] = field.defaultValue;
      _hasChanges = true;
    });
  }

  String _getDefaultLabel(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return _i18n.t('work_field_text');
      case FormFieldType.textarea:
        return _i18n.t('work_field_textarea');
      case FormFieldType.number:
        return _i18n.t('work_field_number');
      case FormFieldType.select:
        return _i18n.t('work_field_select');
      case FormFieldType.selectMultiple:
        return _i18n.t('work_field_select_multiple');
      case FormFieldType.radio:
        return _i18n.t('work_field_radio');
      case FormFieldType.checkbox:
        return _i18n.t('work_field_checkbox');
      case FormFieldType.checkboxGroup:
        return _i18n.t('work_field_checkbox_group');
      case FormFieldType.date:
        return _i18n.t('work_field_date');
      case FormFieldType.time:
        return _i18n.t('work_field_time');
      case FormFieldType.datetime:
        return _i18n.t('work_field_datetime');
      case FormFieldType.rating:
        return _i18n.t('work_field_rating');
      case FormFieldType.scale:
        return _i18n.t('work_field_scale');
      case FormFieldType.signature:
        return _i18n.t('work_field_signature');
      case FormFieldType.section:
        return _i18n.t('work_field_section');
      case FormFieldType.location:
        return _i18n.t('work_field_location');
      case FormFieldType.file:
        return _i18n.t('work_field_file');
      case FormFieldType.image:
        return _i18n.t('work_field_image');
      case FormFieldType.hidden:
        return 'Hidden';
    }
  }

  String _getFieldDescription(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return _i18n.t('work_field_text_desc');
      case FormFieldType.textarea:
        return _i18n.t('work_field_textarea_desc');
      case FormFieldType.number:
        return _i18n.t('work_field_number_desc');
      case FormFieldType.select:
        return _i18n.t('work_field_select_desc');
      case FormFieldType.selectMultiple:
        return _i18n.t('work_field_select_multiple_desc');
      case FormFieldType.radio:
        return _i18n.t('work_field_radio_desc');
      case FormFieldType.checkbox:
        return _i18n.t('work_field_checkbox_desc');
      case FormFieldType.checkboxGroup:
        return _i18n.t('work_field_checkbox_group_desc');
      case FormFieldType.date:
        return _i18n.t('work_field_date_desc');
      case FormFieldType.time:
        return _i18n.t('work_field_time_desc');
      case FormFieldType.datetime:
        return _i18n.t('work_field_datetime_desc');
      case FormFieldType.rating:
        return _i18n.t('work_field_rating_desc');
      case FormFieldType.scale:
        return _i18n.t('work_field_scale_desc');
      case FormFieldType.signature:
        return _i18n.t('work_field_signature_desc');
      case FormFieldType.section:
        return _i18n.t('work_field_section_desc');
      case FormFieldType.location:
        return _i18n.t('work_field_location_desc');
      case FormFieldType.file:
        return _i18n.t('work_field_file_desc');
      case FormFieldType.image:
        return _i18n.t('work_field_image_desc');
      case FormFieldType.hidden:
        return 'Hidden field';
    }
  }

  void _deleteField(String fieldId) {
    if (_form == null) return;

    setState(() {
      _form!.fields.removeWhere((f) => f.id == fieldId);
      _previewValues.remove(fieldId);
      _previewErrors.remove(fieldId);
      _hasChanges = true;
    });
  }

  /// Show form settings dialog (time interval, etc.)
  Future<void> _showFormSettingsDialog() async {
    if (_form == null) return;

    final settings = _form!.settings;
    var acceptingSubmissions = settings.acceptingSubmissions;
    DateTime? openAfter = settings.openAfter;
    DateTime? closeAfter = settings.closeAfter;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          return AlertDialog(
            title: Text(_i18n.t('work_form_settings')),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Accept submissions switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_i18n.t('work_form_accepting_submissions')),
                      subtitle: Text(
                        acceptingSubmissions
                            ? _i18n.t('work_form_accepting_submissions_on')
                            : _i18n.t('work_form_accepting_submissions_off'),
                        style: TextStyle(
                          color: acceptingSubmissions
                              ? Colors.green
                              : theme.colorScheme.error,
                        ),
                      ),
                      value: acceptingSubmissions,
                      onChanged: (val) => setDialogState(() => acceptingSubmissions = val),
                    ),

                    const Divider(height: 32),

                    // Time interval section
                    Text(
                      _i18n.t('work_form_time_interval'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _i18n.t('work_form_time_interval_desc'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Start date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow),
                      title: Text(_i18n.t('work_form_open_after')),
                      subtitle: Text(
                        openAfter != null
                            ? _formatDateTimeForDisplay(openAfter!)
                            : _i18n.t('work_form_no_limit'),
                        style: TextStyle(
                          color: openAfter != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (openAfter != null)
                            IconButton(
                              icon: Icon(Icons.clear, color: theme.colorScheme.error),
                              onPressed: () => setDialogState(() => openAfter = null),
                              tooltip: _i18n.t('work_form_clear_date'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              final date = await _pickDateTime(context, openAfter);
                              if (date != null) {
                                setDialogState(() => openAfter = date);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // End date
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.stop),
                      title: Text(_i18n.t('work_form_close_after')),
                      subtitle: Text(
                        closeAfter != null
                            ? _formatDateTimeForDisplay(closeAfter!)
                            : _i18n.t('work_form_no_limit'),
                        style: TextStyle(
                          color: closeAfter != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (closeAfter != null)
                            IconButton(
                              icon: Icon(Icons.clear, color: theme.colorScheme.error),
                              onPressed: () => setDialogState(() => closeAfter = null),
                              tooltip: _i18n.t('work_form_clear_date'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              final date = await _pickDateTime(context, closeAfter);
                              if (date != null) {
                                setDialogState(() => closeAfter = date);
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Validation warning
                    if (openAfter != null && closeAfter != null && openAfter!.isAfter(closeAfter!))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: theme.colorScheme.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _i18n.t('work_form_date_warning'),
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Status indicator
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getFormStatusIcon(acceptingSubmissions, openAfter, closeAfter),
                            color: _getFormStatusColor(acceptingSubmissions, openAfter, closeAfter, theme),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getFormStatusText(acceptingSubmissions, openAfter, closeAfter),
                              style: TextStyle(
                                color: _getFormStatusColor(acceptingSubmissions, openAfter, closeAfter, theme),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_i18n.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_i18n.t('save')),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      setState(() {
        _form!.settings = _form!.settings.copyWith(
          acceptingSubmissions: acceptingSubmissions,
          openAfter: openAfter,
          closeAfter: closeAfter,
          clearOpenAfter: openAfter == null,
          clearCloseAfter: closeAfter == null,
        );
        _hasChanges = true;
      });
    }
  }

  /// Pick a date and time
  Future<DateTime?> _pickDateTime(BuildContext context, DateTime? initial) async {
    final now = DateTime.now();
    final initialDate = initial ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );

    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// Format date/time for display in settings dialog
  String _formatDateTimeForDisplay(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Get form status icon based on settings
  IconData _getFormStatusIcon(bool acceptingSubmissions, DateTime? openAfter, DateTime? closeAfter) {
    if (!acceptingSubmissions) return Icons.block;
    final now = DateTime.now();
    if (openAfter != null && now.isBefore(openAfter)) return Icons.schedule;
    if (closeAfter != null && now.isAfter(closeAfter)) return Icons.lock;
    return Icons.lock_open;
  }

  /// Get form status color based on settings
  Color _getFormStatusColor(bool acceptingSubmissions, DateTime? openAfter, DateTime? closeAfter, ThemeData theme) {
    if (!acceptingSubmissions) return theme.colorScheme.error;
    final now = DateTime.now();
    if (openAfter != null && now.isBefore(openAfter)) return Colors.orange;
    if (closeAfter != null && now.isAfter(closeAfter)) return theme.colorScheme.error;
    return Colors.green;
  }

  /// Get form status text based on settings
  String _getFormStatusText(bool acceptingSubmissions, DateTime? openAfter, DateTime? closeAfter) {
    if (!acceptingSubmissions) {
      return _i18n.t('work_form_status_disabled');
    }
    final now = DateTime.now();
    if (openAfter != null && now.isBefore(openAfter)) {
      return _i18n.t('work_form_status_scheduled');
    }
    if (closeAfter != null && now.isAfter(closeAfter)) {
      return _i18n.t('work_form_status_closed');
    }
    return _i18n.t('work_form_status_open');
  }

  /// Enhanced field editor dialog with type-specific configuration
  Future<void> _showFieldConfigDialog(NdfFormField field) async {
    final labelController = TextEditingController(text: field.label);
    final descController = TextEditingController(text: field.description ?? '');
    final placeholderController = TextEditingController(text: field.placeholder ?? '');
    var isRequired = field.required;

    // Options for choice fields
    var options = field.options?.map((o) => FormOption(value: o.value, label: o.label)).toList() ?? [];

    // Rating configuration
    var minRating = field.minRating?.toInt() ?? 1;
    var maxRating = field.maxRating?.toInt() ?? 5;

    // Validation rules
    var minLength = field.validation?.minLength;
    var maxLength = field.validation?.maxLength;
    var minSelected = field.validation?.minSelected;
    var maxSelected = field.validation?.maxSelected;

    final bool hasOptions = field.type == FormFieldType.select ||
        field.type == FormFieldType.selectMultiple ||
        field.type == FormFieldType.radio ||
        field.type == FormFieldType.checkboxGroup;

    final bool hasRating = field.type == FormFieldType.rating;
    final bool hasScale = field.type == FormFieldType.scale;
    final bool hasTextValidation = field.type == FormFieldType.text || field.type == FormFieldType.textarea;
    final bool hasSelectionValidation = field.type == FormFieldType.selectMultiple || field.type == FormFieldType.checkboxGroup;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);

          return AlertDialog(
            title: Text(_i18n.t('work_form_edit_field')),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic section
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: _i18n.t('work_form_field_label'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: _i18n.t('work_form_field_description'),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: placeholderController,
                      decoration: InputDecoration(
                        labelText: _i18n.t('work_form_field_placeholder'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isRequired,
                      title: Text(_i18n.t('work_form_field_required')),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setDialogState(() => isRequired = val ?? false),
                    ),

                    // Options editor for choice fields
                    if (hasOptions) ...[
                      const Divider(height: 32),
                      Text(
                        _i18n.t('work_form_configure_options'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      ...options.asMap().entries.map((entry) {
                        final index = entry.key;
                        final option = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: option.label),
                                  decoration: InputDecoration(
                                    labelText: _i18n.t('work_form_option_label').replaceAll('{number}', '${index + 1}'),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (val) {
                                    options[index] = FormOption(
                                      value: 'option${index + 1}',
                                      label: val,
                                    );
                                  },
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                onPressed: options.length > 1 ? () {
                                  setDialogState(() {
                                    options.removeAt(index);
                                  });
                                } : null,
                                tooltip: _i18n.t('work_form_remove_option'),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(_i18n.t('work_form_add_option')),
                        onPressed: () {
                          setDialogState(() {
                            final newIndex = options.length + 1;
                            options.add(FormOption(
                              value: 'option$newIndex',
                              label: 'Option $newIndex',
                            ));
                          });
                        },
                      ),
                    ],

                    // Rating configuration
                    if (hasRating) ...[
                      const Divider(height: 32),
                      Text(
                        _i18n.t('work_form_configure_rating'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: minRating,
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_min_rating'),
                                border: const OutlineInputBorder(),
                              ),
                              items: [0, 1].map((v) => DropdownMenuItem(
                                value: v,
                                child: Text('$v'),
                              )).toList(),
                              onChanged: (val) => setDialogState(() => minRating = val ?? 1),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: maxRating,
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_max_rating'),
                                border: const OutlineInputBorder(),
                              ),
                              items: [3, 4, 5, 6, 7, 10].map((v) => DropdownMenuItem(
                                value: v,
                                child: Text('$v'),
                              )).toList(),
                              onChanged: (val) => setDialogState(() => maxRating = val ?? 5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _i18n.t('work_form_preview_stars'),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(maxRating - minRating + 1, (index) {
                          return Icon(
                            Icons.star,
                            color: Colors.amber,
                            size: 24,
                          );
                        }),
                      ),
                    ],

                    // Scale configuration
                    if (hasScale) ...[
                      const Divider(height: 32),
                      Text(
                        _i18n.t('work_form_rating_range'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: minRating.toString()),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_min_rating'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                minRating = int.tryParse(val) ?? 1;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: maxRating.toString()),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_max_rating'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                maxRating = int.tryParse(val) ?? 10;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Text validation
                    if (hasTextValidation) ...[
                      const Divider(height: 32),
                      Text(
                        _i18n.t('work_form_configure_validation'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: minLength?.toString() ?? ''),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_min_length'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                minLength = int.tryParse(val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: maxLength?.toString() ?? ''),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_max_length'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                maxLength = int.tryParse(val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Selection validation
                    if (hasSelectionValidation) ...[
                      const Divider(height: 32),
                      Text(
                        _i18n.t('work_form_configure_validation'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: minSelected?.toString() ?? ''),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_min_selections'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                minSelected = int.tryParse(val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: maxSelected?.toString() ?? ''),
                              decoration: InputDecoration(
                                labelText: _i18n.t('work_form_max_selections'),
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                maxSelected = int.tryParse(val);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_i18n.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_i18n.t('save')),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      // Build validation object
      FormValidation? validation;
      if (minLength != null || maxLength != null || minSelected != null || maxSelected != null) {
        validation = FormValidation(
          minLength: minLength,
          maxLength: maxLength,
          minSelected: minSelected,
          maxSelected: maxSelected,
        );
      }

      final index = _form!.fields.indexWhere((f) => f.id == field.id);
      if (index >= 0) {
        setState(() {
          _form!.fields[index] = NdfFormField(
            id: field.id,
            type: field.type,
            label: labelController.text,
            required: isRequired,
            description: descController.text.isEmpty ? null : descController.text,
            placeholder: placeholderController.text.isEmpty ? null : placeholderController.text,
            defaultValue: field.defaultValue,
            validation: validation,
            options: hasOptions ? options : null,
            rows: field.rows,
            step: field.step,
            format: field.format,
            accept: field.accept,
            maxFiles: field.maxFiles,
            maxSizeMb: field.maxSizeMb,
            minRating: (hasRating || hasScale) ? minRating : null,
            maxRating: (hasRating || hasScale) ? maxRating : null,
            labels: field.labels,
          );
          _hasChanges = true;
        });
      }
    }
  }

  /// Validate a field value
  String? _validateField(NdfFormField field, dynamic value) {
    // Check required
    if (field.required) {
      if (value == null) return '${field.label} is required';
      if (value is String && value.isEmpty) return '${field.label} is required';
      if (value is List && value.isEmpty) return '${field.label} is required';
    }

    // Skip further validation if no value
    if (value == null || (value is String && value.isEmpty)) return null;

    final validation = field.validation;
    if (validation == null) return null;

    // Text length validation
    if (value is String) {
      if (validation.minLength != null && value.length < validation.minLength!) {
        return 'Minimum ${validation.minLength} characters required';
      }
      if (validation.maxLength != null && value.length > validation.maxLength!) {
        return 'Maximum ${validation.maxLength} characters allowed';
      }
    }

    // Selection count validation
    if (value is List) {
      if (validation.minSelected != null && value.length < validation.minSelected!) {
        return 'Select at least ${validation.minSelected} options';
      }
      if (validation.maxSelected != null && value.length > validation.maxSelected!) {
        return 'Select at most ${validation.maxSelected} options';
      }
    }

    return null;
  }

  /// Validate all preview fields
  bool _validatePreview() {
    if (_form == null) return false;

    bool isValid = true;
    final errors = <String, String?>{};

    for (final field in _form!.fields) {
      final error = _validateField(field, _previewValues[field.id]);
      errors[field.id] = error;
      if (error != null) isValid = false;
    }

    setState(() {
      _previewErrors = errors;
    });

    return isValid;
  }

  /// Clear preview values
  void _clearPreview() {
    if (_form == null) return;

    setState(() {
      _previewValues = {};
      _previewErrors = {};
      for (final field in _form!.fields) {
        _previewValues[field.id] = field.defaultValue;
      }
    });
  }

  Future<void> _submitPreview() async {
    if (_form == null) return;

    // Check if form is accepting submissions
    if (!_form!.settings.isOpen) {
      final now = DateTime.now();
      final settings = _form!.settings;
      String message;
      if (!settings.acceptingSubmissions) {
        message = _i18n.t('work_form_submissions_disabled');
      } else if (settings.openAfter != null && now.isBefore(settings.openAfter!)) {
        message = _i18n.t('work_form_not_open_yet');
      } else {
        message = _i18n.t('work_form_closed');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    // Validate all fields
    if (!_validatePreview()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fix the errors before submitting')),
      );
      return;
    }

    // Create response
    final response = FormResponse.create(
      formId: _form!.id,
      formVersion: _form!.version,
      responses: Map<String, dynamic>.from(_previewValues),
    );

    try {
      await _ndfService.saveFormResponse(widget.filePath, response);

      setState(() {
        _responses.insert(0, response);
        // Sync response to spreadsheet
        _syncResponseToSheet(response);
        // Reset preview
        _previewValues = {};
        _previewErrors = {};
        for (final field in _form!.fields) {
          _previewValues[field.id] = field.defaultValue;
        }
        _hasChanges = true; // Mark as changed to save spreadsheet
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('response_submitted'))),
        );
        // Switch to responses tab
        _tabController.animateTo(2);
      }
    } catch (e) {
      LogService().log('FormEditorPage: Error submitting response: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting: $e')),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('unsaved_changes')),
        content: Text(_i18n.t('unsaved_changes_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_i18n.t('discard')),
          ),
          FilledButton(
            onPressed: () async {
              await _save();
              if (mounted) Navigator.pop(context, true);
            },
            child: Text(_i18n.t('save')),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_form?.title ?? widget.title ?? _i18n.t('work_form')),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: _showFormSettingsDialog,
              tooltip: _i18n.t('work_form_settings'),
            ),
            if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _save,
                tooltip: _i18n.t('save'),
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: _i18n.t('design')),
              Tab(text: _i18n.t('preview')),
              Tab(text: '${_i18n.t('responses')} (${_responses.length})'),
            ],
          ),
        ),
        body: _buildBody(),
        floatingActionButton: _tabController.index == 0
            ? FloatingActionButton.extended(
                onPressed: _showAddFieldMenu,
                icon: const Icon(Icons.add),
                label: Text(_i18n.t('add_field')),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_i18n.t('error_loading_document')),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadDocument,
              icon: const Icon(Icons.refresh),
              label: Text(_i18n.t('retry')),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildDesignTab(),
        _buildPreviewTab(),
        _buildResponsesTab(),
      ],
    );
  }

  Widget _buildDesignTab() {
    final theme = Theme.of(context);

    if (_form == null || _form!.fields.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(_i18n.t('work_form_no_fields')),
            const SizedBox(height: 8),
            Text(
              _i18n.t('work_form_no_fields_hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddFieldMenu,
              icon: const Icon(Icons.add),
              label: Text(_i18n.t('add_field')),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _form!.fields.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        setState(() {
          final field = _form!.fields.removeAt(oldIndex);
          _form!.fields.insert(newIndex, field);
          _hasChanges = true;
        });
      },
      itemBuilder: (context, index) {
        final field = _form!.fields[index];
        return _buildDesignFieldCard(field, theme, index);
      },
    );
  }

  /// Build a design card with enhanced info display
  Widget _buildDesignFieldCard(NdfFormField field, ThemeData theme, int index) {
    // Get summary info based on field type
    String? summaryInfo;
    if (field.options != null && field.options!.isNotEmpty) {
      summaryInfo = _i18n.t('work_form_options_count').replaceAll('{count}', '${field.options!.length}');
    } else if (field.type == FormFieldType.rating) {
      final min = field.minRating?.toInt() ?? 1;
      final max = field.maxRating?.toInt() ?? 5;
      summaryInfo = _i18n.t('work_form_stars_range')
          .replaceAll('{min}', '$min')
          .replaceAll('{max}', '$max');
    } else if (field.type == FormFieldType.scale) {
      final min = field.minRating?.toInt() ?? 1;
      final max = field.maxRating?.toInt() ?? 10;
      summaryInfo = '$min - $max';
    }

    return Card(
      key: ValueKey(field.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getFieldColor(field.type).withValues(alpha: 0.15),
          child: Icon(
            _getFieldIcon(field.type),
            color: _getFieldColor(field.type),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(field.label)),
            if (field.required)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _i18n.t('required'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              _getDefaultLabel(field.type),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summaryInfo != null) ...[
              Text(
                ' - ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                summaryInfo,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showFieldConfigDialog(field),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
              onPressed: () => _deleteField(field.id),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTab() {
    if (_form == null || _form!.fields.isEmpty) {
      return Center(child: Text(_i18n.t('work_form_no_fields')));
    }

    final theme = Theme.of(context);
    final isFormOpen = _form!.settings.isOpen;
    final settings = _form!.settings;

    return Column(
      children: [
        // Time restriction banner
        if (!isFormOpen || settings.openAfter != null || settings.closeAfter != null)
          _buildTimeBanner(theme, settings),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _form!.fields.length,
            itemBuilder: (context, index) {
              final field = _form!.fields[index];
              return FormFieldWidget(
                field: field,
                value: _previewValues[field.id],
                error: _previewErrors[field.id],
                onChanged: (val) {
                  setState(() {
                    _previewValues[field.id] = val;
                    // Clear error when value changes
                    _previewErrors[field.id] = null;
                  });
                },
              );
            },
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clearPreview,
                      icon: const Icon(Icons.clear),
                      label: Text(_i18n.t('work_form_clear')),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isFormOpen ? _submitPreview : null,
                      icon: const Icon(Icons.send),
                      label: Text(_i18n.t('work_form_submit')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build the time restriction banner for preview tab
  Widget _buildTimeBanner(ThemeData theme, FormSettings settings) {
    final now = DateTime.now();

    Color bgColor;
    Color textColor;
    IconData icon;
    String text;

    if (!settings.acceptingSubmissions) {
      // Manually disabled
      bgColor = theme.colorScheme.errorContainer;
      textColor = theme.colorScheme.onErrorContainer;
      icon = Icons.block;
      text = _i18n.t('work_form_status_disabled');
    } else if (settings.openAfter != null && now.isBefore(settings.openAfter!)) {
      // Not open yet
      bgColor = Colors.orange.withValues(alpha: 0.15);
      textColor = Colors.orange.shade700;
      icon = Icons.schedule;
      text = '${_i18n.t('work_form_opens')}: ${_formatDateTimeForDisplay(settings.openAfter!)}';
    } else if (settings.closeAfter != null && now.isAfter(settings.closeAfter!)) {
      // Closed
      bgColor = theme.colorScheme.errorContainer;
      textColor = theme.colorScheme.onErrorContainer;
      icon = Icons.lock;
      text = '${_i18n.t('work_form_closed_at')}: ${_formatDateTimeForDisplay(settings.closeAfter!)}';
    } else if (settings.closeAfter != null) {
      // Open but has deadline
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green.shade700;
      icon = Icons.lock_open;
      text = '${_i18n.t('work_form_closes')}: ${_formatDateTimeForDisplay(settings.closeAfter!)}';
    } else {
      // Open with start date shown
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green.shade700;
      icon = Icons.lock_open;
      text = _i18n.t('work_form_status_open');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsesTab() {
    final theme = Theme.of(context);

    if (_responses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(_i18n.t('work_form_no_responses')),
          ],
        ),
      );
    }

    // Ensure spreadsheet is created if we have responses but no sheet yet
    _responsesSheet ??= _buildResponsesSpreadsheet(_form!, _responses);

    return Column(
      children: [
        // Summary header with response count
        _buildResponsesHeader(theme),
        // Spreadsheet view
        Expanded(
          child: SheetGridWidget(
            sheet: _responsesSheet!,
            onChanged: (sheet) {
              setState(() {
                _responsesSheet = sheet;
                _hasChanges = true;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResponsesHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            '${_i18n.t('work_form_total_responses')}: ${_responses.length}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Info tooltip about extra columns
          Tooltip(
            message: _i18n.t('work_form_spreadsheet_hint'),
            child: Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the responses spreadsheet from form responses
  SpreadsheetSheet _buildResponsesSpreadsheet(FormContent form, List<FormResponse> responses) {
    final sheet = SpreadsheetSheet.create(id: 'responses', name: 'Responses');

    // Adjust dimensions based on form fields and responses
    // Columns: # | Submitted | Field1 | Field2 | ... | Extra columns for formulas
    final numFields = form.fields.length;
    final numResponses = responses.length;
    sheet.cols = numFields + 6; // # + Submitted + fields + extra columns for formulas
    sheet.rows = numResponses + 10; // Header + responses + extra rows

    // Row 0: Headers - "#", "Submitted", then field labels (the question text)
    sheet.setCell(0, 0, SpreadsheetCell(value: '#', type: CellType.string));
    sheet.setCell(0, 1, SpreadsheetCell(value: _i18n.t('work_form_submitted'), type: CellType.string));
    for (int i = 0; i < form.fields.length; i++) {
      sheet.setCell(0, i + 2, SpreadsheetCell(
        value: form.fields[i].label,
        type: CellType.string,
      ));
    }

    // Data rows - each row is one response (sorted newest first in _responses)
    // We display oldest first (1, 2, 3...) so reverse the index
    for (int r = 0; r < responses.length; r++) {
      final response = responses[responses.length - 1 - r]; // Reverse order
      final rowIndex = r + 1;

      // Column A: Response index (1, 2, 3, ...)
      sheet.setCell(rowIndex, 0, SpreadsheetCell(
        value: rowIndex,
        type: CellType.number,
      ));

      // Column B: Submitted timestamp (YYYY-MM-DD HH:MM:SS)
      sheet.setCell(rowIndex, 1, SpreadsheetCell(
        value: _formatTimestamp(response.submittedAt),
        type: CellType.string,
      ));

      // Columns C+: Field values (answers)
      for (int c = 0; c < form.fields.length; c++) {
        final field = form.fields[c];
        final value = response.responses[field.id];
        sheet.setCell(rowIndex, c + 2, _valueToCell(value, field.type));
      }
    }

    return sheet;
  }

  /// Sync a new response to the spreadsheet
  void _syncResponseToSheet(FormResponse response) {
    if (_form == null) return;

    // Create spreadsheet if it doesn't exist
    if (_responsesSheet == null) {
      _responsesSheet = _buildResponsesSpreadsheet(_form!, _responses);
      return; // The build already includes the response
    }

    // New row at end (after header + existing responses)
    // responses already includes the new one, so use its length
    final rowIndex = _responses.length;

    // Ensure the sheet has enough rows
    if (rowIndex >= _responsesSheet!.rows) {
      _responsesSheet!.rows = rowIndex + 10;
    }

    // Column A: Response index number
    _responsesSheet!.setCell(rowIndex, 0, SpreadsheetCell(
      value: rowIndex,
      type: CellType.number,
    ));

    // Column B: Submitted timestamp (YYYY-MM-DD HH:MM:SS)
    _responsesSheet!.setCell(rowIndex, 1, SpreadsheetCell(
      value: _formatTimestamp(response.submittedAt),
      type: CellType.string,
    ));

    // Columns C+: Field values (answers)
    for (int c = 0; c < _form!.fields.length; c++) {
      final field = _form!.fields[c];
      final value = response.responses[field.id];
      _responsesSheet!.setCell(rowIndex, c + 2, _valueToCell(value, field.type));
    }
  }

  /// Format a DateTime as YYYY-MM-DD HH:MM:SS
  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// Convert a form field value to a spreadsheet cell
  SpreadsheetCell _valueToCell(dynamic value, FormFieldType fieldType) {
    if (value == null) {
      return SpreadsheetCell(value: '', type: CellType.string);
    }

    switch (fieldType) {
      case FormFieldType.number:
      case FormFieldType.rating:
      case FormFieldType.scale:
        if (value is num) {
          return SpreadsheetCell(value: value, type: CellType.number);
        }
        final parsed = num.tryParse(value.toString());
        if (parsed != null) {
          return SpreadsheetCell(value: parsed, type: CellType.number);
        }
        return SpreadsheetCell(value: value.toString(), type: CellType.string);

      case FormFieldType.checkbox:
        return SpreadsheetCell(value: value == true, type: CellType.boolean);

      case FormFieldType.checkboxGroup:
      case FormFieldType.selectMultiple:
        if (value is List) {
          return SpreadsheetCell(value: value.join(', '), type: CellType.string);
        }
        return SpreadsheetCell(value: value.toString(), type: CellType.string);

      case FormFieldType.date:
        return SpreadsheetCell(value: value.toString(), type: CellType.date);

      case FormFieldType.time:
      case FormFieldType.datetime:
        return SpreadsheetCell(value: value.toString(), type: CellType.datetime);

      default:
        return SpreadsheetCell(value: value.toString(), type: CellType.string);
    }
  }

  void _showAddFieldMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _i18n.t('add_field'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Recommended section at the top
                      _buildFieldTypeSection(
                        _i18n.t('work_form_recommended'),
                        [
                          _FieldTypeOption(FormFieldType.text, Icons.short_text, _getFieldColor(FormFieldType.text)),
                          _FieldTypeOption(FormFieldType.textarea, Icons.notes, _getFieldColor(FormFieldType.textarea)),
                          _FieldTypeOption(FormFieldType.checkboxGroup, Icons.checklist_rtl, _getFieldColor(FormFieldType.checkboxGroup)),
                          _FieldTypeOption(FormFieldType.rating, Icons.star, _getFieldColor(FormFieldType.rating)),
                          _FieldTypeOption(FormFieldType.checkbox, Icons.check_box, _getFieldColor(FormFieldType.checkbox)),
                        ],
                        isRecommended: true,
                      ),
                      _buildFieldTypeSection(_i18n.t('text_fields'), [
                        _FieldTypeOption(FormFieldType.text, Icons.short_text, _getFieldColor(FormFieldType.text)),
                        _FieldTypeOption(FormFieldType.textarea, Icons.notes, _getFieldColor(FormFieldType.textarea)),
                        _FieldTypeOption(FormFieldType.number, Icons.pin, _getFieldColor(FormFieldType.number)),
                      ]),
                      _buildFieldTypeSection(_i18n.t('choice_fields'), [
                        _FieldTypeOption(FormFieldType.select, Icons.arrow_drop_down_circle, _getFieldColor(FormFieldType.select)),
                        _FieldTypeOption(FormFieldType.selectMultiple, Icons.checklist, _getFieldColor(FormFieldType.selectMultiple)),
                        _FieldTypeOption(FormFieldType.radio, Icons.radio_button_checked, _getFieldColor(FormFieldType.radio)),
                        _FieldTypeOption(FormFieldType.checkbox, Icons.check_box, _getFieldColor(FormFieldType.checkbox)),
                        _FieldTypeOption(FormFieldType.checkboxGroup, Icons.checklist_rtl, _getFieldColor(FormFieldType.checkboxGroup)),
                      ]),
                      _buildFieldTypeSection(_i18n.t('date_time_fields'), [
                        _FieldTypeOption(FormFieldType.date, Icons.calendar_today, _getFieldColor(FormFieldType.date)),
                        _FieldTypeOption(FormFieldType.time, Icons.access_time, _getFieldColor(FormFieldType.time)),
                        _FieldTypeOption(FormFieldType.datetime, Icons.event, _getFieldColor(FormFieldType.datetime)),
                      ]),
                      _buildFieldTypeSection(_i18n.t('special_fields'), [
                        _FieldTypeOption(FormFieldType.rating, Icons.star, _getFieldColor(FormFieldType.rating)),
                        _FieldTypeOption(FormFieldType.scale, Icons.linear_scale, _getFieldColor(FormFieldType.scale)),
                        _FieldTypeOption(FormFieldType.signature, Icons.draw, _getFieldColor(FormFieldType.signature)),
                        _FieldTypeOption(FormFieldType.location, Icons.location_on, _getFieldColor(FormFieldType.location)),
                      ]),
                      _buildFieldTypeSection(_i18n.t('layout'), [
                        _FieldTypeOption(FormFieldType.section, Icons.segment, _getFieldColor(FormFieldType.section)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFieldTypeSection(String title, List<_FieldTypeOption> options, {bool isRecommended = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          color: isRecommended ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isRecommended ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isRecommended ? FontWeight.bold : null,
                ),
              ),
              if (isRecommended) ...[
                const SizedBox(width: 8),
                Icon(Icons.thumb_up, size: 16, color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
        ...options.map((opt) => ListTile(
          leading: CircleAvatar(
            backgroundColor: opt.color.withValues(alpha: 0.15),
            child: Icon(opt.icon, color: opt.color, size: 20),
          ),
          title: Text(_getDefaultLabel(opt.type)),
          subtitle: Text(
            _getFieldDescription(opt.type),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () {
            Navigator.pop(context);
            _addField(opt.type);
          },
        )),
      ],
    );
  }

  Color _getFieldColor(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
      case FormFieldType.textarea:
        return Colors.blue;
      case FormFieldType.number:
        return Colors.indigo;
      case FormFieldType.select:
      case FormFieldType.selectMultiple:
      case FormFieldType.radio:
      case FormFieldType.checkbox:
      case FormFieldType.checkboxGroup:
        return Colors.purple;
      case FormFieldType.date:
      case FormFieldType.time:
      case FormFieldType.datetime:
        return Colors.teal;
      case FormFieldType.rating:
        return Colors.amber;
      case FormFieldType.scale:
        return Colors.orange;
      case FormFieldType.signature:
        return Colors.deepPurple;
      case FormFieldType.section:
        return Colors.grey;
      case FormFieldType.location:
        return Colors.green;
      case FormFieldType.file:
      case FormFieldType.image:
        return Colors.brown;
      case FormFieldType.hidden:
        return Colors.grey;
    }
  }

  IconData _getFieldIcon(FormFieldType type) {
    switch (type) {
      case FormFieldType.text:
        return Icons.short_text;
      case FormFieldType.textarea:
        return Icons.notes;
      case FormFieldType.number:
        return Icons.pin;
      case FormFieldType.select:
        return Icons.arrow_drop_down_circle;
      case FormFieldType.selectMultiple:
        return Icons.checklist;
      case FormFieldType.radio:
        return Icons.radio_button_checked;
      case FormFieldType.checkbox:
        return Icons.check_box;
      case FormFieldType.checkboxGroup:
        return Icons.checklist_rtl;
      case FormFieldType.date:
        return Icons.calendar_today;
      case FormFieldType.time:
        return Icons.access_time;
      case FormFieldType.datetime:
        return Icons.event;
      case FormFieldType.rating:
        return Icons.star;
      case FormFieldType.scale:
        return Icons.linear_scale;
      case FormFieldType.signature:
        return Icons.draw;
      case FormFieldType.section:
        return Icons.segment;
      case FormFieldType.location:
        return Icons.location_on;
      case FormFieldType.file:
        return Icons.attach_file;
      case FormFieldType.image:
        return Icons.image;
      case FormFieldType.hidden:
        return Icons.visibility_off;
    }
  }
}

class _FieldTypeOption {
  final FormFieldType type;
  final IconData icon;
  final Color color;

  _FieldTypeOption(this.type, this.icon, this.color);
}
