/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/station_node.dart';
import '../models/station_network.dart';
import '../util/nostr_key_generator.dart';
import 'config_service.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'storage_config.dart';

/// Service for managing this device as a station node
class StationNodeService {
  static final StationNodeService _instance = StationNodeService._internal();
  factory StationNodeService() => _instance;
  StationNodeService._internal();

  final ConfigService _configService = ConfigService();
  final ProfileService _profileService = ProfileService();

  StationNode? _stationNode;
  StationNetwork? _network;
  bool _initialized = false;
  DateTime? _startedAt;
  Timer? _statsTimer;

  // Stream controllers for state changes
  final _stateController = StreamController<StationNode?>.broadcast();
  Stream<StationNode?> get stateStream => _stateController.stream;

  /// Get current station node (if configured)
  StationNode? get stationNode => _stationNode;

  /// Get current network (if joined/created)
  StationNetwork? get network => _network;

  /// Check if station mode is enabled
  bool get isRelayEnabled => _stationNode != null;

  /// Check if station is running
  bool get isRunning => _stationNode?.isRunning ?? false;

  /// Initialize the station node service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadRelayConfig();
      _initialized = true;
      LogService().log('StationNodeService initialized');

      // Auto-start if was running before
      if (_stationNode != null && _configService.get('stationAutoStart') == true) {
        await start();
      }
    } catch (e) {
      LogService().log('Error initializing StationNodeService: $e');
    }
  }

  /// Load station configuration from storage
  Future<void> _loadRelayConfig() async {
    // First try to load from GUI's config
    final stationData = _configService.get('stationNode');
    if (stationData != null) {
      _stationNode = StationNode.fromJson(stationData as Map<String, dynamic>);
      LogService().log('Loaded station node: ${_stationNode!.name} (${_stationNode!.typeDisplay})');
    }

    final networkData = _configService.get('stationNetwork');
    if (networkData != null) {
      _network = StationNetwork.fromJson(networkData as Map<String, dynamic>);
      LogService().log('Loaded network: ${_network!.name}');
    }

    // If no station config found, check CLI's station_config.json
    if (_stationNode == null) {
      await _loadFromCliConfig();
    }
  }

  /// Load station configuration from CLI's station_config.json
  Future<void> _loadFromCliConfig() async {
    try {
      final storageConfig = StorageConfig();
      if (!storageConfig.isInitialized) return;

      final configFile = File(storageConfig.stationConfigPath);
      if (!await configFile.exists()) return;

      final content = await configFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Check if this has station settings (CLI format)
      if (json.containsKey('port') || json.containsKey('callsign')) {
        final profile = _profileService.getProfile();
        final now = DateTime.now();

        // Determine station type from stationRole
        final stationRole = json['stationRole'] as String? ?? 'root';
        final stationType = stationRole == 'node' ? StationType.node : StationType.root;

        // Create a StationNode from CLI settings
        _stationNode = StationNode(
          id: json['networkId'] as String? ?? _generateId(),
          name: json['description'] as String? ?? 'Station',
          stationCallsign: json['callsign'] as String? ?? profile.callsign,
          stationNpub: profile.npub,
          stationNsec: profile.nsec,
          operatorCallsign: profile.callsign,
          operatorNpub: profile.npub,
          type: stationType,
          networkId: json['networkId'] as String?,
          networkName: json['description'] as String? ?? 'Network',
          config: StationNodeConfig(
            storage: StationStorageConfig(
              allocatedMb: json['maxCacheSize'] as int? ?? 1000,
            ),
          ),
          status: (json['enabled'] as bool? ?? false)
              ? StationNodeStatus.running
              : StationNodeStatus.stopped,
          created: now,
          updated: now,
        );

        LogService().log('Loaded station from CLI config: ${_stationNode!.name}');

        // Save to GUI config format for future loads
        _saveRelayConfig();
      }
    } catch (e) {
      LogService().log('Error loading CLI station config: $e');
    }
  }

  /// Save station configuration to storage
  void _saveRelayConfig() {
    if (_stationNode != null) {
      _configService.set('stationNode', _stationNode!.toJson());
    } else {
      _configService.remove('stationNode');
    }

    if (_network != null) {
      _configService.set('stationNetwork', _network!.toJson());
    } else {
      _configService.remove('stationNetwork');
    }
  }

  /// Create a new root station network
  Future<StationNode> createRootRelay({
    required String networkName,
    required String networkDescription,
    required String operatorCallsign,
    required StationNodeConfig config,
    NetworkPolicy policy = const NetworkPolicy(),
    NetworkCollections collections = const NetworkCollections(),
  }) async {
    final profile = _profileService.getProfile();
    if (profile.npub == null || profile.npub!.isEmpty) {
      throw Exception('Profile npub is required to create a station');
    }

    final now = DateTime.now();
    final id = _generateId();
    final networkId = _generateId();

    // Generate station identity (X3 callsign)
    final stationKeys = NostrKeys.forRelay();
    LogService().log('Generated station identity: ${stationKeys.callsign} (${stationKeys.npub.substring(0, 20)}...)');

    // Create the network with station as root
    _network = StationNetwork(
      id: networkId,
      name: networkName,
      description: networkDescription,
      rootNpub: stationKeys.npub,  // Root is the station's npub
      rootCallsign: stationKeys.callsign,  // Root callsign is X3
      policy: policy,
      collections: collections,
      founded: now,
      updated: now,
    );

    // Create the station node with separate identities
    _stationNode = StationNode(
      id: id,
      name: networkName,
      stationCallsign: stationKeys.callsign,  // X3 callsign
      stationNpub: stationKeys.npub,
      stationNsec: stationKeys.nsec,
      operatorCallsign: operatorCallsign,  // X1 callsign from profile
      operatorNpub: profile.npub!,
      type: StationType.root,
      networkId: networkId,
      networkName: networkName,
      config: config,
      status: StationNodeStatus.stopped,
      created: now,
      updated: now,
    );

    _saveRelayConfig();
    await _createRelayDirectories();

    LogService().log('Created root station: $networkName (station: ${stationKeys.callsign}, operator: $operatorCallsign)');
    _stateController.add(_stationNode);

    return _stationNode!;
  }

  /// Join an existing network as a node station
  Future<StationNode> joinAsNode({
    required String nodeName,
    required String operatorCallsign,
    required StationNetwork network,
    required StationNodeConfig config,
  }) async {
    final profile = _profileService.getProfile();
    if (profile.npub == null || profile.npub!.isEmpty) {
      throw Exception('Profile npub is required to join a network');
    }

    final now = DateTime.now();
    final id = _generateId();

    // Generate station identity (X3 callsign)
    final stationKeys = NostrKeys.forRelay();
    LogService().log('Generated station identity: ${stationKeys.callsign} (${stationKeys.npub.substring(0, 20)}...)');

    _network = network;

    _stationNode = StationNode(
      id: id,
      name: nodeName,
      stationCallsign: stationKeys.callsign,  // X3 callsign
      stationNpub: stationKeys.npub,
      stationNsec: stationKeys.nsec,
      operatorCallsign: operatorCallsign,  // X1 callsign from profile
      operatorNpub: profile.npub!,
      type: StationType.node,
      networkId: network.id,
      networkName: network.name,
      rootNpub: network.rootNpub,
      rootCallsign: network.rootCallsign,
      config: config,
      status: StationNodeStatus.stopped,
      created: now,
      updated: now,
    );

    _saveRelayConfig();
    await _createRelayDirectories();

    LogService().log('Joined network as node: $nodeName (station: ${stationKeys.callsign}, operator: $operatorCallsign)');
    _stateController.add(_stationNode);

    return _stationNode!;
  }

  /// Start the station
  Future<void> start() async {
    if (_stationNode == null) {
      throw Exception('No station configured');
    }

    if (_stationNode!.isRunning) {
      LogService().log('Station already running');
      return;
    }

    LogService().log('Starting station: ${_stationNode!.name}');

    _stationNode = _stationNode!.copyWith(
      status: StationNodeStatus.starting,
      updated: DateTime.now(),
    );
    _stateController.add(_stationNode);

    try {
      // TODO: Implement actual station server startup
      // - Start WebSocket server for incoming connections
      // - Start mDNS advertisement
      // - Initialize collection caching
      // - Connect to root (if node)

      await Future.delayed(const Duration(milliseconds: 500)); // Simulate startup

      _startedAt = DateTime.now();
      _stationNode = _stationNode!.copyWith(
        status: StationNodeStatus.running,
        updated: DateTime.now(),
      );

      // Start stats update timer
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _updateStats();
      });

      _saveRelayConfig();
      _stateController.add(_stationNode);

      LogService().log('Station started successfully');
    } catch (e) {
      _stationNode = _stationNode!.copyWith(
        status: StationNodeStatus.error,
        errorMessage: e.toString(),
        updated: DateTime.now(),
      );
      _stateController.add(_stationNode);
      LogService().log('Failed to start station: $e');
      rethrow;
    }
  }

  /// Stop the station
  Future<void> stop() async {
    if (_stationNode == null || !_stationNode!.isRunning) {
      return;
    }

    LogService().log('Stopping station: ${_stationNode!.name}');

    _stationNode = _stationNode!.copyWith(
      status: StationNodeStatus.stopping,
      updated: DateTime.now(),
    );
    _stateController.add(_stationNode);

    try {
      // TODO: Implement actual station server shutdown
      // - Close all connections
      // - Stop WebSocket server
      // - Stop mDNS advertisement

      _statsTimer?.cancel();
      _statsTimer = null;

      await Future.delayed(const Duration(milliseconds: 300)); // Simulate shutdown

      _stationNode = _stationNode!.copyWith(
        status: StationNodeStatus.stopped,
        updated: DateTime.now(),
      );
      _startedAt = null;

      _saveRelayConfig();
      _stateController.add(_stationNode);

      LogService().log('Station stopped');
    } catch (e) {
      _stationNode = _stationNode!.copyWith(
        status: StationNodeStatus.error,
        errorMessage: e.toString(),
        updated: DateTime.now(),
      );
      _stateController.add(_stationNode);
      LogService().log('Error stopping station: $e');
    }
  }

  /// Update station configuration
  Future<void> updateConfig(StationNodeConfig config) async {
    if (_stationNode == null) {
      throw Exception('No station configured');
    }

    _stationNode = _stationNode!.copyWith(
      config: config,
      updated: DateTime.now(),
    );

    _saveRelayConfig();
    _stateController.add(_stationNode);

    LogService().log('Station config updated');
  }

  /// Delete station configuration and leave network
  Future<void> deleteStation() async {
    if (_stationNode == null) return;

    // Stop if running
    if (_stationNode!.isRunning) {
      await stop();
    }

    LogService().log('Deleting station: ${_stationNode!.name}');

    // Clean up directories
    await _deleteStationDirectories();

    _stationNode = null;
    _network = null;

    _saveRelayConfig();
    _stateController.add(null);

    LogService().log('Station deleted');
  }

  /// Get station data directory
  Future<Directory> getStationDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, 'geogram', 'station'));
  }

  /// Create station directories
  Future<void> _createRelayDirectories() async {
    final stationDir = await getStationDirectory();

    final directories = [
      '',
      'authorities',
      'authorities/admins',
      'authorities/group-admins',
      'authorities/moderators',
      'collections',
      'collections/approved',
      'collections/pending',
      'collections/suspended',
      'collections/banned',
      'public',
      'public/forum',
      'public/chat',
      'public/announcements',
      'peers',
      'peers/nodes',
      'banned',
      'banned/users',
      'reputation',
      'points',
      'points/current',
      'points/historical',
      'sync',
      'sync/nodes',
      'logs',
    ];

    for (final dir in directories) {
      final dirPath = path.join(stationDir.path, dir);
      await Directory(dirPath).create(recursive: true);
    }

    // Create initial config files
    await _createInitialFiles(stationDir);

    LogService().log('Created station directories at: ${stationDir.path}');
  }

  /// Create initial station configuration files
  Future<void> _createInitialFiles(Directory stationDir) async {
    if (_stationNode == null || _network == null) return;

    // station.json
    final stationFile = File(path.join(stationDir.path, 'station.json'));
    await stationFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_stationNode!.toJson()),
    );

    // network.json
    final networkFile = File(path.join(stationDir.path, 'network.json'));
    await networkFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_network!.toJson()),
    );

    // authorities/root.txt (if root)
    if (_stationNode!.isRoot) {
      final rootFile = File(path.join(stationDir.path, 'authorities', 'root.txt'));
      await rootFile.writeAsString('''
# ROOT: ${_network!.name}

## Station Identity (X3)
RELAY_CALLSIGN: ${_stationNode!.stationCallsign}
RELAY_NPUB: ${_stationNode!.stationNpub}

## Operator Identity (X1)
OPERATOR_CALLSIGN: ${_stationNode!.operatorCallsign}
OPERATOR_NPUB: ${_stationNode!.operatorNpub}

CREATED: ${_stationNode!.created.toIso8601String()}

Network founder and ultimate authority.

The station (${_stationNode!.stationCallsign}) is managed by operator ${_stationNode!.operatorCallsign}.
''');
    }
  }

  /// Delete station directories
  Future<void> _deleteStationDirectories() async {
    final stationDir = await getStationDirectory();
    if (await stationDir.exists()) {
      await stationDir.delete(recursive: true);
      LogService().log('Deleted station directories');
    }
  }

  /// Update station statistics
  void _updateStats() {
    if (_stationNode == null || !_stationNode!.isRunning) return;

    final uptime = _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : Duration.zero;

    // TODO: Get actual stats from station server
    final stats = StationNodeStats(
      connectedDevices: 0, // TODO: Get from server
      messagesRelayed: 0, // TODO: Get from server
      collectionsServed: 0, // TODO: Get from server
      storageUsedMb: 0, // TODO: Calculate from disk
      lastActivity: DateTime.now(),
      uptime: uptime,
    );

    _stationNode = _stationNode!.copyWith(
      stats: stats,
      updated: DateTime.now(),
    );
    _stateController.add(_stationNode);
  }

  /// Generate a unique ID
  String _generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final random = (DateTime.now().microsecond * 1000).toRadixString(16);
    return '$timestamp$random'.substring(0, 16);
  }

  /// Dispose resources
  void dispose() {
    _statsTimer?.cancel();
    _stateController.close();
  }
}
