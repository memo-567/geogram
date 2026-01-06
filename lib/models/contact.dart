/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Types of contact history entries
enum ContactHistoryEntryType {
  note,      // Regular note
  meeting,   // Met in person
  call,      // Phone/video call
  message,   // Communication exchange
  location,  // Location-related note
  event,     // Related to an event
  system,    // System-generated entry (e.g., identity change)
}

/// Represents a single entry in the contact's history log
class ContactHistoryEntry implements Comparable<ContactHistoryEntry> {
  /// Author's callsign
  final String author;

  /// Timestamp in format: YYYY-MM-DD HH:MM_ss
  final String timestamp;

  /// Entry content
  final String content;

  /// Entry type
  final ContactHistoryEntryType type;

  /// Optional metadata (location coords, event reference, etc.)
  final Map<String, String> metadata;

  ContactHistoryEntry({
    required this.author,
    required this.timestamp,
    required this.content,
    this.type = ContactHistoryEntryType.note,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? {};

  /// Create entry from current time
  factory ContactHistoryEntry.now({
    required String author,
    required String content,
    ContactHistoryEntryType type = ContactHistoryEntryType.note,
    double? latitude,
    double? longitude,
    String? eventReference,
    Map<String, String>? metadata,
  }) {
    final now = DateTime.now();
    final timestamp = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}_'
        '${now.second.toString().padLeft(2, '0')}';

    final meta = <String, String>{...?metadata};
    if (latitude != null) meta['lat'] = latitude.toString();
    if (longitude != null) meta['lon'] = longitude.toString();
    if (eventReference != null) meta['event'] = eventReference;

    return ContactHistoryEntry(
      author: author,
      timestamp: timestamp,
      content: content,
      type: type,
      metadata: meta,
    );
  }

  /// Get latitude from metadata
  double? get latitude {
    final lat = metadata['lat'];
    if (lat == null) return null;
    return double.tryParse(lat);
  }

  /// Get longitude from metadata
  double? get longitude {
    final lon = metadata['lon'];
    if (lon == null) return null;
    return double.tryParse(lon);
  }

  /// Get event reference from metadata
  String? get eventReference => metadata['event'];

  /// Check if has location
  bool get hasLocation => latitude != null && longitude != null;

  /// Parse timestamp to DateTime
  DateTime get timestampDateTime {
    try {
      final normalized = timestamp.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get display timestamp
  String get displayTimestamp => timestamp.replaceAll('_', ':');

  /// Get type name for display
  String get typeName => type.name;

  /// Export as text for file storage
  String exportAsText() {
    final buffer = StringBuffer();
    buffer.writeln('> $timestamp -- $author');
    buffer.writeln('--> type: ${type.name}');

    // Write metadata
    for (final entry in metadata.entries) {
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    // Write content (preserve multi-line)
    buffer.write(content);

    return buffer.toString();
  }

  /// Parse from text format
  static ContactHistoryEntry? parseFromText(String block) {
    final lines = block.split('\n');
    if (lines.isEmpty) return null;

    // Parse header: > YYYY-MM-DD HH:MM_ss -- CALLSIGN
    final headerMatch = RegExp(r'^>\s*(.+?)\s*--\s*(.+)$').firstMatch(lines[0].trim());
    if (headerMatch == null) return null;

    final timestamp = headerMatch.group(1)!.trim();
    final author = headerMatch.group(2)!.trim();

    var type = ContactHistoryEntryType.note;
    final metadata = <String, String>{};
    final contentLines = <String>[];
    bool inContent = false;

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('--> ')) {
        // Parse metadata line
        final metaLine = trimmed.substring(4);
        final colonIndex = metaLine.indexOf(':');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex).trim();
          final value = metaLine.substring(colonIndex + 1).trim();

          if (key == 'type') {
            type = ContactHistoryEntryType.values.firstWhere(
              (t) => t.name == value,
              orElse: () => ContactHistoryEntryType.note,
            );
          } else if (key != 'npub' && key != 'signature') {
            // Skip npub/signature for individual entries
            metadata[key] = value;
          }
        }
      } else {
        // Content line
        inContent = true;
        contentLines.add(line);
      }
    }

    return ContactHistoryEntry(
      author: author,
      timestamp: timestamp,
      content: contentLines.join('\n').trim(),
      type: type,
      metadata: metadata,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'author': author,
        'timestamp': timestamp,
        'content': content,
        'type': type.name,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  /// Create from JSON
  factory ContactHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ContactHistoryEntry(
      author: json['author'] as String,
      timestamp: json['timestamp'] as String,
      content: json['content'] as String,
      type: ContactHistoryEntryType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ContactHistoryEntryType.note,
      ),
      metadata: json['metadata'] != null
          ? Map<String, String>.from(json['metadata'] as Map)
          : null,
    );
  }

  @override
  int compareTo(ContactHistoryEntry other) {
    // Sort by timestamp descending (newest first)
    return other.timestamp.compareTo(timestamp);
  }
}

/// Location type for contact locations
enum ContactLocationType { coordinates, place, online }

/// Model representing a contact location for postcard delivery
class ContactLocation {
  final String name;
  final ContactLocationType type;
  final double? latitude;
  final double? longitude;
  final String? placePath; // Path to place folder for 'place' type

  ContactLocation({
    required this.name,
    this.type = ContactLocationType.coordinates,
    this.latitude,
    this.longitude,
    this.placePath,
  });

  /// Get display string for location
  String get displayString {
    if (type == ContactLocationType.online) {
      return '$name (online)';
    }
    if (type == ContactLocationType.place && placePath != null) {
      return '$name (place)';
    }
    if (latitude != null && longitude != null) {
      return '$name ($latitude,$longitude)';
    }
    return name;
  }

  /// Get type as string
  String get typeString {
    switch (type) {
      case ContactLocationType.coordinates:
        return 'coordinates';
      case ContactLocationType.place:
        return 'place';
      case ContactLocationType.online:
        return 'online';
    }
  }

  /// Parse type from string
  static ContactLocationType parseType(String? typeStr) {
    switch (typeStr) {
      case 'place':
        return ContactLocationType.place;
      case 'online':
        return ContactLocationType.online;
      default:
        return ContactLocationType.coordinates;
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'name': name,
        'type': typeString,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (placePath != null) 'placePath': placePath,
      };

  /// Create from JSON
  factory ContactLocation.fromJson(Map<String, dynamic> json) {
    return ContactLocation(
      name: json['name'] as String,
      type: parseType(json['type'] as String?),
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      placePath: json['placePath'] as String?,
    );
  }

  /// Copy with new values
  ContactLocation copyWith({
    String? name,
    ContactLocationType? type,
    double? latitude,
    double? longitude,
    String? placePath,
  }) {
    return ContactLocation(
      name: name ?? this.name,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placePath: placePath ?? this.placePath,
    );
  }
}

/// Model representing a contact (person or machine)
class Contact {
  final String displayName;
  final String callsign;
  final String? npub; // Optional - can be null for imported contacts
  final String created; // Format: YYYY-MM-DD HH:MM_ss
  final String firstSeen; // Format: YYYY-MM-DD HH:MM_ss

  // Optional contact information
  final List<String> emails;
  final List<String> phones;
  final List<String> addresses;
  final List<String> websites;
  final List<ContactLocation> locations;
  final Map<String, String> socialHandles; // network_id -> handle
  final String? profilePicture;

  // Tags for categorization
  final List<String> tags;

  // Radio amateur callsigns (for different jurisdictions)
  final List<String> radioCallsigns;

  // Temporary identity (for imported contacts without NOSTR)
  final bool isTemporaryIdentity;
  final String? temporaryNsec; // Stored encrypted in file

  // Identity management
  final bool revoked;
  final String? revocationReason;
  final String? successor; // Callsign or npub
  final String? successorSince; // Format: YYYY-MM-DD HH:MM_ss
  final String? previousIdentity; // Callsign or npub
  final String? previousIdentitySince; // Format: YYYY-MM-DD HH:MM_ss

  // History log entries
  final List<ContactHistoryEntry> historyEntries;

  // Legacy notes (for backward compatibility, computed from first entry)
  final String notes;

  // Metadata
  final String? metadataNpub;
  final String? signature;

  // File path (for editing)
  final String? filePath;
  final String? groupPath; // Relative path within contacts/ (e.g., "family", "", "work/engineering")

  Contact({
    required this.displayName,
    required this.callsign,
    this.npub,
    required this.created,
    required this.firstSeen,
    this.emails = const [],
    this.phones = const [],
    this.addresses = const [],
    this.websites = const [],
    this.locations = const [],
    this.socialHandles = const {},
    this.profilePicture,
    this.tags = const [],
    this.radioCallsigns = const [],
    this.isTemporaryIdentity = false,
    this.temporaryNsec,
    this.revoked = false,
    this.revocationReason,
    this.successor,
    this.successorSince,
    this.previousIdentity,
    this.previousIdentitySince,
    this.historyEntries = const [],
    this.notes = '',
    this.metadataNpub,
    this.signature,
    this.filePath,
    this.groupPath,
  });

  /// Parse created timestamp to DateTime
  DateTime get createdDateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse firstSeen timestamp to DateTime
  DateTime get firstSeenDateTime {
    try {
      final normalized = firstSeen.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse successorSince timestamp to DateTime
  DateTime? get successorSinceDateTime {
    if (successorSince == null) return null;
    try {
      final normalized = successorSince!.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Parse previousIdentitySince timestamp to DateTime
  DateTime? get previousIdentitySinceDateTime {
    if (previousIdentitySince == null) return null;
    try {
      final normalized = previousIdentitySince!.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Get display timestamp (formatted for UI)
  String get displayCreated => created.replaceAll('_', ':');
  String get displayFirstSeen => firstSeen.replaceAll('_', ':');
  String? get displaySuccessorSince => successorSince?.replaceAll('_', ':');
  String? get displayPreviousIdentitySince => previousIdentitySince?.replaceAll('_', ':');

  /// Get filename for this contact
  String get filename => '$callsign.txt';

  /// Get profile picture path relative to media/ folder
  String? get profilePicturePath {
    if (profilePicture == null) return null;
    return 'media/$profilePicture';
  }

  /// Check if contact has a valid NOSTR identity
  bool get hasIdentity => npub != null && npub!.isNotEmpty;

  /// Check if contact needs identity upgrade (has temp identity)
  bool get needsIdentityUpgrade => isTemporaryIdentity && temporaryNsec != null;

  /// Get combined notes from all history entries
  String get combinedNotes {
    if (historyEntries.isEmpty) return notes;
    return historyEntries.map((e) => e.content).join('\n\n');
  }

  /// Check if this is a machine contact (heuristic based on notes/history or tags)
  bool get isProbablyMachine {
    // Check tags first
    if (tags.any((t) => ['machine', 'device', 'iot', 'bot', 'server'].contains(t.toLowerCase()))) {
      return true;
    }
    // Then check notes
    final lowerNotes = combinedNotes.toLowerCase();
    return lowerNotes.contains('machine') ||
        lowerNotes.contains('device') ||
        lowerNotes.contains('iot') ||
        lowerNotes.contains('bot') ||
        lowerNotes.contains('server');
  }

  /// Get group display name
  String get groupDisplayName {
    if (groupPath == null || groupPath!.isEmpty) {
      return 'All Contacts';
    }
    return groupPath!.split('/').last;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'callsign': callsign,
        if (npub != null) 'npub': npub,
        'created': created,
        'firstSeen': firstSeen,
        if (emails.isNotEmpty) 'emails': emails,
        if (phones.isNotEmpty) 'phones': phones,
        if (addresses.isNotEmpty) 'addresses': addresses,
        if (websites.isNotEmpty) 'websites': websites,
        if (locations.isNotEmpty) 'locations': locations.map((l) => l.toJson()).toList(),
        if (socialHandles.isNotEmpty) 'socialHandles': socialHandles,
        if (profilePicture != null) 'profilePicture': profilePicture,
        if (tags.isNotEmpty) 'tags': tags,
        if (radioCallsigns.isNotEmpty) 'radioCallsigns': radioCallsigns,
        if (isTemporaryIdentity) 'isTemporaryIdentity': isTemporaryIdentity,
        if (temporaryNsec != null) 'temporaryNsec': temporaryNsec,
        'revoked': revoked,
        if (revocationReason != null) 'revocationReason': revocationReason,
        if (successor != null) 'successor': successor,
        if (successorSince != null) 'successorSince': successorSince,
        if (previousIdentity != null) 'previousIdentity': previousIdentity,
        if (previousIdentitySince != null) 'previousIdentitySince': previousIdentitySince,
        if (historyEntries.isNotEmpty) 'historyEntries': historyEntries.map((e) => e.toJson()).toList(),
        if (notes.isNotEmpty) 'notes': notes,
        if (metadataNpub != null) 'metadataNpub': metadataNpub,
        if (signature != null) 'signature': signature,
        if (filePath != null) 'filePath': filePath,
        if (groupPath != null) 'groupPath': groupPath,
      };

  /// Create from JSON
  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      displayName: json['displayName'] as String,
      callsign: json['callsign'] as String,
      npub: json['npub'] as String?,
      created: json['created'] as String,
      firstSeen: json['firstSeen'] as String,
      emails: json['emails'] != null ? List<String>.from(json['emails'] as List) : const [],
      phones: json['phones'] != null ? List<String>.from(json['phones'] as List) : const [],
      addresses: json['addresses'] != null ? List<String>.from(json['addresses'] as List) : const [],
      websites: json['websites'] != null ? List<String>.from(json['websites'] as List) : const [],
      locations: json['locations'] != null
          ? (json['locations'] as List).map((l) => ContactLocation.fromJson(l as Map<String, dynamic>)).toList()
          : const [],
      socialHandles: json['socialHandles'] != null
          ? Map<String, String>.from(json['socialHandles'] as Map)
          : const {},
      profilePicture: json['profilePicture'] as String?,
      tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : const [],
      radioCallsigns: json['radioCallsigns'] != null ? List<String>.from(json['radioCallsigns'] as List) : const [],
      isTemporaryIdentity: json['isTemporaryIdentity'] as bool? ?? false,
      temporaryNsec: json['temporaryNsec'] as String?,
      revoked: json['revoked'] as bool? ?? false,
      revocationReason: json['revocationReason'] as String?,
      successor: json['successor'] as String?,
      successorSince: json['successorSince'] as String?,
      previousIdentity: json['previousIdentity'] as String?,
      previousIdentitySince: json['previousIdentitySince'] as String?,
      historyEntries: json['historyEntries'] != null
          ? (json['historyEntries'] as List).map((e) => ContactHistoryEntry.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
      notes: json['notes'] as String? ?? '',
      metadataNpub: json['metadataNpub'] as String?,
      signature: json['signature'] as String?,
      filePath: json['filePath'] as String?,
      groupPath: json['groupPath'] as String?,
    );
  }

  /// Create a copy with updated fields
  Contact copyWith({
    String? displayName,
    String? callsign,
    String? npub,
    String? created,
    String? firstSeen,
    List<String>? emails,
    List<String>? phones,
    List<String>? addresses,
    List<String>? websites,
    List<ContactLocation>? locations,
    Map<String, String>? socialHandles,
    String? profilePicture,
    List<String>? tags,
    List<String>? radioCallsigns,
    bool? isTemporaryIdentity,
    String? temporaryNsec,
    bool? revoked,
    String? revocationReason,
    String? successor,
    String? successorSince,
    String? previousIdentity,
    String? previousIdentitySince,
    List<ContactHistoryEntry>? historyEntries,
    String? notes,
    String? metadataNpub,
    String? signature,
    String? filePath,
    String? groupPath,
  }) {
    return Contact(
      displayName: displayName ?? this.displayName,
      callsign: callsign ?? this.callsign,
      npub: npub ?? this.npub,
      created: created ?? this.created,
      firstSeen: firstSeen ?? this.firstSeen,
      emails: emails ?? this.emails,
      phones: phones ?? this.phones,
      addresses: addresses ?? this.addresses,
      websites: websites ?? this.websites,
      locations: locations ?? this.locations,
      socialHandles: socialHandles ?? this.socialHandles,
      profilePicture: profilePicture ?? this.profilePicture,
      tags: tags ?? this.tags,
      radioCallsigns: radioCallsigns ?? this.radioCallsigns,
      isTemporaryIdentity: isTemporaryIdentity ?? this.isTemporaryIdentity,
      temporaryNsec: temporaryNsec ?? this.temporaryNsec,
      revoked: revoked ?? this.revoked,
      revocationReason: revocationReason ?? this.revocationReason,
      successor: successor ?? this.successor,
      successorSince: successorSince ?? this.successorSince,
      previousIdentity: previousIdentity ?? this.previousIdentity,
      previousIdentitySince: previousIdentitySince ?? this.previousIdentitySince,
      historyEntries: historyEntries ?? this.historyEntries,
      notes: notes ?? this.notes,
      metadataNpub: metadataNpub ?? this.metadataNpub,
      signature: signature ?? this.signature,
      filePath: filePath ?? this.filePath,
      groupPath: groupPath ?? this.groupPath,
    );
  }
}

/// Model representing a contact group (folder)
class ContactGroup {
  final String name; // Folder name (e.g., "family", "work")
  final String path; // Full path relative to contacts/ (e.g., "family", "work/engineering")
  final String? description;
  final String? created;
  final String? author;
  final int contactCount;

  ContactGroup({
    required this.name,
    required this.path,
    this.description,
    this.created,
    this.author,
    this.contactCount = 0,
  });

  /// Parse created timestamp to DateTime
  DateTime? get createdDateTime {
    if (created == null) return null;
    try {
      final normalized = created!.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Get display timestamp
  String? get displayCreated => created?.replaceAll('_', ':');

  /// Get filename for group metadata
  String get metadataFilename => 'group.txt';

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        if (description != null) 'description': description,
        if (created != null) 'created': created,
        if (author != null) 'author': author,
        'contactCount': contactCount,
      };

  /// Create from JSON
  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      name: json['name'] as String,
      path: json['path'] as String,
      description: json['description'] as String?,
      created: json['created'] as String?,
      author: json['author'] as String?,
      contactCount: json['contactCount'] as int? ?? 0,
    );
  }
}
