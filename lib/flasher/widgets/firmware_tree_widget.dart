/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

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

  // Track which items show inline details
  String? _detailDevice; // "project/arch/model"
  String? _detailVersion; // "project/arch/model/version"

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Auto-expand if there's a selection
    if (widget.selectedDevice != null) {
      _expandToSelection();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    // Filter hierarchy based on search query
    final filteredHierarchy = _filterHierarchy();
    final projects = filteredHierarchy.keys.toList()..sort();

    // Auto-select if only one result
    _autoSelectSingleResult(filteredHierarchy);

    return Column(
      children: [
        // Search bar
        _buildSearchBar(context),

        // Tree view
        Expanded(
          child: projects.isEmpty && _searchQuery.isNotEmpty
              ? _buildNoResultsState(context)
              : ListView.builder(
                  itemCount: projects.length,
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    return _buildProjectNode(
                      context,
                      project,
                      filteredHierarchy: filteredHierarchy,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search firmware...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.outline),
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase().trim();
            // Expand all when searching
            if (_searchQuery.isNotEmpty) {
              _expandAll();
            }
          });
        },
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
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
            'Try a different search term',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// Filter hierarchy based on search query
  Map<String, Map<String, List<DeviceDefinition>>> _filterHierarchy() {
    if (_searchQuery.isEmpty) {
      return widget.hierarchy;
    }

    final filtered = <String, Map<String, List<DeviceDefinition>>>{};

    for (final projectEntry in widget.hierarchy.entries) {
      final project = projectEntry.key;
      final architectures = projectEntry.value;

      final filteredArchitectures = <String, List<DeviceDefinition>>{};

      for (final archEntry in architectures.entries) {
        final arch = archEntry.key;
        final devices = archEntry.value;

        final filteredDevices = devices.where((device) {
          return _deviceMatchesSearch(device, project, arch);
        }).toList();

        if (filteredDevices.isNotEmpty) {
          filteredArchitectures[arch] = filteredDevices;
        }
      }

      if (filteredArchitectures.isNotEmpty) {
        filtered[project] = filteredArchitectures;
      }
    }

    return filtered;
  }

  /// Check if a device matches the search query
  bool _deviceMatchesSearch(DeviceDefinition device, String project, String arch) {
    final searchFields = [
      device.title,
      device.description,
      device.chip,
      device.effectiveModel,
      device.effectiveProject,
      device.effectiveArchitecture,
      project,
      arch,
      ...device.versions.map((v) => v.version),
      ...device.versions.map((v) => v.releaseNotes ?? ''),
    ];

    return searchFields.any(
      (field) => field.toLowerCase().contains(_searchQuery),
    );
  }

  /// Expand all nodes when searching
  void _expandAll() {
    for (final project in widget.hierarchy.keys) {
      _expandedProjects.add(project);
      final architectures = widget.hierarchy[project] ?? {};
      for (final arch in architectures.keys) {
        _expandedArchitectures.add('$project/$arch');
        final devices = architectures[arch] ?? [];
        for (final device in devices) {
          _expandedDevices.add('$project/$arch/${device.effectiveModel}');
        }
      }
    }
  }

  /// Auto-select if only one device/version matches
  void _autoSelectSingleResult(
    Map<String, Map<String, List<DeviceDefinition>>> filteredHierarchy,
  ) {
    if (_searchQuery.isEmpty) return;

    // Count total devices
    var totalDevices = 0;
    DeviceDefinition? singleDevice;
    String? singleProject;
    String? singleArch;

    for (final projectEntry in filteredHierarchy.entries) {
      for (final archEntry in projectEntry.value.entries) {
        for (final device in archEntry.value) {
          totalDevices++;
          singleDevice = device;
          singleProject = projectEntry.key;
          singleArch = archEntry.key;
        }
      }
    }

    // If only one device, expand it and show details
    if (totalDevices == 1 && singleDevice != null) {
      final key = '$singleProject/$singleArch/${singleDevice.effectiveModel}';
      _expandedProjects.add(singleProject!);
      _expandedArchitectures.add('$singleProject/$singleArch');
      _expandedDevices.add(key);
      _detailDevice = key;

      // If only one version, auto-select it
      if (singleDevice.versions.length == 1) {
        final version = singleDevice.versions.first;
        // Notify parent to select this device/version
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.selectedDevice != singleDevice ||
              widget.selectedVersion != version) {
            widget.onSelected?.call(singleDevice!, version);
          }
        });
      } else if (singleDevice.versions.isEmpty) {
        // No versions, select device itself
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (widget.selectedDevice != singleDevice) {
            widget.onSelected?.call(singleDevice!, null);
          }
        });
      }
    }
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

  Widget _buildProjectNode(
    BuildContext context,
    String project, {
    required Map<String, Map<String, List<DeviceDefinition>>> filteredHierarchy,
  }) {
    final theme = Theme.of(context);
    final isExpanded = _expandedProjects.contains(project);
    final architectures = filteredHierarchy[project]?.keys.toList() ?? [];
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
                // Auto-expand if only one architecture
                if (architectures.length == 1) {
                  final arch = architectures.first;
                  final archKey = '$project/$arch';
                  _expandedArchitectures.add(archKey);
                  // Auto-expand if only one device
                  final devices = filteredHierarchy[project]?[arch] ?? [];
                  if (devices.length == 1) {
                    final device = devices.first;
                    final deviceKey = '$project/$arch/${device.effectiveModel}';
                    _expandedDevices.add(deviceKey);
                    _detailDevice = deviceKey;
                  }
                }
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
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: project,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: ' (${architectures.length})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
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
                filteredHierarchy: filteredHierarchy,
              )),
      ],
    );
  }

  Widget _buildArchitectureNode(
    BuildContext context,
    String project,
    String architecture, {
    required Map<String, Map<String, List<DeviceDefinition>>> filteredHierarchy,
  }) {
    final theme = Theme.of(context);
    final key = '$project/$architecture';
    final isExpanded = _expandedArchitectures.contains(key);
    final devices = filteredHierarchy[project]?[architecture] ?? [];

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
                // Auto-expand if only one device
                if (devices.length == 1) {
                  final device = devices.first;
                  final deviceKey = '$project/$architecture/${device.effectiveModel}';
                  _expandedDevices.add(deviceKey);
                  _detailDevice = deviceKey;
                }
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
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: architecture,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: ' (${devices.length})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
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
    final showDetails = _detailDevice == key;
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
            setState(() {
              // Toggle details
              if (showDetails) {
                _detailDevice = null;
              } else {
                _detailDevice = key;
                _detailVersion = null;
                // Also expand versions when showing details
                if (hasVersions && !isExpanded) {
                  _expandedDevices.add(key);
                }
              }
            });
          },
          child: Container(
            padding:
                const EdgeInsets.only(left: 48, right: 8, top: 8, bottom: 8),
            color: isDeviceSelected && widget.selectedVersion == null
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : showDetails
                    ? theme.colorScheme.surfaceContainerHighest
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        device.chip,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Info icon to indicate details available
                Icon(
                  showDetails ? Icons.info : Icons.info_outline,
                  size: 16,
                  color: showDetails
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                if (hasVersions) ...[
                  const SizedBox(width: 4),
                  // Separate tap target for expand/collapse
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedDevices.remove(key);
                        } else {
                          _expandedDevices.add(key);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Inline device details
        if (showDetails) _buildDeviceDetails(context, device),

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

  Widget _buildDeviceDetails(BuildContext context, DeviceDefinition device) {
    final theme = Theme.of(context);
    final photoPath = device.photoPath;

    return Container(
      margin: const EdgeInsets.only(left: 48, right: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo and basic info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device photo
              if (photoPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(photoPath),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getDeviceIcon(device),
                        size: 32,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getDeviceIcon(device),
                    size: 32,
                    color: theme.colorScheme.outline,
                  ),
                ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _buildInfoChip(context, Icons.memory, device.chip),
                    const SizedBox(height: 4),
                    _buildInfoChip(
                      context,
                      Icons.architecture,
                      device.effectiveArchitecture,
                    ),
                    if (device.versions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildInfoChip(
                        context,
                        Icons.folder_zip,
                        '${device.versions.length} version${device.versions.length > 1 ? 's' : ''}',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Description
          if (device.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              device.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Flash button for devices without versions
          if (device.versions.isEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => widget.onSelected?.call(device, null),
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('Flash Latest'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildVersionNode(
    BuildContext context,
    DeviceDefinition device,
    FirmwareVersion version,
  ) {
    final theme = Theme.of(context);
    final versionKey =
        '${device.effectiveProject}/${device.effectiveArchitecture}/${device.effectiveModel}/${version.version}';
    final showDetails = _detailVersion == versionKey;
    final isLatest = device.latestVersion == version.version ||
        (device.latestVersion == null && device.versions.first == version);
    final isSelected = widget.selectedDevice?.effectiveModel ==
            device.effectiveModel &&
        widget.selectedVersion?.version == version.version;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              // Toggle version details
              if (showDetails) {
                _detailVersion = null;
              } else {
                _detailVersion = versionKey;
              }
            });
          },
          child: Container(
            padding:
                const EdgeInsets.only(left: 72, right: 8, top: 6, bottom: 6),
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : showDetails
                    ? theme.colorScheme.surfaceContainerHighest
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
                Flexible(
                  child: Text(
                    'v${version.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLatest) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                const Spacer(),
                if (version.size != null)
                  Text(
                    _formatSize(version.size!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  showDetails ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),

        // Inline version details
        if (showDetails) _buildVersionDetails(context, device, version),
      ],
    );
  }

  Widget _buildVersionDetails(
    BuildContext context,
    DeviceDefinition device,
    FirmwareVersion version,
  ) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 72, right: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 250;
          return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version info grid
          Wrap(
            spacing: isNarrow ? 8 : 16,
            runSpacing: 8,
            children: [
              if (version.size != null)
                _buildVersionInfoItem(
                  context,
                  Icons.storage,
                  'Size',
                  _formatSize(version.size!),
                ),
              if (version.releaseDate != null)
                _buildVersionInfoItem(
                  context,
                  Icons.calendar_today,
                  'Released',
                  version.releaseDate!,
                ),
              _buildVersionInfoItem(
                context,
                Icons.architecture,
                'Architecture',
                device.effectiveArchitecture,
              ),
              _buildVersionInfoItem(
                context,
                Icons.memory,
                'Chip',
                device.chip,
              ),
            ],
          ),

          // Checksum
          if (version.checksum != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.fingerprint,
                    size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'SHA256: ${version.checksum!.length > 16 ? '${version.checksum!.substring(0, 16)}...' : version.checksum}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Release notes
          if (version.releaseNotes != null &&
              version.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'Release Notes',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              version.releaseNotes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Flash button
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onSelected?.call(device, version),
              icon: const Icon(Icons.flash_on, size: 18),
              label: Text(
                'Flash v${version.version}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
          );
        },
      ),
    );
  }

  Widget _buildVersionInfoItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
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

}
