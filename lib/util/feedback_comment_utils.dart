import 'feedback_folder_utils.dart';
import '../services/profile_storage.dart';

class FeedbackComment {
  final String id;
  final String author;
  final String created;
  final String content;
  final String? npub;
  final String? signature;

  FeedbackComment({
    required this.id,
    required this.author,
    required this.created,
    required this.content,
    this.npub,
    this.signature,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'created': created,
        'content': content,
        if (npub != null && npub!.isNotEmpty) 'npub': npub,
        'has_signature': signature != null && signature!.isNotEmpty,
      };
}

/// Utilities for feedback comment files stored under {contentPath}/feedback/comments.
class FeedbackCommentUtils {
  FeedbackCommentUtils._();

  /// Generate a comment filename in the format: `YYYY-MM-DD_HH-MM-SS_AUTHOR.txt`
  static String generateCommentFilename(DateTime timestamp, String author) {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}_'
        '${timestamp.hour.toString().padLeft(2, '0')}-${timestamp.minute.toString().padLeft(2, '0')}-${timestamp.second.toString().padLeft(2, '0')}_$author.txt';
  }

  /// Generate comment ID (filename without .txt extension).
  static String generateCommentId(DateTime timestamp, String author) {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}_'
        '${timestamp.hour.toString().padLeft(2, '0')}-${timestamp.minute.toString().padLeft(2, '0')}-${timestamp.second.toString().padLeft(2, '0')}_$author';
  }

  /// Validate that a filename follows the comment format.
  static bool isValidCommentFilename(String filename) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_[A-Za-z0-9]+\.txt$').hasMatch(filename);
  }

  /// Format comment file content for writing.
  static String formatCommentFile({
    required String author,
    required String timestamp,
    required String content,
    String? npub,
    String? signature,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('AUTHOR: $author');
    buffer.writeln('CREATED: $timestamp');
    buffer.writeln();
    buffer.writeln(content);

    if (npub != null && npub.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('--> npub: $npub');
    }

    if (signature != null && signature.isNotEmpty) {
      buffer.writeln('--> signature: $signature');
    }

    return buffer.toString();
  }

  /// Parse comment file content.
  static FeedbackComment parseCommentFile(String content, String commentId) {
    final lines = content.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty comment file');
    }

    String? author;
    String? timestamp;
    final contentLines = <String>[];
    String? npub;
    String? signature;
    bool inContent = false;

    for (final line in lines) {
      if (line.startsWith('AUTHOR: ')) {
        author = line.substring(8).trim();
      } else if (line.startsWith('CREATED: ')) {
        timestamp = line.substring(9).trim();
      } else if (line.startsWith('--> ')) {
        final metaLine = line.substring(4).trim();
        final colonIndex = metaLine.indexOf(':');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex).trim();
          final value = metaLine.substring(colonIndex + 1).trim();
          if (key == 'npub') {
            npub = value;
          } else if (key == 'signature') {
            signature = value;
          }
        }
      } else if (line.trim().isEmpty && author != null && timestamp != null && !inContent) {
        inContent = true;
      } else if (inContent && !line.startsWith('--> ')) {
        contentLines.add(line);
      }
    }

    if (author == null || timestamp == null) {
      throw Exception('Invalid comment file: missing AUTHOR or CREATED');
    }

    while (contentLines.isNotEmpty && contentLines.last.trim().isEmpty) {
      contentLines.removeLast();
    }

    return FeedbackComment(
      id: commentId,
      author: author,
      created: timestamp,
      content: contentLines.join('\n').trim(),
      npub: npub,
      signature: signature,
    );
  }

  /// List comment filenames (sorted) for a content item.
  static Future<List<String>> listCommentFiles(
    String contentPath, {
    required ProfileStorage storage,
  }) async {
    final commentsPath = FeedbackFolderUtils.buildCommentsPath(contentPath);
    final entries = await storage.listDirectory(commentsPath);

    final files = <String>[];
    for (final entry in entries) {
      if (!entry.isDirectory && isValidCommentFilename(entry.name)) {
        files.add(entry.name);
      }
    }

    files.sort();
    return files;
  }

  /// Load comments and return them sorted by timestamp (oldest first).
  static Future<List<FeedbackComment>> loadComments(
    String contentPath, {
    required ProfileStorage storage,
  }) async {
    final commentFiles = await listCommentFiles(contentPath, storage: storage);
    final comments = <FeedbackComment>[];
    final commentsDir = FeedbackFolderUtils.buildCommentsPath(contentPath);
    final seenSignatures = <String>{};

    for (final filename in commentFiles) {
      final commentId = filename.replaceAll('.txt', '');
      final filePath = '$commentsDir/$filename';
      try {
        final content = await storage.readString(filePath);
        if (content == null) continue;
        final comment = parseCommentFile(content, commentId);
        final signature = comment.signature;
        if (signature != null && signature.isNotEmpty) {
          if (!seenSignatures.add(signature)) {
            continue;
          }
        }
        comments.add(comment);
      } catch (_) {
        // Skip invalid comment files
      }
    }

    return comments;
  }

  /// Write a comment and return the comment ID.
  static Future<String> writeComment({
    required String contentPath,
    required String author,
    required String content,
    String? npub,
    String? signature,
    required ProfileStorage storage,
  }) async {
    final now = DateTime.now();
    final filename = generateCommentFilename(now, author);
    final commentId = generateCommentId(now, author);

    final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

    final commentContent = formatCommentFile(
      author: author,
      timestamp: timestamp,
      content: content,
      npub: npub,
      signature: signature,
    );

    final commentsPath = FeedbackFolderUtils.buildCommentsPath(contentPath);
    await storage.createDirectory(commentsPath);
    await storage.writeString('$commentsPath/$filename', commentContent);

    return commentId;
  }

  /// Count comment files for a content item.
  static Future<int> getCommentCount(
    String contentPath, {
    required ProfileStorage storage,
  }) async {
    final commentFiles = await listCommentFiles(contentPath, storage: storage);
    return commentFiles.length;
  }

  /// Get a single comment by ID.
  static Future<FeedbackComment?> getComment(
    String contentPath,
    String commentId, {
    required ProfileStorage storage,
  }) async {
    final filename = '$commentId.txt';
    final filePath = '${FeedbackFolderUtils.buildCommentsPath(contentPath)}/$filename';
    final content = await storage.readString(filePath);

    if (content == null) return null;

    try {
      return parseCommentFile(content, commentId);
    } catch (e) {
      return null;
    }
  }

  /// Delete a comment by ID.
  /// Returns true if deleted, false if not found.
  static Future<bool> deleteComment(
    String contentPath,
    String commentId, {
    required ProfileStorage storage,
  }) async {
    final filename = '$commentId.txt';
    final filePath = '${FeedbackFolderUtils.buildCommentsPath(contentPath)}/$filename';

    if (!await storage.exists(filePath)) return false;

    try {
      await storage.delete(filePath);
      return true;
    } catch (e) {
      return false;
    }
  }
}
