/// Random event with probability
class RandomEvent {
  final int probability;
  final String text;
  final String targetScene;

  RandomEvent({
    required this.probability,
    required this.text,
    required this.targetScene,
  });

  /// Parse a random event line like:
  /// - 30% [Merchant appears](#scene-merchant)
  factory RandomEvent.parse(String line) {
    // Extract percentage
    final percentMatch = RegExp(r'(\d+)%').firstMatch(line);
    final probability = percentMatch != null
        ? int.tryParse(percentMatch.group(1)!) ?? 0
        : 0;

    // Extract text and link
    final linkMatch = RegExp(r'\[([^\]]+)\]\(#([^)]+)\)').firstMatch(line);
    if (linkMatch == null) {
      return RandomEvent(
        probability: probability,
        text: line.trim(),
        targetScene: '',
      );
    }

    final text = linkMatch.group(1) ?? '';
    var link = linkMatch.group(2) ?? '';

    // Remove scene- prefix if present
    if (link.startsWith('scene-')) {
      link = link.substring(6);
    }

    return RandomEvent(
      probability: probability,
      text: text,
      targetScene: link,
    );
  }
}
