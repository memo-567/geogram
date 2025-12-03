import 'player.dart';
import 'opponent.dart';
import 'item.dart';
import 'scene.dart';
import 'action.dart';

/// Main game container
class Game {
  String title;
  String description;
  final String startScene;
  final Map<String, Scene> scenes;
  final Map<String, GameAction> actions;
  final Map<String, Item> items;
  final Map<String, Opponent> opponents;
  final Player player;

  Game({
    this.title = 'Untitled Game',
    this.description = '',
    required this.startScene,
    required this.scenes,
    required this.actions,
    required this.items,
    required this.opponents,
    required this.player,
  }) {
    // Add default actions if not present
    if (!actions.containsKey('attack')) {
      actions['attack'] = GameAction.defaultAttack();
    }
    if (!actions.containsKey('defend')) {
      actions['defend'] = GameAction.defaultDefend();
    }
  }

  /// Get scene by ID
  Scene? getScene(String id) => scenes[id];

  /// Get action by ID
  GameAction? getAction(String id) => actions[id];

  /// Get item by ID
  Item? getItem(String id) => items[id];

  /// Get opponent by ID
  Opponent? getOpponent(String id) => opponents[id];

  /// Get game statistics
  Map<String, int> get stats => {
        'scenes': scenes.length,
        'actions': actions.length,
        'items': items.length,
        'opponents': opponents.length,
      };
}
