import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/log_service.dart';
import '../../services/storage_config.dart';
import '../models/transfer_models.dart';

/// Persists per-transfer records for auditing, debugging, and cache lookups.
/// Records are auto-pruned after [_retention] to keep the directory clean.
class TransferRecordService {
  static final TransferRecordService _instance =
      TransferRecordService._internal();
  factory TransferRecordService() => _instance;
  TransferRecordService._internal();

  final _log = LogService();
  final Duration _retention = const Duration(days: 30);
  final Map<String, DateTime> _lastWrite = {};

  late final String _recordsDir;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    _recordsDir = p.join(StorageConfig().baseDir, 'transfers', 'records');
    await Directory(_recordsDir).create(recursive: true);
    await _pruneExpiredRecords();

    _initialized = true;
  }

  /// Ensure the record exists for existing queue items (runs at startup).
  Future<void> backfill(Iterable<Transfer> transfers) async {
    for (final transfer in transfers) {
      await recordRequested(transfer, cacheHit: false, skipIfExists: true);
    }
  }

  Future<void> recordRequested(
    Transfer transfer, {
    required bool cacheHit,
    bool skipIfExists = false,
  }) async {
    _ensureInitialized();
    final file = File(_pathFor(transfer.id));
    if (skipIfExists && await file.exists()) return;

    final record = _baseRecord(transfer, cacheHit: cacheHit);
    await _writeRecord(file, record, force: true);
  }

  Future<void> recordProgress(Transfer transfer) async {
    _ensureInitialized();
    final file = File(_pathFor(transfer.id));
    final record = await _readRecordOrFallback(file, transfer);

    record['bytes_transferred'] = transfer.bytesTransferred;
    record['status'] = transfer.status.name;
    record['last_activity_at'] = DateTime.now().toIso8601String();
    record['transport_used'] = transfer.transportUsed;

    _mergeTransportTotals(
      record,
      transfer.transportUsed ?? 'unknown',
      transfer.bytesTransferred,
    );

    await _writeRecord(file, record);
  }

  Future<void> recordCompleted(Transfer transfer) async {
    _ensureInitialized();
    final file = File(_pathFor(transfer.id));
    final record = await _readRecordOrFallback(file, transfer);

    final completedAt = transfer.completedAt ?? DateTime.now();
    record['status'] = TransferStatus.completed.name;
    record['completed_at'] = completedAt.toIso8601String();
    record['bytes_transferred'] = transfer.bytesTransferred;
    record['transport_used'] = transfer.transportUsed;
    record['error'] = null;

    _mergeTransportTotals(
      record,
      transfer.transportUsed ?? 'unknown',
      transfer.bytesTransferred,
    );
    _appendSegment(
      record,
      transport: transfer.transportUsed ?? 'unknown',
      bytes: transfer.bytesTransferred,
    );

    record['verification'] ??= {};
    // Hash verification is enforced by TransferWorker when expectedHash is provided.
    record['verification']['verified'] = transfer.expectedHash != null;
    record['verification']['hash_used'] = transfer.expectedHash;
    record['verification']['verified_at'] = completedAt.toIso8601String();

    await _writeRecord(file, record, force: true);
  }

  Future<void> recordFailed(
    Transfer transfer, {
    required String error,
    required bool willRetry,
    DateTime? nextRetryAt,
  }) async {
    _ensureInitialized();
    final file = File(_pathFor(transfer.id));
    final record = await _readRecordOrFallback(file, transfer);

    record['status'] = willRetry
        ? TransferStatus.waiting.name
        : TransferStatus.failed.name;
    record['error'] = error;
    record['next_retry_at'] = nextRetryAt?.toIso8601String();
    record['will_retry'] = willRetry;
    record['last_activity_at'] = DateTime.now().toIso8601String();

    await _writeRecord(file, record, force: true);
  }

  /// Load a persisted record for a transfer (if it exists).
  Future<Map<String, dynamic>?> getRecord(String transferId) async {
    _ensureInitialized();
    final file = File(_pathFor(transferId));
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      _log.log('TransferRecordService: Failed to read record: $e');
      return null;
    }
  }

  // ===== Helpers =====

  Map<String, dynamic> _baseRecord(
    Transfer transfer, {
    required bool cacheHit,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'version': '1.1',
      'transfer_id': transfer.id,
      'direction': transfer.direction.name,
      'source_callsign': transfer.sourceCallsign,
      'target_callsign': transfer.targetCallsign,
      'remote_path': transfer.remotePath,
      'remote_url': transfer.remoteUrl,
      'local_path': transfer.localPath,
      'filename': transfer.filename,
      'expected_bytes': transfer.expectedBytes,
      'expected_hash': transfer.expectedHash,
      'requesting_app': transfer.requestingApp,
      'metadata': transfer.metadata,
      'status': transfer.status.name,
      'bytes_transferred': transfer.bytesTransferred,
      'retry_count': transfer.retryCount,
      'transport_used': transfer.transportUsed,
      'created_at': transfer.createdAt.toIso8601String(),
      'started_at': transfer.startedAt?.toIso8601String(),
      'completed_at': transfer.completedAt?.toIso8601String(),
      'last_activity_at': transfer.lastActivityAt?.toIso8601String(),
      'next_retry_at': transfer.nextRetryAt?.toIso8601String(),
      'segments': <Map<String, dynamic>>[],
      'totals_by_transport': <String, int>{},
      'verification': {
        'verified': false,
        'hash_used': transfer.expectedHash,
        'verified_at': null,
      },
      'cache': {
        'cache_hit': cacheHit,
        'cache_path': null,
        'last_accessed_at': null,
      },
      'error': transfer.error,
      'updated_at': now,
    };
  }

  Future<Map<String, dynamic>> _readRecordOrFallback(
    File file,
    Transfer transfer,
  ) async {
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        _log.log(
          'TransferRecordService: Failed to read record ${file.path}: $e',
        );
      }
    }
    return _baseRecord(transfer, cacheHit: false);
  }

  void _mergeTransportTotals(
    Map<String, dynamic> record,
    String transport,
    int bytes,
  ) {
    final totals =
        (record['totals_by_transport'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final current = totals[transport] as int? ?? 0;
    totals[transport] = bytes > current ? bytes : current;
    record['totals_by_transport'] = totals;
  }

  void _appendSegment(
    Map<String, dynamic> record, {
    required String transport,
    required int bytes,
  }) {
    final segments =
        (record['segments'] as List?)?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];

    // Only append meaningful segments
    if (bytes <= 0) {
      record['segments'] = segments;
      return;
    }

    segments.add({
      'transport': transport,
      'from_byte': 0,
      'to_byte': bytes > 0 ? bytes - 1 : 0,
      'bytes': bytes,
      'duration_ms': null,
      'retries': null,
      'started_at': record['started_at'],
    });

    record['segments'] = segments;
  }

  String _pathFor(String transferId) => p.join(_recordsDir, '$transferId.json');

  Future<void> _writeRecord(
    File file,
    Map<String, dynamic> record, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final last = _lastWrite[file.path];
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 2)) {
      return; // Throttle frequent progress writes
    }

    record['updated_at'] = now.toIso8601String();
    try {
      final jsonString = const JsonEncoder.withIndent('  ').convert(record);
      await file.writeAsString(jsonString, flush: force);
      _lastWrite[file.path] = now;
    } catch (e) {
      _log.log(
        'TransferRecordService: Failed to write record ${file.path}: $e',
      );
    }
  }

  Future<void> _pruneExpiredRecords() async {
    try {
      final dir = Directory(_recordsDir);
      if (!await dir.exists()) return;

      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        final age = now.difference(stat.modified);
        if (age > _retention) {
          await entity.delete();
        }
      }
    } catch (e) {
      _log.log('TransferRecordService: Failed pruning records: $e');
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'TransferRecordService not initialized. Call initialize() first.',
      );
    }
  }
}
