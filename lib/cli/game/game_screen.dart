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
    stdout.writeln('    Press Enter to start...');

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
    stdout.writeln('┌─────────────────────────────────────────────────────────────┐');
    stdout.writeln('│ HP: $hpBar  Gold: $gold  ATK: $atk  DEF: $def  [I]nventory │');
    stdout.writeln('└─────────────────────────────────────────────────────────────┘');
  }

  /// Mini health bar for status display
  String _miniHealthBar(int current, int max) {
    final width = 10;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '█' * percent;
    final empty = '░' * (width - percent);
    return '$filled$empty $current/$max';
  }

  /// Show inventory screen
  Future<void> showInventory(Player player, Map<String, Item> items) async {
    stdout.writeln();
    stdout.writeln('╔════════════════════════════════════════╗');
    stdout.writeln('║            INVENTORY                   ║');
    stdout.writeln('╚════════════════════════════════════════╝');
    stdout.writeln();

    // Show stats
    stdout.writeln('  Stats:');
    stdout.writeln('    Health:     ${player.health}/${player.maxHealth}');
    stdout.writeln('    Attack:     ${player.attack}');
    stdout.writeln('    Defense:    ${player.defense}');
    stdout.writeln('    Gold:       ${player.gold}');
    stdout.writeln();

    // Show inventory items
    stdout.writeln('  Items:');
    if (player.inventory.isEmpty) {
      stdout.writeln('    (empty)');
    } else {
      for (final itemId in player.inventory) {
        final item = items[itemId];
        if (item != null) {
          stdout.writeln('    • ${item.name}');
          if (item.description.isNotEmpty) {
            stdout.writeln('      ${item.description}');
          }
        } else {
          stdout.writeln('    • $itemId');
        }
      }
    }
    stdout.writeln();
    stdout.writeln('  Press Enter to continue...');
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
        stdout.writeln('  $w');
      }
    }
    stdout.writeln();
  }

  /// Get player choice from a list (single keypress)
  Future<Choice?> getChoice(List<Choice> choices) async {
    if (choices.isEmpty) {
      stdout.writeln('  (End of scene)');
      return null;
    }

    stdout.writeln('What do you do?');
    stdout.writeln();

    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      stdout.writeln('  ${i + 1}) ${choice.text}');
    }
    stdout.writeln('  [I] Inventory  [Q] Quit');

    stdout.writeln();
    stdout.write('> ');

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
    stdout.writeln('Invalid. Defaulting to option 1.');
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
          stdout.writeln('Press CTRL+C again within 2 seconds to quit...');
          stdout.write('> ');
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
    stdout.writeln('══════════════════════════════════════════════════════════════');
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
    stdout.writeln('══════════════════════════════════════════════════════════════');
    stdout.writeln();

    await _pause(500);
  }

  /// Show combat status display (stats only, no ASCII art)
  Future<void> showCombatStatus(Player player, Opponent opponent) async {
    stdout.writeln();
    stdout.writeln('────────────────────────────────────────────────────────────────');

    // Show stats side by side
    _showCombatStats(player, opponent);

    stdout.writeln('────────────────────────────────────────────────────────────────');
    stdout.writeln();
  }

  /// Display combat arena with characters facing each other
  /// Both characters are aligned at the bottom (feet on ground)
  void _showCombatArena(List<String> playerArt, List<String> opponentArt) {
    // Calculate max width for each character's art
    int playerWidth = 0;
    int opponentWidth = 0;
    for (final line in playerArt) {
      if (line.length > playerWidth) playerWidth = line.length;
    }
    for (final line in opponentArt) {
      if (line.length > opponentWidth) opponentWidth = line.length;
    }

    // Ensure minimum widths
    const minWidth = 15;
    final leftWidth = playerWidth > minWidth ? playerWidth : minWidth;
    final rightWidth = opponentWidth > minWidth ? opponentWidth : minWidth;

    // Fixed middle section width (must be consistent for all lines!)
    const middleText = '   VS   '; // 8 chars, centered
    const middleWidth = 8;

    // Calculate heights for vertical alignment
    final playerHeight = playerArt.length;
    final opponentHeight = opponentArt.length;
    final maxLines = playerHeight > opponentHeight ? playerHeight : opponentHeight;
    final playerTopPad = maxLines - playerHeight;
    final opponentTopPad = maxLines - opponentHeight;
    final vsLine = maxLines ~/ 2;

    for (var i = 0; i < maxLines; i++) {
      // Get player art line (with top padding for alignment)
      String leftArt;
      final playerLineIndex = i - playerTopPad;
      if (playerLineIndex >= 0 && playerLineIndex < playerArt.length) {
        leftArt = playerArt[playerLineIndex];
      } else {
        leftArt = '';
      }

      // Get opponent art line (with top padding for alignment)
      String rightArt;
      final opponentLineIndex = i - opponentTopPad;
      if (opponentLineIndex >= 0 && opponentLineIndex < opponentArt.length) {
        rightArt = opponentArt[opponentLineIndex];
      } else {
        rightArt = '';
      }

      // Pad to fixed widths (CRITICAL: all lines must have same total width)
      final leftPadded = leftArt.padRight(leftWidth);
      final rightPadded = rightArt.padRight(rightWidth); // padRight, not padLeft

      // Middle section - MUST be same width for all lines
      final middle = (i == vsLine) ? middleText : ' ' * middleWidth;

      stdout.writeln('    $leftPadded$middle$rightPadded');
    }
  }

  /// Show stats for both combatants
  void _showCombatStats(Player player, Opponent opponent) {
    const colWidth = 28;

    // Player stats (left) | Opponent stats (right)
    final playerName = player.name;
    final opponentName = opponent.name;

    // Header with names
    stdout.writeln('    ${playerName.padRight(colWidth)}${opponentName.padLeft(colWidth)}');
    stdout.writeln();

    // Health bars
    final pHealth = _compactHealthBar(player.health, player.maxHealth);
    final oHealth = _compactHealthBar(opponent.health, opponent.maxHealth);
    stdout.writeln('    HP: $pHealth      HP: $oHealth');

    // Stats line
    final pStats = 'ATK: ${player.attack}  DEF: ${player.defense}';
    final oStats = 'ATK: ${opponent.attack}  DEF: ${opponent.defense}';
    stdout.writeln('    $pStats          $oStats');
  }

  /// Compact health bar
  String _compactHealthBar(int current, int max) {
    final width = 15;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '█' * percent;
    final empty = '░' * (width - percent);
    return '$filled$empty $current/$max';
  }

  /// Get combat action from player (single keypress, Attack or Run)
  Future<String?> getCombatAction(List<String> availableActions) async {
    stdout.writeln('Choose your action:');
    stdout.writeln();

    // Fixed combat options: Attack and Run
    stdout.writeln('  1) Attack');
    stdout.writeln('  2) Run away');

    stdout.writeln();
    stdout.write('> ');

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
    stdout.writeln('  $message');
    await _pause(500);
  }

  /// Show victory message
  Future<void> showVictory(String opponentName) async {
    stdout.writeln();
    stdout.writeln('  ╔════════════════════════════════╗');
    stdout.writeln('  ║        VICTORY!                ║');
    stdout.writeln('  ╚════════════════════════════════╝');
    stdout.writeln();
    stdout.writeln('  You defeated $opponentName!');
    stdout.writeln();
    await _pause(1000);
  }

  /// Show defeat message
  Future<void> showDefeat() async {
    stdout.writeln();
    stdout.writeln('  ╔════════════════════════════════╗');
    stdout.writeln('  ║          DEFEAT                ║');
    stdout.writeln('  ╚════════════════════════════════╝');
    stdout.writeln();
    stdout.writeln('  You have been defeated...');
    stdout.writeln();
    await _pause(1000);
  }

  /// Show game over screen
  Future<void> showGameOver() async {
    stdout.writeln();
    stdout.writeln('  ╔════════════════════════════════╗');
    stdout.writeln('  ║         GAME OVER              ║');
    stdout.writeln('  ╚════════════════════════════════╝');
    stdout.writeln();
    await _pause(1500);
  }

  /// Show game completion
  Future<void> showGameComplete(String title) async {
    stdout.writeln();
    stdout.writeln('  ╔════════════════════════════════╗');
    stdout.writeln('  ║      THE END                   ║');
    stdout.writeln('  ╚════════════════════════════════╝');
    stdout.writeln();
    stdout.writeln('  Thanks for playing $title!');
    stdout.writeln();
  }

  /// Show item pickup
  Future<void> showItemPickup(String itemName) async {
    stdout.writeln();
    stdout.writeln('  * You found: $itemName');
    stdout.writeln();
    await _pause(500);
  }

  /// Print error message
  void printError(String message) {
    stdout.writeln('Error: $message');
  }

  /// Print info message
  void printInfo(String message) {
    stdout.writeln(message);
  }

  /// Clear the screen
  void clear() {
    StoryUtils.clearScreen();
  }

  /// Pause for a duration
  Future<void> _pause(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  /// Wait for user to press enter (no-op for Telegram compatibility)
  Future<void> waitForEnter() async {
    // No-op: removed prompt for platforms that don't support empty input
  }
}
