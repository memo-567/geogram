/// POST and IHAVE command utilities.
library;

import '../models/article.dart';

/// Formats an article for posting.
///
/// Ensures proper line endings and dot-stuffing.
String formatArticleForPost(NNTPArticle article) {
  final buffer = StringBuffer();

  // Required headers
  buffer.writeln('From: ${article.from}');
  buffer.writeln('Newsgroups: ${article.newsgroups}');
  buffer.writeln('Subject: ${article.subject}');

  // Optional headers
  if (article.references != null && article.references!.isNotEmpty) {
    buffer.writeln('References: ${article.references}');
  }
  if (article.replyTo != null && article.replyTo!.isNotEmpty) {
    buffer.writeln('Reply-To: ${article.replyTo}');
  }
  if (article.organization != null && article.organization!.isNotEmpty) {
    buffer.writeln('Organization: ${article.organization}');
  }

  // Custom headers
  for (final entry in article.headers.entries) {
    final key = entry.key.toLowerCase();
    // Skip headers we already handled
    if (_handledHeaders.contains(key)) continue;
    buffer.writeln('${_capitalizeHeader(entry.key)}: ${entry.value}');
  }

  // Blank line separates headers from body
  buffer.writeln();

  // Body with dot-stuffing
  for (final line in article.body.split('\n')) {
    if (line.startsWith('.')) {
      buffer.write('.');
    }
    buffer.writeln(line);
  }

  return buffer.toString();
}

const _handledHeaders = {
  'from',
  'newsgroups',
  'subject',
  'date',
  'message-id',
  'references',
  'reply-to',
  'organization',
};

String _capitalizeHeader(String h) {
  return h.split('-').map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join('-');
}

/// Creates a reply article.
NNTPArticle createReply({
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

/// Creates a followup article (cross-posted reply).
NNTPArticle createFollowup({
  required NNTPArticle original,
  required String from,
  required String body,
  required String newsgroups,
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
    newsgroups: newsgroups,
    organization: organization,
    body: body,
  );
}

/// Validates an article before posting.
///
/// Returns a list of validation errors, empty if valid.
List<String> validateArticle(NNTPArticle article) {
  final errors = <String>[];

  if (article.from.isEmpty) {
    errors.add('From header is required');
  }
  if (article.newsgroups.isEmpty) {
    errors.add('Newsgroups header is required');
  }
  if (article.subject.isEmpty) {
    errors.add('Subject header is required');
  }
  if (article.body.isEmpty) {
    errors.add('Article body cannot be empty');
  }

  // Validate From format
  if (!article.from.contains('@')) {
    errors.add('From header must contain a valid email address');
  }

  // Check for oversized article (most servers have limits)
  final size = article.body.length;
  if (size > 1024 * 1024) {
    // 1MB
    errors.add('Article body exceeds 1MB limit');
  }

  return errors;
}

/// Quotes original article text for reply.
String quoteText(String text, {String prefix = '> '}) {
  return text.split('\n').map((line) => '$prefix$line').join('\n');
}

/// Extracts attribution line for quoting.
///
/// Example: "On 2025-01-30, John Doe wrote:"
String createAttribution(NNTPArticle article) {
  final date = article.date;
  final dateStr =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Extract name from From header
  var name = article.from;
  final angleIdx = name.indexOf('<');
  if (angleIdx > 0) {
    name = name.substring(0, angleIdx).trim().replaceAll('"', '');
  }

  return 'On $dateStr, $name wrote:';
}
