/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Account Setup Dialog - Configure NNTP server connection
 */

import 'package:flutter/material.dart';

import '../../models/nntp_account.dart';

/// Dialog for setting up an NNTP account
class AccountSetupDialog extends StatefulWidget {
  final NNTPAccount? existing;

  const AccountSetupDialog({
    super.key,
    this.existing,
  });

  @override
  State<AccountSetupDialog> createState() => _AccountSetupDialogState();
}

class _AccountSetupDialogState extends State<AccountSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _useTLS = false;
  bool _showPassword = false;
  bool _usePreset = true;

  // Presets for common servers
  static const _presets = <String, Map<String, dynamic>>{
    'eternal-september': {
      'name': 'Eternal September',
      'host': 'news.eternal-september.org',
      'port': 119,
      'tls': false,
      'requiresAuth': true,
    },
    'gmane': {
      'name': 'Gmane',
      'host': 'news.gmane.io',
      'port': 119,
      'tls': false,
      'requiresAuth': false,
    },
    'aioe': {
      'name': 'Aioe',
      'host': 'news.aioe.org',
      'port': 119,
      'tls': false,
      'requiresAuth': false,
    },
  };

  String? _selectedPreset;

  @override
  void initState() {
    super.initState();

    if (widget.existing != null) {
      _usePreset = false;
      _nameController.text = widget.existing!.name;
      _hostController.text = widget.existing!.host;
      _portController.text = widget.existing!.port.toString();
      _useTLS = widget.existing!.useTLS;
      _usernameController.text = widget.existing!.username ?? '';
      _passwordController.text = widget.existing!.password ?? '';
    } else {
      _portController.text = '119';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _applyPreset(String presetId) {
    final preset = _presets[presetId]!;
    setState(() {
      _selectedPreset = presetId;
      _nameController.text = preset['name'] as String;
      _hostController.text = preset['host'] as String;
      _portController.text = (preset['port'] as int).toString();
      _useTLS = preset['tls'] as bool;
    });
  }

  NNTPAccount? _buildAccount() {
    if (!_formKey.currentState!.validate()) return null;

    final id = widget.existing?.id ??
        _hostController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');

    return NNTPAccount(
      id: id,
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 119,
      useTLS: _useTLS,
      username: _usernameController.text.isNotEmpty
          ? _usernameController.text.trim()
          : null,
      password: _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Account' : 'Add Account'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Presets
                if (!isEditing) ...[
                  SwitchListTile(
                    title: const Text('Use preset server'),
                    value: _usePreset,
                    onChanged: (value) {
                      setState(() {
                        _usePreset = value;
                        if (!value) {
                          _selectedPreset = null;
                        }
                      });
                    },
                  ),
                  if (_usePreset) ...[
                    const SizedBox(height: 8),
                    ..._presets.entries.map((entry) {
                      final preset = entry.value;
                      return RadioListTile<String>(
                        title: Text(preset['name'] as String),
                        subtitle: Text(preset['host'] as String),
                        value: entry.key,
                        groupValue: _selectedPreset,
                        onChanged: (value) {
                          if (value != null) _applyPreset(value);
                        },
                      );
                    }),
                    const Divider(),
                  ],
                ],

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Account Name',
                    hintText: 'My News Server',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Host
                TextFormField(
                  controller: _hostController,
                  enabled: !_usePreset || _selectedPreset == null,
                  decoration: const InputDecoration(
                    labelText: 'Server',
                    hintText: 'news.example.com',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Server is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Port and TLS
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _portController,
                        enabled: !_usePreset || _selectedPreset == null,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '119',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) {
                            return 'Invalid';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('TLS'),
                        value: _useTLS,
                        onChanged: _usePreset && _selectedPreset != null
                            ? null
                            : (value) {
                                setState(() {
                                  _useTLS = value;
                                  if (value && _portController.text == '119') {
                                    _portController.text = '563';
                                  } else if (!value && _portController.text == '563') {
                                    _portController.text = '119';
                                  }
                                });
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Authentication
                Text(
                  'Authentication (optional)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final account = _buildAccount();
            if (account != null) {
              Navigator.pop(context, account);
            }
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
