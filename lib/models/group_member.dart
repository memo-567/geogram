/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Role in a group
enum GroupRole {
  admin,
  moderator,
  contributor,
  guest;

  static GroupRole fromString(String value) {
    return GroupRole.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => GroupRole.guest,
    );
  }

  String toUpperString() => name.toUpperCase();
}

/// Model representing a group member
class GroupMember {
  final String callsign;
  final String npub;
  final GroupRole role;
  final String joined;
  final String? signature;
  final Map<String, String> metadata;

  GroupMember({
    required this.callsign,
    required this.npub,
    required this.role,
    required this.joined,
    this.signature,
    this.metadata = const {},
  });

  /// Parse joined timestamp to DateTime
  DateTime get joinedDateTime {
    try {
      final normalized = joined.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Check if member is signed
  bool get isSigned => signature != null && signature!.isNotEmpty;

  /// Check if user is admin
  bool get isAdmin => role == GroupRole.admin;

  /// Check if user is moderator or higher
  bool get isModerator => role == GroupRole.moderator || role == GroupRole.admin;

  /// Check if user is contributor or higher
  bool get isContributor =>
      role == GroupRole.contributor || role == GroupRole.moderator || role == GroupRole.admin;

  /// Parse member from members.txt line
  static GroupMember? fromMembersTxt(List<String> lines, int startIndex) {
    if (startIndex >= lines.length) return null;

    final headerLine = lines[startIndex];
    GroupRole? role;
    String? callsign;

    // Parse role line: "ADMIN: CR7BBQ"
    if (headerLine.startsWith('ADMIN: ')) {
      role = GroupRole.admin;
      callsign = headerLine.substring(7).trim();
    } else if (headerLine.startsWith('MODERATOR: ')) {
      role = GroupRole.moderator;
      callsign = headerLine.substring(11).trim();
    } else if (headerLine.startsWith('CONTRIBUTOR: ')) {
      role = GroupRole.contributor;
      callsign = headerLine.substring(13).trim();
    } else if (headerLine.startsWith('GUEST: ')) {
      role = GroupRole.guest;
      callsign = headerLine.substring(7).trim();
    }

    if (role == null || callsign == null || callsign.isEmpty) return null;

    String? npub;
    String? joined;
    String? signature;
    final Map<String, String> metadata = {};

    // Parse metadata lines
    for (int i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('-->')) {
        final metaLine = line.substring(3).trim();
        final colonIndex = metaLine.indexOf(':');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex).trim();
          final value = metaLine.substring(colonIndex + 1).trim();

          if (key == 'npub') {
            npub = value;
          } else if (key == 'joined') {
            joined = value;
          } else if (key == 'signature') {
            signature = value;
          } else {
            metadata[key] = value;
          }
        }
      } else if (line.trim().isEmpty || !line.startsWith('-->')) {
        // End of this member's section
        break;
      }
    }

    if (npub == null || joined == null) return null;

    return GroupMember(
      callsign: callsign,
      npub: npub,
      role: role,
      joined: joined,
      signature: signature,
      metadata: metadata,
    );
  }

  /// Export member as text for members.txt
  String exportAsText() {
    final buffer = StringBuffer();

    buffer.writeln('${role.toUpperString()}: $callsign');
    buffer.writeln('--> npub: $npub');
    buffer.writeln('--> joined: $joined');

    for (var entry in metadata.entries) {
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    if (signature != null && signature!.isNotEmpty) {
      buffer.writeln('--> signature: $signature');
    }

    return buffer.toString();
  }

  /// Create copy with updated fields
  GroupMember copyWith({
    String? callsign,
    String? npub,
    GroupRole? role,
    String? joined,
    String? signature,
    Map<String, String>? metadata,
  }) {
    return GroupMember(
      callsign: callsign ?? this.callsign,
      npub: npub ?? this.npub,
      role: role ?? this.role,
      joined: joined ?? this.joined,
      signature: signature ?? this.signature,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'GroupMember(callsign: $callsign, role: ${role.name})';
  }
}
