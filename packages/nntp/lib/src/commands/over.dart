/// OVER/XOVER command utilities.
library;

import '../models/overview.dart';
import '../models/range.dart';

/// Overview field indices (standard format per RFC 3977).
class OverviewField {
  static const int articleNumber = 0;
  static const int subject = 1;
  static const int from = 2;
  static const int date = 3;
  static const int messageId = 4;
  static const int references = 5;
  static const int bytes = 6;
  static const int lines = 7;

  /// First index for optional/extra headers.
  static const int extrasStart = 8;
}

/// Parses OVER/XOVER response lines.
List<OverviewEntry> parseOverviewResponse(List<String> lines) {
  return lines
      .map((line) => OverviewEntry.parse(line))
      .whereType<OverviewEntry>()
      .toList();
}

/// Builds OVER command string.
String buildOverCommand({Range? range, bool useLegacy = false}) {
  final command = useLegacy ? 'XOVER' : 'OVER';
  if (range == null) {
    return command;
  }
  return '$command ${range.toNNTPString()}';
}

/// Validates and normalizes an overview range.
///
/// - Returns null if range is entirely out of bounds.
/// - Adjusts range to fit within group bounds.
Range? normalizeRange(Range range, int low, int high) {
  // Entirely below group
  if (range.end != null && range.end! < low) {
    return null;
  }

  // Entirely above group
  if (range.start > high) {
    return null;
  }

  // Adjust start
  final adjustedStart = range.start < low ? low : range.start;

  // Adjust end (null means open-ended)
  int? adjustedEnd;
  if (range.end != null) {
    adjustedEnd = range.end! > high ? high : range.end;
  }

  return Range(adjustedStart, adjustedEnd);
}

/// Splits a large range into chunks for progressive fetching.
List<Range> splitRange(Range range, int chunkSize, {int? maxArticle}) {
  final chunks = <Range>[];

  var start = range.start;
  final end = range.end ?? maxArticle ?? (start + chunkSize * 10);

  while (start <= end) {
    final chunkEnd = start + chunkSize - 1;
    if (chunkEnd >= end) {
      chunks.add(Range(start, end));
      break;
    }
    chunks.add(Range(start, chunkEnd));
    start = chunkEnd + 1;
  }

  return chunks;
}
