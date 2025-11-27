/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Model representing a reputation entry for a callsign
class ReputationEntry {
  final String callsign;
  final String npub;
  final int value; // Reputation points
  final String givenBy; // Callsign of person giving reputation
  final String givenByNpub; // npub of person giving reputation
  final String timestamp;
  final String reason;
  final String signature; // Signed by givenByNpub's nsec

  ReputationEntry({
    required this.callsign,
    required this.npub,
    required this.value,
    required this.givenBy,
    required this.givenByNpub,
    required this.timestamp,
    required this.reason,
    required this.signature,
  });

  /// Parse timestamp to DateTime
  DateTime get timestampDateTime {
    try {
      final normalized = timestamp.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Check if entry has valid signature
  bool get isSigned => signature.isNotEmpty;

  /// Parse reputation entry from file content
  static ReputationEntry? fromText(String content, String filename) {
    final lines = content.split('\n');

    String? callsign;
    String? npub;
    int? value;
    String? givenBy;
    String? givenByNpub;
    String? timestamp;
    String? reason;
    String? signature;

    for (var line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('# REPUTATION:')) {
        callsign = trimmed.substring(13).trim();
      } else if (trimmed.startsWith('npub:')) {
        npub = trimmed.substring(5).trim();
      } else if (trimmed.startsWith('value:')) {
        value = int.tryParse(trimmed.substring(6).trim());
      } else if (trimmed.startsWith('given_by:')) {
        givenBy = trimmed.substring(9).trim();
      } else if (trimmed.startsWith('given_by_npub:')) {
        givenByNpub = trimmed.substring(14).trim();
      } else if (trimmed.startsWith('timestamp:')) {
        timestamp = trimmed.substring(10).trim();
      } else if (trimmed.startsWith('reason:')) {
        reason = trimmed.substring(7).trim();
      } else if (trimmed.startsWith('signature:')) {
        signature = trimmed.substring(10).trim();
      }
    }

    if (callsign == null ||
        npub == null ||
        value == null ||
        givenBy == null ||
        givenByNpub == null ||
        timestamp == null ||
        reason == null ||
        signature == null) {
      return null;
    }

    return ReputationEntry(
      callsign: callsign,
      npub: npub,
      value: value,
      givenBy: givenBy,
      givenByNpub: givenByNpub,
      timestamp: timestamp,
      reason: reason,
      signature: signature,
    );
  }

  /// Export reputation entry as text
  String exportAsText() {
    final buffer = StringBuffer();

    buffer.writeln('# REPUTATION: $callsign');
    buffer.writeln('npub: $npub');
    buffer.writeln('value: $value');
    buffer.writeln('given_by: $givenBy');
    buffer.writeln('given_by_npub: $givenByNpub');
    buffer.writeln('timestamp: $timestamp');
    buffer.writeln('reason: $reason');
    buffer.writeln('signature: $signature');

    return buffer.toString();
  }

  @override
  String toString() {
    return 'ReputationEntry(callsign: $callsign, value: $value, givenBy: $givenBy)';
  }
}
