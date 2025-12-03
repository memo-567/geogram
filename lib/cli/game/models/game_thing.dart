/// Base class for all game entities (Player, Opponent, Item)
abstract class GameThing {
  final String id;
  String name;
  String description;
  final Map<String, int> attributes = {};

  GameThing({
    required this.id,
    required this.name,
    this.description = '',
  });

  /// Get attribute value
  int getAttribute(String key) => attributes[key] ?? 0;

  /// Set attribute value
  void setAttribute(String key, int value) {
    attributes[key] = value;
  }

  /// Convert to map for JS execution
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      ...attributes.map((k, v) => MapEntry(k, v)),
    };
  }

  /// Update from JS result map
  void fromMap(Map<String, dynamic> map) {
    for (final entry in map.entries) {
      if (entry.value is int) {
        attributes[entry.key] = entry.value;
      } else if (entry.value is num) {
        attributes[entry.key] = entry.value.toInt();
      }
    }
  }

  /// Get ASCII art representation
  List<String> getAsciiArt() {
    return [
      '  ╭───╮  ',
      '  │ ? │  ',
      '  ╰───╯  ',
    ];
  }
}
