// Pure Dart Config Service for CLI mode (no Flutter dependencies)
// Reads/writes the same config.json format as the Flutter ConfigService
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'pure_storage_config.dart';

/// Pure Dart config service for CLI mode
/// Shares the same config.json format with the Flutter ConfigService
class CliConfigService {
  static final CliConfigService _instance = CliConfigService._internal();
  factory CliConfigService() => _instance;
  CliConfigService._internal();

  File? _configFile;
  Map<String, dynamic> _config = {};
  bool _initialized = false;
  File? get _backupFile =>
      _configFile != null ? File('${_configFile!.path}.bak') : null;

  /// Debounce timer for save operations
  Timer? _saveDebounceTimer;
  bool _pendingSave = false;
  static const Duration _saveDebounceDuration = Duration(milliseconds: 500);

  /// Initialize the config service and load existing configuration
  Future<void> init() async {
    if (_initialized) return;

    final storageConfig = PureStorageConfig();
    if (!storageConfig.isInitialized) {
      throw StateError(
        'PureStorageConfig must be initialized before CliConfigService. '
        'Call PureStorageConfig().init() first.',
      );
    }

    _configFile = File(storageConfig.configPath);

    if (await _configFile!.exists()) {
      await _load();
    } else {
      _createDefaultConfig();
      await _saveImmediate();
    }
    _initialized = true;
  }

  /// Create default configuration
  void _createDefaultConfig() {
    _config = {
      'version': '1.0.0',
      'created': DateTime.now().toIso8601String(),
      'collections': {
        'favorites': <String>[],
      },
      'settings': {
        'theme': 'system',
        'language': 'en',
      },
    };
  }

  /// Load configuration from disk
  Future<void> _load() async {
    String? raw;
    try {
      raw = await _configFile!.readAsString();
      _config = json.decode(raw) as Map<String, dynamic>;
      await _writeBackup(raw);
      return;
    } catch (e) {
      stderr.writeln('CliConfigService: Error loading config: $e');
    }

    // Try restoring from backup before falling back to defaults
    final restored = await _restoreFromBackup();
    if (restored) return;

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

  /// Save configuration immediately (used for initial save and when needed)
  Future<void> _saveImmediate() async {
    _pendingSave = false;
    if (_configFile == null) {
      stderr.writeln('CliConfigService: Error saving config: not initialized');
      return;
    }
    try {
      final contents = JsonEncoder.withIndent('  ').convert(_config);

      await _configFile!.parent.create(recursive: true);

      // Persist backup of the previous good config if present
      if (await _configFile!.exists()) {
        final existing = await _configFile!.readAsString();
        await _writeBackup(existing);
      }

      final tmpFile = File('${_configFile!.path}.tmp');
      await tmpFile.writeAsString(contents, flush: true);
      await tmpFile.rename(_configFile!.path);
    } catch (e) {
      stderr.writeln('CliConfigService: Error saving config: $e');
    }
  }

  /// Flush any pending saves immediately (call this before exiting or when immediate persistence is required)
  Future<void> flush() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_pendingSave) {
      await _saveImmediate();
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

  /// Get the full configuration map
  Map<String, dynamic> getAll() {
    return Map<String, dynamic>.from(_config);
  }

  Future<void> _writeBackup(String contents) async {
    if (_backupFile == null) return;
    try {
      await _backupFile!.parent.create(recursive: true);
      await _backupFile!.writeAsString(contents, flush: true);
    } catch (e) {
      stderr.writeln('CliConfigService: Error writing backup: $e');
    }
  }

  Future<bool> _restoreFromBackup() async {
    if (_backupFile == null || !await _backupFile!.exists()) return false;
    try {
      final contents = await _backupFile!.readAsString();
      _config = json.decode(contents) as Map<String, dynamic>;

      final tmpFile = File('${_configFile!.path}.tmp');
      await tmpFile.writeAsString(contents, flush: true);
      await tmpFile.rename(_configFile!.path);
      stderr.writeln('CliConfigService: Restored config from backup');
      return true;
    } catch (e) {
      stderr.writeln('CliConfigService: Error restoring backup: $e');
      return false;
    }
  }

  Future<void> _quarantineCorruptFile() async {
    if (_configFile == null || !await _configFile!.exists()) return;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final quarantinePath = '${_configFile!.path}.corrupt-$timestamp';
    try {
      await _configFile!.rename(quarantinePath);
      stderr.writeln(
        'CliConfigService: Moved corrupt config to $quarantinePath',
      );
    } catch (e) {
      stderr.writeln('CliConfigService: Failed to quarantine config: $e');
    }
  }
}
