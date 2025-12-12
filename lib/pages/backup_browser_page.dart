/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/backup_service.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';
import '../models/backup_models.dart';

/// Backup management page with wizard-style role selection.
/// Users can choose to be a Backup User (client) or Backup Provider (host).
class BackupBrowserPage extends StatefulWidget {
  const BackupBrowserPage({super.key});

  @override
  State<BackupBrowserPage> createState() => _BackupBrowserPageState();
}

class _BackupBrowserPageState extends State<BackupBrowserPage> {
  final BackupService _backupService = BackupService();
  final DevicesService _devicesService = DevicesService();
  final I18nService _i18n = I18nService();

  // Current view state
  _BackupViewState _viewState = _BackupViewState.roleSelection;

  // Provider state
  BackupProviderSettings? _providerSettings;
  List<BackupClientRelationship> _clients = [];

  // Client state
  List<BackupProviderRelationship> _providers = [];
  BackupStatus? _backupStatus;

  // Loading state
  bool _isLoading = true;

  // Stream subscriptions
  StreamSubscription<BackupStatus>? _statusSubscription;
  StreamSubscription<List<BackupProviderRelationship>>? _providersSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupSubscriptions();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _providersSubscription?.cancel();
    super.dispose();
  }

  void _setupSubscriptions() {
    _statusSubscription = _backupService.statusStream.listen((status) {
      if (mounted) {
        setState(() => _backupStatus = status);
      }
    });

    _providersSubscription = _backupService.providersStream.listen((providers) {
      if (mounted) {
        setState(() => _providers = providers);
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Ensure service is initialized
      await _backupService.initialize();

      // Load provider settings (sync getters)
      _providerSettings = _backupService.providerSettings;
      _clients = _backupService.getClients();

      // Load client state (sync getters)
      _providers = _backupService.getProviders();
      _backupStatus = _backupService.backupStatus;

      // Determine initial view state based on existing configuration
      _determineViewState();
    } catch (e) {
      // Handle error
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _determineViewState() {
    // If provider mode is enabled, show provider view
    if (_providerSettings?.enabled == true) {
      _viewState = _BackupViewState.providerDashboard;
    }
    // If has providers configured, show client view
    else if (_providers.isNotEmpty) {
      _viewState = _BackupViewState.clientDashboard;
    }
    // Otherwise show role selection wizard
    else {
      _viewState = _BackupViewState.roleSelection;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('backup_app')),
        actions: [
          if (_viewState != _BackupViewState.roleSelection)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsMenu,
              tooltip: _i18n.t('settings'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_viewState) {
      case _BackupViewState.roleSelection:
        return _buildRoleSelectionWizard();
      case _BackupViewState.clientDashboard:
        return _buildClientDashboard();
      case _BackupViewState.providerDashboard:
        return _buildProviderDashboard();
      case _BackupViewState.selectProvider:
        return _buildProviderSelectionPage();
    }
  }

  // ============================================================
  // ROLE SELECTION WIZARD
  // ============================================================

  Widget _buildRoleSelectionWizard() {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.backup,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _i18n.t('backup_setup_title'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _i18n.t('backup_setup_description'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Backup User option
              _buildRoleCard(
                icon: Icons.cloud_upload,
                title: _i18n.t('backup_role_user'),
                description: _i18n.t('backup_role_user_description'),
                onTap: () => setState(() => _viewState = _BackupViewState.selectProvider),
              ),

              const SizedBox(height: 16),

              // Backup Provider option
              _buildRoleCard(
                icon: Icons.cloud_download,
                title: _i18n.t('backup_role_provider'),
                description: _i18n.t('backup_role_provider_description'),
                onTap: _enableProviderMode,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PROVIDER SELECTION (Contact picker)
  // ============================================================

  Widget _buildProviderSelectionPage() {
    final theme = Theme.of(context);
    final folders = _devicesService.getFolders();
    final devicesByFolder = <String, List<RemoteDevice>>{};

    // Organize devices by folder, filtering to those with npubs
    for (final folder in folders) {
      final devicesInFolder = _devicesService.getDevicesInFolder(folder.id)
          .where((device) => device.npub != null && device.npub!.isNotEmpty)
          .toList();
      if (devicesInFolder.isNotEmpty) {
        devicesByFolder[folder.id] = devicesInFolder;
      }
    }

    // Also include devices that are already providers (to show pending status)
    final existingProviderNpubs = _providers.map((p) => p.providerNpub).toSet();

    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _viewState = _BackupViewState.roleSelection),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _i18n.t('backup_select_provider'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _i18n.t('backup_select_provider_hint'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Contact list
        Expanded(
          child: devicesByFolder.isEmpty
              ? _buildNoContactsState(theme)
              : ListView.builder(
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final devices = devicesByFolder[folder.id];
                    if (devices == null || devices.isEmpty) return const SizedBox.shrink();

                    return _buildFolderSection(theme, folder, devices, existingProviderNpubs);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNoContactsState(ThemeData theme) {
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
              _i18n.t('backup_no_contacts'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t('backup_no_contacts_hint'),
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

  Widget _buildFolderSection(
    ThemeData theme,
    DeviceFolder folder,
    List<RemoteDevice> devices,
    Set<String> existingProviderNpubs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder header
        Container(
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
            ],
          ),
        ),
        // Devices in folder
        ...devices.map((device) => _buildContactTile(theme, device, existingProviderNpubs)),
      ],
    );
  }

  Widget _buildContactTile(
    ThemeData theme,
    RemoteDevice device,
    Set<String> existingProviderNpubs,
  ) {
    final isPending = existingProviderNpubs.contains(device.npub);
    final existingProvider = isPending
        ? _providers.firstWhere(
            (p) => p.providerNpub == device.npub,
            orElse: () => BackupProviderRelationship(
              providerNpub: device.npub!,
              providerCallsign: device.callsign,
              backupIntervalDays: 1,
              status: BackupRelationshipStatus.pending,
              createdAt: DateTime.now(),
            ),
          )
        : null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: device.isOnline
            ? Colors.green.withOpacity(0.1)
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          _getDeviceIcon(device),
          color: device.isOnline ? Colors.green : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: [
          Text(device.displayName),
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
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.green),
              ),
            ),
          ],
        ],
      ),
      subtitle: isPending
          ? Text(
              _i18n.t('backup_status_${existingProvider?.status.name ?? 'pending'}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _getStatusColor(existingProvider?.status),
              ),
            )
          : Text(
              device.callsign,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: isPending
          ? _buildStatusChip(theme, existingProvider?.status)
          : FilledButton.tonal(
              onPressed: () => _requestBackupProvider(device),
              child: Text(_i18n.t('backup_request')),
            ),
      onTap: isPending ? null : () => _requestBackupProvider(device),
    );
  }

  Widget _buildStatusChip(ThemeData theme, BackupRelationshipStatus? status) {
    Color color;
    IconData icon;

    switch (status) {
      case BackupRelationshipStatus.pending:
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case BackupRelationshipStatus.active:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case BackupRelationshipStatus.declined:
        color = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        color = theme.colorScheme.onSurfaceVariant;
        icon = Icons.help_outline;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        _i18n.t('backup_status_${status?.name ?? 'unknown'}'),
        style: TextStyle(color: color, fontSize: 12),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Color _getStatusColor(BackupRelationshipStatus? status) {
    switch (status) {
      case BackupRelationshipStatus.pending:
        return Colors.orange;
      case BackupRelationshipStatus.active:
        return Colors.green;
      case BackupRelationshipStatus.declined:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getDeviceIcon(RemoteDevice device) {
    final platform = device.platform?.toLowerCase() ?? '';
    if (platform == 'esp32' || platform == 'esp8266' || platform == 'arduino' || platform == 'embedded') {
      return Icons.settings_input_antenna;
    }
    if (device.callsign.startsWith('X3')) {
      return Icons.cell_tower;
    }
    if (platform == 'linux' || platform == 'macos' || platform == 'windows') {
      return Icons.laptop;
    }
    return Icons.smartphone;
  }

  Future<void> _requestBackupProvider(RemoteDevice device) async {
    try {
      await _backupService.sendInvite(device.callsign, 1); // Default 1 day interval
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('backup_request_sent'))),
        );
        setState(() => _viewState = _BackupViewState.clientDashboard);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // ============================================================
  // CLIENT DASHBOARD
  // ============================================================

  Widget _buildClientDashboard() {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Backup status card
          if (_backupStatus != null && _backupStatus!.status != 'idle')
            _buildBackupProgressCard(theme),

          // Providers section
          Text(
            _i18n.t('backup_providers'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_providers.isEmpty)
            _buildEmptyProvidersCard(theme)
          else
            ..._providers.map((provider) => _buildProviderCard(theme, provider)),

          const SizedBox(height: 24),

          // Add provider button
          OutlinedButton.icon(
            onPressed: () => setState(() => _viewState = _BackupViewState.selectProvider),
            icon: const Icon(Icons.add),
            label: Text(_i18n.t('backup_add_provider')),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupProgressCard(ThemeData theme) {
    final status = _backupStatus!;
    final isBackingUp = status.status == 'in_progress';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBackingUp ? Icons.cloud_upload : Icons.cloud_done,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isBackingUp
                        ? _i18n.t('backup_in_progress')
                        : _i18n.t('backup_complete'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (isBackingUp) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: status.progressPercent / 100),
              const SizedBox(height: 8),
              Text(
                '${status.filesTransferred}/${status.filesTotal} ${_i18n.t('files')} - ${status.progressPercent}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyProvidersCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _i18n.t('backup_no_providers'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t('backup_no_providers_hint'),
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

  Widget _buildProviderCard(ThemeData theme, BackupProviderRelationship provider) {
    final isActive = provider.status == BackupRelationshipStatus.active;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isActive ? Colors.green.withOpacity(0.1) : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.cloud,
                    color: isActive ? Colors.green : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.providerCallsign,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _i18n.t('backup_status_${provider.status.name}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _getStatusColor(provider.status),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(theme, provider.status),
              ],
            ),
            if (isActive && provider.lastSuccessfulBackup != null) ...[
              const SizedBox(height: 12),
              Text(
                '${_i18n.t('backup_last_backup')}: ${_formatDate(provider.lastSuccessfulBackup!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isActive)
                  FilledButton.icon(
                    onPressed: () => _startBackup(provider),
                    icon: const Icon(Icons.backup, size: 18),
                    label: Text(_i18n.t('backup_now')),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeProvider(provider),
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PROVIDER DASHBOARD
  // ============================================================

  Widget _buildProviderDashboard() {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Provider status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cloud_done, color: Colors.green, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _i18n.t('backup_provider_enabled'),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _i18n.t('backup_provider_accepting'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _providerSettings?.enabled ?? false,
                    onChanged: (value) => _toggleProviderMode(value),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Clients section
          Text(
            _i18n.t('backup_clients'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_clients.isEmpty)
            _buildNoClientsCard(theme)
          else
            ..._clients.map((client) => _buildClientCard(theme, client)),
        ],
      ),
    );
  }

  Widget _buildNoClientsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _i18n.t('backup_no_clients'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t('backup_no_clients_hint'),
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

  Widget _buildClientCard(ThemeData theme, BackupClientRelationship client) {
    final isPending = client.status == BackupRelationshipStatus.pending;
    final isActive = client.status == BackupRelationshipStatus.active;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isActive ? Colors.green.withOpacity(0.1) : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    color: isActive ? Colors.green : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.clientCallsign,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isPending
                            ? _i18n.t('backup_pending_request')
                            : '${_formatBytes(client.currentStorageBytes)} / ${_formatBytes(client.maxStorageBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isPending ? Colors.orange : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(theme, client.status),
              ],
            ),
            if (isPending) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _declineClient(client),
                    child: Text(_i18n.t('decline')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => _acceptClient(client),
                    child: Text(_i18n.t('accept')),
                  ),
                ],
              ),
            ] else ...[
              if (client.lastBackupAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_i18n.t('backup_last_backup')}: ${_formatDate(client.lastBackupAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeClient(client),
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _enableProviderMode() async {
    try {
      await _backupService.enableProviderMode(
        maxTotalStorageBytes: 10 * 1024 * 1024 * 1024, // 10 GB default
        defaultMaxClientStorageBytes: 1024 * 1024 * 1024, // 1 GB per client
        defaultMaxSnapshots: 10,
      );
      await _loadData();
      if (mounted) {
        setState(() => _viewState = _BackupViewState.providerDashboard);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleProviderMode(bool enabled) async {
    try {
      if (enabled) {
        await _backupService.enableProviderMode(
          maxTotalStorageBytes: 10 * 1024 * 1024 * 1024,
          defaultMaxClientStorageBytes: 1024 * 1024 * 1024,
          defaultMaxSnapshots: 10,
        );
      } else {
        await _backupService.disableProviderMode();
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _startBackup(BackupProviderRelationship provider) async {
    try {
      await _backupService.startBackup(provider.providerCallsign);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('backup_started'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _removeProvider(BackupProviderRelationship provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('backup_remove_provider_title')),
        content: Text(_i18n.t('backup_remove_provider_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_i18n.t('remove')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _backupService.removeProvider(provider.providerCallsign);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _acceptClient(BackupClientRelationship client) async {
    try {
      await _backupService.acceptInvite(
        client.clientNpub,
        client.clientCallsign,
        _providerSettings?.defaultMaxClientStorageBytes ?? 1024 * 1024 * 1024,
        _providerSettings?.defaultMaxSnapshots ?? 10,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('backup_client_accepted'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _declineClient(BackupClientRelationship client) async {
    try {
      await _backupService.declineInvite(client.clientNpub, client.clientCallsign);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('backup_client_declined'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _removeClient(BackupClientRelationship client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('backup_remove_client_title')),
        content: Text(_i18n.t('backup_remove_client_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_i18n.t('remove')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _backupService.removeClient(client.clientCallsign);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(_i18n.t('backup_switch_role')),
              onTap: () {
                Navigator.pop(context);
                setState(() => _viewState = _BackupViewState.roleSelection);
              },
            ),
            if (_viewState == _BackupViewState.providerDashboard)
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(_i18n.t('backup_provider_settings')),
                onTap: () {
                  Navigator.pop(context);
                  _showProviderSettingsDialog();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showProviderSettingsDialog() {
    final maxStorageController = TextEditingController(
      text: ((_providerSettings?.maxTotalStorageBytes ?? 10737418240) / (1024 * 1024 * 1024)).toStringAsFixed(0),
    );
    final maxClientStorageController = TextEditingController(
      text: ((_providerSettings?.defaultMaxClientStorageBytes ?? 1073741824) / (1024 * 1024 * 1024)).toStringAsFixed(0),
    );
    final maxSnapshotsController = TextEditingController(
      text: (_providerSettings?.defaultMaxSnapshots ?? 10).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('backup_provider_settings')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: maxStorageController,
              decoration: InputDecoration(
                labelText: _i18n.t('backup_max_storage_gb'),
                suffixText: 'GB',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: maxClientStorageController,
              decoration: InputDecoration(
                labelText: _i18n.t('backup_max_client_storage_gb'),
                suffixText: 'GB',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: maxSnapshotsController,
              decoration: InputDecoration(
                labelText: _i18n.t('backup_max_snapshots'),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final maxStorage = (double.tryParse(maxStorageController.text) ?? 10) * 1024 * 1024 * 1024;
              final maxClientStorage = (double.tryParse(maxClientStorageController.text) ?? 1) * 1024 * 1024 * 1024;
              final maxSnapshots = int.tryParse(maxSnapshotsController.text) ?? 10;

              await _backupService.updateProviderSettings(
                maxTotalStorageBytes: maxStorage.toInt(),
                defaultMaxClientStorageBytes: maxClientStorage.toInt(),
                defaultMaxSnapshots: maxSnapshots,
              );
              await _loadData();
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(_i18n.t('save')),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

enum _BackupViewState {
  roleSelection,
  clientDashboard,
  providerDashboard,
  selectProvider,
}
