/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/relay_node.dart';
import '../models/relay_network.dart';
import '../services/relay_node_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';

/// Wizard for joining a network as a node relay
class RelaySetupNodePage extends StatefulWidget {
  const RelaySetupNodePage({super.key});

  @override
  State<RelaySetupNodePage> createState() => _RelaySetupNodePageState();
}

class _RelaySetupNodePageState extends State<RelaySetupNodePage> {
  final RelayNodeService _relayNodeService = RelayNodeService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();

  int _currentStep = 0;
  bool _isJoining = false;
  bool _isConnecting = false;

  // Step 1: Network Selection
  final _rootUrlController = TextEditingController();
  RelayNetwork? _selectedNetwork;

  // Step 2: Node Configuration
  final _nodeNameController = TextEditingController();
  final _callsignController = TextEditingController();
  double? _latitude;
  double? _longitude;
  double _radiusKm = 50;

  // Step 3: Storage & Channels
  int _allocatedMb = 500;
  BinaryPolicy _binaryPolicy = BinaryPolicy.textOnly;
  bool _internetEnabled = true;
  bool _wifiLanEnabled = true;
  bool _bluetoothEnabled = false;
  bool _loraEnabled = false;

  @override
  void initState() {
    super.initState();
    final profile = _profileService.getProfile();
    _callsignController.text = profile.callsign ?? '';
    _latitude = profile.latitude;
    _longitude = profile.longitude;
  }

  @override
  void dispose() {
    _rootUrlController.dispose();
    _nodeNameController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Join as Node Relay'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: _buildControls,
        steps: [
          _buildNetworkStep(),
          _buildConfigStep(),
          _buildStorageStep(),
          _buildReviewStep(),
        ],
      ),
    );
  }

  Step _buildNetworkStep() {
    return Step(
      title: Text('Select Network'),
      subtitle: Text('Step 1 of 4'),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter Root Relay URL', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rootUrlController,
                  decoration: InputDecoration(
                    hintText: 'wss://relay.example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isConnecting ? null : _connectToRoot,
                child: _isConnecting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Connect'),
              ),
            ],
          ),
          if (_selectedNetwork != null) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text('Connected to network', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Network: ${_selectedNetwork!.name}'),
                  Text('Root: ${_selectedNetwork!.rootCallsign}'),
                  Text('Collections: ${_selectedNetwork!.collections.all.join(", ")}'),
                  Text('Policy: ${_selectedNetwork!.policy.nodeRegistration.name} registration'),
                ],
              ),
            ),
          ],
          SizedBox(height: 24),
          Text('Or select from discovered networks:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'No networks discovered nearby.\nEnter a root relay URL above.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Step _buildConfigStep() {
    return Step(
      title: Text('Node Configuration'),
      subtitle: Text('Step 2 of 4'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedNetwork != null)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Joining: ${_selectedNetwork!.name}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          TextField(
            controller: _nodeNameController,
            decoration: InputDecoration(
              labelText: 'Your Node Name *',
              hintText: 'e.g., Lisbon Downtown Relay',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _callsignController,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Operator Callsign (X1)',
              helperText: 'Your identity as the relay operator',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[400], size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your node will receive its own X3 callsign (generated from its unique keypair). Your X1 callsign identifies you as the operator.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          Text('Geographic Coverage', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[100],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 40, color: Colors.grey),
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
                  max: 200,
                  divisions: 39,
                  label: '${_radiusKm.round()} km',
                  onChanged: (v) => setState(() => _radiusKm = v),
                ),
              ),
              Text('${_radiusKm.round()} km'),
            ],
          ),
        ],
      ),
    );
  }

  Step _buildStorageStep() {
    return Step(
      title: Text('Storage & Channels'),
      subtitle: Text('Step 3 of 4'),
      isActive: _currentStep >= 2,
      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage Allocation', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  onChanged: (v) => setState(() => _allocatedMb = v.round()),
                ),
              ),
              SizedBox(width: 16),
              Text(_formatStorage(_allocatedMb), style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              _buildPresetButton('Minimal', 50),
              _buildPresetButton('Standard', 500),
              _buildPresetButton('High', 10000),
            ],
          ),
          SizedBox(height: 16),
          Text('Binary Policy', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          SegmentedButton<BinaryPolicy>(
            segments: [
              ButtonSegment(value: BinaryPolicy.textOnly, label: Text('Text only')),
              ButtonSegment(value: BinaryPolicy.thumbnailsOnly, label: Text('Thumbnails')),
              ButtonSegment(value: BinaryPolicy.onDemand, label: Text('On-demand')),
            ],
            selected: {_binaryPolicy},
            onSelectionChanged: (v) => setState(() => _binaryPolicy = v.first),
          ),
          SizedBox(height: 24),
          Text('Communication Channels', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildChannelSwitch('Internet (WebSocket)', 'Available', _internetEnabled, true, (v) {}),
          _buildChannelSwitch('Local WiFi', 'Available', _wifiLanEnabled, true, (v) => setState(() => _wifiLanEnabled = v)),
          _buildChannelSwitch('Bluetooth LE', 'Not available', _bluetoothEnabled, false, (v) {}),
          _buildChannelSwitch('LoRa', 'Not detected', _loraEnabled, false, (v) {}),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, int value) {
    final isSelected = _allocatedMb == value;
    return OutlinedButton(
      onPressed: () => setState(() => _allocatedMb = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildChannelSwitch(String name, String status, bool enabled, bool available, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(name),
      subtitle: Text(status, style: TextStyle(fontSize: 12, color: available ? Colors.green : Colors.grey)),
      value: enabled,
      onChanged: available ? onChanged : null,
      contentPadding: EdgeInsets.zero,
    );
  }

  Step _buildReviewStep() {
    return Step(
      title: Text('Review & Join'),
      subtitle: Text('Step 4 of 4'),
      isActive: _currentStep >= 3,
      state: StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection('Node Summary', [
            'Name: ${_nodeNameController.text}',
            'Operator: ${_callsignController.text} (X1)',
            'Relay: Will be assigned X3 callsign',
            'Type: Node Relay',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Network', [
            'Name: ${_selectedNetwork?.name ?? "Not selected"}',
            'Root: ${_selectedNetwork?.rootCallsign ?? "-"}',
            'Registration: ${_selectedNetwork?.policy.nodeRegistration.name ?? "-"}',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Coverage', [
            'Center: ${_latitude?.toStringAsFixed(4) ?? "-"}, ${_longitude?.toStringAsFixed(4) ?? "-"}',
            'Radius: ${_radiusKm.round()} km',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Resources', [
            'Storage: ${_formatStorage(_allocatedMb)}',
            'Binary: ${_binaryPolicy.name}',
            'Channels: ${_getEnabledChannels().join(", ")}',
          ]),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('By joining, you agree to:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• Follow network policies set by root'),
                Text('• Cache and serve data within your capacity'),
                Text('• Forward messages between connected devices'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: EdgeInsets.only(left: 8),
          child: Text('• $item', style: TextStyle(fontSize: 13)),
        )),
      ],
    );
  }

  List<String> _getEnabledChannels() {
    final channels = <String>[];
    if (_internetEnabled) channels.add('Internet');
    if (_wifiLanEnabled) channels.add('WiFi LAN');
    if (_bluetoothEnabled) channels.add('Bluetooth');
    if (_loraEnabled) channels.add('LoRa');
    return channels;
  }

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    final isLastStep = _currentStep == 3;
    return Padding(
      padding: EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: details.onStepCancel,
              child: Text('Back'),
            ),
          Spacer(),
          if (isLastStep)
            ElevatedButton(
              onPressed: _isJoining ? null : _joinNetwork,
              child: _isJoining
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Join Network'),
            )
          else
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next Step'),
            ),
        ],
      ),
    );
  }

  void _onStepContinue() {
    if (_currentStep == 0 && _selectedNetwork == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please connect to a network first')),
      );
      return;
    }

    if (_currentStep == 1) {
      if (_nodeNameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Node name is required')),
        );
        return;
      }
      if (_callsignController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Callsign is required')),
        );
        return;
      }
    }

    if (_currentStep < 3) {
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _connectToRoot() async {
    final url = _rootUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a root relay URL')),
      );
      return;
    }

    setState(() => _isConnecting = true);

    try {
      // TODO: Actually connect to the root relay and fetch network info
      // For now, create a mock network
      await Future.delayed(Duration(seconds: 1));

      final mockNetwork = RelayNetwork(
        id: 'mock-network-id',
        name: 'Demo Network',
        description: 'A demo relay network',
        rootNpub: 'npub1demo...',
        rootCallsign: 'DEMO1',
        rootUrl: url,
        policy: NetworkPolicy(),
        collections: NetworkCollections(),
        founded: DateTime.now(),
        updated: DateTime.now(),
      );

      setState(() {
        _selectedNetwork = mockNetwork;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${mockNetwork.name}')),
      );
    } catch (e) {
      LogService().log('Error connecting to root: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _joinNetwork() async {
    if (_selectedNetwork == null) return;

    setState(() => _isJoining = true);

    try {
      final channels = <ChannelConfig>[];
      if (_internetEnabled) {
        channels.add(ChannelConfig(type: 'internet', enabled: true));
      }
      if (_wifiLanEnabled) {
        channels.add(ChannelConfig(type: 'wifi_lan', enabled: true));
      }
      if (_bluetoothEnabled) {
        channels.add(ChannelConfig(type: 'bluetooth', enabled: true));
      }
      if (_loraEnabled) {
        channels.add(ChannelConfig(type: 'lora', enabled: true));
      }

      final config = RelayNodeConfig(
        storage: RelayStorageConfig(
          allocatedMb: _allocatedMb,
          binaryPolicy: _binaryPolicy,
        ),
        coverage: _latitude != null
            ? GeographicCoverage(
                latitude: _latitude!,
                longitude: _longitude!,
                radiusKm: _radiusKm,
              )
            : null,
        channels: channels,
        supportedCollections: _selectedNetwork!.collections.all,
      );

      await _relayNodeService.joinAsNode(
        nodeName: _nodeNameController.text,
        operatorCallsign: _callsignController.text,
        network: _selectedNetwork!,
        config: config,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined network as node relay!')),
        );
      }
    } catch (e) {
      LogService().log('Error joining network: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
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
