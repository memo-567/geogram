import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../connection/connection_manager.dart';
import '../services/profile_service.dart';
import '../services/station_service.dart';

/// Full-screen page displaying a QR code with the user's connection info
class TransferReceivePage extends StatefulWidget {
  const TransferReceivePage({super.key});

  @override
  State<TransferReceivePage> createState() => _TransferReceivePageState();
}

class _TransferReceivePageState extends State<TransferReceivePage> {
  String _qrData = '';
  String _callsign = '';
  String _npub = '';
  Map<String, dynamic> _connections = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConnectionInfo();
  }

  Future<void> _loadConnectionInfo() async {
    // Get callsign and npub from ProfileService
    final profile = ProfileService().getProfile();
    final callsign = profile.callsign;
    final npub = profile.npub;

    // Get available transports from ConnectionManager
    final connManager = ConnectionManager();
    final transports = connManager.availableTransports;

    // Get station URL
    final stationService = StationService();
    final station = stationService.isInitialized
        ? stationService.getPreferredStation()
        : null;

    // Build connections map
    final connections = <String, dynamic>{};
    for (final transport in transports) {
      if (transport.id == 'station' && station != null && station.url.isNotEmpty) {
        connections['internet'] = {'station': station.url};
      } else if (transport.id == 'ble') {
        connections['ble'] = true;
      } else if (transport.id == 'lan') {
        connections['lan'] = true;
      } else if (transport.id == 'usb_aoa') {
        connections['usb'] = true;
      }
    }

    // Build QR data
    final qrJson = jsonEncode({
      'geogram': '1.0',
      'callsign': callsign,
      'npub': npub,
      'connections': connections,
    });

    setState(() {
      _callsign = callsign;
      _npub = npub;
      _connections = connections;
      _qrData = qrJson;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _qrData,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Callsign
                  Text(
                    _callsign,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Connection methods
                  _buildConnectionsList(theme),
                  const SizedBox(height: 24),

                  // Manual instructions
                  _buildManualInstructions(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectionsList(ThemeData theme) {
    if (_connections.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No connection methods available',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Available connections',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_connections.containsKey('ble'))
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Bluetooth Low Energy'),
              subtitle: const Text('Close range, no internet required'),
              dense: true,
            ),
          if (_connections.containsKey('lan'))
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Local Network'),
              subtitle: const Text('Same WiFi network'),
              dense: true,
            ),
          if (_connections.containsKey('usb'))
            ListTile(
              leading: const Icon(Icons.usb),
              title: const Text('USB'),
              subtitle: const Text('Direct USB connection'),
              dense: true,
            ),
          if (_connections.containsKey('internet'))
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Internet'),
              subtitle: Text(
                (_connections['internet'] as Map?)?['station'] ?? 'Station relay',
              ),
              dense: true,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildManualInstructions(ThemeData theme) {
    final connectionDescriptions = <String>[];
    if (_connections.containsKey('ble')) {
      connectionDescriptions.add('BLE');
    }
    if (_connections.containsKey('lan')) {
      connectionDescriptions.add('LAN');
    }
    if (_connections.containsKey('usb')) {
      connectionDescriptions.add('USB');
    }
    if (_connections.containsKey('internet')) {
      final station = (_connections['internet'] as Map?)?['station'] as String?;
      if (station != null) {
        connectionDescriptions.add('Internet ($station)');
      } else {
        connectionDescriptions.add('Internet');
      }
    }

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'No camera? Share this info manually:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Callsign: $_callsign',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            if (connectionDescriptions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Connections: ${connectionDescriptions.join(', ')}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _qrData));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Connection info copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy connection info'),
            ),
          ],
        ),
      ),
    );
  }
}
