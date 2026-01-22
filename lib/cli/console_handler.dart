/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Generic console handler with platform-agnostic command logic.
 * Uses ConsoleIO for I/O abstraction.
 */

import 'console_io.dart';
import 'game/game_config.dart';
import '../tts/services/tts_service.dart';
import '../version.dart';

/// Service interface for profile management
abstract class ProfileServiceInterface {
  String get activeCallsign;
  String get activeNpub;
  String? get activeNickname;
  bool get isStationProfile;
  List<ProfileInfo> getAllProfiles();
  String? get activeProfileId;
  ProfileInfo? getProfileByCallsign(String callsign);
  ProfileInfo? getProfileById(String id);
  Future<ProfileInfo> createProfile({bool isStation = false});
  Future<void> switchToProfile(String id);
}

/// Basic profile info used across platforms
class ProfileInfo {
  final String id;
  final String callsign;
  final String npub;
  final String nickname;
  final bool isStation;
  final String? locationName;

  ProfileInfo({
    required this.id,
    required this.callsign,
    required this.npub,
    this.nickname = '',
    this.isStation = false,
    this.locationName,
  });
}

/// Service interface for station/server management
abstract class StationServiceInterface {
  bool get isRunning;
  int get port;
  String get callsign;
  int get connectedDevices;
  int get uptime;
  int get cacheSize;
  double get cacheSizeMB;
  double get maxCacheSize;
  bool get tileServerEnabled;
  bool get osmFallbackEnabled;
  int get maxZoomLevel;

  Future<bool> start();
  Future<void> stop();
  Future<void> setPort(int port);
  void clearCache();
}

/// Callback type for game execution
/// Called when 'play' command is issued and raw mode is supported
/// Returns game path to play, handler should run the game
typedef GamePlayCallback = Future<void> Function(String gamePath);

/// Generic console handler with all shared command logic
///
/// Uses [ConsoleIO] for platform-agnostic I/O.
/// Services are injected to support different implementations.
class ConsoleHandler {
  final ConsoleIO io;
  final ProfileServiceInterface profileService;
  final StationServiceInterface? stationService;
  final GameConfig? gameConfig;

  /// Callback for game execution (only called when supportsRawMode is true)
  GamePlayCallback? onPlayGame;

  /// Virtual filesystem current path
  String _currentPath = '/';

  /// Root directories in virtual filesystem
  List<String> get rootDirs {
    final dirs = ['profiles', 'config', 'logs'];
    if (stationService != null) dirs.add('station');
    if (gameConfig != null) dirs.add('games');
    dirs.sort();
    return dirs;
  }

  /// Directory-specific commands for TAB completion
  Map<String, List<String>> get dirCommands => {
    '/': ['ls', 'cd', 'pwd', 'status', 'help', 'quit', 'exit', 'clear', 'profile', 'station', 'games', 'play'],
    '/profiles': ['ls', 'cd', 'pwd', 'profile', 'status', 'help', 'quit', 'exit', 'clear'],
    '/config': ['ls', 'cd', 'pwd', 'status', 'help', 'quit', 'exit', 'clear'],
    '/logs': ['ls', 'cd', 'pwd', 'status', 'help', 'quit', 'exit', 'clear'],
    '/station': ['ls', 'cd', 'pwd', 'start', 'stop', 'status', 'port', 'cache', 'help', 'quit', 'exit', 'clear'],
    '/games': ['ls', 'cd', 'pwd', 'games', 'play', 'status', 'help', 'quit', 'exit', 'clear'],
  };

  ConsoleHandler({
    required this.io,
    required this.profileService,
    this.stationService,
    this.gameConfig,
  });

  /// Get current path
  String get currentPath => _currentPath;

  /// Get prompt string
  String getPrompt() => 'geogram:$_currentPath\$ ';

  /// Get welcome banner
  String getBanner() {
    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('=' * 50);
    buf.writeln('  Geogram v$appVersion - Console');
    buf.writeln('  Active Profile: ${profileService.activeCallsign}${profileService.isStationProfile ? ' (Relay)' : ''}');
    buf.writeln('=' * 50);
    buf.writeln();
    buf.writeln('Type "help" for available commands.');
    buf.writeln();
    return buf.toString();
  }

  /// Process a command
  /// Returns true if the command indicates exit
  Future<bool> processCommand(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;

    final parts = trimmed.split(RegExp(r'\s+'));
    final command = parts[0].toLowerCase();
    final args = parts.length > 1 ? parts.sublist(1) : <String>[];

    return await _dispatchCommand(command, args);
  }

  /// Dispatch command to appropriate handler
  Future<bool> _dispatchCommand(String command, List<String> args) async {
    // Context-specific commands when in /station
    if (stationService != null && (_currentPath == '/station' || _currentPath.startsWith('/station/'))) {
      switch (command) {
        case 'start':
          await _handleStationStart();
          return false;
        case 'stop':
          await _handleStationStop();
          return false;
        case 'port':
          await _handleStationPort(args);
          return false;
        case 'cache':
          _handleStationCache(args);
          return false;
      }
    }

    // Global commands
    switch (command) {
      case 'help':
        _printHelp();
        return false;
      case 'status':
        _printStatus();
        return false;
      case 'ls':
        _handleLs(args);
        return false;
      case 'cd':
        _handleCd(args);
        return false;
      case 'pwd':
        io.writeln(_currentPath);
        return false;
      case 'profile':
        await _handleProfile(args);
        return false;
      case 'station':
        if (stationService != null) {
          await _handleStation(args);
        } else {
          _writeError('Station service not available');
        }
        return false;
      case 'games':
        if (gameConfig != null) {
          await _handleGames(args);
        } else {
          _writeError('Games not available');
        }
        return false;
      case 'play':
        if (gameConfig != null) {
          await _handlePlay(args);
        } else {
          _writeError('Games not available');
        }
        return false;
      case 'clear':
        io.clear();
        return false;
      case 'quit':
      case 'exit':
        return true;
      case 'say':
        await _handleSay(args);
        return false;
      default:
        _writeError('Unknown command: $command. Type "help" for available commands.');
        return false;
    }
  }

  // --- Help and Status ---

  void _printHelp() {
    io.writeln();
    io.writeln('Available Commands:');
    io.writeln();
    io.writeln('  Navigation:');
    io.writeln('    ls [path]          List directory contents');
    io.writeln('    cd <path>          Change directory');
    io.writeln('    pwd                Print working directory');
    io.writeln();
    io.writeln('  Profile Management:');
    io.writeln('    profile list       List all profiles');
    io.writeln('    profile switch <id|callsign>  Switch active profile');
    io.writeln('    profile create [--station]    Create new profile');
    io.writeln('    profile info [id]  Show profile details');
    io.writeln();
    if (stationService != null) {
      io.writeln('  Station Server:');
      io.writeln('    station start        Start the station server');
      io.writeln('    station stop         Stop the station server');
      io.writeln('    station status       Show station server status');
      io.writeln('    station port <port>  Set station server port');
      io.writeln('    station cache clear  Clear tile cache');
      io.writeln('    station cache stats  Show cache statistics');
      io.writeln();
    }
    if (gameConfig != null) {
      io.writeln('  Games:');
      io.writeln('    games list         List available games');
      io.writeln('    games info <name>  Show game details');
      io.writeln('    play <name>        Play a game');
      io.writeln();
    }
    io.writeln('  General:');
    io.writeln('    status             Show application status');
    io.writeln('    help               Show this help message');
    io.writeln('    clear              Clear the screen');
    io.writeln('    say <text>         Speak text using TTS');
    io.writeln('    quit               Exit the console');
    io.writeln();
    io.writeln('  Virtual Filesystem:');
    io.writeln('    /profiles/         List all profiles/callsigns');
    io.writeln('    /config/           Configuration settings');
    io.writeln('    /logs/             View logs');
    if (stationService != null) {
      io.writeln('    /station/          Station status and commands');
    }
    if (gameConfig != null) {
      io.writeln('    /games/            Available games');
    }
    io.writeln();
  }

  void _printStatus() {
    final profiles = profileService.getAllProfiles();

    io.writeln();
    io.writeln('Geogram Status');
    io.writeln('-' * 40);
    io.writeln('Version:        $appVersion');
    io.writeln('Profile:        ${profileService.activeCallsign}');
    io.writeln('Mode:           ${profileService.isStationProfile ? 'Relay (X3 callsign)' : 'Standard'}');
    io.writeln('Total Profiles: ${profiles.length}');
    final nickname = profileService.activeNickname;
    io.writeln('Nickname:       ${nickname?.isNotEmpty == true ? nickname : '(not set)'}');
    io.writeln('NPub:           ${_truncateNpub(profileService.activeNpub)}');
    io.writeln();

    if (stationService != null) {
      io.writeln('Station Server:');
      io.writeln('-' * 40);
      if (stationService!.isRunning) {
        io.writeln('Status:         Running');
        io.writeln('Port:           ${stationService!.port}');
        io.writeln('Devices:        ${stationService!.connectedDevices}');
        io.writeln('Uptime:         ${_formatUptime(stationService!.uptime)}');
        io.writeln('Cache:          ${stationService!.cacheSize} tiles (${stationService!.cacheSizeMB.toStringAsFixed(1)} MB)');
      } else {
        io.writeln('Status:         Stopped');
        io.writeln('Port:           ${stationService!.port}');
      }
      io.writeln();
    }
  }

  // --- Navigation Commands ---

  void _handleLs(List<String> args) {
    final path = args.isNotEmpty ? _resolvePath(args[0]) : _currentPath;

    if (path == '/') {
      for (final dir in rootDirs) {
        io.writeln('$dir/');
      }
    } else if (path == '/profiles') {
      final profiles = profileService.getAllProfiles();
      final activeId = profileService.activeProfileId;

      for (final profile in profiles) {
        final isActive = profile.id == activeId;
        final marker = isActive ? '* ' : '  ';
        final stationTag = profile.isStation ? ' [station]' : '';
        io.writeln('$marker${profile.callsign}/$stationTag');
      }
    } else if (path.startsWith('/profiles/')) {
      final callsign = path.substring('/profiles/'.length).replaceAll('/', '');
      final profile = profileService.getProfileByCallsign(callsign);

      if (profile == null) {
        _writeError('Profile not found: $callsign');
        return;
      }

      io.writeln('collections/');
      io.writeln('chat/');
      io.writeln('settings/');
    } else if (path == '/config') {
      io.writeln('profile.json');
      io.writeln('config.json');
      if (stationService != null) {
        io.writeln('stationServer.json');
      }
    } else if (path == '/logs') {
      io.writeln('geogram.log');
    } else if (path == '/station' && stationService != null) {
      final status = stationService!.isRunning ? 'Running' : 'Stopped';
      io.writeln('status      $status');
      io.writeln('devices/');
      io.writeln('config/');
      io.writeln('cache/');
    } else if (path == '/games' && gameConfig != null) {
      _listGames();
    } else {
      _writeError('Directory not found: $path');
    }
  }

  void _handleCd(List<String> args) {
    if (args.isEmpty) {
      _currentPath = '/';
      return;
    }

    final target = _resolvePath(args[0]);

    // Validate path: must be root, a root directory, or a valid subdirectory
    if (_isValidPath(target)) {
      _currentPath = target;
    } else {
      _writeError('Directory not found: ${args[0]}');
    }
  }

  /// Check if a path is valid in the virtual filesystem
  bool _isValidPath(String path) {
    if (path == '/') return true;

    final parts = path.substring(1).split('/');
    if (parts.isEmpty) return false;

    // First part must be a root directory
    final rootDir = parts[0];
    if (!rootDirs.contains(rootDir)) return false;

    // For now, only allow one level deep (e.g., /games, /profiles)
    // Subdirectories like /profiles/<callsign> are handled specially
    if (parts.length == 1) return true;

    // Allow /profiles/<callsign> paths
    if (rootDir == 'profiles' && parts.length == 2) {
      final callsign = parts[1];
      return profileService.getProfileByCallsign(callsign) != null;
    }

    return false;
  }

  // --- Profile Commands ---

  Future<void> _handleProfile(List<String> args) async {
    if (args.isEmpty) {
      _writeError('Usage: profile <list|switch|create|info>');
      return;
    }

    final subcommand = args[0].toLowerCase();
    final subargs = args.length > 1 ? args.sublist(1) : <String>[];

    switch (subcommand) {
      case 'list':
        _handleProfileList();
        break;
      case 'switch':
        await _handleProfileSwitch(subargs);
        break;
      case 'create':
        await _handleProfileCreate(subargs);
        break;
      case 'info':
        _handleProfileInfo(subargs);
        break;
      default:
        _writeError('Unknown profile command: $subcommand');
    }
  }

  void _handleProfileList() {
    final profiles = profileService.getAllProfiles();
    final activeId = profileService.activeProfileId;

    io.writeln();
    io.writeln('Profiles:');
    io.writeln('-' * 50);

    for (final profile in profiles) {
      final isActive = profile.id == activeId;
      final marker = isActive ? '* ' : '  ';
      final modeTag = profile.isStation ? '[Relay]' : '[Standard]';

      io.writeln('$marker${profile.callsign.padRight(12)} $modeTag');
      if (profile.nickname.isNotEmpty) {
        io.writeln('    Nickname: ${profile.nickname}');
      }
    }
    io.writeln();
  }

  Future<void> _handleProfileSwitch(List<String> args) async {
    if (args.isEmpty) {
      _writeError('Usage: profile switch <callsign|id>');
      return;
    }

    final target = args[0];

    var profile = profileService.getProfileByCallsign(target);
    profile ??= profileService.getProfileById(target);

    if (profile == null) {
      _writeError('Profile not found: $target');
      return;
    }

    await profileService.switchToProfile(profile.id);
    io.writeln('Switched to profile: ${profile.callsign}${profile.isStation ? ' (Relay Mode)' : ''}');
  }

  Future<void> _handleProfileCreate(List<String> args) async {
    final isStation = args.contains('--station');

    io.writeln('Creating new profile...');

    final profile = await profileService.createProfile(isStation: isStation);

    io.writeln('Created ${isStation ? 'station ' : ''}profile: ${profile.callsign}');
    io.writeln('Use "profile switch ${profile.callsign}" to activate.');
  }

  void _handleProfileInfo(List<String> args) {
    ProfileInfo? profile;

    if (args.isNotEmpty) {
      profile = profileService.getProfileByCallsign(args[0]);
      profile ??= profileService.getProfileById(args[0]);
    } else {
      final activeId = profileService.activeProfileId;
      if (activeId != null) {
        profile = profileService.getProfileById(activeId);
      }
    }

    if (profile == null) {
      _writeError('Profile not found');
      return;
    }

    final isActive = profile.id == profileService.activeProfileId;

    io.writeln();
    io.writeln('Profile: ${profile.callsign}${isActive ? ' (active)' : ''}');
    io.writeln('-' * 40);
    io.writeln('ID:       ${profile.id}');
    io.writeln('Mode:     ${profile.isStation ? 'Relay (X3)' : 'Standard'}');
    io.writeln('Nickname: ${profile.nickname.isNotEmpty ? profile.nickname : '(not set)'}');
    io.writeln('NPub:     ${profile.npub}');
    if (profile.locationName?.isNotEmpty == true) {
      io.writeln('Location: ${profile.locationName}');
    }
    io.writeln();
  }

  // --- Station Commands ---

  Future<void> _handleStation(List<String> args) async {
    if (stationService == null) {
      _writeError('Station service not available');
      return;
    }

    if (args.isEmpty) {
      _printStationStatus();
      return;
    }

    final subcommand = args[0].toLowerCase();
    final subargs = args.length > 1 ? args.sublist(1) : <String>[];

    switch (subcommand) {
      case 'start':
        await _handleStationStart();
        break;
      case 'stop':
        await _handleStationStop();
        break;
      case 'status':
        _printStationStatus();
        break;
      case 'port':
        await _handleStationPort(subargs);
        break;
      case 'cache':
        _handleStationCache(subargs);
        break;
      default:
        _writeError('Unknown station command: $subcommand');
        _writeError('Available: start, stop, status, port, cache');
    }
  }

  Future<void> _handleStationStart() async {
    if (stationService!.isRunning) {
      io.writeln('Station server is already running on port ${stationService!.port}');
      return;
    }

    io.writeln('Starting station server on port ${stationService!.port}...');
    final success = await stationService!.start();

    if (success) {
      io.writeln('Station server started successfully');
      io.writeln('  Port: ${stationService!.port}');
      io.writeln('  Status: http://localhost:${stationService!.port}/api/status');
    } else {
      _writeError('Failed to start station server');
    }
  }

  Future<void> _handleStationStop() async {
    if (!stationService!.isRunning) {
      io.writeln('Station server is not running');
      return;
    }

    io.writeln('Stopping station server...');
    await stationService!.stop();
    io.writeln('Station server stopped');
  }

  void _printStationStatus() {
    io.writeln();
    io.writeln('Station Server Status');
    io.writeln('-' * 40);

    if (stationService!.isRunning) {
      io.writeln('Status:        Running');
      io.writeln('Port:          ${stationService!.port}');
      io.writeln('Callsign:      ${stationService!.callsign}');
      io.writeln('Devices:       ${stationService!.connectedDevices}');
      io.writeln('Uptime:        ${_formatUptime(stationService!.uptime)}');
      io.writeln('Cache:         ${stationService!.cacheSize} tiles (${stationService!.cacheSizeMB.toStringAsFixed(1)} MB)');
    } else {
      io.writeln('Status:        Stopped');
    }

    io.writeln();
    io.writeln('Settings:');
    io.writeln('-' * 40);
    io.writeln('Port:          ${stationService!.port}');
    io.writeln('Tile Server:   ${stationService!.tileServerEnabled ? 'Enabled' : 'Disabled'}');
    io.writeln('OSM Fallback:  ${stationService!.osmFallbackEnabled ? 'Enabled' : 'Disabled'}');
    io.writeln('Max Zoom:      ${stationService!.maxZoomLevel}');
    io.writeln('Max Cache:     ${stationService!.maxCacheSize.toStringAsFixed(0)} MB');
    io.writeln();
  }

  Future<void> _handleStationPort(List<String> args) async {
    if (args.isEmpty) {
      io.writeln('Current port: ${stationService!.port}');
      return;
    }

    final portStr = args[0];
    final port = int.tryParse(portStr);

    if (port == null || port < 1 || port > 65535) {
      _writeError('Invalid port number: $portStr (must be 1-65535)');
      return;
    }

    await stationService!.setPort(port);
    io.writeln('Port set to $port');

    if (stationService!.isRunning) {
      io.writeln('Station server will restart on new port...');
    }
  }

  void _handleStationCache(List<String> args) {
    if (args.isEmpty) {
      io.writeln('Cache: ${stationService!.cacheSize} tiles (${stationService!.cacheSizeMB.toStringAsFixed(1)} MB)');
      return;
    }

    final subcommand = args[0].toLowerCase();

    switch (subcommand) {
      case 'clear':
        stationService!.clearCache();
        io.writeln('Cache cleared');
        break;
      case 'stats':
        io.writeln();
        io.writeln('Cache Statistics');
        io.writeln('-' * 30);
        io.writeln('Tiles:    ${stationService!.cacheSize}');
        io.writeln('Size:     ${stationService!.cacheSizeMB.toStringAsFixed(1)} MB');
        io.writeln('Max Size: ${stationService!.maxCacheSize.toStringAsFixed(0)} MB');
        io.writeln();
        break;
      default:
        _writeError('Unknown cache command: $subcommand');
        _writeError('Available: clear, stats');
    }
  }

  // --- Games Commands ---

  Future<void> _handleGames(List<String> args) async {
    if (gameConfig == null) {
      _writeError('Games not available');
      return;
    }

    if (args.isEmpty) {
      _listGames();
      return;
    }

    switch (args[0].toLowerCase()) {
      case 'list':
        _listGames();
        break;
      case 'info':
        if (args.length < 2) {
          _writeError('Usage: games info <game-name>');
        } else {
          _showGameInfo(args[1]);
        }
        break;
      default:
        _writeError('Unknown games command: ${args[0]}');
        io.writeln('Available: list, info');
    }
  }

  void _listGames() {
    final games = gameConfig!.listGames();

    io.writeln();
    io.writeln('Available Games (${games.length})');
    io.writeln('-' * 40);

    if (games.isEmpty) {
      io.writeln('No games found in ${gameConfig!.gamesDirectory}');
      io.writeln('Add .md game files to play');
    } else {
      for (final game in games) {
        final name = game.path.split('/').last;
        final info = gameConfig!.getGameInfo(name);
        final title = info?['title'] ?? name.replaceAll('.md', '');
        io.writeln('  ${name.padRight(25)} $title');
      }
    }

    io.writeln();
    io.writeln('Use "play <game-name>" to start a game');
    io.writeln();
  }

  void _showGameInfo(String name) {
    final info = gameConfig!.getGameInfo(name);

    if (info == null) {
      _writeError('Game not found: $name');
      return;
    }

    io.writeln();
    io.writeln('Game: ${info['title']}');
    io.writeln('-' * 40);
    io.writeln('File:      ${info['name']}');
    io.writeln('Scenes:    ${info['scenes']}');
    io.writeln('Items:     ${info['items']}');
    io.writeln('Opponents: ${info['opponents']}');
    io.writeln('Actions:   ${info['actions']}');
    io.writeln();
    io.writeln('To play: play ${info['name']}');
    io.writeln();
  }

  Future<void> _handlePlay(List<String> args) async {
    if (gameConfig == null) {
      _writeError('Games not available');
      return;
    }

    if (args.isEmpty) {
      _writeError('Usage: play <game-name.md>');
      io.writeln('Use "ls /games" or "games list" to see available games');
      return;
    }

    final gameName = args[0];
    final gamePath = gameConfig!.getGamePath(gameName);

    if (gamePath == null) {
      _writeError('Game not found: $gameName');
      io.writeln('Use "ls /games" or "games list" to see available games');
      return;
    }

    // Play the game via callback
    if (onPlayGame != null) {
      await onPlayGame!(gamePath);
    } else {
      io.writeln('Game execution not configured');
    }
  }

  // --- Utility Methods ---

  String _resolvePath(String path) {
    if (path.startsWith('/')) {
      return _normalizePath(path);
    }

    if (path == '..') {
      final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return '/';
      parts.removeLast();
      return parts.isEmpty ? '/' : '/${parts.join('/')}';
    }

    if (path == '.') {
      return _currentPath;
    }

    final newPath = _currentPath == '/' ? '/$path' : '$_currentPath/$path';
    return _normalizePath(newPath);
  }

  String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    var normalized = path.replaceAll(RegExp(r'/+'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _formatUptime(int minutes) {
    if (minutes < 60) return '${minutes}m';
    if (minutes < 1440) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}m';
    }
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    return '${days}d ${hours}h';
  }

  // --- Text-to-Speech ---

  Future<void> _handleSay(List<String> args) async {
    if (args.isEmpty) {
      io.writeln('Usage: say <text>');
      io.writeln('Example: say Hello world');
      return;
    }

    final text = args.join(' ');
    io.writeln('Speaking...');

    try {
      final tts = TtsService();

      // Ensure model is loaded (shows download progress)
      if (!tts.isLoaded) {
        io.writeln('Loading TTS model...');
        await for (final progress in tts.load()) {
          if (progress < 1.0) {
            // Could show progress here if desired
          }
        }

        if (!tts.isLoaded) {
          _writeError('Failed to load TTS model');
          return;
        }
      }

      await tts.speak(text);
    } catch (e) {
      _writeError('TTS error: $e');
    }
  }

  String _truncateNpub(String npub) {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 12)}...${npub.substring(npub.length - 6)}';
  }

  void _writeError(String message) {
    io.writeln('ERROR: $message');
  }
}
