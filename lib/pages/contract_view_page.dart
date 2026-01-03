/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../wallet/models/debt_entry.dart';
import '../wallet/models/debt_ledger.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';

/// Read-only contract view page with option to sign.
class ContractViewPage extends StatefulWidget {
  final String collectionPath;
  final String debtId;
  final I18nService i18n;

  const ContractViewPage({
    super.key,
    required this.collectionPath,
    required this.debtId,
    required this.i18n,
  });

  @override
  State<ContractViewPage> createState() => _ContractViewPageState();
}

class _ContractViewPageState extends State<ContractViewPage> {
  final WalletService _service = WalletService();
  final ProfileService _profileService = ProfileService();

  DebtLedger? _ledger;
  bool _loading = true;
  bool _signing = false;
  String? _userNpub;
  bool _isCreditor = false;
  bool _isDebtor = false;
  bool _hasUserSigned = false;

  @override
  void initState() {
    super.initState();
    _loadContract();
  }

  Future<void> _loadContract() async {
    setState(() => _loading = true);
    try {
      await _service.initializeCollection(widget.collectionPath);
      final ledger = await _service.findDebt(widget.debtId);

      final profile = _profileService.getProfile();
      _userNpub = profile.npub;

      if (ledger != null && _userNpub != null) {
        _isCreditor = ledger.creditorNpub == _userNpub;
        _isDebtor = ledger.debtorNpub == _userNpub;

        // Verify signatures to update verified status on entries
        await _service.verifyDebt(ledger);

        // Check if user has already signed
        _hasUserSigned = ledger.entries.any((entry) =>
            entry.npub == _userNpub &&
            entry.isSigned &&
            (entry.type == DebtEntryType.create || entry.type == DebtEntryType.confirm));
      }

      setState(() {
        _ledger = ledger;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
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

  Color _getStatusColor(DebtStatus status) {
    switch (status) {
      case DebtStatus.draft:
        return Colors.grey;
      case DebtStatus.pending:
        return Colors.orange;
      case DebtStatus.open:
        return Colors.blue;
      case DebtStatus.paid:
        return Colors.green;
      case DebtStatus.expired:
        return Colors.red;
      case DebtStatus.retired:
        return Colors.purple;
      case DebtStatus.rejected:
        return Colors.red;
      case DebtStatus.uncollectable:
        return Colors.brown;
      case DebtStatus.unpayable:
        return Colors.brown;
    }
  }

  Future<void> _signContract() async {
    if (_ledger == null || _hasUserSigned) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.i18n.t('wallet_sign_contract'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.i18n.t('wallet_sign_contract_message')),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.i18n.t('wallet_confirm_debt_message'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit, size: 18),
            label: Text(widget.i18n.t('wallet_sign_contract')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _signing = true);

    try {
      final profile = _profileService.getProfile();
      final success = await _service.confirmDebt(
        debtId: _ledger!.id,
        author: profile.callsign,
        profile: profile,
      );

      if (success) {
        _showSuccess(widget.i18n.t('wallet_debt_confirmed'));
        await _loadContract();
      } else {
        _showError(widget.i18n.t('wallet_confirm_error'));
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _signing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_contract_title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ledger = _ledger;
    if (ledger == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_contract_title'))),
        body: Center(
          child: Text(widget.i18n.t('wallet_debt_not_found')),
        ),
      );
    }

    final currency = ledger.currencyObj;
    final statusColor = _getStatusColor(ledger.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_contract_title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _getStatusLabel(ledger.status),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Amount
                    Text(
                      currency?.format(ledger.currentBalance) ??
                          '${ledger.currentBalance.toStringAsFixed(2)} ${ledger.currency}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Parties
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildPartyInfo(
                          theme,
                          widget.i18n.t('wallet_creditor'),
                          ledger.creditorName ?? ledger.creditor ?? '',
                          _isCreditor,
                          ledger.hasValidCreate,
                        ),
                        Icon(
                          Icons.arrow_forward,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        _buildPartyInfo(
                          theme,
                          widget.i18n.t('wallet_debtor'),
                          ledger.debtorName ?? ledger.debtor ?? '',
                          _isDebtor,
                          ledger.hasValidConfirm,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.i18n.t('wallet_description'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(ledger.description),
                    if (ledger.dueDate != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.event,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.i18n.t('wallet_due_date')}: ${ledger.dueDate}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Signature status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.i18n.t('wallet_signatures'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSignatureRow(
                      theme,
                      widget.i18n.t('wallet_creditor'),
                      ledger.creditorName ?? ledger.creditor ?? '',
                      ledger.hasValidCreate,
                    ),
                    const SizedBox(height: 8),
                    _buildSignatureRow(
                      theme,
                      widget.i18n.t('wallet_debtor'),
                      ledger.debtorName ?? ledger.debtor ?? '',
                      ledger.hasValidConfirm,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Terms section (if present)
            if (ledger.terms != null && ledger.terms!.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.i18n.t('wallet_terms'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ledger.terms!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Full contract content (entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.i18n.t('wallet_history'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...ledger.entries.map((entry) => _buildEntryItem(theme, entry)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80), // Space for bottom button
          ],
        ),
      ),
      bottomNavigationBar: (_isDebtor && ledger.isPending && !_hasUserSigned)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _signing ? null : _signContract,
                  icon: _signing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.edit),
                  label: Text(widget.i18n.t('wallet_sign_contract')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            )
          : _hasUserSigned
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            widget.i18n.t('wallet_already_signed'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
    );
  }

  Widget _buildPartyInfo(
    ThemeData theme,
    String role,
    String name,
    bool isCurrentUser,
    bool hasSigned,
  ) {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              backgroundColor: isCurrentUser
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                color: isCurrentUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasSigned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isCurrentUser ? FontWeight.bold : null,
          ),
        ),
        Text(
          role,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureRow(
    ThemeData theme,
    String role,
    String name,
    bool isSigned,
  ) {
    return Row(
      children: [
        Icon(
          isSigned ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 20,
          color: isSigned ? Colors.green : theme.colorScheme.outline,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(name, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        Text(
          isSigned
              ? widget.i18n.t('wallet_signed')
              : widget.i18n.t('wallet_pending'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSigned ? Colors.green : Colors.orange,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEntryItem(ThemeData theme, DebtEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getEntryTypeIcon(entry.type),
              size: 14,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _getEntryTypeLabel(entry.type),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (entry.isSigned)
                      Icon(
                        entry.isVerified ? Icons.verified : Icons.warning_amber,
                        size: 14,
                        color: entry.isVerified ? Colors.green : Colors.orange,
                      ),
                  ],
                ),
                Text(
                  '${widget.i18n.t('by')}: ${entry.author}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.content.isNotEmpty)
                  Text(
                    entry.content.length > 100
                        ? '${entry.content.substring(0, 100)}...'
                        : entry.content,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getEntryTypeIcon(DebtEntryType type) {
    switch (type) {
      case DebtEntryType.create:
        return Icons.add_circle;
      case DebtEntryType.confirm:
        return Icons.check_circle;
      case DebtEntryType.reject:
        return Icons.cancel;
      case DebtEntryType.witness:
        return Icons.visibility;
      case DebtEntryType.payment:
        return Icons.payment;
      case DebtEntryType.confirmPayment:
        return Icons.done_all;
      case DebtEntryType.workSession:
        return Icons.work;
      case DebtEntryType.confirmSession:
        return Icons.task_alt;
      case DebtEntryType.statusChange:
        return Icons.swap_horiz;
      case DebtEntryType.note:
        return Icons.note;
      case DebtEntryType.transfer:
        return Icons.send;
      case DebtEntryType.transferReceive:
        return Icons.call_received;
      case DebtEntryType.transferPayment:
        return Icons.swap_calls;
    }
  }

  String _getEntryTypeLabel(DebtEntryType type) {
    switch (type) {
      case DebtEntryType.create:
        return widget.i18n.t('wallet_entry_create');
      case DebtEntryType.confirm:
        return widget.i18n.t('wallet_entry_confirm');
      case DebtEntryType.reject:
        return widget.i18n.t('wallet_entry_reject');
      case DebtEntryType.witness:
        return widget.i18n.t('wallet_entry_witness');
      case DebtEntryType.payment:
        return widget.i18n.t('wallet_entry_payment');
      case DebtEntryType.confirmPayment:
        return widget.i18n.t('wallet_entry_confirm_payment');
      case DebtEntryType.workSession:
        return widget.i18n.t('wallet_entry_work_session');
      case DebtEntryType.confirmSession:
        return widget.i18n.t('wallet_entry_confirm_session');
      case DebtEntryType.statusChange:
        return widget.i18n.t('wallet_entry_status_change');
      case DebtEntryType.note:
        return widget.i18n.t('wallet_entry_note');
      case DebtEntryType.transfer:
        return widget.i18n.t('wallet_entry_transfer');
      case DebtEntryType.transferReceive:
        return widget.i18n.t('wallet_entry_transfer_receive');
      case DebtEntryType.transferPayment:
        return widget.i18n.t('wallet_entry_transfer_payment');
    }
  }
}
