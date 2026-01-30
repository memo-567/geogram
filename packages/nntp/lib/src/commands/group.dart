/// GROUP and LISTGROUP command utilities.
library;

import '../models/newsgroup.dart';

/// Parses GROUP command response.
///
/// Response format: "211 count low high group"
/// Example: "211 1234 3000 4233 comp.lang.dart"
class GroupResponse {
  final int count;
  final int low;
  final int high;
  final String name;

  const GroupResponse({
    required this.count,
    required this.low,
    required this.high,
    required this.name,
  });

  /// Parses a GROUP response message.
  static GroupResponse? parse(String message) {
    final parts = message.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    final count = int.tryParse(parts[0]);
    final low = int.tryParse(parts[1]);
    final high = int.tryParse(parts[2]);
    final name = parts[3];

    if (count == null || low == null || high == null) return null;

    return GroupResponse(
      count: count,
      low: low,
      high: high,
      name: name,
    );
  }

  /// Converts to a Newsgroup model.
  Newsgroup toNewsgroup() => Newsgroup(
        name: name,
        firstArticle: low,
        lastArticle: high,
        estimatedCount: count,
      );
}

/// Parses LISTGROUP response data (article numbers).
List<int> parseListGroupResponse(List<String> lines) {
  return lines
      .map((line) => int.tryParse(line.trim()))
      .whereType<int>()
      .toList();
}
