/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Lightweight update notification from a station
/// Format: UPDATE:{callsign}/{collectionType}/{path}
/// Example: UPDATE:X3R5TR/chat/test
class UpdateNotification {
  final String callsign;
  final String collectionType;
  final String path;

  UpdateNotification({
    required this.callsign,
    required this.collectionType,
    required this.path,
  });

  /// Parse an update notification string
  /// Returns null if the format is invalid
  static UpdateNotification? parse(String notification) {
    // Format: UPDATE:{callsign}/{collectionType}/{path}
    if (!notification.startsWith('UPDATE:')) {
      return null;
    }

    final content = notification.substring(7); // Remove "UPDATE:"
    final parts = content.split('/');

    if (parts.length < 3) {
      return null;
    }

    return UpdateNotification(
      callsign: parts[0],
      collectionType: parts[1],
      path: parts.sublist(2).join('/'), // Handle paths with slashes
    );
  }

  @override
  String toString() =>
      'UpdateNotification(callsign: $callsign, type: $collectionType, path: $path)';
}
