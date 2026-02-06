/// Mirror Wizard Page.
///
/// Step-by-step wizard for adding a mirror peer device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/mirror_config.dart';
import '../services/mirror_config_service.dart';

/// Wizard for pairing a new mirror device
class MirrorWizardPage extends StatefulWidget {
  const MirrorWizardPage({super.key});

  @override
  State<MirrorWizardPage> createState() => _MirrorWizardPageState();
}

class _MirrorWizardPageState extends State<MirrorWizardPage> {
  final MirrorConfigService _configService = MirrorConfigService.instance;
  final PageController _pageController = PageController();

  int _currentStep = 0;
  bool _isSearching = false;
  List<_DiscoveredDevice> _discoveredDevices = [];
  Timer? _discoveryTimer;
  bool _scanCancelled = false;
  _DiscoveredDevice? _selectedDevice;
  String _manualAddress = '';
  final Map<String, bool> _selectedApps = {};
  final Map<String, SyncStyle> _appStyles = {};
  InitialSyncOption _initialSyncOption = InitialSyncOption.downloadAll;

  // Available apps to sync
  final List<_AppInfo> _availableApps = [
    _AppInfo('blog', 'Blog', 'Posts, comments, and likes', Icons.article),
    _AppInfo('chat', 'Chat', 'Messages and conversations', Icons.chat),
    _AppInfo('places', 'Places', 'Saved locations', Icons.place),
    _AppInfo('events', 'Events', 'Calendar events', Icons.event),
    _AppInfo('contacts', 'Contacts', 'Contact list', Icons.contacts),
    _AppInfo('tracker', 'Tracker', 'GPS tracks', Icons.route),
    _AppInfo('shared_folder', 'Shared folder', 'Shared files', Icons.folder),
    _AppInfo('files', 'Files', 'File explorer', Icons.snippet_folder),
  ];

  @override
  void initState() {
    super.initState();
    // Select all apps by default
    for (final app in _availableApps) {
      _selectedApps[app.id] = true;
      _appStyles[app.id] = SyncStyle.sendReceive;
    }
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _scanCancelled = true;
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Mirror Device'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildIntroStep(),
                _buildDiscoveryStep(),
                _buildAppsStep(),
                _buildInitialSyncStep(),
                _buildCompleteStep(),
              ],
            ),
          ),

          // Navigation buttons
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Intro', 'Find', 'Apps', 'Sync', 'Done'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Row(
            children: [
              if (index > 0)
                Container(
                  width: 24,
                  height: 2,
                  color: isCompleted
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive || isCompleted
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildIntroStep() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(
              Icons.sync_alt,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Mirror Your Apps',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Mirror keeps your apps synchronized between devices. Changes on one device automatically appear on the other.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildFeatureRow(
            Icons.devices,
            'Multi-device sync',
            'Keep the same data on multiple devices',
          ),
          _buildFeatureRow(
            Icons.wifi,
            'Works over WiFi & Bluetooth',
            'Sync directly when on the same network',
          ),
          _buildFeatureRow(
            Icons.tune,
            'Per-app control',
            'Choose which apps to sync and how',
          ),
          _buildFeatureRow(
            Icons.offline_bolt,
            'Offline support',
            'Changes sync when devices reconnect',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryStep() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find Device',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the other device has Mirror enabled and is on the same network.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),

          // Auto-searching indicator
          if (_isSearching) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Searching your network...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Discovered devices
          if (_discoveredDevices.isNotEmpty) ...[
            Text(
              'Discovered Devices',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...(_discoveredDevices.map((device) => _buildDeviceTile(device))),
            const SizedBox(height: 24),
          ],

          // Manual entry
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Or enter address manually:',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Device Address',
              hintText: 'e.g., 192.168.1.100 or device.local',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _manualAddress = value,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _manualAddress.isNotEmpty ? _connectManual : null,
            icon: const Icon(Icons.link),
            label: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(_DiscoveredDevice device) {
    final theme = Theme.of(context);
    final isSelected = _selectedDevice?.id == device.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            device.platform == 'Android'
                ? Icons.android
                : device.platform == 'iOS'
                    ? Icons.phone_iphone
                    : Icons.computer,
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(device.name),
        subtitle: Row(
          children: [
            Icon(
              device.method == 'lan' ? Icons.wifi : Icons.bluetooth,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              device.address,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
            if (device.latencyMs != null) ...[
              const SizedBox(width: 8),
              Text(
                '${device.latencyMs}ms',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
        onTap: () {
          _discoveryTimer?.cancel();
          _discoveryTimer = null;
          _scanCancelled = true;
          setState(() {
            _selectedDevice = device;
            _isSearching = false;
          });
        },
      ),
    );
  }

  Widget _buildAppsStep() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Apps',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which apps to synchronize and how.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          ..._availableApps.map((app) => _buildAppSelectTile(app)),
        ],
      ),
    );
  }

  Widget _buildAppSelectTile(_AppInfo app) {
    final theme = Theme.of(context);
    final isSelected = _selectedApps[app.id] ?? false;
    final style = _appStyles[app.id] ?? SyncStyle.sendReceive;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  _selectedApps[app.id] = value ?? false;
                });
              },
            ),
            Icon(app.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    app.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              DropdownButton<SyncStyle>(
                value: style,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(
                    value: SyncStyle.sendReceive,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.sync, size: 16),
                        SizedBox(width: 4),
                        Text('Send & Receive'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SyncStyle.receiveOnly,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.download, size: 16),
                        SizedBox(width: 4),
                        Text('Receive Only'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: SyncStyle.sendOnly,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.upload, size: 16),
                        SizedBox(width: 4),
                        Text('Send Only'),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _appStyles[app.id] = value;
                    });
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialSyncStep() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Initial Sync',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The other device has existing data. How should we proceed?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          _buildSyncOptionTile(
            InitialSyncOption.downloadAll,
            'Download all existing data',
            'Get everything from the other device (recommended)',
            Icons.cloud_download,
          ),
          _buildSyncOptionTile(
            InitialSyncOption.startFresh,
            'Start fresh',
            'Keep current data, sync only new changes going forward',
            Icons.fiber_new,
          ),
          _buildSyncOptionTile(
            InitialSyncOption.uploadMine,
            'Replace with my data',
            'Upload my data to the other device',
            Icons.cloud_upload,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOptionTile(
    InitialSyncOption option,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final isSelected = _initialSyncOption == option;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: Radio<InitialSyncOption>(
          value: option,
          groupValue: _initialSyncOption,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _initialSyncOption = value;
              });
            }
          },
        ),
        onTap: () {
          setState(() {
            _initialSyncOption = option;
          });
        },
      ),
    );
  }

  Widget _buildCompleteStep() {
    final theme = Theme.of(context);
    final selectedAppCount =
        _selectedApps.values.where((v) => v).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.check_circle,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 24),
          Text(
            'Ready to Sync!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your device is ready to sync with:',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.devices,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedDevice?.name ?? 'Manual Device',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _selectedDevice?.address ?? _manualAddress,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '$selectedAppCount',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Apps to sync',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(
                            _initialSyncOption == InitialSyncOption.downloadAll
                                ? Icons.cloud_download
                                : _initialSyncOption ==
                                        InitialSyncOption.uploadMine
                                    ? Icons.cloud_upload
                                    : Icons.fiber_new,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                          Text(
                            _initialSyncOption == InitialSyncOption.downloadAll
                                ? 'Download'
                                : _initialSyncOption ==
                                        InitialSyncOption.uploadMine
                                    ? 'Upload'
                                    : 'Fresh start',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final isFirstStep = _currentStep == 0;
    final isLastStep = _currentStep == 4;
    final canProceed = _canProceed();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!isFirstStep && !isLastStep)
            TextButton(
              onPressed: _previousStep,
              child: const Text('Back'),
            ),
          const Spacer(),
          if (isLastStep)
            ElevatedButton.icon(
              onPressed: _finishWizard,
              icon: const Icon(Icons.check),
              label: const Text('Start Sync'),
            )
          else
            ElevatedButton(
              onPressed: canProceed ? _nextStep : null,
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0: // Intro
        return true;
      case 1: // Discovery
        return _selectedDevice != null || _manualAddress.isNotEmpty;
      case 2: // Apps
        return _selectedApps.values.any((v) => v);
      case 3: // Initial sync
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      // Cancel discovery when leaving step 1
      if (_currentStep == 1) {
        _discoveryTimer?.cancel();
        _discoveryTimer = null;
        _scanCancelled = true;
      }
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // Auto-start discovery when entering step 1
      if (_currentStep == 1) {
        _startDiscovery();
        _discoveryTimer?.cancel();
        _discoveryTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _startDiscovery(),
        );
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      // Cancel discovery when leaving step 1
      if (_currentStep == 1) {
        _discoveryTimer?.cancel();
        _discoveryTimer = null;
        _scanCancelled = true;
      }
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _startDiscovery() async {
    if (_isSearching) return;

    setState(() {
      _isSearching = true;
      _scanCancelled = false;
    });

    final selectedId = _selectedDevice?.id;
    final found = <_DiscoveredDevice>[];

    try {
      // Get local IPv4 addresses
      final localIps = <String>[];
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback &&
                (addr.address.startsWith('192.') ||
                    addr.address.startsWith('10.') ||
                    addr.address.startsWith('172.'))) {
              localIps.add(addr.address);
            }
          }
        }
      } catch (_) {}

      if (localIps.isEmpty || _scanCancelled) return;

      // Extract unique subnets
      final subnets = localIps
          .map((ip) => ip.substring(0, ip.lastIndexOf('.')))
          .toSet();

      // Build list of all IPs to scan (excluding our own)
      final targets = <String>[];
      for (final subnet in subnets) {
        for (var i = 1; i <= 254; i++) {
          final ip = '$subnet.$i';
          if (!localIps.contains(ip)) {
            targets.add(ip);
          }
        }
      }

      // Scan in batches of 50 concurrent requests
      const batchSize = 50;
      const port = 3456;
      final timeout = Duration(milliseconds: 400);

      for (var i = 0; i < targets.length; i += batchSize) {
        if (_scanCancelled || !mounted) break;

        final batch = targets.sublist(
          i,
          (i + batchSize).clamp(0, targets.length),
        );

        final futures = batch.map((ip) async {
          try {
            final uri = Uri.parse('http://$ip:$port/api/status');
            final response = await http
                .get(uri)
                .timeout(timeout);
            if (response.statusCode == 200) {
              final body = response.body;
              // Accept any geogram response
              if (body.contains('Geogram') || body.contains('geogram')) {
                try {
                  final json = jsonDecode(body) as Map<String, dynamic>;
                  final name = (json['nickname'] as String?) ??
                      (json['callsign'] as String?) ??
                      ip;
                  final platform =
                      (json['platform'] as String?) ?? 'Unknown';
                  return _DiscoveredDevice(
                    id: '$ip:$port',
                    name: name,
                    address: '$ip:$port',
                    platform: platform,
                    method: 'lan',
                  );
                } catch (_) {
                  // Valid response but not JSON — still a geogram device
                  return _DiscoveredDevice(
                    id: '$ip:$port',
                    name: ip,
                    address: '$ip:$port',
                    platform: 'Unknown',
                    method: 'lan',
                  );
                }
              }
            }
          } catch (_) {
            // Timeout or connection refused — not a geogram device
          }
          return null;
        });

        final results = await Future.wait(futures);

        for (final device in results) {
          if (device != null) {
            found.add(device);
          }
        }

        // Update UI in real-time as batches complete
        if (mounted && !_scanCancelled) {
          setState(() {
            _discoveredDevices = List.of(found);
            // Preserve selection across re-scans
            if (selectedId != null) {
              final match = found.where((d) => d.id == selectedId);
              if (match.isNotEmpty) {
                _selectedDevice = match.first;
              }
            }
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _connectManual() {
    // Create a device from manual entry
    final device = _DiscoveredDevice(
      id: const Uuid().v4(),
      name: 'Manual Device',
      address: _manualAddress,
      platform: 'Unknown',
      method: 'manual',
    );

    setState(() {
      _selectedDevice = device;
    });
  }

  void _finishWizard() async {
    // Create the peer from wizard data
    final apps = <String, AppSyncConfig>{};
    for (final entry in _selectedApps.entries) {
      if (entry.value) {
        apps[entry.key] = AppSyncConfig(
          appId: entry.key,
          style: _appStyles[entry.key] ?? SyncStyle.sendReceive,
          enabled: true,
        );
      }
    }

    final peer = MirrorPeer(
      peerId: _selectedDevice?.id ?? const Uuid().v4(),
      name: _selectedDevice?.name ?? 'Manual Device',
      callsign: '', // Will be filled when actually connected
      addresses: [_selectedDevice?.address ?? _manualAddress],
      apps: apps,
      platform: _selectedDevice?.platform,
    );

    await _configService.addPeer(peer);

    // Enable mirror if not already enabled
    if (!_configService.isEnabled) {
      await _configService.setEnabled(true);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }
}

/// Internal class for discovered devices during wizard
class _DiscoveredDevice {
  final String id;
  final String name;
  final String address;
  final String platform;
  final String method; // lan, ble, manual
  final int? latencyMs;

  _DiscoveredDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.platform,
    required this.method,
    this.latencyMs,
  });
}

/// Internal class for app info
class _AppInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;

  _AppInfo(this.id, this.name, this.description, this.icon);
}

/// Initial sync options
enum InitialSyncOption {
  downloadAll,
  startFresh,
  uploadMine,
}
