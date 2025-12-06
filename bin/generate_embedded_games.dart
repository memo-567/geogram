#!/usr/bin/env dart
/// Script to generate games_embedded.dart from the games folder
/// Run this script whenever you add new games to the games folder:
///   dart bin/generate_embedded_games.dart
///
/// This will update lib/cli/game/games_embedded.dart with all .md files
/// from the games folder.

import 'dart:io';

Future<void> main() async {
  final gamesDir = Directory('games');
  final outputFile = File('lib/cli/game/games_embedded.dart');

  if (!await gamesDir.exists()) {
    print('Error: games folder not found');
    exit(1);
  }

  // Find all .md files in the games folder
  final gameFiles = gamesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (gameFiles.isEmpty) {
    print('Error: No game files found in games folder');
    exit(1);
  }

  print('Found ${gameFiles.length} game files:');
  for (final file in gameFiles) {
    print('  - ${file.path}');
  }

  // Generate the Dart file
  final buffer = StringBuffer();

  buffer.writeln('/// Embedded game files for CLI distribution');
  buffer.writeln('/// These games are bundled with the CLI binary and extracted on first run');
  buffer.writeln('///');
  buffer.writeln('/// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY');
  buffer.writeln('/// Run: dart bin/generate_embedded_games.dart');
  buffer.writeln('');
  buffer.writeln('class GamesEmbedded {');
  buffer.writeln('  /// Map of game filename to content');
  buffer.writeln('  static const Map<String, String> games = {');

  // Add each game to the map
  for (var i = 0; i < gameFiles.length; i++) {
    final file = gameFiles[i];
    final filename = file.path.split('/').last;
    final varName = _toVariableName(filename);
    final trailing = i < gameFiles.length - 1 ? ',' : '';
    buffer.writeln("    '$filename': _$varName$trailing");
  }

  buffer.writeln('  };');
  buffer.writeln('');

  // Add each game's content as a constant
  for (final file in gameFiles) {
    final filename = file.path.split('/').last;
    final varName = _toVariableName(filename);
    final content = await file.readAsString();

    buffer.writeln("  static const String _$varName = r'''");
    buffer.write(content);
    if (!content.endsWith('\n')) {
      buffer.writeln();
    }
    buffer.writeln("''';");
    buffer.writeln('');
  }

  buffer.writeln('}');

  // Write the output file
  await outputFile.writeAsString(buffer.toString());

  print('');
  print('Generated: ${outputFile.path}');
  print('Done!');
}

/// Convert filename to a valid Dart variable name
String _toVariableName(String filename) {
  // Remove .md extension and convert to camelCase
  var name = filename.replaceAll('.md', '');

  // Convert kebab-case or snake_case to camelCase
  final parts = name.split(RegExp(r'[-_]'));
  if (parts.isEmpty) return name;

  final result = StringBuffer(parts[0].toLowerCase());
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.isNotEmpty) {
      result.write(part[0].toUpperCase());
      if (part.length > 1) {
        result.write(part.substring(1).toLowerCase());
      }
    }
  }

  return result.toString();
}
