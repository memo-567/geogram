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
import '../widgets/serial_monitor_widget.dart';

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
  final _flasherScrollController = ScrollController();
  final _monitorKey = GlobalKey<SerialMonitorWidgetState>();

  // Device hierarchy for library view
  Map<String, Map<String, List<DeviceDefinition>>> _hierarchy = {};

  // Selection
  DeviceDefinition? _selectedDevice;
  FirmwareVersion? _selectedVersion;

  // Port selection
  List<PortInfo> _ports = [];
  PortInfo? _selectedPort;
  List<PortInfo> _selectedPorts = [];
  String? _firmwarePath;

  // Multi-flash progress tracking
  Map<String, FlashProgress> _multiFlashProgress = {};

  // State
  bool _isLoading = true;
  bool _isFlashing = false;
  FlashProgress? _flashProgress;
  String? _error;

  // Monitor after flash option
  bool _monitorAfterFlash = true;
  bool _monitorWasConnected = false;

  @override
  void initState() {
    super.initState();
    _flasherService = FlasherService.withPath(widget.basePath);
    _tabController = TabController(length: 3, vsync: this);
    _loadDevices();
    _refreshPorts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _flasherScrollController.dispose();
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

        // Remove any selected ports that are no longer available
        _selectedPorts.removeWhere((port) => !ports.contains(port));

        // Auto-select matching port for selected device
        if (_selectedDevice != null && _selectedDevice!.usb != null) {
          final matching = _findMatchingPort(_selectedDevice!);
          if (matching != null) {
            _selectedPort = matching;
            if (!_selectedPorts.contains(matching)) {
              _selectedPorts.add(matching);
            }
            return;
          }
        }

        // If no port selected yet, auto-select the most likely ESP32 port
        if (_selectedPort == null && ports.isNotEmpty) {
          _selectedPort = _findBestEsp32Port(ports);
          if (_selectedPort != null && _selectedPorts.isEmpty) {
            _selectedPorts.add(_selectedPort!);
          }
        }

        // Keep _selectedPort in sync with _selectedPorts
        if (_selectedPorts.isNotEmpty && _selectedPort == null) {
          _selectedPort = _selectedPorts.first;
        }
      });
    } catch (e) {
      // Port listing failed - may not have libserialport installed
      setState(() {
        _ports = [];
        _selectedPorts.clear();
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

    // Get the list of ports to flash
    final portsToFlash = _selectedPorts.isNotEmpty
        ? _selectedPorts
        : (_selectedPort != null ? [_selectedPort!] : <PortInfo>[]);

    if (portsToFlash.isEmpty) {
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

    // Check if monitor is connected and disconnect if so
    _monitorWasConnected = _monitorKey.currentState?.isConnected ?? false;
    if (_monitorWasConnected) {
      await _monitorKey.currentState?.disconnect();
    }

    final isMultiFlash = portsToFlash.length > 1;

    setState(() {
      _isFlashing = true;
      _error = null;
      if (isMultiFlash) {
        _multiFlashProgress = {
          for (final port in portsToFlash) port.path: FlashProgress.connecting()
        };
        _flashProgress = null;
      } else {
        _flashProgress = FlashProgress.connecting();
        _multiFlashProgress = {};
      }
    });

    // Scroll to bottom to show progress
    _scrollToBottom();

    // Determine firmware path
    String? firmwarePath = _firmwarePath;
    if (firmwarePath == null && _selectedVersion != null) {
      // Use local version path
      final basePath = _selectedDevice!.basePath;
      if (basePath != null) {
        firmwarePath = '$basePath/${_selectedVersion!.firmwarePath}';
      }
    }

    if (isMultiFlash) {
      // Flash multiple devices in parallel
      await _flashMultipleDevices(portsToFlash, firmwarePath);
    } else {
      // Flash single device
      await _flashSingleDevice(portsToFlash.first, firmwarePath);
    }
  }

  Future<void> _flashSingleDevice(PortInfo port, String? firmwarePath) async {
    try {
      await _flasherService.flashDevice(
        device: _selectedDevice!,
        portPath: port.path,
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

        // Switch to monitor tab and connect if option is enabled
        if (_monitorAfterFlash) {
          // Small delay to let the device boot
          await Future.delayed(const Duration(milliseconds: 500));
          _tabController.animateTo(2); // Monitor tab
          // Connect to monitor after a short delay
          Future.delayed(const Duration(milliseconds: 300), () {
            _monitorKey.currentState?.connect();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _flashProgress = FlashProgress.error(e.toString());
        });
        _showError('Flash failed: $e');

        // Reconnect monitor if it was connected before and flash failed
        if (_monitorWasConnected) {
          await Future.delayed(const Duration(milliseconds: 500));
          _monitorKey.currentState?.connect();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFlashing = false;
        });
      }
    }
  }

  Future<void> _flashMultipleDevices(
    List<PortInfo> ports,
    String? firmwarePath,
  ) async {
    // Track results
    final results = <String, bool>{};
    final errors = <String, String>{};

    try {
      // Flash all devices in parallel
      final futures = ports.map((port) async {
        try {
          await _flasherService.flashDevice(
            device: _selectedDevice!,
            portPath: port.path,
            firmwarePath: firmwarePath,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _multiFlashProgress[port.path] = progress;
                });
              }
            },
          );
          results[port.path] = true;
        } catch (e) {
          results[port.path] = false;
          errors[port.path] = e.toString();
          if (mounted) {
            setState(() {
              _multiFlashProgress[port.path] = FlashProgress.error(e.toString());
            });
          }
        }
      });

      await Future.wait(futures);

      if (mounted) {
        final successCount = results.values.where((v) => v).length;
        final failCount = results.values.where((v) => !v).length;

        if (failCount == 0) {
          _showSuccess('All $successCount devices flashed successfully!');
        } else if (successCount == 0) {
          _showError('All $failCount devices failed to flash');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$successCount succeeded, $failCount failed',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Switch to monitor tab if option is enabled and at least one succeeded
        if (_monitorAfterFlash && successCount > 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          _tabController.animateTo(2);
          Future.delayed(const Duration(milliseconds: 300), () {
            _monitorKey.currentState?.connect();
          });
        }

        // Reconnect monitor if it was connected before and all failed
        if (successCount == 0 && _monitorWasConnected) {
          await Future.delayed(const Duration(milliseconds: 500));
          _monitorKey.currentState?.connect();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFlashing = false;
        });
      }
    }
  }

  Widget _buildMultiFlashProgress() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flashing ${_multiFlashProgress.length} devices',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._multiFlashProgress.entries.map((entry) {
              final portPath = entry.key;
              final progress = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          progress.isCompleted
                              ? Icons.check_circle
                              : progress.isError
                                  ? Icons.error
                                  : Icons.flash_on,
                          size: 16,
                          color: progress.isCompleted
                              ? Colors.green
                              : progress.isError
                                  ? Colors.red
                                  : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          portPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        Text(
                          progress.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: progress.isError
                                ? Colors.red
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    if (!progress.isCompleted && !progress.isError) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress.progress,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_flasherScrollController.hasClients) {
        _flasherScrollController.animateTo(
          _flasherScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
            Tab(text: 'Monitor', icon: Icon(Icons.terminal)),
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
                _buildMonitorTab(),
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

  Widget _buildMonitorTab() {
    return SerialMonitorWidget(
      key: _monitorKey,
      ports: _ports,
      selectedPort: _selectedPort,
      onPortChanged: (port) {
        setState(() {
          _selectedPort = port;
        });
      },
      onRefreshPorts: _refreshPorts,
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
      controller: _flasherScrollController,
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
          if (_isFlashing || _flashProgress != null || _multiFlashProgress.isNotEmpty) ...[
            Text(
              'Progress',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_multiFlashProgress.isNotEmpty)
              _buildMultiFlashProgress()
            else
              FlashProgressWidget(
                progress: _flashProgress ?? FlashProgress(),
              ),
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 16),

          // Flash button
          Center(
            child: ElevatedButton.icon(
              onPressed: _isFlashing ||
                      _selectedDevice == null ||
                      (_selectedPorts.isEmpty && _selectedPort == null)
                  ? null
                  : _startFlash,
              icon: _isFlashing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flash_on),
              label: Text(_isFlashing
                  ? 'Flashing...'
                  : _selectedPorts.length > 1
                      ? 'Flash ${_selectedPorts.length} Devices'
                      : 'Flash Device'),
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

  /// Get all ESP32 ports from the available ports
  List<PortInfo> _getEsp32Ports() {
    return _ports.where((port) {
      // Check for Espressif native USB (VID 0x303A)
      if (port.vid == 0x303A) return true;
      // Check for common USB-UART bridges
      return Esp32UsbIdentifiers.matchEsp32(port) != null;
    }).toList();
  }

  Widget _buildPortSelector() {
    final esp32Ports = _getEsp32Ports();
    final hasMultipleEsp32 = esp32Ports.length > 1;

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
            else if (hasMultipleEsp32) ...[
              // Multiple ESP32s detected - show multi-select UI
              Text(
                '${esp32Ports.length} ESP32 devices detected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select devices to flash:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              ...esp32Ports.map((port) {
                final isSelected = _selectedPorts.contains(port);
                final esp32Type = Esp32UsbIdentifiers.matchEsp32(port);

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: _isFlashing
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selectedPorts.add(port);
                            } else {
                              _selectedPorts.remove(port);
                            }
                            // Keep _selectedPort in sync for monitor tab
                            if (_selectedPorts.isNotEmpty) {
                              _selectedPort = _selectedPorts.first;
                            } else {
                              _selectedPort = null;
                            }
                          });
                        },
                  title: Text(port.path),
                  subtitle: Text(esp32Type ?? port.product ?? 'ESP32'),
                  secondary: Container(
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
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _isFlashing
                        ? null
                        : () {
                            setState(() {
                              _selectedPorts = List.from(esp32Ports);
                              _selectedPort = _selectedPorts.isNotEmpty
                                  ? _selectedPorts.first
                                  : null;
                            });
                          },
                    child: const Text('Select All'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isFlashing
                        ? null
                        : () {
                            setState(() {
                              _selectedPorts.clear();
                              _selectedPort = null;
                            });
                          },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ] else
              DropdownButtonFormField<PortInfo>(
                // Use value only if port is still in the list
                value: _ports.contains(_selectedPort) ? _selectedPort : null,
                isExpanded: true,
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
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                    // Keep _selectedPorts in sync
                    _selectedPorts.clear();
                    if (port != null) {
                      _selectedPorts.add(port);
                    }
                  });
                },
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refreshPorts,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Ports'),
            ),
            const Divider(height: 24),
            // Open monitor after flash option
            CheckboxListTile(
              value: _monitorAfterFlash,
              onChanged: _isFlashing
                  ? null
                  : (value) {
                      setState(() {
                        _monitorAfterFlash = value ?? true;
                      });
                    },
              title: const Text('Open monitor after flash'),
              subtitle: const Text('Switch to Monitor tab to see device output'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
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
