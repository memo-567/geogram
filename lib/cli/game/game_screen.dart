import 'dart:io';

import 'models/player.dart';
import 'models/opponent.dart';
import 'models/choice.dart';
import 'models/item.dart';
import 'story_utils.dart';

/// Console I/O interface for game display
class GameScreen {
  /// Timestamp of last CTRL+C press for double-tap quit
  DateTime? _lastCtrlC;

  /// Track if this is first input read (for buffer cleanup)
  bool _firstRead = true;

  /// Show game intro/title screen
  Future<void> showIntro(String title) async {
    // Drain any buffered input from CLI transition
    _drainBufferedInput();
    _firstRead = false; // Mark as drained so _readSingleKey doesn't drain again

    StoryUtils.clearScreen();
    stdout.writeln();

    // Print title box
    final titleLines = StoryUtils.generateTitleBox(title);
    for (final line in titleLines) {
      stdout.writeln('    $line');
    }

    stdout.writeln();
    stdout.writeln('    \x1B[90mPress Enter to start...\x1B[0m');

    // Use raw mode to wait for Enter specifically
    // This also consumes any buffered garbage bytes
    stdin.echoMode = false;
    stdin.lineMode = false;
    try {
      // Wait for Enter specifically, ignore all other keys
      while (true) {
        final byte = stdin.readByteSync();
        if (byte == -1) continue; // EOF, retry
        if (byte == 13 || byte == 10) break; // CR or LF = Enter
        if (byte == 3) return; // CTRL+C = quit
        // Ignore all other keys - this drains any garbage
      }
    } finally {
      stdin.lineMode = true;
      stdin.echoMode = true;
    }
  }

  /// Show player status bar
  void showStatusBar(Player player, Map<String, Item> items) {
    final hp = player.health;
    final maxHp = player.maxHealth;
    final gold = player.gold;
    final atk = player.attack;
    final def = player.defense;

    // Build compact status line
    final hpBar = _miniHealthBar(hp, maxHp);
    stdout.writeln('\x1B[90m┌─────────────────────────────────────────────────────────────┐\x1B[0m');
    stdout.writeln('\x1B[90m│\x1B[0m HP: $hpBar  \x1B[33mGold: $gold\x1B[0m  ATK: \x1B[31m$atk\x1B[0m  DEF: \x1B[34m$def\x1B[0m  \x1B[36m[I]nventory\x1B[0m \x1B[90m│\x1B[0m');
    stdout.writeln('\x1B[90m└─────────────────────────────────────────────────────────────┘\x1B[0m');
  }

  /// Mini health bar for status display
  String _miniHealthBar(int current, int max) {
    final width = 10;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '█' * percent;
    final empty = '░' * (width - percent);
    final color = percent > 5 ? '\x1B[32m' : (percent > 2 ? '\x1B[33m' : '\x1B[31m');
    return '$color$filled\x1B[90m$empty\x1B[0m $current/$max';
  }

  /// Show inventory screen
  Future<void> showInventory(Player player, Map<String, Item> items) async {
    stdout.writeln();
    stdout.writeln('\x1B[1;36m╔════════════════════════════════════════╗\x1B[0m');
    stdout.writeln('\x1B[1;36m║            INVENTORY                   ║\x1B[0m');
    stdout.writeln('\x1B[1;36m╚════════════════════════════════════════╝\x1B[0m');
    stdout.writeln();

    // Show stats
    stdout.writeln('  \x1B[1mStats:\x1B[0m');
    stdout.writeln('    Health:     \x1B[32m${player.health}/${player.maxHealth}\x1B[0m');
    stdout.writeln('    Attack:     \x1B[31m${player.attack}\x1B[0m');
    stdout.writeln('    Defense:    \x1B[34m${player.defense}\x1B[0m');
    stdout.writeln('    Gold:       \x1B[33m${player.gold}\x1B[0m');
    stdout.writeln();

    // Show inventory items
    stdout.writeln('  \x1B[1mItems:\x1B[0m');
    if (player.inventory.isEmpty) {
      stdout.writeln('    \x1B[90m(empty)\x1B[0m');
    } else {
      for (final itemId in player.inventory) {
        final item = items[itemId];
        if (item != null) {
          stdout.writeln('    • \x1B[36m${item.name}\x1B[0m');
          if (item.description.isNotEmpty) {
            stdout.writeln('      \x1B[90m${item.description}\x1B[0m');
          }
        } else {
          stdout.writeln('    • $itemId');
        }
      }
    }
    stdout.writeln();
    stdout.writeln('  \x1B[90mPress Enter to continue...\x1B[0m');
    stdin.readLineSync();
  }

  /// Print narrative text
  Future<void> printNarrative(String text) async {
    if (text.isEmpty) return;

    stdout.writeln();
    final lines = text.split('\n');
    for (final line in lines) {
      final wrapped = StoryUtils.wrapText(line, 70);
      for (final w in wrapped) {
        stdout.writeln('  \x1B[37m$w\x1B[0m');
      }
    }
    stdout.writeln();
  }

  /// Get player choice from a list (single keypress)
  Future<Choice?> getChoice(List<Choice> choices) async {
    if (choices.isEmpty) {
      stdout.writeln('  \x1B[90m(End of scene)\x1B[0m');
      return null;
    }

    stdout.writeln('\x1B[33mWhat do you do?\x1B[0m');
    stdout.writeln();

    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      stdout.writeln('  \x1B[36m${i + 1})\x1B[0m ${choice.text}');
    }
    stdout.writeln('  \x1B[90m[I] Inventory  [Q] Quit\x1B[0m');

    stdout.writeln();
    stdout.write('\x1B[33m> \x1B[0m');

    final key = _readSingleKey();
    stdout.writeln(key); // Echo the key

    // Check for quit
    if (key.toLowerCase() == 'q') {
      return null;
    }

    // Check for inventory
    if (key.toLowerCase() == 'i') {
      return Choice.inventory();
    }

    final index = int.tryParse(key);
    if (index != null && index >= 1 && index <= choices.length) {
      return choices[index - 1];
    }

    // Invalid input - default to first choice
    stdout.writeln('\x1B[31mInvalid. Defaulting to option 1.\x1B[0m');
    return choices.first;
  }

  /// Drain any buffered input from stdin using async stream with timeout
  void _drainBufferedInput() {
    // Use tcflush to properly flush the terminal input buffer
    try {
      // tcflush TCIFLUSH (0) flushes data received but not read
      // We can use Python to call tcflush since Dart doesn't have direct access
      Process.runSync('python3', [
        '-c',
        'import sys, termios; termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)'
      ]);
    } catch (e) {
      // If Python fails, try alternative: use 'read' with timeout to drain
      try {
        // Use bash read with timeout to drain any buffered input
        Process.runSync('bash', [
          '-c',
          'read -t 0.1 -n 10000 discard 2>/dev/null || true'
        ]);
      } catch (e2) {
        // Ignore - best effort
      }
    }
    // Brief pause to ensure flush completes
    sleep(Duration(milliseconds: 50));
  }

  /// Read a single key without requiring ENTER
  /// Returns 'q' for quit, handles double CTRL+C and arrow key sequences
  String _readSingleKey() {
    stdin.echoMode = false;
    stdin.lineMode = false;
    try {
      // On first read, discard any buffered input from CLI
      if (_firstRead) {
        _firstRead = false;
        // Consume any buffered garbage by reading with timeout
        // Use a brief async check to see if there's immediate data
        _drainBufferedInput();
      }

      var byte = stdin.readByteSync();

      // Keep retrying on EOF - can happen due to terminal state transitions
      while (byte == -1) {
        sleep(Duration(milliseconds: 100));
        byte = stdin.readByteSync();
      }

      // Handle escape sequences (arrow keys, etc.)
      if (byte == 27) { // ESC
        // Check if this is an escape sequence
        // Read with a small timeout to see if more bytes follow
        final nextByte = stdin.readByteSync();
        if (nextByte == 91) { // '[' - this is an escape sequence
          final seqByte = stdin.readByteSync();
          // Arrow keys: A=up, B=down, C=right, D=left
          // Just ignore arrow keys and read again
          return _readSingleKey();
        }
        // Plain ESC key pressed - ignore and read again
        return _readSingleKey();
      }

      // Handle CTRL+C with double-tap requirement
      if (byte == 3) {
        final now = DateTime.now();
        if (_lastCtrlC != null && now.difference(_lastCtrlC!).inMilliseconds < 2000) {
          // Second CTRL+C within 2 seconds - quit
          stdout.writeln();
          return 'q';
        } else {
          // First CTRL+C - warn user
          _lastCtrlC = now;
          stdout.writeln();
          stdout.writeln('\x1B[33mPress CTRL+C again within 2 seconds to quit...\x1B[0m');
          stdout.write('\x1B[33m> \x1B[0m');
          // Continue reading for another key
          return _readSingleKey();
        }
      }

      // Reset CTRL+C timer on any other key
      _lastCtrlC = null;
      return String.fromCharCode(byte);
    } finally {
      stdin.lineMode = true;
      stdin.echoMode = true;
    }
  }

  /// Show combat intro with both characters and ASCII art side by side
  Future<void> showCombatIntro(Player player, Opponent opponent) async {
    stdout.writeln();
    stdout.writeln('\x1B[1;33m══════════════════════════════════════════════════════════════\x1B[0m');
    stdout.writeln();

    // Get combat art for both (use getAsciiArt to get custom art from markdown)
    final playerArt = player.getAsciiArt();
    final opponentArt = opponent.getAsciiArt();

    // Display side by side with VS in the middle
    _showCombatArena(playerArt, opponentArt);

    stdout.writeln();

    // Show stats side by side
    _showCombatStats(player, opponent);

    stdout.writeln();
    stdout.writeln('\x1B[1;33m══════════════════════════════════════════════════════════════\x1B[0m');
    stdout.writeln();

    await _pause(500);
  }

  /// Show combat status display (stats only, no ASCII art)
  Future<void> showCombatStatus(Player player, Opponent opponent) async {
    stdout.writeln();
    stdout.writeln('\x1B[1;33m────────────────────────────────────────────────────────────────\x1B[0m');

    // Show stats side by side
    _showCombatStats(player, opponent);

    stdout.writeln('\x1B[1;33m────────────────────────────────────────────────────────────────\x1B[0m');
    stdout.writeln();
  }

  /// Display combat arena with characters facing each other
  void _showCombatArena(List<String> playerArt, List<String> opponentArt) {
    const artWidth = 15;
    const middleGap = 8;
    final maxLines = playerArt.length > opponentArt.length ? playerArt.length : opponentArt.length;

    // VS marker in the middle
    final vsLine = maxLines ~/ 2;

    for (var i = 0; i < maxLines; i++) {
      final leftArt = i < playerArt.length ? playerArt[i] : '';
      final rightArt = i < opponentArt.length ? opponentArt[i] : '';

      // Pad art to consistent width
      final leftPadded = leftArt.padRight(artWidth);
      final rightPadded = rightArt.padLeft(artWidth);

      // Middle section with VS
      String middle;
      if (i == vsLine) {
        middle = '\x1B[1;31m  VS  \x1B[0m'.padLeft(middleGap + 10).padRight(middleGap + 10);
      } else if (i == vsLine - 1 || i == vsLine + 1) {
        middle = ' ' * middleGap;
      } else {
        middle = ' ' * middleGap;
      }

      stdout.writeln('    \x1B[36m$leftPadded\x1B[0m$middle\x1B[31m$rightPadded\x1B[0m');
    }
  }

  /// Show stats for both combatants
  void _showCombatStats(Player player, Opponent opponent) {
    const colWidth = 28;

    // Player stats (left) | Opponent stats (right)
    final playerName = '\x1B[1;36m${player.name}\x1B[0m';
    final opponentName = '\x1B[1;31m${opponent.name}\x1B[0m';

    // Header with names
    stdout.writeln('    ${playerName.padRight(colWidth + 10)}${opponentName.padLeft(colWidth)}');
    stdout.writeln();

    // Health bars
    final pHealth = _compactHealthBar(player.health, player.maxHealth, '\x1B[32m');
    final oHealth = _compactHealthBar(opponent.health, opponent.maxHealth, '\x1B[31m');
    stdout.writeln('    HP: $pHealth      HP: $oHealth');

    // Stats line
    final pStats = 'ATK: \x1B[33m${player.attack}\x1B[0m  DEF: \x1B[34m${player.defense}\x1B[0m';
    final oStats = 'ATK: \x1B[33m${opponent.attack}\x1B[0m  DEF: \x1B[34m${opponent.defense}\x1B[0m';
    stdout.writeln('    $pStats          $oStats');
  }

  /// Compact health bar with color
  String _compactHealthBar(int current, int max, String color) {
    final width = 15;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '█' * percent;
    final empty = '░' * (width - percent);
    return '$color$filled\x1B[90m$empty\x1B[0m $current/$max';
  }

  /// Get combat action from player (single keypress, Attack or Run)
  Future<String?> getCombatAction(List<String> availableActions) async {
    stdout.writeln('\x1B[33mChoose your action:\x1B[0m');
    stdout.writeln();

    // Fixed combat options: Attack and Run
    stdout.writeln('  \x1B[36m1)\x1B[0m Attack');
    stdout.writeln('  \x1B[36m2)\x1B[0m Run away');

    stdout.writeln();
    stdout.write('\x1B[33m> \x1B[0m');

    final key = _readSingleKey();
    stdout.writeln(key); // Echo the key

    if (key == '2' || key.toLowerCase() == 'r') {
      return 'run'; // Special: flee combat
    }

    if (key.toLowerCase() == 'q') {
      return null; // Quit
    }

    // Default to attack
    return 'attack';
  }

  /// Show combat result message
  Future<void> showCombatMessage(String message) async {
    stdout.writeln();
    stdout.writeln('  \x1B[1m$message\x1B[0m');
    await _pause(500);
  }

  /// Show victory message
  Future<void> showVictory(String opponentName) async {
    stdout.writeln();
    stdout.writeln('  \x1B[32m╔════════════════════════════════╗\x1B[0m');
    stdout.writeln('  \x1B[32m║        VICTORY!                ║\x1B[0m');
    stdout.writeln('  \x1B[32m╚════════════════════════════════╝\x1B[0m');
    stdout.writeln();
    stdout.writeln('  \x1B[32mYou defeated $opponentName!\x1B[0m');
    stdout.writeln();
    await _pause(1000);
  }

  /// Show defeat message
  Future<void> showDefeat() async {
    stdout.writeln();
    stdout.writeln('  \x1B[31m╔════════════════════════════════╗\x1B[0m');
    stdout.writeln('  \x1B[31m║          DEFEAT                ║\x1B[0m');
    stdout.writeln('  \x1B[31m╚════════════════════════════════╝\x1B[0m');
    stdout.writeln();
    stdout.writeln('  \x1B[31mYou have been defeated...\x1B[0m');
    stdout.writeln();
    await _pause(1000);
  }

  /// Show game over screen
  Future<void> showGameOver() async {
    stdout.writeln();
    stdout.writeln('  \x1B[31m╔════════════════════════════════╗\x1B[0m');
    stdout.writeln('  \x1B[31m║         GAME OVER              ║\x1B[0m');
    stdout.writeln('  \x1B[31m╚════════════════════════════════╝\x1B[0m');
    stdout.writeln();
    await _pause(1500);
  }

  /// Show game completion
  Future<void> showGameComplete(String title) async {
    stdout.writeln();
    stdout.writeln('  \x1B[33m╔════════════════════════════════╗\x1B[0m');
    stdout.writeln('  \x1B[33m║      THE END                   ║\x1B[0m');
    stdout.writeln('  \x1B[33m╚════════════════════════════════╝\x1B[0m');
    stdout.writeln();
    stdout.writeln('  \x1B[33mThanks for playing $title!\x1B[0m');
    stdout.writeln();
  }

  /// Show item pickup
  Future<void> showItemPickup(String itemName) async {
    stdout.writeln();
    stdout.writeln('  \x1B[32m★ You found: $itemName\x1B[0m');
    stdout.writeln();
    await _pause(500);
  }

  /// Print error message
  void printError(String message) {
    stdout.writeln('\x1B[31mError: $message\x1B[0m');
  }

  /// Print info message
  void printInfo(String message) {
    stdout.writeln('\x1B[36m$message\x1B[0m');
  }

  /// Clear the screen
  void clear() {
    StoryUtils.clearScreen();
  }

  /// Pause for a duration
  Future<void> _pause(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  /// Wait for user to press enter
  Future<void> waitForEnter() async {
    stdout.writeln('  \x1B[90mPress Enter to continue...\x1B[0m');
    stdin.readLineSync();
  }
}
