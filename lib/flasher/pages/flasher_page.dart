/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/device_definition.dart';
import '../models/flash_progress.dart';
import '../serial/serial_port.dart';
import '../services/flasher_service.dart';
import '../widgets/add_firmware_wizard.dart';
import '../widgets/firmware_tree_widget.dart';
import '../widgets/flash_progress_widget.dart';

/// Main flasher page with Library and Flasher tabs
class FlasherPage extends StatefulWidget {
  final String basePath;

  const FlasherPage({
    super.key,
    required this.basePath,
  });

  @override
  State<FlasherPage> createState() => _FlasherPageState();
}

class _FlasherPageState extends State<FlasherPage>
    with SingleTickerProviderStateMixin {
  late FlasherService _flasherService;
  late TabController _tabController;

  // Device hierarchy for library view
  Map<String, Map<String, List<DeviceDefinition>>> _hierarchy = {};

  // Selection
  DeviceDefinition? _selectedDevice;
  FirmwareVersion? _selectedVersion;

  // Port selection
  List<PortInfo> _ports = [];
  PortInfo? _selectedPort;
  String? _firmwarePath;

  // State
  bool _isLoading = true;
  bool _isFlashing = false;
  FlashProgress? _flashProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _flasherService = FlasherService.withPath(widget.basePath);
    _tabController = TabController(length: 2, vsync: this);
    _loadDevices();
    _refreshPorts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final hierarchy = await _flasherService.storage.loadDevicesByHierarchy();
      setState(() {
        _hierarchy = hierarchy;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshPorts() async {
    try {
      final ports = await _flasherService.listPorts();
      setState(() {
        _ports = ports;

        // Auto-select matching port for selected device
        if (_selectedDevice != null && _selectedDevice!.usb != null) {
          final matching = _findMatchingPort(_selectedDevice!);
          if (matching != null) {
            _selectedPort = matching;
            return;
          }
        }

        // If no port selected yet, auto-select the most likely ESP32 port
        if (_selectedPort == null && ports.isNotEmpty) {
          _selectedPort = _findBestEsp32Port(ports);
        }
      });
    } catch (e) {
      // Port listing failed - may not have libserialport installed
      setState(() {
        _ports = [];
      });
    }
  }

  /// Find the most likely ESP32 port from available ports
  PortInfo? _findBestEsp32Port(List<PortInfo> ports) {
    // Priority order for ESP32 detection:
    // 1. Espressif native USB (ESP32-C3/S2/S3) - VID 0x303A
    // 2. Known USB-UART bridges commonly used with ESP32

    // First, look for Espressif native USB
    for (final port in ports) {
      if (port.vid == 0x303A) {
        return port;
      }
    }

    // Then check for common USB-UART chips
    for (final port in ports) {
      final match = Esp32UsbIdentifiers.matchEsp32(port);
      if (match != null) {
        return port;
      }
    }

    // If no ESP32 found but we have ports, select the first USB serial port
    // (skip built-in serial ports that typically have no VID/PID)
    for (final port in ports) {
      if (port.vid != null && port.pid != null) {
        return port;
      }
    }

    // Last resort: return first port
    return ports.isNotEmpty ? ports.first : null;
  }

  PortInfo? _findMatchingPort(DeviceDefinition device) {
    if (device.usb == null) return null;

    final vid = device.usb!.vidInt;
    final pid = device.usb!.pidInt;

    for (final port in _ports) {
      if (port.vid == vid && port.pid == pid) {
        return port;
      }
    }

    return null;
  }

  void _onFirmwareSelected(DeviceDefinition device, FirmwareVersion? version) {
    setState(() {
      _selectedDevice = device;
      _selectedVersion = version;
      _firmwarePath = null; // Reset custom firmware

      // Auto-select matching port
      final matching = _findMatchingPort(device);
      if (matching != null) {
        _selectedPort = matching;
      }
    });

    // Switch to Flasher tab (index 0)
    _tabController.animateTo(0);
  }

  Future<void> _selectFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _firmwarePath = result.files.first.path;
      });
    }
  }

  Future<void> _startFlash() async {
    if (_selectedDevice == null) {
      _showError('Please select a firmware from the Library');
      return;
    }

    if (_selectedPort == null) {
      _showError('Please select a serial port');
      return;
    }

    // Need either firmware file, local version, or URL
    final hasLocalVersion = _selectedVersion != null;
    final hasFirmwareUrl = _selectedDevice!.flash.firmwareUrl != null;
    if (_firmwarePath == null && !hasLocalVersion && !hasFirmwareUrl) {
      _showError('No firmware available for this device');
      return;
    }

    setState(() {
      _isFlashing = true;
      _flashProgress = FlashProgress.connecting();
      _error = null;
    });

    try {
      // Determine firmware path
      String? firmwarePath = _firmwarePath;
      if (firmwarePath == null && _selectedVersion != null) {
        // Use local version path
        final basePath = _selectedDevice!.basePath;
        if (basePath != null) {
          firmwarePath = '$basePath/${_selectedVersion!.firmwarePath}';
        }
      }

      await _flasherService.flashDevice(
        device: _selectedDevice!,
        portPath: _selectedPort!.path,
        firmwarePath: firmwarePath,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _flashProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        _showSuccess('Flash completed successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _flashProgress = FlashProgress.error(e.toString());
        });
        _showError('Flash failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFlashing = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flasher'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Flasher', icon: Icon(Icons.flash_on)),
            Tab(text: 'Library', icon: Icon(Icons.folder)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadDevices();
              _refreshPorts();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _error != null
          ? _buildErrorView()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFlasherTab(),
                _buildLibraryTab(),
              ],
            ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error ?? 'Unknown error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDevices,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    return Stack(
      children: [
        FirmwareTreeWidget(
          hierarchy: _hierarchy,
          selectedDevice: _selectedDevice,
          selectedVersion: _selectedVersion,
          onSelected: _onFirmwareSelected,
          isLoading: _isLoading,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add_firmware',
            onPressed: _openAddFirmwareWizard,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }

  void _openAddFirmwareWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => AddFirmwareWizard(
          basePath: widget.basePath,
          hierarchy: _hierarchy,
          onComplete: () {
            _loadDevices();
          },
        ),
      ),
    );
  }

  Widget _buildFlasherTab() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Firmware selection
          Text(
            'Firmware',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildFirmwareSelection(theme),

          const SizedBox(height: 24),

          // Port selection
          Text(
            'Serial Port',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildPortSelector(),

          const SizedBox(height: 24),

          // Flash progress
          if (_isFlashing || _flashProgress != null) ...[
            Text(
              'Progress',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FlashProgressWidget(
              progress: _flashProgress ?? FlashProgress(),
            ),
            const SizedBox(height: 24),
          ],

          // Flash button
          Center(
            child: ElevatedButton.icon(
              onPressed: _isFlashing || _selectedDevice == null
                  ? null
                  : _startFlash,
              icon: _isFlashing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flash_on),
              label: Text(_isFlashing ? 'Flashing...' : 'Flash Device'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_ports.isEmpty)
              const Text(
                'No serial ports found. Make sure your device is connected.',
              )
            else
              DropdownButtonFormField<PortInfo>(
                value: _selectedPort,
                decoration: const InputDecoration(
                  labelText: 'Serial Port',
                  border: OutlineInputBorder(),
                ),
                items: _ports.map((port) {
                  final isMatch = _selectedDevice != null &&
                      _selectedDevice!.usb != null &&
                      port.vid == _selectedDevice!.usb!.vidInt &&
                      port.pid == _selectedDevice!.usb!.pidInt;

                  final esp32Type = Esp32UsbIdentifiers.matchEsp32(port);
                  final isEsp32 = esp32Type != null;

                  // Build label with ESP32 indicator
                  String label = port.path;
                  if (isEsp32) {
                    label = '${port.path} - $esp32Type';
                  } else if (port.product != null) {
                    label = '${port.path} (${port.product})';
                  }

                  return DropdownMenuItem(
                    value: port,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label),
                        if (isMatch)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.check_circle,
                                size: 16, color: Colors.green),
                          )
                        else if (isEsp32)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ESP32',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (port) {
                  setState(() {
                    _selectedPort = port;
                  });
                },
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refreshPorts,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Ports'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirmwareSelection(ThemeData theme) {
    // If a custom firmware file is selected
    if (_firmwarePath != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.file_present, color: Colors.green, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Firmware',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        Text(
                          _firmwarePath!.split(Platform.pathSeparator).last,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _firmwarePath = null;
                      });
                    },
                    tooltip: 'Clear',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.folder),
                      label: const Text('Library'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectFirmware,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // If a device from library is selected
    if (_selectedDevice != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Device image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildDeviceImage(),
                  ),
                  const SizedBox(width: 16),

                  // Device info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedDevice!.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_selectedDevice!.effectiveProject} / ${_selectedDevice!.effectiveArchitecture}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (_selectedVersion != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'v${_selectedVersion!.version}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.folder),
                      label: const Text('Library'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectFirmware,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // No firmware selected - show both options
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.memory,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No firmware selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.folder),
                    label: const Text('Library'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectFirmware,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceImage() {
    final photoPath = _selectedDevice?.photoPath;
    if (photoPath != null) {
      final file = File(photoPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        );
      }
    }
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.developer_board,
        size: 32,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
