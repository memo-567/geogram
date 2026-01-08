/// Visibility levels for tracker items
enum TrackerVisibilityLevel {
  /// Only the owner can access (default)
  private,

  /// Anyone can view
  public,

  /// Only accessible via link with secret ID
  unlisted,

  /// Specific contacts and/or groups can access
  restricted,
}

/// Contact allowed to access restricted content
class AllowedContact {
  final String callsign;
  final String npub;
  final String addedAt;

  const AllowedContact({
    required this.callsign,
    required this.npub,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        'npub': npub,
        'added_at': addedAt,
      };

  factory AllowedContact.fromJson(Map<String, dynamic> json) {
    return AllowedContact(
      callsign: json['callsign'] as String,
      npub: json['npub'] as String,
      addedAt: json['added_at'] as String,
    );
  }
}

/// Group allowed to access restricted content
class AllowedGroup {
  final String groupId;
  final String groupName;
  final String addedAt;

  const AllowedGroup({
    required this.groupId,
    required this.groupName,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'group_name': groupName,
        'added_at': addedAt,
      };

  factory AllowedGroup.fromJson(Map<String, dynamic> json) {
    return AllowedGroup(
      groupId: json['group_id'] as String,
      groupName: json['group_name'] as String,
      addedAt: json['added_at'] as String,
    );
  }
}

/// Previously used unlisted ID that has been invalidated
class PreviousUnlistedId {
  final String id;
  final String invalidatedAt;

  const PreviousUnlistedId({
    required this.id,
    required this.invalidatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'invalidated_at': invalidatedAt,
      };

  factory PreviousUnlistedId.fromJson(Map<String, dynamic> json) {
    return PreviousUnlistedId(
      id: json['id'] as String,
      invalidatedAt: json['invalidated_at'] as String,
    );
  }
}

/// Visibility settings for tracker items
class TrackerVisibility {
  final TrackerVisibilityLevel level;

  /// For unlisted: the secret ID required to access
  final String? unlistedId;

  /// When the unlisted ID was created
  final String? unlistedIdCreatedAt;

  /// Previously used unlisted IDs (for tracking invalidated links)
  final List<PreviousUnlistedId> previousUnlistedIds;

  /// For restricted: contacts allowed to access
  final List<AllowedContact> allowedContacts;

  /// For restricted: groups allowed to access
  final List<AllowedGroup> allowedGroups;

  const TrackerVisibility({
    this.level = TrackerVisibilityLevel.private,
    this.unlistedId,
    this.unlistedIdCreatedAt,
    this.previousUnlistedIds = const [],
    this.allowedContacts = const [],
    this.allowedGroups = const [],
  });

  /// Default private visibility
  static const TrackerVisibility private = TrackerVisibility(
    level: TrackerVisibilityLevel.private,
  );

  /// Public visibility
  static const TrackerVisibility public = TrackerVisibility(
    level: TrackerVisibilityLevel.public,
  );

  /// Create unlisted visibility with a new ID
  factory TrackerVisibility.unlisted({
    required String unlistedId,
    required String createdAt,
    List<PreviousUnlistedId> previousIds = const [],
  }) {
    return TrackerVisibility(
      level: TrackerVisibilityLevel.unlisted,
      unlistedId: unlistedId,
      unlistedIdCreatedAt: createdAt,
      previousUnlistedIds: previousIds,
    );
  }

  /// Create restricted visibility
  factory TrackerVisibility.restricted({
    List<AllowedContact> contacts = const [],
    List<AllowedGroup> groups = const [],
  }) {
    return TrackerVisibility(
      level: TrackerVisibilityLevel.restricted,
      allowedContacts: contacts,
      allowedGroups: groups,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'level': level.name,
    };

    if (level == TrackerVisibilityLevel.unlisted) {
      if (unlistedId != null) json['unlisted_id'] = unlistedId;
      if (unlistedIdCreatedAt != null) {
        json['unlisted_id_created_at'] = unlistedIdCreatedAt;
      }
      if (previousUnlistedIds.isNotEmpty) {
        json['previous_unlisted_ids'] =
            previousUnlistedIds.map((p) => p.toJson()).toList();
      }
    }

    if (level == TrackerVisibilityLevel.restricted) {
      if (allowedContacts.isNotEmpty) {
        json['allowed_contacts'] =
            allowedContacts.map((c) => c.toJson()).toList();
      }
      if (allowedGroups.isNotEmpty) {
        json['allowed_groups'] = allowedGroups.map((g) => g.toJson()).toList();
      }
    }

    return json;
  }

  factory TrackerVisibility.fromJson(Map<String, dynamic> json) {
    final levelStr = json['level'] as String? ?? 'private';
    final level = TrackerVisibilityLevel.values.firstWhere(
      (l) => l.name == levelStr,
      orElse: () => TrackerVisibilityLevel.private,
    );

    return TrackerVisibility(
      level: level,
      unlistedId: json['unlisted_id'] as String?,
      unlistedIdCreatedAt: json['unlisted_id_created_at'] as String?,
      previousUnlistedIds: (json['previous_unlisted_ids'] as List<dynamic>?)
              ?.map((p) =>
                  PreviousUnlistedId.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      allowedContacts: (json['allowed_contacts'] as List<dynamic>?)
              ?.map((c) => AllowedContact.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      allowedGroups: (json['allowed_groups'] as List<dynamic>?)
              ?.map((g) => AllowedGroup.fromJson(g as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  TrackerVisibility copyWith({
    TrackerVisibilityLevel? level,
    String? unlistedId,
    String? unlistedIdCreatedAt,
    List<PreviousUnlistedId>? previousUnlistedIds,
    List<AllowedContact>? allowedContacts,
    List<AllowedGroup>? allowedGroups,
  }) {
    return TrackerVisibility(
      level: level ?? this.level,
      unlistedId: unlistedId ?? this.unlistedId,
      unlistedIdCreatedAt: unlistedIdCreatedAt ?? this.unlistedIdCreatedAt,
      previousUnlistedIds: previousUnlistedIds ?? this.previousUnlistedIds,
      allowedContacts: allowedContacts ?? this.allowedContacts,
      allowedGroups: allowedGroups ?? this.allowedGroups,
    );
  }

  /// Check if a contact has access
  bool hasAccess(String callsign, List<String> userGroupIds) {
    switch (level) {
      case TrackerVisibilityLevel.private:
        return false; // Only owner, checked elsewhere
      case TrackerVisibilityLevel.public:
        return true;
      case TrackerVisibilityLevel.unlisted:
        return false; // Requires key, checked elsewhere
      case TrackerVisibilityLevel.restricted:
        // Check if contact is in allowed list
        if (allowedContacts.any((c) => c.callsign == callsign)) {
          return true;
        }
        // Check if any of user's groups are allowed
        for (final group in allowedGroups) {
          if (userGroupIds.contains(group.groupId)) {
            return true;
          }
        }
        return false;
    }
  }

  /// Validate unlisted key
  bool validateUnlistedKey(String key) {
    if (level != TrackerVisibilityLevel.unlisted) return false;
    return unlistedId == key;
  }
}
