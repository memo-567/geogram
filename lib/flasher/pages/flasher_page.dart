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
import '../widgets/device_card.dart';
import '../widgets/flash_progress_widget.dart';

/// Main flasher page for browsing devices and flashing firmware
class FlasherPage extends StatefulWidget {
  final String basePath;

  const FlasherPage({
    super.key,
    required this.basePath,
  });

  @override
  State<FlasherPage> createState() => _FlasherPageState();
}

class _FlasherPageState extends State<FlasherPage> {
  late FlasherService _flasherService;

  List<DeviceDefinition> _devices = [];
  List<PortInfo> _ports = [];
  DeviceDefinition? _selectedDevice;
  PortInfo? _selectedPort;
  String? _firmwarePath;

  bool _isLoading = true;
  bool _isFlashing = false;
  FlashProgress? _flashProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _flasherService = FlasherService.withPath(widget.basePath);
    _loadDevices();
    _refreshPorts();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final devices = await _flasherService.storage.loadAllDevices();
      setState(() {
        _devices = devices;
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

        // Auto-select matching port
        if (_selectedDevice != null && _selectedDevice!.usb != null) {
          final matching = _findMatchingPort(_selectedDevice!);
          if (matching != null) {
            _selectedPort = matching;
          }
        }
      });
    } catch (e) {
      // Port listing failed - may not have libserialport installed
      setState(() {
        _ports = [];
      });
    }
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
      _showError('Please select a device');
      return;
    }

    if (_selectedPort == null) {
      _showError('Please select a serial port');
      return;
    }

    // Need either firmware file or URL
    if (_firmwarePath == null && _selectedDevice!.flash.firmwareUrl == null) {
      _showError('Please select a firmware file');
      return;
    }

    setState(() {
      _isFlashing = true;
      _flashProgress = FlashProgress.connecting();
      _error = null;
    });

    try {
      await _flasherService.flashDevice(
        device: _selectedDevice!,
        portPath: _selectedPort!.path,
        firmwarePath: _firmwarePath,
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flasher'),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildContent(theme),
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

  Widget _buildContent(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device selection
          Text(
            'Select Device',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildDeviceGrid(),

          const SizedBox(height: 24),

          // Port selection
          Text(
            'Serial Port',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildPortSelector(),

          const SizedBox(height: 24),

          // Firmware selection
          Text(
            'Firmware',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildFirmwareSelector(),

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
              onPressed: _isFlashing ? null : _startFlash,
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

  Widget _buildDeviceGrid() {
    if (_devices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('No devices found'),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _devices.map((device) {
        final isSelected = _selectedDevice?.id == device.id;
        return DeviceCard(
          device: device,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedDevice = device;
              // Try to auto-select matching port
              final matching = _findMatchingPort(device);
              if (matching != null) {
                _selectedPort = matching;
              }
            });
          },
        );
      }).toList(),
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

                  return DropdownMenuItem(
                    value: port,
                    child: Row(
                      children: [
                        Text(port.displayName),
                        if (isMatch) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle,
                              size: 16, color: Colors.green),
                        ],
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

  Widget _buildFirmwareSelector() {
    final hasFirmwareUrl = _selectedDevice?.flash.firmwareUrl != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasFirmwareUrl) ...[
              RadioListTile<bool>(
                title: const Text('Download latest firmware'),
                subtitle: Text(
                  _selectedDevice?.flash.firmwareUrl ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                value: true,
                groupValue: _firmwarePath == null,
                onChanged: (value) {
                  if (value == true) {
                    setState(() {
                      _firmwarePath = null;
                    });
                  }
                },
              ),
              RadioListTile<bool>(
                title: const Text('Use local file'),
                subtitle: _firmwarePath != null
                    ? Text(
                        _firmwarePath!.split(Platform.pathSeparator).last,
                        style: const TextStyle(fontSize: 12),
                      )
                    : const Text('No file selected'),
                value: false,
                groupValue: _firmwarePath == null,
                onChanged: (value) async {
                  if (value == false) {
                    await _selectFirmware();
                  }
                },
              ),
            ] else ...[
              if (_firmwarePath != null)
                ListTile(
                  leading: const Icon(Icons.file_present),
                  title: Text(_firmwarePath!.split(Platform.pathSeparator).last),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _firmwarePath = null;
                      });
                    },
                  ),
                )
              else
                const Text('Select a firmware file to flash'),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _selectFirmware,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse...'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
