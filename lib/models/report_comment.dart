/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Model representing a comment on a report
class ReportComment {
  final String id;
  final String author;
  final String content;
  final String created;
  final String? npub;

  ReportComment({
    required this.id,
    required this.author,
    required this.content,
    required this.created,
    this.npub,
  });

  /// Parse timestamp to DateTime
  DateTime get dateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get formatted date string
  String get displayDate {
    final dt = dateTime;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Parse comment from text file content
  static ReportComment fromText(String text, String fileName) {
    final lines = text.split('\n');

    String? author;
    String? created;
    String? npub;
    final contentLines = <String>[];
    bool inContent = false;

    for (final line in lines) {
      if (line.startsWith('AUTHOR: ')) {
        author = line.substring(8).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('--> npub: ')) {
        npub = line.substring(10).trim();
      } else if (line.trim().isEmpty && author != null && created != null && !inContent) {
        inContent = true;
      } else if (inContent && !line.startsWith('-->')) {
        contentLines.add(line);
      }
    }

    if (author == null || created == null) {
      throw Exception('Missing required comment fields');
    }

    return ReportComment(
      id: fileName.replaceAll('.txt', ''),
      author: author,
      content: contentLines.join('\n').trim(),
      created: created,
      npub: npub,
    );
  }

  /// Export comment as text
  String exportAsText() {
    final buffer = StringBuffer();

    buffer.writeln('AUTHOR: $author');
    buffer.writeln('CREATED: $created');
    buffer.writeln();
    buffer.writeln(content);

    if (npub != null && npub!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('--> npub: $npub');
    }

    return buffer.toString();
  }

  @override
  String toString() {
    return 'ReportComment(id: $id, author: $author, created: $created)';
  }
}
