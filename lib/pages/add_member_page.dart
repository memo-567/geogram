/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/chat_channel.dart';
import '../services/chat_service.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';

/// Full-screen page for adding members to a restricted chat room.
/// Shows list of known devices organized by folders and allows manual npub entry.
class AddMemberPage extends StatefulWidget {
  final ChatChannel channel;
  final String userNpub;
  final ChatChannelConfig config;

  const AddMemberPage({
    Key? key,
    required this.channel,
    required this.userNpub,
    required this.config,
  }) : super(key: key);

  @override
  State<AddMemberPage> createState() => _AddMemberPageState();
}

class _AddMemberPageState extends State<AddMemberPage> {
  final ChatService _chatService = ChatService();
  final DevicesService _devicesService = DevicesService();
  final I18nService _i18n = I18nService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualNpubController = TextEditingController();

  /// All available devices organized by folder
  Map<String, List<RemoteDevice>> _devicesByFolder = {};

  /// Folders in display order
  List<DeviceFolder> _folders = [];

  /// Filtered devices when searching
  List<RemoteDevice> _searchResults = [];

  /// Selected npubs for batch adding
  final Set<String> _selectedNpubs = {};

  /// Set of existing members (to filter out)
  late Set<String> _existingMembers;

  bool _isLoading = false;
  bool _showManualEntry = false;
  String? _manualNpubError;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _existingMembers = <String>{
      if (widget.config.owner != null) widget.config.owner!,
      ...widget.config.admins,
      ...widget.config.moderatorNpubs,
      ...widget.config.members,
      ...widget.config.banned,
    };
    _loadDevices();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualNpubController.dispose();
    super.dispose();
  }

  void _loadDevices() {
    // Get all folders
    _folders = _devicesService.getFolders();

    // Organize devices by folder, filtering to those with npubs and not already members
    _devicesByFolder = {};

    for (final folder in _folders) {
      final devicesInFolder = _devicesService.getDevicesInFolder(folder.id)
          .where((device) {
            // Must have an npub to be added as a member
            if (device.npub == null || device.npub!.isEmpty) return false;
            // Must not already be a member/admin/moderator/owner/banned
            if (_existingMembers.contains(device.npub)) return false;
            return true;
          })
          .toList();

      if (devicesInFolder.isNotEmpty) {
        _devicesByFolder[folder.id] = devicesInFolder;
      }
    }

    setState(() {});
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      if (_isSearching) {
        // Search across all devices in all folders
        _searchResults = [];
        for (final devices in _devicesByFolder.values) {
          for (final device in devices) {
            if (device.callsign.toLowerCase().contains(query) ||
                (device.nickname?.toLowerCase().contains(query) ?? false) ||
                (device.npub?.toLowerCase().contains(query) ?? false)) {
              _searchResults.add(device);
            }
          }
        }
      }
    });
  }

  void _toggleSelection(String npub) {
    setState(() {
      if (_selectedNpubs.contains(npub)) {
        _selectedNpubs.remove(npub);
      } else {
        _selectedNpubs.add(npub);
      }
    });
  }

  void _toggleFolderSelection(String folderId) {
    final devicesInFolder = _devicesByFolder[folderId] ?? [];
    final folderNpubs = devicesInFolder
        .where((d) => d.npub != null)
        .map((d) => d.npub!)
        .toSet();

    // Check if all devices in folder are selected
    final allSelected = folderNpubs.every((npub) => _selectedNpubs.contains(npub));

    setState(() {
      if (allSelected) {
        // Deselect all in folder
        _selectedNpubs.removeAll(folderNpubs);
      } else {
        // Select all in folder
        _selectedNpubs.addAll(folderNpubs);
      }
    });
  }

  bool _isFolderFullySelected(String folderId) {
    final devicesInFolder = _devicesByFolder[folderId] ?? [];
    if (devicesInFolder.isEmpty) return false;

    return devicesInFolder
        .where((d) => d.npub != null)
        .every((d) => _selectedNpubs.contains(d.npub));
  }

  bool _isFolderPartiallySelected(String folderId) {
    final devicesInFolder = _devicesByFolder[folderId] ?? [];
    if (devicesInFolder.isEmpty) return false;

    final selectedCount = devicesInFolder
        .where((d) => d.npub != null && _selectedNpubs.contains(d.npub))
        .length;

    return selectedCount > 0 && selectedCount < devicesInFolder.length;
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedNpubs.isEmpty) return;

    setState(() => _isLoading = true);

    int added = 0;
    int failed = 0;

    for (final npub in _selectedNpubs) {
      try {
        await _chatService.addMember(widget.channel.id, widget.userNpub, npub);
        added++;
      } catch (e) {
        failed++;
      }
    }

    setState(() => _isLoading = false);

    if (mounted) {
      if (failed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_i18n.t('members_added', params: [added.toString()])),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $added, failed $failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      Navigator.pop(context, true); // Return true to indicate changes were made
    }
  }

  void _validateManualNpub(String value) {
    setState(() {
      if (value.isEmpty) {
        _manualNpubError = null;
      } else if (!value.startsWith('npub1')) {
        _manualNpubError = _i18n.t('invalid_npub_format');
      } else if (value.length < 60) {
        _manualNpubError = _i18n.t('npub_too_short');
      } else {
        _manualNpubError = null;
      }
    });
  }

  Future<void> _addManualNpub() async {
    final npub = _manualNpubController.text.trim();
    if (npub.isEmpty || _manualNpubError != null) return;

    if (_existingMembers.contains(npub)) {
      setState(() {
        _manualNpubError = _i18n.t('already_a_member');
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _chatService.addMember(widget.channel.id, widget.userNpub, npub);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_i18n.t('member_added')),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _manualNpubError = e.toString();
      });
    }
  }

  int get _totalDeviceCount {
    int count = 0;
    for (final devices in _devicesByFolder.values) {
      count += devices.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('add_member')),
        actions: [
          if (_selectedNpubs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _addSelectedMembers,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(_i18n.t('add_count', params: [_selectedNpubs.length.toString()])),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _i18n.t('search_devices'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
          ),

          // Manual npub entry toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: () {
                setState(() {
                  _showManualEntry = !_showManualEntry;
                  if (!_showManualEntry) {
                    _manualNpubController.clear();
                    _manualNpubError = null;
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _showManualEntry
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 20,
                      color: _showManualEntry
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _i18n.t('add_by_npub'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _showManualEntry
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showManualEntry ? Icons.expand_less : Icons.expand_more,
                      color: _showManualEntry
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Manual npub entry panel
          if (_showManualEntry)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _manualNpubController,
                    decoration: InputDecoration(
                      labelText: _i18n.t('nostr_public_key_npub'),
                      hintText: 'npub1...',
                      errorText: _manualNpubError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    maxLines: 2,
                    onChanged: _validateManualNpub,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _manualNpubController.text.isNotEmpty &&
                            _manualNpubError == null &&
                            !_isLoading
                        ? _addManualNpub
                        : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(_i18n.t('add_member')),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Device list header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.devices,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  _i18n.t('known_devices'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_totalDeviceCount',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Device list (organized by folders or search results)
          Expanded(
            child: _totalDeviceCount == 0
                ? _buildEmptyState(theme)
                : _isSearching
                    ? _buildSearchResults(theme)
                    : _buildFolderList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _i18n.t('no_devices_with_npub'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t('use_manual_npub_entry'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _i18n.t('no_devices_found'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildDeviceTile(theme, _searchResults[index]);
      },
    );
  }

  Widget _buildFolderList(ThemeData theme) {
    // Only show folders that have devices
    final foldersWithDevices = _folders
        .where((f) => _devicesByFolder.containsKey(f.id))
        .toList();

    return ListView.builder(
      itemCount: foldersWithDevices.length,
      itemBuilder: (context, index) {
        final folder = foldersWithDevices[index];
        final devices = _devicesByFolder[folder.id] ?? [];
        return _buildFolderSection(theme, folder, devices);
      },
    );
  }

  Widget _buildFolderSection(ThemeData theme, DeviceFolder folder, List<RemoteDevice> devices) {
    final isFullySelected = _isFolderFullySelected(folder.id);
    final isPartiallySelected = _isFolderPartiallySelected(folder.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder header with select all checkbox
        InkWell(
          onTap: () => _toggleFolderSelection(folder.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    folder.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${devices.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isFullySelected,
                  tristate: true,
                  onChanged: (_) => _toggleFolderSelection(folder.id),
                  // Show indeterminate state if partially selected
                  isError: false,
                ),
              ],
            ),
          ),
        ),
        // Devices in folder
        ...devices.map((device) => _buildDeviceTile(theme, device)),
      ],
    );
  }

  Widget _buildDeviceTile(ThemeData theme, RemoteDevice device) {
    final isSelected = _selectedNpubs.contains(device.npub);

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: device.isOnline
                ? Colors.green.withOpacity(0.1)
                : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              _getDeviceIcon(device),
              color: device.isOnline
                  ? Colors.green
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (isSelected)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: 12,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(
            device.displayName,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (device.isOnline) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _i18n.t('online'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (device.nickname != null && device.nickname != device.callsign)
            Text(
              device.callsign,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Text(
            _truncateNpub(device.npub ?? ''),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
      trailing: Checkbox(
        value: isSelected,
        onChanged: device.npub != null
            ? (value) => _toggleSelection(device.npub!)
            : null,
      ),
      onTap: device.npub != null ? () => _toggleSelection(device.npub!) : null,
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
    );
  }

  IconData _getDeviceIcon(RemoteDevice device) {
    final platform = device.platform?.toLowerCase() ?? '';

    // Check for embedded platforms first
    if (platform == 'esp32' ||
        platform == 'esp8266' ||
        platform == 'arduino' ||
        platform == 'embedded') {
      return Icons.settings_input_antenna;
    }

    // Check if station (callsign starts with X3)
    if (device.callsign.startsWith('X3')) {
      return Icons.cell_tower;
    }

    // Desktop platforms
    if (platform == 'linux' || platform == 'macos' || platform == 'windows') {
      return Icons.laptop;
    }

    // Mobile platforms (default)
    return Icons.smartphone;
  }

  String _truncateNpub(String npub) {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}...${npub.substring(npub.length - 8)}';
  }
}
