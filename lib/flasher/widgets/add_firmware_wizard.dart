/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../models/device_definition.dart';
import '../protocols/protocol_registry.dart';

/// Wizard for adding new firmware to the library
///
/// Follows the hierarchy: Project -> Architecture -> Model -> Version
class AddFirmwareWizard extends StatefulWidget {
  final String basePath;
  final Map<String, Map<String, List<DeviceDefinition>>> hierarchy;
  final VoidCallback? onComplete;

  const AddFirmwareWizard({
    super.key,
    required this.basePath,
    required this.hierarchy,
    this.onComplete,
  });

  @override
  State<AddFirmwareWizard> createState() => _AddFirmwareWizardState();
}

class _AddFirmwareWizardState extends State<AddFirmwareWizard> {
  int _currentStep = 0;

  // Step 1: Project
  String? _selectedProject;
  final _newProjectController = TextEditingController();
  bool _isNewProject = false;

  // Step 2: Architecture
  String? _selectedArchitecture;
  final _newArchitectureController = TextEditingController();
  bool _isNewArchitecture = false;

  // Step 3: Model
  String? _selectedModel;
  final _newModelController = TextEditingController();
  bool _isNewModel = false;
  final _modelTitleController = TextEditingController();
  final _modelDescriptionController = TextEditingController();
  final _modelChipController = TextEditingController();
  String? _modelPhotoPath;
  String _selectedProtocol = 'esptool';

  // Step 4: Version
  final _versionController = TextEditingController();
  final _releaseNotesController = TextEditingController();
  String? _firmwarePath;
  int? _firmwareSize;
  bool _useUrl = false;
  final _firmwareUrlController = TextEditingController();

  // Focus nodes for Enter key navigation
  final _modelTitleFocus = FocusNode();
  final _modelChipFocus = FocusNode();
  final _modelDescriptionFocus = FocusNode();
  final _firmwareUrlFocus = FocusNode();
  final _releaseNotesFocus = FocusNode();

  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _newProjectController.dispose();
    _newArchitectureController.dispose();
    _newModelController.dispose();
    _modelTitleController.dispose();
    _modelDescriptionController.dispose();
    _modelChipController.dispose();
    _versionController.dispose();
    _releaseNotesController.dispose();
    _firmwareUrlController.dispose();
    _modelTitleFocus.dispose();
    _modelChipFocus.dispose();
    _modelDescriptionFocus.dispose();
    _firmwareUrlFocus.dispose();
    _releaseNotesFocus.dispose();
    super.dispose();
  }

  void _tryNextStep() {
    if (_canProceed && !_isSaving) {
      _nextStep();
    }
  }

  List<String> get _projects => widget.hierarchy.keys.toList()..sort();

  List<String> get _architectures {
    if (_selectedProject == null) return [];
    return widget.hierarchy[_selectedProject]?.keys.toList() ?? []
      ..sort();
  }

  List<String> get _models {
    if (_selectedProject == null || _selectedArchitecture == null) return [];
    final devices =
        widget.hierarchy[_selectedProject]?[_selectedArchitecture] ?? [];
    return devices.map((d) => d.effectiveModel).toList()..sort();
  }

  String get _effectiveProject =>
      _isNewProject ? _newProjectController.text.trim() : _selectedProject ?? '';

  String get _effectiveArchitecture => _isNewArchitecture
      ? _newArchitectureController.text.trim()
      : _selectedArchitecture ?? '';

  String get _effectiveModel =>
      _isNewModel ? _newModelController.text.trim() : _selectedModel ?? '';

  bool get _canProceed {
    switch (_currentStep) {
      case 0: // Project
        return _effectiveProject.isNotEmpty;
      case 1: // Architecture
        return _effectiveArchitecture.isNotEmpty;
      case 2: // Model
        if (_effectiveModel.isEmpty) return false;
        if (_isNewModel) {
          return _modelTitleController.text.trim().isNotEmpty &&
              _modelChipController.text.trim().isNotEmpty;
        }
        return true;
      case 3: // Version
        if (_versionController.text.trim().isEmpty) return false;
        if (_useUrl) {
          final url = _firmwareUrlController.text.trim();
          return url.isNotEmpty &&
              (url.startsWith('http://') || url.startsWith('https://'));
        }
        return _firmwarePath != null;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
        // Reset subsequent selections when moving forward
        if (_currentStep == 1) {
          _selectedArchitecture = null;
          _isNewArchitecture = false;
        } else if (_currentStep == 2) {
          _selectedModel = null;
          _isNewModel = false;
        }
      });
    } else {
      _save();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _pickFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        final file = File(path);
        final stat = await file.stat();
        setState(() {
          _firmwarePath = path;
          _firmwareSize = stat.size;
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        setState(() {
          _modelPhotoPath = path;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final project = _effectiveProject;
      final architecture = _effectiveArchitecture;
      final model = _effectiveModel;
      final version = _versionController.text.trim();

      // Create directory structure
      final modelDir =
          Directory('${widget.basePath}/$project/$architecture/$model');
      final versionDir = Directory('${modelDir.path}/$version');

      await versionDir.create(recursive: true);

      // Create or update device.json if new model
      if (_isNewModel) {
        final deviceFile = File('${modelDir.path}/device.json');
        final now = DateTime.now().toIso8601String();

        // Copy photo if provided
        String? photoFilename;
        if (_modelPhotoPath != null) {
          final mediaDir = Directory('${modelDir.path}/media');
          await mediaDir.create(recursive: true);

          final sourcePhoto = File(_modelPhotoPath!);
          final ext = _modelPhotoPath!.split('.').last.toLowerCase();
          photoFilename = 'device.$ext';
          final destPhoto = File('${mediaDir.path}/$photoFilename');
          await sourcePhoto.copy(destPhoto.path);
        }

        final deviceJson = {
          'project': project,
          'architecture': architecture,
          'model': model,
          'id': model,
          'family': architecture,
          'chip': _modelChipController.text.trim(),
          'title': _modelTitleController.text.trim(),
          'description': _modelDescriptionController.text.trim(),
          if (photoFilename != null)
            'media': {
              'photo': photoFilename,
            },
          'flash': {
            'protocol': _selectedProtocol,
            'baud_rate': 921600,
          },
          'created_at': now,
          'modified_at': now,
          'versions': [],
        };
        await deviceFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(deviceJson),
        );
      }

      // Copy or download firmware file
      int? firmwareSize = _firmwareSize;
      final destFile = File('${versionDir.path}/firmware.bin');

      if (_useUrl && _firmwareUrlController.text.trim().isNotEmpty) {
        // Download from URL
        final url = _firmwareUrlController.text.trim();
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download firmware: HTTP ${response.statusCode}');
        }
        await destFile.writeAsBytes(response.bodyBytes);
        firmwareSize = response.bodyBytes.length;
      } else if (_firmwarePath != null) {
        // Copy local file
        final sourceFile = File(_firmwarePath!);
        await sourceFile.copy(destFile.path);
      }

      // Create version.json
      final versionJson = {
        'version': version,
        'release_date': DateTime.now().toIso8601String().split('T').first,
        if (firmwareSize != null) 'size': firmwareSize,
        if (_releaseNotesController.text.trim().isNotEmpty)
          'release_notes': _releaseNotesController.text.trim(),
      };
      final versionFile = File('${versionDir.path}/version.json');
      await versionFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(versionJson),
      );

      // Update device.json versions list
      final deviceFile = File('${modelDir.path}/device.json');
      if (await deviceFile.exists()) {
        final content = await deviceFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final versions = (json['versions'] as List<dynamic>?) ?? [];
        versions.insert(0, {
          'version': version,
          'release_date': DateTime.now().toIso8601String().split('T').first,
          if (firmwareSize != null) 'size': firmwareSize,
          if (_releaseNotesController.text.trim().isNotEmpty)
            'release_notes': _releaseNotesController.text.trim(),
        });
        json['versions'] = versions;
        json['latest_version'] = version;
        json['modified_at'] = DateTime.now().toIso8601String();
        await deviceFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
        );
      }

      if (mounted) {
        widget.onComplete?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Firmware'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Stepper indicator
          _buildStepIndicator(theme),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildStepContent(theme),
            ),
          ),

          // Error message
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(Icons.error, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),

          // Navigation buttons
          _buildNavigationButtons(theme),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    final steps = ['Project', 'Arch', 'Model', 'Version'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Expanded(
            child: Row(
              children: [
                // Connector line (before)
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isCompleted || isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withOpacity(0.3),
                    ),
                  ),

                // Step circle with label
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? theme.colorScheme.primary
                            : isCompleted
                                ? theme.colorScheme.primary.withOpacity(0.7)
                                : theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: isActive || isCompleted
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: theme.colorScheme.onPrimary,
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isActive
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.outline,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[index],
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),

                // Connector line (after, for last item only to balance)
                if (index == steps.length - 1)
                  const SizedBox(width: 0),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildProjectStep(theme);
      case 1:
        return _buildArchitectureStep(theme);
      case 2:
        return _buildModelStep(theme);
      case 3:
        return _buildVersionStep(theme);
      default:
        return const SizedBox();
    }
  }

  Widget _buildProjectStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select or create a project',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Projects group related firmware (e.g., "geogram", "quansheng")',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 24),

        // Existing projects
        if (_projects.isNotEmpty) ...[
          Text(
            'Existing Projects',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _projects.map((project) {
              final isSelected = !_isNewProject && _selectedProject == project;
              return ChoiceChip(
                label: Text(project),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _isNewProject = false;
                    _selectedProject = selected ? project : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // New project option
        CheckboxListTile(
          title: const Text('Create new project'),
          value: _isNewProject,
          onChanged: (value) {
            setState(() {
              _isNewProject = value ?? false;
              if (_isNewProject) {
                _selectedProject = null;
              }
            });
          },
        ),

        if (_isNewProject) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _newProjectController,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'e.g., geogram',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _tryNextStep(),
          ),
        ],
      ],
    );
  }

  Widget _buildArchitectureStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select or create an architecture',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Architecture represents the chip family (e.g., "esp32", "stm32")',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Project: $_effectiveProject',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),

        // Existing architectures
        if (_architectures.isNotEmpty && !_isNewProject) ...[
          Text(
            'Existing Architectures',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _architectures.map((arch) {
              final isSelected =
                  !_isNewArchitecture && _selectedArchitecture == arch;
              return ChoiceChip(
                label: Text(arch),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _isNewArchitecture = false;
                    _selectedArchitecture = selected ? arch : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // New architecture option
        CheckboxListTile(
          title: const Text('Create new architecture'),
          value: _isNewArchitecture,
          onChanged: (value) {
            setState(() {
              _isNewArchitecture = value ?? false;
              if (_isNewArchitecture) {
                _selectedArchitecture = null;
              }
            });
          },
        ),

        if (_isNewArchitecture) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _newArchitectureController,
            decoration: const InputDecoration(
              labelText: 'Architecture name',
              hintText: 'e.g., esp32',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _tryNextStep(),
          ),
        ],
      ],
    );
  }

  Widget _buildModelStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select or create a model',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Model represents the specific device/board (e.g., "esp32-c3-mini")',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Path: $_effectiveProject / $_effectiveArchitecture',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),

        // Existing models
        if (_models.isNotEmpty && !_isNewProject && !_isNewArchitecture) ...[
          Text(
            'Existing Models',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _models.map((model) {
              final isSelected = !_isNewModel && _selectedModel == model;
              return ChoiceChip(
                label: Text(model),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _isNewModel = false;
                    _selectedModel = selected ? model : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // New model option
        CheckboxListTile(
          title: const Text('Create new model'),
          value: _isNewModel,
          onChanged: (value) {
            setState(() {
              _isNewModel = value ?? false;
              if (_isNewModel) {
                _selectedModel = null;
              }
            });
          },
        ),

        if (_isNewModel) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _newModelController,
            decoration: const InputDecoration(
              labelText: 'Model ID *',
              hintText: 'e.g., esp32-c3-mini',
              helperText: 'Used as folder name (no spaces)',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _modelTitleFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelTitleController,
            focusNode: _modelTitleFocus,
            decoration: const InputDecoration(
              labelText: 'Title *',
              hintText: 'e.g., ESP32-C3 Mini',
              helperText: 'Human-readable name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _modelChipFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelChipController,
            focusNode: _modelChipFocus,
            decoration: const InputDecoration(
              labelText: 'Chip *',
              hintText: 'e.g., ESP32-C3',
              helperText: 'Main chip/MCU name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _modelDescriptionFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelDescriptionController,
            focusNode: _modelDescriptionFocus,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Brief description of the device',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _tryNextStep(),
          ),
          const SizedBox(height: 16),

          // Device photo
          Text(
            'Device Photo',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_modelPhotoPath != null) ...[
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_modelPhotoPath!),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _modelPhotoPath!.split(Platform.pathSeparator).last,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _modelPhotoPath = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Select image'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Flash protocol selector
          Text(
            'Flash Protocol *',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedProtocol,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: 'Protocol used to flash firmware',
            ),
            items: ProtocolRegistry.getAllProtocolInfo()
                .map((info) => DropdownMenuItem(
                      value: info['id'],
                      child: Text(info['name'] ?? info['id']!),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedProtocol = value ?? 'esptool'),
          ),
        ],
      ],
    );
  }

  Widget _buildVersionStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add firmware version',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Path: $_effectiveProject / $_effectiveArchitecture / $_effectiveModel',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),

        // Version number
        TextField(
          controller: _versionController,
          decoration: const InputDecoration(
            labelText: 'Version *',
            hintText: 'e.g., 1.0.0',
            helperText: 'Semantic version number',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_useUrl) {
              _firmwareUrlFocus.requestFocus();
            } else {
              _releaseNotesFocus.requestFocus();
            }
          },
        ),
        const SizedBox(height: 16),

        // Firmware source toggle
        Text(
          'Firmware Source *',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.folder_open),
              label: Text('Local File'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.link),
              label: Text('URL'),
            ),
          ],
          selected: {_useUrl},
          onSelectionChanged: (selected) {
            setState(() {
              _useUrl = selected.first;
            });
          },
        ),
        const SizedBox(height: 12),

        // Firmware input based on selection
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _useUrl ? _buildUrlInput(theme) : _buildFileInput(theme),
          ),
        ),
        const SizedBox(height: 16),

        // Release notes
        TextField(
          controller: _releaseNotesController,
          focusNode: _releaseNotesFocus,
          decoration: const InputDecoration(
            labelText: 'Release Notes',
            hintText: 'What changed in this version?',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _tryNextStep(),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Back button
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _isSaving ? null : _previousStep,
              child: const Text('Back'),
            )
          else
            const SizedBox(width: 80),

          const Spacer(),

          // Next/Save button
          FilledButton(
            onPressed: _canProceed && !_isSaving ? _nextStep : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_currentStep == 3 ? 'Save' : 'Next'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildFileInput(ThemeData theme) {
    if (_firmwarePath != null) {
      return Row(
        children: [
          const Icon(Icons.file_present, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _firmwarePath!.split(Platform.pathSeparator).last,
                  style: theme.textTheme.bodyMedium,
                ),
                if (_firmwareSize != null)
                  Text(
                    _formatSize(_firmwareSize!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _firmwarePath = null;
                _firmwareSize = null;
              });
            },
          ),
        ],
      );
    }

    return Center(
      child: OutlinedButton.icon(
        onPressed: _pickFirmware,
        icon: const Icon(Icons.upload_file),
        label: const Text('Select firmware.bin'),
      ),
    );
  }

  Widget _buildUrlInput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _firmwareUrlController,
          focusNode: _firmwareUrlFocus,
          decoration: const InputDecoration(
            labelText: 'Firmware URL',
            hintText: 'https://example.com/firmware.bin',
            helperText: 'Direct link to firmware binary',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _releaseNotesFocus.requestFocus(),
        ),
        const SizedBox(height: 8),
        Text(
          'The firmware will be downloaded when you save.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
