/// Newsgroup metadata model.
library;

/// Represents a Usenet newsgroup with its metadata.
class Newsgroup {
  /// Full newsgroup name (e.g., "comp.lang.dart").
  final String name;

  /// Human-readable description, if available.
  final String? description;

  /// Lowest article number in the group (low water mark).
  final int firstArticle;

  /// Highest article number in the group (high water mark).
  final int lastArticle;

  /// Estimated number of articles in the group.
  ///
  /// Note: This is an estimate and may not be accurate.
  final int estimatedCount;

  /// Whether posting is allowed to this group.
  final bool postingAllowed;

  const Newsgroup({
    required this.name,
    this.description,
    required this.firstArticle,
    required this.lastArticle,
    required this.estimatedCount,
    this.postingAllowed = true,
  });

  /// Creates a newsgroup from LIST ACTIVE response line.
  ///
  /// Format: group high low flags
  /// Example: comp.lang.dart 12345 1 y
  ///
  /// Flags:
  /// - y: posting allowed
  /// - n: no posting
  /// - m: moderated
  /// - x: no local posting
  /// - j: junk group (not recommended)
  /// - =name: alias to another group
  static Newsgroup? fromListActive(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    final name = parts[0];
    final high = int.tryParse(parts[1]);
    final low = int.tryParse(parts[2]);
    final flags = parts[3];

    if (high == null || low == null) return null;

    // Calculate estimated count
    final count = high >= low ? high - low + 1 : 0;

    return Newsgroup(
      name: name,
      firstArticle: low,
      lastArticle: high,
      estimatedCount: count,
      postingAllowed: flags == 'y' || flags == 'm',
    );
  }

  /// Creates a newsgroup from GROUP command response.
  ///
  /// Response format: 211 count low high name
  static Newsgroup? fromGroupResponse(String response) {
    final parts = response.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) return null;

    // parts[0] is "211"
    final count = int.tryParse(parts[1]);
    final low = int.tryParse(parts[2]);
    final high = int.tryParse(parts[3]);
    final name = parts[4];

    if (count == null || low == null || high == null) return null;

    return Newsgroup(
      name: name,
      firstArticle: low,
      lastArticle: high,
      estimatedCount: count,
    );
  }

  /// Creates a copy with optional description.
  Newsgroup withDescription(String? description) => Newsgroup(
        name: name,
        description: description,
        firstArticle: firstArticle,
        lastArticle: lastArticle,
        estimatedCount: estimatedCount,
        postingAllowed: postingAllowed,
      );

  /// Converts to JSON for storage.
  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'firstArticle': firstArticle,
        'lastArticle': lastArticle,
        'estimatedCount': estimatedCount,
        'postingAllowed': postingAllowed,
      };

  /// Creates from JSON storage.
  factory Newsgroup.fromJson(Map<String, dynamic> json) => Newsgroup(
        name: json['name'] as String,
        description: json['description'] as String?,
        firstArticle: json['firstArticle'] as int,
        lastArticle: json['lastArticle'] as int,
        estimatedCount: json['estimatedCount'] as int,
        postingAllowed: json['postingAllowed'] as bool? ?? true,
      );

  @override
  String toString() => 'Newsgroup($name, $firstArticle-$lastArticle)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Newsgroup && name == other.name;

  @override
  int get hashCode => name.hashCode;
}
