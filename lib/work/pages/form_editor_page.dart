/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/form_content.dart';
import '../services/ndf_service.dart';
import '../widgets/form/form_field_widget.dart';

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
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _error;

  late TabController _tabController;

  // Form preview state
  Map<String, dynamic> _previewValues = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

      // Initialize preview values with defaults
      final previewValues = <String, dynamic>{};
      for (final field in form.fields) {
        previewValues[field.id] = field.defaultValue;
      }

      setState(() {
        _metadata = metadata;
        _form = form;
        _responses = responses;
        _previewValues = previewValues;
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
        return 'Text Question';
      case FormFieldType.textarea:
        return 'Long Text';
      case FormFieldType.number:
        return 'Number';
      case FormFieldType.select:
        return 'Dropdown';
      case FormFieldType.selectMultiple:
        return 'Multi-select';
      case FormFieldType.radio:
        return 'Single Choice';
      case FormFieldType.checkbox:
        return 'Checkbox';
      case FormFieldType.checkboxGroup:
        return 'Multiple Choice';
      case FormFieldType.date:
        return 'Date';
      case FormFieldType.time:
        return 'Time';
      case FormFieldType.datetime:
        return 'Date and Time';
      case FormFieldType.rating:
        return 'Rating';
      case FormFieldType.scale:
        return 'Scale';
      case FormFieldType.signature:
        return 'Signature';
      case FormFieldType.section:
        return 'Section';
      case FormFieldType.location:
        return 'Location';
      case FormFieldType.file:
        return 'File Upload';
      case FormFieldType.image:
        return 'Image Upload';
      case FormFieldType.hidden:
        return 'Hidden';
    }
  }

  void _deleteField(String fieldId) {
    if (_form == null) return;

    setState(() {
      _form!.fields.removeWhere((f) => f.id == fieldId);
      _previewValues.remove(fieldId);
      _hasChanges = true;
    });
  }

  void _editField(NdfFormField field) async {
    final labelController = TextEditingController(text: field.label);
    final descController = TextEditingController(text: field.description ?? '');
    final placeholderController = TextEditingController(text: field.placeholder ?? '');
    var isRequired = field.required;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_i18n.t('edit_field')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  decoration: InputDecoration(
                    labelText: _i18n.t('field_label'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: _i18n.t('description'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: placeholderController,
                  decoration: InputDecoration(
                    labelText: _i18n.t('placeholder'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: isRequired,
                  title: Text(_i18n.t('required')),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setDialogState(() => isRequired = val ?? false),
                ),
              ],
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
        ),
      ),
    );

    if (result == true) {
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
            validation: field.validation,
            options: field.options,
            rows: field.rows,
            step: field.step,
            format: field.format,
            accept: field.accept,
            maxFiles: field.maxFiles,
            maxSizeMb: field.maxSizeMb,
            minRating: field.minRating,
            maxRating: field.maxRating,
            labels: field.labels,
          );
          _hasChanges = true;
        });
      }
    }
  }

  Future<void> _submitPreview() async {
    if (_form == null) return;

    // Validate required fields
    for (final field in _form!.fields) {
      if (field.required && (_previewValues[field.id] == null || _previewValues[field.id].toString().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${field.label} is required')),
        );
        return;
      }
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
        // Reset preview
        _previewValues = {};
        for (final field in _form!.fields) {
          _previewValues[field.id] = field.defaultValue;
        }
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
            Text(_i18n.t('empty_form')),
            const SizedBox(height: 8),
            Text(
              _i18n.t('empty_form_hint'),
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

  Widget _buildDesignFieldCard(NdfFormField field, ThemeData theme, int index) {
    return Card(
      key: ValueKey(field.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(_getFieldIcon(field.type)),
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
                  'Required',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          field.type.name,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editField(field),
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
      return Center(child: Text(_i18n.t('no_fields_to_preview')));
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _form!.fields.length,
            itemBuilder: (context, index) {
              final field = _form!.fields[index];
              return FormFieldWidget(
                field: field,
                value: _previewValues[field.id],
                onChanged: (val) {
                  setState(() {
                    _previewValues[field.id] = val;
                  });
                },
              );
            },
          ),
        ),
        // Submit button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitPreview,
              icon: const Icon(Icons.send),
              label: Text(_i18n.t('submit')),
            ),
          ),
        ),
      ],
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
            Text(_i18n.t('no_responses')),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _responses.length,
      itemBuilder: (context, index) {
        final response = _responses[index];
        return _buildResponseCard(response, theme);
      },
    );
  }

  Widget _buildResponseCard(FormResponse response, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          response.isSigned ? Icons.verified : Icons.description_outlined,
          color: response.isSigned ? Colors.green : null,
        ),
        title: Text('Response ${response.id.substring(0, 8)}'),
        subtitle: Text(
          _formatDateTime(response.submittedAt),
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: response.responses.entries.map((entry) {
                final field = _form?.fields.where((f) => f.id == entry.key).firstOrNull;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field?.label ?? entry.key,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatValue(entry.value),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatValue(dynamic value) {
    if (value == null) return '-';
    if (value is List) return value.join(', ');
    if (value is Map) return value.toString();
    return value.toString();
  }

  void _showAddFieldMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _i18n.t('add_field'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildFieldTypeSection(_i18n.t('text_fields'), [
                      _FieldTypeOption(FormFieldType.text, Icons.short_text),
                      _FieldTypeOption(FormFieldType.textarea, Icons.notes),
                      _FieldTypeOption(FormFieldType.number, Icons.pin),
                    ]),
                    _buildFieldTypeSection(_i18n.t('choice_fields'), [
                      _FieldTypeOption(FormFieldType.select, Icons.arrow_drop_down_circle),
                      _FieldTypeOption(FormFieldType.selectMultiple, Icons.checklist),
                      _FieldTypeOption(FormFieldType.radio, Icons.radio_button_checked),
                      _FieldTypeOption(FormFieldType.checkbox, Icons.check_box),
                      _FieldTypeOption(FormFieldType.checkboxGroup, Icons.checklist_rtl),
                    ]),
                    _buildFieldTypeSection(_i18n.t('date_time_fields'), [
                      _FieldTypeOption(FormFieldType.date, Icons.calendar_today),
                      _FieldTypeOption(FormFieldType.time, Icons.access_time),
                      _FieldTypeOption(FormFieldType.datetime, Icons.event),
                    ]),
                    _buildFieldTypeSection(_i18n.t('special_fields'), [
                      _FieldTypeOption(FormFieldType.rating, Icons.star),
                      _FieldTypeOption(FormFieldType.scale, Icons.linear_scale),
                      _FieldTypeOption(FormFieldType.signature, Icons.draw),
                      _FieldTypeOption(FormFieldType.location, Icons.location_on),
                    ]),
                    _buildFieldTypeSection(_i18n.t('layout'), [
                      _FieldTypeOption(FormFieldType.section, Icons.segment),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldTypeSection(String title, List<_FieldTypeOption> options) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...options.map((opt) => ListTile(
          leading: Icon(opt.icon),
          title: Text(_getDefaultLabel(opt.type)),
          onTap: () {
            Navigator.pop(context);
            _addField(opt.type);
          },
        )),
      ],
    );
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

  _FieldTypeOption(this.type, this.icon);
}
