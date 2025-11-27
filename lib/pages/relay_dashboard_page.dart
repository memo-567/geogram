/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/relay_node.dart';
import '../services/relay_node_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import 'relay_setup_root_page.dart';
import 'relay_setup_node_page.dart';
import 'relay_settings_page.dart';
import 'relay_logs_page.dart';
import 'relay_authorities_page.dart';
import 'relay_topology_page.dart';

/// Dashboard for managing relay node
class RelayDashboardPage extends StatefulWidget {
  const RelayDashboardPage({super.key});

  @override
  State<RelayDashboardPage> createState() => _RelayDashboardPageState();
}

class _RelayDashboardPageState extends State<RelayDashboardPage> {
  final RelayNodeService _relayNodeService = RelayNodeService();
  final I18nService _i18n = I18nService();

  StreamSubscription<RelayNode?>? _subscription;
  RelayNode? _relayNode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _relayNodeService.initialize();

    _subscription = _relayNodeService.stateStream.listen((node) {
      if (mounted) {
        setState(() => _relayNode = node);
      }
    });

    setState(() {
      _relayNode = _relayNodeService.relayNode;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Relay')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_relayNode == null) {
      return _buildSetupView();
    }

    return _buildDashboardView();
  }

  Widget _buildSetupView() {
    return Scaffold(
      appBar: AppBar(title: Text('Relay')),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 500),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cell_tower, size: 80, color: Colors.grey),
              SizedBox(height: 24),
              Text(
                'Enable Relay Mode',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 8),
              Text(
                'Turn this device into a relay node to help connect other devices across networks.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildSetupCard(
                      icon: Icons.hub,
                      title: 'Root Relay',
                      description: 'Create a new relay network. You become the network owner.',
                      buttonText: 'Create Network',
                      onTap: _createRootRelay,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _buildSetupCard(
                      icon: Icons.device_hub,
                      title: 'Node Relay',
                      description: 'Join an existing relay network. Extend network coverage.',
                      buttonText: 'Join Network',
                      onTap: _joinAsNode,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.white),
            SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: onTap,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Relay Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Connected Devices', '${_relayNode!.stats.connectedDevices}', Icons.devices)),
                SizedBox(width: 16),
                Expanded(child: _buildStatCard('Messages Relayed', '${_relayNode!.stats.messagesRelayed}', Icons.message)),
              ],
            ),
            SizedBox(height: 16),
            _buildStorageCard(),
            SizedBox(height: 16),
            _buildChannelsCard(),
            SizedBox(height: 16),
            _buildActionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isRunning = _relayNode!.isRunning;
    final statusColor = isRunning ? Colors.green : Colors.grey;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'RELAY STATUS: ${_relayNode!.statusDisplay.toUpperCase()}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                Switch(
                  value: isRunning,
                  onChanged: _toggleRelay,
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Type: ${_relayNode!.typeDisplay}'),
            Text('Network: ${_relayNode!.networkName ?? "N/A"}'),
            if (_relayNode!.isRunning)
              Text('Uptime: ${_formatUptime(_relayNode!.stats.uptime)}'),
            if (_relayNode!.errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Error: ${_relayNode!.errorMessage}',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.white),
            SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageCard() {
    final used = _relayNode!.stats.storageUsedMb;
    final allocated = _relayNode!.config.storage.allocatedMb;
    final percent = allocated > 0 ? (used / allocated).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STORAGE', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: percent,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                SizedBox(width: 16),
                Text('${(percent * 100).toStringAsFixed(0)}%'),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Used: ${_formatStorage(used)} / ${_formatStorage(allocated)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            SizedBox(height: 4),
            Text(
              'Policy: ${_relayNode!.config.storage.binaryPolicy.name}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsCard() {
    final channels = _relayNode!.config.channels;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CHANNELS', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (channels.isEmpty)
              Text('No channels configured', style: TextStyle(color: Colors.grey))
            else
              ...channels.map((ch) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _getChannelIcon(ch.type),
                      size: 20,
                      color: ch.enabled ? Colors.green : Colors.grey,
                    ),
                    SizedBox(width: 8),
                    Text(ch.type),
                    Spacer(),
                    Text(
                      ch.enabled ? 'Active' : 'Off',
                      style: TextStyle(
                        color: ch.enabled ? Colors.green : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )),
            // Show default channels if none configured
            if (channels.isEmpty) ...[
              _buildDefaultChannelRow('Internet', true),
              _buildDefaultChannelRow('WiFi LAN', true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultChannelRow(String name, bool active) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.wifi,
            size: 20,
            color: active ? Colors.green : Colors.grey,
          ),
          SizedBox(width: 8),
          Text(name),
          Spacer(),
          Text(
            active ? 'Active' : 'Off',
            style: TextStyle(
              color: active ? Colors.green : Colors.grey,
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

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RelayLogsPage()),
                    );
                  },
                  icon: Icon(Icons.article),
                  label: Text('View Logs'),
                ),
                if (_relayNode!.isRoot)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RelayAuthoritiesPage()),
                      );
                    },
                    icon: Icon(Icons.admin_panel_settings),
                    label: Text('Manage Authorities'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RelayTopologyPage()),
                    );
                  },
                  icon: Icon(Icons.account_tree),
                  label: Text('Network Topology'),
                ),
                OutlinedButton.icon(
                  onPressed: _confirmDeleteRelay,
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  label: Text('Delete Relay', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _createRootRelay() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RelaySetupRootPage()),
    );
    if (result == true) {
      setState(() => _relayNode = _relayNodeService.relayNode);
    }
  }

  void _joinAsNode() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RelaySetupNodePage()),
    );
    if (result == true) {
      setState(() => _relayNode = _relayNodeService.relayNode);
    }
  }

  void _toggleRelay(bool enabled) async {
    try {
      if (enabled) {
        await _relayNodeService.start();
      } else {
        await _relayNodeService.stop();
      }
    } catch (e) {
      LogService().log('Error toggling relay: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RelaySettingsPage()),
    );
  }

  void _confirmDeleteRelay() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Relay?'),
        content: Text(
          'This will delete all relay configuration and data. '
          'If this is a root relay, the network will be destroyed. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _relayNodeService.deleteRelay();
              setState(() => _relayNode = null);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Relay deleted')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatUptime(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatStorage(int mb) {
    if (mb >= 1000) {
      return '${(mb / 1000).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}
