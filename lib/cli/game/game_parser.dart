import 'models/game.dart';
import 'models/player.dart';
import 'models/opponent.dart';
import 'models/item.dart';
import 'models/scene.dart';
import 'models/action.dart';
import 'models/choice.dart';
import 'models/random_event.dart';

/// Parses markdown game scripts into game objects
class GameParser {
  /// Parse markdown content into a Game object
  Game parse(String content) {
    final blocks = _getTextBlocks(content);

    final scenes = <String, Scene>{};
    final actions = <String, GameAction>{};
    final items = <String, Item>{};
    final opponents = <String, Opponent>{};
    Player? player;
    String? title;
    String? description;
    String? startScene;

    for (final block in blocks) {
      final trimmedBlock = block.trim();

      if (trimmedBlock.startsWith('# Scene:')) {
        final scene = _parseScene(trimmedBlock);
        scenes[scene.id] = scene;
        startScene ??= scene.id;
      } else if (trimmedBlock.startsWith('# Action:')) {
        final action = _parseAction(trimmedBlock);
        actions[action.id] = action;
      } else if (trimmedBlock.startsWith('# Item:')) {
        final item = _parseItem(trimmedBlock);
        items[item.id] = item;
      } else if (trimmedBlock.startsWith('# Opponent:')) {
        final opponent = _parseOpponent(trimmedBlock);
        opponents[opponent.id] = opponent;
      } else if (trimmedBlock.startsWith('# Player')) {
        player = _parsePlayer(trimmedBlock);
      } else if (trimmedBlock.startsWith('# Title:')) {
        title = _parseTitle(trimmedBlock);
      } else if (trimmedBlock.startsWith('# Description:')) {
        description = _parseDescription(trimmedBlock);
      }
    }

    return Game(
      title: title ?? 'Untitled Game',
      description: description ?? '',
      startScene: startScene ?? 'start',
      scenes: scenes,
      actions: actions,
      items: items,
      opponents: opponents,
      player: player ?? Player.defaultPlayer(),
    );
  }

  /// Split content into blocks by top-level headers
  List<String> _getTextBlocks(String content) {
    // Split by lines starting with "# "
    final blocks = <String>[];
    final lines = content.split('\n');
    var currentBlock = StringBuffer();

    for (final line in lines) {
      if (line.startsWith('# ') && currentBlock.isNotEmpty) {
        blocks.add(currentBlock.toString());
        currentBlock = StringBuffer();
      }
      currentBlock.writeln(line);
    }

    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock.toString());
    }

    return blocks;
  }

  /// Parse a scene block
  Scene _parseScene(String block) {
    final lines = block.split('\n');
    final headerLine = lines.first;

    // Extract scene name and ID
    final name = headerLine.substring('# Scene:'.length).trim();
    final id = _normalizeId(name);

    // Extract description (lines starting with >)
    final descLines = lines.where((l) => l.startsWith('>')).map((l) => l.substring(1).trim()).toList();
    final description = descLines.join('\n');

    // Parse choices
    final choices = <Choice>[];
    var inChoiceSection = false;
    for (final line in lines) {
      if (line.startsWith('## Choice:')) {
        inChoiceSection = true;
        continue;
      }
      if (line.startsWith('## ')) {
        inChoiceSection = false;
      }
      if (inChoiceSection && line.trim().startsWith('-')) {
        choices.add(Choice.parse(line));
      }
    }

    // Parse random events
    final randomEvents = <RandomEvent>[];
    var inRandomSection = false;
    for (final line in lines) {
      if (line.startsWith('## Random:')) {
        inRandomSection = true;
        continue;
      }
      if (line.startsWith('## ')) {
        inRandomSection = false;
      }
      if (inRandomSection && line.trim().startsWith('-')) {
        randomEvents.add(RandomEvent.parse(line));
      }
    }

    return Scene(
      id: id,
      name: name,
      description: description,
      choices: choices,
      randomEvents: randomEvents,
    );
  }

  /// Parse an action block
  GameAction _parseAction(String block) {
    final lines = block.split('\n');
    final headerLine = lines.first;

    // Extract action name and ID
    final name = headerLine.substring('# Action:'.length).trim();
    final id = _normalizeId(name);

    // Extract description
    final descLines = lines.where((l) => l.startsWith('>')).map((l) => l.substring(1).trim()).toList();
    final description = descLines.join('\n');

    // Extract JavaScript code block
    var script = '';
    var inCodeBlock = false;
    final scriptLines = <String>[];

    for (final line in lines) {
      if (line.trim().startsWith('```javascript') || line.trim().startsWith('```js')) {
        inCodeBlock = true;
        continue;
      }
      if (line.trim() == '```' && inCodeBlock) {
        inCodeBlock = false;
        continue;
      }
      if (inCodeBlock) {
        scriptLines.add(line);
      }
    }

    script = scriptLines.join('\n');

    return GameAction(
      id: id,
      name: name,
      description: description,
      script: script,
    );
  }

  /// Parse an item block
  Item _parseItem(String block) {
    final lines = block.split('\n');
    final headerLine = lines.first;

    // Extract item name and ID
    final name = headerLine.substring('# Item:'.length).trim();
    final id = _normalizeId(name);

    // Parse attributes
    String description = '';
    String type = 'misc';
    bool consumable = false;
    final modifiers = <String, int>{};

    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('-')) {
        final content = trimmed.substring(1).trim();
        final colonIndex = content.indexOf(':');
        if (colonIndex != -1) {
          final key = content.substring(0, colonIndex).trim();
          final value = content.substring(colonIndex + 1).trim();

          switch (key.toLowerCase()) {
            case 'description':
              description = value;
              break;
            case 'type':
              type = value.toLowerCase();
              break;
            case 'consumable':
              consumable = value.toLowerCase() == 'true' || value == '1';
              break;
            default:
              // Parse as modifier
              modifiers[key] = Item.parseModifier(value);
          }
        }
      }
    }

    return Item(
      id: id,
      name: name,
      description: description,
      type: type,
      consumable: consumable,
      modifiers: modifiers,
    );
  }

  /// Parse an opponent block
  Opponent _parseOpponent(String block) {
    final lines = block.split('\n');
    final headerLine = lines.first;

    // Extract opponent name and ID
    final name = headerLine.substring('# Opponent:'.length).trim();
    final id = _normalizeId(name);

    // Parse attributes
    String description = '';
    int health = 50;
    int attack = 10;
    int defense = 5;
    String? asciiArt;
    List<String>? actions;

    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('-')) {
        final content = trimmed.substring(1).trim();
        final colonIndex = content.indexOf(':');
        if (colonIndex != -1) {
          final key = content.substring(0, colonIndex).trim();
          final value = content.substring(colonIndex + 1).trim();

          switch (key.toLowerCase()) {
            case 'description':
              description = value;
              break;
            case 'health':
              health = int.tryParse(value) ?? 50;
              break;
            case 'attack':
              attack = int.tryParse(value) ?? 10;
              break;
            case 'defense':
              defense = int.tryParse(value) ?? 5;
              break;
            case 'actions':
              // Parse comma-separated list of actions
              actions = value.split(',').map((a) => a.trim().toLowerCase()).where((a) => a.isNotEmpty).toList();
              break;
          }
        }
      }
    }

    // Check for ASCII art block (plain ``` or ```ascii, but not ```javascript)
    var inAsciiBlock = false;
    final asciiLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      // Start of code block that's not JavaScript
      if (trimmed.startsWith('```') && !trimmed.startsWith('```javascript') && !trimmed.startsWith('```js') && !inAsciiBlock) {
        inAsciiBlock = true;
        continue;
      }
      if (trimmed == '```' && inAsciiBlock) {
        inAsciiBlock = false;
        continue;
      }
      if (inAsciiBlock) {
        asciiLines.add(line);
      }
    }
    if (asciiLines.isNotEmpty) {
      asciiArt = asciiLines.join('\n');
    }

    return Opponent(
      id: id,
      name: name,
      description: description,
      health: health,
      attack: attack,
      defense: defense,
      asciiArt: asciiArt,
      actions: actions,
    );
  }

  /// Parse player block
  Player _parsePlayer(String block) {
    final lines = block.split('\n');

    int health = 100;
    int maxHealth = 100;
    int attack = 10;
    int defense = 5;
    int gold = 0;
    int experience = 0;
    String? asciiArt;

    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('-')) {
        final content = trimmed.substring(1).trim();
        final colonIndex = content.indexOf(':');
        if (colonIndex != -1) {
          final key = content.substring(0, colonIndex).trim();
          final value = content.substring(colonIndex + 1).trim();

          switch (key.toLowerCase()) {
            case 'health':
              health = int.tryParse(value) ?? 100;
              maxHealth = health;
              break;
            case 'maxhealth':
              maxHealth = int.tryParse(value) ?? 100;
              break;
            case 'attack':
              attack = int.tryParse(value) ?? 10;
              break;
            case 'defense':
              defense = int.tryParse(value) ?? 5;
              break;
            case 'gold':
              gold = int.tryParse(value) ?? 0;
              break;
            case 'experience':
              experience = int.tryParse(value) ?? 0;
              break;
          }
        }
      }
    }

    // Check for ASCII art block (plain ``` but not ```javascript)
    var inAsciiBlock = false;
    final asciiLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('```') && !trimmed.startsWith('```javascript') && !trimmed.startsWith('```js') && !inAsciiBlock) {
        inAsciiBlock = true;
        continue;
      }
      if (trimmed == '```' && inAsciiBlock) {
        inAsciiBlock = false;
        continue;
      }
      if (inAsciiBlock) {
        asciiLines.add(line);
      }
    }
    if (asciiLines.isNotEmpty) {
      asciiArt = asciiLines.join('\n');
    }

    return Player(
      id: 'player',
      name: 'Player',
      health: health,
      maxHealth: maxHealth,
      attack: attack,
      defense: defense,
      gold: gold,
      experience: experience,
      asciiArt: asciiArt,
    );
  }

  /// Parse title from block
  String _parseTitle(String block) {
    final lines = block.split('\n');
    return lines.first.substring('# Title:'.length).trim();
  }

  /// Parse description from block
  String _parseDescription(String block) {
    final lines = block.split('\n');
    final descLines = lines.skip(1).where((l) => l.trim().isNotEmpty).toList();
    return descLines.join('\n').trim();
  }

  /// Normalize a name to an ID (lowercase, hyphenated)
  String _normalizeId(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }
}
