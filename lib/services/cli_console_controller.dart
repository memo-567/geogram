/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * CLI Console Controller for Flutter UI.
 * Uses the shared ConsoleHandler with BufferConsoleIO.
 */

import 'dart:async';
import 'dart:io';

import '../cli/console_completer.dart';
import '../cli/console_handler.dart';
import '../cli/console_io_buffer.dart';
import '../cli/game/game_config.dart';
import '../cli/game/game_engine_io.dart';
import '../cli/game/game_parser.dart';
import '../cli/game/game_screen_io.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import '../services/callsign_generator.dart';
import '../services/station_server_service.dart';
import '../services/storage_config.dart';

/// Adapter for ProfileService to implement ProfileServiceInterface
class _ProfileServiceAdapter implements ProfileServiceInterface {
  final ProfileService _service = ProfileService();

  @override
  String get activeCallsign => _service.getProfile().callsign;

  @override
  String get activeNpub => _service.getProfile().npub;

  @override
  String? get activeNickname => _service.getProfile().nickname;

  @override
  bool get isStationProfile =>
      CallsignGenerator.isStationCallsign(_service.getProfile().callsign);

  @override
  List<ProfileInfo> getAllProfiles() {
    return _service.getAllProfiles().map((p) => ProfileInfo(
      id: p.id,
      callsign: p.callsign,
      npub: p.npub,
      nickname: p.nickname,
      isStation: CallsignGenerator.isStationCallsign(p.callsign),
      locationName: p.locationName,
    )).toList();
  }

  @override
  String? get activeProfileId => _service.activeProfileId;

  @override
  ProfileInfo? getProfileByCallsign(String callsign) {
    final p = _service.getProfileByCallsign(callsign);
    if (p == null) return null;
    return ProfileInfo(
      id: p.id,
      callsign: p.callsign,
      npub: p.npub,
      nickname: p.nickname,
      isStation: CallsignGenerator.isStationCallsign(p.callsign),
      locationName: p.locationName,
    );
  }

  @override
  ProfileInfo? getProfileById(String id) {
    final p = _service.getProfileById(id);
    if (p == null) return null;
    return ProfileInfo(
      id: p.id,
      callsign: p.callsign,
      npub: p.npub,
      nickname: p.nickname,
      isStation: CallsignGenerator.isStationCallsign(p.callsign),
      locationName: p.locationName,
    );
  }

  @override
  Future<ProfileInfo> createProfile({bool isStation = false}) async {
    final p = await _service.createNewProfile(
      type: isStation ? ProfileType.station : ProfileType.client,
    );
    return ProfileInfo(
      id: p.id,
      callsign: p.callsign,
      npub: p.npub,
      nickname: p.nickname,
      isStation: CallsignGenerator.isStationCallsign(p.callsign),
      locationName: p.locationName,
    );
  }

  @override
  Future<void> switchToProfile(String id) async {
    await _service.switchToProfile(id);
  }
}

/// Adapter for StationServerService to implement StationServiceInterface
class _StationServiceAdapter implements StationServiceInterface {
  final StationServerService _service = StationServerService();

  @override
  bool get isRunning => _service.isRunning;

  @override
  int get port => _service.settings.port;

  @override
  String get callsign {
    final status = _service.getStatus();
    return status['callsign'] as String? ?? '';
  }

  @override
  int get connectedDevices => _service.connectedDevices;

  @override
  int get uptime {
    final status = _service.getStatus();
    return status['uptime'] as int? ?? 0;
  }

  @override
  int get cacheSize {
    final status = _service.getStatus();
    return status['cache_size'] as int? ?? 0;
  }

  @override
  double get cacheSizeMB {
    final status = _service.getStatus();
    return (status['cache_size_mb'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  double get maxCacheSize => _service.settings.maxCacheSize.toDouble();

  @override
  bool get tileServerEnabled => _service.settings.tileServerEnabled;

  @override
  bool get osmFallbackEnabled => _service.settings.osmFallbackEnabled;

  @override
  int get maxZoomLevel => _service.settings.maxZoomLevel;

  @override
  Future<bool> start() async => await _service.start();

  @override
  Future<void> stop() async => await _service.stop();

  @override
  Future<void> setPort(int port) async {
    final settings = _service.settings.copyWith(port: port);
    await _service.updateSettings(settings);
  }

  @override
  void clearCache() => _service.clearCache();
}

/// Adapter for CompletionDataProvider
class _CompletionDataProviderAdapter implements CompletionDataProvider {
  final ProfileService _profileService = ProfileService();

  @override
  List<String> getConnectedCallsigns() {
    // In Flutter UI mode, we don't have direct access to connected devices
    // This would need to be implemented via station server service if needed
    return [];
  }

  @override
  Map<String, String> getChatRooms() {
    // In Flutter UI mode, chat rooms would come from a different source
    return {};
  }

  @override
  List<({String callsign, String? nickname, bool isStation})> getProfiles() {
    return _profileService.getAllProfiles().map((p) => (
      callsign: p.callsign,
      nickname: p.nickname.isNotEmpty ? p.nickname : null,
      isStation: CallsignGenerator.isStationCallsign(p.callsign),
    )).toList();
  }
}

/// CLI Console Controller for Flutter UI
///
/// Uses the shared [ConsoleHandler] with [BufferConsoleIO] for output collection.
/// This eliminates code duplication with pure_console.dart.
class CliConsoleController {
  late ConsoleHandler _handler;
  late final BufferConsoleIO _io;
  GameConfig? _gameConfig;

  /// Whether we're currently in game mode
  bool _inGame = false;

  /// Completer for game input
  Completer<String?>? _inputCompleter;

  /// Current game engine (if running)
  GameEngineIO? _currentGame;

  /// Callback for when game output is available
  void Function(String output)? onGameOutput;

  CliConsoleController() {
    _io = BufferConsoleIO();
    _handler = ConsoleHandler(
      io: _io,
      profileService: _ProfileServiceAdapter(),
      stationService: _StationServiceAdapter(),
      gameConfig: null, // Will be set when initialized
    );
  }

  /// Initialize (loads games if available)
  Future<void> initialize() async {
    // Check if StorageConfig is initialized
    if (!StorageConfig().isInitialized) {
      return;
    }

    try {
      _gameConfig = GameConfig();
      // Use console folder for games
      final consoleDir = '${StorageConfig().baseDir}/console';
      await _gameConfig!.initialize(consoleDir);

      // Recreate handler with game config and game play callback
      _handler = ConsoleHandler(
        io: _io,
        profileService: _ProfileServiceAdapter(),
        stationService: _StationServiceAdapter(),
        gameConfig: _gameConfig,
      );
      _handler.onPlayGame = _playGame;
    } catch (e) {
      // Games not available on this platform
      _gameConfig = null;
    }
  }

  /// Whether we're currently in game mode
  bool get inGame => _inGame;

  /// Get current path
  String get currentPath => _handler.currentPath;

  /// Get prompt string
  String getPrompt() {
    if (_inGame) {
      return ''; // Game outputs its own prompts
    }
    return _handler.getPrompt();
  }

  /// Get welcome banner
  String getBanner() => _handler.getBanner();

  /// Get console completer for TAB completion
  ConsoleCompleter get completer => ConsoleCompleter(
    gameConfig: _gameConfig,
    dataProvider: _CompletionDataProviderAdapter(),
    rootDirs: _handler.rootDirs,
  );

  /// Process a command and return the output
  Future<String> processCommand(String input) async {
    // If in game mode, send input to game
    if (_inGame && _inputCompleter != null) {
      _inputCompleter!.complete(input);
      _inputCompleter = null;
      return ''; // Output will come via onGameOutput callback
    }

    _io.clearOutput();
    await _handler.processCommand(input);
    return _io.getOutput() ?? '';
  }

  /// Play a game (called by ConsoleHandler.onPlayGame)
  Future<void> _playGame(String gamePath) async {
    try {
      final content = await File(gamePath).readAsString();
      final parser = GameParser();
      final game = parser.parse(content);

      // Create game screen with our IO
      final gameIo = BufferConsoleIO();
      final screen = GameScreenIO(gameIo);

      // Set up input callback for game
      screen.onReadLine = () async {
        // Flush current output to UI
        final output = gameIo.getOutput();
        if (output != null && output.isNotEmpty) {
          onGameOutput?.call(output);
          gameIo.clearOutput();
        }

        // Wait for user input
        _inputCompleter = Completer<String?>();
        return await _inputCompleter!.future;
      };

      _currentGame = GameEngineIO(game: game, screen: screen);
      _inGame = true;

      // Show initial message
      onGameOutput?.call('\nStarting game: ${game.title}\nType your choices and press Enter. Type "q" to quit.\n\n');

      // Run game in background
      _runGame(gameIo);

    } catch (e) {
      _io.writeln('Failed to start game: $e');
    }
  }

  /// Run the game loop
  Future<void> _runGame(BufferConsoleIO gameIo) async {
    try {
      await _currentGame!.run();
    } catch (e) {
      onGameOutput?.call('\nGame error: $e\n');
    } finally {
      // Game ended
      _inGame = false;
      _currentGame = null;

      // Flush any remaining output
      final output = gameIo.getOutput();
      if (output != null && output.isNotEmpty) {
        onGameOutput?.call(output);
      }


      // Complete any pending input request
      if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
        _inputCompleter!.complete(null);
        _inputCompleter = null;
      }
    }
  }

  /// Quit the current game
  void quitGame() {
    if (_inGame && _currentGame != null) {
      _currentGame!.stop();
      if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
        _inputCompleter!.complete(null);
        _inputCompleter = null;
      }
    }
  }
}
