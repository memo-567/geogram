/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Email Browser Page - Lists email threads across stations
 */

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/email_thread.dart';
import '../services/email_service.dart';
import '../util/event_bus.dart';
import 'email_thread_page.dart';
import 'email_compose_page.dart';

/// Email folder types
enum EmailFolder {
  inbox,
  sent,
  outbox,
  drafts,
  archive,
  spam,
  garbage,
  label,
}

/// Email browser page with folder navigation and thread list
class EmailBrowserPage extends StatefulWidget {
  /// Initial folder to display
  final EmailFolder initialFolder;

  /// Initial station (null for unified view)
  final String? initialStation;

  /// Initial label (for label folder)
  final String? initialLabel;

  const EmailBrowserPage({
    super.key,
    this.initialFolder = EmailFolder.inbox,
    this.initialStation,
    this.initialLabel,
  });

  @override
  State<EmailBrowserPage> createState() => _EmailBrowserPageState();
}

class _EmailBrowserPageState extends State<EmailBrowserPage> {
  final EmailService _emailService = EmailService();

  List<EmailThread> _threads = [];
  EmailThread? _selectedThread;
  EmailFolder _currentFolder = EmailFolder.inbox;
  String? _currentStation; // null = unified (all stations)
  String? _currentLabel;
  bool _isLoading = true;
  String? _error;
  List<String> _labels = [];
  bool _isWideScreen = false;
  bool _showingFolderList = true;  // Mobile: true = show folders, false = show threads
  Map<EmailFolder, int> _folderCounts = {};

  StreamSubscription<EmailChangeEvent>? _emailSubscription;
  EventSubscription<EmailNotificationEvent>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _currentFolder = widget.initialFolder;
    _currentStation = widget.initialStation;
    _currentLabel = widget.initialLabel;
    _initialize();
  }

  @override
  void dispose() {
    _emailSubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _emailService.initialize();
    _emailSubscription = _emailService.onEmailChange.listen(_onEmailChange);
    _notificationSubscription = EventBus().on<EmailNotificationEvent>(_onEmailNotification);
    await _loadLabels();
    await _loadFolderCounts();
    await _loadThreads();
  }

  Future<void> _loadFolderCounts() async {
    final counts = <EmailFolder, int>{};
    counts[EmailFolder.inbox] = (await _emailService.getInbox()).length;
    counts[EmailFolder.sent] = (await _emailService.getSent()).length;
    counts[EmailFolder.outbox] = (await _emailService.getOutbox()).length;
    counts[EmailFolder.drafts] = (await _emailService.getDrafts()).length;
    counts[EmailFolder.archive] = (await _emailService.getArchive()).length;
    counts[EmailFolder.spam] = (await _emailService.getSpam()).length;
    counts[EmailFolder.garbage] = (await _emailService.getGarbage()).length;
    if (mounted) {
      setState(() => _folderCounts = counts);
    }
  }

  void _onEmailNotification(EmailNotificationEvent event) {
    if (!mounted) return;

    // Determine snackbar color based on action
    Color backgroundColor;
    IconData icon;
    switch (event.action) {
      case 'delivered':
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case 'failed':
        backgroundColor = Colors.red;
        icon = Icons.error;
        break;
      case 'pending_approval':
        backgroundColor = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case 'pending':
        backgroundColor = Colors.blue;
        icon = Icons.schedule;
        break;
      case 'delayed':
        backgroundColor = Colors.amber;
        icon = Icons.schedule;
        break;
      default:
        backgroundColor = Colors.blue;
        icon = Icons.info;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(event.message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _loadLabels() async {
    final labels = await _emailService.getLabels();
    if (mounted) {
      setState(() => _labels = labels);
    }
  }

  Future<void> _createLabel() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label name',
            hintText: 'e.g., Work, Personal, Important',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _emailService.createLabel(result);
      await _loadLabels();
    }
  }

  Future<void> _deleteLabel(String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Label?'),
        content: Text('Are you sure you want to delete the label "$label"?\n\n'
            'Emails with this label will not be deleted, only the label will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _emailService.deleteLabel(label);
      await _loadLabels();
      if (_currentLabel == label) {
        _selectFolder(EmailFolder.inbox);
      }
    }
  }

  void _onEmailChange(EmailChangeEvent event) {
    // Reload threads and folder counts when changes occur
    _loadFolderCounts();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<EmailThread> threads;

      // All folders are unified - no per-station filtering needed
      switch (_currentFolder) {
        case EmailFolder.inbox:
          threads = await _emailService.getInbox();
          break;
        case EmailFolder.sent:
          threads = await _emailService.getSent();
          break;
        case EmailFolder.outbox:
          threads = await _emailService.getOutbox();
          break;
        case EmailFolder.drafts:
          threads = await _emailService.getDrafts();
          break;
        case EmailFolder.archive:
          threads = await _emailService.getArchive();
          break;
        case EmailFolder.spam:
          threads = await _emailService.getSpam();
          break;
        case EmailFolder.garbage:
          threads = await _emailService.getGarbage();
          break;
        case EmailFolder.label:
          if (_currentLabel != null) {
            threads = await _emailService.getThreadsByLabel(_currentLabel!);
          } else {
            threads = [];
          }
          break;
      }

      if (mounted) {
        setState(() {
          _threads = threads;
          _isLoading = false;
        });
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

  Future<void> _refresh() async {
    await _loadFolderCounts();
    await _loadThreads();
    await _emailService.processOutbox();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email refreshed'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _getFolderTitle() {
    switch (_currentFolder) {
      case EmailFolder.inbox:
        return _currentStation != null ? 'Inbox - $_currentStation' : 'Inbox';
      case EmailFolder.sent:
        return _currentStation != null ? 'Sent - $_currentStation' : 'Sent';
      case EmailFolder.outbox:
        return _currentStation != null ? 'Outbox - $_currentStation' : 'Outbox';
      case EmailFolder.drafts:
        return 'Drafts';
      case EmailFolder.archive:
        return 'Archive';
      case EmailFolder.spam:
        return _currentStation != null ? 'Spam - $_currentStation' : 'Spam';
      case EmailFolder.garbage:
        return 'Trash';
      case EmailFolder.label:
        return _currentLabel ?? 'Label';
    }
  }

  IconData _getFolderIcon(EmailFolder folder) {
    switch (folder) {
      case EmailFolder.inbox:
        return Icons.inbox;
      case EmailFolder.sent:
        return Icons.send;
      case EmailFolder.outbox:
        return Icons.outbox;
      case EmailFolder.drafts:
        return Icons.drafts;
      case EmailFolder.archive:
        return Icons.archive;
      case EmailFolder.spam:
        return Icons.report;
      case EmailFolder.garbage:
        return Icons.delete;
      case EmailFolder.label:
        return Icons.label;
    }
  }

  void _selectFolder(EmailFolder folder, {String? station, String? label}) {
    setState(() {
      _currentFolder = folder;
      _currentStation = station;
      _currentLabel = label;
      _selectedThread = null;
    });
    _loadThreads();
  }

  void _selectThread(EmailThread thread) {
    // Drafts should open in compose mode for editing
    if (thread.isDraft) {
      Navigator.of(context).push<EmailThread>(
        MaterialPageRoute(
          builder: (context) => EmailComposePage(editDraft: thread),
        ),
      ).then((_) => _loadThreads());
      return;
    }

    if (_isWideScreen) {
      setState(() {
        _selectedThread = thread;
      });
    } else {
      // Navigate to thread page on mobile
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => EmailThreadPage(thread: thread),
        ),
      ).then((_) => _loadThreads());
    }
  }

  Future<void> _composeEmail() async {
    final result = await Navigator.of(context).push<EmailThread>(
      MaterialPageRoute(
        builder: (context) => EmailComposePage(),
      ),
    );

    if (result != null) {
      await _loadThreads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _isWideScreen = constraints.maxWidth >= 600;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            leading: _selectedThread != null
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _selectedThread = null),
                  )
                : (!_isWideScreen && !_showingFolderList)
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => setState(() => _showingFolderList = true),
                      )
                    : null,
            title: Text(_selectedThread != null
                ? _selectedThread!.subject
                : (!_isWideScreen && !_showingFolderList)
                    ? _getFolderTitle()
                    : 'Email'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _handleMenuAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'labels',
                    child: ListTile(
                      leading: Icon(Icons.label),
                      title: Text('Labels'),
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
                  const PopupMenuItem(
                    value: 'accounts',
                    child: ListTile(
                      leading: Icon(Icons.account_circle),
                      title: Text('Accounts'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _composeEmail,
            tooltip: 'Compose',
            child: const Icon(Icons.edit),
          ),
          body: _isWideScreen
              ? Row(
                  children: [
                    // Left panel: Folders only (narrow)
                    SizedBox(
                      width: 180,
                      child: _buildFolderPanel(theme),
                    ),
                    const VerticalDivider(width: 1),
                    // Right panel: Thread list OR thread detail
                    Expanded(
                      child: _selectedThread != null
                          ? EmailThreadPage(
                              thread: _selectedThread!,
                              embedded: true,
                            )
                          : _buildThreadList(),
                    ),
                  ],
                )
              : _selectedThread != null
                  ? EmailThreadPage(
                      thread: _selectedThread!,
                      embedded: true,
                    )
                  : _buildMobileView(theme),
        );
      },
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'labels':
        _showLabelsSheet();
        break;
      case 'settings':
        // TODO: Open email settings
        break;
      case 'accounts':
        // TODO: Open accounts management
        break;
    }
  }

  void _showLabelsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Labels', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  Navigator.pop(context);
                  _createLabel();
                },
                tooltip: 'Create Label',
              ),
            ),
            const Divider(height: 1),
            if (_labels.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No labels yet', style: TextStyle(color: Colors.grey)),
              )
            else
              ...(_labels.map((label) => ListTile(
                leading: const Icon(Icons.label),
                title: Text(label),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteLabel(label);
                  },
                ),
                onTap: () {
                  Navigator.pop(context);
                  _selectFolder(EmailFolder.label, label: label);
                },
              )).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileView(ThemeData theme) {
    if (_showingFolderList) {
      return _buildFolderList(theme);
    }
    return _buildThreadList();
  }

  Widget _buildFolderList(ThemeData theme) {
    return ListView(
      children: [
        _buildFolderListTile(EmailFolder.inbox, 'Inbox', Icons.inbox),
        _buildFolderListTile(EmailFolder.sent, 'Sent', Icons.send),
        _buildFolderListTile(EmailFolder.outbox, 'Outbox', Icons.outbox),
        _buildFolderListTile(EmailFolder.drafts, 'Drafts', Icons.drafts),
        _buildFolderListTile(EmailFolder.archive, 'Archive', Icons.archive),
        _buildFolderListTile(EmailFolder.spam, 'Spam', Icons.report),
        _buildFolderListTile(EmailFolder.garbage, 'Trash', Icons.delete),
      ],
    );
  }

  Widget _buildFolderListTile(EmailFolder folder, String title, IconData icon) {
    final count = _folderCounts[folder] ?? 0;
    return ListTile(
      leading: Icon(icon, color: Colors.amber),
      title: Text(title),
      subtitle: Text('$count ${count == 1 ? 'email' : 'emails'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        setState(() {
          _currentFolder = folder;
          _showingFolderList = false;
        });
        _loadThreads();
      },
    );
  }

  Widget _buildFolderPanel(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: ListView(
        children: [
          _buildFolderTile(EmailFolder.inbox, null, 'Inbox'),
          _buildFolderTile(EmailFolder.sent, null, 'Sent'),
          _buildFolderTile(EmailFolder.outbox, null, 'Outbox'),
          _buildFolderTile(EmailFolder.drafts, null, 'Drafts'),
          _buildFolderTile(EmailFolder.archive, null, 'Archive'),
          _buildFolderTile(EmailFolder.spam, null, 'Spam'),
          _buildFolderTile(EmailFolder.garbage, null, 'Trash'),
        ],
      ),
    );
  }

  Widget _buildFolderTile(EmailFolder folder, String? station, String title) {
    final isSelected = _currentFolder == folder && _currentStation == station;

    return ListTile(
      dense: true,
      leading: Icon(
        _getFolderIcon(folder),
        size: 20,
        color: isSelected ? Theme.of(context).primaryColor : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).primaryColor : null,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
      onTap: () => _selectFolder(folder, station: station),
    );
  }

  Widget _buildThreadList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red[300])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadThreads,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_threads.isEmpty) {
      return _buildEmptyFolder();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: _threads.length,
        itemBuilder: (context, index) {
          final thread = _threads[index];
          return _buildSwipeableThreadTile(thread);
        },
      ),
    );
  }

  Widget _buildSwipeableThreadTile(EmailThread thread) {
    return Dismissible(
      key: Key(thread.threadId),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.blue,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right to delete
          await _emailService.deleteThread(thread);
          if (_selectedThread?.threadId == thread.threadId) {
            setState(() => _selectedThread = null);
          }
          _loadThreads();
          return false; // Don't remove from list, we reload
        } else {
          // Swipe left to archive
          await _emailService.archiveThread(thread);
          if (_selectedThread?.threadId == thread.threadId) {
            setState(() => _selectedThread = null);
          }
          _loadThreads();
          return false;
        }
      },
      child: _buildThreadTile(thread),
    );
  }

  Widget _buildThreadTile(EmailThread thread) {
    final isSelected = _selectedThread?.threadId == thread.threadId;
    final isUnread = thread.status == EmailStatus.received;
    final hasAttachment = thread.hasAttachments;

    // Determine display name based on folder
    String displayName;
    if (_currentFolder == EmailFolder.sent ||
        _currentFolder == EmailFolder.outbox ||
        _currentFolder == EmailFolder.drafts) {
      displayName = thread.to.isNotEmpty ? thread.to.first : 'No recipient';
    } else {
      displayName = thread.from;
    }

    return ListTile(
      selected: isSelected,
      selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
      leading: CircleAvatar(
        backgroundColor: isUnread
            ? Theme.of(context).primaryColor
            : Colors.grey[300],
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: isUnread ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(thread.lastMessageTime),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasAttachment)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.attach_file, size: 14, color: Colors.grey[600]),
                ),
              Expanded(
                child: Text(
                  thread.subject,
                  style: TextStyle(
                    fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            thread.preview,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (_currentStation == null && thread.station != 'local')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                thread.station,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: () => _selectThread(thread),
      onLongPress: () => _showThreadActions(thread),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      // Today - show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      // Older - show date
      return '${date.day}/${date.month}';
    }
  }

  void _showThreadActions(EmailThread thread) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit option for drafts
            if (thread.isDraft)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Draft'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<EmailThread>(
                    MaterialPageRoute(
                      builder: (context) => EmailComposePage(editDraft: thread),
                    ),
                  ).then((_) => _loadThreads());
                },
              ),
            // Reply/Forward options (not for drafts)
            if (!thread.isDraft) ...[
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<EmailThread>(
                    MaterialPageRoute(
                      builder: (context) => EmailComposePage(replyTo: thread),
                    ),
                  ).then((_) => _loadThreads());
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply_all),
                title: const Text('Reply All'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<EmailThread>(
                    MaterialPageRoute(
                      builder: (context) =>
                          EmailComposePage(replyTo: thread, replyAll: true),
                    ),
                  ).then((_) => _loadThreads());
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<EmailThread>(
                    MaterialPageRoute(
                      builder: (context) =>
                          EmailComposePage(forwardFrom: thread),
                    ),
                  ).then((_) => _loadThreads());
                },
              ),
            ],
            // Archive (not for archived threads)
            if (thread.status != EmailStatus.archived)
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('Archive'),
                onTap: () async {
                  Navigator.pop(context);
                  await _emailService.archiveThread(thread);
                  if (_selectedThread?.threadId == thread.threadId) {
                    setState(() => _selectedThread = null);
                  }
                  _loadThreads();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Thread archived')),
                    );
                  }
                },
              ),
            // Restore option for archived/deleted/spam threads
            if (thread.status == EmailStatus.archived ||
                thread.status == EmailStatus.deleted ||
                thread.status == EmailStatus.spam)
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore to Inbox'),
                onTap: () async {
                  Navigator.pop(context);
                  await _emailService.restoreThread(thread);
                  if (_selectedThread?.threadId == thread.threadId) {
                    setState(() => _selectedThread = null);
                  }
                  _loadThreads();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Thread restored to inbox')),
                    );
                  }
                },
              ),
            // Spam option
            if (thread.status != EmailStatus.spam)
              ListTile(
                leading: const Icon(Icons.report),
                title: const Text('Mark as Spam'),
                onTap: () async {
                  Navigator.pop(context);
                  await _emailService.markAsSpam(thread);
                  if (_selectedThread?.threadId == thread.threadId) {
                    setState(() => _selectedThread = null);
                  }
                  _loadThreads();
                },
              ),
            // Delete
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(context);
                await _emailService.deleteThread(thread);
                if (_selectedThread?.threadId == thread.threadId) {
                  setState(() => _selectedThread = null);
                }
                _loadThreads();
              },
            ),
            // Permanent delete for trash
            if (thread.status == EmailStatus.deleted)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Permanently',
                    style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  await _emailService.permanentlyDelete(thread);
                  if (_selectedThread?.threadId == thread.threadId) {
                    setState(() => _selectedThread = null);
                  }
                  _loadThreads();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFolder() {
    String message;
    IconData icon;

    switch (_currentFolder) {
      case EmailFolder.inbox:
        message = 'No emails in inbox';
        icon = Icons.inbox;
        break;
      case EmailFolder.sent:
        message = 'No sent emails';
        icon = Icons.send;
        break;
      case EmailFolder.outbox:
        message = 'No pending emails';
        icon = Icons.outbox;
        break;
      case EmailFolder.drafts:
        message = 'No drafts';
        icon = Icons.drafts;
        break;
      case EmailFolder.archive:
        message = 'No archived emails';
        icon = Icons.archive;
        break;
      case EmailFolder.spam:
        message = 'No spam';
        icon = Icons.report;
        break;
      case EmailFolder.garbage:
        message = 'Trash is empty';
        icon = Icons.delete;
        break;
      case EmailFolder.label:
        message = 'No emails with this label';
        icon = Icons.label;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.email_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Select an email to read',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
