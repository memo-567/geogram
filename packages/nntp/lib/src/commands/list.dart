/// LIST command utilities.
library;

import '../models/newsgroup.dart';

/// LIST command variants.
enum ListCommand {
  /// LIST or LIST ACTIVE - list all groups with status.
  active('ACTIVE'),

  /// LIST NEWSGROUPS - list group descriptions.
  newsgroups('NEWSGROUPS'),

  /// LIST ACTIVE.TIMES - list group creation times.
  activeTimes('ACTIVE.TIMES'),

  /// LIST DISTRIB.PATS - distribution patterns.
  distribPats('DISTRIB.PATS'),

  /// LIST HEADERS - overview headers available.
  headers('HEADERS'),

  /// LIST OVERVIEW.FMT - overview format.
  overviewFmt('OVERVIEW.FMT'),

  /// LIST SUBSCRIPTIONS - default subscriptions.
  subscriptions('SUBSCRIPTIONS'),

  /// LIST MODERATORS - group moderator mappings.
  moderators('MODERATORS'),

  /// LIST MOTD - message of the day.
  motd('MOTD'),

  /// LIST COUNTS - group counts.
  counts('COUNTS');

  final String keyword;
  const ListCommand(this.keyword);
}

/// Parses LIST ACTIVE response.
///
/// Format: "group high low status"
/// Example: "comp.lang.dart 12345 1 y"
class ActiveEntry {
  final String name;
  final int high;
  final int low;
  final String status;

  const ActiveEntry({
    required this.name,
    required this.high,
    required this.low,
    required this.status,
  });

  /// Whether posting is allowed.
  bool get postingAllowed =>
      status == 'y' || status == 'm' || status.isEmpty;

  /// Whether the group is moderated.
  bool get isModerated => status == 'm';

  /// Parses an ACTIVE response line.
  static ActiveEntry? parse(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    final name = parts[0];
    final high = int.tryParse(parts[1]);
    final low = int.tryParse(parts[2]);
    final status = parts[3];

    if (high == null || low == null) return null;

    return ActiveEntry(
      name: name,
      high: high,
      low: low,
      status: status,
    );
  }

  /// Converts to a Newsgroup model.
  Newsgroup toNewsgroup() => Newsgroup(
        name: name,
        firstArticle: low,
        lastArticle: high,
        estimatedCount: high >= low ? high - low + 1 : 0,
        postingAllowed: postingAllowed,
      );
}

/// Parses LIST NEWSGROUPS response.
///
/// Format: "group description"
/// Example: "comp.lang.dart Discussion about Dart programming"
Map<String, String> parseNewsgroupDescriptions(List<String> lines) {
  final descriptions = <String, String>{};

  for (final line in lines) {
    final spaceIndex = line.indexOf(' ');
    if (spaceIndex > 0) {
      final name = line.substring(0, spaceIndex);
      final desc = line.substring(spaceIndex + 1).trim();
      descriptions[name] = desc;
    }
  }

  return descriptions;
}

/// Parses LIST OVERVIEW.FMT response.
///
/// Returns the list of header names in overview order.
List<String> parseOverviewFormat(List<String> lines) {
  final headers = <String>[];

  for (final line in lines) {
    // Format: "header-name:" or "header-name:full"
    final colonIndex = line.indexOf(':');
    if (colonIndex > 0) {
      headers.add(line.substring(0, colonIndex).toLowerCase());
    }
  }

  return headers;
}

/// Standard overview format per RFC 3977.
const standardOverviewFormat = [
  'subject',
  'from',
  'date',
  'message-id',
  'references',
  ':bytes',
  ':lines',
];
