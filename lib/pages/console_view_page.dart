/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console view page - Full-screen WebView running TinyEMU Alpine Linux VM.
 */

import 'package:flutter/material.dart';
import '../models/console_session.dart';
import '../services/console_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../widgets/console_webview.dart';

/// Full-screen console view page
class ConsoleViewPage extends StatefulWidget {
  final ConsoleSession session;

  const ConsoleViewPage({
    super.key,
    required this.session,
  });

  @override
  State<ConsoleViewPage> createState() => _ConsoleViewPageState();
}

class _ConsoleViewPageState extends State<ConsoleViewPage> {
  final ConsoleService _consoleService = ConsoleService();
  final I18nService _i18n = I18nService();

  late ConsoleSession _session;
  final GlobalKey<ConsoleWebViewState> _webViewKey = GlobalKey();
  bool _isReady = false;
  bool _showToolbar = true;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _updateSessionState(ConsoleSessionState.running);
  }

  @override
  void dispose() {
    _saveCurrentState();
    _updateSessionState(ConsoleSessionState.suspended);
    super.dispose();
  }

  Future<void> _updateSessionState(ConsoleSessionState state) async {
    _session = _session.copyWith(state: state);
    await _consoleService.updateSession(_session);
  }

  Future<void> _saveCurrentState() async {
    // Save VM state via WebView
    _webViewKey.currentState?.saveState();
    LogService().log('Console: Saving state for ${_session.name}');
  }

  void _onVmStateChanged(ConsoleSessionState state) {
    if (mounted) {
      setState(() {
        _session = _session.copyWith(state: state);
      });
    }
  }

  void _onVmReady() {
    if (mounted) {
      setState(() => _isReady = true);
    }
  }

  void _showSaveDialog() async {
    await _saveCurrentState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('state_saved'))),
      );
    }
  }

  void _showLoadDialog() async {
    final states = await _consoleService.listSavedStates(_session.id);

    if (!mounted) return;

    if (states.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('no_saved_states'))),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_i18n.t('load_state')),
        children: states.map((state) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, state),
            child: Text(state),
          );
        }).toList(),
      ),
    );

    if (selected != null && mounted) {
      final statePath = '${_session.savedStatesPath}/$selected.state';
      _webViewKey.currentState?.loadState(statePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('state_loaded'))),
      );
    }
  }

  void _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('reset_session')),
        content: Text(_i18n.t('reset_session_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_i18n.t('reset')),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _webViewKey.currentState?.resetVm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('session_reset'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _showToolbar
          ? AppBar(
              title: Row(
                children: [
                  _buildStatusIndicator(),
                  const SizedBox(width: 8),
                  Text(_session.name),
                ],
              ),
              actions: [
                // Save state
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: _i18n.t('save_state'),
                  onPressed: _isReady ? _showSaveDialog : null,
                ),
                // Load state
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: _i18n.t('load_state'),
                  onPressed: _isReady ? _showLoadDialog : null,
                ),
                // Reset
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: _i18n.t('reset_session'),
                  onPressed: _isReady ? _showResetDialog : null,
                ),
                // Toggle toolbar
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: _i18n.t('fullscreen'),
                  onPressed: () {
                    setState(() => _showToolbar = false);
                  },
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onDoubleTap: () {
          if (!_showToolbar) {
            setState(() => _showToolbar = true);
          }
        },
        child: Stack(
          children: [
            // WebView
            ConsoleWebView(
              key: _webViewKey,
              session: _session,
              onStateChanged: _onVmStateChanged,
              onReady: _onVmReady,
            ),

            // Fullscreen exit hint
            if (!_showToolbar)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _i18n.t('double_tap_exit_fullscreen'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color color;
    String tooltip;

    switch (_session.state) {
      case ConsoleSessionState.running:
        color = Colors.green;
        tooltip = _i18n.t('vm_running');
        break;
      case ConsoleSessionState.suspended:
        color = Colors.orange;
        tooltip = _i18n.t('vm_suspended');
        break;
      case ConsoleSessionState.stopped:
      default:
        color = Colors.grey;
        tooltip = _i18n.t('vm_stopped');
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
