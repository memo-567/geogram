/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'config_service.dart';
import 'bluetooth_classic_service.dart';
import 'log_service.dart';
import '../models/bluetooth_classic_device.dart';

/// Service for managing Bluetooth Classic pairing information
///
/// This service tracks which BLE devices have been upgraded to BLE+
/// (paired via Bluetooth Classic for faster data transfer).
class BluetoothClassicPairingService {
  static final BluetoothClassicPairingService _instance = BluetoothClassicPairingService._internal();
  factory BluetoothClassicPairingService() => _instance;
  BluetoothClassicPairingService._internal();

  /// ConfigService storage key
  static const String _storageKey = 'bluetoothClassicPairedDevices';

  /// Settings storage key
  static const String _settingsKey = 'bluetoothClassicSettings';

  /// In-memory cache of paired devices
  final Map<String, BluetoothClassicDevice> _pairedDevices = {};

  /// Stream controller for pairing changes
  final _pairingChangesController = StreamController<BluetoothClassicDevice>.broadcast();
  Stream<BluetoothClassicDevice> get pairingChangesStream => _pairingChangesController.stream;

  /// Initialization state
  bool _isInitialized = false;

  /// Initialize the pairing service (load from config)
  Future<void> initialize() async {
    if (_isInitialized) return;

    _loadFromConfig();
    _isInitialized = true;
    LogService().log('BluetoothClassicPairing: Initialized with ${_pairedDevices.length} paired devices');
  }

  /// Load paired devices from ConfigService
  void _loadFromConfig() {
    final config = ConfigService();
    final stored = config.get(_storageKey) as Map<String, dynamic>?;

    if (stored != null) {
      _pairedDevices.clear();
      for (final entry in stored.entries) {
        try {
          final device = BluetoothClassicDevice.fromJson(
            entry.value as Map<String, dynamic>,
          );
          _pairedDevices[entry.key] = device;
        } catch (e) {
          LogService().log('BluetoothClassicPairing: Failed to load device ${entry.key}: $e');
        }
      }
    }
  }

  /// Save paired devices to ConfigService
  void _saveToConfig() {
    final config = ConfigService();
    final data = <String, dynamic>{};

    for (final entry in _pairedDevices.entries) {
      data[entry.key] = entry.value.toJson();
    }

    config.set(_storageKey, data);
  }

  /// Check if a device is BLE+ (has Bluetooth Classic pairing)
  bool isBLEPlus(String callsign) {
    return _pairedDevices.containsKey(callsign);
  }

  /// Get the Bluetooth Classic MAC address for a callsign
  String? getClassicMac(String callsign) {
    return _pairedDevices[callsign]?.classicMac;
  }

  /// Get full paired device info for a callsign
  BluetoothClassicDevice? getPairedDevice(String callsign) {
    return _pairedDevices[callsign];
  }

  /// Get all paired devices
  List<BluetoothClassicDevice> getAllPairedDevices() {
    return _pairedDevices.values.toList();
  }

  /// Store a new pairing
  Future<void> storePairing({
    required String callsign,
    required String classicMac,
    String? bleMac,
    List<String>? capabilities,
  }) async {
    final device = BluetoothClassicDevice(
      callsign: callsign,
      classicMac: classicMac,
      bleMac: bleMac,
      pairedAt: DateTime.now(),
      capabilities: capabilities ?? const ['spp'],
    );

    _pairedDevices[callsign] = device;
    _saveToConfig();
    _pairingChangesController.add(device);

    LogService().log('BluetoothClassicPairing: Stored pairing for $callsign ($classicMac)');
  }

  /// Remove a pairing
  Future<void> removePairing(String callsign) async {
    final device = _pairedDevices.remove(callsign);
    if (device != null) {
      _saveToConfig();
      LogService().log('BluetoothClassicPairing: Removed pairing for $callsign');
    }
  }

  /// Update last connected timestamp for a device
  void updateLastConnected(String callsign) {
    final device = _pairedDevices[callsign];
    if (device != null) {
      _pairedDevices[callsign] = device.copyWithLastConnected(DateTime.now());
      _saveToConfig();
    }
  }

  /// Initiate BLE+ pairing flow from a BLE device
  ///
  /// This method:
  /// 1. Gets the Bluetooth Classic MAC from the BLE device (via HELLO handshake)
  /// 2. Triggers the system pairing dialog
  /// 3. On success, stores the pairing
  ///
  /// Returns true if pairing was successful
  Future<bool> initiatePairingFromBLE({
    required String callsign,
    required String classicMac,
    String? bleMac,
  }) async {
    final btService = BluetoothClassicService();
    await btService.initialize();

    // Check if already paired at system level
    final alreadyPaired = await btService.isPaired(classicMac);
    if (alreadyPaired) {
      // Device is already paired, just store the mapping
      await storePairing(
        callsign: callsign,
        classicMac: classicMac,
        bleMac: bleMac,
      );
      return true;
    }

    // Request system pairing
    LogService().log('BluetoothClassicPairing: Initiating pairing for $callsign ($classicMac)');
    final success = await btService.requestPairing(classicMac);

    if (success) {
      // Store the pairing
      await storePairing(
        callsign: callsign,
        classicMac: classicMac,
        bleMac: bleMac,
      );
      LogService().log('BluetoothClassicPairing: Pairing successful for $callsign');
      return true;
    } else {
      LogService().log('BluetoothClassicPairing: Pairing failed for $callsign');
      return false;
    }
  }

  /// Verify that stored pairings are still valid at the system level
  /// Removes any pairings that are no longer bonded
  Future<void> verifyPairings() async {
    final btService = BluetoothClassicService();
    final toRemove = <String>[];

    for (final entry in _pairedDevices.entries) {
      final isPaired = await btService.isPaired(entry.value.classicMac);
      if (!isPaired) {
        toRemove.add(entry.key);
        LogService().log('BluetoothClassicPairing: ${entry.key} is no longer paired at system level');
      }
    }

    for (final callsign in toRemove) {
      await removePairing(callsign);
    }
  }

  // Settings management

  /// Get the auto-upgrade threshold (bytes)
  int getAutoUpgradeThreshold() {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>?;
    return settings?['autoUpgradeThreshold'] as int? ?? 10 * 1024; // Default 10KB
  }

  /// Set the auto-upgrade threshold (bytes)
  void setAutoUpgradeThreshold(int bytes) {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>? ?? {};
    settings['autoUpgradeThreshold'] = bytes;
    config.set(_settingsKey, settings);
  }

  /// Check if should ask before auto-upgrade
  bool shouldAskBeforeUpgrade() {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>?;
    return settings?['askBeforeUpgrade'] as bool? ?? true;
  }

  /// Set ask before upgrade preference
  void setAskBeforeUpgrade(bool ask) {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>? ?? {};
    settings['askBeforeUpgrade'] = ask;
    config.set(_settingsKey, settings);
  }

  /// Check if should prefer Classic for large data
  bool shouldPreferClassicForLargeData() {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>?;
    return settings?['preferClassicForLargeData'] as bool? ?? true;
  }

  /// Set prefer Classic for large data preference
  void setPreferClassicForLargeData(bool prefer) {
    final config = ConfigService();
    final settings = config.get(_settingsKey) as Map<String, dynamic>? ?? {};
    settings['preferClassicForLargeData'] = prefer;
    config.set(_settingsKey, settings);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _pairingChangesController.close();
  }
}
