/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Card widget for displaying a receipt summary.
library;

import 'package:flutter/material.dart';

import '../../wallet/models/currency.dart';
import '../../wallet/models/receipt.dart';
import '../../services/i18n_service.dart';

/// Card widget for displaying a receipt
class ReceiptCardWidget extends StatelessWidget {
  final Receipt receipt;
  final I18nService i18n;
  final String? userNpub;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ReceiptCardWidget({
    super.key,
    required this.receipt,
    required this.i18n,
    this.userNpub,
    this.onTap,
    this.onLongPress,
  });

  bool get isPayer => userNpub != null && receipt.payer.npub == userNpub;
  bool get isPayee => userNpub != null && receipt.payee.npub == userNpub;

  String get _formattedAmount {
    final currency = Currencies.byCode(receipt.currency);
    if (currency != null) {
      return currency.format(receipt.amount);
    }
    return '${receipt.amount.toStringAsFixed(2)} ${receipt.currency}';
  }

  Color _getStatusColor(ThemeData theme) {
    switch (receipt.status) {
      case ReceiptStatus.draft:
        return theme.colorScheme.outline;
      case ReceiptStatus.issued:
        return Colors.orange;
      case ReceiptStatus.pending:
        return Colors.orange;
      case ReceiptStatus.confirmed:
        return Colors.green;
    }
  }

  IconData _getStatusIcon() {
    switch (receipt.status) {
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

  String _getStatusLabel() {
    switch (receipt.status) {
      case ReceiptStatus.draft:
        return i18n.t('wallet_receipt_status_draft');
      case ReceiptStatus.issued:
        return i18n.t('wallet_receipt_status_issued');
      case ReceiptStatus.pending:
        return i18n.t('wallet_receipt_status_pending');
      case ReceiptStatus.confirmed:
        return i18n.t('wallet_receipt_status_confirmed');
    }
  }

  String _getDirectionLabel() {
    if (isPayer) {
      return i18n.t('wallet_paid_to').replaceAll('{0}', receipt.payee.displayName);
    } else if (isPayee) {
      return i18n.t('wallet_received_from').replaceAll('{0}', receipt.payer.displayName);
    }
    return '${receipt.payer.displayName} -> ${receipt.payee.displayName}';
  }

  String? _getPaymentMethodLabel() {
    if (receipt.paymentMethod == null) return null;
    return i18n.t('wallet_receipt_payment_${receipt.paymentMethod}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(theme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with amount and status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPayer
                    ? Colors.red.withValues(alpha: 0.1)
                    : isPayee
                        ? Colors.green.withValues(alpha: 0.1)
                        : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  // Direction icon
                  Icon(
                    isPayer
                        ? Icons.arrow_upward
                        : isPayee
                            ? Icons.arrow_downward
                            : Icons.swap_horiz,
                    color: isPayer
                        ? Colors.red
                        : isPayee
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  // Amount
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formattedAmount,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPayer
                                ? Colors.red.shade700
                                : isPayee
                                    ? Colors.green.shade700
                                    : theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _getDirectionLabel(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getStatusIcon(),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusLabel(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Description and metadata
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.description,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Metadata row
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      // Date
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            receipt.formattedTimestamp,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      // Payment method
                      if (receipt.paymentMethod != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.payment,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getPaymentMethodLabel() ?? receipt.paymentMethod!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      // Location
                      if (receipt.location != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              receipt.location!.placeName ?? i18n.t('wallet_receipt_location_recorded'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      // Attachments
                      if (receipt.attachments.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.attach_file,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${receipt.attachments.length}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      // Signatures
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (receipt.payerSignature != null)
                            Icon(
                              Icons.check_circle,
                              size: 14,
                              color: Colors.green,
                            ),
                          if (receipt.payeeSignature != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                            ),
                          if (receipt.witnessSignatures.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.visibility,
                                    size: 14,
                                    color: Colors.blue,
                                  ),
                                  Text(
                                    '${receipt.witnessSignatures.length}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.blue,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
