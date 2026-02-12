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
/// Returns 'unknown' for null values.
String formatTimeAgo(DateTime? dateTime) {
  if (dateTime == null) return 'unknown';
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

/// Format uptime from seconds to short string (e.g., "5s", "3m", "2h", "1d")
String formatUptimeShort(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m';
  if (seconds < 86400) return '${seconds ~/ 3600}h';
  return '${seconds ~/ 86400}d';
}

/// Format uptime from seconds to long string (e.g., "2d 5h", "3h 15m")
String formatUptimeLong(int seconds) {
  if (seconds < 60) return '${seconds}s';

  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;

  final parts = <String>[];
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  if (minutes > 0 && days == 0) parts.add('${minutes}m');

  return parts.isEmpty ? '0m' : parts.join(' ');
}

/// Format uptime from minutes to human readable string (e.g., "2 days 5 hours 30 minutes")
String formatUptimeFromMinutes(int minutes) {
  if (minutes < 1) return '0 minutes';

  final days = minutes ~/ 1440; // 1440 minutes per day
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;

  final parts = <String>[];
  if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
  if (hours > 0) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
  if (mins > 0 && days == 0) parts.add('$mins ${mins == 1 ? 'minute' : 'minutes'}');

  return parts.isEmpty ? '0 minutes' : parts.join(' ');
}
