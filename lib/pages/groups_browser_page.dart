/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/group.dart';
import '../models/group_member.dart';
import '../services/collection_service.dart';
import '../services/groups_service.dart';
import '../services/group_sync_service.dart';
import '../services/profile_service.dart';
import '../services/profile_storage.dart';
import '../services/i18n_service.dart';
import 'group_detail_page.dart';

/// Groups browser page
class GroupsBrowserPage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;

  const GroupsBrowserPage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
  });

  @override
  State<GroupsBrowserPage> createState() => _GroupsBrowserPageState();
}

class _GroupsBrowserPageState extends State<GroupsBrowserPage> {
  final GroupsService _groupsService = GroupsService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();
  final TextEditingController _searchController = TextEditingController();

  List<Group> _allGroups = [];
  List<Group> _filteredGroups = [];
  GroupType? _filterType;
  bool _isLoading = true;
  bool _showOnlyMyGroups = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterGroups);
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Set profile storage for encrypted storage support
    final profileStorage = CollectionService().profileStorage;
    if (profileStorage != null) {
      final scopedStorage = ScopedProfileStorage.fromAbsolutePath(
        profileStorage,
        widget.collectionPath,
      );
      _groupsService.setStorage(scopedStorage);
    } else {
      _groupsService.setStorage(FilesystemProfileStorage(widget.collectionPath));
    }

    final currentProfile = _profileService.getProfile();
    await _groupsService.initializeCollection(
      widget.collectionPath,
      creatorNpub: currentProfile.npub,
    );
    if (_groupsService.isCollectionAdmin(currentProfile.npub)) {
      await GroupSyncService().syncGroupsCollection(
        groupsCollectionPath: widget.collectionPath,
      );
    }
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);

    _allGroups = await _groupsService.loadGroups();

    setState(() {
      _filteredGroups = _allGroups;
      _isLoading = false;
    });

    _filterGroups();
  }

  void _filterGroups() {
    final query = _searchController.text.toLowerCase();
    final currentProfile = _profileService.getProfile();

    setState(() {
      _filteredGroups = _allGroups.where((group) {
        // Filter by type
        if (_filterType != null && group.type != _filterType) {
          return false;
        }

        // Filter by "my groups" toggle
        if (_showOnlyMyGroups) {
          if (!group.isMember(currentProfile.npub)) {
            return false;
          }
        }

        // Filter by search query
        if (query.isEmpty) return true;

        final title = group.title.toLowerCase();
        final description = group.description.toLowerCase();
        final name = group.name.toLowerCase();
        return title.contains(query) || description.contains(query) || name.contains(query);
      }).toList();

      // Sort by title
      _filteredGroups.sort((a, b) => a.title.compareTo(b.title));
    });
  }

  String _getDisplayTitle() {
    if (widget.collectionTitle.toLowerCase() == 'groups') {
      return _i18n.t('collection_type_groups');
    }
    return widget.collectionTitle;
  }

  String _getGroupTypeDisplay(GroupType type) {
    switch (type) {
      case GroupType.friends:
        return _i18n.t('group_type_friends');
      case GroupType.association:
        return _i18n.t('group_type_association');
      case GroupType.authorityPolice:
        return _i18n.t('group_type_authority_police');
      case GroupType.authorityFire:
        return _i18n.t('group_type_authority_fire');
      case GroupType.authorityCivilProtection:
        return _i18n.t('group_type_authority_civil_protection');
      case GroupType.authorityMilitary:
        return _i18n.t('group_type_authority_military');
      case GroupType.healthHospital:
        return _i18n.t('group_type_health_hospital');
      case GroupType.healthClinic:
        return _i18n.t('group_type_health_clinic');
      case GroupType.healthEmergency:
        return _i18n.t('group_type_health_emergency');
      case GroupType.adminTownhall:
        return _i18n.t('group_type_admin_townhall');
      case GroupType.adminRegional:
        return _i18n.t('group_type_admin_regional');
      case GroupType.adminNational:
        return _i18n.t('group_type_admin_national');
      case GroupType.infrastructureUtilities:
        return _i18n.t('group_type_infrastructure_utilities');
      case GroupType.infrastructureTransport:
        return _i18n.t('group_type_infrastructure_transport');
      case GroupType.educationSchool:
        return _i18n.t('group_type_education_school');
      case GroupType.educationUniversity:
        return _i18n.t('group_type_education_university');
      case GroupType.collectionModerator:
        return _i18n.t('group_type_collection_moderator');
    }
  }

  IconData _getGroupTypeIcon(GroupType type) {
    switch (type) {
      case GroupType.friends:
        return Icons.people;
      case GroupType.association:
        return Icons.groups;
      case GroupType.authorityPolice:
        return Icons.local_police;
      case GroupType.authorityFire:
        return Icons.local_fire_department;
      case GroupType.authorityCivilProtection:
        return Icons.shield;
      case GroupType.authorityMilitary:
        return Icons.military_tech;
      case GroupType.healthHospital:
        return Icons.local_hospital;
      case GroupType.healthClinic:
        return Icons.medical_services;
      case GroupType.healthEmergency:
        return Icons.emergency;
      case GroupType.adminTownhall:
        return Icons.location_city;
      case GroupType.adminRegional:
        return Icons.map;
      case GroupType.adminNational:
        return Icons.flag;
      case GroupType.infrastructureUtilities:
        return Icons.power;
      case GroupType.infrastructureTransport:
        return Icons.directions_bus;
      case GroupType.educationSchool:
        return Icons.school;
      case GroupType.educationUniversity:
        return Icons.account_balance;
      case GroupType.collectionModerator:
        return Icons.admin_panel_settings;
    }
  }

  Color _getGroupTypeColor(GroupType type) {
    switch (type) {
      case GroupType.friends:
        return Colors.blue;
      case GroupType.association:
        return Colors.green;
      case GroupType.authorityPolice:
      case GroupType.authorityFire:
      case GroupType.authorityCivilProtection:
      case GroupType.authorityMilitary:
        return Colors.red;
      case GroupType.healthHospital:
      case GroupType.healthClinic:
      case GroupType.healthEmergency:
        return Colors.teal;
      case GroupType.adminTownhall:
      case GroupType.adminRegional:
      case GroupType.adminNational:
        return Colors.purple;
      case GroupType.infrastructureUtilities:
      case GroupType.infrastructureTransport:
        return Colors.orange;
      case GroupType.educationSchool:
      case GroupType.educationUniversity:
        return Colors.indigo;
      case GroupType.collectionModerator:
        return Colors.amber;
    }
  }

  Widget _buildGroupTypeChip(Group group) {
    final color = _getGroupTypeColor(group.type);
    final icon = _getGroupTypeIcon(group.type);
    final label = _getGroupTypeDisplay(group.type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(GroupRole role) {
    Color color;
    String label;

    switch (role) {
      case GroupRole.admin:
        color = Colors.red;
        label = _i18n.t('role_admin');
        break;
      case GroupRole.moderator:
        color = Colors.orange;
        label = _i18n.t('role_moderator');
        break;
      case GroupRole.contributor:
        color = Colors.blue;
        label = _i18n.t('role_contributor');
        break;
      case GroupRole.guest:
        color = Colors.grey;
        label = _i18n.t('role_guest');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildGroupCard(Group group) {
    final theme = Theme.of(context);
    final currentProfile = _profileService.getProfile();
    final userRole = group.getUserRole(currentProfile.npub);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupDetailPage(
                collectionPath: widget.collectionPath,
                groupName: group.name,
              ),
            ),
          ).then((_) => _loadGroups());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (userRole != null) ...[
                              const SizedBox(width: 8),
                              _buildRoleBadge(userRole),
                            ],
                          ],
                        ),
                        if (group.collectionType != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_i18n.t('moderates')}: ${group.collectionType}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildGroupTypeChip(group),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                group.description,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${group.memberCount} ${_i18n.t('members')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (group.areaCount > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${group.areaCount} ${_i18n.t('areas')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  if (!group.isActive)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning, size: 16, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          _i18n.t('inactive'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getDisplayTitle()),
        actions: [
          // Filter by type
          PopupMenuButton<GroupType?>(
            icon: Icon(_filterType == null ? Icons.filter_alt_outlined : Icons.filter_alt),
            tooltip: _i18n.t('filter_by_type'),
            onSelected: (type) {
              setState(() {
                _filterType = type;
                _filterGroups();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Text(_i18n.t('all_types')),
              ),
              const PopupMenuDivider(),
              ...GroupType.values.map((type) => PopupMenuItem(
                value: type,
                child: Row(
                  children: [
                    Icon(_getGroupTypeIcon(type), size: 18, color: _getGroupTypeColor(type)),
                    const SizedBox(width: 8),
                    Text(_getGroupTypeDisplay(type)),
                  ],
                ),
              )),
            ],
          ),
          // Toggle my groups
          IconButton(
            icon: Icon(_showOnlyMyGroups ? Icons.person : Icons.person_outline),
            tooltip: _i18n.t('my_groups'),
            onPressed: () {
              setState(() {
                _showOnlyMyGroups = !_showOnlyMyGroups;
                _filterGroups();
              });
            },
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _i18n.t('refresh'),
            onPressed: _loadGroups,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _i18n.t('search_groups'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
              ),
            ),
          ),

          // Group list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _allGroups.isEmpty ? Icons.groups_outlined : Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _allGroups.isEmpty
                                  ? _i18n.t('no_groups_yet')
                                  : _i18n.t('no_matching_groups'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey,
                              ),
                            ),
                            if (_allGroups.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _i18n.t('create_first_group'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredGroups.length,
                        itemBuilder: (context, index) {
                          final group = _filteredGroups[index];
                          return _buildGroupCard(group);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGroup,
        tooltip: _i18n.t('new_group'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createGroup() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CreateGroupDialog(),
    );

    if (result != null) {
      try {
        final currentProfile = _profileService.getProfile();

        await _groupsService.createGroup(
          title: result['title'],
          description: result['description'],
          type: result['type'],
          collectionType: result['collectionType'],
          creatorNpub: currentProfile.npub,
          creatorCallsign: currentProfile.callsign,
        );

        await GroupSyncService().syncGroupsCollection(
          groupsCollectionPath: widget.collectionPath,
        );

        await _loadGroups();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('group_created'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_i18n.t('error')}: $e')),
          );
        }
      }
    }
  }
}

class _CreateGroupDialog extends StatefulWidget {
  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final I18nService _i18n = I18nService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  GroupType _selectedType = GroupType.association;
  String? _collectionType;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _getGroupTypeDisplay(GroupType type) {
    switch (type) {
      case GroupType.friends:
        return _i18n.t('group_type_friends');
      case GroupType.association:
        return _i18n.t('group_type_association');
      case GroupType.authorityPolice:
        return _i18n.t('group_type_authority_police');
      case GroupType.authorityFire:
        return _i18n.t('group_type_authority_fire');
      case GroupType.authorityCivilProtection:
        return _i18n.t('group_type_authority_civil_protection');
      case GroupType.authorityMilitary:
        return _i18n.t('group_type_authority_military');
      case GroupType.healthHospital:
        return _i18n.t('group_type_health_hospital');
      case GroupType.healthClinic:
        return _i18n.t('group_type_health_clinic');
      case GroupType.healthEmergency:
        return _i18n.t('group_type_health_emergency');
      case GroupType.adminTownhall:
        return _i18n.t('group_type_admin_townhall');
      case GroupType.adminRegional:
        return _i18n.t('group_type_admin_regional');
      case GroupType.adminNational:
        return _i18n.t('group_type_admin_national');
      case GroupType.infrastructureUtilities:
        return _i18n.t('group_type_infrastructure_utilities');
      case GroupType.infrastructureTransport:
        return _i18n.t('group_type_infrastructure_transport');
      case GroupType.educationSchool:
        return _i18n.t('group_type_education_school');
      case GroupType.educationUniversity:
        return _i18n.t('group_type_education_university');
      case GroupType.collectionModerator:
        return _i18n.t('group_type_collection_moderator');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_i18n.t('new_group')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _i18n.t('group_title'),
                hintText: 'Lisbon Fire Department',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: _i18n.t('description'),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GroupType>(
              value: _selectedType,
              decoration: InputDecoration(labelText: _i18n.t('group_type')),
              items: GroupType.values.map((type) => DropdownMenuItem(
                value: type,
                child: Text(_getGroupTypeDisplay(type)),
              )).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
            ),
            if (_selectedType == GroupType.collectionModerator) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _collectionType,
                decoration: InputDecoration(labelText: _i18n.t('collection_type')),
                items: [
                  'blog', 'forum', 'events', 'news', 'alerts',
                  'postcards', 'contacts', 'places', 'market'
                ].map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type),
                )).toList(),
                onChanged: (value) {
                  setState(() => _collectionType = value);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_i18n.t('cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty &&
                _descriptionController.text.isNotEmpty) {
              if (_selectedType == GroupType.collectionModerator &&
                  _collectionType == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_i18n.t('select_collection_type'))),
                );
                return;
              }

              Navigator.pop(context, {
                'title': _titleController.text,
                'description': _descriptionController.text,
                'type': _selectedType,
                'collectionType': _collectionType,
              });
            }
          },
          child: Text(_i18n.t('create')),
        ),
      ],
    );
  }
}
