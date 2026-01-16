/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * GameScreen adapter for ConsoleIO - enables games in Flutter UI.
 * Uses line-based input instead of raw terminal mode.
 */

import '../console_io.dart';
import 'models/player.dart';
import 'models/opponent.dart';
import 'models/choice.dart';
import 'models/item.dart';
import 'story_utils.dart';

/// Game screen that uses ConsoleIO for platform-agnostic I/O.
///
/// Unlike the CLI GameScreen which uses raw terminal mode for single-key input,
/// this version uses line-based input (type + Enter) making it suitable for
/// Flutter UI and other non-terminal platforms.
class GameScreenIO {
  final ConsoleIO io;

  /// Callback to read a line of input (set by game runner)
  Future<String?> Function()? onReadLine;

  GameScreenIO(this.io);

  /// Show game intro/title screen
  Future<void> showIntro(String title) async {
    io.clear();
    io.writeln();

    // Print title box
    final titleLines = StoryUtils.generateTitleBox(title);
    for (final line in titleLines) {
      io.writeln('    $line');
    }

    io.writeln();
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
    io.writeln('+---------------------------------------------------------+');
    io.writeln('| HP: $hpBar  Gold: $gold  ATK: $atk  DEF: $def  [I]nventory |');
    io.writeln('+---------------------------------------------------------+');
  }

  /// Mini health bar for status display
  String _miniHealthBar(int current, int max) {
    final width = 10;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '#' * percent;
    final empty = '-' * (width - percent);
    return '[$filled$empty] $current/$max';
  }

  /// Show inventory screen
  Future<void> showInventory(Player player, Map<String, Item> items) async {
    io.writeln();
    io.writeln('+========================================+');
    io.writeln('|            INVENTORY                   |');
    io.writeln('+========================================+');
    io.writeln();

    // Show stats
    io.writeln('  Stats:');
    io.writeln('    Health:     ${player.health}/${player.maxHealth}');
    io.writeln('    Attack:     ${player.attack}');
    io.writeln('    Defense:    ${player.defense}');
    io.writeln('    Gold:       ${player.gold}');
    io.writeln();

    // Show inventory items
    io.writeln('  Items:');
    if (player.inventory.isEmpty) {
      io.writeln('    (empty)');
    } else {
      for (final itemId in player.inventory) {
        final item = items[itemId];
        if (item != null) {
          io.writeln('    * ${item.name}');
          if (item.description.isNotEmpty) {
            io.writeln('      ${item.description}');
          }
        } else {
          io.writeln('    * $itemId');
        }
      }
    }
    io.writeln();
  }

  /// Print narrative text
  Future<void> printNarrative(String text) async {
    if (text.isEmpty) return;

    io.writeln();
    final lines = text.split('\n');
    for (final line in lines) {
      final wrapped = StoryUtils.wrapText(line, 70);
      for (final w in wrapped) {
        io.writeln('  $w');
      }
    }
    io.writeln();
  }

  /// Get player choice from a list
  Future<Choice?> getChoice(List<Choice> choices) async {
    if (choices.isEmpty) {
      io.writeln('  (End of scene)');
      return null;
    }

    io.writeln('What do you do?');
    io.writeln();

    for (var i = 0; i < choices.length; i++) {
      final choice = choices[i];
      io.writeln('  ${i + 1}) ${choice.text}');
    }
    io.writeln('  [I] Inventory  [Q] Quit');

    io.writeln();
    io.write('> ');

    final input = await _readLine();
    if (input == null || input.isEmpty) {
      return choices.first;
    }

    final key = input.trim().toLowerCase();

    // Check for quit
    if (key == 'q' || key == 'quit') {
      return null;
    }

    // Check for inventory
    if (key == 'i' || key == 'inventory') {
      return Choice.inventory();
    }

    final index = int.tryParse(key);
    if (index != null && index >= 1 && index <= choices.length) {
      return choices[index - 1];
    }

    // Invalid input - default to first choice
    io.writeln('Invalid. Defaulting to option 1.');
    return choices.first;
  }

  /// Show combat intro with both characters
  Future<void> showCombatIntro(Player player, Opponent opponent) async {
    io.writeln();
    io.writeln('==============================================================');
    io.writeln();

    // Get combat art for both
    final playerArt = player.getAsciiArt();
    final opponentArt = opponent.getAsciiArt();

    // Display side by side
    _showCombatArena(playerArt, opponentArt);

    io.writeln();

    // Show stats side by side
    _showCombatStats(player, opponent);

    io.writeln();
    io.writeln('==============================================================');
    io.writeln();

    await _pause(500);
  }

  /// Show combat status display (stats only)
  Future<void> showCombatStatus(Player player, Opponent opponent) async {
    io.writeln();
    io.writeln('--------------------------------------------------------------');
    _showCombatStats(player, opponent);
    io.writeln('--------------------------------------------------------------');
    io.writeln();
  }

  /// Display combat arena with characters facing each other
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

    // Debug: verify calculations
    // Total line width = 4 (indent) + leftWidth + middleWidth + rightWidth
    // io.writeln('DEBUG: leftWidth=$leftWidth, middleWidth=$middleWidth, rightWidth=$rightWidth');

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

      io.writeln('    $leftPadded$middle$rightPadded');
    }
  }

  /// Show stats for both combatants
  void _showCombatStats(Player player, Opponent opponent) {
    io.writeln('    ${player.name.padRight(28)}${opponent.name.padLeft(28)}');
    io.writeln();

    final pHealth = _compactHealthBar(player.health, player.maxHealth);
    final oHealth = _compactHealthBar(opponent.health, opponent.maxHealth);
    io.writeln('    HP: $pHealth      HP: $oHealth');

    final pStats = 'ATK: ${player.attack}  DEF: ${player.defense}';
    final oStats = 'ATK: ${opponent.attack}  DEF: ${opponent.defense}';
    io.writeln('    $pStats          $oStats');
  }

  /// Compact health bar
  String _compactHealthBar(int current, int max) {
    final width = 15;
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '#' * percent;
    final empty = '-' * (width - percent);
    return '[$filled$empty] $current/$max';
  }

  /// Get combat action from player
  Future<String?> getCombatAction(List<String> availableActions) async {
    io.writeln('Choose your action:');
    io.writeln();
    io.writeln('  1) Attack');
    io.writeln('  2) Run away');

    io.writeln();
    io.write('> ');

    final input = await _readLine();
    if (input == null || input.isEmpty) {
      return 'attack';
    }

    final key = input.trim().toLowerCase();

    if (key == '2' || key == 'r' || key == 'run') {
      return 'run';
    }

    if (key == 'q' || key == 'quit') {
      return null;
    }

    return 'attack';
  }

  /// Show combat result message
  Future<void> showCombatMessage(String message) async {
    io.writeln();
    io.writeln('  $message');
    await _pause(500);
  }

  /// Show victory message
  Future<void> showVictory(String opponentName) async {
    io.writeln();
    io.writeln('  +================================+');
    io.writeln('  |        VICTORY!                |');
    io.writeln('  +================================+');
    io.writeln();
    io.writeln('  You defeated $opponentName!');
    io.writeln();
    await _pause(1000);
  }

  /// Show defeat message
  Future<void> showDefeat() async {
    io.writeln();
    io.writeln('  +================================+');
    io.writeln('  |          DEFEAT                |');
    io.writeln('  +================================+');
    io.writeln();
    io.writeln('  You have been defeated...');
    io.writeln();
    await _pause(1000);
  }

  /// Show game over screen
  Future<void> showGameOver() async {
    io.writeln();
    io.writeln('  +================================+');
    io.writeln('  |         GAME OVER              |');
    io.writeln('  +================================+');
    io.writeln();
    await _pause(1500);
  }

  /// Show game completion
  Future<void> showGameComplete(String title) async {
    io.writeln();
    io.writeln('  +================================+');
    io.writeln('  |      THE END                   |');
    io.writeln('  +================================+');
    io.writeln();
    io.writeln('  Thanks for playing $title!');
    io.writeln();
  }

  /// Show item pickup
  Future<void> showItemPickup(String itemName) async {
    io.writeln();
    io.writeln('  * You found: $itemName');
    io.writeln();
    await _pause(500);
  }

  /// Print error message
  void printError(String message) {
    io.writeln('Error: $message');
  }

  /// Print info message
  void printInfo(String message) {
    io.writeln(message);
  }

  /// Clear the screen
  void clear() {
    io.clear();
  }

  /// Pause for a duration
  Future<void> _pause(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  /// Wait for user to press enter (no-op for Telegram compatibility)
  Future<void> waitForEnter() async {
    // No-op: removed prompt for platforms that don't support empty input
  }

  /// Read a line of input
  Future<String?> _readLine() async {
    if (onReadLine != null) {
      return await onReadLine!();
    }
    return await io.readLine();
  }
}
