/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/relay_node.dart';
import '../services/relay_node_service.dart';
import '../services/log_service.dart';

/// Settings page for relay configuration
class RelaySettingsPage extends StatefulWidget {
  const RelaySettingsPage({super.key});

  @override
  State<RelaySettingsPage> createState() => _RelaySettingsPageState();
}

class _RelaySettingsPageState extends State<RelaySettingsPage> {
  final RelayNodeService _relayNodeService = RelayNodeService();

  late RelayNodeConfig _config;
  bool _isSaving = false;
  bool _hasChanges = false;

  // Storage settings
  late int _allocatedMb;
  late BinaryPolicy _binaryPolicy;
  late int _thumbnailMaxKb;
  late bool _foreverRetention;
  late int _retentionDays;
  late bool _foreverChatRetention;
  late int _chatRetentionDays;

  // Connection settings
  late bool _acceptConnections;
  late int _maxConnections;

  // Coverage settings
  double? _latitude;
  double? _longitude;
  late double _radiusKm;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final node = _relayNodeService.relayNode;
    if (node == null) return;

    _config = node.config;

    // Storage
    _allocatedMb = _config.storage.allocatedMb;
    _binaryPolicy = _config.storage.binaryPolicy;
    _thumbnailMaxKb = _config.storage.thumbnailMaxKb;
    _retentionDays = _config.storage.retentionDays;
    _foreverRetention = _retentionDays == 0;
    if (_retentionDays == 0) _retentionDays = 365; // Default for display
    _chatRetentionDays = _config.storage.chatRetentionDays;
    _foreverChatRetention = _chatRetentionDays == 0;
    if (_chatRetentionDays == 0) _chatRetentionDays = 90; // Default for display

    // Connections
    _acceptConnections = _config.acceptConnections;
    _maxConnections = _config.maxConnections;

    // Coverage
    _latitude = _config.coverage?.latitude;
    _longitude = _config.coverage?.longitude;
    _radiusKm = _config.coverage?.radiusKm ?? 50.0;
  }

  @override
  Widget build(BuildContext context) {
    final node = _relayNodeService.relayNode;
    if (node == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Relay Settings')),
        body: Center(child: Text('No relay configured')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Relay Settings'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Save', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(node),
            SizedBox(height: 16),
            _buildStorageSection(),
            SizedBox(height: 16),
            _buildConnectionsSection(),
            SizedBox(height: 16),
            _buildCoverageSection(),
            SizedBox(height: 16),
            _buildChannelsSection(node),
            SizedBox(height: 16),
            _buildCollectionsSection(node),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(RelayNode node) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RELAY IDENTITY', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            _buildInfoRow('Name', node.name),
            _buildInfoRow('Type', node.typeDisplay),
            _buildInfoRow('Relay (X3)', node.relayCallsign),
            _buildInfoRow('Relay NPUB', _truncateNpub(node.relayNpub)),
            SizedBox(height: 8),
            Divider(),
            SizedBox(height: 8),
            Text('OPERATOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600])),
            SizedBox(height: 8),
            _buildInfoRow('Operator (X1)', node.operatorCallsign),
            _buildInfoRow('Operator NPUB', _truncateNpub(node.operatorNpub)),
            SizedBox(height: 8),
            Divider(),
            SizedBox(height: 8),
            _buildInfoRow('Network', node.networkName ?? 'N/A'),
            _buildInfoRow('ID', node.id),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey[600]))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _truncateNpub(String npub) {
    if (npub.length > 20) {
      return '${npub.substring(0, 10)}...${npub.substring(npub.length - 8)}';
    }
    return npub;
  }

  Widget _buildStorageSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STORAGE', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Allocated Storage'),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _allocatedMb.toDouble(),
                    min: 50,
                    max: 10000,
                    divisions: 199,
                    label: _formatStorage(_allocatedMb),
                    onChanged: (value) {
                      setState(() {
                        _allocatedMb = value.round();
                        _hasChanges = true;
                      });
                    },
                  ),
                ),
                SizedBox(width: 16),
                Text(_formatStorage(_allocatedMb), style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                _buildPresetButton('50 MB', 50),
                _buildPresetButton('500 MB', 500),
                _buildPresetButton('1 GB', 1000),
                _buildPresetButton('5 GB', 5000),
                _buildPresetButton('10 GB', 10000),
              ],
            ),
            SizedBox(height: 24),
            Text('Binary Data Policy'),
            SizedBox(height: 8),
            SegmentedButton<BinaryPolicy>(
              segments: [
                ButtonSegment(value: BinaryPolicy.textOnly, label: Text('Text')),
                ButtonSegment(value: BinaryPolicy.thumbnailsOnly, label: Text('Thumbs')),
                ButtonSegment(value: BinaryPolicy.onDemand, label: Text('On-demand')),
                ButtonSegment(value: BinaryPolicy.fullCache, label: Text('Full')),
              ],
              selected: {_binaryPolicy},
              onSelectionChanged: (value) {
                setState(() {
                  _binaryPolicy = value.first;
                  _hasChanges = true;
                });
              },
            ),
            if (_binaryPolicy == BinaryPolicy.thumbnailsOnly) ...[
              SizedBox(height: 16),
              Row(
                children: [
                  Text('Max thumbnail size: '),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: 'KB',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      controller: TextEditingController(text: _thumbnailMaxKb.toString()),
                      onChanged: (v) {
                        _thumbnailMaxKb = int.tryParse(v) ?? 10;
                        _hasChanges = true;
                      },
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: 24),
            Text('Data Retention'),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Forum/Reports:')),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text('Forever'),
                      selected: _foreverRetention,
                      onSelected: (v) {
                        setState(() {
                          _foreverRetention = true;
                          _hasChanges = true;
                        });
                      },
                    ),
                    SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Limit'),
                      selected: !_foreverRetention,
                      onSelected: (v) {
                        setState(() {
                          _foreverRetention = false;
                          _hasChanges = true;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (!_foreverRetention)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 16),
                child: Row(
                  children: [
                    Text('Remove after: '),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: 'd',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        controller: TextEditingController(text: _retentionDays.toString()),
                        onChanged: (v) {
                          _retentionDays = int.tryParse(v) ?? 365;
                          _hasChanges = true;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Chat messages:')),
                Row(
                  children: [
                    ChoiceChip(
                      label: Text('Forever'),
                      selected: _foreverChatRetention,
                      onSelected: (v) {
                        setState(() {
                          _foreverChatRetention = true;
                          _hasChanges = true;
                        });
                      },
                    ),
                    SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Limit'),
                      selected: !_foreverChatRetention,
                      onSelected: (v) {
                        setState(() {
                          _foreverChatRetention = false;
                          _hasChanges = true;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (!_foreverChatRetention)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 16),
                child: Row(
                  children: [
                    Text('Remove after: '),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          suffixText: 'd',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        controller: TextEditingController(text: _chatRetentionDays.toString()),
                        onChanged: (v) {
                          _chatRetentionDays = int.tryParse(v) ?? 90;
                          _hasChanges = true;
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, int value) {
    final isSelected = _allocatedMb == value;
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _allocatedMb = value;
          _hasChanges = true;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildConnectionsSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONNECTIONS', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            SwitchListTile(
              title: Text('Accept incoming connections'),
              value: _acceptConnections,
              onChanged: (value) {
                setState(() {
                  _acceptConnections = value;
                  _hasChanges = true;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
            Row(
              children: [
                Expanded(child: Text('Max connections:')),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    controller: TextEditingController(text: _maxConnections.toString()),
                    onChanged: (v) {
                      _maxConnections = int.tryParse(v) ?? 50;
                      _hasChanges = true;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverageSection() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GEOGRAPHIC COVERAGE', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map, size: 32, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      _latitude != null
                          ? 'Center: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}'
                          : 'Location not set',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Text('Coverage Radius: '),
                Expanded(
                  child: Slider(
                    value: _radiusKm,
                    min: 5,
                    max: 500,
                    divisions: 99,
                    label: '${_radiusKm.round()} km',
                    onChanged: (v) {
                      setState(() {
                        _radiusKm = v;
                        _hasChanges = true;
                      });
                    },
                  ),
                ),
                Text('${_radiusKm.round()} km'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsSection(RelayNode node) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COMMUNICATION CHANNELS', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (node.config.channels.isEmpty)
              Text('Default channels active (Internet, WiFi LAN)', style: TextStyle(color: Colors.grey))
            else
              ...node.config.channels.map((ch) => _buildChannelRow(ch)),
            SizedBox(height: 8),
            Text(
              'Channel configuration requires app restart',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelRow(ChannelConfig channel) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _getChannelIcon(channel.type),
            size: 20,
            color: channel.enabled ? Colors.green : Colors.grey,
          ),
          SizedBox(width: 8),
          Expanded(child: Text(channel.type)),
          Text(
            channel.enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: channel.enabled ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getChannelIcon(String type) {
    switch (type) {
      case 'internet':
        return Icons.public;
      case 'wifi_lan':
        return Icons.wifi;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'lora':
        return Icons.settings_input_antenna;
      default:
        return Icons.device_hub;
    }
  }

  Widget _buildCollectionsSection(RelayNode node) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SUPPORTED COLLECTIONS', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: node.config.supportedCollections.map((c) => Chip(
                label: Text(c),
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              )).toList(),
            ),
            SizedBox(height: 8),
            Text(
              'Collection support is defined by the network',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      final newStorage = RelayStorageConfig(
        allocatedMb: _allocatedMb,
        binaryPolicy: _binaryPolicy,
        thumbnailMaxKb: _thumbnailMaxKb,
        retentionDays: _foreverRetention ? 0 : _retentionDays,
        chatRetentionDays: _foreverChatRetention ? 0 : _chatRetentionDays,
      );

      GeographicCoverage? newCoverage;
      if (_latitude != null && _longitude != null) {
        newCoverage = GeographicCoverage(
          latitude: _latitude!,
          longitude: _longitude!,
          radiusKm: _radiusKm,
        );
      }

      final newConfig = _config.copyWith(
        storage: newStorage,
        coverage: newCoverage,
        acceptConnections: _acceptConnections,
        maxConnections: _maxConnections,
      );

      await _relayNodeService.updateConfig(newConfig);

      setState(() {
        _config = newConfig;
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      LogService().log('Error saving relay settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatStorage(int mb) {
    if (mb >= 1000) {
      return '${(mb / 1000).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}
