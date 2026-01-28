/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Form field types
enum FormFieldType {
  text,
  textarea,
  number,
  select,
  selectMultiple,
  radio,
  checkbox,
  checkboxGroup,
  date,
  time,
  datetime,
  location,
  file,
  image,
  rating,
  scale,
  signature,
  section,
  hidden,
}

/// A select option
class FormOption {
  final String value;
  final String label;

  FormOption({required this.value, required this.label});

  factory FormOption.fromJson(Map<String, dynamic> json) {
    return FormOption(
      value: json['value'] as String,
      label: json['label'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// Field validation rules
class FormValidation {
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final num? min;
  final num? max;
  final bool? integer;
  final int? minSelected;
  final int? maxSelected;

  FormValidation({
    this.minLength,
    this.maxLength,
    this.pattern,
    this.min,
    this.max,
    this.integer,
    this.minSelected,
    this.maxSelected,
  });

  factory FormValidation.fromJson(Map<String, dynamic> json) {
    return FormValidation(
      minLength: json['min_length'] as int?,
      maxLength: json['max_length'] as int?,
      pattern: json['pattern'] as String?,
      min: json['min'] as num?,
      max: json['max'] as num?,
      integer: json['integer'] as bool?,
      minSelected: json['min_selected'] as int?,
      maxSelected: json['max_selected'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (minLength != null) 'min_length': minLength,
    if (maxLength != null) 'max_length': maxLength,
    if (pattern != null) 'pattern': pattern,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (integer != null) 'integer': integer,
    if (minSelected != null) 'min_selected': minSelected,
    if (maxSelected != null) 'max_selected': maxSelected,
  };

  bool get isEmpty =>
      minLength == null &&
      maxLength == null &&
      pattern == null &&
      min == null &&
      max == null &&
      integer == null &&
      minSelected == null &&
      maxSelected == null;
}

/// A form field definition
class NdfFormField {
  final String id;
  final FormFieldType type;
  final String label;
  final bool required;
  final String? placeholder;
  final String? description;
  final dynamic defaultValue;
  final FormValidation? validation;
  final List<FormOption>? options;
  final int? rows;
  final num? step;
  final String? format;
  final List<String>? accept;
  final int? maxFiles;
  final int? maxSizeMb;
  final num? minRating;
  final num? maxRating;
  final Map<String, String>? labels;

  NdfFormField({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.placeholder,
    this.description,
    this.defaultValue,
    this.validation,
    this.options,
    this.rows,
    this.step,
    this.format,
    this.accept,
    this.maxFiles,
    this.maxSizeMb,
    this.minRating,
    this.maxRating,
    this.labels,
  });

  factory NdfFormField.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = FormFieldType.values.firstWhere(
      (t) => t.name == typeStr || _typeAliases[typeStr] == t,
      orElse: () => FormFieldType.text,
    );

    List<FormOption>? options;
    final optionsJson = json['options'] as List<dynamic>?;
    if (optionsJson != null) {
      options = optionsJson
          .map((o) => FormOption.fromJson(o as Map<String, dynamic>))
          .toList();
    }

    FormValidation? validation;
    final validationJson = json['validation'] as Map<String, dynamic>?;
    if (validationJson != null) {
      validation = FormValidation.fromJson(validationJson);
    }

    Map<String, String>? labels;
    final labelsJson = json['labels'] as Map<String, dynamic>?;
    if (labelsJson != null) {
      labels = labelsJson.map((k, v) => MapEntry(k, v as String));
    }

    return NdfFormField(
      id: json['id'] as String,
      type: type,
      label: json['label'] as String,
      required: json['required'] as bool? ?? false,
      placeholder: json['placeholder'] as String?,
      description: json['description'] as String?,
      defaultValue: json['default'],
      validation: validation,
      options: options,
      rows: json['rows'] as int?,
      step: json['step'] as num?,
      format: json['format'] as String?,
      accept: (json['accept'] as List<dynamic>?)?.map((a) => a as String).toList(),
      maxFiles: json['max_files'] as int?,
      maxSizeMb: json['max_size_mb'] as int?,
      minRating: json['min'] as num?,
      maxRating: json['max'] as num?,
      labels: labels,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'label': label,
    if (required) 'required': required,
    if (placeholder != null) 'placeholder': placeholder,
    if (description != null) 'description': description,
    if (defaultValue != null) 'default': defaultValue,
    if (validation != null && !validation!.isEmpty) 'validation': validation!.toJson(),
    if (options != null) 'options': options!.map((o) => o.toJson()).toList(),
    if (rows != null) 'rows': rows,
    if (step != null) 'step': step,
    if (format != null) 'format': format,
    if (accept != null) 'accept': accept,
    if (maxFiles != null) 'max_files': maxFiles,
    if (maxSizeMb != null) 'max_size_mb': maxSizeMb,
    if (minRating != null) 'min': minRating,
    if (maxRating != null) 'max': maxRating,
    if (labels != null) 'labels': labels,
  };

  static const _typeAliases = <String, FormFieldType>{
    'select_multiple': FormFieldType.selectMultiple,
    'checkbox_group': FormFieldType.checkboxGroup,
  };
}

/// Form section for layout
class FormSection {
  final String? title;
  final String? description;
  final List<String> fields;

  FormSection({
    this.title,
    this.description,
    required this.fields,
  });

  factory FormSection.fromJson(Map<String, dynamic> json) {
    return FormSection(
      title: json['title'] as String?,
      description: json['description'] as String?,
      fields: (json['fields'] as List<dynamic>).map((f) => f as String).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    'fields': fields,
  };
}

/// Form layout configuration
class FormLayout {
  final String type;
  final List<FormSection>? sections;

  FormLayout({
    this.type = 'linear',
    this.sections,
  });

  factory FormLayout.fromJson(Map<String, dynamic> json) {
    List<FormSection>? sections;
    final sectionsJson = json['sections'] as List<dynamic>?;
    if (sectionsJson != null) {
      sections = sectionsJson
          .map((s) => FormSection.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return FormLayout(
      type: json['type'] as String? ?? 'linear',
      sections: sections,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (sections != null) 'sections': sections!.map((s) => s.toJson()).toList(),
  };
}

/// Form settings
class FormSettings {
  final bool allowAnonymous;
  final bool requireSignature;
  final bool multipleSubmissions;
  final bool editableAfterSubmit;
  final List<String>? notifyOnSubmit;
  final DateTime? closeAfter;
  final int? maxResponses;

  FormSettings({
    this.allowAnonymous = false,
    this.requireSignature = true,
    this.multipleSubmissions = false,
    this.editableAfterSubmit = false,
    this.notifyOnSubmit,
    this.closeAfter,
    this.maxResponses,
  });

  factory FormSettings.fromJson(Map<String, dynamic> json) {
    return FormSettings(
      allowAnonymous: json['allow_anonymous'] as bool? ?? false,
      requireSignature: json['require_signature'] as bool? ?? true,
      multipleSubmissions: json['multiple_submissions'] as bool? ?? false,
      editableAfterSubmit: json['editable_after_submit'] as bool? ?? false,
      notifyOnSubmit: (json['notify_on_submit'] as List<dynamic>?)
          ?.map((n) => n as String)
          .toList(),
      closeAfter: json['close_after'] != null
          ? DateTime.parse(json['close_after'] as String)
          : null,
      maxResponses: json['max_responses'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'allow_anonymous': allowAnonymous,
    'require_signature': requireSignature,
    'multiple_submissions': multipleSubmissions,
    'editable_after_submit': editableAfterSubmit,
    if (notifyOnSubmit != null) 'notify_on_submit': notifyOnSubmit,
    if (closeAfter != null) 'close_after': closeAfter!.toIso8601String(),
    if (maxResponses != null) 'max_responses': maxResponses,
  };
}

/// Main form content (form definition)
class FormContent {
  final String id;
  final String schema;
  String title;
  String? description;
  int version;
  final DateTime created;
  DateTime modified;
  final FormSettings settings;
  final List<NdfFormField> fields;
  final FormLayout layout;

  FormContent({
    required this.id,
    this.schema = 'ndf-form-1.0',
    required this.title,
    this.description,
    this.version = 1,
    required this.created,
    required this.modified,
    FormSettings? settings,
    required this.fields,
    FormLayout? layout,
  }) : settings = settings ?? FormSettings(),
       layout = layout ?? FormLayout();

  factory FormContent.create({required String title, String? description}) {
    final now = DateTime.now();
    final id = 'form-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return FormContent(
      id: id,
      title: title,
      description: description,
      created: now,
      modified: now,
      fields: [],
    );
  }

  factory FormContent.fromJson(Map<String, dynamic> json) {
    final fieldsJson = json['fields'] as List<dynamic>? ?? [];
    final fields = fieldsJson
        .map((f) => NdfFormField.fromJson(f as Map<String, dynamic>))
        .toList();

    FormSettings? settings;
    final settingsJson = json['settings'] as Map<String, dynamic>?;
    if (settingsJson != null) {
      settings = FormSettings.fromJson(settingsJson);
    }

    FormLayout? layout;
    final layoutJson = json['layout'] as Map<String, dynamic>?;
    if (layoutJson != null) {
      layout = FormLayout.fromJson(layoutJson);
    }

    return FormContent(
      id: json['id'] as String,
      schema: json['schema'] as String? ?? 'ndf-form-1.0',
      title: json['title'] as String,
      description: json['description'] as String?,
      version: json['version'] as int? ?? 1,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
      settings: settings,
      fields: fields,
      layout: layout,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'schema': schema,
    'title': title,
    if (description != null) 'description': description,
    'version': version,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'settings': settings.toJson(),
    'fields': fields.map((f) => f.toJson()).toList(),
    'layout': layout.toJson(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Get field by ID
  NdfFormField? getField(String id) {
    return fields.where((f) => f.id == id).firstOrNull;
  }

  /// Add a field
  void addField(NdfFormField field) {
    fields.add(field);
    modified = DateTime.now();
    version++;
  }

  /// Remove a field
  void removeField(String id) {
    fields.removeWhere((f) => f.id == id);
    modified = DateTime.now();
    version++;
  }
}

/// Location value in form response
class LocationValue {
  final double lat;
  final double lng;
  final double? accuracy;
  final double? altitude;

  LocationValue({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.altitude,
  });

  factory LocationValue.fromJson(Map<String, dynamic> json) {
    return LocationValue(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (accuracy != null) 'accuracy': accuracy,
    if (altitude != null) 'altitude': altitude,
  };
}

/// File attachment in form response
class FileAttachment {
  final String asset;
  final int? size;

  FileAttachment({required this.asset, this.size});

  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    return FileAttachment(
      asset: json['asset'] as String,
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'asset': asset,
    if (size != null) 'size': size,
  };
}

/// Form response signature
class ResponseSignature {
  final String npub;
  final int createdAt;
  final int kind;
  final String sig;

  ResponseSignature({
    required this.npub,
    required this.createdAt,
    required this.kind,
    required this.sig,
  });

  factory ResponseSignature.fromJson(Map<String, dynamic> json) {
    return ResponseSignature(
      npub: json['npub'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      sig: json['sig'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'npub': npub,
    'created_at': createdAt,
    'kind': kind,
    'sig': sig,
  };
}

/// Form response
class FormResponse {
  final String id;
  final String formId;
  final int formVersion;
  final DateTime submittedAt;
  final Map<String, dynamic> responses;
  final Map<String, dynamic>? metadata;
  final ResponseSignature? signature;

  FormResponse({
    required this.id,
    required this.formId,
    required this.formVersion,
    required this.submittedAt,
    required this.responses,
    this.metadata,
    this.signature,
  });

  factory FormResponse.create({
    required String formId,
    required int formVersion,
    required Map<String, dynamic> responses,
  }) {
    final now = DateTime.now();
    final id = 'resp-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return FormResponse(
      id: id,
      formId: formId,
      formVersion: formVersion,
      submittedAt: now,
      responses: responses,
    );
  }

  factory FormResponse.fromJson(Map<String, dynamic> json) {
    ResponseSignature? signature;
    final sigJson = json['signature'] as Map<String, dynamic>?;
    if (sigJson != null) {
      signature = ResponseSignature.fromJson(sigJson);
    }

    return FormResponse(
      id: json['id'] as String,
      formId: json['form_id'] as String,
      formVersion: json['form_version'] as int,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      responses: json['responses'] as Map<String, dynamic>,
      metadata: json['metadata'] as Map<String, dynamic>?,
      signature: signature,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'form_id': formId,
    'form_version': formVersion,
    'submitted_at': submittedAt.toIso8601String(),
    'responses': responses,
    if (metadata != null) 'metadata': metadata,
    if (signature != null) 'signature': signature!.toJson(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Get response value for a field
  dynamic getResponse(String fieldId) => responses[fieldId];

  /// Check if response has a signature
  bool get isSigned => signature != null;
}
