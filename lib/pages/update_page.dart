import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/update_settings.dart';
import '../services/update_service.dart';
import '../version.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final UpdateService _updateService = UpdateService();
  ReleaseInfo? _latestRelease;
  List<BackupInfo> _backups = [];
  bool _isLoading = false;
  String? _error;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _latestRelease = _updateService.getLatestRelease();
      _backups = await _updateService.listBackups();
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = 'Checking for updates...';
    });

    try {
      _latestRelease = await _updateService.checkForUpdates();
      if (_latestRelease != null) {
        final isNewer = _updateService.isNewerVersion(
          _updateService.getCurrentVersion(),
          _latestRelease!.version,
        );
        if (isNewer) {
          _statusMessage = 'Update available: ${_latestRelease!.version}';
        } else {
          _statusMessage = 'You are running the latest version';
        }
      } else {
        _statusMessage = 'Could not check for updates';
      }
    } catch (e) {
      _error = e.toString();
      _statusMessage = null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    if (_latestRelease == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Downloading update...';
    });

    try {
      final downloadPath = await _updateService.downloadUpdate(
        _latestRelease!,
        onProgress: (progress) {
          setState(() {
            _statusMessage = 'Downloading: ${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (downloadPath != null) {
        setState(() {
          _statusMessage = 'Applying update...';
        });

        final success = await _updateService.applyUpdate(downloadPath);
        if (success) {
          _statusMessage = 'Update installed! Please restart the application.';
          _backups = await _updateService.listBackups();
        } else {
          _error = 'Failed to apply update';
          _statusMessage = null;
        }
      } else {
        _error = 'Download failed or no binary available for this platform';
        _statusMessage = null;
      }
    } catch (e) {
      _error = e.toString();
      _statusMessage = null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rollback(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Rollback'),
        content: Text(
          'Are you sure you want to rollback to version ${backup.version ?? "unknown"}?\n\n'
          'The application will need to be restarted after the rollback.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Rolling back...';
    });

    try {
      final success = await _updateService.rollback(backup);
      if (success) {
        _statusMessage = 'Rollback complete! Please restart the application.';
      } else {
        _error = 'Rollback failed';
        _statusMessage = null;
      }
    } catch (e) {
      _error = e.toString();
      _statusMessage = null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Backup'),
        content: Text('Are you sure you want to delete "${backup.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _updateService.deleteBackup(backup);
    if (success) {
      setState(() {
        _backups.remove(backup);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup deleted')),
        );
      }
    }
  }

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = _updateService.detectPlatform();
    final settings = _updateService.getSettings();
    final currentVersion = _updateService.getCurrentVersion();
    final hasUpdate = _latestRelease != null &&
        _updateService.isNewerVersion(currentVersion, _latestRelease!.version);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Software Updates'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Version Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Current Version',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('Version', 'v$currentVersion'),
                      _buildInfoRow('Platform', platform.name.toUpperCase()),
                      _buildInfoRow('Binary Type', platform.binaryPattern),
                      if (settings.lastCheckTime != null)
                        _buildInfoRow(
                          'Last Check',
                          _formatDateTime(settings.lastCheckTime!),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Update Status Card
              if (_statusMessage != null || _error != null)
                Card(
                  color: _error != null
                      ? Theme.of(context).colorScheme.errorContainer
                      : hasUpdate
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          _error != null
                              ? Icons.error_outline
                              : hasUpdate
                                  ? Icons.system_update
                                  : Icons.check_circle_outline,
                          color: _error != null
                              ? Theme.of(context).colorScheme.error
                              : hasUpdate
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error ?? _statusMessage ?? '',
                            style: TextStyle(
                              color: _error != null
                                  ? Theme.of(context).colorScheme.onErrorContainer
                                  : Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_statusMessage != null || _error != null) const SizedBox(height: 24),

              // Download Progress
              if (_updateService.isDownloading)
                Column(
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _updateService.downloadProgress,
                      builder: (context, progress, child) {
                        return LinearProgressIndicator(value: progress);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),

              // Latest Release Card
              if (_latestRelease != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              hasUpdate ? Icons.new_releases : Icons.verified,
                              color: hasUpdate
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.green,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              hasUpdate ? 'Update Available' : 'Latest Release',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow('Version', 'v${_latestRelease!.version}'),
                        if (_latestRelease!.name != null)
                          _buildInfoRow('Name', _latestRelease!.name!),
                        if (_latestRelease!.publishedAt != null)
                          _buildInfoRow(
                            'Released',
                            _formatDateString(_latestRelease!.publishedAt!),
                          ),
                        _buildInfoRow(
                          'Available for',
                          _latestRelease!.assets.keys.map((k) => k.toUpperCase()).join(', '),
                        ),
                        if (_latestRelease!.body != null &&
                            _latestRelease!.body!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                            'Release Notes:',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _latestRelease!.body!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (_latestRelease!.htmlUrl != null) ...[
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () => _launchURL(_latestRelease!.htmlUrl!),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('View on GitHub'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _checkForUpdates,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Check for Updates'),
                    ),
                  ),
                  if (hasUpdate && !kIsWeb) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _downloadAndInstall,
                        icon: const Icon(Icons.download),
                        label: const Text('Install Update'),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 32),

              // Backups Section
              if (!kIsWeb) ...[
                Text(
                  'Rollback Backups',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Previous versions are saved automatically before updates.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                if (_backups.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.history,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No backups available',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_backups.length, (index) {
                    final backup = _backups[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text('v${backup.version ?? "unknown"}'),
                        subtitle: Text(
                          '${backup.formattedSize} • ${_formatDateTime(backup.timestamp)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore),
                              tooltip: 'Rollback to this version',
                              onPressed: _isLoading ? null : () => _rollback(backup),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              tooltip: 'Delete backup',
                              onPressed: _isLoading ? null : () => _deleteBackup(backup),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],

              const SizedBox(height: 32),

              // Settings Section
              Text(
                'Update Settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto-check for updates'),
                      subtitle: const Text('Check for updates when app starts'),
                      value: settings.autoCheckUpdates,
                      onChanged: (value) async {
                        await _updateService.updateSettings(
                          settings.copyWith(autoCheckUpdates: value),
                        );
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Update notifications'),
                      subtitle: const Text('Notify when updates are available'),
                      value: settings.notifyOnUpdate,
                      onChanged: (value) async {
                        await _updateService.updateSettings(
                          settings.copyWith(notifyOnUpdate: value),
                        );
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Maximum backups'),
                      subtitle: Text('Keep ${settings.maxBackups} previous versions'),
                      trailing: DropdownButton<int>(
                        value: settings.maxBackups,
                        items: [3, 5, 10, 15, 20]
                            .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (value) async {
                          if (value != null) {
                            await _updateService.updateSettings(
                              settings.copyWith(maxBackups: value),
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateString(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return _formatDateTime(dt);
    } catch (e) {
      return isoDate;
    }
  }
}
