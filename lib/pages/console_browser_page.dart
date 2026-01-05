/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console browser page - Lists and manages console sessions.
 */

import 'package:flutter/material.dart';
import '../models/console_session.dart';
import '../services/console_service.dart';
import '../services/console_vm_manager.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import 'console_view_page.dart';
import 'console_settings_page.dart';

/// Console browser page
class ConsoleBrowserPage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;

  const ConsoleBrowserPage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
  });

  @override
  State<ConsoleBrowserPage> createState() => _ConsoleBrowserPageState();
}

class _ConsoleBrowserPageState extends State<ConsoleBrowserPage> {
  final ConsoleService _consoleService = ConsoleService();
  final ConsoleVmManager _vmManager = ConsoleVmManager();
  final I18nService _i18n = I18nService();

  ConsoleSession? _selectedSession;
  bool _isLoading = true;
  bool _vmReady = false;
  bool _isDownloading = false;
  String _statusMessage = '';
  double _vmDownloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _statusMessage = _i18n.t('initializing') != 'initializing'
          ? _i18n.t('initializing')
          : 'Initializing...';
    });

    try {
      // Initialize collection
      await _consoleService.initializeCollection(widget.collectionPath);
      await _vmManager.initialize();

      // Check if we have any sessions, auto-create "Session 1" if empty
      if (_consoleService.sessions.isEmpty) {
        if (mounted) {
          setState(() => _statusMessage = 'Creating default session...');
        }
        final session = await _consoleService.createSession(name: 'Session 1');
        if (mounted) {
          setState(() => _selectedSession = session);
        }
        LogService().log('Console: Auto-created Session 1');
      }

      // Check if VM files are ready
      final filesExist = await _checkVmFilesExist();

      if (mounted) {
        setState(() => _isLoading = false);
      }

      if (filesExist) {
        // Files exist - mark ready and auto-launch
        _vmReady = true;
        final sessions = _consoleService.sessions;
        if (sessions.isNotEmpty && mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (mounted) {
            _openSession(sessions.first);
          }
        }
      } else {
        // Files don't exist - start download (which will auto-launch on success)
        await _downloadVmFiles(autoLaunch: true);
      }
    } catch (e) {
      LogService().log('Console: Error initializing: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  /// Check if VM files exist without triggering download
  Future<bool> _checkVmFilesExist() async {
    for (final filename in ConsoleVmManager.requiredFiles) {
      if (!await _vmManager.isFileDownloaded(filename)) {
        return false;
      }
    }
    return true;
  }

  /// Download VM files with progress tracking
  Future<void> _downloadVmFiles({bool autoLaunch = true}) async {
    if (_isDownloading) return; // Prevent double downloads

    LogService().log('Console: Starting VM files download...');

    if (mounted) {
      setState(() {
        _isDownloading = true;
        _statusMessage = 'Connecting to station server...';
        _vmDownloadProgress = 0.0;
      });
    }

    // Listen to download progress
    final subscription = _vmManager.downloadStateChanges.listen((filename) {
      if (mounted) {
        final progress = _vmManager.getDownloadProgress(filename);
        setState(() {
          _vmDownloadProgress = progress;
          if (_vmManager.isDownloading(filename)) {
            _statusMessage = 'Downloading $filename... ${(progress * 100).toInt()}%';
          }
        });
      }
    });

    try {
      final success = await _vmManager.downloadVmFiles();
      LogService().log('Console: Download result: $success');

      if (mounted) {
        setState(() {
          _vmReady = success;
          _isDownloading = false;
          _statusMessage = '';
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('VM files downloaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Auto-launch first session after successful download
          if (autoLaunch) {
            final sessions = _consoleService.sessions;
            if (sessions.isNotEmpty) {
              await Future.delayed(const Duration(milliseconds: 200));
              if (mounted) {
                _openSession(sessions.first);
              }
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to download VM files. Check your internet connection.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _downloadVmFiles(autoLaunch: autoLaunch),
              ),
            ),
          );
        }
      }
    } catch (e) {
      LogService().log('Console: Download error: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      subscription.cancel();
    }
  }

  Future<void> _createSession() async {
    final nameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('new_session')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: _i18n.t('session_name'),
            hintText: _i18n.t('session_name_hint'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(_i18n.t('create')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final session = await _consoleService.createSession(name: result);
        if (mounted) {
          setState(() {
            _selectedSession = session;
          });
        }
      } catch (e) {
        LogService().log('Console: Error creating session: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('error_creating_session'))),
          );
        }
      }
    }
  }

  Future<void> _deleteSession(ConsoleSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('delete_session')),
        content: Text(_i18n.t('delete_session_confirm', params: [session.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _consoleService.deleteSession(session.id);
        if (mounted) {
          setState(() {
            if (_selectedSession?.id == session.id) {
              _selectedSession = null;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('session_deleted'))),
          );
        }
      } catch (e) {
        LogService().log('Console: Error deleting session: $e');
      }
    }
  }

  void _openSession(ConsoleSession session) {
    if (!_vmReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('vm_files_not_ready'))),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsoleViewPage(session: session),
      ),
    );
  }

  void _openSettings(ConsoleSession session) async {
    final result = await Navigator.push<ConsoleSession>(
      context,
      MaterialPageRoute(
        builder: (context) => ConsoleSettingsPage(session: session),
      ),
    );

    if (result != null && mounted) {
      await _consoleService.updateSession(result);
      setState(() {
        if (_selectedSession?.id == result.id) {
          _selectedSession = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collectionTitle),
        actions: [
          // Show download button or progress
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            )
          else if (!_vmReady && !_isLoading)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: _i18n.t('download_vm_files'),
              onPressed: () => _downloadVmFiles(autoLaunch: true),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createSession,
        tooltip: _i18n.t('new_session'),
        child: const Icon(Icons.add),
      ),
      body: _isLoading || _isDownloading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isDownloading) ...[
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        value: _vmDownloadProgress > 0 ? _vmDownloadProgress : null,
                      ),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _statusMessage,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : isWide
              ? _buildWideLayout(theme)
              : _buildNarrowLayout(theme),
    );
  }

  Widget _buildWideLayout(ThemeData theme) {
    return Row(
      children: [
        // Session list
        SizedBox(
          width: 300,
          child: _buildSessionList(theme),
        ),
        const VerticalDivider(width: 1),
        // Session detail
        Expanded(
          child: _selectedSession != null
              ? _buildSessionDetail(theme, _selectedSession!)
              : _buildEmptyState(theme),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(ThemeData theme) {
    return _buildSessionList(theme);
  }

  Widget _buildSessionList(ThemeData theme) {
    final sessions = _consoleService.sessions;

    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _i18n.t('no_sessions'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t('create_session_hint'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isSelected = _selectedSession?.id == session.id;

        return ListTile(
          selected: isSelected,
          leading: _buildSessionIcon(session, theme),
          title: Text(session.name),
          subtitle: Text(
            '${session.vmType} - ${session.memory} MB',
            style: theme.textTheme.bodySmall,
          ),
          trailing: session.keepRunning
              ? Icon(
                  Icons.autorenew,
                  size: 16,
                  color: theme.colorScheme.primary,
                )
              : null,
          onTap: () {
            final isWide = MediaQuery.of(context).size.width > 600;
            if (isWide) {
              setState(() => _selectedSession = session);
            } else {
              _openSession(session);
            }
          },
          onLongPress: () => _showSessionMenu(session),
        );
      },
    );
  }

  Widget _buildSessionIcon(ConsoleSession session, ThemeData theme) {
    IconData icon;
    Color color;

    switch (session.state) {
      case ConsoleSessionState.running:
        icon = Icons.play_circle_filled;
        color = Colors.green;
        break;
      case ConsoleSessionState.suspended:
        icon = Icons.pause_circle_filled;
        color = Colors.orange;
        break;
      case ConsoleSessionState.stopped:
      default:
        icon = Icons.terminal;
        color = theme.colorScheme.onSurface.withOpacity(0.5);
    }

    return Icon(icon, color: color);
  }

  Widget _buildSessionDetail(ThemeData theme, ConsoleSession session) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              _buildSessionIcon(session, theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      _i18n.t('created_at', params: [session.displayCreated]),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Info cards
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildInfoChip(
                theme,
                Icons.memory,
                '${session.memory} MB',
                _i18n.t('memory'),
              ),
              _buildInfoChip(
                theme,
                Icons.computer,
                session.vmType,
                _i18n.t('vm_type'),
              ),
              _buildInfoChip(
                theme,
                session.networkEnabled ? Icons.wifi : Icons.wifi_off,
                session.networkEnabled
                    ? _i18n.t('network_enabled')
                    : _i18n.t('network_disabled'),
                _i18n.t('network'),
              ),
              if (session.keepRunning)
                _buildInfoChip(
                  theme,
                  Icons.autorenew,
                  _i18n.t('keep_running'),
                  _i18n.t('auto_start'),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Mounts
          if (session.mounts.isNotEmpty) ...[
            Text(
              _i18n.t('mounted_folders'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...session.mounts.map((mount) => ListTile(
                  dense: true,
                  leading: Icon(
                    mount.readonly ? Icons.folder_outlined : Icons.folder,
                    size: 20,
                  ),
                  title: Text(mount.vmPath),
                  subtitle: Text(mount.hostPath),
                  trailing: mount.readonly
                      ? Text(
                          _i18n.t('readonly'),
                          style: theme.textTheme.bodySmall,
                        )
                      : null,
                )),
            const SizedBox(height: 16),
          ],

          // Description
          if (session.description != null &&
              session.description!.isNotEmpty) ...[
            Text(
              _i18n.t('description'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(session.description!),
            const SizedBox(height: 16),
          ],

          const Spacer(),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openSettings(session),
                icon: const Icon(Icons.settings),
                label: Text(_i18n.t('settings')),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _vmReady ? () => _openSession(session) : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_i18n.t('launch')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app,
            size: 48,
            color: theme.colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _i18n.t('select_session'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionMenu(ConsoleSession session) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(_i18n.t('launch')),
              onTap: () {
                Navigator.pop(context);
                _openSession(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(_i18n.t('settings')),
              onTap: () {
                Navigator.pop(context);
                _openSettings(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(_i18n.t('delete')),
              onTap: () {
                Navigator.pop(context);
                _deleteSession(session);
              },
            ),
          ],
        ),
      ),
    );
  }
}
