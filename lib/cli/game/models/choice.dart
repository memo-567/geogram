/// Link type for choices
enum LinkType {
  scene,
  item,
  action,
  opponent,
  leave,
  inventory, // Special: show inventory screen
}

/// Player choice in a scene
class Choice {
  final String text;
  final String targetId;
  final LinkType linkType;
  final String? opponentId;
  final String? actionId;
  final String? winScene;
  final String? loseScene;
  final List<String>? winItems;
  final Map<String, dynamic>? requirements;

  Choice({
    required this.text,
    required this.targetId,
    this.linkType = LinkType.scene,
    this.opponentId,
    this.actionId,
    this.winScene,
    this.loseScene,
    this.winItems,
    this.requirements,
  });

  /// Create special inventory choice marker
  factory Choice.inventory() => Choice(
    text: 'Inventory',
    targetId: '',
    linkType: LinkType.inventory,
  );

  /// Parse a choice line like:
  /// - [Enter tavern](#scene-tavern)
  /// - [Fight guard](#opponent-guard) -> win:#scene-victory; lose:#scene-defeat
  /// - [Take sword](#item-sword)
  factory Choice.parse(String line) {
    // Extract text and link: [Text](#link)
    final linkMatch = RegExp(r'\[([^\]]+)\]\(#([^)]+)\)').firstMatch(line);
    if (linkMatch == null) {
      return Choice(text: line.trim(), targetId: '');
    }

    final text = linkMatch.group(1) ?? '';
    final link = linkMatch.group(2) ?? '';

    // Parse link type
    LinkType linkType = LinkType.scene;
    String targetId = link;

    if (link.startsWith('scene-')) {
      linkType = LinkType.scene;
      targetId = link.substring(6);
    } else if (link.startsWith('item-')) {
      linkType = LinkType.item;
      targetId = link.substring(5);
    } else if (link.startsWith('action-')) {
      linkType = LinkType.action;
      targetId = link.substring(7);
    } else if (link.startsWith('opponent-')) {
      linkType = LinkType.opponent;
      targetId = link.substring(9);
    } else if (link == 'leave' || link.startsWith('leave-')) {
      linkType = LinkType.leave;
      targetId = link;
    }

    // Parse consequences: -> win:#scene-victory; lose:#scene-defeat
    String? winScene;
    String? loseScene;
    String? opponentId;
    String? actionId;
    List<String>? winItems;

    final consequenceMatch = RegExp(r'->\s*(.+)$').firstMatch(line);
    if (consequenceMatch != null) {
      final consequences = consequenceMatch.group(1)!;

      // Parse win consequences
      final winMatch = RegExp(r'win:\s*([^;]+)').firstMatch(consequences);
      if (winMatch != null) {
        final winParts = winMatch.group(1)!.split(';').map((s) => s.trim()).toList();
        for (final part in winParts) {
          if (part.startsWith('#scene-')) {
            winScene = part.substring(7);
          } else if (part.startsWith('#item-')) {
            winItems ??= [];
            winItems.add(part.substring(6));
          }
        }
      }

      // Parse lose consequences
      final loseMatch = RegExp(r'lose:\s*#scene-([^;\s]+)').firstMatch(consequences);
      if (loseMatch != null) {
        loseScene = loseMatch.group(1);
      }
    }

    // If opponent link, set up combat
    if (linkType == LinkType.opponent) {
      opponentId = targetId;
      actionId = 'attack'; // Default action
    }

    return Choice(
      text: text,
      targetId: targetId,
      linkType: linkType,
      opponentId: opponentId,
      actionId: actionId,
      winScene: winScene,
      loseScene: loseScene,
      winItems: winItems,
    );
  }
}
