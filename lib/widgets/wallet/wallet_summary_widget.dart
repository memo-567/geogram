/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Widget displaying wallet summary with owed/owing totals.
library;

import 'package:flutter/material.dart';

import '../../wallet/models/debt_summary.dart';
import '../../services/i18n_service.dart';

/// Widget showing wallet balance summary
class WalletSummaryWidget extends StatelessWidget {
  final WalletSummary summary;
  final I18nService i18n;
  final VoidCallback? onOwedToMeTap;
  final VoidCallback? onIOweTap;

  const WalletSummaryWidget({
    super.key,
    required this.summary,
    required this.i18n,
    this.onOwedToMeTap,
    this.onIOweTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('wallet_summary'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Owed to me
                Expanded(
                  child: _SummaryCard(
                    label: i18n.t('wallet_owed_to_me'),
                    amounts: summary.owedToYou,
                    color: Colors.green,
                    icon: Icons.arrow_downward,
                    count: summary.creditorDebtsCount,
                    i18n: i18n,
                    onTap: onOwedToMeTap,
                  ),
                ),
                const SizedBox(width: 16),
                // I owe
                Expanded(
                  child: _SummaryCard(
                    label: i18n.t('wallet_i_owe'),
                    amounts: summary.youOwe,
                    color: Colors.red,
                    icon: Icons.arrow_upward,
                    count: summary.debtorDebtsCount,
                    i18n: i18n,
                    onTap: onIOweTap,
                  ),
                ),
              ],
            ),
            // Active debts count
            if (summary.totalActiveCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    i18n.t('wallet_active_debts').replaceAll('{0}', summary.totalActiveCount.toString()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (summary.pendingCount > 0) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.hourglass_empty,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      i18n.t('wallet_pending_debts').replaceAll('{0}', summary.pendingCount.toString()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final Map<String, double> amounts;
  final Color color;
  final IconData icon;
  final int count;
  final I18nService i18n;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.label,
    required this.amounts,
    required this.color,
    required this.icon,
    required this.count,
    required this.i18n,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (amounts.isEmpty)
              Text(
                '-',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...amounts.entries.map((e) => Text(
                    _formatAmount(e.key, e.value),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color.withValues(alpha: 0.9),
                      fontWeight: FontWeight.bold,
                    ),
                  )),
            if (count > 0) ...[
              const SizedBox(height: 4),
              Text(
                i18n.t('wallet_debt_count').replaceAll('{0}', count.toString()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAmount(String currency, double amount) {
    // Simple formatting - could use Currency class for proper formatting
    switch (currency) {
      case 'EUR':
        return '€${amount.toStringAsFixed(2)}';
      case 'USD':
        return '\$${amount.toStringAsFixed(2)}';
      case 'GBP':
        return '£${amount.toStringAsFixed(2)}';
      case 'MIN':
        return _formatDuration(amount.toInt());
      default:
        return '${amount.toStringAsFixed(2)} $currency';
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}
