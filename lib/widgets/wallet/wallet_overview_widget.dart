/// Wallet overview widget showing summary of debts.
///
/// Displays total amounts owed to you and that you owe,
/// with breakdowns by currency and status.
library;

import 'package:flutter/material.dart';

import '../../wallet/models/debt_summary.dart';
import '../../wallet/models/currency.dart';
import '../../services/i18n_service.dart';

/// Overview widget showing wallet summary
class WalletOverviewWidget extends StatelessWidget {
  final WalletSummary summary;
  final I18nService i18n;
  final VoidCallback? onOwedToYouTap;
  final VoidCallback? onYouOweTap;
  final VoidCallback? onPendingTap;

  const WalletOverviewWidget({
    super.key,
    required this.summary,
    required this.i18n,
    this.onOwedToYouTap,
    this.onYouOweTap,
    this.onPendingTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  i18n.t('wallet_overview'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary cards row
            Row(
              children: [
                // Owed to you (positive - green)
                Expanded(
                  child: _SummaryCard(
                    title: i18n.t('owed_to_you'),
                    amounts: summary.owedToYou,
                    count: summary.creditorDebtsCount,
                    color: Colors.green,
                    icon: Icons.arrow_downward,
                    onTap: onOwedToYouTap,
                  ),
                ),
                const SizedBox(width: 12),
                // You owe (negative - red)
                Expanded(
                  child: _SummaryCard(
                    title: i18n.t('you_owe'),
                    amounts: summary.youOwe,
                    count: summary.debtorDebtsCount,
                    color: Colors.red,
                    icon: Icons.arrow_upward,
                    onTap: onYouOweTap,
                  ),
                ),
              ],
            ),

            // Pending and overdue indicators
            if (summary.pendingCount > 0 || summary.overdueCount > 0) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (summary.pendingCount > 0)
                    _StatusBadge(
                      label: '${summary.pendingCount} ${i18n.t('pending')}',
                      color: Colors.orange,
                      icon: Icons.hourglass_empty,
                      onTap: onPendingTap,
                    ),
                  if (summary.pendingCount > 0 && summary.overdueCount > 0)
                    const SizedBox(width: 8),
                  if (summary.overdueCount > 0)
                    _StatusBadge(
                      label: '${summary.overdueCount} ${i18n.t('overdue')}',
                      color: Colors.red,
                      icon: Icons.warning,
                    ),
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
  final String title;
  final Map<String, double> amounts;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.title,
    required this.amounts,
    required this.count,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (amounts.isEmpty)
              Text(
                '-',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              )
            else
              ..._buildAmountLines(theme, color),
            const SizedBox(height: 4),
            Text(
              '$count ${count == 1 ? 'debt' : 'debts'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAmountLines(ThemeData theme, Color color) {
    final widgets = <Widget>[];
    for (final entry in amounts.entries) {
      final currency = Currencies.byCode(entry.key);
      final formatted = currency?.format(entry.value) ??
          '${entry.value.toStringAsFixed(2)} ${entry.key}';
      widgets.add(
        Text(
          formatted,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );
    }
    return widgets;
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
