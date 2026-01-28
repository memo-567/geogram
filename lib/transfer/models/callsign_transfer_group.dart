import 'transfer_models.dart';

/// Groups transfers by callsign for aggregated display.
///
/// Downloads are grouped by `sourceCallsign`, uploads by `targetCallsign`.
/// Provides aggregate metrics (total files, size, progress) for the group.
class CallsignTransferGroup {
  final String callsign;
  final TransferDirection direction;
  final List<Transfer> transfers;

  CallsignTransferGroup({
    required this.callsign,
    required this.direction,
    required this.transfers,
  });

  // Computed aggregates
  int get totalFiles => transfers.length;

  int get completedFiles =>
      transfers.where((t) => t.status == TransferStatus.completed).length;

  int get activeFiles => transfers.where((t) => t.isActive).length;

  int get queuedFiles => transfers.where((t) => t.isPending).length;

  int get failedFiles =>
      transfers.where((t) => t.status == TransferStatus.failed).length;

  int get totalBytes =>
      transfers.fold(0, (sum, t) => sum + t.expectedBytes);

  int get bytesTransferred =>
      transfers.fold(0, (sum, t) => sum + t.bytesTransferred);

  double get progressPercent =>
      totalBytes > 0 ? bytesTransferred / totalBytes * 100 : 0;

  double get progressFraction =>
      totalBytes > 0 ? bytesTransferred / totalBytes : 0;

  /// Sum of active transfer speeds
  double get speedBytesPerSecond {
    double totalSpeed = 0;
    for (final t in transfers) {
      if (t.isActive && t.speedBytesPerSecond != null) {
        totalSpeed += t.speedBytesPerSecond!;
      }
    }
    return totalSpeed;
  }

  /// Estimated time remaining based on aggregate speed and remaining bytes
  Duration? get estimatedTimeRemaining {
    final speed = speedBytesPerSecond;
    if (speed <= 0) return null;
    final remaining = totalBytes - bytesTransferred;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / speed).round());
  }

  /// Worst-case status from all transfers.
  /// Priority: failed > active > queued > completed
  TransferStatus get aggregateStatus {
    if (transfers.any((t) => t.status == TransferStatus.failed)) {
      return TransferStatus.failed;
    }
    if (transfers.any((t) => t.isActive)) {
      return TransferStatus.transferring;
    }
    if (transfers.any((t) => t.isPending)) {
      return TransferStatus.queued;
    }
    if (transfers.every((t) => t.status == TransferStatus.completed)) {
      return TransferStatus.completed;
    }
    // Mixed states (some completed, some cancelled, etc.)
    return TransferStatus.completed;
  }

  /// Most recent activity timestamp across all transfers
  DateTime? get lastActivity {
    DateTime? latest;
    for (final t in transfers) {
      final activity = t.lastActivityAt ?? t.startedAt ?? t.createdAt;
      if (latest == null || activity.isAfter(latest)) {
        latest = activity;
      }
    }
    return latest;
  }

  /// Status chip label for collapsed view
  String get statusLabel {
    if (failedFiles > 0) {
      return '$failedFiles failed';
    }
    if (activeFiles > 0) {
      return '$activeFiles active';
    }
    if (queuedFiles > 0) {
      return '$queuedFiles queued';
    }
    if (completedFiles == totalFiles) {
      return 'Done';
    }
    return '$completedFiles/$totalFiles';
  }

  /// Whether any transfers in this group have actions available
  bool get hasActiveTransfers => activeFiles > 0 || queuedFiles > 0;
}

/// Groups a list of transfers by callsign.
///
/// Downloads are grouped by `sourceCallsign`, uploads by `targetCallsign`.
/// Groups are sorted by most recent activity.
List<CallsignTransferGroup> groupTransfersByCallsign(List<Transfer> transfers) {
  final downloadsByCallsign = <String, List<Transfer>>{};
  final uploadsByCallsign = <String, List<Transfer>>{};

  for (final transfer in transfers) {
    if (transfer.direction == TransferDirection.download) {
      final key = transfer.sourceCallsign.isNotEmpty
          ? transfer.sourceCallsign
          : _extractCallsignFromUrl(transfer.remoteUrl) ?? 'Unknown';
      downloadsByCallsign.putIfAbsent(key, () => []).add(transfer);
    } else if (transfer.direction == TransferDirection.upload) {
      final key = transfer.targetCallsign.isNotEmpty
          ? transfer.targetCallsign
          : 'Unknown';
      uploadsByCallsign.putIfAbsent(key, () => []).add(transfer);
    }
  }

  final groups = <CallsignTransferGroup>[];

  // Build download groups
  for (final entry in downloadsByCallsign.entries) {
    groups.add(CallsignTransferGroup(
      callsign: entry.key,
      direction: TransferDirection.download,
      transfers: entry.value,
    ));
  }

  // Build upload groups
  for (final entry in uploadsByCallsign.entries) {
    groups.add(CallsignTransferGroup(
      callsign: entry.key,
      direction: TransferDirection.upload,
      transfers: entry.value,
    ));
  }

  // Sort by most recent activity (most recent first)
  groups.sort((a, b) {
    final aActivity = a.lastActivity;
    final bActivity = b.lastActivity;
    if (aActivity == null && bActivity == null) return 0;
    if (aActivity == null) return 1;
    if (bActivity == null) return -1;
    return bActivity.compareTo(aActivity);
  });

  return groups;
}

/// Extract callsign from URL if it contains one (e.g., http://X1ABC.local/...)
String? _extractCallsignFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host;
  // Check if host looks like a callsign (e.g., "X1ABC.local" or "X1ABC")
  final match = RegExp(r'^([A-Z0-9]{4,8})(\.local)?$', caseSensitive: false)
      .firstMatch(host);
  return match?.group(1)?.toUpperCase();
}
