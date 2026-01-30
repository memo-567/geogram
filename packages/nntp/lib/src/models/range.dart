/// Article number range for NNTP commands.
library;

/// Represents a range of article numbers.
///
/// Used with commands like LISTGROUP, OVER, and NEWNEWS.
/// Supports:
/// - Single article: Range(100)
/// - Bounded range: Range(100, 200)
/// - Open-ended range: Range(100, null) means "100-"
class Range {
  /// Start of the range (inclusive).
  final int start;

  /// End of the range (inclusive), or null for open-ended.
  final int? end;

  /// Creates a range from [start] to [end].
  ///
  /// If [end] is null, the range is open-ended (start-).
  /// If [end] equals [start], it represents a single article.
  const Range(this.start, [this.end]);

  /// Creates a range for a single article number.
  const Range.single(int number)
      : start = number,
        end = number;

  /// Creates an open-ended range starting at [start].
  const Range.from(int start)
      : this.start = start,
        end = null;

  /// Whether this range represents a single article.
  bool get isSingle => end != null && start == end;

  /// Whether this range is open-ended.
  bool get isOpenEnded => end == null;

  /// Formats the range for NNTP commands.
  ///
  /// Examples:
  /// - Single: "100"
  /// - Bounded: "100-200"
  /// - Open-ended: "100-"
  String toNNTPString() {
    if (isSingle) {
      return start.toString();
    }
    if (isOpenEnded) {
      return '$start-';
    }
    return '$start-$end';
  }

  /// Parses a range from NNTP format.
  ///
  /// Accepts:
  /// - "100" -> single article
  /// - "100-200" -> bounded range
  /// - "100-" -> open-ended range
  static Range? parse(String s) {
    s = s.trim();
    if (s.isEmpty) return null;

    if (!s.contains('-')) {
      final num = int.tryParse(s);
      return num != null ? Range.single(num) : null;
    }

    final parts = s.split('-');
    if (parts.length != 2) return null;

    final start = int.tryParse(parts[0]);
    if (start == null) return null;

    if (parts[1].isEmpty) {
      return Range.from(start);
    }

    final end = int.tryParse(parts[1]);
    return end != null ? Range(start, end) : null;
  }

  @override
  String toString() => 'Range($start${end != null ? ', $end' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Range && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}
