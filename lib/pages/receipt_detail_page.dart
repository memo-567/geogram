/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wallet/models/receipt.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';

/// Page for viewing and managing receipt details
class ReceiptDetailPage extends StatefulWidget {
  final String collectionPath;
  final String receiptId;
  final I18nService i18n;

  const ReceiptDetailPage({
    super.key,
    required this.collectionPath,
    required this.receiptId,
    required this.i18n,
  });

  @override
  State<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends State<ReceiptDetailPage> {
  final WalletService _service = WalletService();
  final ProfileService _profileService = ProfileService();

  Receipt? _receipt;
  bool _loading = true;
  String? _userNpub;
  bool _isPayer = false;
  bool _isPayee = false;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    setState(() => _loading = true);
    try {
      await _service.initializeCollection(widget.collectionPath);
      final receipt = await _service.getReceipt(widget.receiptId);

      final profile = _profileService.getProfile();
      _userNpub = profile.npub;

      if (receipt != null && _userNpub != null) {
        _isPayer = receipt.payer.npub == _userNpub;
        _isPayee = receipt.payee.npub == _userNpub;
      }

      setState(() {
        _receipt = receipt;
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

  String _getStatusLabel(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.draft:
        return widget.i18n.t('wallet_receipt_status_draft');
      case ReceiptStatus.issued:
        return widget.i18n.t('wallet_receipt_status_issued');
      case ReceiptStatus.pending:
        return widget.i18n.t('wallet_receipt_status_pending');
      case ReceiptStatus.confirmed:
        return widget.i18n.t('wallet_receipt_status_confirmed');
    }
  }

  Color _getStatusColor(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.draft:
        return Colors.grey;
      case ReceiptStatus.issued:
        return Colors.blue;
      case ReceiptStatus.pending:
        return Colors.orange;
      case ReceiptStatus.confirmed:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.draft:
        return Icons.edit_outlined;
      case ReceiptStatus.issued:
        return Icons.send;
      case ReceiptStatus.pending:
        return Icons.hourglass_empty;
      case ReceiptStatus.confirmed:
        return Icons.check_circle;
    }
  }

  String _getPaymentMethodLabel(String? method) {
    if (method == null) return '';
    final key = 'wallet_receipt_payment_$method';
    final translated = widget.i18n.t(key);
    if (translated == key) {
      return PaymentMethods.displayName(method);
    }
    return translated;
  }

  Future<void> _signAsPayer() async {
    final profile = _profileService.getProfile();
    if (_receipt == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_receipt_sign_payer_title')),
        content: Text(widget.i18n.t('wallet_receipt_sign_payer_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('sign')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _service.signReceiptAsPayer(
        receiptId: _receipt!.id,
        profile: profile,
      );
      if (result != null) {
        _showSuccess(widget.i18n.t('wallet_receipt_signed'));
        await _loadReceipt();
      } else {
        _showError(widget.i18n.t('wallet_receipt_sign_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _signAsPayee() async {
    final profile = _profileService.getProfile();
    if (_receipt == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_receipt_sign_payee_title')),
        content: Text(widget.i18n.t('wallet_receipt_sign_payee_message')),
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
      final result = await _service.signReceiptAsPayee(
        receiptId: _receipt!.id,
        profile: profile,
      );
      if (result != null) {
        _showSuccess(widget.i18n.t('wallet_receipt_confirmed'));
        await _loadReceipt();
      } else {
        _showError(widget.i18n.t('wallet_receipt_confirm_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _addWitness() async {
    final profile = _profileService.getProfile();
    if (_receipt == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_receipt_add_witness_title')),
        content: Text(widget.i18n.t('wallet_receipt_add_witness_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.i18n.t('wallet_receipt_witness')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _service.addReceiptWitness(
        receiptId: _receipt!.id,
        profile: profile,
      );
      if (result != null) {
        _showSuccess(widget.i18n.t('wallet_receipt_witness_added'));
        await _loadReceipt();
      } else {
        _showError(widget.i18n.t('wallet_receipt_witness_error'));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _copyReceiptId() async {
    if (_receipt == null) return;
    await Clipboard.setData(ClipboardData(text: _receipt!.id));
    _showSuccess(widget.i18n.t('copied'));
  }

  void _showActionsMenu() {
    final receipt = _receipt;
    if (receipt == null) return;

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
            // Payer can sign if not yet signed
            if (_isPayer && receipt.payerSignature == null)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: Text(widget.i18n.t('wallet_receipt_sign_as_payer')),
                subtitle:
                    Text(widget.i18n.t('wallet_receipt_sign_payer_hint')),
                onTap: () {
                  Navigator.pop(context);
                  _signAsPayer();
                },
              ),
            // Payee can confirm if payer has signed
            if (_isPayee &&
                receipt.payerSignature != null &&
                receipt.payeeSignature == null)
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(widget.i18n.t('wallet_receipt_confirm_receipt')),
                subtitle:
                    Text(widget.i18n.t('wallet_receipt_confirm_hint')),
                onTap: () {
                  Navigator.pop(context);
                  _signAsPayee();
                },
              ),
            // Anyone can add witness signature
            if (receipt.payerSignature != null &&
                !receipt.witnessSignatures.any((w) => w.npub == _userNpub))
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.purple),
                title: Text(widget.i18n.t('wallet_receipt_add_witness')),
                subtitle:
                    Text(widget.i18n.t('wallet_receipt_witness_hint')),
                onTap: () {
                  Navigator.pop(context);
                  _addWitness();
                },
              ),
            // Copy receipt ID
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(widget.i18n.t('wallet_receipt_copy_id')),
              onTap: () {
                Navigator.pop(context);
                _copyReceiptId();
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
        appBar: AppBar(title: Text(widget.i18n.t('wallet_receipt_detail'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final receipt = _receipt;
    if (receipt == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_receipt_detail'))),
        body: Center(
          child: Text(widget.i18n.t('wallet_receipt_not_found')),
        ),
      );
    }

    final statusColor = _getStatusColor(receipt.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_receipt_detail')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReceipt,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReceipt,
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
                            _getStatusIcon(receipt.status),
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getStatusLabel(receipt.status),
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
                      receipt.formattedAmount,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isPayer
                            ? Colors.red.shade700
                            : _isPayee
                                ? Colors.green.shade700
                                : theme.colorScheme.onSurface,
                      ),
                    ),
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
                              color: _isPayer
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              receipt.payer.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: _isPayer ? FontWeight.bold : null,
                              ),
                            ),
                            Text(
                              widget.i18n.t('wallet_receipt_payer'),
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
                              color: _isPayee
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              receipt.payee.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: _isPayee ? FontWeight.bold : null,
                              ),
                            ),
                            Text(
                              widget.i18n.t('wallet_receipt_payee'),
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
                    Text(receipt.description),
                    if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.i18n.t('wallet_receipt_notes'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(receipt.notes!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Details card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.i18n.t('details'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Timestamp
                    _buildDetailRow(
                      theme,
                      Icons.schedule,
                      widget.i18n.t('wallet_receipt_timestamp'),
                      receipt.formattedTimestamp,
                    ),
                    // Payment method
                    if (receipt.paymentMethod != null)
                      _buildDetailRow(
                        theme,
                        Icons.payment,
                        widget.i18n.t('wallet_receipt_payment_method'),
                        _getPaymentMethodLabel(receipt.paymentMethod),
                      ),
                    // Reference
                    if (receipt.reference != null)
                      _buildDetailRow(
                        theme,
                        Icons.tag,
                        widget.i18n.t('wallet_receipt_reference'),
                        receipt.reference!,
                      ),
                    // Location
                    if (receipt.location != null) ...[
                      _buildDetailRow(
                        theme,
                        Icons.location_on,
                        widget.i18n.t('wallet_receipt_location'),
                        receipt.location!.placeName ??
                            receipt.location!.coordinates,
                      ),
                      if (receipt.location!.accuracy != null)
                        _buildDetailRow(
                          theme,
                          Icons.gps_fixed,
                          widget.i18n.t('wallet_receipt_accuracy'),
                          '${receipt.location!.accuracy!.toStringAsFixed(0)} m',
                        ),
                    ],
                    // Tags
                    if (receipt.tags.isNotEmpty)
                      _buildDetailRow(
                        theme,
                        Icons.label,
                        widget.i18n.t('wallet_receipt_tags'),
                        receipt.tags.join(', '),
                      ),
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
                      widget.i18n.t('wallet_receipt_payer'),
                      receipt.payer.displayName,
                      receipt.payerSignature != null,
                      receipt.payerSignature?.timestamp,
                    ),
                    const SizedBox(height: 8),
                    _buildSignatureRow(
                      theme,
                      widget.i18n.t('wallet_receipt_payee'),
                      receipt.payee.displayName,
                      receipt.payeeSignature != null,
                      receipt.payeeSignature?.timestamp,
                    ),
                    if (receipt.witnessSignatures.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.i18n.t('wallet_witnesses'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...receipt.witnessSignatures.map((w) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildSignatureRow(
                              theme,
                              widget.i18n.t('wallet_witness'),
                              w.callsign ?? w.npub.substring(0, 16),
                              true,
                              w.timestamp,
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),

            // Attachments
            if (receipt.attachments.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.i18n.t('wallet_receipt_attachments'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...receipt.attachments.map((a) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file),
                            title: Text(a.filename),
                            subtitle: Text(
                              'SHA1: ${a.sha1.substring(0, 8)}...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showActionsMenu,
        icon: const Icon(Icons.menu),
        label: Text(widget.i18n.t('actions')),
      ),
    );
  }

  Widget _buildDetailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureRow(
    ThemeData theme,
    String role,
    String name,
    bool isSigned,
    DateTime? timestamp,
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isSigned
                  ? widget.i18n.t('wallet_signed')
                  : widget.i18n.t('wallet_pending'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSigned ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isSigned && timestamp != null)
              Text(
                '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
