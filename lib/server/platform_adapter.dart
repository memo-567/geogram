// Platform adapter interface for abstracting CLI vs App differences
import 'dart:typed_data';

/// Abstract interface for platform-specific operations
/// Implementations provided by PureStationServer (CLI) and StationServerService (App)
abstract class PlatformAdapter {
  /// Get the base data directory for the station
  String getDataDirectory();

  /// Get the tiles directory for cached map tiles
  String getTilesDirectory();

  /// Get the updates directory for mirrored updates
  String getUpdatesDirectory();

  /// Get the station callsign
  String getCallsign();

  /// Get the station npub (NOSTR public key)
  String getNpub();

  /// Get the station nsec (NOSTR private key)
  String getNsec();

  /// Log a message (level: INFO, WARN, ERROR, DEBUG)
  void log(String level, String message);

  /// Load an asset file (Flutter assets or file system)
  /// Returns null if asset not found
  Future<Uint8List?> loadAsset(String assetPath);

  /// Check if the platform supports Flutter services
  bool get hasFlutterServices;

  /// Get the current user profile callsign (for App mode)
  /// Returns station callsign for CLI mode
  String getCurrentUserCallsign();

  /// Get the current user npub (for App mode)
  /// Returns station npub for CLI mode
  String getCurrentUserNpub();

  /// Save settings to persistent storage
  Future<void> saveSettings(Map<String, dynamic> settings);

  /// Load settings from persistent storage
  Future<Map<String, dynamic>?> loadSettings();
}

/// CLI platform adapter implementation using pure Dart file I/O
class CliPlatformAdapter implements PlatformAdapter {
  final String _dataDir;
  final String Function() _getCallsign;
  final String Function() _getNpub;
  final String Function() _getNsec;
  final void Function(String, String) _logFn;
  final Future<void> Function(Map<String, dynamic>) _saveFn;
  final Future<Map<String, dynamic>?> Function() _loadFn;

  CliPlatformAdapter({
    required String dataDir,
    required String Function() getCallsign,
    required String Function() getNpub,
    required String Function() getNsec,
    required void Function(String, String) log,
    required Future<void> Function(Map<String, dynamic>) saveSettings,
    required Future<Map<String, dynamic>?> Function() loadSettings,
  })  : _dataDir = dataDir,
        _getCallsign = getCallsign,
        _getNpub = getNpub,
        _getNsec = getNsec,
        _logFn = log,
        _saveFn = saveSettings,
        _loadFn = loadSettings;

  @override
  String getDataDirectory() => _dataDir;

  @override
  String getTilesDirectory() => '$_dataDir/tiles';

  @override
  String getUpdatesDirectory() => '$_dataDir/updates';

  @override
  String getCallsign() => _getCallsign();

  @override
  String getNpub() => _getNpub();

  @override
  String getNsec() => _getNsec();

  @override
  void log(String level, String message) => _logFn(level, message);

  @override
  Future<Uint8List?> loadAsset(String assetPath) async {
    // CLI mode loads from file system
    final file = await _loadFile('$_dataDir/$assetPath');
    if (file != null) return file;

    // Try current directory
    return _loadFile(assetPath);
  }

  Future<Uint8List?> _loadFile(String path) async {
    try {
      final file = await _readFile(path);
      return file;
    } catch (_) {
      return null;
    }
  }

  // Platform-specific file read (to be implemented by actual CLI code)
  Future<Uint8List?> _readFile(String path) async {
    // This will be overridden by the actual implementation
    return null;
  }

  @override
  bool get hasFlutterServices => false;

  @override
  String getCurrentUserCallsign() => _getCallsign();

  @override
  String getCurrentUserNpub() => _getNpub();

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) => _saveFn(settings);

  @override
  Future<Map<String, dynamic>?> loadSettings() => _loadFn();
}

/// App platform adapter implementation using Flutter services
class AppPlatformAdapter implements PlatformAdapter {
  final String _dataDir;
  final String Function() _getCallsign;
  final String Function() _getNpub;
  final String Function() _getNsec;
  final String Function() _getUserCallsign;
  final String Function() _getUserNpub;
  final void Function(String, String) _logFn;
  final Future<Uint8List?> Function(String) _loadAssetFn;
  final Future<void> Function(Map<String, dynamic>) _saveFn;
  final Future<Map<String, dynamic>?> Function() _loadFn;

  AppPlatformAdapter({
    required String dataDir,
    required String Function() getCallsign,
    required String Function() getNpub,
    required String Function() getNsec,
    required String Function() getUserCallsign,
    required String Function() getUserNpub,
    required void Function(String, String) log,
    required Future<Uint8List?> Function(String) loadAsset,
    required Future<void> Function(Map<String, dynamic>) saveSettings,
    required Future<Map<String, dynamic>?> Function() loadSettings,
  })  : _dataDir = dataDir,
        _getCallsign = getCallsign,
        _getNpub = getNpub,
        _getNsec = getNsec,
        _getUserCallsign = getUserCallsign,
        _getUserNpub = getUserNpub,
        _logFn = log,
        _loadAssetFn = loadAsset,
        _saveFn = saveSettings,
        _loadFn = loadSettings;

  @override
  String getDataDirectory() => _dataDir;

  @override
  String getTilesDirectory() => '$_dataDir/tiles';

  @override
  String getUpdatesDirectory() => '$_dataDir/updates';

  @override
  String getCallsign() => _getCallsign();

  @override
  String getNpub() => _getNpub();

  @override
  String getNsec() => _getNsec();

  @override
  void log(String level, String message) => _logFn(level, message);

  @override
  Future<Uint8List?> loadAsset(String assetPath) => _loadAssetFn(assetPath);

  @override
  bool get hasFlutterServices => true;

  @override
  String getCurrentUserCallsign() => _getUserCallsign();

  @override
  String getCurrentUserNpub() => _getUserNpub();

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) => _saveFn(settings);

  @override
  Future<Map<String, dynamic>?> loadSettings() => _loadFn();
}
