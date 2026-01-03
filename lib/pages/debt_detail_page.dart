/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wallet/models/debt_entry.dart';
import '../wallet/models/debt_ledger.dart';
import '../wallet/services/wallet_service.dart';
import '../services/direct_message_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';
import 'contract_document_page.dart';

/// Page for viewing and managing debt details
class DebtDetailPage extends StatefulWidget {
  final String collectionPath;
  final String debtId;
  final I18nService i18n;

  const DebtDetailPage({
    super.key,
    required this.collectionPath,
    required this.debtId,
    required this.i18n,
  });

  @override
  State<DebtDetailPage> createState() => _DebtDetailPageState();
}

class _DebtDetailPageState extends State<DebtDetailPage> {
  final WalletService _service = WalletService();
  final ProfileService _profileService = ProfileService();

  DebtLedger? _ledger;
  bool _loading = true;
  String? _userNpub;
  bool _isCreditor = false;
  bool _isDebtor = false;

  @override
  void initState() {
    super.initState();
    _loadDebt();
  }

  Future<void> _loadDebt() async {
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

  IconData _getStatusIcon(DebtStatus status) {
    switch (status) {
      case DebtStatus.draft:
        return Icons.edit_outlined;
      case DebtStatus.pending:
        return Icons.hourglass_empty;
      case DebtStatus.open:
        return Icons.lock_open;
      case DebtStatus.paid:
        return Icons.check_circle;
      case DebtStatus.expired:
        return Icons.timer_off;
      case DebtStatus.retired:
        return Icons.block;
      case DebtStatus.rejected:
        return Icons.cancel;
      case DebtStatus.uncollectable:
        return Icons.person_off;
      case DebtStatus.unpayable:
        return Icons.money_off;
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

  Future<void> _confirmDebt() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_confirm_debt_title')),
        content: Text(widget.i18n.t('wallet_confirm_debt_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.confirmDebt(
        debtId: _ledger!.id,
        author: profile.callsign,
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_debt_confirmed'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_confirm_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _rejectDebt() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_reject_debt_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.i18n.t('wallet_reject_debt_message')),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_reject_reason'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('reject')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.rejectDebt(
        debtId: _ledger!.id,
        author: profile.callsign,
        content: reasonController.text,
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_debt_rejected'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_reject_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _addPayment() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String? method;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.i18n.t('wallet_add_payment_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('wallet_amount'),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                    suffixText: _ledger!.currency ?? '',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('wallet_payment_method'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'cash',
                      child: Text(widget.i18n.t('wallet_method_cash')),
                    ),
                    DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text(widget.i18n.t('wallet_method_bank_transfer')),
                    ),
                    DropdownMenuItem(
                      value: 'card',
                      child: Text(widget.i18n.t('wallet_method_card')),
                    ),
                    DropdownMenuItem(
                      value: 'crypto',
                      child: Text(widget.i18n.t('wallet_method_crypto')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(widget.i18n.t('wallet_method_other')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => method = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('wallet_note'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(widget.i18n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.i18n.t('wallet_add_payment')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      _showError(widget.i18n.t('wallet_invalid_amount'));
      return;
    }

    final newBalance = _ledger!.currentBalance - amount;

    try {
      final success = await _service.recordPayment(
        debtId: _ledger!.id,
        author: profile.callsign,
        amount: amount,
        newBalance: newBalance,
        method: method,
        content: noteController.text,
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_payment_added'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_payment_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _confirmPayment(DebtEntry paymentEntry) async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_confirm_payment_title')),
        content: Text(widget.i18n.t('wallet_confirm_payment_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.confirmPayment(
        debtId: _ledger!.id,
        author: profile.callsign,
        content: 'Payment confirmed.',
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_payment_confirmed'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_confirm_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _addNote() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_add_note_title')),
        content: TextField(
          controller: noteController,
          decoration: InputDecoration(
            labelText: widget.i18n.t('wallet_note'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('wallet_add_note')),
          ),
        ],
      ),
    );

    if (confirmed != true || noteController.text.isEmpty) return;

    try {
      final success = await _service.addNote(
        debtId: _ledger!.id,
        author: profile.callsign,
        content: noteController.text,
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_note_added'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_note_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _settleDebt() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_settle_debt_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.i18n.t('wallet_settle_debt_message')),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_note'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('wallet_settle')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.changeStatus(
        debtId: _ledger!.id,
        author: profile.callsign,
        newStatus: DebtStatus.paid,
        content: noteController.text.isNotEmpty ? noteController.text : 'Debt settled.',
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_debt_settled'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_settle_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _cancelDebt() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_cancel_debt_title')),
        content: Text(widget.i18n.t('wallet_cancel_debt_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('wallet_cancel_debt')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.changeStatus(
        debtId: _ledger!.id,
        author: profile.callsign,
        newStatus: DebtStatus.retired,
        content: 'Debt cancelled by creditor.',
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_debt_cancelled'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_cancel_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _markUncollectable() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_mark_uncollectable_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.i18n.t('wallet_mark_uncollectable_message')),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_reason'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.brown,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.declareUncollectable(
        debtId: _ledger!.id,
        reason: reasonController.text.isNotEmpty
            ? reasonController.text
            : 'Marked as uncollectable.',
        content: 'Declared uncollectable by ${profile.callsign}.',
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_marked_uncollectable'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_uncollectable_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _markUnpayable() async {
    final profile = _profileService.getProfile();
    if (_ledger == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_mark_unpayable_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.i18n.t('wallet_mark_unpayable_message')),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_reason'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.brown,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.declareUnpayable(
        debtId: _ledger!.id,
        reason: reasonController.text.isNotEmpty
            ? reasonController.text
            : 'Marked as unpayable.',
        content: 'Declared unpayable by ${profile.callsign}.',
        profile: profile,
      );
      if (success) {
        _showSuccess(widget.i18n.t('wallet_marked_unpayable'));
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_unpayable_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteEntry(int entryIndex) async {
    if (_ledger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_delete_entry_title')),
        content: Text(widget.i18n.t('wallet_delete_entry_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.deleteEntry(
        debtId: _ledger!.id,
        entryIndex: entryIndex,
      );
      if (success) {
        await _loadDebt();
      } else {
        _showError(widget.i18n.t('wallet_delete_entry_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _deleteDebt() async {
    if (_ledger == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_delete_debt_title')),
        content: Text(widget.i18n.t('wallet_delete_debt_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _service.deleteDebt(_ledger!.id);
      if (success && mounted) {
        Navigator.pop(context, true); // Return to list
      } else {
        _showError(widget.i18n.t('wallet_delete_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _viewContract() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractDocumentPage(
          collectionPath: widget.collectionPath,
          debtId: widget.debtId,
          i18n: widget.i18n,
        ),
      ),
    ).then((_) => _loadDebt());
  }

  Future<void> _requestSignature() async {
    if (_ledger == null) return;

    final debtorCallsign = _ledger!.debtor;
    if (debtorCallsign == null || debtorCallsign.isEmpty) {
      _showError(widget.i18n.t('wallet_no_debtor'));
      return;
    }

    // Show informative popup before sending
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.i18n.t('wallet_request_signature_title'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.i18n.t('wallet_request_signature_info')),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.i18n.t('wallet_request_signature_device_info'),
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
            icon: const Icon(Icons.send, size: 18),
            label: Text(widget.i18n.t('wallet_send_request')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final currency = _ledger!.currencyObj;
    final amountStr = currency?.format(_ledger!.currentBalance) ??
        '${_ledger!.currentBalance} ${_ledger!.currency}';

    // Build message content
    final message = widget.i18n.t(
      'wallet_signature_request_message',
      params: [amountStr, _ledger!.description],
    );

    try {
      final dmService = DirectMessageService();
      await dmService.sendMessage(
        debtorCallsign,
        message,
        metadata: {
          'type': 'debt_signature_request',
          'debt_id': _ledger!.id,
        },
      );

      _showSuccess(widget.i18n.t('wallet_signature_requested'));
    } catch (e) {
      _showError(widget.i18n.t('wallet_signature_request_error'));
    }
  }

  void _showActionsMenu() {
    final ledger = _ledger;
    if (ledger == null) return;

    final isOpenOrPending = ledger.isPending || ledger.isActive;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.i18n.t('actions'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const Divider(height: 1),
            // View Contract - always available
            ListTile(
              leading: Icon(Icons.description, color: Theme.of(context).colorScheme.primary),
              title: Text(widget.i18n.t('wallet_view_contract')),
              onTap: () {
                Navigator.pop(context);
                _viewContract();
              },
            ),
            // Pending actions for debtor
            if (ledger.isPending && _isDebtor) ...[
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(widget.i18n.t('wallet_confirm_debt')),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDebt();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: Text(widget.i18n.t('wallet_reject_debt')),
                onTap: () {
                  Navigator.pop(context);
                  _rejectDebt();
                },
              ),
            ],
            // Pending actions for creditor - can cancel/withdraw or request signature
            if (ledger.isPending && _isCreditor) ...[
              ListTile(
                leading: const Icon(Icons.send, color: Colors.blue),
                title: Text(widget.i18n.t('wallet_request_signature')),
                onTap: () {
                  Navigator.pop(context);
                  _requestSignature();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.orange),
                title: Text(widget.i18n.t('wallet_cancel_debt')),
                onTap: () {
                  Navigator.pop(context);
                  _cancelDebt();
                },
              ),
            ],
            // Active debt actions
            if (ledger.isActive) ...[
              // Debtor can add payment
              if (_isDebtor)
                ListTile(
                  leading: const Icon(Icons.payment),
                  title: Text(widget.i18n.t('wallet_add_payment')),
                  onTap: () {
                    Navigator.pop(context);
                    _addPayment();
                  },
                ),
              // Creditor can settle when balance is 0 or negative
              if (_isCreditor && ledger.currentBalance <= 0)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(widget.i18n.t('wallet_settle_debt')),
                  onTap: () {
                    Navigator.pop(context);
                    _settleDebt();
                  },
                ),
              // Creditor can mark as uncollectable
              if (_isCreditor)
                ListTile(
                  leading: const Icon(Icons.person_off, color: Colors.brown),
                  title: Text(widget.i18n.t('wallet_mark_uncollectable')),
                  onTap: () {
                    Navigator.pop(context);
                    _markUncollectable();
                  },
                ),
              // Debtor can mark as unpayable
              if (_isDebtor)
                ListTile(
                  leading: const Icon(Icons.money_off, color: Colors.brown),
                  title: Text(widget.i18n.t('wallet_mark_unpayable')),
                  onTap: () {
                    Navigator.pop(context);
                    _markUnpayable();
                  },
                ),
            ],
            // Both can add notes on open/pending debts
            if (isOpenOrPending)
              ListTile(
                leading: const Icon(Icons.note_add),
                title: Text(widget.i18n.t('wallet_add_note')),
                onTap: () {
                  Navigator.pop(context);
                  _addNote();
                },
              ),
            const Divider(),
            // Delete debt - always available
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(widget.i18n.t('wallet_delete_debt')),
              onTap: () {
                Navigator.pop(context);
                _deleteDebt();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_debt_detail'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ledger = _ledger;
    if (ledger == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_debt_detail'))),
        body: Center(
          child: Text(widget.i18n.t('wallet_debt_not_found')),
        ),
      );
    }

    final currency = ledger.currencyObj;
    final statusColor = _getStatusColor(ledger.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_debt_detail')),
      ),
      body: RefreshIndicator(
        onRefresh: _loadDebt,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header card with amount and status
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getStatusIcon(ledger.status),
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getStatusLabel(ledger.status),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Amount
                    Text(
                      currency?.format(ledger.currentBalance) ??
                          '${ledger.currentBalance.toStringAsFixed(2)} ${ledger.currency}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isCreditor
                            ? Colors.green.shade700
                            : _isDebtor
                                ? Colors.red.shade700
                                : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (ledger.originalAmount != ledger.currentBalance) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.i18n.t('wallet_original')}: ${currency?.format(ledger.originalAmount ?? 0) ?? ledger.originalAmount?.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Direction info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Icon(
                              Icons.person,
                              size: 20,
                              color: _isCreditor
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ledger.creditorName ?? ledger.creditor ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight:
                                    _isCreditor ? FontWeight.bold : null,
                              ),
                            ),
                            Text(
                              widget.i18n.t('wallet_creditor'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Icon(
                            Icons.arrow_forward,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Column(
                          children: [
                            Icon(
                              Icons.person,
                              size: 20,
                              color: _isDebtor
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ledger.debtorName ?? ledger.debtor ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: _isDebtor ? FontWeight.bold : null,
                              ),
                            ),
                            Text(
                              widget.i18n.t('wallet_debtor'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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
            const SizedBox(height: 16),

            // Description
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
                    if (ledger.terms != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.i18n.t('wallet_terms'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(ledger.terms!),
                    ],
                    if (ledger.dueDate != null) ...[
                      const SizedBox(height: 16),
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

            // Signatures status
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
                    if (ledger.witnessEntries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...ledger.witnessEntries.map((w) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildSignatureRow(
                              theme,
                              widget.i18n.t('wallet_witness'),
                              w.author,
                              w.isSigned,
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Entry timeline
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.i18n.t('wallet_history'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${ledger.entries.length} ${widget.i18n.t('wallet_entries')}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...ledger.entries.reversed.toList().asMap().entries.map(
                      (mapEntry) {
                        // mapEntry.key is reversed index, calculate actual index
                        final actualIndex = ledger.entries.length - 1 - mapEntry.key;
                        return _buildEntryItem(theme, mapEntry.value, actualIndex);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: (_isCreditor || _isDebtor)
          ? FloatingActionButton.extended(
              onPressed: _showActionsMenu,
              icon: const Icon(Icons.menu),
              label: Text(widget.i18n.t('actions')),
            )
          : null,
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
              Text(
                name,
                style: theme.textTheme.bodyMedium,
              ),
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

  Widget _buildEntryItem(ThemeData theme, DebtEntry entry, int entryIndex) {
    final hasUnconfirmedPayment = entry.type == DebtEntryType.payment &&
        !_ledger!.entries.any((e) =>
            e.type == DebtEntryType.confirmPayment &&
            e.timestamp.compareTo(entry.timestamp) > 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _getEntryTypeIcon(entry.type),
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              Container(
                width: 2,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Entry content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getEntryTypeLabel(entry.type),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      entry.timestamp.substring(0, 16).replaceAll('_', ':'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.i18n.t('by')}: ${entry.author}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.content,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (entry.amount != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${widget.i18n.t('wallet_amount')}: ${_ledger!.currencyObj?.format(entry.amount!) ?? entry.amount?.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (entry.balance != null) ...[
                  Text(
                    '${widget.i18n.t('wallet_balance')}: ${_ledger!.currencyObj?.format(entry.balance!) ?? entry.balance?.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // Confirm payment button for creditor
                if (hasUnconfirmedPayment && _isCreditor) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _confirmPayment(entry),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(widget.i18n.t('wallet_confirm_payment')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
