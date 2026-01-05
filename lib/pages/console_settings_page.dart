/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console settings page - Configure session settings (RAM, mounts, network).
 */

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/console_session.dart';
import '../services/i18n_service.dart';

/// Console session settings page
class ConsoleSettingsPage extends StatefulWidget {
  final ConsoleSession session;

  const ConsoleSettingsPage({
    super.key,
    required this.session,
  });

  @override
  State<ConsoleSettingsPage> createState() => _ConsoleSettingsPageState();
}

class _ConsoleSettingsPageState extends State<ConsoleSettingsPage> {
  final I18nService _i18n = I18nService();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  late String _vmType;
  late int _memory;
  late bool _networkEnabled;
  late bool _keepRunning;
  late List<ConsoleMount> _mounts;

  static const List<int> _memoryOptions = [64, 128, 256, 512];
  static const List<String> _vmTypeOptions = [
    'alpine-x86',
    'alpine-riscv64',
    'buildroot-riscv64',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.session.name);
    _descriptionController =
        TextEditingController(text: widget.session.description ?? '');
    _vmType = widget.session.vmType;
    _memory = widget.session.memory;
    _networkEnabled = widget.session.networkEnabled;
    _keepRunning = widget.session.keepRunning;
    _mounts = List.from(widget.session.mounts);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.session.copyWith(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      vmType: _vmType,
      memory: _memory,
      networkEnabled: _networkEnabled,
      keepRunning: _keepRunning,
      mounts: _mounts,
    );
    Navigator.pop(context, updated);
  }

  void _addMount() async {
    final vmPathController = TextEditingController(text: '/mnt/');
    String? hostPath;
    bool readonly = false;

    final result = await showDialog<ConsoleMount>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_i18n.t('add_mount')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // VM Path
              TextField(
                controller: vmPathController,
                decoration: InputDecoration(
                  labelText: _i18n.t('vm_path'),
                  hintText: '/mnt/data',
                ),
              ),
              const SizedBox(height: 16),

              // Host folder
              Text(
                _i18n.t('host_folder'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hostPath ?? _i18n.t('no_folder_selected'),
                      style: TextStyle(
                        color: hostPath != null
                            ? null
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath();
                      if (result != null) {
                        setDialogState(() => hostPath = result);
                      }
                    },
                    child: Text(_i18n.t('browse')),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Read-only toggle
              SwitchListTile(
                title: Text(_i18n.t('readonly')),
                subtitle: Text(_i18n.t('readonly_description')),
                value: readonly,
                onChanged: (value) => setDialogState(() => readonly = value),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_i18n.t('cancel')),
            ),
            TextButton(
              onPressed: hostPath != null &&
                      vmPathController.text.trim().isNotEmpty
                  ? () => Navigator.pop(
                        context,
                        ConsoleMount(
                          hostPath: hostPath!,
                          vmPath: vmPathController.text.trim(),
                          readonly: readonly,
                        ),
                      )
                  : null,
              child: Text(_i18n.t('add')),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() => _mounts.add(result));
    }
  }

  void _editMount(int index) async {
    final mount = _mounts[index];
    final vmPathController = TextEditingController(text: mount.vmPath);
    String hostPath = mount.hostPath;
    bool readonly = mount.readonly;

    final result = await showDialog<ConsoleMount>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_i18n.t('edit_mount')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: vmPathController,
                decoration: InputDecoration(
                  labelText: _i18n.t('vm_path'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _i18n.t('host_folder'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hostPath,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath();
                      if (result != null) {
                        setDialogState(() => hostPath = result);
                      }
                    },
                    child: Text(_i18n.t('browse')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(_i18n.t('readonly')),
                value: readonly,
                onChanged: (value) => setDialogState(() => readonly = value),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_i18n.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                ConsoleMount(
                  hostPath: hostPath,
                  vmPath: vmPathController.text.trim(),
                  readonly: readonly,
                ),
              ),
              child: Text(_i18n.t('save')),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() => _mounts[index] = result);
    }
  }

  void _removeMount(int index) {
    setState(() => _mounts.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('session_settings')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(_i18n.t('save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Session name
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: _i18n.t('session_name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: _i18n.t('description'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // VM Type
          Text(
            _i18n.t('vm_type'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: _vmTypeOptions.map((type) {
              return ButtonSegment(
                value: type,
                label: Text(type.split('-').last.toUpperCase()),
              );
            }).toList(),
            selected: {_vmType},
            onSelectionChanged: (selection) {
              setState(() => _vmType = selection.first);
            },
          ),
          const SizedBox(height: 24),

          // Memory
          Text(
            _i18n.t('memory_ram'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: _memoryOptions.map((mem) {
              return ButtonSegment(
                value: mem,
                label: Text('$mem MB'),
              );
            }).toList(),
            selected: {_memory},
            onSelectionChanged: (selection) {
              setState(() => _memory = selection.first);
            },
          ),
          Text(
            _i18n.t('memory_note'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // Network
          SwitchListTile(
            title: Text(_i18n.t('network')),
            subtitle: Text(_i18n.t('network_description')),
            value: _networkEnabled,
            onChanged: (value) => setState(() => _networkEnabled = value),
          ),
          const Divider(),

          // Keep running
          SwitchListTile(
            title: Text(_i18n.t('keep_running')),
            subtitle: Text(_i18n.t('keep_running_description')),
            value: _keepRunning,
            onChanged: (value) => setState(() => _keepRunning = value),
          ),
          const SizedBox(height: 24),

          // Mounted folders
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _i18n.t('mounted_folders'),
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addMount,
                tooltip: _i18n.t('add_mount'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_mounts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _i18n.t('no_mounts'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._mounts.asMap().entries.map((entry) {
              final index = entry.key;
              final mount = entry.value;
              return Card(
                child: ListTile(
                  leading: Icon(
                    mount.readonly ? Icons.folder_outlined : Icons.folder,
                  ),
                  title: Text(mount.vmPath),
                  subtitle: Text(mount.hostPath),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (mount.readonly)
                        Chip(
                          label: Text(
                            _i18n.t('readonly'),
                            style: const TextStyle(fontSize: 10),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editMount(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _removeMount(index),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
