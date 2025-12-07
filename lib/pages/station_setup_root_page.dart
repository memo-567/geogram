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

/// Wizard for creating a root station network
class StationSetupRootPage extends StatefulWidget {
  const StationSetupRootPage({super.key});

  @override
  State<StationSetupRootPage> createState() => _RelaySetupRootPageState();
}

class _RelaySetupRootPageState extends State<StationSetupRootPage> {
  final StationNodeService _stationNodeService = StationNodeService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();

  int _currentStep = 0;
  bool _isCreating = false;

  // Step 1: Network Identity
  final _networkNameController = TextEditingController();
  final _networkDescriptionController = TextEditingController();
  final _callsignController = TextEditingController();

  // Step 2: Collections
  final Set<String> _communityCollections = {'reports', 'places', 'events'};
  final Set<String> _publicCollections = {'forum', 'chat', 'announcements'};
  final Set<String> _userCollections = {'blogs'};

  // Step 3: Storage
  int _allocatedMb = 500;
  BinaryPolicy _binaryPolicy = BinaryPolicy.textOnly;
  bool _foreverRetention = true;
  int _retentionDays = 365;
  bool _foreverChatRetention = true;
  int _chatRetentionDays = 90;

  // Step 4: Policy
  NodeRegistrationPolicy _nodeRegistration = NodeRegistrationPolicy.open;
  UserRegistrationPolicy _userRegistration = UserRegistrationPolicy.open;
  bool _enableFlagging = true;
  int _flagThresholdHide = 5;
  bool _allowFederation = true;

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
        title: Text('Create Root Station'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: _buildControls,
        steps: [
          _buildIdentityStep(),
          _buildCollectionsStep(),
          _buildStorageStep(),
          _buildPolicyStep(),
          _buildReviewStep(),
        ],
      ),
    );
  }

  Step _buildIdentityStep() {
    return Step(
      title: Text('Network Identity'),
      subtitle: Text('Step 1 of 5'),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _networkNameController,
            decoration: InputDecoration(
              labelText: 'Network Name *',
              hintText: 'e.g., Portugal Community Network',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _networkDescriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Describe your network...',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _callsignController,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Operator Callsign (X1)',
              helperText: 'Your identity as the station operator',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[800],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'NPUB: ${_profileService.getProfile().npub ?? "Not set"}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12, fontFamily: 'monospace'),
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
                    'The station will receive its own X3 callsign (generated from its unique keypair). Your X1 callsign identifies you as the operator.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Step _buildCollectionsStep() {
    return Step(
      title: Text('Collections'),
      subtitle: Text('Step 2 of 5'),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Community Collections (auto-sync)', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildCollectionCheckbox('reports', 'Reports', 'Emergency and incident reports', _communityCollections),
          _buildCollectionCheckbox('places', 'Places', 'Points of interest', _communityCollections),
          _buildCollectionCheckbox('events', 'Events', 'Community events', _communityCollections),
          _buildCollectionCheckbox('contacts', 'Contacts', 'Shared contact directory', _communityCollections),
          SizedBox(height: 16),
          Text('Public Collections (hosted on root)', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildCollectionCheckbox('forum', 'Forum', 'Network-wide discussions', _publicCollections),
          _buildCollectionCheckbox('chat', 'Chat', 'Real-time messaging', _publicCollections),
          _buildCollectionCheckbox('announcements', 'Announcements', 'Official network notices', _publicCollections),
          SizedBox(height: 16),
          Text('User Collections (require approval)', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildCollectionCheckbox('shops', 'Shops', 'Business listings', _userCollections),
          _buildCollectionCheckbox('services', 'Services', 'Service providers', _userCollections),
          _buildCollectionCheckbox('blogs', 'Blogs', 'Personal blogs', _userCollections),
        ],
      ),
    );
  }

  Widget _buildCollectionCheckbox(String id, String name, String description, Set<String> set) {
    return CheckboxListTile(
      title: Text(name),
      subtitle: Text(description, style: TextStyle(fontSize: 12)),
      value: set.contains(id),
      onChanged: (value) {
        setState(() {
          if (value == true) {
            set.add(id);
          } else {
            set.remove(id);
          }
        });
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Step _buildStorageStep() {
    return Step(
      title: Text('Storage'),
      subtitle: Text('Step 3 of 5'),
      isActive: _currentStep >= 2,
      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Allocate Storage', style: TextStyle(fontWeight: FontWeight.bold)),
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
          SizedBox(height: 24),
          Text('Binary Data Policy', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildPolicyRadio(BinaryPolicy.textOnly, 'Text only', 'Maximum efficiency'),
          _buildPolicyRadio(BinaryPolicy.thumbnailsOnly, 'Thumbnails only', 'Balanced (recommended)'),
          _buildPolicyRadio(BinaryPolicy.onDemand, 'On-demand', 'Cache popular binaries'),
          _buildPolicyRadio(BinaryPolicy.fullCache, 'Full cache', 'Store everything'),
          SizedBox(height: 24),
          Text('Data Retention', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Forum posts:')),
              Row(
                children: [
                  ChoiceChip(
                    label: Text('Forever'),
                    selected: _foreverRetention,
                    onSelected: (v) => setState(() => _foreverRetention = true),
                  ),
                  SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Limit'),
                    selected: !_foreverRetention,
                    onSelected: (v) => setState(() => _foreverRetention = false),
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
                        suffixText: 'days',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      controller: TextEditingController(text: _retentionDays.toString()),
                      onChanged: (v) => _retentionDays = int.tryParse(v) ?? 365,
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
                    onSelected: (v) => setState(() => _foreverChatRetention = true),
                  ),
                  SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Limit'),
                    selected: !_foreverChatRetention,
                    onSelected: (v) => setState(() => _foreverChatRetention = false),
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
                        suffixText: 'days',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      controller: TextEditingController(text: _chatRetentionDays.toString()),
                      onChanged: (v) => _chatRetentionDays = int.tryParse(v) ?? 90,
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

  Widget _buildPolicyRadio(BinaryPolicy policy, String title, String subtitle) {
    return RadioListTile<BinaryPolicy>(
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12)),
      value: policy,
      groupValue: _binaryPolicy,
      onChanged: (value) => setState(() => _binaryPolicy = value!),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Step _buildPolicyStep() {
    return Step(
      title: Text('Network Policy'),
      subtitle: Text('Step 4 of 5'),
      isActive: _currentStep >= 3,
      state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Node Registration', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          RadioListTile<NodeRegistrationPolicy>(
            title: Text('Open'),
            subtitle: Text('Anyone can join as a node'),
            value: NodeRegistrationPolicy.open,
            groupValue: _nodeRegistration,
            onChanged: (v) => setState(() => _nodeRegistration = v!),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<NodeRegistrationPolicy>(
            title: Text('Approval'),
            subtitle: Text('Nodes require admin approval'),
            value: NodeRegistrationPolicy.approval,
            groupValue: _nodeRegistration,
            onChanged: (v) => setState(() => _nodeRegistration = v!),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<NodeRegistrationPolicy>(
            title: Text('Invite'),
            subtitle: Text('Nodes need invitation'),
            value: NodeRegistrationPolicy.invite,
            groupValue: _nodeRegistration,
            onChanged: (v) => setState(() => _nodeRegistration = v!),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          SizedBox(height: 16),
          Text('User Registration', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          RadioListTile<UserRegistrationPolicy>(
            title: Text('Open'),
            subtitle: Text('Anyone can participate'),
            value: UserRegistrationPolicy.open,
            groupValue: _userRegistration,
            onChanged: (v) => setState(() => _userRegistration = v!),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<UserRegistrationPolicy>(
            title: Text('Approval'),
            subtitle: Text('Users require approval to post'),
            value: UserRegistrationPolicy.approval,
            groupValue: _userRegistration,
            onChanged: (v) => setState(() => _userRegistration = v!),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          SizedBox(height: 16),
          Text('Moderation', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          SwitchListTile(
            title: Text('Enable community flagging'),
            value: _enableFlagging,
            onChanged: (v) => setState(() => _enableFlagging = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_enableFlagging)
            Padding(
              padding: EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  Text('Flag threshold to hide: '),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      controller: TextEditingController(text: _flagThresholdHide.toString()),
                      onChanged: (v) => _flagThresholdHide = int.tryParse(v) ?? 5,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 16),
          Text('Federation', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          SwitchListTile(
            title: Text('Allow federation with other networks'),
            value: _allowFederation,
            onChanged: (v) => setState(() => _allowFederation = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Step _buildReviewStep() {
    return Step(
      title: Text('Review & Create'),
      subtitle: Text('Step 5 of 5'),
      isActive: _currentStep >= 4,
      state: StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection('Network Summary', [
            'Name: ${_networkNameController.text}',
            'Operator: ${_callsignController.text} (X1)',
            'Station: Will be assigned X3 callsign',
            'Type: Root Station',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Collections', [
            'Community: ${_communityCollections.join(", ")}',
            'Public: ${_publicCollections.join(", ")}',
            'User: ${_userCollections.join(", ")}',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Storage', [
            'Allocated: ${_formatStorage(_allocatedMb)}',
            'Binary policy: ${_binaryPolicy.name}',
          ]),
          SizedBox(height: 16),
          _buildSummarySection('Policy', [
            'Node registration: ${_nodeRegistration.name}',
            'User registration: ${_userRegistration.name}',
            'Federation: ${_allowFederation ? "Enabled" : "Disabled"}',
          ]),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber[700]),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Creating a root station makes you responsible for the network. You will be the ultimate authority for all network decisions.',
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
    final isLastStep = _currentStep == 4;
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
              onPressed: _isCreating ? null : _createRelay,
              child: _isCreating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Create Network'),
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
          SnackBar(content: Text('Network name is required')),
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

    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _createRelay() async {
    setState(() => _isCreating = true);

    try {
      final config = StationNodeConfig(
        storage: StationStorageConfig(
          allocatedMb: _allocatedMb,
          binaryPolicy: _binaryPolicy,
          retentionDays: _foreverRetention ? 0 : _retentionDays,
          chatRetentionDays: _foreverChatRetention ? 0 : _chatRetentionDays,
        ),
        supportedCollections: [
          ..._communityCollections,
          ..._publicCollections,
          ..._userCollections,
        ],
      );

      final policy = NetworkPolicy(
        nodeRegistration: _nodeRegistration,
        userRegistration: _userRegistration,
        enableCommunityFlagging: _enableFlagging,
        flagThresholdHide: _flagThresholdHide,
        allowFederation: _allowFederation,
      );

      final collections = NetworkCollections(
        community: _communityCollections.toList(),
        public: _publicCollections.toList(),
        userApprovalRequired: _userCollections.toList(),
      );

      await _stationNodeService.createRootRelay(
        networkName: _networkNameController.text,
        networkDescription: _networkDescriptionController.text,
        operatorCallsign: _callsignController.text,
        config: config,
        policy: policy,
        collections: collections,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Root station created successfully!')),
        );
      }
    } catch (e) {
      LogService().log('Error creating root station: $e');
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
