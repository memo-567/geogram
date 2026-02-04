/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/chat_settings.dart';
import '../models/chat_security.dart';
import '../models/chat_channel.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:path/path.dart' as path;

/// Page for managing chat settings and moderators
class ChatSettingsPage extends StatefulWidget {
  final String appPath;
  final String? channelId;

  const ChatSettingsPage({
    Key? key,
    required this.appPath,
    this.channelId,
  }) : super(key: key);

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  final ChatService _chatService = ChatService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();

  ChatSettings _settings = ChatSettings();
  ChatSecurity _security = ChatSecurity();
  ChatChannel? _channel;
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _isChannelOwner = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load settings and security
  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load settings
      final settingsFile =
          File(path.join(widget.appPath, 'extra', 'settings.json'));
      if (await settingsFile.exists()) {
        final content = await settingsFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _settings = ChatSettings.fromJson(json);
      }

      // Load security
      _security = _chatService.security;

      // Check if current user is admin
      final profile = _profileService.getProfile();
      _isAdmin = _security.isAdmin(profile.npub);

      // Load channel if channelId provided
      if (widget.channelId != null) {
        try {
          _channel = _chatService.channels.firstWhere(
            (c) => c.id == widget.channelId,
          );
          // Check if current user is the channel owner
          _isChannelOwner = _channel?.config?.owner == profile.npub ||
              (_channel?.config?.owner == null && _isAdmin);
        } catch (_) {
          // Channel not found
        }
      }
    } catch (e) {
      _showError('Failed to load settings: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Save settings
  Future<void> _saveSettings() async {
    try {
      final extraDir = Directory(path.join(widget.appPath, 'extra'));
      if (!await extraDir.exists()) {
        await extraDir.create(recursive: true);
      }

      final settingsFile =
          File(path.join(widget.appPath, 'extra', 'settings.json'));
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_settings.toJson()),
      );
    } catch (e) {
      _showError('Failed to save settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_i18n.t('chat_settings')),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('chat_settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Message signing section
          _buildSection(
            theme,
            _i18n.t('message_signing'),
            [
              SwitchListTile(
                title: Text(_i18n.t('sign_messages_by_default')),
                subtitle: Text(
                  _i18n.t('sign_messages_desc'),
                ),
                value: _settings.signMessages,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings.copyWith(signMessages: value);
                  });
                  _saveSettings();
                },
              ),
              if (_profileService.getProfile().npub.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _i18n.t('nostr_keys_required'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Room visibility section (only for group channels, visible to owner/admin)
          if (_channel != null &&
              _channel!.isGroup &&
              (_isChannelOwner || _isAdmin)) ...[
            _buildSection(
              theme,
              _i18n.t('room_visibility'),
              [
                _buildVisibilitySelector(theme),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Security section (admin only)
          if (_isAdmin) ...[
            _buildSection(
              theme,
              _i18n.t('security_moderation'),
              [
                ListTile(
                  title: Text(_i18n.t('your_admin_status')),
                  subtitle: Text('npub: ${_security.adminNpub ?? "Not set"}'),
                  leading: const Icon(Icons.admin_panel_settings),
                ),
                const Divider(),
                ..._buildModeratorSections(theme),
              ],
            ),
          ] else ...[
            _buildSection(
              theme,
              _i18n.t('moderation'),
              [
                ListTile(
                  title: Text(_i18n.t('moderators')),
                  subtitle: Text(
                      _i18n.t('only_admin_manage_moderators')),
                  leading: const Icon(Icons.shield),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Build moderator sections for each channel
  List<Widget> _buildModeratorSections(ThemeData theme) {
    List<Widget> widgets = [];

    // Main channel moderators
    widgets.add(
      ListTile(
        title: Text(_i18n.t('main_channel_moderators')),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _addModerator('main'),
        ),
      ),
    );

    final mainMods = _security.getModerators('main');
    if (mainMods.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _i18n.t('no_moderators_assigned'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    } else {
      for (var npub in mainMods) {
        widgets.add(
          ListTile(
            dense: true,
            leading: const Icon(Icons.person, size: 20),
            title: Text(
              npub,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _removeModerator('main', npub),
            ),
          ),
        );
      }
    }

    widgets.add(const Divider());

    // Group channels
    final channels = _chatService.channels
        .where((ch) => ch.isGroup && ch.id != 'main')
        .toList();

    for (var channel in channels) {
      widgets.add(
        ListTile(
          title: Text(_i18n.t('channel_moderators', params: [channel.name])),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addModerator(channel.id),
          ),
        ),
      );

      final channelMods = _security.getModerators(channel.id);
      if (channelMods.isEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _i18n.t('no_moderators_assigned'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      } else {
        for (var npub in channelMods) {
          widgets.add(
            ListTile(
              dense: true,
              leading: const Icon(Icons.person, size: 20),
              title: Text(
                npub,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () => _removeModerator(channel.id, npub),
              ),
            ),
          );
        }
      }

      widgets.add(const Divider());
    }

    return widgets;
  }

  /// Build a section
  Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  /// Add moderator dialog
  Future<void> _addModerator(String channelId) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('add_moderator')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: _i18n.t('nostr_public_key_npub'),
            hintText: _i18n.t('npub_placeholder'),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_i18n.t('add')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (!result.startsWith('npub1')) {
        _showError(_i18n.t('invalid_npub_format'));
        return;
      }

      try {
        _security.addModerator(channelId, result);
        await _chatService.saveSecurity(_security);
        setState(() {});
        _showSuccess(_i18n.t('moderator_added'));
      } catch (e) {
        _showError('Failed to add moderator: $e');
      }
    }
  }

  /// Remove moderator
  Future<void> _removeModerator(String channelId, String npub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('remove_moderator')),
        content: Text(_i18n.t('remove_moderator_confirm')),
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
        _security.removeModerator(channelId, npub);
        await _chatService.saveSecurity(_security);
        setState(() {});
        _showSuccess(_i18n.t('moderator_removed'));
      } catch (e) {
        _showError('Failed to remove moderator: $e');
      }
    }
  }

  /// Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Show success message
  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Build visibility selector with radio options
  Widget _buildVisibilitySelector(ThemeData theme) {
    final currentVisibility = _channel?.config?.visibility ?? 'PUBLIC';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _i18n.t('change_visibility_warning'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        RadioListTile<String>(
          title: Row(
            children: [
              Icon(Icons.public, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(_i18n.t('public')),
            ],
          ),
          subtitle: Text(
            _i18n.t('public_room_description'),
            style: theme.textTheme.bodySmall,
          ),
          value: 'PUBLIC',
          groupValue: currentVisibility,
          onChanged: (value) => _changeVisibility(value!),
        ),
        RadioListTile<String>(
          title: Row(
            children: [
              Icon(Icons.lock, size: 20, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text(_i18n.t('restricted')),
            ],
          ),
          subtitle: Text(
            _i18n.t('restricted_room_description'),
            style: theme.textTheme.bodySmall,
          ),
          value: 'RESTRICTED',
          groupValue: currentVisibility,
          onChanged: (value) => _changeVisibility(value!),
        ),
      ],
    );
  }

  /// Change room visibility
  Future<void> _changeVisibility(String newVisibility) async {
    if (_channel == null) return;

    final profile = _profileService.getProfile();

    // Get current config or create a default one
    final currentConfig = _channel!.config ?? ChatChannelConfig(
      id: _channel!.id,
      name: _channel!.name,
      visibility: 'PUBLIC',
    );

    final currentVisibility = currentConfig.visibility;
    if (currentVisibility == newVisibility) return;

    try {
      var updatedConfig = currentConfig.copyWith(visibility: newVisibility);

      // If making restricted and no owner set, set current user as owner
      if (newVisibility == 'RESTRICTED' && updatedConfig.owner == null) {
        updatedConfig = updatedConfig.copyWith(owner: profile.npub);
      }

      // If making restricted, ensure current user is in members list
      if (newVisibility == 'RESTRICTED' &&
          !updatedConfig.members.contains(profile.npub)) {
        final newMembers = List<String>.from(updatedConfig.members)
          ..add(profile.npub);
        updatedConfig = updatedConfig.copyWith(members: newMembers);
      }

      await _chatService.updateChannel(_channel!.copyWith(config: updatedConfig));

      setState(() {
        _channel = _chatService.channels.firstWhere(
          (c) => c.id == widget.channelId,
        );
        _isChannelOwner = true; // After making restricted, user becomes owner
      });

      _showSuccess(newVisibility == 'RESTRICTED'
          ? _i18n.t('room_made_restricted')
          : _i18n.t('room_made_public'));
    } catch (e) {
      _showError('Failed to change visibility: $e');
    }
  }
}
