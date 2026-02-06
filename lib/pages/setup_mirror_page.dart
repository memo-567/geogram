/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';

/// Passive mirror setup page — shows this device's IP address
/// so the other device can add it via Settings > Mirror > Add Device.
class SetupMirrorPage extends StatefulWidget {
  const SetupMirrorPage({super.key});

  @override
  State<SetupMirrorPage> createState() => _SetupMirrorPageState();
}

class _SetupMirrorPageState extends State<SetupMirrorPage> {
  final I18nService _i18n = I18nService();
  List<String> _ipAddresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchIpAddresses();
  }

  Future<void> _fetchIpAddresses() async {
    final ips = await _getLocalIpAddresses();
    if (mounted) {
      setState(() {
        _ipAddresses = ips;
        _isLoading = false;
      });
    }
  }

  Future<List<String>> _getLocalIpAddresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      LogService().log('Error getting local IPs: $e');
    }
    return ips;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.tOrDefault('setup_mirror', 'Setup Mirror')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Icon header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sync_alt,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(
                    _i18n.tOrDefault('setup_mirror_title', 'Become a Mirror'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Description
                  Text(
                    _i18n.tOrDefault(
                      'setup_mirror_description',
                      'This device will become a mirror of another existing device, keeping the same profile and data in sync between both.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // WiFi security info card
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_lock,
                              color: theme.colorScheme.onSecondaryContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _i18n.tOrDefault(
                                'setup_mirror_wifi_security',
                                'Mirrors only work through local WiFi for security reasons. Both devices must be connected to the same network.',
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // IP address display
                  _buildIpAddressSection(theme),
                  const SizedBox(height: 32),
                  // Instructions for other device
                  _buildInstructions(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildIpAddressSection(ThemeData theme) {
    if (_ipAddresses.isEmpty) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.wifi_off, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _i18n.tOrDefault(
                    'setup_mirror_no_ip',
                    'No WiFi connection detected. Connect to a WiFi network and try again.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Text(
          _i18n.tOrDefault(
              'setup_mirror_your_ip', "This device's IP address:"),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final ip in _ipAddresses) ...[
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: ip));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      _i18n.tOrDefault('copied_to_clipboard', 'Copied: {0}',
                          params: [ip])),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: SelectableText(
                      ip,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.copy,
                      size: 20, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildInstructions(ThemeData theme) {
    final steps = [
      _i18n.tOrDefault('setup_mirror_step1',
          'Make sure both devices are on the same WiFi network'),
      _i18n.tOrDefault('setup_mirror_step2', 'Open Settings'),
      _i18n.tOrDefault('setup_mirror_step3', 'Tap "Mirror"'),
      _i18n.tOrDefault('setup_mirror_step4',
          'Enable Mirror if not already enabled'),
      _i18n.tOrDefault('setup_mirror_step5', 'Tap "Add Device"'),
      _i18n.tOrDefault('setup_mirror_step6',
          'Enter this device\'s IP address shown above'),
      _i18n.tOrDefault('setup_mirror_step7',
          'Follow the wizard to select which apps to sync'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _i18n.tOrDefault(
              'setup_mirror_instructions_title', 'On the other device:'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < steps.length; i++)
          _buildStepRow(theme, i + 1, steps[i]),
      ],
    );
  }

  Widget _buildStepRow(ThemeData theme, int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
