// Pure Dart console for CLI mode (no Flutter dependencies)
import 'dart:io';

import 'package:dart_console/dart_console.dart';

import 'pure_relay.dart';
import 'game/game_config.dart';
import 'game/game_parser.dart';
import 'game/game_engine.dart';
import 'game/game_screen.dart';

/// Completion candidate
class Candidate {
  final String value;
  final String display;
  final String? group;
  final bool complete;

  Candidate(this.value, {String? display, this.group, this.complete = true})
      : display = display ?? value;
}

/// Pure Dart CLI console for geogram-desktop
class PureConsole {
  /// Virtual filesystem current path
  String _currentPath = '/';

  /// Current chat room (when in /chat/<room>)
  String? _currentChatRoom;

  /// Root directories in virtual filesystem
  static const List<String> rootDirs = ['relay', 'devices', 'chat', 'config', 'logs', 'ssl', 'games'];

  /// Global commands available everywhere
  static const List<String> globalCommands = [
    'help', 'status', 'stats', 'ls', 'cd', 'pwd', 'df',
    'relay', 'devices', 'chat', 'config', 'logs',
    'broadcast', 'kick', 'quiet', 'verbose', 'restart', 'reload',
    'clear', 'quit', 'exit', 'shutdown',
    'top', 'tail', 'head', 'cat', 'setup', 'ssl',
    'play', 'games'
  ];

  /// Sub-commands for main commands
  static const Map<String, List<String>> subCommands = {
    'relay': ['start', 'stop', 'status', 'restart', 'port', 'callsign', 'cache'],
    'devices': ['list', 'scan', 'ping', 'kick'],
    'chat': ['list', 'info', 'create', 'delete', 'rename', 'history', 'say', 'delmsg'],
    'config': ['set', 'save'],
    'df': ['-h'],
    'ssl': ['domain', 'email', 'request', 'test', 'renew', 'autorenew', 'selfsigned', 'enable', 'disable'],
    'games': ['list', 'info'],
  };

  /// Directory-specific commands (when inside these directories)
  static const Map<String, List<String>> dirCommands = {
    '/relay': ['start', 'stop', 'status', 'restart', 'port', 'callsign', 'cache'],
    '/devices': ['list', 'scan', 'ping', 'kick'],
    '/chat': ['list', 'info', 'create', 'delete', 'rename', 'history', 'say', 'delmsg', 'messages'],
    '/config': ['set', 'save'],
    '/logs': [],
    '/ssl': ['domain', 'email', 'request', 'test', 'renew', 'autorenew', 'selfsigned', 'enable', 'disable', 'status'],
    '/games': ['list', 'info', 'play'],
  };

  /// Config keys for completion
  static const List<String> configKeys = [
    'port', 'callsign', 'description', 'location', 'latitude', 'longitude',
    'tileServerEnabled', 'osmFallbackEnabled', 'maxZoomLevel', 'maxCacheSize',
    'enableAprs', 'enableCors', 'maxConnectedDevices'
  ];

  /// Command history
  final List<String> _history = [];
  int _historyIndex = 0;

  /// Double CTRL+C handling
  DateTime? _lastCtrlCTime;
  static const _ctrlCTimeout = Duration(seconds: 2);

  /// Relay server instance
  final PureRelayServer _relay = PureRelayServer();

  /// SSL certificate manager
  SslCertificateManager? _sslManager;

  /// Game engine config
  final GameConfig _gameConfig = GameConfig();

  /// Run CLI mode
  Future<void> run(List<String> args) async {
    // Check for --setup flag
    final forceSetup = args.contains('--setup') || args.contains('-s');

    await _initializeServices();
    _printBanner();

    // Check if setup is needed
    if (forceSetup || _relay.settings.needsSetup()) {
      if (_relay.settings.needsSetup()) {
        stdout.writeln('\x1B[33mInitial setup required.\x1B[0m');
        stdout.writeln();
      }
      await _handleSetup();
    }

    await _commandLoop();
  }

  Future<void> _initializeServices() async {
    try {
      await _relay.initialize();

      // Initialize SSL manager
      _sslManager = SslCertificateManager(_relay.settings, _relay.dataDir!);
      await _sslManager!.initialize();
      _sslManager!.startAutoRenewal();

      // Initialize game engine
      await _gameConfig.initialize(_relay.dataDir!);
    } catch (e) {
      _printError('Failed to initialize services: $e');
      exit(1);
    }
  }

  /// Cleanup all services before exit
  Future<void> _cleanup() async {
    // Stop SSL auto-renewal timer
    _sslManager?.stop();
    // Stop relay server
    if (_relay.isRunning) {
      await _relay.stop();
    }
    // Reset console to normal mode
    _console.rawMode = false;
  }

  void _printBanner() {
    stdout.writeln();
    stdout.writeln('\x1B[36m' + '=' * 60 + '\x1B[0m');
    stdout.writeln('\x1B[36m  Geogram Desktop v$cliAppVersion - CLI Mode\x1B[0m');
    stdout.writeln('\x1B[36m  Relay Callsign: ${_relay.settings.callsign}\x1B[0m');
    stdout.writeln('\x1B[36m' + '=' * 60 + '\x1B[0m');
    stdout.writeln();
    stdout.writeln('Type "help" for available commands.');
    stdout.writeln();
  }

  Future<void> _commandLoop() async {
    while (true) {
      final prompt = _buildPrompt();
      final input = await _readLineWithCompletion(prompt);

      if (input == null || input.isEmpty) continue;

      // Handle double CTRL+C exit
      if (input == '__EXIT__') {
        await _cleanup();
        stdout.writeln('Goodbye!');
        exit(0);
      }

      // Add to history
      if (_history.isEmpty || _history.last != input) {
        _history.add(input);
      }
      _historyIndex = _history.length;

      // If in a chat room, treat non-command input as a message
      if (_currentChatRoom != null && !input.startsWith('/') && !_isCommand(input)) {
        _relay.postMessage(_currentChatRoom!, input);
        continue;
      }

      final parts = _parseInput(input);
      final command = parts[0].toLowerCase().replaceFirst('/', '');
      final args = parts.length > 1 ? parts.sublist(1) : <String>[];

      try {
        final shouldExit = await _processCommand(command, args);
        if (shouldExit) break;
      } catch (e) {
        _printError('Error: $e');
      }
    }
  }

  String _buildPrompt() {
    final chatPrefix = _currentChatRoom != null
        ? '\x1B[35m[$_currentChatRoom]\x1B[0m '
        : '';
    return '$chatPrefix\x1B[32mgeogram:$_currentPath\$ \x1B[0m';
  }

  /// Console instance for terminal control
  final Console _console = Console();

  /// Read a line with TAB completion and history support
  Future<String?> _readLineWithCompletion(String prompt) async {
    // Check if stdin is a terminal
    if (!stdin.hasTerminal) {
      stdout.write(prompt);
      return stdin.readLineSync()?.trim();
    }

    stdout.write(prompt);
    var buffer = '';
    var index = 0; // cursor position

    // Use dart_console's rawMode for reliable terminal mode control
    _console.rawMode = true;
    try {
      while (true) {
        final byte = stdin.readByteSync();
        if (byte == -1) continue; // EOF, keep reading

        // Enter (CR or LF)
        if (byte == 13 || byte == 10) {
          stdout.writeln();
          return buffer.trim();
        }

        // CTRL+C
        if (byte == 3) {
          final now = DateTime.now();
          if (_lastCtrlCTime != null &&
              now.difference(_lastCtrlCTime!) < _ctrlCTimeout) {
            stdout.writeln();
            stdout.writeln('Shutting down...');
            return '__EXIT__';
          } else {
            _lastCtrlCTime = now;
            stdout.writeln();
            stdout.writeln('Press Ctrl+C again to exit (or wait 2 seconds to cancel)');
            _redrawLine(prompt, buffer, index);
          }
          continue;
        }

        // CTRL+D
        if (byte == 4) {
          if (buffer.isEmpty) {
            stdout.writeln();
            return 'quit';
          }
          continue;
        }

        // Escape sequence (arrow keys, etc.)
        if (byte == 27) {
          final byte1 = stdin.readByteSync();
          if (byte1 == -1) continue;

          // Handle ESC [ or ESC O sequences (most common)
          if (byte1 == 91 || byte1 == 79) { // '[' (91) or 'O' (79)
            final byte2 = stdin.readByteSync();
            if (byte2 == -1) continue;

            // Handle extended sequences like ESC [ 1 ~ (Home) or ESC [ 3 ~ (Delete)
            if (byte2 >= 49 && byte2 <= 54) { // '1' to '6'
              final byte3 = stdin.readByteSync();
              if (byte3 == 126) { // '~'
                // Extended key handling
                switch (byte2) {
                  case 49: // Home
                    _handleArrowKey(72, buffer, index, prompt, (newBuf, newIdx) {
                      buffer = newBuf;
                      index = newIdx;
                    });
                    break;
                  case 51: // Delete
                    _handleArrowKey(126, buffer, index, prompt, (newBuf, newIdx) {
                      buffer = newBuf;
                      index = newIdx;
                    });
                    break;
                  case 52: // End
                    _handleArrowKey(70, buffer, index, prompt, (newBuf, newIdx) {
                      buffer = newBuf;
                      index = newIdx;
                    });
                    break;
                }
                continue;
              }
              // Not a tilde, might be something else - just skip
              continue;
            }

            // Standard arrow keys (A=65, B=66, C=67, D=68), Home (H=72), End (F=70)
            _handleArrowKey(byte2, buffer, index, prompt, (newBuf, newIdx) {
              buffer = newBuf;
              index = newIdx;
            });
          }
          // Everything after ESC is consumed, continue to next byte
          continue;
        }

        // Backspace (127 or 8)
        if (byte == 127 || byte == 8) {
          if (index > 0) {
            buffer = buffer.substring(0, index - 1) + buffer.substring(index);
            index--;
            _redrawLine(prompt, buffer, index);
          }
          continue;
        }

        // CTRL+A - Home
        if (byte == 1) {
          while (index > 0) {
            index--;
            stdout.write('\x1B[D');
          }
          continue;
        }

        // CTRL+E - End
        if (byte == 5) {
          while (index < buffer.length) {
            index++;
            stdout.write('\x1B[C');
          }
          continue;
        }

        // CTRL+U - Clear line before cursor
        if (byte == 21) {
          if (index > 0) {
            buffer = buffer.substring(index);
            index = 0;
            _redrawLine(prompt, buffer, index);
          }
          continue;
        }

        // CTRL+K - Clear line after cursor
        if (byte == 11) {
          if (index < buffer.length) {
            buffer = buffer.substring(0, index);
            _redrawLine(prompt, buffer, index);
          }
          continue;
        }

        // CTRL+L - Clear screen
        if (byte == 12) {
          stdout.write('\x1B[2J\x1B[H');
          stdout.write(prompt + buffer);
          for (var i = buffer.length; i > index; i--) {
            stdout.write('\x1B[D');
          }
          continue;
        }

        // TAB - completion
        if (byte == 9) {
          final result = _handleTabCompletion(buffer, index, prompt);
          if (result != null) {
            buffer = result;
            index = buffer.length;
            _redrawLine(prompt, buffer, index);
          }
          continue;
        }

        // Regular printable character
        if (byte >= 32 && byte < 127) {
          final char = String.fromCharCode(byte);
          buffer = buffer.substring(0, index) + char + buffer.substring(index);
          index++;
          if (index == buffer.length) {
            stdout.write(char);
          } else {
            _redrawLine(prompt, buffer, index);
          }
        }
      }
    } finally {
      // Restore terminal to normal mode
      _console.rawMode = false;
    }
  }

  /// Handle arrow key input
  void _handleArrowKey(int keyCode, String buffer, int index, String prompt,
      void Function(String, int) updateState) {
    switch (keyCode) {
      case 65: // Up arrow
        if (_history.isNotEmpty && _historyIndex > 0) {
          _historyIndex--;
          final newBuffer = _history[_historyIndex];
          _redrawLine(prompt, newBuffer, newBuffer.length);
          updateState(newBuffer, newBuffer.length);
        }
        break;
      case 66: // Down arrow
        if (_historyIndex < _history.length - 1) {
          _historyIndex++;
          final newBuffer = _history[_historyIndex];
          _redrawLine(prompt, newBuffer, newBuffer.length);
          updateState(newBuffer, newBuffer.length);
        } else if (_historyIndex >= _history.length - 1) {
          _historyIndex = _history.length;
          _redrawLine(prompt, '', 0);
          updateState('', 0);
        }
        break;
      case 67: // Right arrow
        if (index < buffer.length) {
          stdout.write('\x1B[C');
          updateState(buffer, index + 1);
        }
        break;
      case 68: // Left arrow
        if (index > 0) {
          stdout.write('\x1B[D');
          updateState(buffer, index - 1);
        }
        break;
      case 72: // Home
        var newIndex = index;
        while (newIndex > 0) {
          newIndex--;
          stdout.write('\x1B[D');
        }
        updateState(buffer, newIndex);
        break;
      case 70: // End
        var newIndex = index;
        while (newIndex < buffer.length) {
          newIndex++;
          stdout.write('\x1B[C');
        }
        updateState(buffer, newIndex);
        break;
      case 51: // Delete key (ESC [ 3 ~)
        final tilde = stdin.readByteSync(); // consume ~
        if (tilde == 126 && index < buffer.length) {
          final newBuffer = buffer.substring(0, index) + buffer.substring(index + 1);
          _redrawLine(prompt, newBuffer, index);
          updateState(newBuffer, index);
        }
        break;
    }
  }

  /// Redraw the current line with prompt and buffer
  void _redrawLine(String prompt, String buffer, int cursorIndex) {
    // Move to start of line, clear line, rewrite
    stdout.write('\r\x1B[K$prompt$buffer');
    // Move cursor to correct position
    for (var i = buffer.length; i > cursorIndex; i--) {
      stdout.write('\x1B[D');
    }
  }

  /// Handle TAB completion
  String? _handleTabCompletion(String buffer, int cursorPos, String prompt) {
    final beforeCursor = buffer.substring(0, cursorPos);
    final candidates = _getCompletions(beforeCursor);

    if (candidates.isEmpty) {
      return null;
    }

    if (candidates.length == 1) {
      // Single match - complete it
      final candidate = candidates.first;
      final parts = beforeCursor.split(RegExp(r'\s+'));
      if (parts.isEmpty) return candidate.value;

      parts[parts.length - 1] = candidate.value;
      final completed = parts.join(' ');
      return candidate.complete ? '$completed ' : completed;
    }

    // Multiple matches - show them and find common prefix
    _console.writeLine();
    _displayCandidates(candidates);

    // Find common prefix
    final commonPrefix = _findCommonPrefix(candidates.map((c) => c.value).toList());
    final parts = beforeCursor.split(RegExp(r'\s+'));
    final lastPart = parts.isNotEmpty ? parts.last : '';

    if (commonPrefix.length > lastPart.length) {
      parts[parts.length - 1] = commonPrefix;
      return parts.join(' ');
    }

    return buffer; // Return unchanged
  }

  /// Get completion candidates based on current input
  List<Candidate> _getCompletions(String buffer) {
    final parts = buffer.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return _getContextAwareCommands('');
    }

    final firstWord = parts[0].toLowerCase();
    final endsWithSpace = buffer.endsWith(' ');

    if (parts.length == 1 && !endsWithSpace) {
      // Completing first word (command)
      return _getContextAwareCommands(firstWord);
    }

    // If buffer ends with space and parts.length == 1, treat as completing second word with empty partial
    final effectivePartsLength = endsWithSpace ? parts.length + 1 : parts.length;

    // Check if it's a directory-local command
    if (dirCommands.containsKey(_currentPath)) {
      final localCmds = dirCommands[_currentPath]!;
      if (localCmds.contains(firstWord)) {
        return _completeLocalCommandArgs(firstWord, parts);
      }
    }

    // Completing subsequent words (sub-commands or arguments)
    if (effectivePartsLength == 2) {
      final partial = parts.length > 1 ? parts[1].toLowerCase() : '';

      // Check for sub-commands
      if (subCommands.containsKey(firstWord)) {
        return _filterCandidates(subCommands[firstWord]!, partial);
      }

      // Special completions based on command
      switch (firstWord) {
        case 'kick':
          return _completeCallsigns(partial);
        case 'ls':
        case 'cd':
          return _completePaths(partial);
        case 'play':
          return _completeGameFiles(partial);
      }
    }

    if (effectivePartsLength == 3) {
      final subCmd = parts.length > 1 ? parts[1].toLowerCase() : '';
      final partial = parts.length > 2 ? parts[2].toLowerCase() : '';

      // relay cache <subcommand>
      if (firstWord == 'relay' && subCmd == 'cache') {
        return _filterCandidates(['clear', 'stats'], partial);
      }

      // config set <key>
      if (firstWord == 'config' && subCmd == 'set') {
        return _filterCandidates(configKeys, partial);
      }

      // chat <subcommand> <roomId>
      if (firstWord == 'chat' && ['info', 'delete', 'rename', 'history', 'say', 'delmsg'].contains(subCmd)) {
        return _completeRoomIds(partial);
      }

      // devices ping/kick <target>
      if (firstWord == 'devices') {
        if (subCmd == 'kick') {
          return _completeCallsigns(partial);
        }
      }
    }

    return [];
  }

  /// Get commands based on current directory context
  List<Candidate> _getContextAwareCommands(String partial) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    // First add directory-local commands (if in a special directory)
    if (dirCommands.containsKey(_currentPath)) {
      final localCmds = dirCommands[_currentPath]!;
      for (final cmd in localCmds) {
        if (cmd.toLowerCase().startsWith(lowerPartial)) {
          final dirName = _currentPath.substring(1).toUpperCase();
          candidates.add(Candidate(cmd, group: '$dirName commands'));
        }
      }
    }

    // Add chat room-specific commands
    if (_currentChatRoom != null) {
      for (final cmd in ['messages', 'delmsg']) {
        if (cmd.startsWith(lowerPartial)) {
          candidates.add(Candidate(cmd, group: 'CHAT commands'));
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
  List<Candidate> _completeLocalCommandArgs(String localCmd, List<String> parts) {
    // Get partial - when buffer ends with space but parts.length == 1, partial is empty
    final partial = parts.length > 1 ? parts[1].toLowerCase() : '';

    if (_currentPath == '/config') {
      if (localCmd == 'set') {
        return _filterCandidates(configKeys, partial);
      }
    } else if (_currentPath == '/chat') {
      if (['info', 'delete', 'rename', 'history'].contains(localCmd)) {
        return _completeRoomIds(partial);
      }
    } else if (_currentPath == '/devices') {
      if (localCmd == 'kick') {
        return _completeCallsigns(partial);
      }
      if (localCmd == 'scan' && partial.startsWith('-')) {
        return _filterCandidates(['-t'], partial);
      }
    } else if (_currentPath == '/relay') {
      if (localCmd == 'cache') {
        return _filterCandidates(['clear', 'stats'], partial);
      }
    } else if (_currentPath == '/games') {
      if (localCmd == 'play' || localCmd == 'info') {
        return _completeGameFiles(partial);
      }
    }

    return [];
  }

  /// Complete with path entries (for ls, cd)
  List<Candidate> _completePaths(String partial) {
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
      } else if (baseDir == 'chat' && pathParts.length == 2) {
        // Completing chat room name
        final roomPartial = pathParts[1].toLowerCase();
        for (final roomId in _relay.chatRooms.keys) {
          if (roomId.toLowerCase().startsWith(roomPartial)) {
            candidates.add(Candidate('/chat/$roomId', display: '/chat/$roomId/', group: 'chat room', complete: false));
          }
        }
      }
      return candidates;
    }

    // Relative path completion based on current directory
    if (_currentPath == '/') {
      for (final dir in rootDirs) {
        if (dir.toLowerCase().startsWith(lowerPartial)) {
          candidates.add(Candidate(dir, display: '$dir/', group: 'directory', complete: false));
        }
      }
    } else if (_currentPath == '/chat') {
      for (final roomId in _relay.chatRooms.keys) {
        if (roomId.toLowerCase().startsWith(lowerPartial)) {
          candidates.add(Candidate(roomId, display: '$roomId/', group: 'chat room', complete: false));
        }
      }
    } else if (_currentPath == '/devices') {
      for (final client in _relay.clients.values) {
        final callsign = client.callsign ?? 'unknown';
        if (callsign.toLowerCase().startsWith(lowerPartial)) {
          candidates.add(Candidate(callsign, group: 'device'));
        }
      }
    }

    return candidates;
  }

  /// Complete with callsigns
  List<Candidate> _completeCallsigns(String partial) {
    final candidates = <Candidate>[];
    final upperPartial = partial.toUpperCase();

    for (final client in _relay.clients.values) {
      final callsign = client.callsign ?? '';
      if (callsign.toUpperCase().startsWith(upperPartial)) {
        candidates.add(Candidate(callsign, group: 'device'));
      }
    }

    return candidates;
  }

  /// Complete with chat room IDs
  List<Candidate> _completeRoomIds(String partial) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    for (final room in _relay.chatRooms.values) {
      if (room.id.toLowerCase().startsWith(lowerPartial)) {
        candidates.add(Candidate(room.id, display: '${room.id} (${room.name})', group: 'room'));
      }
    }

    return candidates;
  }

  /// Complete game file names for 'play' command
  List<Candidate> _completeGameFiles(String partial) {
    final candidates = <Candidate>[];
    final lowerPartial = partial.toLowerCase();

    if (!_gameConfig.isInitialized) return candidates;

    final games = _gameConfig.listGames();
    for (final game in games) {
      final fileName = game.path.split('/').last;
      if (fileName.toLowerCase().startsWith(lowerPartial)) {
        final info = _gameConfig.getGameInfo(fileName);
        final title = info?['title'] ?? fileName;
        candidates.add(Candidate(fileName, display: '$fileName ($title)', group: 'game'));
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

  /// Find common prefix among candidates
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

  /// Display completion candidates
  void _displayCandidates(List<Candidate> candidates) {
    // Group candidates
    final groups = <String?, List<Candidate>>{};
    for (final c in candidates) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }

    for (final entry in groups.entries) {
      if (entry.key != null) {
        stdout.writeln('\x1B[33m${entry.key}:\x1B[0m');
      }
      final displays = entry.value.map((c) => c.display).toList();
      _printColumns(displays);
    }
  }

  /// Print items in columns
  void _printColumns(List<String> items) {
    if (items.isEmpty) return;

    final maxLen = items.map((s) => s.length).reduce((a, b) => a > b ? a : b);
    final termWidth = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final colWidth = maxLen + 2;
    final numCols = (termWidth / colWidth).floor().clamp(1, items.length);

    for (var i = 0; i < items.length; i += numCols) {
      final row = <String>[];
      for (var j = 0; j < numCols && i + j < items.length; j++) {
        row.add(items[i + j].padRight(colWidth));
      }
      stdout.writeln('  ${row.join('')}');
    }
  }

  List<String> _parseInput(String input) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var quoteChar = '';

    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if ((c == '"' || c == "'") && !inQuotes) {
        inQuotes = true;
        quoteChar = c;
      } else if (c == quoteChar && inQuotes) {
        inQuotes = false;
        quoteChar = '';
      } else if (c == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }
    return parts;
  }

  bool _isCommand(String input) {
    final commands = ['help', 'status', 'stats', 'ls', 'cd', 'pwd', 'relay', 'devices',
      'chat', 'config', 'logs', 'clear', 'quit', 'exit', 'broadcast', 'kick', 'df',
      'quiet', 'verbose', 'restart', 'reload', 'messages', 'delmsg'];
    final firstWord = input.split(' ').first.toLowerCase();
    return commands.contains(firstWord);
  }

  Future<bool> _processCommand(String command, List<String> args) async {
    // Context-specific commands when in /relay
    if (_currentPath == '/relay' || _currentPath.startsWith('/relay/')) {
      switch (command) {
        case 'start':
          await _handleRelayStart();
          return false;
        case 'stop':
          await _handleRelayStop();
          return false;
        case 'port':
          await _handleRelayPort(args);
          return false;
        case 'cache':
          _handleRelayCache(args);
          return false;
        case 'callsign':
          await _handleRelayCallsign(args);
          return false;
      }
    }

    // Context-specific commands when in /chat/<room>
    if (_currentChatRoom != null) {
      switch (command) {
        case 'messages':
          _handleChatHistory(args);
          return false;
        case 'delmsg':
          _handleDeleteMessage(args);
          return false;
      }
    }

    // Context-specific commands when in /ssl
    if (_currentPath == '/ssl') {
      switch (command) {
        case 'domain':
          await _handleSslDomain(args);
          return false;
        case 'email':
          await _handleSslEmail(args);
          return false;
        case 'request':
          await _handleSslRequest(staging: false);
          return false;
        case 'test':
          await _handleSslRequest(staging: true);
          return false;
        case 'renew':
          await _handleSslRenew();
          return false;
        case 'autorenew':
          await _handleSslAutoRenew(args);
          return false;
        case 'selfsigned':
          await _handleSslSelfSigned(args);
          return false;
        case 'enable':
          await _handleSslEnable(true);
          return false;
        case 'disable':
          await _handleSslEnable(false);
          return false;
        case 'status':
          await _showSslStatus();
          return false;
      }
    }

    // Global commands
    switch (command) {
      case 'help':
      case '?':
        _printHelp();
        break;
      case 'status':
        _printStatus();
        break;
      case 'stats':
        _printStats();
        break;
      case 'ls':
        _handleLs(args);
        break;
      case 'cd':
        _handleCd(args);
        break;
      case 'pwd':
        stdout.writeln(_currentPath);
        break;
      case 'relay':
        await _handleRelay(args);
        break;
      case 'devices':
        await _handleDevices(args);
        break;
      case 'chat':
        await _handleChat(args);
        break;
      case 'config':
        await _handleConfig(args);
        break;
      case 'logs':
        _handleLogs(args);
        break;
      case 'broadcast':
        _handleBroadcast(args);
        break;
      case 'kick':
        _handleKick(args);
        break;
      case 'df':
        await _handleDf(args);
        break;
      case 'quiet':
        _relay.quietMode = true;
        stdout.writeln('Quiet mode enabled');
        break;
      case 'verbose':
        _relay.quietMode = false;
        stdout.writeln('Verbose mode enabled');
        break;
      case 'restart':
        await _relay.restart();
        break;
      case 'reload':
        await _relay.reloadSettings();
        stdout.writeln('Settings reloaded');
        break;
      case 'clear':
        stdout.write('\x1B[2J\x1B[H');
        break;
      case 'top':
        await _handleTop();
        break;
      case 'tail':
        await _handleTail(args);
        break;
      case 'head':
        await _handleHead(args);
        break;
      case 'cat':
        await _handleCat(args);
        break;
      case 'setup':
        await _handleSetup();
        break;
      case 'ssl':
        await _handleSsl(args);
        break;
      case 'play':
        await _handlePlay(args);
        break;
      case 'games':
        await _handleGames(args);
        break;
      case 'quit':
      case 'exit':
      case 'shutdown':
        await _cleanup();
        stdout.writeln('Goodbye!');
        exit(0);
      default:
        _printError('Unknown command: $command. Type "help" for available commands.');
    }
    return false;
  }

  void _printHelp() {
    stdout.writeln();
    stdout.writeln('\x1B[1mAvailable Commands:\x1B[0m');
    stdout.writeln();
    stdout.writeln('  \x1B[33mNavigation:\x1B[0m');
    stdout.writeln('    ls [path]          List directory contents');
    stdout.writeln('    cd <path>          Change directory');
    stdout.writeln('    pwd                Print working directory');
    stdout.writeln('    df [-h]            Show disk usage');
    stdout.writeln();
    stdout.writeln('  \x1B[33mStatus & Monitoring:\x1B[0m');
    stdout.writeln('    status             Show application status');
    stdout.writeln('    stats              Show detailed statistics');
    stdout.writeln('    top                Live monitoring dashboard (q to exit)');
    stdout.writeln('    logs [n]           Show last n log entries (default: 20)');
    stdout.writeln('    tail [-n N] [file] Show last N lines (default: 10, logs)');
    stdout.writeln('    head [-n N] [file] Show first N lines (default: 10, logs)');
    stdout.writeln('    cat <file>         Show entire file (logs, config, or path)');
    stdout.writeln('    quiet              Enable quiet mode (suppress logs)');
    stdout.writeln('    verbose            Enable verbose mode (show logs)');
    stdout.writeln();
    stdout.writeln('  \x1B[33mRelay Server:\x1B[0m');
    stdout.writeln('    relay start        Start the relay server');
    stdout.writeln('    relay stop         Stop the relay server');
    stdout.writeln('    relay status       Show relay server status');
    stdout.writeln('    relay restart      Restart the relay server');
    stdout.writeln('    relay port <port>  Set relay server port');
    stdout.writeln('    relay callsign <cs> Set relay callsign');
    stdout.writeln('    relay cache clear  Clear tile cache');
    stdout.writeln('    relay cache stats  Show cache statistics');
    stdout.writeln();
    stdout.writeln('  \x1B[33mDevice Management:\x1B[0m');
    stdout.writeln('    devices list       List connected devices');
    stdout.writeln('    devices scan       Scan network for devices');
    stdout.writeln('    devices ping <ip>  Ping a specific device');
    stdout.writeln('    devices kick <cs>  Disconnect a device');
    stdout.writeln();
    stdout.writeln('  \x1B[33mChat Management:\x1B[0m');
    stdout.writeln('    chat list          List all chat rooms');
    stdout.writeln('    chat info <id>     Show room details');
    stdout.writeln('    chat create <id> <name> [desc]  Create room');
    stdout.writeln('    chat delete <id>   Delete a chat room');
    stdout.writeln('    chat history <id> [n]  Show room messages');
    stdout.writeln('    chat say <id> <msg>    Post message to room');
    stdout.writeln();
    stdout.writeln('  \x1B[33mConfiguration:\x1B[0m');
    stdout.writeln('    config             Show current configuration');
    stdout.writeln('    config set <key> <value>  Set a config value');
    stdout.writeln('    config save        Save configuration to file');
    stdout.writeln('    reload             Reload config from file');
    stdout.writeln();
    stdout.writeln('  \x1B[33mSSL/TLS Certificates:\x1B[0m');
    stdout.writeln('    ssl                Show SSL status');
    stdout.writeln('    ssl domain <name>  Set domain for SSL certificate');
    stdout.writeln('    ssl email <addr>   Set email for Let\'s Encrypt');
    stdout.writeln('    ssl request        Request Let\'s Encrypt certificate');
    stdout.writeln('    ssl test           Request test certificate (staging)');
    stdout.writeln('    ssl renew          Renew existing certificate');
    stdout.writeln('    ssl autorenew <on|off>  Enable/disable auto-renewal');
    stdout.writeln('    ssl selfsigned <domain> Generate self-signed cert');
    stdout.writeln('    ssl enable         Enable SSL/HTTPS');
    stdout.writeln('    ssl disable        Disable SSL/HTTPS');
    stdout.writeln();
    stdout.writeln('  \x1B[33mGames:\x1B[0m');
    stdout.writeln('    play <game.md>     Play a markdown game');
    stdout.writeln('    games list         List available games');
    stdout.writeln('    games info <game>  Show game details');
    stdout.writeln();
    stdout.writeln('  \x1B[33mConnection:\x1B[0m');
    stdout.writeln('    kick <callsign>    Disconnect a device');
    stdout.writeln('    broadcast <msg>    Send message to all devices');
    stdout.writeln();
    stdout.writeln('  \x1B[33mSystem:\x1B[0m');
    stdout.writeln('    setup              Run the setup wizard');
    stdout.writeln('    restart            Restart the relay server');
    stdout.writeln('    clear              Clear the screen');
    stdout.writeln('    quit / exit        Exit the CLI');
    stdout.writeln();
    stdout.writeln('  \x1B[33mVirtual Filesystem:\x1B[0m');
    stdout.writeln('    /relay/            Relay status and settings');
    stdout.writeln('    /devices/          Connected devices');
    stdout.writeln('    /chat/             Chat rooms (cd into room to chat)');
    stdout.writeln('    /config/           Configuration');
    stdout.writeln('    /logs/             View logs');
    stdout.writeln('    /ssl/              SSL/TLS certificates (cd ssl, then run commands)');
    stdout.writeln('    /games/            Markdown-based text adventure games');
    stdout.writeln();
  }

  void _printStatus() {
    final relayStatus = _relay.getStatus();

    stdout.writeln();
    stdout.writeln('\x1B[1mGeogram Desktop Status\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Version:        $cliAppVersion');
    stdout.writeln('Callsign:       ${_relay.settings.callsign}');
    stdout.writeln('Mode:           Relay (CLI)');
    stdout.writeln('Data Dir:       ${_relay.dataDir}');
    stdout.writeln();
    stdout.writeln('\x1B[1mRelay Server:\x1B[0m');
    stdout.writeln('-' * 40);
    if (relayStatus['running'] == true) {
      stdout.writeln('Status:         \x1B[32mRunning\x1B[0m');
      stdout.writeln('Port:           ${relayStatus['port']}');
      stdout.writeln('Devices:        ${relayStatus['connected_devices']}');
      stdout.writeln('Uptime:         ${_formatUptime(relayStatus['uptime'] as int)}');
      stdout.writeln('Cache:          ${relayStatus['cache_size']} tiles (${relayStatus['cache_size_mb']} MB)');
      stdout.writeln('Chat Rooms:     ${relayStatus['chat_rooms']}');
      stdout.writeln('Messages:       ${relayStatus['total_messages']}');
    } else {
      stdout.writeln('Status:         \x1B[33mStopped\x1B[0m');
      stdout.writeln('Port:           ${_relay.settings.port}');
    }
    stdout.writeln();
  }

  void _printStats() {
    final stats = _relay.stats;

    stdout.writeln();
    stdout.writeln('\x1B[1mServer Statistics\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Total Connections:     ${stats.totalConnections}');
    stdout.writeln('Total Messages:        ${stats.totalMessages}');
    stdout.writeln('Total API Requests:    ${stats.totalApiRequests}');
    stdout.writeln('Total Tile Requests:   ${stats.totalTileRequests}');
    stdout.writeln();
    stdout.writeln('\x1B[1mTile Cache:\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Tiles Cached:          ${stats.tilesCached}');
    stdout.writeln('Served from Cache:     ${stats.tilesServedFromCache}');
    stdout.writeln('Downloaded:            ${stats.tilesDownloaded}');
    stdout.writeln();
    stdout.writeln('\x1B[1mLast Activity:\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Last Connection:       ${stats.lastConnection?.toLocal() ?? 'Never'}');
    stdout.writeln('Last Message:          ${stats.lastMessage?.toLocal() ?? 'Never'}');
    stdout.writeln('Last Tile Request:     ${stats.lastTileRequest?.toLocal() ?? 'Never'}');
    stdout.writeln();
  }

  // --- Relay commands ---

  Future<void> _handleRelay(List<String> args) async {
    if (args.isEmpty) {
      _printRelayStatus();
      return;
    }

    final subcommand = args[0].toLowerCase();
    final subargs = args.length > 1 ? args.sublist(1) : <String>[];

    switch (subcommand) {
      case 'start':
        await _handleRelayStart();
        break;
      case 'stop':
        await _handleRelayStop();
        break;
      case 'status':
        _printRelayStatus();
        break;
      case 'restart':
        await _relay.restart();
        break;
      case 'port':
        await _handleRelayPort(subargs);
        break;
      case 'callsign':
        await _handleRelayCallsign(subargs);
        break;
      case 'cache':
        _handleRelayCache(subargs);
        break;
      default:
        _printError('Unknown relay command: $subcommand');
        _printError('Available: start, stop, status, restart, port, callsign, cache');
    }
  }

  Future<void> _handleRelayStart() async {
    if (_relay.isRunning) {
      stdout.writeln('\x1B[33mRelay server is already running on port ${_relay.settings.port}\x1B[0m');
      return;
    }

    stdout.writeln('Starting relay server on port ${_relay.settings.port}...');
    final success = await _relay.start();

    if (success) {
      stdout.writeln('\x1B[32mRelay server started successfully\x1B[0m');
      stdout.writeln('  Port: ${_relay.settings.port}');
      stdout.writeln('  Callsign: ${_relay.settings.callsign}');
      stdout.writeln('  Status: http://localhost:${_relay.settings.port}/api/status');
      stdout.writeln('  Tiles:  http://localhost:${_relay.settings.port}/tiles/{callsign}/{z}/{x}/{y}.png');
    } else {
      _printError('Failed to start relay server');
    }
  }

  Future<void> _handleRelayStop() async {
    if (!_relay.isRunning) {
      stdout.writeln('\x1B[33mRelay server is not running\x1B[0m');
      return;
    }

    stdout.writeln('Stopping relay server...');
    await _relay.stop();
    stdout.writeln('\x1B[32mRelay server stopped\x1B[0m');
  }

  void _printRelayStatus() {
    final status = _relay.getStatus();
    final settings = _relay.settings;

    stdout.writeln();
    stdout.writeln('\x1B[1mRelay Server Status\x1B[0m');
    stdout.writeln('-' * 40);

    if (status['running'] == true) {
      stdout.writeln('Status:        \x1B[32mRunning\x1B[0m');
      stdout.writeln('Port:          ${status['port']}');
      stdout.writeln('Callsign:      ${status['callsign']}');
      stdout.writeln('Devices:       ${status['connected_devices']}');
      stdout.writeln('Uptime:        ${_formatUptime(status['uptime'] as int)}');
      stdout.writeln('Cache:         ${status['cache_size']} tiles (${status['cache_size_mb']} MB)');
    } else {
      stdout.writeln('Status:        \x1B[33mStopped\x1B[0m');
    }

    stdout.writeln();
    stdout.writeln('\x1B[1mSettings:\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Port:          ${settings.port}');
    stdout.writeln('Callsign:      ${settings.callsign}');
    stdout.writeln('Description:   ${settings.description ?? '(not set)'}');
    stdout.writeln('Location:      ${settings.location ?? '(not set)'}');
    stdout.writeln('Tile Server:   ${settings.tileServerEnabled ? 'Enabled' : 'Disabled'}');
    stdout.writeln('OSM Fallback:  ${settings.osmFallbackEnabled ? 'Enabled' : 'Disabled'}');
    stdout.writeln('Max Zoom:      ${settings.maxZoomLevel}');
    stdout.writeln('Max Cache:     ${settings.maxCacheSize} MB');
    stdout.writeln('APRS:          ${settings.enableAprs ? 'Enabled' : 'Disabled'}');
    stdout.writeln('CORS:          ${settings.enableCors ? 'Enabled' : 'Disabled'}');
    stdout.writeln();
  }

  Future<void> _handleRelayPort(List<String> args) async {
    if (args.isEmpty) {
      stdout.writeln('Current port: ${_relay.settings.port}');
      return;
    }

    final port = int.tryParse(args[0]);
    if (port == null || port < 1 || port > 65535) {
      _printError('Invalid port number: ${args[0]} (must be 1-65535)');
      return;
    }

    final settings = _relay.settings.copyWith(port: port);
    await _relay.updateSettings(settings);
    stdout.writeln('\x1B[32mPort set to $port\x1B[0m');
  }

  Future<void> _handleRelayCallsign(List<String> args) async {
    if (args.isEmpty) {
      stdout.writeln('Current callsign: ${_relay.settings.callsign}');
      return;
    }

    final callsign = args[0].toUpperCase();
    if (callsign.length < 3 || callsign.length > 10) {
      _printError('Invalid callsign: must be 3-10 characters');
      return;
    }

    final settings = _relay.settings.copyWith(callsign: callsign);
    await _relay.updateSettings(settings);
    stdout.writeln('\x1B[32mCallsign set to $callsign\x1B[0m');
  }

  void _handleRelayCache(List<String> args) {
    if (args.isEmpty) {
      final status = _relay.getStatus();
      stdout.writeln('Cache: ${status['cache_size']} tiles (${status['cache_size_mb']} MB)');
      return;
    }

    switch (args[0].toLowerCase()) {
      case 'clear':
        _relay.clearCache();
        stdout.writeln('\x1B[32mCache cleared\x1B[0m');
        break;
      case 'stats':
        final stats = _relay.stats;
        stdout.writeln();
        stdout.writeln('\x1B[1mCache Statistics\x1B[0m');
        stdout.writeln('-' * 30);
        stdout.writeln('Tiles Cached:       ${stats.tilesCached}');
        stdout.writeln('Served from Cache:  ${stats.tilesServedFromCache}');
        stdout.writeln('Downloaded:         ${stats.tilesDownloaded}');
        stdout.writeln('Max Size:           ${_relay.settings.maxCacheSize} MB');
        stdout.writeln();
        break;
      default:
        _printError('Unknown cache command. Available: clear, stats');
    }
  }

  // --- Device commands ---

  Future<void> _handleDevices(List<String> args) async {
    if (args.isEmpty) {
      _listDevices();
      return;
    }

    switch (args[0].toLowerCase()) {
      case 'list':
        _listDevices();
        break;
      case 'scan':
        await _scanDevices(args.length > 1 ? args.sublist(1) : []);
        break;
      case 'ping':
        if (args.length < 2) {
          _printError('Usage: devices ping <ip[:port]>');
        } else {
          await _pingDevice(args[1]);
        }
        break;
      case 'kick':
        if (args.length < 2) {
          _printError('Usage: devices kick <callsign>');
        } else {
          _handleKick(args.sublist(1));
        }
        break;
      default:
        _printError('Unknown devices command. Available: list, scan, ping, kick');
    }
  }

  void _listDevices() {
    final clients = _relay.clients;

    stdout.writeln();
    stdout.writeln('\x1B[1mConnected Devices (${clients.length})\x1B[0m');
    stdout.writeln('-' * 60);

    if (clients.isEmpty) {
      stdout.writeln('No devices connected');
    } else {
      stdout.writeln('${'Callsign'.padRight(12)} ${'Type'.padRight(10)} ${'Address'.padRight(16)} Connected');
      stdout.writeln('-' * 60);
      for (final client in clients.values) {
        final connectedAgo = DateTime.now().difference(client.connectedAt);
        stdout.writeln(
          '${(client.callsign ?? 'Unknown').padRight(12)} '
          '${(client.deviceType ?? 'Unknown').padRight(10)} '
          '${(client.address ?? 'Unknown').padRight(16)} '
          '${_formatDuration(connectedAgo)} ago'
        );
      }
    }
    stdout.writeln();
  }

  Future<void> _scanDevices(List<String> args) async {
    int timeout = 2000;
    for (int i = 0; i < args.length - 1; i++) {
      if (args[i] == '-t') {
        timeout = int.tryParse(args[i + 1]) ?? 2000;
      }
    }

    stdout.writeln('Scanning network for Geogram devices (timeout: ${timeout}ms)...');
    final devices = await _relay.scanNetwork(timeout: timeout);

    stdout.writeln();
    stdout.writeln('\x1B[1mDiscovered Devices (${devices.length})\x1B[0m');
    stdout.writeln('-' * 60);

    if (devices.isEmpty) {
      stdout.writeln('No devices found');
    } else {
      for (final device in devices) {
        stdout.writeln(
          '${device['callsign'].toString().padRight(12)} '
          '${device['type'].toString().padRight(8)} '
          '${device['ip']}:${device['port']} '
          'v${device['version']}'
        );
      }
    }
    stdout.writeln();
  }

  Future<void> _pingDevice(String address) async {
    stdout.writeln('Pinging $address...');
    final result = await _relay.pingDevice(address);

    if (result != null) {
      stdout.writeln();
      stdout.writeln('\x1B[32mDevice found:\x1B[0m');
      stdout.writeln('  Callsign: ${result['callsign']}');
      stdout.writeln('  Type:     ${result['type']}');
      stdout.writeln('  Name:     ${result['name']}');
      stdout.writeln('  Version:  ${result['version']}');
      stdout.writeln('  Address:  ${result['ip']}:${result['port']}');
    } else {
      _printError('Device not responding at $address');
    }
  }

  void _handleKick(List<String> args) {
    if (args.isEmpty) {
      _printError('Usage: kick <callsign>');
      return;
    }

    final callsign = args[0];
    if (_relay.kickDevice(callsign)) {
      stdout.writeln('\x1B[32mDevice $callsign disconnected\x1B[0m');
    } else {
      _printError('Device not found: $callsign');
    }
  }

  // --- Chat commands ---

  Future<void> _handleChat(List<String> args) async {
    if (args.isEmpty) {
      _listChatRooms();
      return;
    }

    switch (args[0].toLowerCase()) {
      case 'list':
        _listChatRooms();
        break;
      case 'info':
        if (args.length < 2) {
          _printError('Usage: chat info <room_id>');
        } else {
          _showChatInfo(args[1]);
        }
        break;
      case 'create':
        if (args.length < 3) {
          _printError('Usage: chat create <id> <name> [description]');
        } else {
          final desc = args.length > 3 ? args.sublist(3).join(' ') : null;
          _createChatRoom(args[1], args[2], desc);
        }
        break;
      case 'delete':
        if (args.length < 2) {
          _printError('Usage: chat delete <room_id>');
        } else {
          _deleteChatRoom(args[1]);
        }
        break;
      case 'rename':
        if (args.length < 3) {
          _printError('Usage: chat rename <old_id> <new_name>');
        } else {
          _renameChatRoom(args[1], args[2]);
        }
        break;
      case 'history':
        if (args.length < 2) {
          _printError('Usage: chat history <room_id> [count]');
        } else {
          _showChatHistory(args[1], args.length > 2 ? int.tryParse(args[2]) : null);
        }
        break;
      case 'say':
        if (args.length < 3) {
          _printError('Usage: chat say <room_id> <message>');
        } else {
          _postMessage(args[1], args.sublist(2).join(' '));
        }
        break;
      case 'delmsg':
        if (args.length < 3) {
          _printError('Usage: chat delmsg <room_id> <message_id>');
        } else {
          if (_relay.deleteMessage(args[1], args[2])) {
            stdout.writeln('Message deleted');
          } else {
            _printError('Message not found');
          }
        }
        break;
      default:
        _printError('Unknown chat command. Available: list, info, create, delete, rename, history, say, delmsg');
    }
  }

  void _listChatRooms() {
    final rooms = _relay.chatRooms;

    stdout.writeln();
    stdout.writeln('\x1B[1mChat Rooms (${rooms.length})\x1B[0m');
    stdout.writeln('-' * 50);

    for (final room in rooms.values) {
      stdout.writeln(
        '${room.id.padRight(15)} '
        '${room.name.padRight(20)} '
        '${room.messages.length} msgs'
      );
    }
    stdout.writeln();
  }

  void _showChatInfo(String roomId) {
    final room = _relay.chatRooms[roomId];
    if (room == null) {
      _printError('Room not found: $roomId');
      return;
    }

    stdout.writeln();
    stdout.writeln('\x1B[1mChat Room: ${room.name}\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('ID:          ${room.id}');
    stdout.writeln('Name:        ${room.name}');
    stdout.writeln('Description: ${room.description.isEmpty ? '(none)' : room.description}');
    stdout.writeln('Creator:     ${room.creatorCallsign}');
    stdout.writeln('Created:     ${room.createdAt.toLocal()}');
    stdout.writeln('Last Active: ${room.lastActivity.toLocal()}');
    stdout.writeln('Messages:    ${room.messages.length}');
    stdout.writeln('Public:      ${room.isPublic ? 'Yes' : 'No'}');
    stdout.writeln();
  }

  void _createChatRoom(String id, String name, String? description) {
    final room = _relay.createChatRoom(id, name, description: description);
    if (room != null) {
      stdout.writeln('\x1B[32mChat room created: $name ($id)\x1B[0m');
    } else {
      _printError('Room with ID "$id" already exists');
    }
  }

  void _deleteChatRoom(String id) {
    if (id == 'general') {
      _printError('Cannot delete the general room');
      return;
    }
    if (_relay.deleteChatRoom(id)) {
      stdout.writeln('\x1B[32mChat room deleted: $id\x1B[0m');
    } else {
      _printError('Room not found: $id');
    }
  }

  void _renameChatRoom(String id, String newName) {
    if (_relay.renameChatRoom(id, newName)) {
      stdout.writeln('\x1B[32mRoom renamed to: $newName\x1B[0m');
    } else {
      _printError('Room not found: $id');
    }
  }

  void _showChatHistory(String roomId, int? limit) {
    final messages = _relay.getChatHistory(roomId, limit: limit ?? 20);
    if (messages.isEmpty) {
      stdout.writeln('No messages in room');
      return;
    }

    stdout.writeln();
    for (final msg in messages) {
      final time = msg.timestamp.toLocal();
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      stdout.writeln('\x1B[33m[$timeStr]\x1B[0m \x1B[36m${msg.senderCallsign}:\x1B[0m ${msg.content}');
    }
    stdout.writeln();
  }

  void _postMessage(String roomId, String message) {
    if (!_relay.chatRooms.containsKey(roomId)) {
      _printError('Room not found: $roomId');
      return;
    }
    _relay.postMessage(roomId, message);
    stdout.writeln('Message sent');
  }

  void _handleChatHistory(List<String> args) {
    if (_currentChatRoom == null) return;
    final limit = args.isNotEmpty ? int.tryParse(args[0]) : null;
    _showChatHistory(_currentChatRoom!, limit);
  }

  void _handleDeleteMessage(List<String> args) {
    if (_currentChatRoom == null || args.isEmpty) return;
    if (_relay.deleteMessage(_currentChatRoom!, args[0])) {
      stdout.writeln('Message deleted');
    } else {
      _printError('Message not found');
    }
  }

  // --- Config commands ---

  Future<void> _handleConfig(List<String> args) async {
    if (args.isEmpty) {
      _showConfig();
      return;
    }

    switch (args[0].toLowerCase()) {
      case 'set':
        if (args.length < 3) {
          _printError('Usage: config set <key> <value>');
        } else {
          await _setConfig(args[1], args.sublist(2).join(' '));
        }
        break;
      case 'save':
        await _relay.saveSettings();
        stdout.writeln('\x1B[32mConfiguration saved\x1B[0m');
        break;
      default:
        _printError('Unknown config command. Available: set, save');
    }
  }

  void _showConfig() {
    final settings = _relay.settings;

    stdout.writeln();
    stdout.writeln('\x1B[1mConfiguration\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('port:               ${settings.port}');
    stdout.writeln('callsign:           ${settings.callsign}');
    stdout.writeln('description:        ${settings.description ?? '(not set)'}');
    stdout.writeln('location:           ${settings.location ?? '(not set)'}');
    stdout.writeln('latitude:           ${settings.latitude ?? '(not set)'}');
    stdout.writeln('longitude:          ${settings.longitude ?? '(not set)'}');
    stdout.writeln('tileServerEnabled:  ${settings.tileServerEnabled}');
    stdout.writeln('osmFallbackEnabled: ${settings.osmFallbackEnabled}');
    stdout.writeln('maxZoomLevel:       ${settings.maxZoomLevel}');
    stdout.writeln('maxCacheSize:       ${settings.maxCacheSize}');
    stdout.writeln('enableAprs:         ${settings.enableAprs}');
    stdout.writeln('enableCors:         ${settings.enableCors}');
    stdout.writeln('maxConnectedDevices: ${settings.maxConnectedDevices}');
    stdout.writeln();
    stdout.writeln('Use "config set <key> <value>" to change settings');
    stdout.writeln('Use "config save" to persist changes');
    stdout.writeln();
  }

  Future<void> _setConfig(String key, String value) async {
    try {
      dynamic parsedValue;
      if (value == 'true') {
        parsedValue = true;
      } else if (value == 'false') {
        parsedValue = false;
      } else if (int.tryParse(value) != null) {
        parsedValue = int.parse(value);
      } else if (double.tryParse(value) != null) {
        parsedValue = double.parse(value);
      } else {
        parsedValue = value;
      }

      _relay.setSetting(key, parsedValue);
      stdout.writeln('\x1B[32m$key set to $value\x1B[0m');
      stdout.writeln('Use "config save" to persist changes');
    } catch (e) {
      _printError('Failed to set $key: $e');
    }
  }

  // --- Logs command ---

  void _handleLogs(List<String> args) {
    final limit = args.isNotEmpty ? int.tryParse(args[0]) ?? 20 : 20;
    final logs = _relay.getLogs(limit: limit);

    stdout.writeln();
    stdout.writeln('\x1B[1mRecent Logs (${logs.length})\x1B[0m');
    stdout.writeln('-' * 60);

    if (logs.isEmpty) {
      stdout.writeln('No logs available');
    } else {
      for (final log in logs) {
        final levelColor = switch (log.level) {
          'ERROR' => '\x1B[31m',
          'WARN' => '\x1B[33m',
          'INFO' => '\x1B[32m',
          _ => '\x1B[0m',
        };
        final time = log.timestamp.toLocal();
        final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
        stdout.writeln('$timeStr $levelColor[${log.level}]\x1B[0m ${log.message}');
      }
    }
    stdout.writeln();
  }

  // --- Broadcast command ---

  void _handleBroadcast(List<String> args) {
    if (args.isEmpty) {
      _printError('Usage: broadcast <message>');
      return;
    }

    final message = args.join(' ');
    _relay.broadcast(message);
    stdout.writeln('\x1B[32mBroadcast sent to ${_relay.connectedDevices} devices\x1B[0m');
  }

  // --- Disk usage command ---

  Future<void> _handleDf(List<String> args) async {
    final humanReadable = args.contains('-h');
    final dataDir = _relay.dataDir;

    if (dataDir == null) {
      _printError('Data directory not initialized');
      return;
    }

    stdout.writeln();
    stdout.writeln('\x1B[1mDisk Usage\x1B[0m');
    stdout.writeln('-' * 50);

    // Calculate directory sizes
    final tilesDir = Directory('$dataDir/tiles');
    int tilesSize = 0;
    if (await tilesDir.exists()) {
      await for (final entity in tilesDir.list(recursive: true)) {
        if (entity is File) {
          tilesSize += await entity.length();
        }
      }
    }

    final configFile = File('$dataDir/relay_config.json');
    final configSize = await configFile.exists() ? await configFile.length() : 0;

    final total = tilesSize + configSize;

    if (humanReadable) {
      stdout.writeln('Tiles:  ${_formatBytes(tilesSize)}');
      stdout.writeln('Config: ${_formatBytes(configSize)}');
      stdout.writeln('Total:  ${_formatBytes(total)}');
    } else {
      stdout.writeln('Tiles:  $tilesSize bytes');
      stdout.writeln('Config: $configSize bytes');
      stdout.writeln('Total:  $total bytes');
    }
    stdout.writeln();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // --- Top command (live monitoring dashboard) ---

  Future<void> _handleTop() async {
    stdout.writeln('Live monitoring - press q to exit');
    stdout.writeln();

    _console.rawMode = true;
    try {
      var running = true;
      while (running) {
        // Clear screen and move cursor to top
        stdout.write('\x1B[2J\x1B[H');

        // Header
        stdout.writeln('\x1B[1;36m=== Geogram Desktop - Live Monitor ===\x1B[0m');
        stdout.writeln('\x1B[33mPress q to exit\x1B[0m');
        stdout.writeln();

        // Status section
        final status = _relay.getStatus();
        final relayStatus = status['running'] == true
            ? '\x1B[32mRunning\x1B[0m'
            : '\x1B[33mStopped\x1B[0m';
        stdout.writeln('\x1B[1mRelay:\x1B[0m $relayStatus  '
            '\x1B[1mPort:\x1B[0m ${status['port']}  '
            '\x1B[1mDevices:\x1B[0m ${status['connected_devices']}  '
            '\x1B[1mUptime:\x1B[0m ${_formatUptime(status['uptime'] as int)}');
        stdout.writeln();

        // Stats section
        final stats = _relay.stats;
        stdout.writeln('\x1B[1mStats:\x1B[0m  '
            'Connections: ${stats.totalConnections}  '
            'Messages: ${stats.totalMessages}  '
            'API: ${stats.totalApiRequests}  '
            'Tiles: ${stats.totalTileRequests}');
        stdout.writeln();

        // Recent logs
        stdout.writeln('\x1B[1mRecent Logs:\x1B[0m');
        stdout.writeln('-' * 60);
        final logs = _relay.getLogs(limit: 15);
        if (logs.isEmpty) {
          stdout.writeln('(no logs)');
        } else {
          for (final log in logs) {
            final levelColor = switch (log.level) {
              'ERROR' => '\x1B[31m',
              'WARN' => '\x1B[33m',
              'INFO' => '\x1B[32m',
              _ => '\x1B[0m',
            };
            final time = log.timestamp.toLocal();
            final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
            stdout.writeln('$timeStr $levelColor[${log.level}]\x1B[0m ${log.message}');
          }
        }

        // Check for q key (non-blocking)
        // Wait for up to 1 second, checking for input
        final stopwatch = Stopwatch()..start();
        while (stopwatch.elapsedMilliseconds < 1000) {
          // Check if there's input available
          if (stdin.hasTerminal) {
            try {
              final key = _console.readKey();
              if (key.char.toLowerCase() == 'q') {
                running = false;
                break;
              }
            } catch (_) {
              // No input available, continue waiting
            }
          }
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
    } finally {
      _console.rawMode = false;
    }

    stdout.writeln();
    stdout.writeln('Exited live monitor');
  }

  // --- File viewing commands (tail, head, cat) ---

  Future<void> _handleTail(List<String> args) async {
    int lines = 10;
    String? target;

    // Parse arguments: tail [-n lines] [target]
    var i = 0;
    while (i < args.length) {
      if (args[i] == '-n' && i + 1 < args.length) {
        lines = int.tryParse(args[i + 1]) ?? 10;
        i += 2;
      } else {
        target = args[i];
        i++;
      }
    }

    await _viewFile(target ?? 'logs', lines: lines, mode: 'tail');
  }

  Future<void> _handleHead(List<String> args) async {
    int lines = 10;
    String? target;

    // Parse arguments: head [-n lines] [target]
    var i = 0;
    while (i < args.length) {
      if (args[i] == '-n' && i + 1 < args.length) {
        lines = int.tryParse(args[i + 1]) ?? 10;
        i += 2;
      } else {
        target = args[i];
        i++;
      }
    }

    await _viewFile(target ?? 'logs', lines: lines, mode: 'head');
  }

  Future<void> _handleCat(List<String> args) async {
    if (args.isEmpty) {
      _printError('Usage: cat <file>');
      _printError('Available: logs, config, /path/to/file');
      return;
    }

    await _viewFile(args[0], mode: 'cat');
  }

  Future<void> _viewFile(String target, {int lines = 10, required String mode}) async {
    List<String> content = [];

    // Handle virtual files
    switch (target.toLowerCase()) {
      case 'logs':
      case '/logs':
        final logs = _relay.logs;
        content = logs.map((log) {
          final time = log.timestamp.toLocal();
          final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
          return '$timeStr [${log.level}] ${log.message}';
        }).toList();
        break;

      case 'config':
      case '/config':
      case 'relay_config.json':
        final settings = _relay.settings;
        content = [
          '{',
          '  "port": ${settings.port},',
          '  "callsign": "${settings.callsign}",',
          '  "description": "${settings.description ?? ''}",',
          '  "location": "${settings.location ?? ''}",',
          '  "latitude": ${settings.latitude ?? 'null'},',
          '  "longitude": ${settings.longitude ?? 'null'},',
          '  "tileServerEnabled": ${settings.tileServerEnabled},',
          '  "osmFallbackEnabled": ${settings.osmFallbackEnabled},',
          '  "maxZoomLevel": ${settings.maxZoomLevel},',
          '  "maxCacheSize": ${settings.maxCacheSize},',
          '  "enableAprs": ${settings.enableAprs},',
          '  "enableCors": ${settings.enableCors},',
          '  "maxConnectedDevices": ${settings.maxConnectedDevices}',
          '}',
        ];
        break;

      default:
        // Try to read as real file
        final file = File(target);
        if (await file.exists()) {
          try {
            content = await file.readAsLines();
          } catch (e) {
            _printError('Cannot read file: $e');
            return;
          }
        } else {
          _printError('File not found: $target');
          _printError('Available virtual files: logs, config');
          return;
        }
    }

    if (content.isEmpty) {
      stdout.writeln('(empty)');
      return;
    }

    // Apply mode
    List<String> output;
    switch (mode) {
      case 'head':
        output = content.take(lines).toList();
        break;
      case 'tail':
        output = content.length > lines
            ? content.sublist(content.length - lines)
            : content;
        break;
      case 'cat':
      default:
        output = content;
    }

    // Print with line numbers for cat
    if (mode == 'cat') {
      final maxLineNum = output.length.toString().length;
      for (var i = 0; i < output.length; i++) {
        final lineNum = (i + 1).toString().padLeft(maxLineNum);
        stdout.writeln('\x1B[33m$lineNum\x1B[0m  ${output[i]}');
      }
    } else {
      for (final line in output) {
        stdout.writeln(line);
      }
    }
  }

  // --- Setup wizard ---

  Future<void> _handleSetup() async {
    stdout.writeln();
    stdout.writeln('\x1B[1;36m' + '=' * 60 + '\x1B[0m');
    stdout.writeln('\x1B[1;36m  Geogram Desktop Relay Setup Wizard\x1B[0m');
    stdout.writeln('\x1B[1;36m' + '=' * 60 + '\x1B[0m');
    stdout.writeln();

    // Step 1: Relay Identity
    _printSection('STEP 1: RELAY IDENTITY');
    final callsign = await _generateCallsign();
    stdout.writeln('Generated relay callsign: \x1B[32m$callsign\x1B[0m');
    stdout.writeln();

    // Step 2: Relay Role
    _printSection('STEP 2: RELAY NETWORK ROLE');
    stdout.writeln('Select relay role:');
    stdout.writeln('  \x1B[33m1)\x1B[0m Root Relay - Primary relay (accepts node connections)');
    stdout.writeln('  \x1B[33m2)\x1B[0m Node Relay - Connects to an existing root relay');
    stdout.writeln();

    final roleChoice = await _promptChoice('Enter choice (1 or 2)', ['1', '2']);
    final isRoot = roleChoice == '1';
    String? parentUrl;
    String? networkId;

    if (isRoot) {
      stdout.writeln('Configuring as \x1B[32mRoot Relay\x1B[0m');
      networkId = await _promptInputWithDefault('Network ID (optional)', '');
    } else {
      stdout.writeln('Configuring as \x1B[33mNode Relay\x1B[0m');
      stdout.writeln();

      // Validate parent URL
      while (parentUrl == null || parentUrl.isEmpty) {
        parentUrl = await _promptInput('Root relay WebSocket URL (e.g., ws://relay.example.com:8080): ');
        if (parentUrl != null && parentUrl.isNotEmpty) {
          if (!parentUrl.startsWith('ws://') && !parentUrl.startsWith('wss://')) {
            stdout.writeln('\x1B[31mInvalid URL format. Must start with "ws://" or "wss://"\x1B[0m');
            parentUrl = null;
          }
        }
      }
      networkId = await _promptInputWithDefault('Network ID (should match root relay)', '');
    }
    stdout.writeln();

    // Step 3: Server Settings
    _printSection('STEP 3: SERVER SETTINGS');

    final portStr = await _promptInputWithDefault('Server port', '${_relay.settings.port}');
    final port = int.tryParse(portStr) ?? 8080;

    final description = await _promptInputWithDefault(
      'Server description',
      _relay.settings.description ?? 'Geogram Desktop Relay',
    );

    final location = await _promptInputWithDefault(
      'Location (optional)',
      _relay.settings.location ?? '',
    );

    String? latStr;
    String? lonStr;
    double? latitude;
    double? longitude;

    if (location.isNotEmpty) {
      latStr = await _promptInputWithDefault('Latitude (optional)', '');
      lonStr = await _promptInputWithDefault('Longitude (optional)', '');
      latitude = latStr.isNotEmpty ? double.tryParse(latStr) : null;
      longitude = lonStr.isNotEmpty ? double.tryParse(lonStr) : null;
    }
    stdout.writeln();

    // Step 4: Features
    _printSection('STEP 4: FEATURES');

    final enableAprs = await _promptConfirm('Enable APRS-IS announcements?', false);
    final enableTiles = await _promptConfirm('Enable tile server?', true);
    final enableOsmFallback = enableTiles && await _promptConfirm('Enable OSM fallback for tiles?', true);
    stdout.writeln();

    // Summary
    _printSection('SETUP SUMMARY');
    stdout.writeln('Relay Configuration:');
    stdout.writeln('  Callsign:       \x1B[36m$callsign\x1B[0m');
    stdout.writeln('  Role:           \x1B[36m${isRoot ? 'ROOT' : 'NODE'}\x1B[0m');
    if (!isRoot && parentUrl != null) {
      stdout.writeln('  Parent Relay:   \x1B[36m$parentUrl\x1B[0m');
    }
    if (networkId != null && networkId.isNotEmpty) {
      stdout.writeln('  Network ID:     \x1B[36m$networkId\x1B[0m');
    }
    stdout.writeln();
    stdout.writeln('Server Settings:');
    stdout.writeln('  Port:           \x1B[36m$port\x1B[0m');
    stdout.writeln('  Description:    \x1B[36m$description\x1B[0m');
    if (location.isNotEmpty) {
      stdout.writeln('  Location:       \x1B[36m$location\x1B[0m');
    }
    if (latitude != null && longitude != null) {
      stdout.writeln('  Coordinates:    \x1B[36m$latitude, $longitude\x1B[0m');
    }
    stdout.writeln();
    stdout.writeln('Features:');
    stdout.writeln('  APRS:           ${enableAprs ? '\x1B[32mEnabled\x1B[0m' : '\x1B[33mDisabled\x1B[0m'}');
    stdout.writeln('  Tile Server:    ${enableTiles ? '\x1B[32mEnabled\x1B[0m' : '\x1B[33mDisabled\x1B[0m'}');
    if (enableTiles) {
      stdout.writeln('  OSM Fallback:   ${enableOsmFallback ? '\x1B[32mEnabled\x1B[0m' : '\x1B[33mDisabled\x1B[0m'}');
    }
    stdout.writeln();

    final confirm = await _promptConfirm('Save this configuration?', true);
    if (!confirm) {
      stdout.writeln('\x1B[33mSetup cancelled. No changes saved.\x1B[0m');
      return;
    }

    // Apply settings
    final newSettings = _relay.settings.copyWith(
      callsign: callsign,
      relayRole: isRoot ? 'root' : 'node',
      parentRelayUrl: parentUrl,
      networkId: networkId,
      port: port,
      description: description,
      location: location.isNotEmpty ? location : null,
      latitude: latitude,
      longitude: longitude,
      enableAprs: enableAprs,
      tileServerEnabled: enableTiles,
      osmFallbackEnabled: enableOsmFallback,
      setupComplete: true,
    );

    await _relay.updateSettings(newSettings);

    stdout.writeln();
    stdout.writeln('\x1B[32mConfiguration saved successfully!\x1B[0m');
    stdout.writeln();
    stdout.writeln('To start the relay server, type: \x1B[36mrelay start\x1B[0m');
    stdout.writeln();
  }

  void _printSection(String title) {
    stdout.writeln('\x1B[1;33m--- $title ---\x1B[0m');
    stdout.writeln();
  }

  Future<String> _generateCallsign() async {
    // Generate X3 + random alphanumeric suffix
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final suffix = String.fromCharCodes(
      List.generate(4, (i) => chars.codeUnitAt((random ~/ (i + 1)) % chars.length)),
    );
    return 'X3$suffix';
  }

  Future<String> _promptInput(String prompt) async {
    stdout.write('$prompt ');
    return stdin.readLineSync()?.trim() ?? '';
  }

  Future<String> _promptInputWithDefault(String prompt, String defaultValue) async {
    if (defaultValue.isNotEmpty) {
      stdout.write('$prompt [\x1B[36m$defaultValue\x1B[0m]: ');
    } else {
      stdout.write('$prompt: ');
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  Future<String> _promptChoice(String prompt, List<String> validChoices) async {
    while (true) {
      stdout.write('$prompt: ');
      final input = stdin.readLineSync()?.trim() ?? '';
      if (validChoices.contains(input)) {
        return input;
      }
      stdout.writeln('\x1B[31mInvalid choice. Please enter one of: ${validChoices.join(', ')}\x1B[0m');
    }
  }

  Future<bool> _promptConfirm(String prompt, bool defaultValue) async {
    final defaultStr = defaultValue ? 'Y/n' : 'y/N';
    stdout.write('$prompt [$defaultStr]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (input.isEmpty) return defaultValue;
    return input == 'y' || input == 'yes';
  }

  // --- SSL commands ---

  Future<void> _handleSsl(List<String> args) async {
    if (args.isEmpty) {
      await _showSslStatus();
      return;
    }

    final subcommand = args[0].toLowerCase();
    final subargs = args.length > 1 ? args.sublist(1) : <String>[];

    switch (subcommand) {
      case 'domain':
        await _handleSslDomain(subargs);
        break;
      case 'email':
        await _handleSslEmail(subargs);
        break;
      case 'request':
        await _handleSslRequest(staging: false);
        break;
      case 'test':
        await _handleSslRequest(staging: true);
        break;
      case 'renew':
        await _handleSslRenew();
        break;
      case 'autorenew':
        await _handleSslAutoRenew(subargs);
        break;
      case 'selfsigned':
        await _handleSslSelfSigned(subargs);
        break;
      case 'enable':
        await _handleSslEnable(true);
        break;
      case 'disable':
        await _handleSslEnable(false);
        break;
      default:
        _printError('Unknown ssl command: $subcommand');
        _printError('Available: domain, email, request, test, renew, autorenew, selfsigned, enable, disable');
    }
  }

  Future<void> _showSslStatus() async {
    if (_sslManager == null) {
      _printError('SSL manager not initialized');
      return;
    }

    final status = await _sslManager!.getStatus();

    stdout.writeln();
    stdout.writeln('\x1B[1mSSL/TLS Certificate Status\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('Domain:         ${status['domain']}');
    stdout.writeln('Email:          ${status['email']}');
    stdout.writeln('SSL Enabled:    ${status['enabled'] == true ? '\x1B[32mYes\x1B[0m' : '\x1B[33mNo\x1B[0m'}');
    stdout.writeln('Auto-Renew:     ${status['autoRenew'] == true ? '\x1B[32mEnabled\x1B[0m' : '\x1B[33mDisabled\x1B[0m'}');
    stdout.writeln('Certificate:    ${status['hasCertificate'] == true ? '\x1B[32mInstalled\x1B[0m' : '\x1B[33mNot installed\x1B[0m'}');

    if (status['hasCertificate'] == true) {
      if (status['expiresAt'] != null) {
        stdout.writeln('Expires:        ${status['expiresAt']}');
        stdout.writeln('Days Left:      ${status['daysUntilExpiry']}');
      }
      if (status['certPath'] != null) {
        stdout.writeln('Cert Path:      ${status['certPath']}');
      }
    }

    stdout.writeln();
    stdout.writeln('\x1B[33mSSL Commands:\x1B[0m');
    stdout.writeln('  ssl domain <domain>      Set domain for certificate');
    stdout.writeln('  ssl email <email>        Set email for Let\'s Encrypt');
    stdout.writeln('  ssl request              Request production certificate');
    stdout.writeln('  ssl test                 Request test certificate (staging)');
    stdout.writeln('  ssl renew                Force certificate renewal');
    stdout.writeln('  ssl autorenew <on|off>   Enable/disable auto-renewal');
    stdout.writeln('  ssl selfsigned [domain]  Generate self-signed certificate');
    stdout.writeln('  ssl enable               Enable SSL/HTTPS');
    stdout.writeln('  ssl disable              Disable SSL/HTTPS');
    stdout.writeln();
  }

  Future<void> _handleSslDomain(List<String> args) async {
    if (args.isEmpty) {
      stdout.writeln('Current domain: ${_relay.settings.sslDomain ?? '(not set)'}');
      return;
    }

    final domain = args[0];
    final settings = _relay.settings.copyWith(sslDomain: domain);
    await _relay.updateSettings(settings);
    stdout.writeln('\x1B[32mSSL domain set to: $domain\x1B[0m');
  }

  Future<void> _handleSslEmail(List<String> args) async {
    if (args.isEmpty) {
      stdout.writeln('Current email: ${_relay.settings.sslEmail ?? '(not set)'}');
      return;
    }

    final email = args[0];
    if (!email.contains('@')) {
      _printError('Invalid email address');
      return;
    }

    final settings = _relay.settings.copyWith(sslEmail: email);
    await _relay.updateSettings(settings);
    stdout.writeln('\x1B[32mSSL email set to: $email\x1B[0m');
  }

  Future<void> _handleSslRequest({required bool staging}) async {
    if (_sslManager == null) {
      _printError('SSL manager not initialized');
      return;
    }

    final envType = staging ? 'staging (test)' : 'production';
    stdout.writeln('Requesting $envType certificate...');
    stdout.writeln('Domain: ${_relay.settings.sslDomain}');
    stdout.writeln('Email:  ${_relay.settings.sslEmail}');
    stdout.writeln();

    try {
      final success = await _sslManager!.requestCertificate(staging: staging);
      if (success) {
        stdout.writeln('\x1B[32mCertificate request successful!\x1B[0m');
        stdout.writeln();
        stdout.writeln('To enable HTTPS, run: ssl enable');
        stdout.writeln('Then restart the relay: restart');
      }
    } catch (e) {
      _printError('Certificate request failed: $e');
    }
  }

  Future<void> _handleSslRenew() async {
    if (_sslManager == null) {
      _printError('SSL manager not initialized');
      return;
    }

    stdout.writeln('Renewing certificate...');

    try {
      final success = await _sslManager!.renewCertificate(staging: false);
      if (success) {
        stdout.writeln('\x1B[32mCertificate renewed successfully!\x1B[0m');
      }
    } catch (e) {
      _printError('Certificate renewal failed: $e');
    }
  }

  Future<void> _handleSslAutoRenew(List<String> args) async {
    if (args.isEmpty) {
      final current = _relay.settings.sslAutoRenew ? 'on' : 'off';
      stdout.writeln('Auto-renewal is currently: $current');
      return;
    }

    final value = args[0].toLowerCase();
    final enabled = value == 'on' || value == 'true' || value == '1';

    final settings = _relay.settings.copyWith(sslAutoRenew: enabled);
    await _relay.updateSettings(settings);

    if (enabled) {
      _sslManager?.startAutoRenewal();
      stdout.writeln('\x1B[32mAuto-renewal enabled\x1B[0m');
    } else {
      _sslManager?.stop();
      stdout.writeln('\x1B[33mAuto-renewal disabled\x1B[0m');
    }
  }

  Future<void> _handleSslSelfSigned(List<String> args) async {
    if (_sslManager == null) {
      _printError('SSL manager not initialized');
      return;
    }

    final domain = args.isNotEmpty ? args[0] : (_relay.settings.sslDomain ?? 'localhost');

    stdout.writeln('Generating self-signed certificate for: $domain');

    try {
      final success = await _sslManager!.generateSelfSigned(domain);
      if (success) {
        stdout.writeln('\x1B[32mSelf-signed certificate generated!\x1B[0m');
        stdout.writeln('\x1B[33mWarning: Self-signed certificates are not trusted by browsers.\x1B[0m');
        stdout.writeln();
        stdout.writeln('To enable HTTPS, run: ssl enable');
        stdout.writeln('Then restart the relay: restart');
      }
    } catch (e) {
      _printError('Failed to generate self-signed certificate: $e');
    }
  }

  Future<void> _handleSslEnable(bool enable) async {
    if (_sslManager == null) {
      _printError('SSL manager not initialized');
      return;
    }

    if (enable && !_sslManager!.hasCertificate()) {
      _printError('No certificate installed. Run "ssl request" or "ssl selfsigned" first.');
      return;
    }

    final settings = _relay.settings.copyWith(
      enableSsl: enable,
      sslCertPath: enable ? _sslManager!.certPath : null,
      sslKeyPath: enable ? _sslManager!.domainKeyPath : null,
    );
    await _relay.updateSettings(settings);

    if (enable) {
      stdout.writeln('\x1B[32mSSL/HTTPS enabled\x1B[0m');
      stdout.writeln('HTTPS will be available on port ${_relay.settings.sslPort} after restart');
    } else {
      stdout.writeln('\x1B[33mSSL/HTTPS disabled\x1B[0m');
    }
    stdout.writeln('Restart the relay for changes to take effect: restart');
  }

  // --- Game commands ---

  Future<void> _handlePlay(List<String> args) async {
    if (args.isEmpty) {
      _printError('Usage: play <game-name.md>');
      stdout.writeln('Use "ls /games" or "games list" to see available games');
      return;
    }

    final gameName = args[0];
    final gamePath = _gameConfig.getGamePath(gameName);

    if (gamePath == null) {
      _printError('Game not found: $gameName');
      stdout.writeln('Use "ls /games" or "games list" to see available games');
      return;
    }

    try {
      final content = await File(gamePath).readAsString();
      final parser = GameParser();
      final game = parser.parse(content);

      final screen = GameScreen();
      final engine = GameEngine(game: game, screen: screen);

      stdout.writeln();
      stdout.writeln('\x1B[1;36mStarting game: ${game.title}\x1B[0m');
      stdout.writeln('\x1B[90mPress Ctrl+C or type "quit" to exit the game\x1B[0m');
      stdout.writeln();

      await engine.run();

      stdout.writeln();
      stdout.writeln('\x1B[1;33mGame ended. Returning to CLI.\x1B[0m');
      stdout.writeln();
    } catch (e) {
      _printError('Failed to start game: $e');
    }
  }

  Future<void> _handleGames(List<String> args) async {
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
          _printError('Usage: games info <game-name>');
        } else {
          _showGameInfo(args[1]);
        }
        break;
      default:
        _printError('Unknown games command: ${args[0]}');
        stdout.writeln('Available: list, info');
    }
  }

  void _listGames() {
    final games = _gameConfig.listGames();

    stdout.writeln();
    stdout.writeln('\x1B[1mAvailable Games (${games.length})\x1B[0m');
    stdout.writeln('-' * 40);

    if (games.isEmpty) {
      stdout.writeln('No games found in ${_gameConfig.gamesDirectory}');
      stdout.writeln('Add .md game files to play');
    } else {
      for (final game in games) {
        final name = game.path.split('/').last;
        final info = _gameConfig.getGameInfo(name);
        final title = info?['title'] ?? name.replaceAll('.md', '');
        stdout.writeln('  \x1B[36m${name.padRight(25)}\x1B[0m $title');
      }
    }

    stdout.writeln();
    stdout.writeln('Use "play <game-name>" to start a game');
    stdout.writeln();
  }

  void _showGameInfo(String name) {
    final info = _gameConfig.getGameInfo(name);

    if (info == null) {
      _printError('Game not found: $name');
      return;
    }

    stdout.writeln();
    stdout.writeln('\x1B[1mGame: ${info['title']}\x1B[0m');
    stdout.writeln('-' * 40);
    stdout.writeln('File:      ${info['name']}');
    stdout.writeln('Scenes:    ${info['scenes']}');
    stdout.writeln('Items:     ${info['items']}');
    stdout.writeln('Opponents: ${info['opponents']}');
    stdout.writeln('Actions:   ${info['actions']}');
    stdout.writeln();
    stdout.writeln('To play: play ${info['name']}');
    stdout.writeln();
  }

  // --- Navigation commands ---

  void _handleLs(List<String> args) {
    final path = args.isNotEmpty ? _resolvePath(args[0]) : _currentPath;

    if (path == '/') {
      for (final dir in rootDirs) {
        stdout.writeln('\x1B[34m$dir/\x1B[0m');
      }
    } else if (path == '/relay') {
      final status = _relay.isRunning ? '\x1B[32mRunning\x1B[0m' : '\x1B[33mStopped\x1B[0m';
      stdout.writeln('status      $status');
      stdout.writeln('\x1B[34mconfig/\x1B[0m');
      stdout.writeln('\x1B[34mcache/\x1B[0m');
    } else if (path == '/devices') {
      _listDevices();
    } else if (path == '/chat') {
      for (final room in _relay.chatRooms.values) {
        stdout.writeln('\x1B[34m${room.id}/\x1B[0m  ${room.name}');
      }
    } else if (path.startsWith('/chat/')) {
      final roomId = path.substring('/chat/'.length);
      final room = _relay.chatRooms[roomId];
      if (room != null) {
        stdout.writeln('${room.messages.length} messages');
        stdout.writeln('Last activity: ${room.lastActivity.toLocal()}');
      } else {
        _printError('Room not found');
      }
    } else if (path == '/config') {
      stdout.writeln('relay_config.json');
    } else if (path == '/logs') {
      stdout.writeln('(${_relay.logs.length} log entries)');
    } else if (path == '/ssl') {
      final sslEnabled = _relay.settings.enableSsl ? '\x1B[32mEnabled\x1B[0m' : '\x1B[33mDisabled\x1B[0m';
      final hasCert = _sslManager?.hasCertificate() == true;
      final certStatus = hasCert ? '\x1B[32mInstalled\x1B[0m' : '\x1B[33mNot installed\x1B[0m';
      stdout.writeln('status       $sslEnabled');
      stdout.writeln('certificate  $certStatus');
      stdout.writeln('domain       ${_relay.settings.sslDomain ?? "(not set)"}');
      stdout.writeln('email        ${_relay.settings.sslEmail ?? "(not set)"}');
      stdout.writeln('autorenew    ${_relay.settings.sslAutoRenew ? "on" : "off"}');
    } else if (path == '/games') {
      _listGames();
    } else {
      _printError('Directory not found: $path');
    }
  }

  void _handleCd(List<String> args) {
    if (args.isEmpty) {
      _currentPath = '/';
      _currentChatRoom = null;
      return;
    }

    final target = _resolvePath(args[0]);

    if (target == '/' || rootDirs.contains(target.substring(1).split('/')[0])) {
      _currentPath = target;

      // Check if we're entering a chat room
      if (target.startsWith('/chat/') && target.length > '/chat/'.length) {
        final roomId = target.substring('/chat/'.length).split('/')[0];
        if (_relay.chatRooms.containsKey(roomId)) {
          _currentChatRoom = roomId;
          stdout.writeln('Entered chat room: ${_relay.chatRooms[roomId]!.name}');
          stdout.writeln('Type messages directly, or use /messages, /delmsg commands');
        } else {
          _printError('Room not found: $roomId');
          _currentPath = '/chat';
          _currentChatRoom = null;
        }
      } else {
        _currentChatRoom = null;
      }
    } else {
      _printError('Directory not found: ${args[0]}');
    }
  }

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

  String _formatUptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    if (seconds < 86400) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    return '${days}d ${hours}h';
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  void _printError(String message) {
    stdout.writeln('\x1B[31m$message\x1B[0m');
  }
}

/// Entry point for pure Dart CLI mode
Future<void> runPureCliMode(List<String> args) async {
  final console = PureConsole();
  await console.run(args);
}
