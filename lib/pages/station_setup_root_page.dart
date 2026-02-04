/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/station_node.dart';
import '../models/station_network.dart';
import '../services/station_node_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';

/// Wizard for creating a station
class StationSetupRootPage extends StatefulWidget {
  const StationSetupRootPage({super.key});

  @override
  State<StationSetupRootPage> createState() => _StationSetupRootPageState();
}

class _StationSetupRootPageState extends State<StationSetupRootPage> {
  final StationNodeService _stationNodeService = StationNodeService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();

  int _currentStep = 0;
  bool _isCreating = false;

  // Step 1: Station Identity
  final _networkNameController = TextEditingController();
  final _networkDescriptionController = TextEditingController();
  final _callsignController = TextEditingController();

  // Step 2: Storage (other options configurable in Station Settings after creation)
  int _allocatedMb = 10000;

  @override
  void initState() {
    super.initState();
    final profile = _profileService.getProfile();
    _callsignController.text = profile.callsign ?? '';
  }

  @override
  void dispose() {
    _networkNameController.dispose();
    _networkDescriptionController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Station'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: _buildControls,
        steps: [
          _buildIdentityStep(),
          _buildStorageStep(),
          _buildReviewStep(),
        ],
      ),
    );
  }

  Step _buildIdentityStep() {
    final profile = _profileService.getProfile();
    final isStationProfile = profile.callsign?.startsWith('X3') ?? false;

    return Step(
      title: Text('Station Identity'),
      subtitle: Text('Step 1 of 3'),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _networkNameController,
            decoration: InputDecoration(
              labelText: 'Station Name *',
              hintText: 'e.g., Portugal Community Station',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _networkDescriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Describe your station...',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _callsignController,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Station Callsign',
              helperText: isStationProfile
                  ? 'Your station identity'
                  : 'Will be derived from station keypair',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[800],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'NPUB: ${profile.npub ?? "Not set"}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12, fontFamily: 'monospace'),
          ),
          if (isStationProfile) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green[400], size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You are using a station profile. This identity will be used for your station.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Step _buildStorageStep() {
    return Step(
      title: Text('Storage'),
      subtitle: Text('Step 2 of 3'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Allocate Storage', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            'Maximum storage space for cached data (map tiles, media, etc.)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          SizedBox(height: 16),
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
                    setState(() => _allocatedMb = value.round());
                  },
                ),
              ),
              SizedBox(width: 16),
              Text(_formatStorage(_allocatedMb), style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildPresetButton('500 MB', 500),
              _buildPresetButton('1 GB', 1000),
              _buildPresetButton('5 GB', 5000),
              _buildPresetButton('10 GB', 10000),
            ],
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, color: Colors.grey[500], size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Additional settings (binary policy, data retention, network policy) can be configured in Station Settings after creation.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ),
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

  Step _buildReviewStep() {
    final profile = _profileService.getProfile();
    final isStationProfile = profile.callsign?.startsWith('X3') ?? false;

    return Step(
      title: Text('Review & Create'),
      subtitle: Text('Step 3 of 3'),
      isActive: _currentStep >= 2,
      state: StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection('Station', [
            'Name: ${_networkNameController.text}',
            'Callsign: ${_callsignController.text}',
            if (!isStationProfile) 'Note: Station callsign will be generated',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Storage', [
            'Allocated: ${_formatStorage(_allocatedMb)}',
          ]),
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
                Icon(Icons.info_outline, color: Colors.blue[400]),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your station will be ready to accept connections after creation. You can adjust settings at any time.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
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

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    final isLastStep = _currentStep == 2;
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
              onPressed: _isCreating ? null : _createStation,
              child: _isCreating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Create Station'),
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
    if (_currentStep == 0) {
      // Validate identity
      if (_networkNameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Station name is required')),
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

    if (_currentStep < 2) {
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _createStation() async {
    setState(() => _isCreating = true);

    try {
      // Use sensible defaults for options not yet implemented
      final config = StationNodeConfig(
        storage: StationStorageConfig(
          allocatedMb: _allocatedMb,
          binaryPolicy: BinaryPolicy.thumbnailsOnly,
          retentionDays: 0, // Forever
          chatRetentionDays: 0, // Forever
        ),
        supportedApps: ['reports', 'places', 'events', 'forum', 'chat'],
      );

      final policy = NetworkPolicy(
        nodeRegistration: NodeRegistrationPolicy.open,
        userRegistration: UserRegistrationPolicy.open,
        enableCommunityFlagging: false,
        flagThresholdHide: 5,
        allowFederation: true,
      );

      final collections = NetworkApps(
        community: ['reports', 'places', 'events'],
        public: ['forum', 'chat'],
        userApprovalRequired: [],
      );

      await _stationNodeService.createRootStation(
        networkName: _networkNameController.text,
        networkDescription: _networkDescriptionController.text,
        operatorCallsign: _callsignController.text,
        config: config,
        policy: policy,
        apps: collections,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Station created successfully!')),
        );
      }
    } catch (e) {
      LogService().log('Error creating station: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
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
