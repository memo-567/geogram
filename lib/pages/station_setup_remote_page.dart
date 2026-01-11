/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/station_node_service.dart';
import '../services/log_service.dart';
import '../util/nostr_crypto.dart';

/// Page for connecting to a remote station server
class StationSetupRemotePage extends StatefulWidget {
  const StationSetupRemotePage({super.key});

  @override
  State<StationSetupRemotePage> createState() => _StationSetupRemotePageState();
}

class _StationSetupRemotePageState extends State<StationSetupRemotePage> {
  final StationNodeService _stationNodeService = StationNodeService();

  final _urlController = TextEditingController();
  final _nsecController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isTestingConnection = false;
  bool _isConnecting = false;
  bool _connectionTested = false;
  bool _connectionSuccess = false;
  bool _obscureNsec = true;
  String? _testError;
  Map<String, dynamic>? _remoteStatus;

  @override
  void dispose() {
    _urlController.dispose();
    _nsecController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Remote Station'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[400], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connect to a station server running on another device (e.g., a Linux server). '
                      'You\'ll need the station URL and its NSEC (private key) for authentication.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // URL field
            const Text('Station URL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://station.example.com or wss://station.example.com',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
              onChanged: (_) => _resetConnectionTest(),
            ),
            const SizedBox(height: 16),

            // NSEC field
            const Text('Station NSEC', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _nsecController,
              obscureText: _obscureNsec,
              decoration: InputDecoration(
                hintText: 'nsec1...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNsec ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureNsec = !_obscureNsec),
                ),
              ),
              onChanged: (_) => _resetConnectionTest(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[400], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keep your NSEC private. It grants full control over the station.',
                      style: TextStyle(fontSize: 11, color: Colors.orange[300]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Name field (optional)
            const Text('Display Name (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'e.g., My Cloud Server',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
            ),
            const SizedBox(height: 24),

            // Test connection button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTestingConnection ? null : _testConnection,
                icon: _isTestingConnection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
              ),
            ),
            const SizedBox(height: 16),

            // Connection status
            if (_connectionTested) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _connectionSuccess
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _connectionSuccess
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _connectionSuccess ? Icons.check_circle : Icons.error,
                          color: _connectionSuccess ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _connectionSuccess ? 'Connection successful!' : 'Connection failed',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _connectionSuccess ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    if (_connectionSuccess && _remoteStatus != null) ...[
                      const SizedBox(height: 8),
                      Text('Name: ${_remoteStatus!['name'] ?? 'Unknown'}'),
                      Text('Version: ${_remoteStatus!['version'] ?? 'Unknown'}'),
                      Text('Callsign: ${_remoteStatus!['callsign'] ?? 'Unknown'}'),
                      if (_remoteStatus!['connected_devices'] != null)
                        Text('Connected devices: ${_remoteStatus!['connected_devices']}'),
                    ],
                    if (!_connectionSuccess && _testError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _testError!,
                        style: TextStyle(color: Colors.red[300], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Connect button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_connectionSuccess && !_isConnecting) ? _connect : null,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_link),
                label: Text(_isConnecting ? 'Connecting...' : 'Connect Station'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetConnectionTest() {
    if (_connectionTested) {
      setState(() {
        _connectionTested = false;
        _connectionSuccess = false;
        _testError = null;
        _remoteStatus = null;
      });
    }
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    final nsec = _nsecController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a station URL')),
      );
      return;
    }

    if (nsec.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the station NSEC')),
      );
      return;
    }

    // Validate NSEC format
    if (!nsec.startsWith('nsec1')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid NSEC format. It should start with "nsec1"')),
      );
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionTested = false;
      _testError = null;
    });

    try {
      // Convert URL to HTTP if needed for status check
      var statusUrl = url;
      if (statusUrl.startsWith('wss://')) {
        statusUrl = statusUrl.replaceFirst('wss://', 'https://');
      } else if (statusUrl.startsWith('ws://')) {
        statusUrl = statusUrl.replaceFirst('ws://', 'http://');
      }
      if (!statusUrl.endsWith('/')) {
        statusUrl += '/';
      }
      statusUrl += 'api/status';

      LogService().log('Testing connection to: $statusUrl');

      final response = await http.get(
        Uri.parse(statusUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final status = json.decode(response.body) as Map<String, dynamic>;

        // Verify NSEC is valid by attempting to decode it
        try {
          final privateKeyHex = NostrCrypto.decodeNsec(nsec);
          NostrCrypto.derivePublicKey(privateKeyHex);

          // Basic validation - we connected successfully
          setState(() {
            _connectionTested = true;
            _connectionSuccess = true;
            _remoteStatus = status;
          });
        } catch (e) {
          setState(() {
            _connectionTested = true;
            _connectionSuccess = false;
            _testError = 'Invalid NSEC: $e';
          });
        }
      } else {
        setState(() {
          _connectionTested = true;
          _connectionSuccess = false;
          _testError = 'Server returned status ${response.statusCode}';
        });
      }
    } catch (e) {
      LogService().log('Connection test failed: $e');
      setState(() {
        _connectionTested = true;
        _connectionSuccess = false;
        _testError = e.toString();
      });
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  Future<void> _connect() async {
    if (!_connectionSuccess || _remoteStatus == null) return;

    setState(() => _isConnecting = true);

    try {
      final url = _urlController.text.trim();
      final nsec = _nsecController.text.trim();
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : _remoteStatus!['name'] as String? ?? 'Remote Station';

      await _stationNodeService.connectToRemoteStation(
        url: url,
        nsec: nsec,
        name: name,
        remoteStatus: _remoteStatus!,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to $name')),
        );
      }
    } catch (e) {
      LogService().log('Failed to connect: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}
