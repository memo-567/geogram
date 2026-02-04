/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';

import 'package:flutter/material.dart';

import '../wallet/models/currency.dart';
import '../wallet/models/debt_entry.dart';
import '../wallet/models/debt_summary.dart';
import '../wallet/models/receipt.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';
import '../widgets/wallet/debt_card_widget.dart';
import '../widgets/wallet/receipt_card_widget.dart';
import '../widgets/wallet/wallet_summary_widget.dart';
import 'create_debt_page.dart';
import 'create_receipt_page.dart';
import 'debt_detail_page.dart';
import 'receipt_detail_page.dart';
import 'wallet_settings_page.dart';

/// Main wallet browser page with summary and debt/receipt lists
class WalletBrowserPage extends StatefulWidget {
  final String appPath;
  final String appTitle;
  final I18nService i18n;

  const WalletBrowserPage({
    super.key,
    required this.appPath,
    required this.appTitle,
    required this.i18n,
  });

  @override
  State<WalletBrowserPage> createState() => _WalletBrowserPageState();
}

class _WalletBrowserPageState extends State<WalletBrowserPage>
    with SingleTickerProviderStateMixin {
  final WalletService _service = WalletService();
  final ProfileService _profileService = ProfileService();

  late TabController _tabController;
  List<DebtSummary> _debts = [];
  List<Receipt> _receipts = [];
  List<String> _folders = [];
  WalletSummary? _summary;
  bool _loading = true;
  String? _userNpub;
  StreamSubscription? _changesSub;

  // Filters
  DebtStatus? _statusFilter;
  String? _currencyFilter;
  bool _showOnlyOwedToMe = false;
  bool _showOnlyIOwe = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeService();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _initializeService() async {
    await _service.initializeApp(widget.appPath);
    await Currencies.loadCustomCurrencies();

    final profile = _profileService.getProfile();
    _userNpub = profile.npub;

    _changesSub = _service.changes.listen(_onWalletChange);
    await _loadData();
  }

  void _onWalletChange(WalletChange change) {
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _debts = await _service.listAllDebts();
      _receipts = await _service.listAllReceipts();
      _folders = await _service.getFolders();

      if (_userNpub != null) {
        _summary = await _service.getSummary(_userNpub!);
      }
    } catch (e) {
      // Handle error
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<DebtSummary> get _filteredDebts {
    var filtered = _debts;

    // Status filter
    if (_statusFilter != null) {
      filtered = filtered.where((d) => d.status == _statusFilter).toList();
    }

    // Currency filter
    if (_currencyFilter != null) {
      filtered = filtered.where((d) => d.currency == _currencyFilter).toList();
    }

    // Direction filters
    if (_showOnlyOwedToMe && _userNpub != null) {
      filtered = filtered.where((d) => d.creditorNpub == _userNpub).toList();
    } else if (_showOnlyIOwe && _userNpub != null) {
      filtered = filtered.where((d) => d.debtorNpub == _userNpub).toList();
    }

    return filtered;
  }

  String _getDisplayTitle() {
    if (widget.appTitle.startsWith('app_type_')) {
      return widget.i18n.t(widget.appTitle);
    }
    return widget.appTitle;
  }

  void _showFilterSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.i18n.t('filter'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              // Status filter
              ListTile(
                title: Text(widget.i18n.t('status')),
                trailing: DropdownButton<DebtStatus?>(
                  value: _statusFilter,
                  hint: Text(widget.i18n.t('all')),
                  onChanged: (value) {
                    setModalState(() => _statusFilter = value);
                    setState(() {});
                  },
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(widget.i18n.t('all')),
                    ),
                    ...DebtStatus.values.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_getStatusLabel(s)),
                        )),
                  ],
                ),
              ),
              // Direction filter
              CheckboxListTile(
                title: Text(widget.i18n.t('wallet_owed_to_me')),
                value: _showOnlyOwedToMe,
                onChanged: (value) {
                  setModalState(() {
                    _showOnlyOwedToMe = value ?? false;
                    if (_showOnlyOwedToMe) _showOnlyIOwe = false;
                  });
                  setState(() {});
                },
              ),
              CheckboxListTile(
                title: Text(widget.i18n.t('wallet_i_owe')),
                value: _showOnlyIOwe,
                onChanged: (value) {
                  setModalState(() {
                    _showOnlyIOwe = value ?? false;
                    if (_showOnlyIOwe) _showOnlyOwedToMe = false;
                  });
                  setState(() {});
                },
              ),
              // Clear filters
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () {
                    setModalState(() {
                      _statusFilter = null;
                      _currencyFilter = null;
                      _showOnlyOwedToMe = false;
                      _showOnlyIOwe = false;
                    });
                    setState(() {});
                  },
                  child: Text(widget.i18n.t('clear_filters')),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(DebtStatus status) {
    switch (status) {
      case DebtStatus.draft:
        return widget.i18n.t('wallet_status_draft');
      case DebtStatus.pending:
        return widget.i18n.t('wallet_status_pending');
      case DebtStatus.open:
        return widget.i18n.t('wallet_status_open');
      case DebtStatus.paid:
        return widget.i18n.t('wallet_status_paid');
      case DebtStatus.expired:
        return widget.i18n.t('wallet_status_expired');
      case DebtStatus.retired:
        return widget.i18n.t('wallet_status_retired');
      case DebtStatus.rejected:
        return widget.i18n.t('wallet_status_rejected');
      case DebtStatus.uncollectable:
        return widget.i18n.t('wallet_status_uncollectable');
      case DebtStatus.unpayable:
        return widget.i18n.t('wallet_status_unpayable');
    }
  }

  void _showAddMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.i18n.t('wallet_add'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(widget.i18n.t('wallet_create_debt')),
              subtitle: Text(widget.i18n.t('wallet_create_debt_hint')),
              onTap: () {
                Navigator.pop(context);
                _createDebt();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt),
              title: Text(widget.i18n.t('wallet_receipt_create')),
              subtitle: Text(widget.i18n.t('wallet_receipt_empty_hint')),
              onTap: () {
                Navigator.pop(context);
                _createReceipt();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(widget.i18n.t('wallet_create_folder')),
              subtitle: Text(widget.i18n.t('wallet_create_folder_hint')),
              onTap: () {
                Navigator.pop(context);
                _createFolder();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_create_folder')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: widget.i18n.t('wallet_folder_name'),
            hintText: widget.i18n.t('wallet_folder_name_hint'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(widget.i18n.t('create')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final success = await _service.createFolder(result);
      if (success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('wallet_folder_created'))),
        );
      }
    }
  }

  Future<void> _renameFolder(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_rename_folder')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: widget.i18n.t('wallet_folder_name'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(widget.i18n.t('rename')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != oldName) {
      final success = await _service.renameFolder(oldName, result);
      if (success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('wallet_folder_renamed'))),
        );
      }
    }
  }

  Future<void> _deleteFolder(String folderName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_delete_folder')),
        content: Text(widget.i18n.t('wallet_delete_folder_confirm', params: [folderName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _service.deleteFolder(folderName);
      if (success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('wallet_folder_deleted'))),
        );
      }
    }
  }

  void _showFolderOptions(String folderName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.folder),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      folderName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(widget.i18n.t('rename')),
              onTap: () {
                Navigator.pop(context);
                _renameFolder(folderName);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text(
                widget.i18n.t('delete'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteFolder(folderName);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _createDebt() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateDebtPage(
          appPath: widget.appPath,
          i18n: widget.i18n,
        ),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _createReceipt() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateReceiptPage(
          appPath: widget.appPath,
          i18n: widget.i18n,
        ),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openDebt(DebtSummary debt) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DebtDetailPage(
          appPath: widget.appPath,
          debtId: debt.id,
          i18n: widget.i18n,
        ),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openReceipt(Receipt receipt) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptDetailPage(
          appPath: widget.appPath,
          receiptId: receipt.id,
          i18n: widget.i18n,
        ),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WalletSettingsPage(i18n: widget.i18n),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getDisplayTitle()),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.receipt_long),
              text: widget.i18n.t('wallet_debts'),
            ),
            Tab(
              icon: const Icon(Icons.receipt),
              text: widget.i18n.t('wallet_receipts'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: widget.i18n.t('filter'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: widget.i18n.t('settings'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary section
                if (_summary != null)
                  WalletSummaryWidget(
                    summary: _summary!,
                    i18n: widget.i18n,
                    onOwedToMeTap: () {
                      setState(() {
                        _showOnlyOwedToMe = true;
                        _showOnlyIOwe = false;
                      });
                      _tabController.animateTo(0);
                    },
                    onIOweTap: () {
                      setState(() {
                        _showOnlyIOwe = true;
                        _showOnlyOwedToMe = false;
                      });
                      _tabController.animateTo(0);
                    },
                  ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDebtsTab(theme),
                      _buildReceiptsTab(theme),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: Text(widget.i18n.t('wallet_add')),
      ),
    );
  }

  Widget _buildDebtsTab(ThemeData theme) {
    final debts = _filteredDebts;
    final hasContent = debts.isNotEmpty || _folders.isNotEmpty;

    if (!hasContent) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('wallet_no_debts'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.i18n.t('wallet_no_debts_hint'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Total items: folders + debts
    final totalItems = _folders.length + debts.length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          // Show folders first
          if (index < _folders.length) {
            final folder = _folders[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    Icons.folder,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                  title: Text(
                    folder,
                    style: theme.textTheme.titleMedium,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showFolderOptions(folder),
                  ),
                  onTap: () {
                    // TODO: Navigate to folder contents
                  },
                  onLongPress: () => _showFolderOptions(folder),
                ),
              ),
            );
          }

          // Show debts after folders
          final debtIndex = index - _folders.length;
          final debt = debts[debtIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DebtCardWidget(
              debt: debt,
              userNpub: _userNpub,
              i18n: widget.i18n,
              onTap: () => _openDebt(debt),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReceiptsTab(ThemeData theme) {
    if (_receipts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.i18n.t('wallet_receipt_empty'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.i18n.t('wallet_receipt_empty_hint'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _receipts.length,
        itemBuilder: (context, index) {
          final receipt = _receipts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ReceiptCardWidget(
              receipt: receipt,
              userNpub: _userNpub,
              i18n: widget.i18n,
              onTap: () => _openReceipt(receipt),
            ),
          );
        },
      ),
    );
  }
}
