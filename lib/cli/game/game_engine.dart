import 'dart:math';

import 'models/game.dart';
import 'models/scene.dart';
import 'models/choice.dart';
import 'models/random_event.dart';
import 'game_screen.dart';
import 'js_runtime.dart';

/// Main game loop controller
class GameEngine {
  final Game game;
  final GameScreen screen;
  final JsRuntime jsRuntime;

  String _currentSceneId;
  bool _running = false;
  final Random _random = Random();

  GameEngine({
    required this.game,
    required this.screen,
  })  : jsRuntime = JsRuntime(),
        _currentSceneId = game.startScene;

  /// Run the game loop
  Future<void> run() async {
    _running = true;
    _currentSceneId = game.startScene;

    // Show intro
    await screen.showIntro(game.title);

    // Main game loop
    while (_running) {
      final scene = game.scenes[_currentSceneId];
      if (scene == null) {
        screen.printError('Scene not found: $_currentSceneId');
        break;
      }

      await _playScene(scene);

      // Check if scene is an end scene
      if (scene.isEndScene) {
        await screen.showGameComplete(game.title);
        break;
      }
    }
  }

  /// Stop the game
  void stop() {
    _running = false;
  }

  /// Play a single scene
  Future<void> _playScene(Scene scene) async {
    // Show status bar
    screen.showStatusBar(game.player, game.items);

    // Print scene description
    await screen.printNarrative(scene.description);

    // Check for random events first
    if (scene.randomEvents.isNotEmpty) {
      final event = _rollRandomEvent(scene.randomEvents);
      if (event != null) {
        await screen.printNarrative(event.text);
        _currentSceneId = event.targetScene;
        return;
      }
    }

    // If no choices, this is an end scene
    if (scene.choices.isEmpty) {
      return;
    }

    // Get player choice (loop for inventory)
    while (true) {
      final choice = await screen.getChoice(scene.choices);
      if (choice == null) {
        // Player quit
        _running = false;
        return;
      }

      // Handle inventory request
      if (choice.linkType == LinkType.inventory) {
        await screen.showInventory(game.player, game.items);
        screen.showStatusBar(game.player, game.items);
        continue; // Show choices again
      }

      // Process the choice
      await _processChoice(choice);
      break;
    }
  }

  /// Roll for a random event
  RandomEvent? _rollRandomEvent(List<RandomEvent> events) {
    final roll = _random.nextInt(100) + 1;
    var cumulative = 0;

    for (final event in events) {
      cumulative += event.probability;
      if (roll <= cumulative) {
        return event;
      }
    }

    return null;
  }

  /// Process a player choice
  Future<void> _processChoice(Choice choice) async {
    switch (choice.linkType) {
      case LinkType.scene:
        _currentSceneId = choice.targetId;
        break;

      case LinkType.item:
        await _handleItemPickup(choice);
        break;

      case LinkType.opponent:
        await _handleCombat(choice);
        break;

      case LinkType.action:
        // Direct action execution (rare)
        _currentSceneId = choice.targetId;
        break;

      case LinkType.leave:
        _running = false;
        break;

      case LinkType.inventory:
        // Handled earlier in the loop, should not reach here
        break;
    }
  }

  /// Handle item pickup
  Future<void> _handleItemPickup(Choice choice) async {
    final item = game.items[choice.targetId];
    if (item == null) {
      screen.printError('Item not found: ${choice.targetId}');
      return;
    }

    // Add item to player inventory
    game.player.addItem(item.id);

    // Apply item modifiers
    game.player.applyItemModifiers(item.modifiers);

    // Show pickup message
    await screen.showItemPickup(item.name);

    // Navigate to win scene if specified, otherwise stay
    if (choice.winScene != null) {
      _currentSceneId = choice.winScene!;
    }
  }

  /// Handle combat encounter
  Future<void> _handleCombat(Choice choice) async {
    final opponent = game.opponents[choice.opponentId ?? choice.targetId];
    if (opponent == null) {
      screen.printError('Opponent not found: ${choice.opponentId ?? choice.targetId}');
      _currentSceneId = choice.loseScene ?? _currentSceneId;
      return;
    }

    // Create opponent instance for this fight
    final opponentInstance = opponent.createInstance();

    // Get available actions from opponent (what the player can do against this opponent)
    final availableActions = opponentInstance.actions
        .where((actionId) => game.actions.containsKey(actionId))
        .toList();

    if (availableActions.isEmpty) {
      screen.printError('No valid actions available for this opponent');
      _currentSceneId = choice.loseScene ?? _currentSceneId;
      return;
    }

    // Show combat intro (first time with ASCII art)
    await screen.showCombatIntro(game.player, opponentInstance);

    // Combat loop
    var firstTurn = false; // Already showed intro
    while (true) {
      // Show combat status (stats only on subsequent turns)
      if (firstTurn) {
        await screen.showCombatIntro(game.player, opponentInstance);
        firstTurn = false;
      } else {
        await screen.showCombatStatus(game.player, opponentInstance);
      }

      // Get player action (Attack or Run)
      final playerAction = await screen.getCombatAction(availableActions);

      if (playerAction == null) {
        // Player quit
        _running = false;
        return;
      }

      // Handle run away
      if (playerAction == 'run') {
        await screen.showCombatMessage('You flee from the battle!');
        _currentSceneId = choice.loseScene ?? _currentSceneId;
        return;
      }

      // Get selected action
      final selectedAction = game.actions[playerAction];
      if (selectedAction == null) {
        screen.printError('Action not found: $playerAction');
        continue;
      }

      // Show action description
      await screen.showCombatMessage(selectedAction.description);

      // Execute action script
      final result = jsRuntime.execute(
        selectedAction.script,
        entityA: game.player.toMap(),
        entityB: opponentInstance.toMap(),
      );

      // Update entities from result
      game.player.fromMap(result['A'] as Map<String, dynamic>);
      opponentInstance.fromMap(result['B'] as Map<String, dynamic>);

      final output = result['output'] as String;

      // Show result message
      await screen.showCombatMessage('Result: $output');

      // Check result
      if (output == 'win') {
        await screen.showVictory(opponentInstance.name);

        // Award items
        if (choice.winItems != null) {
          for (final itemId in choice.winItems!) {
            final item = game.items[itemId];
            if (item != null) {
              game.player.addItem(item.id);
              game.player.applyItemModifiers(item.modifiers);
              await screen.showItemPickup(item.name);
            }
          }
        }

        _currentSceneId = choice.winScene ?? _currentSceneId;
        return;
      } else if (output == 'lose') {
        await screen.showDefeat();

        // Check if player is dead
        if (game.player.health <= 0) {
          await screen.showGameOver();
          _running = false;
          return;
        }

        _currentSceneId = choice.loseScene ?? 'game-over';
        return;
      }

      // Combat continues
      await _pause(500);
    }
  }

  /// Get combat message based on result
  String _getCombatMessage(String result, String opponentName) {
    switch (result) {
      case 'win':
        return 'You defeated $opponentName!';
      case 'lose':
        return 'You were defeated by $opponentName...';
      default:
        return 'The battle continues...';
    }
  }

  /// Pause for milliseconds
  Future<void> _pause(int ms) async {
    await Future.delayed(Duration(milliseconds: ms));
  }
}
