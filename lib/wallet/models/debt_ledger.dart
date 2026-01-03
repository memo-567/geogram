/// Represents a debt ledger file (.md) that contains all entries for a debt.
///
/// The ledger is an append-only file where each entry is signed and the
/// signature covers all content above it in the file.
library;

import '../../util/chat_format.dart';
import 'debt_entry.dart';
import 'currency.dart';

/// Represents a parsed debt ledger file.
class DebtLedger {
  /// Unique debt identifier (matches filename without .md)
  final String id;

  /// Human-readable description/title
  final String description;

  /// All entries in chronological order
  final List<DebtEntry> entries;

  /// File path (if loaded from disk)
  String? filePath;

  DebtLedger({
    required this.id,
    required this.description,
    List<DebtEntry>? entries,
    this.filePath,
  }) : entries = entries ?? [];

  /// Parse a debt ledger from markdown content.
  factory DebtLedger.parse(String content, {String? filePath}) {
    // Parse header: # debt_id: Description
    String id = '';
    String description = '';

    final lines = content.split('\n');
    for (final line in lines) {
      if (line.startsWith('# ')) {
        final headerContent = line.substring(2);
        final colonIdx = headerContent.indexOf(':');
        if (colonIdx > 0) {
          id = headerContent.substring(0, colonIdx).trim();
          description = headerContent.substring(colonIdx + 1).trim();
        } else {
          id = headerContent.trim();
        }
        break;
      }
    }

    // Parse entries using ChatFormat
    final parsed = ChatFormat.parse(content);
    final entries = parsed.map((p) {
      final typeStr = p.getMeta('type');
      final type = DebtEntry.parseType(typeStr) ?? DebtEntryType.note;

      return DebtEntry(
        author: p.author,
        timestamp: p.timestamp,
        content: p.content,
        type: type,
        metadata: Map<String, String>.from(p.metadata),
      );
    }).toList();

    // Sort entries by timestamp
    entries.sort();

    return DebtLedger(
      id: id,
      description: description,
      entries: entries,
      filePath: filePath,
    );
  }

  /// Export ledger to markdown format.
  String export() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('# $id: $description');

    // Entries with double newline between each
    for (final entry in entries) {
      buffer.writeln();
      buffer.writeln();
      buffer.write(entry.exportAsText());
    }

    return buffer.toString();
  }

  /// Get the content to sign for a new entry.
  ///
  /// This includes the entire file content up to (but not including)
  /// the signature line of the new entry.
  String getContentToSign(DebtEntry newEntry) {
    final buffer = StringBuffer();

    // Include existing content
    buffer.write(export());

    // Add the new entry (without signature)
    buffer.writeln();
    buffer.writeln();
    buffer.writeln('> ${newEntry.timestamp} -- ${newEntry.author}');
    buffer.writeln('--> type: ${DebtEntry.typeToString(newEntry.type)}');

    // Metadata (excluding signature-related)
    const reservedKeys = {'type', 'npub', 'signature', 'created_at'};
    for (final entry in newEntry.metadata.entries) {
      if (reservedKeys.contains(entry.key)) continue;
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    // Content
    if (newEntry.content.isNotEmpty) {
      buffer.writeln(newEntry.content);
    }

    // created_at if present
    if (newEntry.hasMeta('created_at')) {
      buffer.writeln('--> created_at: ${newEntry.getMeta('created_at')}');
    }

    // npub (included in signed content)
    if (newEntry.hasMeta('npub')) {
      buffer.writeln('--> npub: ${newEntry.npub}');
    }

    return buffer.toString().trimRight();
  }

  /// Add an entry to the ledger.
  void addEntry(DebtEntry entry) {
    entries.add(entry);
    entries.sort();
  }

  // ============ Computed Properties ============

  /// Get the create entry (first entry).
  DebtEntry? get createEntry {
    try {
      return entries.firstWhere((e) => e.type == DebtEntryType.create);
    } catch (_) {
      return null;
    }
  }

  /// Get the confirm entry.
  DebtEntry? get confirmEntry {
    try {
      return entries.firstWhere((e) => e.type == DebtEntryType.confirm);
    } catch (_) {
      return null;
    }
  }

  /// Get all witness entries.
  List<DebtEntry> get witnessEntries {
    return entries.where((e) => e.type == DebtEntryType.witness).toList();
  }

  /// Get all payment entries.
  List<DebtEntry> get paymentEntries {
    return entries.where((e) => e.type == DebtEntryType.payment).toList();
  }

  /// Get all work session entries.
  List<DebtEntry> get sessionEntries {
    return entries.where((e) => e.type == DebtEntryType.workSession).toList();
  }

  /// Get all transfer entries (debt transferred out).
  List<DebtEntry> get transferEntries {
    return entries.where((e) => e.type == DebtEntryType.transfer).toList();
  }

  /// Total amount transferred out to other creditors.
  double get totalTransferredOut {
    double total = 0;
    for (final entry in transferEntries) {
      total += entry.amount ?? 0;
    }
    return total;
  }

  /// Check if this debt was created from a transfer.
  bool get isFromTransfer {
    return entries.any((e) => e.type == DebtEntryType.transferReceive);
  }

  /// Get the source debt ID if this was created from a transfer.
  String? get sourceDebtId {
    try {
      final entry = entries.firstWhere(
        (e) => e.type == DebtEntryType.transferReceive,
      );
      return entry.sourceDebtId;
    } catch (_) {
      return null;
    }
  }

  /// Current status based on latest status entry.
  DebtStatus get status {
    // Check for status_change entries (reverse order)
    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.type == DebtEntryType.statusChange ||
          entry.type == DebtEntryType.confirm ||
          entry.type == DebtEntryType.reject ||
          entry.type == DebtEntryType.create) {
        final status = entry.status;
        if (status != null) return status;
      }
    }
    return DebtStatus.draft;
  }

  /// Creditor callsign (from create entry).
  String? get creditor => createEntry?.creditor;

  /// Creditor npub (from create entry).
  String? get creditorNpub => createEntry?.creditorNpub;

  /// Creditor name (from create entry).
  String? get creditorName => createEntry?.creditorName;

  /// Debtor callsign (from create entry).
  String? get debtor => createEntry?.debtor;

  /// Debtor npub (from create entry).
  String? get debtorNpub => createEntry?.debtorNpub;

  /// Debtor name (from create entry).
  String? get debtorName => createEntry?.debtorName;

  /// Original amount (from create entry).
  double? get originalAmount => createEntry?.amount;

  /// Currency code (from create entry).
  String? get currency => createEntry?.currency;

  /// Currency object.
  Currency? get currencyObj => Currencies.byCode(currency ?? '');

  /// Whether this is a time-based debt.
  bool get isTimeBased => Currencies.isTimeCurrency(currency ?? '');

  /// Due date (from create entry).
  String? get dueDate => createEntry?.dueDate;

  /// Terms (from create entry).
  String? get terms => createEntry?.terms;

  /// Current balance (from latest payment or session entry).
  double get currentBalance {
    // Find the latest entry with a balance
    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.type == DebtEntryType.payment ||
          entry.type == DebtEntryType.confirmPayment ||
          entry.type == DebtEntryType.confirmSession ||
          entry.type == DebtEntryType.transfer ||
          entry.type == DebtEntryType.transferPayment) {
        final balance = entry.balance;
        if (balance != null) return balance;
      }
    }
    // No payments yet, return original amount
    return originalAmount ?? 0;
  }

  /// Total paid amount.
  double get totalPaid {
    double total = 0;
    for (final entry in paymentEntries) {
      total += entry.amount ?? 0;
    }
    return total;
  }

  /// Total time worked (in minutes, for time-based debts).
  int get totalTimeWorked {
    int total = 0;
    for (final entry in sessionEntries) {
      total += entry.duration ?? 0;
    }
    return total;
  }

  /// Formatted total time worked.
  String get formattedTimeWorked => formatDuration(totalTimeWorked);

  /// Check if debt is fully paid.
  bool get isFullyPaid => currentBalance <= 0 || status == DebtStatus.paid;

  /// Check if debt is active (open and not settled).
  bool get isActive => status == DebtStatus.open;

  /// Check if debt is pending confirmation.
  bool get isPending => status == DebtStatus.pending;

  /// Created timestamp (from create entry).
  DateTime? get createdAt => createEntry?.dateTime;

  /// Last modified timestamp (from last entry).
  DateTime? get modifiedAt => entries.isNotEmpty ? entries.last.dateTime : null;

  // ============ Validation ============

  /// Check if all entries have valid signatures.
  bool get allSignaturesValid {
    return entries.every((e) => !e.isSigned || e.isVerified);
  }

  /// Get entries with invalid signatures.
  List<DebtEntry> get invalidEntries {
    return entries.where((e) => e.isSigned && !e.isVerified).toList();
  }

  /// Check if the create entry exists and is signed.
  bool get hasValidCreate {
    final create = createEntry;
    return create != null && create.isSigned && create.isVerified;
  }

  /// Check if the confirm entry exists and is signed.
  bool get hasValidConfirm {
    final confirm = confirmEntry;
    return confirm != null && confirm.isSigned && confirm.isVerified;
  }

  /// Check if both parties have signed (debt is properly established).
  bool get isEstablished => hasValidCreate && hasValidConfirm;

  @override
  String toString() {
    return 'DebtLedger(id: $id, status: $status, entries: ${entries.length})';
  }
}
