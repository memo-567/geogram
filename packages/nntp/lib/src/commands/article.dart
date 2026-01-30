/// ARTICLE, HEAD, BODY, STAT command utilities.
library;

import '../models/article.dart';

/// Article retrieval modes.
enum ArticleRetrievalMode {
  /// Full article (headers + body).
  full('ARTICLE'),

  /// Headers only.
  head('HEAD'),

  /// Body only.
  body('BODY'),

  /// Status only (check existence).
  stat('STAT');

  final String command;
  const ArticleRetrievalMode(this.command);
}

/// Parses article headers from HEAD response or ARTICLE response.
Map<String, String> parseHeaders(List<String> lines) {
  final headers = <String, String>{};
  String? currentKey;
  final currentValue = StringBuffer();

  for (var line in lines) {
    // Empty line marks end of headers
    if (line.isEmpty) break;

    // Continuation of previous header (starts with whitespace)
    if (line.startsWith(' ') || line.startsWith('\t')) {
      if (currentKey != null) {
        currentValue.write(' ');
        currentValue.write(line.trim());
      }
      continue;
    }

    // Save previous header
    if (currentKey != null) {
      headers[currentKey] = currentValue.toString();
      currentValue.clear();
    }

    // Parse new header
    final colonIndex = line.indexOf(':');
    if (colonIndex > 0) {
      currentKey = line.substring(0, colonIndex).toLowerCase();
      currentValue.write(line.substring(colonIndex + 1).trim());
    }
  }

  // Save last header
  if (currentKey != null) {
    headers[currentKey] = currentValue.toString();
  }

  return headers;
}

/// Parses a complete article from ARTICLE response lines.
NNTPArticle parseArticle(List<String> lines, {int? articleNumber}) {
  return NNTPArticle.parse(lines.join('\n'), articleNumber: articleNumber);
}

/// Extracts body from ARTICLE response lines (after empty line).
String parseBody(List<String> lines) {
  final bodyStart = lines.indexWhere((line) => line.isEmpty);
  if (bodyStart < 0 || bodyStart >= lines.length - 1) {
    return '';
  }
  return lines.sublist(bodyStart + 1).join('\n');
}

/// Parses STAT response to extract article number and message-id.
///
/// Response format: "223 number <message-id>"
/// Example: "223 12345 <abc@example.com>"
class StatResponse {
  final int articleNumber;
  final String messageId;

  const StatResponse({
    required this.articleNumber,
    required this.messageId,
  });

  static StatResponse? parse(String message) {
    final parts = message.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;

    final number = int.tryParse(parts[0]);
    if (number == null) return null;

    final messageId = parts.length > 1 ? parts[1] : '';

    return StatResponse(
      articleNumber: number,
      messageId: messageId,
    );
  }
}

/// Extracts the author name from a From header.
///
/// Handles formats like:
/// - "John Doe <john@example.com>"
/// - "john@example.com (John Doe)"
/// - "john@example.com"
String extractAuthorName(String from) {
  from = from.trim();

  // Format: "Name <email>"
  final angleMatch = RegExp(r'^([^<]+)<').firstMatch(from);
  if (angleMatch != null) {
    return angleMatch.group(1)!.trim().replaceAll('"', '');
  }

  // Format: "email (Name)"
  final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(from);
  if (parenMatch != null) {
    return parenMatch.group(1)!.trim();
  }

  // Just email, extract local part
  final atIndex = from.indexOf('@');
  if (atIndex > 0) {
    return from.substring(0, atIndex);
  }

  return from;
}

/// Extracts the email address from a From header.
String extractAuthorEmail(String from) {
  from = from.trim();

  // Format: "Name <email>"
  final angleMatch = RegExp(r'<([^>]+)>').firstMatch(from);
  if (angleMatch != null) {
    return angleMatch.group(1)!.trim();
  }

  // Format: "email (Name)"
  final parenMatch = RegExp(r'^([^\s(]+)').firstMatch(from);
  if (parenMatch != null) {
    return parenMatch.group(1)!.trim();
  }

  return from;
}
