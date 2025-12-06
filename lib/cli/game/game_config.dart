import 'dart:io';
import 'games_embedded.dart';

/// Games directory configuration
class GameConfig {
  static const String defaultGamesFolder = 'games';

  late String gamesDirectory;
  bool _initialized = false;

  /// Initialize the games directory
  /// Uses the project's games folder or a custom path
  /// If no games are found, extracts embedded games
  Future<void> initialize(String baseDir) async {
    // First check if there's a games folder relative to the executable
    final execDir = File(Platform.resolvedExecutable).parent.path;

    // Try multiple locations for the games folder
    final possiblePaths = [
      '$baseDir/$defaultGamesFolder',           // Data directory
      '$execDir/$defaultGamesFolder',           // Next to executable
      '$execDir/../$defaultGamesFolder',        // One level up from executable
      '${Directory.current.path}/$defaultGamesFolder', // Current working directory
    ];

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists() && await _hasGames(dir)) {
        gamesDirectory = path;
        _initialized = true;
        return;
      }
    }

    // Default to data directory and create it
    gamesDirectory = '$baseDir/$defaultGamesFolder';
    final dir = Directory(gamesDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Extract embedded games if directory is empty
    if (!await _hasGames(dir)) {
      await _extractEmbeddedGames(dir);
    }

    _initialized = true;
  }

  /// Check if directory has any game files
  Future<bool> _hasGames(Directory dir) async {
    if (!await dir.exists()) return false;
    final files = dir.listSync().where((e) => e.path.endsWith('.md'));
    return files.isNotEmpty;
  }

  /// Extract embedded games to the games directory
  Future<void> _extractEmbeddedGames(Directory dir) async {
    for (final entry in GamesEmbedded.games.entries) {
      final filename = entry.key;
      final content = entry.value;
      final file = File('${dir.path}/$filename');
      await file.writeAsString(content);
    }
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// List all game files in the games directory
  List<FileSystemEntity> listGames() {
    if (!_initialized) return [];

    final dir = Directory(gamesDirectory);
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .where((e) => e.path.endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Get full path to a game file
  String? getGamePath(String name) {
    if (!_initialized) return null;

    // Try exact path first
    var path = '$gamesDirectory/$name';
    if (File(path).existsSync()) return path;

    // Try adding .md extension
    if (!name.endsWith('.md')) {
      path = '$gamesDirectory/$name.md';
      if (File(path).existsSync()) return path;
    }

    return null;
  }

  /// Check if a game exists
  bool gameExists(String name) {
    return getGamePath(name) != null;
  }

  /// Get game file info
  Map<String, dynamic>? getGameInfo(String name) {
    final path = getGamePath(name);
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    final stat = file.statSync();
    final content = file.readAsStringSync();

    // Extract title from content
    String? title;
    final titleMatch = RegExp(r'^# Title:\s*(.+)$', multiLine: true).firstMatch(content);
    if (titleMatch != null) {
      title = titleMatch.group(1);
    }

    // Count scenes, items, opponents
    final sceneCount = RegExp(r'^# Scene:', multiLine: true).allMatches(content).length;
    final itemCount = RegExp(r'^# Item:', multiLine: true).allMatches(content).length;
    final opponentCount = RegExp(r'^# Opponent:', multiLine: true).allMatches(content).length;
    final actionCount = RegExp(r'^# Action:', multiLine: true).allMatches(content).length;

    return {
      'name': name,
      'path': path,
      'title': title ?? name.replaceAll('.md', ''),
      'size': stat.size,
      'modified': stat.modified,
      'scenes': sceneCount,
      'items': itemCount,
      'opponents': opponentCount,
      'actions': actionCount,
    };
  }
}
