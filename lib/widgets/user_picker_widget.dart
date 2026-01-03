/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';

/// Result of user selection
class UserPickerResult {
  final String callsign;
  final String npub;
  final String? displayName;

  UserPickerResult({
    required this.callsign,
    required this.npub,
    this.displayName,
  });
}

/// A reusable widget for selecting a user from known devices.
/// Shows users organized by folders with search functionality.
class UserPickerWidget extends StatefulWidget {
  final I18nService i18n;
  final String? excludeNpub; // Exclude this user (e.g., current user)

  const UserPickerWidget({
    super.key,
    required this.i18n,
    this.excludeNpub,
  });

  @override
  State<UserPickerWidget> createState() => _UserPickerWidgetState();
}

class _UserPickerWidgetState extends State<UserPickerWidget> {
  final DevicesService _devicesService = DevicesService();
  final TextEditingController _searchController = TextEditingController();

  Map<String, List<RemoteDevice>> _devicesByFolder = {};
  List<DeviceFolder> _folders = [];
  List<RemoteDevice> _searchResults = [];
  bool _isSearching = false;
  Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadDevices() {
    _folders = _devicesService.getFolders();
    _devicesByFolder = {};

    for (final folder in _folders) {
      final devicesInFolder = _devicesService.getDevicesInFolder(folder.id)
          .where((device) {
            // Must have an npub
            if (device.npub == null || device.npub!.isEmpty) return false;
            // Exclude specified user
            if (widget.excludeNpub != null && device.npub == widget.excludeNpub) {
              return false;
            }
            return true;
          })
          .toList();

      if (devicesInFolder.isNotEmpty) {
        _devicesByFolder[folder.id] = devicesInFolder;
      }
    }

    // Auto-expand first folder if only one has devices
    if (_devicesByFolder.length == 1) {
      _expandedFolders.add(_devicesByFolder.keys.first);
    }

    setState(() {});
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    // Search across all folders
    final results = <RemoteDevice>[];
    for (final devices in _devicesByFolder.values) {
      for (final device in devices) {
        final matchesCallsign = device.callsign.toLowerCase().contains(query);
        final matchesName = device.displayName?.toLowerCase().contains(query) ?? false;
        final matchesNpub = device.npub?.toLowerCase().contains(query) ?? false;

        if (matchesCallsign || matchesName || matchesNpub) {
          results.add(device);
        }
      }
    }

    setState(() {
      _isSearching = true;
      _searchResults = results;
    });
  }

  void _selectDevice(RemoteDevice device) {
    if (device.npub == null) return;

    Navigator.pop(
      context,
      UserPickerResult(
        callsign: device.callsign,
        npub: device.npub!,
        displayName: device.displayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDevices = _devicesByFolder.values.fold<int>(
      0,
      (sum, devices) => sum + devices.length,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title and search
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_search, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      widget.i18n.t('wallet_select_user'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.i18n.t('search'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: totalDevices == 0
                ? _buildEmptyState(theme)
                : _isSearching
                    ? _buildSearchResults(theme, scrollController)
                    : _buildFolderList(theme, scrollController),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            widget.i18n.t('wallet_no_users_found'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.i18n.t('wallet_no_users_found_hint'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme, ScrollController controller) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('no_results'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildDeviceTile(_searchResults[index], theme);
      },
    );
  }

  Widget _buildFolderList(ThemeData theme, ScrollController controller) {
    final foldersWithDevices = _folders
        .where((f) => _devicesByFolder.containsKey(f.id))
        .toList();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: foldersWithDevices.length,
      itemBuilder: (context, index) {
        final folder = foldersWithDevices[index];
        final devices = _devicesByFolder[folder.id] ?? [];
        final isExpanded = _expandedFolders.contains(folder.id);

        return Column(
          children: [
            // Folder header
            ListTile(
              leading: Icon(
                isExpanded ? Icons.folder_open : Icons.folder,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                folder.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${devices.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedFolders.remove(folder.id);
                  } else {
                    _expandedFolders.add(folder.id);
                  }
                });
              },
            ),
            // Devices in folder
            if (isExpanded)
              ...devices.map((device) => _buildDeviceTile(device, theme)),
            if (index < foldersWithDevices.length - 1)
              const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildDeviceTile(RemoteDevice device, ThemeData theme) {
    final hasNpub = device.npub != null && device.npub!.isNotEmpty;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: hasNpub
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Text(
          device.callsign.isNotEmpty
              ? device.callsign[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: hasNpub
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(device.displayName ?? device.callsign),
      subtitle: Text(
        device.callsign,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: hasNpub
          ? Icon(Icons.chevron_right, color: theme.colorScheme.primary)
          : Icon(Icons.block, color: theme.colorScheme.error),
      enabled: hasNpub,
      onTap: hasNpub ? () => _selectDevice(device) : null,
    );
  }
}
