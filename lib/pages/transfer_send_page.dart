import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/devices_service.dart';
import '../transfer/services/p2p_transfer_service.dart';
import '../widgets/file_folder_picker.dart';
import 'transfer_page.dart';
import 'transfer_send_scan_page.dart';

/// Represents a recipient for file transfer
class Recipient {
  final String callsign;
  final String? nickname;
  final String? npub;
  final Map<String, dynamic> connections;

  const Recipient({
    required this.callsign,
    this.nickname,
    this.npub,
    this.connections = const {},
  });

  /// Display format: "Nickname (CALLSIGN)" or just "CALLSIGN"
  String get displayLabel =>
      nickname != null ? '$nickname ($callsign)' : callsign;

  List<String> get availableConnections {
    final list = <String>[];
    if (connections['ble'] == true) list.add('BLE');
    if (connections['lan'] == true) list.add('LAN');
    if (connections['usb'] == true) list.add('USB');
    if (connections['internet'] != null) list.add('Internet');
    return list;
  }

  factory Recipient.fromQrJson(Map<String, dynamic> json) {
    return Recipient(
      callsign: json['callsign'] as String,
      nickname: json['nickname'] as String?,
      npub: json['npub'] as String?,
      connections: json['connections'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Create a recipient from manually entered callsign (no connection info)
  factory Recipient.fromCallsign(String callsign) {
    return Recipient(callsign: callsign.toUpperCase());
  }

  /// Create a recipient from a RemoteDevice
  factory Recipient.fromRemoteDevice(RemoteDevice device) {
    // Build connections map from device's connectionMethods
    final connections = <String, dynamic>{};
    for (final method in device.connectionMethods) {
      switch (method.toLowerCase()) {
        case 'ble':
          connections['ble'] = true;
          break;
        case 'lan':
        case 'wifi':
          connections['lan'] = true;
          break;
        case 'usb':
          connections['usb'] = true;
          break;
        case 'station':
        case 'internet':
          connections['internet'] = {'station': device.url};
          break;
      }
    }

    return Recipient(
      callsign: device.callsign,
      nickname: device.nickname,
      npub: device.npub,
      connections: connections,
    );
  }
}

/// Represents a selected item (file or folder) to send
class SendItem {
  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;

  const SendItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
  });
}

/// Page for selecting files and folders to send
class TransferSendPage extends StatefulWidget {
  const TransferSendPage({super.key});

  /// Remember last used recipient (in RAM only, not persisted)
  static String? _lastRecipientCallsign;

  @override
  State<TransferSendPage> createState() => _TransferSendPageState();
}

class _TransferSendPageState extends State<TransferSendPage> {
  final List<SendItem> _items = [];
  Recipient? _recipient;
  final _callsignController = TextEditingController();
  bool _isCalculatingSize = false;

  // Device discovery
  final DevicesService _devicesService = DevicesService();
  StreamSubscription<List<RemoteDevice>>? _devicesSubscription;
  List<RemoteDevice> _reachableDevices = [];

  int get _totalBytes => _items.fold(0, (sum, item) => sum + item.sizeBytes);
  bool get _canSend => _recipient != null && _items.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initDevicesService();
  }

  Future<void> _initDevicesService() async {
    // Load initial devices from cache
    // Filter to only devices with actual connection methods (excludes ghost devices)
    _reachableDevices = _devicesService
        .getAllDevices()
        .where((d) => d.isOnline && d.connectionMethods.isNotEmpty)
        .toList();
    if (mounted) setState(() {});

    // Restore last used recipient if available
    _restoreLastRecipient();

    // Trigger device discovery (same as Devices UI does)
    _devicesService.refreshAllDevices();

    // Subscribe to device updates
    // Filter to only devices with actual connection methods (excludes ghost devices)
    _devicesSubscription = _devicesService.devicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _reachableDevices = devices
              .where((d) => d.isOnline && d.connectionMethods.isNotEmpty)
              .toList();
        });
        // Re-check last recipient in case device info became available
        if (_recipient == null && TransferSendPage._lastRecipientCallsign != null) {
          _restoreLastRecipient();
        }
      }
    });
  }

  /// Restore last used recipient from static cache
  void _restoreLastRecipient() {
    final lastCallsign = TransferSendPage._lastRecipientCallsign;
    if (lastCallsign == null || lastCallsign.isEmpty) return;

    // Try to find matching device for richer recipient info
    final matchingDevice = _reachableDevices.firstWhere(
      (d) => d.callsign.toUpperCase() == lastCallsign.toUpperCase(),
      orElse: () => RemoteDevice(callsign: '', name: '', apps: []),
    );

    if (matchingDevice.callsign.isNotEmpty) {
      _recipient = Recipient.fromRemoteDevice(matchingDevice);
      _callsignController.text = _recipient!.displayLabel;
    } else {
      // Use plain callsign if device not found
      _recipient = Recipient.fromCallsign(lastCallsign);
      _callsignController.text = lastCallsign;
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _callsignController.dispose();
    super.dispose();
  }

  /// Filter devices based on search query (matches callsign or nickname)
  List<RemoteDevice> _filterDevices(String query) {
    if (query.isEmpty) return _reachableDevices;

    final upperQuery = query.toUpperCase();
    final lowerQuery = query.toLowerCase();

    return _reachableDevices.where((device) {
      // Match callsign
      if (device.callsign.toUpperCase().contains(upperQuery)) return true;
      // Match nickname
      if (device.nickname?.toLowerCase().contains(lowerQuery) ?? false) {
        return true;
      }
      // Match display name
      if (device.displayName.toLowerCase().contains(lowerQuery)) return true;
      return false;
    }).toList();
  }

  void _selectDevice(RemoteDevice device) {
    final recipient = Recipient.fromRemoteDevice(device);
    _callsignController.text = recipient.displayLabel;
    setState(() => _recipient = recipient);
  }

  void _setRecipientFromCallsign(String callsign) {
    if (callsign.trim().isEmpty) {
      setState(() => _recipient = null);
    } else {
      // Check if this matches an existing device
      final matchingDevice = _reachableDevices.firstWhere(
        (d) =>
            d.callsign.toUpperCase() == callsign.trim().toUpperCase() ||
            d.nickname?.toLowerCase() == callsign.trim().toLowerCase(),
        orElse: () => RemoteDevice(
          callsign: '',
          name: '',
          apps: [],
        ),
      );

      if (matchingDevice.callsign.isNotEmpty) {
        setState(() => _recipient = Recipient.fromRemoteDevice(matchingDevice));
      } else {
        setState(() => _recipient = Recipient.fromCallsign(callsign.trim()));
      }
    }
  }

  void _clearRecipient() {
    _callsignController.clear();
    setState(() => _recipient = null);
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<Recipient>(
      context,
      MaterialPageRoute(
        builder: (context) => const TransferSendScanPage(),
      ),
    );

    if (result != null && mounted) {
      _callsignController.text = result.displayLabel;
      setState(() => _recipient = result);
    }
  }

  Future<void> _addItems() async {
    try {
      final paths = await FileFolderPicker.show(
        context,
        title: 'Select files or folders',
        allowMultiSelect: true,
      );

      if (paths == null || paths.isEmpty) return;

      setState(() => _isCalculatingSize = true);

      for (final itemPath in paths) {
        // Check if already added
        if (_items.any((item) => item.path == itemPath)) continue;

        // Check if it's a directory
        final isDir = await FileSystemEntity.isDirectory(itemPath);
        final name = itemPath.split(Platform.pathSeparator).last;

        SendItem newItem;
        if (isDir) {
          // Calculate folder size
          final size = await _calculateDirectorySize(itemPath);
          newItem = SendItem(
            path: itemPath,
            name: name,
            isDirectory: true,
            sizeBytes: size,
          );
        } else {
          final file = File(itemPath);
          final size = await file.length();
          newItem = SendItem(
            path: itemPath,
            name: name,
            isDirectory: false,
            sizeBytes: size,
          );
        }

        if (mounted) {
          setState(() => _items.add(newItem));
        }
      }

      if (mounted) {
        setState(() => _isCalculatingSize = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCalculatingSize = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting items: $e')),
        );
      }
    }
  }

  Future<int> _calculateDirectorySize(String path) async {
    int totalSize = 0;
    try {
      final dir = Directory(path);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (_) {
      // Ignore permission errors
    }
    return totalSize;
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _clearAll() {
    _callsignController.clear();
    setState(() {
      _items.clear();
      _recipient = null;
    });
  }

  bool _isSending = false;

  Future<void> _onSend() async {
    if (!_canSend || _isSending) return;

    setState(() => _isSending = true);

    try {
      final offer = await P2PTransferService().sendOffer(
        recipientCallsign: _recipient!.callsign,
        items: _items,
      );

      if (offer != null && mounted) {
        // Remember recipient for next send operation
        TransferSendPage._lastRecipientCallsign = _recipient!.callsign;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Offer sent to ${_recipient!.callsign}. '
              'Waiting for acceptance...',
            ),
          ),
        );

        // Navigate to transfer page to see pending offer
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TransferPage()),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send offer. Please try again.'),
          ),
        );
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send'),
        actions: [
          if (_items.isNotEmpty || _recipient != null)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // Recipient section
          _buildRecipientSection(theme),

          // Add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCalculatingSize ? null : _addItems,
                icon: _isCalculatingSize
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Items list or empty state
          Expanded(
            child: _items.isEmpty
                ? _buildEmptyState(theme)
                : _buildItemsList(theme),
          ),

          // Bottom summary and send button
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  Widget _buildRecipientSection(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send to',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Autocomplete<RemoteDevice>(
                    optionsBuilder: (textEditingValue) {
                      return _filterDevices(textEditingValue.text);
                    },
                    displayStringForOption: (device) {
                      return device.nickname != null
                          ? '${device.nickname} (${device.callsign})'
                          : device.callsign;
                    },
                    onSelected: _selectDevice,
                    fieldViewBuilder: (
                      context,
                      controller,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      // Sync with our controller when text changes externally
                      if (_callsignController.text.isNotEmpty &&
                          controller.text != _callsignController.text) {
                        controller.text = _callsignController.text;
                      }

                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: 'Enter callsign or nickname...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    _clearRecipient();
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          _callsignController.text = value;
                          _setRecipientFromCallsign(value);
                        },
                        onSubmitted: (_) => onFieldSubmitted(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 300,
                              maxWidth: 350,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final device = options.elementAt(index);
                                return _buildDeviceOption(
                                  theme,
                                  device,
                                  () => onSelected(device),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ],
            ),
            if (_recipient != null) ...[
              const SizedBox(height: 12),
              _buildRecipientDisplay(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceOption(
    ThemeData theme,
    RemoteDevice device,
    VoidCallback onTap,
  ) {
    final hasNickname = device.nickname != null;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Online indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: device.isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary: nickname or callsign
                    Text(
                      hasNickname ? device.nickname! : device.callsign,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Secondary: callsign if nickname exists, or connection info
                    if (hasNickname)
                      Text(
                        device.callsign,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),
              // Connection methods
              if (device.connectionMethods.isNotEmpty)
                Text(
                  device.connectionMethods.take(2).join(' • '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipientDisplay(ThemeData theme) {
    final connections = _recipient!.availableConnections;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipient!.displayLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (connections.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    connections.join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: theme.colorScheme.error, size: 20),
            onPressed: _clearRecipient,
            tooltip: 'Clear recipient',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.upload_file,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No files selected',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add files or folders to send',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (item.isDirectory ? Colors.amber : Colors.blue)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                item.isDirectory ? Icons.folder : _getFileIcon(item.name),
                color: item.isDirectory ? Colors.amber : Colors.blue,
              ),
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.isDirectory
                  ? 'Folder - ${_formatBytes(item.sizeBytes)}'
                  : _formatBytes(item.sizeBytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.close, color: theme.colorScheme.error),
              onPressed: () => _removeItem(index),
              tooltip: 'Remove',
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary row
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_items.length} ${_items.length == 1 ? 'item' : 'items'} selected',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total size: ${_formatBytes(_totalBytes)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _canSend && !_isSending ? _onSend : null,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSending ? 'Sending...' : 'Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'aac':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }
}

/// Text input formatter that converts all input to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
