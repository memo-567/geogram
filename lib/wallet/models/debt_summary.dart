/// Lightweight summary model for displaying debts in lists.
///
/// This provides computed data from a DebtLedger without needing
/// to keep the full ledger in memory.
library;

import 'debt_entry.dart';
import 'debt_ledger.dart';
import 'currency.dart';

/// Summary of a debt for display in lists and cards.
class DebtSummary {
  /// Unique debt identifier
  final String id;

  /// Human-readable description
  final String description;

  /// File path to the ledger
  final String? filePath;

  /// Current status
  final DebtStatus status;

  /// Whether this is a time-based debt
  final bool isTimeBased;

  /// Currency code
  final String? currency;

  /// Original amount
  final double? originalAmount;

  /// Current balance
  final double currentBalance;

  /// Total paid/worked
  final double totalPaid;

  /// Creditor callsign
  final String? creditor;

  /// Creditor npub
  final String? creditorNpub;

  /// Creditor name
  final String? creditorName;

  /// Debtor callsign
  final String? debtor;

  /// Debtor npub
  final String? debtorNpub;

  /// Debtor name
  final String? debtorName;

  /// Due date (YYYY-MM-DD)
  final String? dueDate;

  /// Created timestamp
  final DateTime? createdAt;

  /// Last modified timestamp
  final DateTime? modifiedAt;

  /// Number of entries in ledger
  final int entryCount;

  /// Number of payments made
  final int paymentCount;

  /// Whether all signatures are valid
  final bool allSignaturesValid;

  /// Whether both parties have signed (debt is established)
  final bool isEstablished;

  /// Number of witnesses
  final int witnessCount;

  /// Number of transfers out
  final int transferCount;

  /// Total amount transferred out
  final double totalTransferredOut;

  /// Whether this debt was created from a transfer
  final bool isFromTransfer;

  /// Source debt ID if created from transfer
  final String? sourceDebtId;

  DebtSummary({
    required this.id,
    required this.description,
    this.filePath,
    required this.status,
    required this.isTimeBased,
    this.currency,
    this.originalAmount,
    required this.currentBalance,
    required this.totalPaid,
    this.creditor,
    this.creditorNpub,
    this.creditorName,
    this.debtor,
    this.debtorNpub,
    this.debtorName,
    this.dueDate,
    this.createdAt,
    this.modifiedAt,
    required this.entryCount,
    required this.paymentCount,
    required this.allSignaturesValid,
    required this.isEstablished,
    required this.witnessCount,
    required this.transferCount,
    required this.totalTransferredOut,
    required this.isFromTransfer,
    this.sourceDebtId,
  });

  /// Create summary from a DebtLedger.
  factory DebtSummary.fromLedger(DebtLedger ledger) {
    return DebtSummary(
      id: ledger.id,
      description: ledger.description,
      filePath: ledger.filePath,
      status: ledger.status,
      isTimeBased: ledger.isTimeBased,
      currency: ledger.currency,
      originalAmount: ledger.originalAmount,
      currentBalance: ledger.currentBalance,
      totalPaid: ledger.totalPaid.toDouble(),
      creditor: ledger.creditor,
      creditorNpub: ledger.creditorNpub,
      creditorName: ledger.creditorName,
      debtor: ledger.debtor,
      debtorNpub: ledger.debtorNpub,
      debtorName: ledger.debtorName,
      dueDate: ledger.dueDate,
      createdAt: ledger.createdAt,
      modifiedAt: ledger.modifiedAt,
      entryCount: ledger.entries.length,
      paymentCount: ledger.paymentEntries.length,
      allSignaturesValid: ledger.allSignaturesValid,
      isEstablished: ledger.isEstablished,
      witnessCount: ledger.witnessEntries.length,
      transferCount: ledger.transferEntries.length,
      totalTransferredOut: ledger.totalTransferredOut,
      isFromTransfer: ledger.isFromTransfer,
      sourceDebtId: ledger.sourceDebtId,
    );
  }

  // ============ Computed Properties ============

  /// Get currency object.
  Currency? get currencyObj => Currencies.byCode(currency ?? '');

  /// Format the original amount with currency.
  String get formattedOriginalAmount {
    if (originalAmount == null) return '';
    final curr = currencyObj;
    if (curr != null) {
      return curr.format(originalAmount!);
    }
    return originalAmount!.toStringAsFixed(2);
  }

  /// Format the current balance with currency.
  String get formattedBalance {
    final curr = currencyObj;
    if (curr != null) {
      return curr.format(currentBalance);
    }
    return currentBalance.toStringAsFixed(2);
  }

  /// Format the total paid with currency.
  String get formattedTotalPaid {
    final curr = currencyObj;
    if (curr != null) {
      return curr.format(totalPaid);
    }
    return totalPaid.toStringAsFixed(2);
  }

  /// Progress percentage (0.0 to 1.0).
  double get progress {
    if (originalAmount == null || originalAmount == 0) return 0;
    return (totalPaid / originalAmount!).clamp(0.0, 1.0);
  }

  /// Progress as percentage string.
  String get progressPercent => '${(progress * 100).toStringAsFixed(0)}%';

  /// Whether the debt is fully paid.
  bool get isFullyPaid => currentBalance <= 0 || status == DebtStatus.paid;

  /// Whether the debt is active (open and not settled).
  bool get isActive => status == DebtStatus.open;

  /// Whether the debt is pending confirmation.
  bool get isPending => status == DebtStatus.pending;

  /// Whether the debt is overdue.
  bool get isOverdue {
    if (dueDate == null || isFullyPaid) return false;
    try {
      final due = DateTime.parse(dueDate!);
      return DateTime.now().isAfter(due);
    } catch (_) {
      return false;
    }
  }

  /// Days until due date (negative if overdue).
  int? get daysUntilDue {
    if (dueDate == null) return null;
    try {
      final due = DateTime.parse(dueDate!);
      return due.difference(DateTime.now()).inDays;
    } catch (_) {
      return null;
    }
  }

  /// Display name for creditor.
  String get creditorDisplayName =>
      creditorName ?? creditor ?? 'Unknown';

  /// Display name for debtor.
  String get debtorDisplayName =>
      debtorName ?? debtor ?? 'Unknown';

  /// Short status text for display.
  String get statusText {
    switch (status) {
      case DebtStatus.draft:
        return 'Draft';
      case DebtStatus.pending:
        return 'Pending';
      case DebtStatus.open:
        return isOverdue ? 'Overdue' : 'Open';
      case DebtStatus.paid:
        return 'Paid';
      case DebtStatus.expired:
        return 'Expired';
      case DebtStatus.retired:
        return 'Retired';
      case DebtStatus.rejected:
        return 'Rejected';
      case DebtStatus.uncollectable:
        return 'Uncollectable';
      case DebtStatus.unpayable:
        return 'Unpayable';
    }
  }

  /// Whether the debt is closed due to party unavailability.
  bool get isClosedDueToUnavailability {
    return status == DebtStatus.uncollectable ||
        status == DebtStatus.unpayable;
  }

  @override
  String toString() {
    return 'DebtSummary(id: $id, status: $status, balance: $formattedBalance)';
  }
}

/// Aggregated summary across multiple debts.
class WalletSummary {
  /// Total amount you are owed (you are creditor)
  final Map<String, double> owedToYou;

  /// Total amount you owe (you are debtor)
  final Map<String, double> youOwe;

  /// Count of active debts where you are creditor
  final int creditorDebtsCount;

  /// Count of active debts where you are debtor
  final int debtorDebtsCount;

  /// Count of pending debts awaiting your signature
  final int pendingCount;

  /// Count of overdue debts
  final int overdueCount;

  WalletSummary({
    required this.owedToYou,
    required this.youOwe,
    required this.creditorDebtsCount,
    required this.debtorDebtsCount,
    required this.pendingCount,
    required this.overdueCount,
  });

  /// Create summary from a list of debt summaries.
  factory WalletSummary.fromDebts(
    List<DebtSummary> debts,
    String userNpub,
  ) {
    final owedToYou = <String, double>{};
    final youOwe = <String, double>{};
    int creditorCount = 0;
    int debtorCount = 0;
    int pendingCount = 0;
    int overdueCount = 0;

    for (final debt in debts) {
      if (!debt.isActive && !debt.isPending) continue;

      final currency = debt.currency ?? 'EUR';
      final balance = debt.currentBalance;

      final isCreditor = debt.creditorNpub == userNpub;
      final isDebtor = debt.debtorNpub == userNpub;

      if (isCreditor && debt.isActive) {
        owedToYou[currency] = (owedToYou[currency] ?? 0) + balance;
        creditorCount++;
      } else if (isDebtor && debt.isActive) {
        youOwe[currency] = (youOwe[currency] ?? 0) + balance;
        debtorCount++;
      }

      if (debt.isPending) {
        pendingCount++;
      }

      if (debt.isOverdue) {
        overdueCount++;
      }
    }

    return WalletSummary(
      owedToYou: owedToYou,
      youOwe: youOwe,
      creditorDebtsCount: creditorCount,
      debtorDebtsCount: debtorCount,
      pendingCount: pendingCount,
      overdueCount: overdueCount,
    );
  }

  /// Format owed to you amounts.
  String formatOwedToYou() {
    if (owedToYou.isEmpty) return 'Nothing';
    return _formatAmounts(owedToYou);
  }

  /// Format you owe amounts.
  String formatYouOwe() {
    if (youOwe.isEmpty) return 'Nothing';
    return _formatAmounts(youOwe);
  }

  String _formatAmounts(Map<String, double> amounts) {
    final parts = <String>[];
    for (final entry in amounts.entries) {
      final curr = Currencies.byCode(entry.key);
      if (curr != null) {
        parts.add(curr.format(entry.value));
      } else {
        parts.add('${entry.value.toStringAsFixed(2)} ${entry.key}');
      }
    }
    return parts.join(', ');
  }

  /// Total active debts count.
  int get totalActiveCount => creditorDebtsCount + debtorDebtsCount;

  @override
  String toString() {
    return 'WalletSummary(owed: $owedToYou, owing: $youOwe)';
  }
}
