/// Miscellaneous NNTP command utilities.
library;

/// Parses DATE response.
///
/// Response format: "111 YYYYMMDDhhmmss"
DateTime parseNNTPDate(String message) {
  final dateStr = message.trim();
  if (dateStr.length < 14) {
    throw FormatException('Invalid DATE response: $message');
  }

  final year = int.parse(dateStr.substring(0, 4));
  final month = int.parse(dateStr.substring(4, 6));
  final day = int.parse(dateStr.substring(6, 8));
  final hour = int.parse(dateStr.substring(8, 10));
  final minute = int.parse(dateStr.substring(10, 12));
  final second = int.parse(dateStr.substring(12, 14));

  return DateTime.utc(year, month, day, hour, minute, second);
}

/// Formats a DateTime for NNTP commands (NEWGROUPS, NEWNEWS).
///
/// Format: "YYMMDD HHMMSS GMT" or "YYYYMMDD HHMMSS GMT"
class NNTPDateFormat {
  /// Formats date part.
  static String date(DateTime dt, {bool useFullYear = true}) {
    final year = useFullYear
        ? dt.year.toString().padLeft(4, '0')
        : (dt.year % 100).toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  /// Formats time part.
  static String time(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour$minute$second';
  }

  /// Formats complete date/time for NNTP command.
  static String format(DateTime dt, {bool utc = true}) {
    final d = utc ? dt.toUtc() : dt;
    return '${date(d)} ${time(d)}${utc ? ' GMT' : ''}';
  }
}

/// Parses HELP response.
///
/// Returns a list of available commands.
List<String> parseHelpResponse(List<String> lines) {
  final commands = <String>[];

  for (final line in lines) {
    // Skip empty lines and headers
    if (line.isEmpty || line.startsWith(' ')) continue;

    // Extract first word (command name)
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.toUpperCase() == parts.first) {
      commands.add(parts.first);
    }
  }

  return commands;
}

/// Parses NEWGROUPS response.
///
/// Same format as LIST ACTIVE.
/// Returns list of "group high low status" lines.
List<String> parseNewGroupsResponse(List<String> lines) {
  return lines.where((line) => line.trim().isNotEmpty).toList();
}

/// Parses NEWNEWS response.
///
/// Returns list of message-ids.
List<String> parseNewNewsResponse(List<String> lines) {
  return lines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Calculates time since last sync for NEWGROUPS/NEWNEWS.
DateTime calculateSyncTime(DateTime? lastSync, {Duration maxAge = const Duration(days: 14)}) {
  final now = DateTime.now().toUtc();

  if (lastSync == null) {
    // First sync - go back maxAge
    return now.subtract(maxAge);
  }

  // Use last sync time, but cap at maxAge
  final earliest = now.subtract(maxAge);
  return lastSync.isAfter(earliest) ? lastSync : earliest;
}
