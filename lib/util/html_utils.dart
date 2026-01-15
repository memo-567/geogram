/// Common HTML utilities shared between Flutter and CLI station servers
/// Pure Dart - no Flutter dependencies

/// Escape HTML entities to prevent XSS
String escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

/// Convert a list of strings to a JSON array string
String toJsonArray(List<String> items) {
  if (items.isEmpty) return '[]';
  final escaped = items.map((s) => '"${s.replaceAll('"', '\\"')}"').join(',');
  return '[$escaped]';
}

/// Format a DateTime as a human-readable "time ago" string with full words
/// Returns strings like "5 minutes ago", "2 hours ago", "3 days ago", etc.
String formatTimeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inDays >= 30) {
    final months = diff.inDays ~/ 30;
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  } else if (diff.inDays >= 7) {
    final weeks = diff.inDays ~/ 7;
    return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
  } else if (diff.inDays > 0) {
    return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  } else if (diff.inHours > 0) {
    return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
  } else if (diff.inMinutes > 0) {
    return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  } else {
    return 'just now';
  }
}
