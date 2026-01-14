import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../util/nostr_key_generator.dart';
import '../platform/web_storage.dart' if (dart.library.io) '../platform/web_storage_stub.dart';
import 'storage_config.dart';
import 'log_service.dart';

/// Service for managing application configuration stored in config.json
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  File? _configFile;
  Map<String, dynamic> _config = {};
  static const String _webStorageKey = 'geogram_config';
  static const String _webStorageBackupKey = 'geogram_config_backup';

  /// Debounce timer for save operations
  Timer? _saveDebounceTimer;
  bool _pendingSave = false;
  static const Duration _saveDebounceDuration = Duration(milliseconds: 500);

  /// Initialize the config service and load existing configuration
  Future<void> init() async {
    if (kIsWeb) {
      await _initWeb();
    } else {
      await _initNative();
    }
  }

  /// Initialize for native platforms (file-based storage)
  ///
  /// Uses StorageConfig for path management. StorageConfig must be initialized
  /// before calling this method.
  Future<void> _initNative() async {
    final storageConfig = StorageConfig();
    if (!storageConfig.isInitialized) {
      throw StateError(
        'StorageConfig must be initialized before ConfigService. '
        'Call StorageConfig().init() first.',
      );
    }

    _configFile = File(storageConfig.configPath);

    if (await _configFile!.exists()) {
      await _load();
    } else {
      _createDefaultConfig();
      await _saveImmediate();
    }
  }

  /// Initialize for web platform (localStorage-based storage)
  Future<void> _initWeb() async {
    final stored = WebStorage.get(_webStorageKey);
    if (stored != null) {
      try {
        _config = json.decode(stored) as Map<String, dynamic>;
        // Keep a backup copy in localStorage
        WebStorage.set(_webStorageBackupKey, stored);
        return;
      } catch (e) {
        LogService().log('Error loading web config: $e');
      }
    }

    // Attempt to restore from backup when primary entry is missing or corrupted
    final backup = WebStorage.get(_webStorageBackupKey);
    if (backup != null) {
      try {
        _config = json.decode(backup) as Map<String, dynamic>;
        WebStorage.set(_webStorageKey, backup);
        return;
      } catch (e) {
        LogService().log('Error loading web config backup: $e');
      }
    }

    // Fall back to defaults only if both primary and backup are unusable
    _createDefaultConfig();
    await _saveImmediate();
  }

  /// Create default configuration
  void _createDefaultConfig() {
    _config = {
      'version': '1.0.0',
      'created': DateTime.now().toIso8601String(),
      'collections': <String, dynamic>{
        'favorites': <String>[],
      },
      'settings': <String, dynamic>{
        'theme': 'system',
        'language': 'en_US',
      },
    };
  }

  /// Load configuration from disk (native only)
  Future<void> _load() async {
    String? raw;
    try {
      raw = await _configFile!.readAsString();
      final data = json.decode(raw) as Map<String, dynamic>;
      _config = Map<String, dynamic>.from(data);
      await _writeBackup(raw);
      return;
    } catch (e) {
      stderr.writeln('Error loading config: $e');
    }

    // Attempt to recover from backup before falling back to defaults
    final recovered = await _restoreFromBackup();
    if (recovered) {
      return;
    }

    // Quarantine the corrupt file to avoid overwriting it and to aid debugging
    await _quarantineCorruptFile();
    _config = {};
  }

  /// Save configuration to storage (debounced to prevent too many file operations)
  void _save() {
    // Cancel any pending save and schedule a new one
    _saveDebounceTimer?.cancel();
    _pendingSave = true;
    _saveDebounceTimer = Timer(_saveDebounceDuration, () {
      _saveImmediate();
    });
  }

  /// Force immediate save (public, for use when app is closing)
  Future<void> saveNow() async {
    _saveDebounceTimer?.cancel();
    await _saveImmediate();
  }

  /// Save configuration immediately (used for initial save and when needed)
  Future<void> _saveImmediate() async {
    _pendingSave = false;
    if (kIsWeb) {
      try {
        final contents = JsonEncoder.withIndent('  ').convert(_config);
        WebStorage.set(_webStorageKey, contents);
        // Maintain a backup copy in case localStorage entry is corrupted
        WebStorage.set(_webStorageBackupKey, contents);
      } catch (e) {
        LogService().log('Error saving web config: $e');
      }
    } else {
      if (_configFile == null) {
        stderr.writeln('Error saving config: ConfigService not initialized');
        return;
      }
      try {
        final contents = JsonEncoder.withIndent('  ').convert(_config);

        // Ensure the config directory exists
        await _configFile!.parent.create(recursive: true);

        // Persist a backup of the last known good config before overwriting
        if (await _configFile!.exists()) {
          final existing = await _configFile!.readAsString();
          await _writeBackup(existing);
        }

        // Atomic-ish write: write to a temp file then rename
        final tmpFile = File('${_configFile!.path}.tmp');
        await tmpFile.writeAsString(contents, flush: true);
        await tmpFile.rename(_configFile!.path);
      } catch (e) {
        stderr.writeln('Error saving config: $e');
      }
    }
  }

  /// Get a configuration value
  dynamic get(String key, [dynamic defaultValue]) {
    return _config[key] ?? defaultValue;
  }

  /// Set a configuration value
  void set(String key, dynamic value) {
    _config[key] = value;
    _save();
  }

  /// Remove a configuration value
  void remove(String key) {
    _config.remove(key);
    _save();
  }

  /// Get nested configuration value using dot notation
  dynamic getNestedValue(String path, [dynamic defaultValue]) {
    final keys = path.split('.');
    dynamic current = _config;

    for (var key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return defaultValue;
      }
    }

    return current;
  }

  /// Set nested configuration value using dot notation
  void setNestedValue(String path, dynamic value) {
    final keys = path.split('.');
    Map<String, dynamic> current = _config;

    for (int i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      if (!current.containsKey(key) || current[key] is! Map<String, dynamic>) {
        current[key] = <String, dynamic>{};
      }
      current = current[key] as Map<String, dynamic>;
    }

    current[keys.last] = value;
    _save();
  }

  /// Check if a collection is favorited
  bool isFavorite(String collectionId) {
    final favorites = getNestedValue('collections.favorites', <String>[]) as List;
    return favorites.contains(collectionId);
  }

  /// Toggle favorite status of a collection
  void toggleFavorite(String collectionId) {
    final favorites = List<String>.from(
      getNestedValue('collections.favorites', <String>[]) as List
    );

    if (favorites.contains(collectionId)) {
      favorites.remove(collectionId);
    } else {
      favorites.add(collectionId);
    }

    setNestedValue('collections.favorites', favorites);
  }

  /// Get the full configuration map
  Map<String, dynamic> getAll() {
    return Map<String, dynamic>.from(_config);
  }

  /// Write a backup copy of the config alongside the main file
  Future<void> _writeBackup(String contents) async {
    if (_configFile == null) return;
    try {
      final backupFile = File('${_configFile!.path}.bak');
      await backupFile.parent.create(recursive: true);
      await backupFile.writeAsString(contents, flush: true);
    } catch (e) {
      stderr.writeln('Error writing config backup: $e');
    }
  }

  /// Restore config from backup if possible
  Future<bool> _restoreFromBackup() async {
    if (_configFile == null) return false;
    final backupFile = File('${_configFile!.path}.bak');
    if (!await backupFile.exists()) return false;

    try {
      final contents = await backupFile.readAsString();
      final data = json.decode(contents) as Map<String, dynamic>;
      _config = Map<String, dynamic>.from(data);

      // Rewrite the main file from the recovered backup to ensure future loads succeed
      final tmpFile = File('${_configFile!.path}.tmp');
      await tmpFile.writeAsString(contents, flush: true);
      await tmpFile.rename(_configFile!.path);
      stderr.writeln('ConfigService: Restored config from backup');
      return true;
    } catch (e) {
      stderr.writeln('Error restoring config from backup: $e');
      return false;
    }
  }

  /// Quarantine a corrupt config file to avoid losing it
  Future<void> _quarantineCorruptFile() async {
    if (_configFile == null) return;
    final file = _configFile!;
    if (!await file.exists()) return;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final quarantinePath = '${file.path}.corrupt-$timestamp';
    try {
      await file.rename(quarantinePath);
      stderr.writeln('ConfigService: Moved corrupt config to $quarantinePath');
    } catch (e) {
      stderr.writeln('ConfigService: Failed to quarantine corrupt config: $e');
    }
  }

  /// Store collection npub/nsec key pair
  void storeCollectionKeys(NostrKeys keys) {
    // Ensure collectionKeys section exists
    if (!_config.containsKey('collectionKeys')) {
      _config['collectionKeys'] = <String, dynamic>{};
    }

    final collectionKeys = _config['collectionKeys'] as Map<String, dynamic>;
    collectionKeys[keys.npub] = keys.toJson();

    _save();
    stderr.writeln('Stored keys for collection: ${keys.npub}');
  }

  /// Get nsec for a given npub
  String? getNsec(String npub) {
    final collectionKeys = _config['collectionKeys'] as Map<String, dynamic>?;
    if (collectionKeys == null || !collectionKeys.containsKey(npub)) {
      return null;
    }

    final keyData = collectionKeys[npub] as Map<String, dynamic>;
    return keyData['nsec'] as String?;
  }

  /// Check if we own this collection (have the nsec)
  bool isOwnedCollection(String npub) {
    return getNsec(npub) != null;
  }

  /// Get all owned collections (npubs we have nsec for)
  Map<String, String> getAllOwnedCollections() {
    final owned = <String, String>{};
    final collectionKeys = _config['collectionKeys'] as Map<String, dynamic>?;

    if (collectionKeys == null) {
      return owned;
    }

    for (var entry in collectionKeys.entries) {
      final npub = entry.key;
      final keyData = entry.value as Map<String, dynamic>;
      final nsec = keyData['nsec'] as String?;

      if (nsec != null) {
        owned[npub] = nsec;
      }
    }

    return owned;
  }

  /// Get auto-start on boot setting (defaults to true)
  bool get autoStartOnBoot {
    return getNestedValue('settings.autoStartOnBoot', true) as bool;
  }

  /// Set auto-start on boot setting
  /// Also syncs to SharedPreferences for native BootReceiver access
  Future<void> setAutoStartOnBoot(bool value) async {
    setNestedValue('settings.autoStartOnBoot', value);

    // Sync to SharedPreferences for native Java BootReceiver access
    if (!kIsWeb) {
      try {
        // Use method channel to sync to SharedPreferences
        // This is handled by the platform channel in MainActivity
        await _syncAutoStartToNative(value);
      } catch (e) {
        LogService().log('ConfigService: Error syncing auto-start to native: $e');
      }
    }
  }

  /// Sync auto-start setting to native SharedPreferences
  Future<void> _syncAutoStartToNative(bool value) async {
    // Import shared_preferences dynamically to avoid web issues
    final prefs = await _getSharedPreferences();
    if (prefs != null) {
      await prefs.setBool('auto_start_on_boot', value);
    }
  }

  /// Get SharedPreferences instance (lazy import to avoid web issues)
  Future<dynamic> _getSharedPreferences() async {
    try {
      // Using dynamic import pattern
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs;
    } catch (e) {
      return null;
    }
  }
}
