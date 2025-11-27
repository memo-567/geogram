/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'dart:convert';
import '../models/group.dart';
import '../models/group_member.dart';
import '../models/group_area.dart';
import '../models/group_application.dart';
import '../models/reputation_entry.dart';
import '../models/relay_node.dart';
import '../util/nostr_key_generator.dart';
import 'log_service.dart';

/// Service for managing groups
class GroupsService {
  static final GroupsService _instance = GroupsService._internal();
  factory GroupsService() => _instance;
  GroupsService._internal();

  String? _collectionPath;
  final List<String> _admins = [];

  /// Initialize groups service for a collection
  Future<void> initializeCollection(String collectionPath, {String? creatorNpub}) async {
    LogService().log('GroupsService: Initializing with collection path: $collectionPath');
    _collectionPath = collectionPath;

    // Load admins
    await _loadAdmins();

    LogService().log('GroupsService: Initialization complete');
  }

  /// Load collection admins from individual files
  Future<void> _loadAdmins() async {
    if (_collectionPath == null) return;

    final adminsDir = Directory('$_collectionPath/admins');
    if (!await adminsDir.exists()) {
      // Try legacy admins.txt file
      await _loadAdminsLegacy();
      return;
    }

    try {
      _admins.clear();

      final entities = await adminsDir.list().toList();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.txt')) {
          final content = await entity.readAsString();
          final lines = content.split('\n');

          String? npub;
          for (var line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('npub: ')) {
              npub = trimmed.substring(6).trim();
              break;
            }
          }

          if (npub != null && npub.isNotEmpty) {
            _admins.add(npub);
          }
        }
      }

      LogService().log('GroupsService: Loaded ${_admins.length} admins from individual files');
    } catch (e) {
      LogService().log('GroupsService: Error loading admins: $e');
    }
  }

  /// Load admins from legacy admins.txt file
  Future<void> _loadAdminsLegacy() async {
    if (_collectionPath == null) return;

    final adminsFile = File('$_collectionPath/admins.txt');
    if (!await adminsFile.exists()) return;

    try {
      final content = await adminsFile.readAsString();
      final lines = content.split('\n');

      _admins.clear();

      String? currentCallsign;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        // Skip comments and empty lines
        if (line.isEmpty || line.startsWith('#')) continue;

        // Check if line is a callsign (not metadata)
        if (!line.startsWith('-->')) {
          currentCallsign = line;
        } else if (line.startsWith('--> npub:') && currentCallsign != null) {
          final npub = line.substring(9).trim();
          if (npub.isNotEmpty) {
            _admins.add(npub);
          }
        }
      }

      LogService().log('GroupsService: Loaded ${_admins.length} admins from legacy file');
    } catch (e) {
      LogService().log('GroupsService: Error loading legacy admins: $e');
    }
  }

  /// Get collection admins
  List<String> getAdmins() => List.unmodifiable(_admins);

  /// Check if user is collection admin
  bool isCollectionAdmin(String npub) {
    return _admins.contains(npub);
  }

  /// Save admin to individual file
  Future<void> saveAdmin(String callsign, String npub, {String? signature}) async {
    if (_collectionPath == null) return;

    final adminsDir = Directory('$_collectionPath/admins');
    if (!await adminsDir.exists()) {
      await adminsDir.create(recursive: true);
    }

    final adminFile = File('$_collectionPath/admins/$callsign.txt');
    final buffer = StringBuffer();

    buffer.writeln('# ADMIN: $callsign');
    buffer.writeln('npub: $npub');
    buffer.writeln('added: ${_formatTimestamp(DateTime.now())}');
    if (signature != null && signature.isNotEmpty) {
      buffer.writeln('signature: $signature');
    }

    await adminFile.writeAsString(buffer.toString(), flush: true);

    // Add to in-memory list
    if (!_admins.contains(npub)) {
      _admins.add(npub);
    }

    LogService().log('GroupsService: Saved admin $callsign');
  }

  /// Remove admin file
  Future<void> removeAdmin(String callsign, String npub) async {
    if (_collectionPath == null) return;

    final adminFile = File('$_collectionPath/admins/$callsign.txt');
    if (await adminFile.exists()) {
      await adminFile.delete();
    }

    _admins.remove(npub);
    LogService().log('GroupsService: Removed admin $callsign');
  }

  /// Save moderator to individual file (group-specific)
  Future<void> saveModerator(String groupName, String callsign, String npub, {String? signature}) async {
    if (_collectionPath == null) return;

    final moderatorsDir = Directory('$_collectionPath/$groupName/moderators');
    if (!await moderatorsDir.exists()) {
      await moderatorsDir.create(recursive: true);
    }

    final modFile = File('$_collectionPath/$groupName/moderators/$callsign.txt');
    final buffer = StringBuffer();

    buffer.writeln('# MODERATOR: $callsign');
    buffer.writeln('npub: $npub');
    buffer.writeln('added: ${_formatTimestamp(DateTime.now())}');
    if (signature != null && signature.isNotEmpty) {
      buffer.writeln('signature: $signature');
    }

    await modFile.writeAsString(buffer.toString(), flush: true);
    LogService().log('GroupsService: Saved moderator $callsign for group $groupName');
  }

  /// Remove moderator file
  Future<void> removeModerator(String groupName, String callsign) async {
    if (_collectionPath == null) return;

    final modFile = File('$_collectionPath/$groupName/moderators/$callsign.txt');
    if (await modFile.exists()) {
      await modFile.delete();
    }

    LogService().log('GroupsService: Removed moderator $callsign from group $groupName');
  }

  /// Load all groups
  Future<List<Group>> loadGroups() async {
    if (_collectionPath == null) return [];

    final groups = <Group>[];
    final dir = Directory(_collectionPath!);

    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();

    for (var entity in entities) {
      if (entity is Directory) {
        final groupName = entity.path.split('/').last;

        // Skip special directories
        if (groupName == 'extra' || groupName.startsWith('.')) continue;

        try {
          final group = await loadGroup(groupName);
          if (group != null) {
            groups.add(group);
          }
        } catch (e) {
          LogService().log('GroupsService: Error loading group $groupName: $e');
        }
      }
    }

    // Sort by title
    groups.sort((a, b) => a.title.compareTo(b.title));

    LogService().log('GroupsService: Loaded ${groups.length} groups');
    return groups;
  }

  /// Load single group by name
  Future<Group?> loadGroup(String groupName) async {
    if (_collectionPath == null) return null;

    final groupPath = '$_collectionPath/$groupName';
    final groupDir = Directory(groupPath);

    if (!await groupDir.exists()) return null;

    // Load group.json
    final groupFile = File('$groupPath/group.json');
    if (!await groupFile.exists()) {
      LogService().log('GroupsService: group.json not found for $groupName');
      return null;
    }

    try {
      final content = await groupFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      var group = Group.fromJson(json, groupName);

      // Load members
      final members = await loadMembers(groupName);
      group = group.copyWith(members: members);

      // Load areas
      final areas = await loadAreas(groupName);
      group = group.copyWith(areas: areas);

      // Load config
      final config = await loadConfig(groupName);
      if (config != null) {
        group = group.copyWith(config: config);
      }

      return group;
    } catch (e) {
      LogService().log('GroupsService: Error loading group $groupName: $e');
      return null;
    }
  }

  /// Load members for a group
  Future<List<GroupMember>> loadMembers(String groupName) async {
    if (_collectionPath == null) return [];

    final membersFile = File('$_collectionPath/$groupName/members.txt');
    if (!await membersFile.exists()) return [];

    try {
      final content = await membersFile.readAsString();
      final lines = content.split('\n');
      final members = <GroupMember>[];

      int i = 0;
      while (i < lines.length) {
        final line = lines[i].trim();

        // Skip empty lines and comments
        if (line.isEmpty || line.startsWith('#')) {
          i++;
          continue;
        }

        // Check if line starts a member entry
        if (line.startsWith('ADMIN:') ||
            line.startsWith('MODERATOR:') ||
            line.startsWith('CONTRIBUTOR:') ||
            line.startsWith('GUEST:')) {
          final member = GroupMember.fromMembersTxt(lines, i);
          if (member != null) {
            members.add(member);
          }

          // Skip past this member's metadata lines
          i++;
          while (i < lines.length && (lines[i].startsWith('-->') || lines[i].trim().isEmpty)) {
            i++;
          }
        } else {
          i++;
        }
      }

      LogService().log('GroupsService: Loaded ${members.length} members for $groupName');
      return members;
    } catch (e) {
      LogService().log('GroupsService: Error loading members for $groupName: $e');
      return [];
    }
  }

  /// Load areas for a group
  Future<List<GroupArea>> loadAreas(String groupName) async {
    if (_collectionPath == null) return [];

    final areasFile = File('$_collectionPath/$groupName/areas.json');
    if (!await areasFile.exists()) return [];

    try {
      final content = await areasFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final areasData = json['areas'] as List<dynamic>;

      final areas = areasData
          .map((data) => GroupArea.fromJson(data as Map<String, dynamic>))
          .toList();

      LogService().log('GroupsService: Loaded ${areas.length} areas for $groupName');
      return areas;
    } catch (e) {
      LogService().log('GroupsService: Error loading areas for $groupName: $e');
      return [];
    }
  }

  /// Load config for a group
  Future<Map<String, dynamic>?> loadConfig(String groupName) async {
    if (_collectionPath == null) return null;

    final configFile = File('$_collectionPath/$groupName/config.json');
    if (!await configFile.exists()) return null;

    try {
      final content = await configFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      LogService().log('GroupsService: Error loading config for $groupName: $e');
      return null;
    }
  }

  /// Load applications for a group
  Future<List<GroupApplication>> loadApplications(
    String groupName, {
    ApplicationStatus? filterStatus,
  }) async {
    if (_collectionPath == null) return [];

    final applications = <GroupApplication>[];

    // Determine which subdirectories to scan
    final subdirs = <String>[];
    if (filterStatus == null) {
      subdirs.addAll(['pending', 'approved', 'rejected']);
    } else {
      subdirs.add(filterStatus.name);
    }

    for (var subdir in subdirs) {
      final dirPath = '$_collectionPath/$groupName/candidates/$subdir';
      final dir = Directory(dirPath);

      if (!await dir.exists()) continue;

      final entities = await dir.list().toList();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('_application.txt')) {
          try {
            final content = await entity.readAsString();
            final filename = entity.path.split('/').last;
            final application = GroupApplication.fromText(content, filename);
            applications.add(application);
          } catch (e) {
            LogService().log('GroupsService: Error loading application ${entity.path}: $e');
          }
        }
      }
    }

    // Sort by application date (most recent first)
    applications.sort((a, b) => b.appliedDateTime.compareTo(a.appliedDateTime));

    LogService().log('GroupsService: Loaded ${applications.length} applications for $groupName');
    return applications;
  }

  /// Save group
  Future<void> saveGroup(Group group) async {
    if (_collectionPath == null) return;

    final groupPath = '$_collectionPath/${group.name}';
    final groupDir = Directory(groupPath);

    // Create group directory if needed
    if (!await groupDir.exists()) {
      await groupDir.create(recursive: true);
    }

    // Save group.json
    final groupFile = File('$groupPath/group.json');
    await groupFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(group.toJson()),
      flush: true,
    );

    // Save members.txt
    await saveMembers(group.name, group.members);

    // Save areas.json
    await saveAreas(group.name, group.areas);

    // Save config.json
    if (group.config.isNotEmpty) {
      final configFile = File('$groupPath/config.json');
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(group.config),
        flush: true,
      );
    }

    LogService().log('GroupsService: Saved group ${group.name}');
  }

  /// Save members
  Future<void> saveMembers(String groupName, List<GroupMember> members) async {
    if (_collectionPath == null) return;

    final membersFile = File('$_collectionPath/$groupName/members.txt');
    final buffer = StringBuffer();

    // Header (get from group data if available)
    final group = await loadGroup(groupName);
    if (group != null) {
      buffer.writeln('# GROUP: ${group.title}');
      buffer.writeln('# TYPE: ${group.type.toFileString()}');
      if (group.collectionType != null) {
        buffer.writeln('# COLLECTION: ${group.collectionType}');
      }
      buffer.writeln('# Created: ${group.created}');
      buffer.writeln();
    }

    // Write members by role
    final admins = members.where((m) => m.role == GroupRole.admin).toList();
    final moderators = members.where((m) => m.role == GroupRole.moderator).toList();
    final contributors = members.where((m) => m.role == GroupRole.contributor).toList();
    final guests = members.where((m) => m.role == GroupRole.guest).toList();

    for (var member in [...admins, ...moderators, ...contributors, ...guests]) {
      buffer.write(member.exportAsText());
      buffer.writeln();
    }

    await membersFile.writeAsString(buffer.toString(), flush: true);
    LogService().log('GroupsService: Saved ${members.length} members for $groupName');
  }

  /// Save areas
  Future<void> saveAreas(String groupName, List<GroupArea> areas) async {
    if (_collectionPath == null) return;

    final areasFile = File('$_collectionPath/$groupName/areas.json');

    final json = {
      'areas': areas.map((a) => a.toJson()).toList(),
      'updated': _formatTimestamp(DateTime.now()),
    };

    await areasFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );

    LogService().log('GroupsService: Saved ${areas.length} areas for $groupName');
  }

  /// Save application
  Future<void> saveApplication(String groupName, GroupApplication application) async {
    if (_collectionPath == null) return;

    final subdir = application.status.name;
    final dirPath = '$_collectionPath/$groupName/candidates/$subdir';
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('$dirPath/${application.filename}');
    await file.writeAsString(application.exportAsText(), flush: true);

    LogService().log('GroupsService: Saved application ${application.filename} to $subdir');
  }

  /// Move application to different status folder
  Future<void> moveApplication(
    String groupName,
    GroupApplication application,
    ApplicationStatus newStatus,
  ) async {
    if (_collectionPath == null) return;

    // Delete from old location
    final oldSubdir = application.status.name;
    final oldPath = '$_collectionPath/$groupName/candidates/$oldSubdir/${application.filename}';
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      await oldFile.delete();
    }

    // Save to new location
    final updatedApplication = application.copyWith(status: newStatus);
    await saveApplication(groupName, updatedApplication);

    LogService().log('GroupsService: Moved application ${application.filename} from $oldSubdir to ${newStatus.name}');
  }

  /// Create new group
  Future<void> createGroup({
    required String title,
    required String description,
    required GroupType type,
    String? collectionType,
    required String creatorNpub,
    required String creatorCallsign,
  }) async {
    if (_collectionPath == null) return;

    // Generate npub/nsec key pair for the group
    final keys = NostrKeyGenerator.generateKeyPair();
    final groupNpub = keys.npub;
    final groupNsec = keys.nsec;

    final timestamp = _formatTimestamp(DateTime.now());

    final group = Group(
      name: groupNpub,
      title: title,
      description: description,
      type: type,
      collectionType: collectionType,
      created: timestamp,
      updated: timestamp,
      status: 'active',
      members: [
        GroupMember(
          callsign: creatorCallsign,
          npub: creatorNpub,
          role: GroupRole.admin,
          joined: timestamp,
        ),
      ],
      areas: [],
      config: _getDefaultConfig(),
    );

    await saveGroup(group);

    // Save the nsec to security.json
    final groupPath = '$_collectionPath/$groupNpub';
    final securityFile = File('$groupPath/security.json');
    await securityFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'nsec': groupNsec,
        'created': timestamp,
      }),
      flush: true,
    );

    // Create candidate subdirectories
    final candidatesPath = '$_collectionPath/$groupNpub/candidates';
    for (var subdir in ['pending', 'approved', 'rejected']) {
      final dir = Directory('$candidatesPath/$subdir');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    // Create feature directories if enabled
    if (group.isFeatureEnabled('photos')) {
      final photosDir = Directory('$_collectionPath/$groupNpub/photos/.reactions');
      await photosDir.create(recursive: true);
    }

    if (group.isFeatureEnabled('news')) {
      final year = DateTime.now().year;
      final newsDir = Directory('$_collectionPath/$groupNpub/news/$year/files');
      await newsDir.create(recursive: true);
    }

    if (group.isFeatureEnabled('alerts')) {
      await Directory('$_collectionPath/$groupNpub/alerts/active').create(recursive: true);
      await Directory('$_collectionPath/$groupNpub/alerts/archived').create(recursive: true);
    }

    if (group.isFeatureEnabled('chat')) {
      final year = DateTime.now().year;
      final chatDir = Directory('$_collectionPath/$groupNpub/chat/$year/files');
      await chatDir.create(recursive: true);
    }

    LogService().log('GroupsService: Created group $groupNpub');
  }

  /// Get default config for new groups
  Map<String, dynamic> _getDefaultConfig() {
    return {
      'features': {
        'photos': true,
        'news': true,
        'alerts': true,
        'chat': true,
        'comments': true,
      },
      'permissions': {
        'photos_upload': ['admin', 'moderator', 'contributor'],
        'photos_delete': ['admin', 'moderator'],
        'news_publish': ['admin', 'moderator'],
        'news_edit': ['admin', 'moderator'],
        'alerts_issue': ['admin', 'moderator'],
        'alerts_archive': ['admin', 'moderator'],
        'chat_post': ['admin', 'moderator', 'contributor', 'guest'],
        'chat_delete': ['admin', 'moderator'],
        'cross_group_post': ['admin', 'moderator', 'contributor'],
      },
      'chat_settings': {
        'allow_cross_group_posts': true,
        'allow_file_attachments': true,
        'message_retention_days': 365,
      },
      'updated': _formatTimestamp(DateTime.now()),
    };
  }

  /// Format timestamp in geogram format
  String _formatTimestamp(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute\_$second';
  }

  /// Delete group (mark as inactive)
  Future<void> deleteGroup(String groupName) async {
    if (_collectionPath == null) return;

    final group = await loadGroup(groupName);
    if (group == null) return;

    // Mark as inactive instead of deleting (for audit trail)
    final updatedGroup = group.copyWith(
      status: 'inactive',
      updated: _formatTimestamp(DateTime.now()),
    );

    await saveGroup(updatedGroup);
    LogService().log('GroupsService: Marked group $groupName as inactive');
  }

  /// Add member to group
  Future<void> addMember(String groupName, GroupMember member) async {
    final group = await loadGroup(groupName);
    if (group == null) return;

    // Check if member already exists
    final existingIndex = group.members.indexWhere((m) => m.npub == member.npub);
    if (existingIndex >= 0) {
      // Update existing member
      final updatedMembers = List<GroupMember>.from(group.members);
      updatedMembers[existingIndex] = member;
      await saveMembers(groupName, updatedMembers);
    } else {
      // Add new member
      final updatedMembers = [...group.members, member];
      await saveMembers(groupName, updatedMembers);
    }

    LogService().log('GroupsService: Added/updated member ${member.callsign} in $groupName');
  }

  /// Remove member from group
  Future<void> removeMember(String groupName, String npub) async {
    final group = await loadGroup(groupName);
    if (group == null) return;

    final updatedMembers = group.members.where((m) => m.npub != npub).toList();
    await saveMembers(groupName, updatedMembers);

    LogService().log('GroupsService: Removed member with npub $npub from $groupName');
  }

  /// Update member role
  Future<void> updateMemberRole(String groupName, String npub, GroupRole newRole) async {
    final group = await loadGroup(groupName);
    if (group == null) return;

    final updatedMembers = group.members.map((m) {
      if (m.npub == npub) {
        return m.copyWith(role: newRole);
      }
      return m;
    }).toList();

    await saveMembers(groupName, updatedMembers);
    LogService().log('GroupsService: Updated member role in $groupName');
  }

  /// Save reputation entry for a callsign
  Future<void> saveReputationEntry(
    String callsign,
    String npub,
    int value,
    String givenBy,
    String givenByNpub,
    String reason,
    String signature,
  ) async {
    if (_collectionPath == null) return;

    final reputationDir = Directory('$_collectionPath/reputation/$callsign');
    if (!await reputationDir.exists()) {
      await reputationDir.create(recursive: true);
    }

    // Create unique filename with timestamp
    final timestamp = _formatTimestamp(DateTime.now());
    final timestampFile = timestamp.replaceAll(' ', '_').replaceAll(':', '-');
    final entryFile = File('$_collectionPath/reputation/$callsign/${timestampFile}_$givenBy.txt');

    final entry = ReputationEntry(
      callsign: callsign,
      npub: npub,
      value: value,
      givenBy: givenBy,
      givenByNpub: givenByNpub,
      timestamp: timestamp,
      reason: reason,
      signature: signature,
    );

    await entryFile.writeAsString(entry.exportAsText(), flush: true);
    LogService().log('GroupsService: Saved reputation entry for $callsign');
  }

  /// Load all reputation entries for a callsign
  Future<List<ReputationEntry>> loadReputationEntries(String callsign) async {
    if (_collectionPath == null) return [];

    final reputationDir = Directory('$_collectionPath/reputation/$callsign');
    if (!await reputationDir.exists()) return [];

    final entries = <ReputationEntry>[];

    try {
      final files = await reputationDir.list().toList();
      for (var file in files) {
        if (file is File && file.path.endsWith('.txt')) {
          final content = await file.readAsString();
          final filename = file.path.split('/').last;
          final entry = ReputationEntry.fromText(content, filename);
          if (entry != null) {
            entries.add(entry);
          }
        }
      }

      // Sort by timestamp (most recent first)
      entries.sort((a, b) => b.timestampDateTime.compareTo(a.timestampDateTime));

      LogService().log('GroupsService: Loaded ${entries.length} reputation entries for $callsign');
    } catch (e) {
      LogService().log('GroupsService: Error loading reputation for $callsign: $e');
    }

    return entries;
  }

  /// Get total reputation score for a callsign
  Future<int> getReputationScore(String callsign) async {
    final entries = await loadReputationEntries(callsign);
    return entries.fold<int>(0, (sum, entry) => sum + entry.value);
  }

  /// Save relay network topology to sync folder
  Future<void> saveNetworkTopology(List<RelayNode> nodes) async {
    if (_collectionPath == null) return;

    final syncDir = Directory('$_collectionPath/sync');
    if (!await syncDir.exists()) {
      await syncDir.create(recursive: true);
    }

    final topologyFile = File('$_collectionPath/sync/network_topology.json');
    final json = {
      'updated': DateTime.now().toIso8601String(),
      'nodes': nodes.map((n) => n.toJson()).toList(),
    };

    await topologyFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );

    LogService().log('GroupsService: Saved network topology with ${nodes.length} nodes');
  }

  /// Load relay network topology from sync folder
  Future<List<RelayNode>> loadNetworkTopology() async {
    if (_collectionPath == null) return [];

    final topologyFile = File('$_collectionPath/sync/network_topology.json');
    if (!await topologyFile.exists()) return [];

    try {
      final content = await topologyFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final nodesData = json['nodes'] as List<dynamic>;

      final nodes = nodesData
          .map((data) => RelayNode.fromJson(data as Map<String, dynamic>))
          .toList();

      LogService().log('GroupsService: Loaded network topology with ${nodes.length} nodes');
      return nodes;
    } catch (e) {
      LogService().log('GroupsService: Error loading network topology: $e');
      return [];
    }
  }

  /// Save collection approval status for a user collection
  Future<void> saveCollectionApproval(
    String userNpub,
    String collectionType,
    String status, // 'approved', 'rejected', 'pending'
    {String? reason}
  ) async {
    if (_collectionPath == null) return;

    final approvalsDir = Directory('$_collectionPath/approvals/$collectionType');
    if (!await approvalsDir.exists()) {
      await approvalsDir.create(recursive: true);
    }

    final approvalFile = File('$_collectionPath/approvals/$collectionType/$userNpub.json');
    final json = {
      'npub': userNpub,
      'collection_type': collectionType,
      'status': status,
      if (reason != null) 'reason': reason,
      'updated': DateTime.now().toIso8601String(),
    };

    await approvalFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );

    LogService().log('GroupsService: Saved collection approval: $userNpub/$collectionType = $status');
  }

  /// Load collection approval status
  Future<Map<String, dynamic>?> loadCollectionApproval(
    String userNpub,
    String collectionType,
  ) async {
    if (_collectionPath == null) return null;

    final approvalFile = File('$_collectionPath/approvals/$collectionType/$userNpub.json');
    if (!await approvalFile.exists()) return null;

    try {
      final content = await approvalFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      LogService().log('GroupsService: Error loading collection approval: $e');
      return null;
    }
  }

  /// Check if collection is approved for user
  Future<bool> isCollectionApproved(String userNpub, String collectionType) async {
    final approval = await loadCollectionApproval(userNpub, collectionType);
    return approval?['status'] == 'approved';
  }

  /// Get all pending approvals for a collection type
  Future<List<Map<String, dynamic>>> getPendingApprovals(String collectionType) async {
    if (_collectionPath == null) return [];

    final approvals = <Map<String, dynamic>>[];
    final approvalsDir = Directory('$_collectionPath/approvals/$collectionType');
    if (!await approvalsDir.exists()) return [];

    try {
      final entities = await approvalsDir.list().toList();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          if (data['status'] == 'pending') {
            approvals.add(data);
          }
        }
      }
    } catch (e) {
      LogService().log('GroupsService: Error loading pending approvals: $e');
    }

    return approvals;
  }
}
