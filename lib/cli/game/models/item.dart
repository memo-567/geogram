import 'game_thing.dart';

/// Item entity with modifiers
class Item extends GameThing {
  final String type;
  final Map<String, int> modifiers = {};
  final bool consumable;

  Item({
    required super.id,
    required super.name,
    super.description,
    this.type = 'misc',
    this.consumable = false,
    Map<String, int>? modifiers,
  }) {
    if (modifiers != null) {
      this.modifiers.addAll(modifiers);
    }
  }

  /// Parse attribute modifier like "+10" or "-5"
  static int parseModifier(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      return int.tryParse(trimmed.substring(1)) ?? 0;
    } else if (trimmed.startsWith('-')) {
      return -(int.tryParse(trimmed.substring(1)) ?? 0);
    }
    return int.tryParse(trimmed) ?? 0;
  }

  @override
  List<String> getAsciiArt() {
    switch (type.toLowerCase()) {
      case 'weapon':
        return [
          '    /\\    ',
          '   /  \\   ',
          '  /____\\  ',
          '    ||    ',
          '    ||    ',
        ];
      case 'armor':
        return [
          '  ╭────╮  ',
          '  │ ## │  ',
          '  │ ## │  ',
          '  ╰────╯  ',
        ];
      case 'potion':
        return [
          '   ___   ',
          '  /   \\  ',
          '  | ~ |  ',
          '  \\___/  ',
        ];
      default:
        return [
          '  ╭───╮  ',
          '  │ * │  ',
          '  ╰───╯  ',
        ];
    }
  }
}
