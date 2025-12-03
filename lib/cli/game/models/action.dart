/// Combat action with JavaScript script
class GameAction {
  final String id;
  final String name;
  final String description;
  final String script;

  GameAction({
    required this.id,
    required this.name,
    this.description = '',
    required this.script,
  });

  /// Default attack action
  factory GameAction.defaultAttack() {
    return GameAction(
      id: 'attack',
      name: 'Attack',
      description: 'You attack the enemy!',
      script: '''
var damage = Math.max(1, A['Attack'] - B['Defense']);
B['Health'] = B['Health'] - damage;
if (B['Health'] <= 0) {
  output = 'win';
} else {
  output = 'continue';
}
''',
    );
  }

  /// Default defend action
  factory GameAction.defaultDefend() {
    return GameAction(
      id: 'defend',
      name: 'Defend',
      description: 'You brace for the enemy attack!',
      script: '''
var reducedDamage = Math.max(1, (B['Attack'] - A['Defense'] * 2) / 2);
A['Health'] = A['Health'] - Math.floor(reducedDamage);
if (A['Health'] <= 0) {
  output = 'lose';
} else {
  output = 'continue';
}
''',
    );
  }
}
