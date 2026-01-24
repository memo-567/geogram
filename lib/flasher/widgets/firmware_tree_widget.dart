/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/device_definition.dart';

/// Selection callback when a device version is selected
typedef OnFirmwareSelected = void Function(
  DeviceDefinition device,
  FirmwareVersion? version,
);

/// Hierarchical tree view for browsing firmware library
///
/// Shows: Project -> Architecture -> Model -> Version
class FirmwareTreeWidget extends StatefulWidget {
  /// Devices organized by project/architecture
  final Map<String, Map<String, List<DeviceDefinition>>> hierarchy;

  /// Currently selected device
  final DeviceDefinition? selectedDevice;

  /// Currently selected version
  final FirmwareVersion? selectedVersion;

  /// Callback when a firmware is selected
  final OnFirmwareSelected? onSelected;

  /// Whether the tree is loading
  final bool isLoading;

  const FirmwareTreeWidget({
    super.key,
    required this.hierarchy,
    this.selectedDevice,
    this.selectedVersion,
    this.onSelected,
    this.isLoading = false,
  });

  @override
  State<FirmwareTreeWidget> createState() => _FirmwareTreeWidgetState();
}

class _FirmwareTreeWidgetState extends State<FirmwareTreeWidget> {
  final Set<String> _expandedProjects = {};
  final Set<String> _expandedArchitectures = {};
  final Set<String> _expandedDevices = {};

  @override
  void initState() {
    super.initState();
    // Auto-expand if there's a selection
    if (widget.selectedDevice != null) {
      _expandToSelection();
    }
  }

  @override
  void didUpdateWidget(FirmwareTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDevice != oldWidget.selectedDevice &&
        widget.selectedDevice != null) {
      _expandToSelection();
    }
  }

  void _expandToSelection() {
    final device = widget.selectedDevice;
    if (device == null) return;

    final project = device.effectiveProject;
    final arch = device.effectiveArchitecture;
    final model = device.effectiveModel;

    _expandedProjects.add(project);
    _expandedArchitectures.add('$project/$arch');
    _expandedDevices.add('$project/$arch/$model');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.hierarchy.isEmpty) {
      return _buildEmptyState(context);
    }

    final projects = widget.hierarchy.keys.toList()..sort();

    return ListView.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return _buildProjectNode(context, project);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No firmware found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add device definitions to the flasher folder',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectNode(BuildContext context, String project) {
    final theme = Theme.of(context);
    final isExpanded = _expandedProjects.contains(project);
    final architectures = widget.hierarchy[project]?.keys.toList() ?? [];
    architectures.sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project header
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedProjects.remove(project);
              } else {
                _expandedProjects.add(project);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),

        // Architectures
        if (isExpanded)
          ...architectures.map((arch) => _buildArchitectureNode(
                context,
                project,
                arch,
              )),
      ],
    );
  }

  Widget _buildArchitectureNode(
    BuildContext context,
    String project,
    String architecture,
  ) {
    final theme = Theme.of(context);
    final key = '$project/$architecture';
    final isExpanded = _expandedArchitectures.contains(key);
    final devices = widget.hierarchy[project]?[architecture] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Architecture header
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedArchitectures.remove(key);
              } else {
                _expandedArchitectures.add(key);
              }
            });
          },
          child: Padding(
            padding:
                const EdgeInsets.only(left: 24, right: 8, top: 8, bottom: 8),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  color: theme.colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    architecture,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),

        // Devices
        if (isExpanded)
          ...devices.map((device) => _buildDeviceNode(
                context,
                project,
                architecture,
                device,
              )),
      ],
    );
  }

  Widget _buildDeviceNode(
    BuildContext context,
    String project,
    String architecture,
    DeviceDefinition device,
  ) {
    final theme = Theme.of(context);
    final model = device.effectiveModel;
    final key = '$project/$architecture/$model';
    final isExpanded = _expandedDevices.contains(key);
    final isDeviceSelected = widget.selectedDevice?.effectiveModel == model &&
        widget.selectedDevice?.effectiveProject == project &&
        widget.selectedDevice?.effectiveArchitecture == architecture;

    final hasVersions = device.versions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Device header
        InkWell(
          onTap: () {
            if (hasVersions) {
              setState(() {
                if (isExpanded) {
                  _expandedDevices.remove(key);
                } else {
                  _expandedDevices.add(key);
                }
              });
            } else {
              // Select device without version
              widget.onSelected?.call(device, null);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.only(left: 48, right: 8, top: 8, bottom: 8),
            color: isDeviceSelected && widget.selectedVersion == null
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : null,
            child: Row(
              children: [
                Icon(
                  _getDeviceIcon(device),
                  color: theme.colorScheme.tertiary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isDeviceSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (!hasVersions)
                        Text(
                          'Download latest',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasVersions)
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
              ],
            ),
          ),
        ),

        // Versions
        if (isExpanded && hasVersions)
          ...device.versions.map((version) => _buildVersionNode(
                context,
                device,
                version,
              )),
      ],
    );
  }

  Widget _buildVersionNode(
    BuildContext context,
    DeviceDefinition device,
    FirmwareVersion version,
  ) {
    final theme = Theme.of(context);
    final isLatest = device.latestVersion == version.version ||
        (device.latestVersion == null && device.versions.first == version);
    final isSelected = widget.selectedDevice?.effectiveModel ==
            device.effectiveModel &&
        widget.selectedVersion?.version == version.version;

    return InkWell(
      onTap: () {
        widget.onSelected?.call(device, version);
      },
      onLongPress: () {
        _showVersionDetails(context, version);
      },
      child: Container(
        padding: const EdgeInsets.only(left: 72, right: 8, top: 6, bottom: 6),
        color: isSelected
            ? theme.colorScheme.primaryContainer.withOpacity(0.5)
            : null,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              'v${version.version}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'latest',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            if (version.size != null) ...[
              const Spacer(),
              Text(
                _formatSize(version.size!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(DeviceDefinition device) {
    switch (device.effectiveArchitecture.toLowerCase()) {
      case 'esp32':
        return Icons.developer_board;
      case 'quansheng':
      case 'uv-k5':
        return Icons.radio;
      case 'stm32':
        return Icons.memory;
      default:
        return Icons.devices_other;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showVersionDetails(BuildContext context, FirmwareVersion version) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${version.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (version.releaseDate != null) ...[
                _buildDetailRow(
                  context,
                  'Release Date',
                  version.releaseDate!,
                  Icons.calendar_today,
                ),
                const SizedBox(height: 8),
              ],
              if (version.size != null) ...[
                _buildDetailRow(
                  context,
                  'Size',
                  _formatSize(version.size!),
                  Icons.storage,
                ),
                const SizedBox(height: 8),
              ],
              if (version.checksum != null) ...[
                _buildDetailRow(
                  context,
                  'SHA256',
                  version.checksum!.substring(0, 16) + '...',
                  Icons.fingerprint,
                ),
                const SizedBox(height: 8),
              ],
              if (version.releaseNotes != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Release Notes',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  version.releaseNotes!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
