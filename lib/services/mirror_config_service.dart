/// Service for managing mirror configuration persistence.
///
/// Handles loading, saving, and streaming mirror config changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/mirror_config.dart';
import 'storage_config.dart';

/// Service for managing mirror sync configuration
class MirrorConfigService {
  static final MirrorConfigService _instance = MirrorConfigService._();
  static MirrorConfigService get instance => _instance;

  MirrorConfigService._();

  MirrorConfig? _config;
  final _configController = StreamController<MirrorConfig>.broadcast();

  /// Stream of config changes
  Stream<MirrorConfig> get configStream => _configController.stream;

  /// Current config (may be null if not loaded)
  MirrorConfig? get config => _config;

  /// Check if mirror is enabled
  bool get isEnabled => _config?.enabled ?? false;

  /// Get config file path
  String get _configPath {
    final basePath = StorageConfig().baseDir;
    return '$basePath/mirror_config.json';
  }

  /// Initialize the service
  Future<void> initialize() async {
    await loadConfig();
  }

  /// Load config from disk
  Future<MirrorConfig> loadConfig() async {
    final file = File(_configPath);

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _config = MirrorConfig.fromJson(json);
      } catch (e) {
        print('Error loading mirror config: $e');
        _config = _createDefaultConfig();
      }
    } else {
      _config = _createDefaultConfig();
    }

    _configController.add(_config!);
    return _config!;
  }

  /// Create default config with new device ID
  MirrorConfig _createDefaultConfig() {
    final deviceId = const Uuid().v4();
    final deviceName = _getDefaultDeviceName();

    return MirrorConfig(
      enabled: false,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  /// Get default device name based on platform
  String _getDefaultDeviceName() {
    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isLinux) return 'Linux Desktop';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    return 'My Device';
  }

  /// Save config to disk
  Future<void> saveConfig(MirrorConfig config) async {
    _config = config;

    final file = File(_configPath);
    await file.parent.create(recursive: true);

    final content = const JsonEncoder.withIndent('  ').convert(config.toJson());
    await file.writeAsString(content);

    _configController.add(config);
  }

  /// Update config and save
  Future<void> updateConfig(MirrorConfig Function(MirrorConfig) updater) async {
    if (_config == null) await loadConfig();
    final updated = updater(_config!);
    await saveConfig(updated);
  }

  /// Enable or disable mirror
  Future<void> setEnabled(bool enabled) async {
    await updateConfig((c) => c.copyWith(enabled: enabled));
  }

  /// Update device name
  Future<void> setDeviceName(String name) async {
    await updateConfig((c) => c.copyWith(deviceName: name));
  }

  /// Add a new peer
  Future<void> addPeer(MirrorPeer peer) async {
    await updateConfig((c) {
      final peers = List<MirrorPeer>.from(c.peers);
      // Remove existing peer with same ID if any
      peers.removeWhere((p) => p.peerId == peer.peerId);
      peers.add(peer);
      return c.copyWith(peers: peers);
    });
  }

  /// Remove a peer
  Future<void> removePeer(String peerId) async {
    await updateConfig((c) {
      final peers = List<MirrorPeer>.from(c.peers);
      peers.removeWhere((p) => p.peerId == peerId);
      return c.copyWith(peers: peers);
    });
  }

  /// Update a peer
  Future<void> updatePeer(MirrorPeer peer) async {
    await updateConfig((c) {
      final peers = List<MirrorPeer>.from(c.peers);
      final index = peers.indexWhere((p) => p.peerId == peer.peerId);
      if (index >= 0) {
        peers[index] = peer;
      }
      return c.copyWith(peers: peers);
    });
  }

  /// Update app sync config for a peer
  Future<void> updatePeerAppConfig(
    String peerId,
    String appId,
    AppSyncConfig appConfig,
  ) async {
    await updateConfig((c) {
      final peers = List<MirrorPeer>.from(c.peers);
      final index = peers.indexWhere((p) => p.peerId == peerId);
      if (index >= 0) {
        final peer = peers[index];
        final apps = Map<String, AppSyncConfig>.from(peer.apps);
        apps[appId] = appConfig;
        peers[index] = peer.copyWith(apps: apps);
      }
      return c.copyWith(peers: peers);
    });
  }

  /// Update connection preferences
  Future<void> updatePreferences(ConnectionPreferences preferences) async {
    await updateConfig((c) => c.copyWith(preferences: preferences));
  }

  /// Update peer connection state (runtime only, not persisted)
  void updatePeerConnectionState(String peerId, PeerConnectionState state) {
    if (_config == null) return;

    final index = _config!.peers.indexWhere((p) => p.peerId == peerId);
    if (index >= 0) {
      _config!.peers[index].connectionState = state;
      if (state == PeerConnectionState.connected ||
          state == PeerConnectionState.syncing) {
        _config!.peers[index].lastSeenAt = DateTime.now();
      }
      _configController.add(_config!);
    }
  }

  /// Update peer sync state for an app (runtime only)
  void updatePeerAppSyncState(String peerId, String appId, SyncState state) {
    if (_config == null) return;

    final peerIndex = _config!.peers.indexWhere((p) => p.peerId == peerId);
    if (peerIndex >= 0) {
      final peer = _config!.peers[peerIndex];
      if (peer.apps.containsKey(appId)) {
        peer.apps[appId]!.state = state;
        _configController.add(_config!);
      }
    }
  }

  /// Mark peer as synced
  Future<void> markPeerSynced(String peerId) async {
    await updateConfig((c) {
      final peers = List<MirrorPeer>.from(c.peers);
      final index = peers.indexWhere((p) => p.peerId == peerId);
      if (index >= 0) {
        peers[index] = peers[index].copyWith(lastSyncAt: DateTime.now());
      }
      return c.copyWith(peers: peers);
    });
  }

  /// Get list of enabled apps for a peer
  List<String> getEnabledAppsForPeer(String peerId) {
    final peer = _config?.getPeer(peerId);
    if (peer == null) return [];

    return peer.apps.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toList();
  }

  /// Dispose resources
  void dispose() {
    _configController.close();
  }
}
