import 'game_thing.dart';

/// Enemy/opponent entity
class Opponent extends GameThing {
  final String? asciiArt;
  final List<String> actions;

  Opponent({
    required super.id,
    required super.name,
    super.description,
    int health = 50,
    int attack = 10,
    int defense = 5,
    this.asciiArt,
    List<String>? actions,
  }) : actions = actions ?? ['attack'] {
    attributes['Health'] = health;
    attributes['MaxHealth'] = health;
    attributes['Attack'] = attack;
    attributes['Defense'] = defense;
  }

  int get health => attributes['Health'] ?? 50;
  set health(int value) => attributes['Health'] = value;

  int get maxHealth => attributes['MaxHealth'] ?? 50;

  int get attack => attributes['Attack'] ?? 10;
  set attack(int value) => attributes['Attack'] = value;

  int get defense => attributes['Defense'] ?? 5;
  set defense(int value) => attributes['Defense'] = value;

  /// Create a fresh instance for combat (preserves original stats)
  Opponent createInstance() {
    final instance = Opponent(
      id: id,
      name: name,
      description: description,
      health: attributes['MaxHealth'] ?? 50,
      attack: attack,
      defense: defense,
      asciiArt: asciiArt,
      actions: List<String>.from(actions),
    );
    // Copy all attributes
    for (final entry in attributes.entries) {
      if (entry.key != 'Health') {
        instance.attributes[entry.key] = entry.value;
      }
    }
    return instance;
  }

  @override
  List<String> getAsciiArt() {
    if (asciiArt != null) {
      return asciiArt!.split('\n');
    }
    // Return detailed art based on opponent name
    return getCombatArt();
  }

  /// Get detailed combat ASCII art (facing left <-)
  List<String> getCombatArt() {
    final lowerName = name.toLowerCase();

    // Ogre/troll type
    if (lowerName.contains('ogre') || lowerName.contains('troll')) {
      return [
        '     ,---.     ',
        '    / o o \\    ',
        '   |   __  |   ',
        '   |  /  \\ |   ',
        '  <[##|  |##]  ',
        '    |_|  |_|   ',
      ];
    }

    // Guard/soldier type
    if (lowerName.contains('guard') || lowerName.contains('soldier') || lowerName.contains('knight')) {
      return [
        '      ,O,      ',
        '     |##|\\     ',
        '    / || \\_    ',
        '   <[==]  |   ',
        '     /  \\      ',
        '    _|  |_     ',
      ];
    }

    // Dragon type
    if (lowerName.contains('dragon')) {
      return [
        '      __/\\/\\   ',
        '     <  o  )   ',
        '      \\___/|   ',
        '     /|   ||   ',
        '    < |___||   ',
        '      |    \\   ',
      ];
    }

    // Skeleton/undead type
    if (lowerName.contains('skeleton') || lowerName.contains('undead') || lowerName.contains('zombie')) {
      return [
        '      .-.      ',
        '     (o o)     ',
        '      | |      ',
        '   <--|X|--    ',
        '      | |      ',
        '     _| |_     ',
      ];
    }

    // Wolf/beast type
    if (lowerName.contains('wolf') || lowerName.contains('beast') || lowerName.contains('bear')) {
      return [
        '     /\\_/\\     ',
        '    ( o.o )    ',
        '     > ^ <     ',
        '    /|   |\\    ',
        '   (_|   |_)   ',
        '              ',
      ];
    }

    // Goblin/small creature
    if (lowerName.contains('goblin') || lowerName.contains('imp')) {
      return [
        '      /\\       ',
        '     (oo)      ',
        '    <(  )>     ',
        '      ||       ',
        '     _||_      ',
        '              ',
      ];
    }

    // Default enemy (facing left)
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'E';
    return [
      '      ___      ',
      '     / $letter \\     ',
      '    |  _  |    ',
      '   <| | | |    ',
      '     |   |     ',
      '    _|   |_    ',
    ];
  }
}
