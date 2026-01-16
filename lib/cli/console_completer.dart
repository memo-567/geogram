/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Shared TAB completion logic for console interfaces.
 * Used by both CLI (pure_console) and Flutter UI (console_terminal_page).
 */

import 'game/game_config.dart';

/// Completion candidate with value, display text, and grouping
class Candidate {
  final String value;
  final String display;
  final String? group;
  final bool complete;

  Candidate(this.value, {String? display, this.group, this.complete = true})
      : display = display ?? value;
}

/// Result of a completion operation
class CompletionResult {
  /// The completed text (may be partial completion to common prefix)
  final String? completedText;

  /// Candidates to display to user (when multiple matches)
  final List<Candidate> candidates;

  /// Whether this was a single exact match
  final bool exactMatch;

  CompletionResult({
    this.completedText,
    this.candidates = const [],
    this.exactMatch = false,
  });
}

/// Provider interface for dynamic completion data
///
/// Implement this to provide platform-specific data like connected devices,
/// chat rooms, etc. that vary between CLI and UI modes.
abstract class CompletionDataProvider {
  /// Get connected device callsigns (for kick command, etc.)
  List<String> getConnectedCallsigns();

  /// Get chat room IDs and names
  Map<String, String> getChatRooms();

  /// Get profile callsigns with optional nicknames
  List<({String callsign, String? nickname, bool isStation})> getProfiles();
}

/// Shared console TAB completion logic
///
/// Provides intelligent completion for:
/// - Commands (global and context-aware)
/// - Sub-commands with descriptions
/// - Virtual filesystem paths
/// - Game files
/// - Dynamic data (devices, profiles, chat rooms)
class ConsoleCompleter {
  final GameConfig? gameConfig;
  final CompletionDataProvider? dataProvider;

  /// Root directories in virtual filesystem
  final List<String> rootDirs;

  /// Global commands available everywhere
  static const List<String> globalCommands = [
    'help', 'status', 'ls', 'cd', 'pwd', 'clear', 'quit', 'exit',
    'profile', 'station', 'games', 'play',
  ];

  /// Sub-commands for main commands
  static const Map<String, List<String>> subCommands = {
    'profile': ['list', 'switch', 'create', 'info'],
    'station': ['start', 'stop', 'status', 'port', 'cache'],
    'games': ['list', 'info'],
  };

  /// Descriptions for sub-commands
  static const Map<String, String> subCommandDescriptions = {
    'profile.list': 'List all profiles',
    'profile.switch': 'Switch active profile',
    'profile.create': 'Create new profile',
    'profile.info': 'Show profile details',
    'station.start': 'Start station server',
    'station.stop': 'Stop station server',
    'station.status': 'Show server status',
    'station.port': 'Set server port',
    'station.cache': 'Manage tile cache',
    'games.list': 'List available games',
    'games.info': 'Show game details',
  };

  /// Directory-specific commands
  static const Map<String, List<String>> dirCommands = {
    '/station': ['start', 'stop', 'port', 'cache'],
    '/games': ['play', 'info'],
    '/profiles': ['switch', 'info'],
  };

  ConsoleCompleter({
    this.gameConfig,
    this.dataProvider,
    this.rootDirs = const ['profiles', 'config', 'logs', 'station', 'games'],
  });

  /// Get completion for the given input at current path
  CompletionResult complete(String input, String currentPath) {
    final candidates = _getCompletions(input, currentPath);

    if (candidates.isEmpty) {
      return CompletionResult();
    }

    if (candidates.length == 1) {
      // Single match - complete it
      final candidate = candidates.first;
      final parts = input.split(RegExp(r'\s+'));
      if (parts.isEmpty) {
        return CompletionResult(
          completedText: candidate.value,
          exactMatch: true,
        );
      }

      parts[parts.length - 1] = candidate.value;
      final completed = parts.join(' ');
      return CompletionResult(
        completedText: candidate.complete ? '$completed ' : completed,
        exactMatch: true,
      );
    }

    // Multiple matches - find common prefix
    final commonPrefix = _findCommonPrefix(candidates.map((c) => c.value).toList());
    final parts = input.split(RegExp(r'\s+'));
    final lastPart = parts.isNotEmpty ? parts.last : '';

    String? completedText;
    if (commonPrefix.length > lastPart.length) {
      parts[parts.length - 1] = commonPrefix;
      completedText = parts.join(' ');
    }

    return CompletionResult(
      completedText: completedText,
      candidates: candidates,
    );
  }

  /// Get completion candidates based on current input
  List<Candidate> _getCompletions(String buffer, String currentPath) {
    final parts = buffer.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return _getContextAwareCommands('', currentPath);
    }

    final firstWord = parts[0].toLowerCase();
    final endsWithSpace = buffer.endsWith(' ');

    if (parts.length == 1 && !endsWithSpace) {
      // Completing first word (command)
      return _getContextAwareCommands(firstWord, currentPath);
    }

    // Check if it's a directory-local command
    if (dirCommands.containsKey(currentPath)) {
      final localCmds = dirCommands[currentPath]!;
      if (localCmds.contains(firstWord)) {
        return _completeLocalCommandArgs(firstWord, parts, currentPath);
      }
    }

    // Completing subsequent words (sub-commands or arguments)
    final effectivePartsLength = endsWithSpace ? parts.length + 1 : parts.length;

    if (effectivePartsLength == 2) {
      final partial = parts.length > 1 ? parts[1].toLowerCase() : '';

      // Check for sub-commands
      if (subCommands.containsKey(firstWord)) {
        return _filterSubCommands(firstWord, subCommands[firstWord]!, partial);
      }

      // Special completions based on command
      switch (firstWord) {
        case 'ls':
        case 'cd':
          return _completePaths(partial, currentPath);
        case 'play':
          return _completeGameFiles(partial);
      }
    }

    if (effectivePartsLength == 3) {
      final subCmd = parts.length > 1 ? parts[1].toLowerCase() : '';
      final partial = parts.length > 2 ? parts[2].toLowerCase() : '';

      // station cache <subcommand>
      if (firstWord == 'station' && subCmd == 'cache') {
        return _filterCandidates(['clear', 'stats'], partial);
      }

      // profile switch <callsign>
      if (firstWord == 'profile' && subCmd == 'switch') {
        return _completeProfileCallsigns(partial);
      }

      // games info <game>
      if (firstWord == 'games' && subCmd == 'info') {
        return _completeGameFiles(partial);
      }
    }

    return [];
  }

  /// Get commands based on current directory context
  List<Candidate> _getContextAwareCommands(String partial, String currentPath) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    // First add directory-local commands
    if (dirCommands.containsKey(currentPath)) {
      final localCmds = dirCommands[currentPath]!;
      for (final cmd in localCmds) {
        if (cmd.toLowerCase().startsWith(lowerPartial)) {
          final dirName = currentPath.substring(1).toUpperCase();
          candidates.add(Candidate(cmd, group: '$dirName commands'));
        }
      }
    }

    // Then add global commands
    for (final cmd in globalCommands) {
      if (cmd.toLowerCase().startsWith(lowerPartial)) {
        candidates.add(Candidate(cmd, group: 'Global commands'));
      }
    }

    return candidates;
  }

  /// Complete directory-local command arguments
  List<Candidate> _completeLocalCommandArgs(String localCmd, List<String> parts, String currentPath) {
    final partial = parts.length > 1 ? parts[1].toLowerCase() : '';

    if (currentPath == '/station') {
      if (localCmd == 'cache') {
        return _filterCandidates(['clear', 'stats'], partial);
      }
    } else if (currentPath == '/games') {
      if (localCmd == 'play' || localCmd == 'info') {
        return _completeGameFiles(partial);
      }
    } else if (currentPath == '/profiles') {
      if (localCmd == 'switch' || localCmd == 'info') {
        return _completeProfileCallsigns(partial);
      }
    }

    return [];
  }

  /// Complete with path entries (for ls, cd)
  List<Candidate> _completePaths(String partial, String currentPath) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    // Parent directory
    if ('..'.startsWith(lowerPartial)) {
      candidates.add(Candidate('..', group: 'parent'));
    }

    if (partial.isEmpty || partial == '/') {
      // Show root directories
      for (final dir in rootDirs) {
        candidates.add(Candidate(dir, display: '$dir/', group: 'directory', complete: false));
      }
      return candidates;
    }

    // Absolute path completion
    if (partial.startsWith('/')) {
      final pathParts = partial.substring(1).split('/');
      final baseDir = pathParts[0];

      if (pathParts.length == 1) {
        // Completing root directory name
        for (final dir in rootDirs) {
          if (dir.startsWith(baseDir.toLowerCase())) {
            candidates.add(Candidate('/$dir', display: '/$dir/', group: 'directory', complete: false));
          }
        }
      }
      return candidates;
    }

    // Relative path completion based on current directory
    if (currentPath == '/') {
      for (final dir in rootDirs) {
        if (dir.toLowerCase().startsWith(lowerPartial)) {
          candidates.add(Candidate(dir, display: '$dir/', group: 'directory', complete: false));
        }
      }
    }

    return candidates;
  }

  /// Complete game file names
  List<Candidate> _completeGameFiles(String partial) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    if (gameConfig == null || !gameConfig!.isInitialized) return candidates;

    final games = gameConfig!.listGames();
    for (final game in games) {
      final fileName = game.path.split('/').last;
      if (fileName.toLowerCase().startsWith(lowerPartial)) {
        final info = gameConfig!.getGameInfo(fileName);
        final title = info?['title'] ?? fileName;
        candidates.add(Candidate(fileName, display: '$fileName ($title)', group: 'game'));
      }
    }

    return candidates;
  }

  /// Complete with profile callsigns
  List<Candidate> _completeProfileCallsigns(String partial) {
    final candidates = <Candidate>[];
    final upperPartial = partial.toUpperCase();

    if (dataProvider == null) return candidates;

    for (final profile in dataProvider!.getProfiles()) {
      if (profile.callsign.toUpperCase().startsWith(upperPartial)) {
        final label = profile.nickname?.isNotEmpty == true
            ? '${profile.callsign} (${profile.nickname})'
            : profile.callsign;
        candidates.add(Candidate(
          profile.callsign,
          display: label,
          group: profile.isStation ? 'station' : 'client',
        ));
      }
    }

    return candidates;
  }

  /// Filter candidates by partial match
  List<Candidate> _filterCandidates(List<String> options, String partial) {
    final lowerPartial = partial.toLowerCase();
    return options
        .where((opt) => opt.toLowerCase().startsWith(lowerPartial))
        .map((opt) => Candidate(opt))
        .toList();
  }

  /// Filter sub-commands with descriptions
  List<Candidate> _filterSubCommands(String command, List<String> options, String partial) {
    final lowerPartial = partial.toLowerCase();
    return options
        .where((opt) => opt.toLowerCase().startsWith(lowerPartial))
        .map((opt) {
          final descKey = '$command.$opt';
          final desc = subCommandDescriptions[descKey];
          final display = desc != null ? '$opt - $desc' : opt;
          return Candidate(opt, display: display, group: '$command subcommands');
        })
        .toList();
  }

  /// Find common prefix among strings
  String _findCommonPrefix(List<String> strings) {
    if (strings.isEmpty) return '';
    if (strings.length == 1) return strings.first;

    var prefix = strings.first;
    for (var i = 1; i < strings.length; i++) {
      while (!strings[i].toLowerCase().startsWith(prefix.toLowerCase())) {
        prefix = prefix.substring(0, prefix.length - 1);
        if (prefix.isEmpty) return '';
      }
    }
    return prefix;
  }

  /// Format candidates for display (returns list of display strings grouped)
  List<String> formatCandidatesForDisplay(List<Candidate> candidates) {
    final lines = <String>[];

    // Group candidates
    final groups = <String?, List<Candidate>>{};
    for (final c in candidates) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }

    for (final entry in groups.entries) {
      if (entry.key != null) {
        lines.add('${entry.key}:');
      }

      // Commands in columns, others one per line
      final isCommandGroup = entry.key != null &&
          (entry.key!.contains('commands') || entry.key!.contains('subcommands'));

      if (isCommandGroup) {
        // Compact display
        final displays = entry.value.map((c) => c.display).toList();
        lines.add('  ${displays.join('  ')}');
      } else {
        // One per line
        for (final c in entry.value) {
          lines.add('  ${c.display}');
        }
      }
    }

    return lines;
  }
}
