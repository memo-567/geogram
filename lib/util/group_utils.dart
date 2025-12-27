/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Shared helpers for group identifiers and timestamps.
class GroupUtils {
  /// Normalize a group name into a directory-safe identifier.
  /// Keeps lowercase letters, numbers, underscores, and dashes.
  static String sanitizeGroupName(String input) {
    var sanitized = input.trim().toLowerCase();
    sanitized = sanitized.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    sanitized = sanitized.replaceAll(RegExp(r'-{2,}'), '-');
    sanitized = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');

    if (sanitized.isEmpty) {
      sanitized = 'group';
    }

    if (sanitized.length > 64) {
      sanitized = sanitized.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    }

    return sanitized;
  }

  /// Format timestamp in geogram format (YYYY-MM-DD HH:MM_ss).
  static String formatTimestamp(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute\_$second';
  }
}
