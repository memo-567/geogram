/// Card widget for displaying a debt summary.
library;

import 'package:flutter/material.dart';

import '../../wallet/models/debt_entry.dart';
import '../../wallet/models/debt_summary.dart';
import '../../services/i18n_service.dart';

/// Card widget for displaying a debt
class DebtCardWidget extends StatelessWidget {
  final DebtSummary debt;
  final I18nService i18n;
  final String? userNpub;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DebtCardWidget({
    super.key,
    required this.debt,
    required this.i18n,
    this.userNpub,
    this.onTap,
    this.onLongPress,
  });

  bool get isCreditor => userNpub != null && debt.creditorNpub == userNpub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine counterparty
    final counterpartyName = isCreditor
        ? debt.debtorDisplayName
        : debt.creditorDisplayName;

    // Status color
    final statusColor = _getStatusColor(debt.status);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Direction indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isCreditor ? Colors.green : Colors.red)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isCreditor ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 20,
                      color: isCreditor ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Counterparty and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          counterpartyName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (debt.description.isNotEmpty)
                          Text(
                            debt.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        debt.formattedBalance,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isCreditor ? Colors.green : Colors.red,
                        ),
                      ),
                      if (debt.originalAmount != null &&
                          debt.currentBalance != debt.originalAmount)
                        Text(
                          'of ${debt.formattedOriginalAmount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Progress bar (if partially paid)
              if (debt.progress > 0 && debt.progress < 1) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: debt.progress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCreditor ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Status and metadata row
              Row(
                children: [
                  // Status badge
                  _StatusBadge(
                    status: debt.status,
                    statusText: debt.statusText,
                    color: statusColor,
                  ),

                  // Transfer indicator
                  if (debt.isFromTransfer) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz,
                              size: 12, color: Colors.purple),
                          const SizedBox(width: 4),
                          Text(
                            i18n.t('transferred'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.purple,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Due date or date info
                  if (debt.dueDate != null)
                    _DueDateBadge(
                      dueDate: debt.dueDate!,
                      daysUntilDue: debt.daysUntilDue,
                      isOverdue: debt.isOverdue,
                      i18n: i18n,
                    ),

                  // Signature status
                  if (!debt.allSignaturesValid)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.warning,
                        size: 16,
                        color: Colors.orange,
                      ),
                    )
                  else if (debt.isEstablished)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.verified,
                        size: 16,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        return Colors.grey;
      case DebtStatus.rejected:
        return Colors.red;
      case DebtStatus.uncollectable:
      case DebtStatus.unpayable:
        return Colors.grey;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final DebtStatus status;
  final String statusText;
  final Color color;

  const _StatusBadge({
    required this.status,
    required this.statusText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        statusText,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _DueDateBadge extends StatelessWidget {
  final String dueDate;
  final int? daysUntilDue;
  final bool isOverdue;
  final I18nService i18n;

  const _DueDateBadge({
    required this.dueDate,
    this.daysUntilDue,
    required this.isOverdue,
    required this.i18n,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isOverdue ? Colors.red : Colors.grey;

    String text;
    if (daysUntilDue == null) {
      text = dueDate;
    } else if (isOverdue) {
      text = '${-daysUntilDue!}d ${i18n.t('overdue')}';
    } else if (daysUntilDue == 0) {
      text = i18n.t('due_today');
    } else if (daysUntilDue! <= 7) {
      text = '${daysUntilDue}d ${i18n.t('left')}';
    } else {
      text = dueDate;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
