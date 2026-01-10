/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/station_node.dart';
import '../services/station_node_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import 'station_setup_root_page.dart';
import 'station_settings_page.dart';
import 'station_logs_page.dart';
import 'station_authorities_page.dart';
import 'station_topology_page.dart';

/// Dashboard for managing station node
class StationDashboardPage extends StatefulWidget {
  const StationDashboardPage({super.key});

  @override
  State<StationDashboardPage> createState() => _RelayDashboardPageState();
}

class _RelayDashboardPageState extends State<StationDashboardPage> {
  final StationNodeService _stationNodeService = StationNodeService();
  final I18nService _i18n = I18nService();

  StreamSubscription<StationNode?>? _subscription;
  StationNode? _stationNode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _stationNodeService.initialize();

    _subscription = _stationNodeService.stateStream.listen((node) {
      if (mounted) {
        setState(() => _stationNode = node);
      }
    });

    setState(() {
      _stationNode = _stationNodeService.stationNode;
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
        appBar: AppBar(title: Text('Station')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_stationNode == null) {
      return _buildSetupView();
    }

    return _buildDashboardView();
  }

  Widget _buildSetupView() {
    return Scaffold(
      appBar: AppBar(title: Text('Station')),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 400),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cell_tower, size: 80, color: Colors.grey),
              SizedBox(height: 24),
              Text(
                'Enable Station Mode',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: 8),
              Text(
                'Turn this device into a station to help connect other devices across networks.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _createRootRelay,
                icon: Icon(Icons.hub),
                label: Text('Create Station'),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Station Dashboard'),
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
            // Show URLs card only when server is actually running
            if (_stationNodeService.stationServer?.isRunning == true) ...[
              _buildUrlsCard(),
              SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(child: _buildStatCard('Connected Devices', '${_stationNode!.stats.connectedDevices}', Icons.devices)),
                SizedBox(width: 16),
                Expanded(child: _buildStatCard('Messages Relayed', '${_stationNode!.stats.messagesRelayed}', Icons.message)),
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
    // Check actual server state, not just node status
    final server = _stationNodeService.stationServer;
    final isActuallyRunning = server != null && server.isRunning;
    final nodeThinkRunning = _stationNode!.isRunning;

    // Use actual server state for display
    final isRunning = isActuallyRunning;
    final statusColor = isRunning ? Colors.green : Colors.grey;

    // If there's a mismatch, update the node status
    if (nodeThinkRunning && !isActuallyRunning) {
      // Node thinks it's running but server isn't - this is the bug
      LogService().log('Station status mismatch: node thinks running but server is not');
    }

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
                  'STATION STATUS: ${isRunning ? "RUNNING" : "STOPPED"}',
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
            Text('Type: ${_stationNode!.typeDisplay}'),
            Text('Network: ${_stationNode!.networkName ?? "N/A"}'),
            if (isRunning && server != null)
              Text('Port: ${server.settings.httpPort}'),
            if (isRunning)
              Text('Uptime: ${_formatUptime(_stationNode!.stats.uptime)}'),
            if (_stationNode!.errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Error: ${_stationNode!.errorMessage}',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlsCard() {
    final server = _stationNodeService.stationServer;
    if (server == null) return SizedBox.shrink();

    final httpPort = server.settings.httpPort;
    final httpsPort = server.settings.httpsPort;
    final enableSsl = server.settings.enableSsl;
    final sslDomain = server.settings.sslDomain;

    // Build list of available URLs
    final urls = <Map<String, String>>[];

    // Always add localhost HTTP
    urls.add({
      'label': 'Local (HTTP)',
      'url': 'http://localhost:$httpPort',
      'icon': 'local',
    });

    // Add local network IPs
    _getLocalIpAddresses().then((ips) {
      if (mounted && ips.isNotEmpty) {
        setState(() {}); // Trigger rebuild with IPs
      }
    });

    // If SSL is enabled and domain is configured
    if (enableSsl && sslDomain != null && sslDomain.isNotEmpty) {
      urls.add({
        'label': 'Public (HTTPS)',
        'url': 'https://$sslDomain:$httpsPort',
        'icon': 'secure',
      });
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 20),
                SizedBox(width: 8),
                Text('STATION URLs', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 12),
            ...urls.map((urlInfo) => _buildUrlRow(
              urlInfo['label']!,
              urlInfo['url']!,
              urlInfo['icon'] == 'secure' ? Icons.lock : Icons.computer,
            )),
            // Show LAN IPs
            FutureBuilder<List<String>>(
              future: _getLocalIpAddresses(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return SizedBox.shrink();
                }
                return Column(
                  children: snapshot.data!.map((ip) => _buildUrlRow(
                    'LAN ($ip)',
                    'http://$ip:$httpPort',
                    Icons.wifi,
                  )).toList(),
                );
              },
            ),
            SizedBox(height: 8),
            Text(
              'Click to open in browser, or copy to share',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlRow(String label, String url, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                InkWell(
                  onTap: () => _openUrl(url),
                  child: Text(
                    url,
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, size: 18),
            onPressed: () => _copyToClipboard(url),
            tooltip: 'Copy URL',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(Icons.open_in_new, size: 18),
            onPressed: () => _openUrl(url),
            tooltip: 'Open in browser',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open URL')),
        );
      }
    } catch (e) {
      LogService().log('Error opening URL: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening URL: $e')),
      );
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
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
    final used = _stationNode!.stats.storageUsedMb;
    final allocated = _stationNode!.config.storage.allocatedMb;
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
              'Policy: ${_stationNode!.config.storage.binaryPolicy.name}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsCard() {
    final channels = _stationNode!.config.channels;

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
                      MaterialPageRoute(builder: (_) => StationLogsPage()),
                    );
                  },
                  icon: Icon(Icons.article),
                  label: Text('View Logs'),
                ),
                if (_stationNode!.isRoot)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => StationAuthoritiesPage()),
                      );
                    },
                    icon: Icon(Icons.admin_panel_settings),
                    label: Text('Manage Authorities'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StationTopologyPage()),
                    );
                  },
                  icon: Icon(Icons.account_tree),
                  label: Text('Network Topology'),
                ),
                OutlinedButton.icon(
                  onPressed: _confirmDeleteRelay,
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  label: Text('Delete Station', style: TextStyle(color: Colors.red)),
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
      MaterialPageRoute(builder: (_) => StationSetupRootPage()),
    );
    if (result == true) {
      setState(() => _stationNode = _stationNodeService.stationNode);
    }
  }

  void _toggleRelay(bool enabled) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text(enabled ? 'Starting station...' : 'Stopping station...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      if (enabled) {
        await _stationNodeService.start();

        // Verify it actually started
        final server = _stationNodeService.stationServer;
        if (server == null || !server.isRunning) {
          final networkSettings = await _stationNodeService.loadNetworkSettings();
          final port = networkSettings['httpPort'] ?? 'unknown';
          throw Exception('Server failed to start. Check if port $port is already in use.');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Station started on port ${server.settings.httpPort}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await _stationNodeService.stop();

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Station stopped'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Force UI refresh
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      LogService().log('Error toggling station: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StationSettingsPage()),
    );
  }

  void _confirmDeleteRelay() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Station?'),
        content: Text(
          'This will delete all station configuration and data. '
          'If this is a root station, the network will be destroyed. '
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
              await _stationNodeService.deleteStation();
              setState(() => _stationNode = null);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Station deleted')),
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
