/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Usenet App Page - Main entry point for NNTP/Usenet client
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nntp/nntp.dart';

import '../../models/nntp_account.dart';
import '../../models/nntp_subscription.dart';
import '../../services/nntp_service.dart';
import '../../services/app_service.dart';
import '../../services/profile_service.dart';
import '../../services/profile_storage.dart';
import '../../services/storage_config.dart';
import 'newsgroup_list_page.dart';
import 'thread_view_page.dart';
import '../widgets/account_setup_dialog.dart';
import '../widgets/newsgroup_tile.dart';

/// Main Usenet app page
class UsenetAppPage extends StatefulWidget {
  const UsenetAppPage({super.key});

  @override
  State<UsenetAppPage> createState() => _UsenetAppPageState();
}

class _UsenetAppPageState extends State<UsenetAppPage> {
  final NNTPService _nntpService = NNTPService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<NNTPAccount> _accounts = [];
  List<NNTPSubscription> _subscriptions = [];
  NNTPSubscription? _selectedSubscription;
  bool _isLoading = true;
  String? _error;
  bool _isWideScreen = false;

  StreamSubscription<NNTPChangeEvent>? _nntpSubscription;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  @override
  void dispose() {
    _nntpSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      // Initialize storage
      final profile = ProfileService().getProfile();
      if (profile != null) {
        final profileStorage = AppService().profileStorage;
        if (profileStorage != null) {
          // Create a scoped storage for the usenet directory
          final usenetDir = StorageConfig().usenetDirForProfile(profile.callsign);
          final scopedStorage = ScopedProfileStorage.fromAbsolutePath(
            profileStorage,
            usenetDir,
          );
          _nntpService.setStorage(scopedStorage);
        }
      }

      await _nntpService.initialize();

      // Subscribe to events
      _nntpSubscription = _nntpService.onNNTPChange.listen(_handleNNTPEvent);

      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _handleNNTPEvent(NNTPChangeEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case NNTPChangeType.connected:
      case NNTPChangeType.disconnected:
      case NNTPChangeType.subscribed:
      case NNTPChangeType.unsubscribed:
      case NNTPChangeType.syncCompleted:
        _loadData();
        break;
      case NNTPChangeType.newArticles:
        // Update unread counts
        _loadSubscriptions();
        break;
      default:
        break;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _accounts = _nntpService.accounts;
      await _loadSubscriptions();

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

  Future<void> _loadSubscriptions() async {
    _subscriptions = _nntpService.allSubscriptions;

    // Sort by unread count, then by name
    _subscriptions.sort((a, b) {
      if (a.hasUnread != b.hasUnread) {
        return a.hasUnread ? -1 : 1;
      }
      return a.groupName.compareTo(b.groupName);
    });

    if (mounted) setState(() {});
  }

  Future<void> _syncAll() async {
    for (final account in _accounts.where((a) => a.isConnected)) {
      try {
        await _nntpService.syncAllGroups(account.id);
      } catch (e) {
        // Continue syncing other accounts
      }
    }
  }

  void _showAddAccountDialog() {
    showDialog<NNTPAccount>(
      context: context,
      builder: (context) => const AccountSetupDialog(),
    ).then((account) {
      if (account != null) {
        _nntpService.addAccount(account).then((_) {
          _nntpService.connect(account.id).then((_) => _loadData());
        });
      }
    });
  }

  void _openGroupBrowser(NNTPAccount account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewsgroupListPage(account: account),
      ),
    ).then((_) => _loadData());
  }

  void _openSubscription(NNTPSubscription subscription) {
    if (_isWideScreen) {
      setState(() => _selectedSubscription = subscription);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadViewPage(subscription: subscription),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(theme),
      drawer: _buildDrawer(theme),
      body: _buildBody(theme),
      floatingActionButton: _accounts.isNotEmpty
          ? FloatingActionButton(
              onPressed: () {
                final connected = _accounts.where((a) => a.isConnected).toList();
                if (connected.isNotEmpty) {
                  _openGroupBrowser(connected.first);
                } else if (_accounts.isNotEmpty) {
                  _nntpService.connect(_accounts.first.id).then((_) {
                    _openGroupBrowser(_accounts.first);
                  });
                }
              },
              tooltip: 'Browse Newsgroups',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Accounts',
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usenet',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_subscriptions.isNotEmpty)
            Text(
              '${_subscriptions.length} subscriptions',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _syncAll,
          tooltip: 'Sync All',
        ),
        PopupMenuButton<String>(
          onSelected: _handleMenuAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'add_account',
              child: ListTile(
                leading: Icon(Icons.person_add),
                title: Text('Add Account'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: ListTile(
                leading: Icon(Icons.settings),
                title: Text('Settings'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'add_account':
        _showAddAccountDialog();
        break;
      case 'settings':
        // TODO: Open settings page
        break;
    }
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.forum,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Accounts',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (_accounts.isEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('No accounts'),
              subtitle: const Text('Add an NNTP server to get started'),
              onTap: _showAddAccountDialog,
            )
          else
            ..._accounts.map((account) => _buildAccountTile(account, theme)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add Account'),
            onTap: () {
              Navigator.pop(context);
              _showAddAccountDialog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(NNTPAccount account, ThemeData theme) {
    final subscriptionCount = _subscriptions
        .where((s) => s.accountId == account.id)
        .length;

    return ExpansionTile(
      leading: Icon(
        account.isConnected ? Icons.cloud_done : Icons.cloud_off,
        color: account.isConnected
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
      ),
      title: Text(account.name),
      subtitle: Text(
        account.isConnected
            ? '$subscriptionCount subscriptions'
            : 'Disconnected',
      ),
      children: [
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(account.isConnected ? 'Disconnect' : 'Connect'),
          onTap: () {
            if (account.isConnected) {
              _nntpService.disconnect(account.id);
            } else {
              _nntpService.connect(account.id);
            }
            Navigator.pop(context);
          },
        ),
        if (account.isConnected)
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('Browse Groups'),
            onTap: () {
              Navigator.pop(context);
              _openGroupBrowser(account);
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Remove Account'),
          onTap: () {
            Navigator.pop(context);
            _confirmRemoveAccount(account);
          },
        ),
      ],
    );
  }

  void _confirmRemoveAccount(NNTPAccount account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Account?'),
        content: Text(
          'Remove ${account.name}? This will also remove all subscriptions for this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _nntpService.removeAccount(account.id).then((_) => _loadData());
            },
            child: const Text('Remove'),
          ),
        ],
      ),
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
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_accounts.isEmpty) {
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
              'Welcome to Usenet',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add an NNTP server to get started',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddAccountDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Account'),
            ),
          ],
        ),
      );
    }

    if (_subscriptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.newspaper,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Subscriptions',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to newsgroups to see them here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                final connected = _accounts.where((a) => a.isConnected).toList();
                if (connected.isNotEmpty) {
                  _openGroupBrowser(connected.first);
                }
              },
              icon: const Icon(Icons.list),
              label: const Text('Browse Newsgroups'),
            ),
          ],
        ),
      );
    }

    if (_isWideScreen) {
      return Row(
        children: [
          SizedBox(
            width: 350,
            child: _buildSubscriptionList(theme),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedSubscription != null
                ? ThreadViewPage(
                    subscription: _selectedSubscription!,
                    embedded: true,
                  )
                : Center(
                    child: Text(
                      'Select a newsgroup',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    return _buildSubscriptionList(theme);
  }

  Widget _buildSubscriptionList(ThemeData theme) {
    // Group subscriptions by account
    final byAccount = <String, List<NNTPSubscription>>{};
    for (final sub in _subscriptions) {
      byAccount.putIfAbsent(sub.accountId, () => []).add(sub);
    }

    if (_accounts.length == 1) {
      // Single account - flat list
      return RefreshIndicator(
        onRefresh: _syncAll,
        child: ListView.builder(
          itemCount: _subscriptions.length,
          itemBuilder: (context, index) {
            final sub = _subscriptions[index];
            return NewsgroupTile(
              subscription: sub,
              isSelected: _selectedSubscription == sub,
              onTap: () => _openSubscription(sub),
              onLongPress: () => _showSubscriptionOptions(sub),
            );
          },
        ),
      );
    }

    // Multiple accounts - grouped list
    return RefreshIndicator(
      onRefresh: _syncAll,
      child: ListView.builder(
        itemCount: byAccount.length,
        itemBuilder: (context, index) {
          final accountId = byAccount.keys.elementAt(index);
          final account = _accounts.firstWhere((a) => a.id == accountId);
          final subs = byAccount[accountId]!;

          return ExpansionTile(
            leading: Icon(
              Icons.cloud,
              color: account.isConnected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            title: Text(account.name),
            subtitle: Text('${subs.length} groups'),
            initiallyExpanded: true,
            children: subs.map((sub) {
              return NewsgroupTile(
                subscription: sub,
                isSelected: _selectedSubscription == sub,
                onTap: () => _openSubscription(sub),
                onLongPress: () => _showSubscriptionOptions(sub),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  void _showSubscriptionOptions(NNTPSubscription subscription) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync'),
              onTap: () {
                Navigator.pop(context);
                _nntpService.syncGroup(
                  subscription.accountId,
                  subscription.groupName,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Mark All Read'),
              onTap: () {
                Navigator.pop(context);
                _nntpService.markAsRead(
                  subscription.accountId,
                  subscription.groupName,
                  all: true,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Unsubscribe'),
              onTap: () {
                Navigator.pop(context);
                _confirmUnsubscribe(subscription);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmUnsubscribe(NNTPSubscription subscription) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe?'),
        content: Text('Unsubscribe from ${subscription.groupName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _nntpService
                  .unsubscribe(subscription.accountId, subscription.groupName)
                  .then((_) => _loadData());
            },
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );
  }
}
