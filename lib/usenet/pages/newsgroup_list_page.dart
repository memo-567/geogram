/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Newsgroup List Page - Browse and subscribe to newsgroups
 */

import 'package:flutter/material.dart';
import 'package:nntp/nntp.dart';

import '../../models/nntp_account.dart';
import '../../services/nntp_service.dart';

/// Page for browsing and subscribing to newsgroups
class NewsgroupListPage extends StatefulWidget {
  final NNTPAccount account;

  const NewsgroupListPage({
    super.key,
    required this.account,
  });

  @override
  State<NewsgroupListPage> createState() => _NewsgroupListPageState();
}

class _NewsgroupListPageState extends State<NewsgroupListPage> {
  final NNTPService _nntpService = NNTPService();
  final TextEditingController _searchController = TextEditingController();

  List<Newsgroup> _allGroups = [];
  List<Newsgroup> _filteredGroups = [];
  Map<String, String> _descriptions = {};
  Set<String> _subscribedGroups = {};
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  // Hierarchy view
  bool _showHierarchy = true;
  String? _selectedHierarchy;
  Map<String, List<Newsgroup>> _byHierarchy = {};

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _loadSubscriptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch groups
      _allGroups = await _nntpService.listGroups(widget.account.id);

      // Sort alphabetically
      _allGroups.sort((a, b) => a.name.compareTo(b.name));

      // Try to fetch descriptions
      try {
        _descriptions = await _nntpService.getGroupDescriptions(widget.account.id);
      } catch (_) {
        // Descriptions are optional
      }

      // Build hierarchy
      _buildHierarchy();

      // Apply filter
      _applyFilter();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _loadSubscriptions() {
    final subs = _nntpService.getSubscriptions(widget.account.id);
    _subscribedGroups = subs.map((s) => s.groupName).toSet();
  }

  void _buildHierarchy() {
    _byHierarchy.clear();

    for (final group in _allGroups) {
      final parts = group.name.split('.');
      final topLevel = parts.first;

      _byHierarchy.putIfAbsent(topLevel, () => []).add(group);
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty && _selectedHierarchy == null) {
      _filteredGroups = _allGroups;
    } else {
      _filteredGroups = _allGroups.where((group) {
        // Filter by hierarchy
        if (_selectedHierarchy != null) {
          if (!group.name.startsWith('$_selectedHierarchy.')) {
            return false;
          }
        }

        // Filter by search
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          if (!group.name.toLowerCase().contains(query)) {
            final desc = _descriptions[group.name]?.toLowerCase() ?? '';
            if (!desc.contains(query)) {
              return false;
            }
          }
        }

        return true;
      }).toList();
    }
  }

  Future<void> _subscribe(Newsgroup group) async {
    try {
      await _nntpService.subscribe(
        widget.account.id,
        group.name,
        description: _descriptions[group.name],
      );

      setState(() {
        _subscribedGroups.add(group.name);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscribed to ${group.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _unsubscribe(group),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to subscribe: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _unsubscribe(Newsgroup group) async {
    try {
      await _nntpService.unsubscribe(widget.account.id, group.name);

      setState(() {
        _subscribedGroups.remove(group.name);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unsubscribe: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Newsgroups'),
            Text(
              widget.account.name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showHierarchy ? Icons.list : Icons.account_tree),
            onPressed: () {
              setState(() {
                _showHierarchy = !_showHierarchy;
                if (!_showHierarchy) {
                  _selectedHierarchy = null;
                  _applyFilter();
                }
              });
            },
            tooltip: _showHierarchy ? 'Flat List' : 'Hierarchy View',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGroups,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search newsgroups...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilter();
                });
              },
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGroups,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_allGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No newsgroups available',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    if (_showHierarchy && _selectedHierarchy == null && _searchQuery.isEmpty) {
      return _buildHierarchyView(theme);
    }

    return _buildGroupList(theme);
  }

  Widget _buildHierarchyView(ThemeData theme) {
    final hierarchies = _byHierarchy.keys.toList()..sort();

    return ListView.builder(
      itemCount: hierarchies.length,
      itemBuilder: (context, index) {
        final hierarchy = hierarchies[index];
        final groups = _byHierarchy[hierarchy]!;

        return ListTile(
          leading: Icon(
            Icons.folder,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            hierarchy,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${groups.length} groups'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _selectedHierarchy = hierarchy;
              _applyFilter();
            });
          },
        );
      },
    );
  }

  Widget _buildGroupList(ThemeData theme) {
    return Column(
      children: [
        if (_selectedHierarchy != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedHierarchy = null;
                      _applyFilter();
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    '$_selectedHierarchy.* (${_filteredGroups.length} groups)',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _filteredGroups.isEmpty
              ? Center(
                  child: Text(
                    'No groups match your search',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredGroups.length,
                  itemBuilder: (context, index) {
                    final group = _filteredGroups[index];
                    final isSubscribed = _subscribedGroups.contains(group.name);
                    final description = _descriptions[group.name];

                    return ListTile(
                      leading: Icon(
                        isSubscribed ? Icons.bookmark : Icons.bookmark_border,
                        color: isSubscribed
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text(
                        group.name,
                        style: TextStyle(
                          fontWeight:
                              isSubscribed ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: description != null
                          ? Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              '${group.estimatedCount} articles',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                      trailing: isSubscribed
                          ? IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _unsubscribe(group),
                              tooltip: 'Unsubscribe',
                            )
                          : IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _subscribe(group),
                              tooltip: 'Subscribe',
                            ),
                      onTap: () {
                        if (isSubscribed) {
                          _unsubscribe(group);
                        } else {
                          _subscribe(group);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
