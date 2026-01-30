/// NNTP article model with headers and body.
library;

/// Represents a complete Usenet article.
class NNTPArticle {
  /// Unique message identifier (e.g., "<abc123@example.com>").
  final String messageId;

  /// Article number within the current group, if known.
  final int? articleNumber;

  /// Article subject line.
  final String subject;

  /// Author in RFC 5322 format (e.g., "John Doe <john@example.com>").
  final String from;

  /// Date the article was posted.
  final DateTime date;

  /// References header containing parent message IDs for threading.
  final String? references;

  /// Newsgroups this article was posted to (comma-separated).
  final String newsgroups;

  /// Reply-To address, if different from From.
  final String? replyTo;

  /// Organization of the poster.
  final String? organization;

  /// Article body content.
  final String body;

  /// All headers as key-value pairs.
  final Map<String, String> headers;

  const NNTPArticle({
    required this.messageId,
    this.articleNumber,
    required this.subject,
    required this.from,
    required this.date,
    this.references,
    required this.newsgroups,
    this.replyTo,
    this.organization,
    required this.body,
    this.headers = const {},
  });

  /// Parses an article from raw NNTP response.
  ///
  /// The response includes headers followed by a blank line and the body.
  factory NNTPArticle.parse(String raw, {int? articleNumber}) {
    final lines = raw.split('\n');
    final headers = <String, String>{};
    final bodyLines = <String>[];
    var inBody = false;
    String? currentHeader;
    String? currentValue;

    for (var line in lines) {
      // Remove trailing CR if present
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }

      if (!inBody) {
        // Empty line marks start of body
        if (line.isEmpty) {
          // Save last header
          if (currentHeader != null) {
            headers[currentHeader] = currentValue ?? '';
          }
          inBody = true;
          continue;
        }

        // Continuation of previous header (starts with whitespace)
        if (line.startsWith(' ') || line.startsWith('\t')) {
          if (currentValue != null) {
            currentValue = '$currentValue ${line.trim()}';
          }
          continue;
        }

        // Save previous header
        if (currentHeader != null) {
          headers[currentHeader] = currentValue ?? '';
        }

        // Parse new header
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          currentHeader = line.substring(0, colonIndex).toLowerCase();
          currentValue = line.substring(colonIndex + 1).trim();
        }
      } else {
        bodyLines.add(line);
      }
    }

    // Parse date
    final dateStr = headers['date'] ?? '';
    DateTime date;
    try {
      date = _parseRfc5322Date(dateStr);
    } catch (_) {
      date = DateTime.now();
    }

    return NNTPArticle(
      messageId: headers['message-id'] ?? '',
      articleNumber: articleNumber,
      subject: headers['subject'] ?? '',
      from: headers['from'] ?? '',
      date: date,
      references: headers['references'],
      newsgroups: headers['newsgroups'] ?? '',
      replyTo: headers['reply-to'],
      organization: headers['organization'],
      body: bodyLines.join('\n').trimRight(),
      headers: headers,
    );
  }

  /// Parses RFC 5322 date format.
  ///
  /// Example: "Thu, 30 Jan 2025 14:30:00 +0000"
  static DateTime _parseRfc5322Date(String s) {
    s = s.trim();
    if (s.isEmpty) return DateTime.now();

    // Try standard parsing first
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // Parse RFC 5322 format manually
    // Remove day name if present
    final commaIndex = s.indexOf(',');
    if (commaIndex != -1) {
      s = s.substring(commaIndex + 1).trim();
    }

    // Parse "30 Jan 2025 14:30:00 +0000"
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length < 4) return DateTime.now();

    final day = int.tryParse(parts[0]) ?? 1;
    final month = _parseMonth(parts[1]);
    final year = int.tryParse(parts[2]) ?? DateTime.now().year;

    // Parse time "14:30:00"
    final timeParts = parts[3].split(':');
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    final second = timeParts.length > 2 ? int.tryParse(timeParts[2]) ?? 0 : 0;

    // Parse timezone offset if present
    var tzOffset = Duration.zero;
    if (parts.length > 4) {
      tzOffset = _parseTzOffset(parts[4]);
    }

    final utc = DateTime.utc(year, month, day, hour, minute, second);
    return utc.subtract(tzOffset);
  }

  static int _parseMonth(String s) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return months[s.toLowerCase()] ?? 1;
  }

  static Duration _parseTzOffset(String s) {
    if (s.isEmpty) return Duration.zero;

    // Handle named zones
    if (s == 'UTC' || s == 'GMT' || s == 'Z') return Duration.zero;

    // Parse numeric offset like "+0000" or "-0500"
    final sign = s.startsWith('-') ? -1 : 1;
    final offset = s.replaceFirst(RegExp(r'^[+-]'), '');
    if (offset.length >= 4) {
      final hours = int.tryParse(offset.substring(0, 2)) ?? 0;
      final minutes = int.tryParse(offset.substring(2, 4)) ?? 0;
      return Duration(hours: sign * hours, minutes: sign * minutes);
    }
    return Duration.zero;
  }

  /// Gets the parent message ID from references (last one).
  String? get parentMessageId {
    if (references == null || references!.isEmpty) return null;
    final refs = references!.trim().split(RegExp(r'\s+'));
    return refs.isNotEmpty ? refs.last : null;
  }

  /// Gets all referenced message IDs.
  List<String> get allReferences {
    if (references == null || references!.isEmpty) return [];
    return references!.trim().split(RegExp(r'\s+'));
  }

  /// Formats article for posting.
  String toPostFormat() {
    final buffer = StringBuffer();

    buffer.writeln('From: $from');
    buffer.writeln('Newsgroups: $newsgroups');
    buffer.writeln('Subject: $subject');
    if (references != null) {
      buffer.writeln('References: $references');
    }
    if (replyTo != null) {
      buffer.writeln('Reply-To: $replyTo');
    }
    if (organization != null) {
      buffer.writeln('Organization: $organization');
    }

    // Add any custom headers
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (!_standardHeaders.contains(key)) {
        buffer.writeln('${_capitalizeHeader(entry.key)}: ${entry.value}');
      }
    }

    buffer.writeln();
    buffer.write(body);

    return buffer.toString();
  }

  static const _standardHeaders = {
    'from', 'newsgroups', 'subject', 'date', 'message-id',
    'references', 'reply-to', 'organization',
  };

  static String _capitalizeHeader(String h) {
    return h.split('-').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join('-');
  }

  /// Converts to JSON for storage.
  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        if (articleNumber != null) 'articleNumber': articleNumber,
        'subject': subject,
        'from': from,
        'date': date.toIso8601String(),
        if (references != null) 'references': references,
        'newsgroups': newsgroups,
        if (replyTo != null) 'replyTo': replyTo,
        if (organization != null) 'organization': organization,
        'body': body,
        'headers': headers,
      };

  /// Creates from JSON storage.
  factory NNTPArticle.fromJson(Map<String, dynamic> json) => NNTPArticle(
        messageId: json['messageId'] as String,
        articleNumber: json['articleNumber'] as int?,
        subject: json['subject'] as String,
        from: json['from'] as String,
        date: DateTime.parse(json['date'] as String),
        references: json['references'] as String?,
        newsgroups: json['newsgroups'] as String,
        replyTo: json['replyTo'] as String?,
        organization: json['organization'] as String?,
        body: json['body'] as String,
        headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      );

  @override
  String toString() => 'NNTPArticle($messageId, "$subject")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NNTPArticle && messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;
}
