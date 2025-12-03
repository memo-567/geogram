import 'game_thing.dart';

/// Player entity with stats and inventory
class Player extends GameThing {
  final List<String> inventory = [];
  final String? asciiArt;

  Player({
    required super.id,
    required super.name,
    super.description,
    int health = 100,
    int maxHealth = 100,
    int attack = 10,
    int defense = 5,
    int gold = 0,
    int experience = 0,
    this.asciiArt,
  }) {
    attributes['Health'] = health;
    attributes['MaxHealth'] = maxHealth;
    attributes['Attack'] = attack;
    attributes['Defense'] = defense;
    attributes['Gold'] = gold;
    attributes['Experience'] = experience;
  }

  /// Create default player
  factory Player.defaultPlayer() {
    return Player(
      id: 'player',
      name: 'Player',
      description: 'The player character',
    );
  }

  int get health => attributes['Health'] ?? 100;
  set health(int value) => attributes['Health'] = value;

  int get maxHealth => attributes['MaxHealth'] ?? 100;
  set maxHealth(int value) => attributes['MaxHealth'] = value;

  int get attack => attributes['Attack'] ?? 10;
  set attack(int value) => attributes['Attack'] = value;

  int get defense => attributes['Defense'] ?? 5;
  set defense(int value) => attributes['Defense'] = value;

  int get gold => attributes['Gold'] ?? 0;
  set gold(int value) => attributes['Gold'] = value;

  /// Add item to inventory
  void addItem(String itemId) {
    inventory.add(itemId);
  }

  /// Remove item from inventory
  bool removeItem(String itemId) {
    return inventory.remove(itemId);
  }

  /// Check if player has item
  bool hasItem(String itemId) {
    return inventory.contains(itemId);
  }

  /// Apply item modifiers
  void applyItemModifiers(Map<String, int> modifiers) {
    for (final entry in modifiers.entries) {
      final current = attributes[entry.key] ?? 0;
      attributes[entry.key] = current + entry.value;
    }
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map['inventory'] = inventory;
    return map;
  }

  @override
  List<String> getAsciiArt() {
    if (asciiArt != null) {
      return asciiArt!.split('\n');
    }
    // Default knight/warrior facing right ->
    return [
      '    O    ',
      '   /|\\>  ',
      '   / \\   ',
    ];
  }

  /// Get detailed ASCII art for combat (facing right)
  List<String> getCombatArt() {
    if (asciiArt != null) {
      return asciiArt!.split('\n');
    }
    // Default knight combat art
    return [
      '      ,O,      ',
      '     /|##|     ',
      '    _/ || \\    ',
      '   |  [==]>   ',
      '      /  \\     ',
      '     _|  |_    ',
    ];
  }
}
