/// Overview entry model for XOVER/OVER response.
library;

/// Represents an overview entry from OVER/XOVER command.
///
/// Overview data provides a compact summary of articles without
/// fetching the full content, used for building article lists.
class OverviewEntry {
  /// Article number in the group.
  final int articleNumber;

  /// Article subject line.
  final String subject;

  /// Author in RFC 5322 format.
  final String from;

  /// Date string as returned by server.
  final String dateString;

  /// Parsed date, if successful.
  final DateTime? date;

  /// Message-ID of this article.
  final String messageId;

  /// References header for threading.
  final String? references;

  /// Size of the article in bytes.
  final int bytes;

  /// Number of lines in the body.
  final int lines;

  /// Additional headers from extended overview.
  final Map<String, String>? extraHeaders;

  const OverviewEntry({
    required this.articleNumber,
    required this.subject,
    required this.from,
    required this.dateString,
    this.date,
    required this.messageId,
    this.references,
    required this.bytes,
    required this.lines,
    this.extraHeaders,
  });

  /// Parses an overview entry from OVER/XOVER response line.
  ///
  /// Standard format (RFC 3977):
  /// article-number\tsubject\tfrom\tdate\tmessage-id\treferences\tbytes\tlines[\textra...]
  ///
  /// Fields are tab-separated. Empty fields may be present for references.
  static OverviewEntry? parse(String line) {
    final parts = line.split('\t');
    if (parts.length < 8) return null;

    final articleNumber = int.tryParse(parts[0]);
    if (articleNumber == null) return null;

    final subject = _decodeHeader(parts[1]);
    final from = _decodeHeader(parts[2]);
    final dateString = parts[3];
    final messageId = parts[4];
    final references = parts[5].isEmpty ? null : parts[5];
    final bytes = int.tryParse(parts[6]) ?? 0;
    final lines = int.tryParse(parts[7]) ?? 0;

    // Parse extra headers if present
    Map<String, String>? extraHeaders;
    if (parts.length > 8) {
      extraHeaders = {};
      for (var i = 8; i < parts.length; i++) {
        final extra = parts[i];
        final colonIndex = extra.indexOf(':');
        if (colonIndex > 0) {
          final key = extra.substring(0, colonIndex).trim().toLowerCase();
          final value = extra.substring(colonIndex + 1).trim();
          extraHeaders[key] = _decodeHeader(value);
        }
      }
    }

    // Try to parse date
    DateTime? date;
    try {
      date = _parseDate(dateString);
    } catch (_) {}

    return OverviewEntry(
      articleNumber: articleNumber,
      subject: subject,
      from: from,
      dateString: dateString,
      date: date,
      messageId: messageId,
      references: references,
      bytes: bytes,
      lines: lines,
      extraHeaders: extraHeaders,
    );
  }

  /// Decodes RFC 2047 encoded headers.
  ///
  /// Example: "=?UTF-8?B?SGVsbG8gV29ybGQ=?=" -> "Hello World"
  static String _decodeHeader(String s) {
    if (!s.contains('=?')) return s;

    // Match =?charset?encoding?encoded_text?=
    final pattern = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');
    return s.replaceAllMapped(pattern, (match) {
      final charset = match.group(1)!.toLowerCase();
      final encoding = match.group(2)!.toUpperCase();
      final text = match.group(3)!;

      try {
        if (encoding == 'B') {
          // Base64
          return _decodeBase64(text);
        } else if (encoding == 'Q') {
          // Quoted-printable
          return _decodeQuotedPrintable(text);
        }
      } catch (_) {}
      return match.group(0)!;
    });
  }

  static String _decodeBase64(String s) {
    // Simplified base64 decoder (Dart's convert library would need import)
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final bytes = <int>[];
    var buffer = 0;
    var bits = 0;

    for (final char in s.codeUnits) {
      if (char == 61) break; // '='
      final value = chars.indexOf(String.fromCharCode(char));
      if (value < 0) continue;

      buffer = (buffer << 6) | value;
      bits += 6;

      while (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xFF);
      }
    }

    return String.fromCharCodes(bytes);
  }

  static String _decodeQuotedPrintable(String s) {
    final result = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (s[i] == '_') {
        result.write(' ');
        i++;
      } else if (s[i] == '=' && i + 2 < s.length) {
        final hex = s.substring(i + 1, i + 3);
        final value = int.tryParse(hex, radix: 16);
        if (value != null) {
          result.writeCharCode(value);
          i += 3;
        } else {
          result.write(s[i]);
          i++;
        }
      } else {
        result.write(s[i]);
        i++;
      }
    }
    return result.toString();
  }

  static DateTime _parseDate(String s) {
    s = s.trim();
    if (s.isEmpty) throw FormatException('Empty date');

    // Try ISO 8601 first
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // Parse RFC 5322 format
    final commaIndex = s.indexOf(',');
    if (commaIndex != -1) {
      s = s.substring(commaIndex + 1).trim();
    }

    final parts = s.split(RegExp(r'\s+'));
    if (parts.length < 4) throw FormatException('Invalid date: $s');

    final day = int.parse(parts[0]);
    final month = _parseMonth(parts[1]);
    final year = int.parse(parts[2]);

    final timeParts = parts[3].split(':');
    final hour = int.parse(timeParts[0]);
    final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
    final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;

    return DateTime.utc(year, month, day, hour, minute, second);
  }

  static int _parseMonth(String s) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return months[s.toLowerCase()] ?? 1;
  }

  /// Gets the parent message ID from references.
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

  /// Converts to JSON for storage.
  Map<String, dynamic> toJson() => {
        'articleNumber': articleNumber,
        'subject': subject,
        'from': from,
        'dateString': dateString,
        if (date != null) 'date': date!.toIso8601String(),
        'messageId': messageId,
        if (references != null) 'references': references,
        'bytes': bytes,
        'lines': lines,
        if (extraHeaders != null) 'extraHeaders': extraHeaders,
      };

  /// Creates from JSON storage.
  factory OverviewEntry.fromJson(Map<String, dynamic> json) => OverviewEntry(
        articleNumber: json['articleNumber'] as int,
        subject: json['subject'] as String,
        from: json['from'] as String,
        dateString: json['dateString'] as String,
        date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
        messageId: json['messageId'] as String,
        references: json['references'] as String?,
        bytes: json['bytes'] as int,
        lines: json['lines'] as int,
        extraHeaders: json['extraHeaders'] != null
            ? Map<String, String>.from(json['extraHeaders'] as Map)
            : null,
      );

  @override
  String toString() => 'OverviewEntry($articleNumber, "$subject")';
}
