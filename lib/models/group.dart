/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'group_member.dart';
import 'group_area.dart';

/// Group types
enum GroupType {
  // Social
  friends,

  // Organizations
  association,

  // Authority
  authorityPolice,
  authorityFire,
  authorityCivilProtection,
  authorityMilitary,

  // Health
  healthHospital,
  healthClinic,
  healthEmergency,

  // Administrative
  adminTownhall,
  adminRegional,
  adminNational,

  // Infrastructure
  infrastructureUtilities,
  infrastructureTransport,

  // Education
  educationSchool,
  educationUniversity,

  // App-specific
  appModerator;

  static GroupType fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('_', '');
    for (var type in GroupType.values) {
      if (type.name.toLowerCase().replaceAll('_', '') == normalized) {
        return type;
      }
    }
    return GroupType.association;
  }

  String toFileString() {
    switch (this) {
      case GroupType.authorityPolice:
        return 'authority_police';
      case GroupType.authorityFire:
        return 'authority_fire';
      case GroupType.authorityCivilProtection:
        return 'authority_civil_protection';
      case GroupType.authorityMilitary:
        return 'authority_military';
      case GroupType.healthHospital:
        return 'health_hospital';
      case GroupType.healthClinic:
        return 'health_clinic';
      case GroupType.healthEmergency:
        return 'health_emergency';
      case GroupType.adminTownhall:
        return 'admin_townhall';
      case GroupType.adminRegional:
        return 'admin_regional';
      case GroupType.adminNational:
        return 'admin_national';
      case GroupType.infrastructureUtilities:
        return 'infrastructure_utilities';
      case GroupType.infrastructureTransport:
        return 'infrastructure_transport';
      case GroupType.educationSchool:
        return 'education_school';
      case GroupType.educationUniversity:
        return 'education_university';
      case GroupType.appModerator:
        return 'app_moderator';
      default:
        return name;
    }
  }
}

/// Model representing a group
class Group {
  final String name;
  final String title;
  final String description;
  final GroupType type;
  final String? appType;
  final String created;
  final String updated;
  final String status;
  final List<GroupMember> members;
  final List<GroupArea> areas;
  final Map<String, dynamic> config;
  final Map<String, String> metadata;

  Group({
    required this.name,
    required this.title,
    required this.description,
    required this.type,
    this.appType,
    required this.created,
    required this.updated,
    this.status = 'active',
    this.members = const [],
    this.areas = const [],
    this.config = const {},
    this.metadata = const {},
  });

  /// Parse timestamp to DateTime
  DateTime get createdDateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse updated timestamp to DateTime
  DateTime get updatedDateTime {
    try {
      final normalized = updated.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Check if group is active
  bool get isActive => status.toLowerCase() == 'active';

  /// Check if group is an app-specific moderator group
  bool get isAppModerator => type == GroupType.appModerator && appType != null;

  /// Get admins
  List<GroupMember> get admins => members.where((m) => m.role == GroupRole.admin).toList();

  /// Get moderators
  List<GroupMember> get moderators => members.where((m) => m.role == GroupRole.moderator).toList();

  /// Get contributors
  List<GroupMember> get contributors => members.where((m) => m.role == GroupRole.contributor).toList();

  /// Get guests
  List<GroupMember> get guests => members.where((m) => m.role == GroupRole.guest).toList();

  /// Get member count
  int get memberCount => members.length;

  /// Get admin count
  int get adminCount => admins.length;

  /// Get moderator count
  int get moderatorCount => moderators.length;

  /// Get contributor count
  int get contributorCount => contributors.length;

  /// Get guest count
  int get guestCount => guests.length;

  /// Get area count
  int get areaCount => areas.length;

  /// Check if user is member
  bool isMember(String npub) {
    if (npub.isEmpty) return false;
    return members.any((m) => m.npub == npub);
  }

  /// Check if user is admin
  bool isAdmin(String npub) {
    if (npub.isEmpty) return false;
    return members.any((m) => m.npub == npub && m.role == GroupRole.admin);
  }

  /// Check if user is moderator or admin
  bool isModerator(String npub) {
    if (npub.isEmpty) return false;
    return members.any((m) =>
      m.npub == npub && (m.role == GroupRole.moderator || m.role == GroupRole.admin));
  }

  /// Check if user is contributor or higher
  bool isContributor(String npub) {
    if (npub.isEmpty) return false;
    return members.any((m) =>
      m.npub == npub && (m.role == GroupRole.contributor || m.role == GroupRole.moderator || m.role == GroupRole.admin));
  }

  /// Get user's role in group
  GroupRole? getUserRole(String npub) {
    if (npub.isEmpty) return null;
    final member = members.firstWhere(
      (m) => m.npub == npub,
      orElse: () => GroupMember(callsign: '', npub: '', role: GroupRole.guest, joined: ''),
    );
    if (member.npub.isEmpty) return null;
    return member.role;
  }

  /// Check if feature is enabled
  bool isFeatureEnabled(String feature) {
    if (!config.containsKey('features')) return false;
    final features = config['features'] as Map<String, dynamic>?;
    if (features == null) return false;
    return features[feature] == true;
  }

  /// Check if user has permission
  bool hasPermission(String permission, String npub) {
    final role = getUserRole(npub);
    if (role == null) return false;

    if (!config.containsKey('permissions')) return false;
    final permissions = config['permissions'] as Map<String, dynamic>?;
    if (permissions == null) return false;

    final allowedRoles = permissions[permission] as List<dynamic>?;
    if (allowedRoles == null) return false;

    return allowedRoles.contains(role.name);
  }

  /// Parse group from group.json
  static Group fromJson(Map<String, dynamic> json, String groupName) {
    final groupData = json['group'] as Map<String, dynamic>;

    return Group(
      name: groupName,
      title: groupData['title'] as String? ?? '',
      description: groupData['description'] as String? ?? '',
      type: GroupType.fromString(groupData['type'] as String? ?? 'association'),
      appType: (groupData['app_type'] ?? groupData['collection_type']) as String?,
      created: groupData['created'] as String? ?? '',
      updated: groupData['updated'] as String? ?? '',
      status: groupData['status'] as String? ?? 'active',
    );
  }

  /// Export group as JSON
  Map<String, dynamic> toJson() {
    return {
      'group': {
        'name': name,
        'title': title,
        'description': description,
        'type': type.toFileString(),
        'app_type': appType,
        'created': created,
        'updated': updated,
        'status': status,
      }
    };
  }

  /// Create copy with updated fields
  Group copyWith({
    String? name,
    String? title,
    String? description,
    GroupType? type,
    String? appType,
    String? created,
    String? updated,
    String? status,
    List<GroupMember>? members,
    List<GroupArea>? areas,
    Map<String, dynamic>? config,
    Map<String, String>? metadata,
  }) {
    return Group(
      name: name ?? this.name,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      appType: appType ?? this.appType,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      status: status ?? this.status,
      members: members ?? this.members,
      areas: areas ?? this.areas,
      config: config ?? this.config,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'Group(name: $name, title: $title, type: ${type.name}, members: ${members.length})';
  }
}
