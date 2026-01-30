/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Article Format Utilities - Parse and export article.md format
 */

import 'package:nntp/nntp.dart';

/// Utilities for parsing and exporting NNTP articles in markdown format.
class ArticleFormat {
  /// Standard header names in article.md format.
  static const String headerMessageId = 'MESSAGE-ID';
  static const String headerFrom = 'FROM';
  static const String headerNewsgroups = 'NEWSGROUPS';
  static const String headerDate = 'DATE';
  static const String headerReferences = 'REFERENCES';
  static const String headerSubject = 'SUBJECT';
  static const String headerReplyTo = 'REPLY-TO';
  static const String headerOrganization = 'ORGANIZATION';

  /// Exports an article to markdown format.
  ///
  /// Format:
  /// ```markdown
  /// # ARTICLE: Subject line
  ///
  /// MESSAGE-ID: <abc123@example.com>
  /// FROM: John Doe <john@example.com>
  /// NEWSGROUPS: comp.lang.dart
  /// DATE: 2025-01-30T14:30:00Z
  /// REFERENCES: <parent@example.com>
  /// SUBJECT: Subject line
  ///
  /// ---
  ///
  /// Article body content...
  /// ```
  static String export(NNTPArticle article) {
    final buffer = StringBuffer();

    // Title
    buffer.writeln('# ARTICLE: ${article.subject}');
    buffer.writeln();

    // Headers
    buffer.writeln('$headerMessageId: ${article.messageId}');
    buffer.writeln('$headerFrom: ${article.from}');
    buffer.writeln('$headerNewsgroups: ${article.newsgroups}');
    buffer.writeln('$headerDate: ${article.date.toUtc().toIso8601String()}');
    if (article.references != null && article.references!.isNotEmpty) {
      buffer.writeln('$headerReferences: ${article.references}');
    }
    buffer.writeln('$headerSubject: ${article.subject}');
    if (article.replyTo != null && article.replyTo!.isNotEmpty) {
      buffer.writeln('$headerReplyTo: ${article.replyTo}');
    }
    if (article.organization != null && article.organization!.isNotEmpty) {
      buffer.writeln('$headerOrganization: ${article.organization}');
    }
    buffer.writeln();

    // Separator
    buffer.writeln('---');
    buffer.writeln();

    // Body
    buffer.write(article.body);

    return buffer.toString();
  }

  /// Parses an article from markdown format.
  ///
  /// Returns null if parsing fails.
  static NNTPArticle? parse(String content, {int? articleNumber}) {
    final lines = content.split('\n');
    final headers = <String, String>{};
    final bodyLines = <String>[];
    var inBody = false;
    var foundSeparator = false;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      // Skip title line
      if (line.startsWith('# ARTICLE:')) continue;

      // Check for separator
      if (line.trim() == '---') {
        foundSeparator = true;
        inBody = true;
        continue;
      }

      if (!inBody) {
        // Skip empty lines in header section
        if (line.trim().isEmpty) continue;

        // Parse header
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          final key = line.substring(0, colonIndex).trim().toUpperCase();
          final value = line.substring(colonIndex + 1).trim();
          headers[key] = value;
        }
      } else {
        bodyLines.add(line);
      }
    }

    // Require at least message-id
    final messageId = headers[headerMessageId];
    if (messageId == null || messageId.isEmpty) return null;

    // Parse date
    DateTime date;
    final dateStr = headers[headerDate] ?? '';
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      date = DateTime.now();
    }

    return NNTPArticle(
      messageId: messageId,
      articleNumber: articleNumber,
      subject: headers[headerSubject] ?? '',
      from: headers[headerFrom] ?? '',
      date: date,
      references: headers[headerReferences],
      newsgroups: headers[headerNewsgroups] ?? '',
      replyTo: headers[headerReplyTo],
      organization: headers[headerOrganization],
      body: bodyLines.join('\n').trim(),
      headers: headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
    );
  }

  /// Extracts the author display name from a From header.
  ///
  /// Handles formats:
  /// - "John Doe <john@example.com>" -> "John Doe"
  /// - "john@example.com (John Doe)" -> "John Doe"
  /// - "john@example.com" -> "john"
  static String extractAuthorName(String from) {
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

    // Just email - extract local part
    final atIndex = from.indexOf('@');
    if (atIndex > 0) {
      return from.substring(0, atIndex);
    }

    return from;
  }

  /// Extracts the email address from a From header.
  static String extractAuthorEmail(String from) {
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

  /// Formats a date for display.
  static String formatDate(DateTime date, {bool relative = true}) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (relative) {
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
    }

    // Full date format
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[date.month - 1];
    final year = date.year != now.year ? ' ${date.year}' : '';
    return '$month ${date.day}$year';
  }

  /// Formats article size for display.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Quotes article text for reply.
  static String quoteForReply(NNTPArticle article, {String prefix = '> '}) {
    final attribution = 'On ${formatDate(article.date, relative: false)}, '
        '${extractAuthorName(article.from)} wrote:';

    final quotedBody = article.body
        .split('\n')
        .map((line) => '$prefix$line')
        .join('\n');

    return '$attribution\n$quotedBody\n\n';
  }

  /// Creates a reply article.
  static NNTPArticle createReply({
    required NNTPArticle original,
    required String from,
    required String body,
    String? organization,
  }) {
    // Build references chain
    final refs = StringBuffer();
    if (original.references != null && original.references!.isNotEmpty) {
      refs.write(original.references);
      refs.write(' ');
    }
    refs.write(original.messageId);

    // Prefix subject with "Re:" if not already present
    var subject = original.subject;
    if (!subject.toLowerCase().startsWith('re:')) {
      subject = 'Re: $subject';
    }

    return NNTPArticle(
      messageId: '', // Server will assign
      subject: subject,
      from: from,
      date: DateTime.now(),
      references: refs.toString(),
      newsgroups: original.newsgroups,
      organization: organization,
      body: body,
    );
  }

  /// Validates an article before posting.
  static List<String> validate(NNTPArticle article) {
    final errors = <String>[];

    if (article.from.isEmpty) {
      errors.add('From header is required');
    } else if (!article.from.contains('@')) {
      errors.add('From header must contain a valid email address');
    }

    if (article.newsgroups.isEmpty) {
      errors.add('Newsgroups header is required');
    }

    if (article.subject.isEmpty) {
      errors.add('Subject is required');
    }

    if (article.body.trim().isEmpty) {
      errors.add('Article body cannot be empty');
    }

    // Check size limits
    if (article.body.length > 1024 * 1024) {
      errors.add('Article body exceeds 1MB limit');
    }

    return errors;
  }

  /// Wraps long lines for posting (RFC 5536 recommends 79 chars).
  static String wrapLines(String text, {int maxWidth = 79}) {
    final lines = <String>[];

    for (final line in text.split('\n')) {
      if (line.length <= maxWidth) {
        lines.add(line);
        continue;
      }

      // Don't wrap quoted lines
      if (line.startsWith('>')) {
        lines.add(line);
        continue;
      }

      // Word wrap
      var current = '';
      for (final word in line.split(' ')) {
        if (current.isEmpty) {
          current = word;
        } else if (current.length + 1 + word.length <= maxWidth) {
          current = '$current $word';
        } else {
          lines.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) {
        lines.add(current);
      }
    }

    return lines.join('\n');
  }

  /// Strips signature from article body.
  static String stripSignature(String body) {
    // Standard signature separator is "-- " on its own line
    final sigIndex = body.indexOf(RegExp(r'\n-- \n'));
    if (sigIndex >= 0) {
      return body.substring(0, sigIndex).trimRight();
    }
    return body;
  }

  /// Extracts signature from article body.
  static String? extractSignature(String body) {
    final sigIndex = body.indexOf(RegExp(r'\n-- \n'));
    if (sigIndex >= 0) {
      return body.substring(sigIndex + 5).trim();
    }
    return null;
  }
}
