/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Backup API endpoints.
 */

import '../api.dart';

/// Backup provider info
class BackupProvider {
  final String callsign;
  final String? name;
  final String status; // 'available', 'pending', 'accepted', 'rejected'
  final int? storageUsed;
  final int? storageLimit;
  final DateTime? lastBackup;
  final DateTime? invitedAt;

  const BackupProvider({
    required this.callsign,
    this.name,
    this.status = 'pending',
    this.storageUsed,
    this.storageLimit,
    this.lastBackup,
    this.invitedAt,
  });

  factory BackupProvider.fromJson(Map<String, dynamic> json) {
    return BackupProvider(
      callsign: json['callsign'] as String? ?? '',
      name: json['name'] as String?,
      status: json['status'] as String? ?? 'pending',
      storageUsed: json['storageUsed'] as int? ?? json['storage_used'] as int?,
      storageLimit: json['storageLimit'] as int? ?? json['storage_limit'] as int?,
      lastBackup: _parseDateTime(json['lastBackup'] ?? json['last_backup']),
      invitedAt: _parseDateTime(json['invitedAt'] ?? json['invited_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double get storageUsagePercent {
    if (storageUsed == null || storageLimit == null || storageLimit == 0) return 0;
    return storageUsed! / storageLimit! * 100;
  }
}

/// Backup client info (for providers)
class BackupClient {
  final String callsign;
  final String? name;
  final String status; // 'active', 'pending', 'suspended'
  final int? storageUsed;
  final int? snapshotCount;
  final DateTime? lastBackup;
  final DateTime? acceptedAt;

  const BackupClient({
    required this.callsign,
    this.name,
    this.status = 'pending',
    this.storageUsed,
    this.snapshotCount,
    this.lastBackup,
    this.acceptedAt,
  });

  factory BackupClient.fromJson(Map<String, dynamic> json) {
    return BackupClient(
      callsign: json['callsign'] as String? ?? '',
      name: json['name'] as String?,
      status: json['status'] as String? ?? 'pending',
      storageUsed: json['storageUsed'] as int? ?? json['storage_used'] as int?,
      snapshotCount: json['snapshotCount'] as int? ?? json['snapshot_count'] as int?,
      lastBackup: _parseDateTime(json['lastBackup'] ?? json['last_backup']),
      acceptedAt: _parseDateTime(json['acceptedAt'] ?? json['accepted_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Backup snapshot info
class BackupSnapshot {
  final String id;
  final DateTime date;
  final int fileCount;
  final int totalSize;
  final String? note;
  final String status; // 'complete', 'partial', 'failed'

  const BackupSnapshot({
    required this.id,
    required this.date,
    this.fileCount = 0,
    this.totalSize = 0,
    this.note,
    this.status = 'complete',
  });

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    return BackupSnapshot(
      id: json['id'] as String? ?? json['date'] as String? ?? '',
      date: _parseDateTime(json['date']) ?? DateTime.now(),
      fileCount: json['fileCount'] as int? ?? json['file_count'] as int? ?? 0,
      totalSize: json['totalSize'] as int? ?? json['total_size'] as int? ?? 0,
      note: json['note'] as String?,
      status: json['status'] as String? ?? 'complete',
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Backup operation status
class BackupStatus {
  final String operation; // 'backup', 'restore', 'idle'
  final String status; // 'running', 'completed', 'failed', 'idle'
  final double progress; // 0.0 to 1.0
  final String? currentFile;
  final int processedFiles;
  final int totalFiles;
  final String? error;

  const BackupStatus({
    this.operation = 'idle',
    this.status = 'idle',
    this.progress = 0,
    this.currentFile,
    this.processedFiles = 0,
    this.totalFiles = 0,
    this.error,
  });

  factory BackupStatus.fromJson(Map<String, dynamic> json) {
    return BackupStatus(
      operation: json['operation'] as String? ?? 'idle',
      status: json['status'] as String? ?? 'idle',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      currentFile: json['currentFile'] as String? ?? json['current_file'] as String?,
      processedFiles: json['processedFiles'] as int? ?? json['processed_files'] as int? ?? 0,
      totalFiles: json['totalFiles'] as int? ?? json['total_files'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  bool get isRunning => status == 'running';
  bool get isIdle => status == 'idle';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  int get progressPercent => (progress * 100).round();
}

/// Backup provider settings
class BackupSettings {
  final bool enabled;
  final int maxStorageBytes;
  final int maxClients;
  final bool autoAccept;

  const BackupSettings({
    this.enabled = false,
    this.maxStorageBytes = 0,
    this.maxClients = 0,
    this.autoAccept = false,
  });

  factory BackupSettings.fromJson(Map<String, dynamic> json) {
    return BackupSettings(
      enabled: json['enabled'] as bool? ?? false,
      maxStorageBytes: json['maxStorageBytes'] as int? ?? json['max_storage_bytes'] as int? ?? 0,
      maxClients: json['maxClients'] as int? ?? json['max_clients'] as int? ?? 0,
      autoAccept: json['autoAccept'] as bool? ?? json['auto_accept'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'maxStorageBytes': maxStorageBytes,
        'maxClients': maxClients,
        'autoAccept': autoAccept,
      };
}

/// Backup API endpoints
class BackupApi {
  final GeogramApi _api;

  BackupApi(this._api);

  // ============================================================
  // Provider Settings
  // ============================================================

  /// Get backup provider settings
  Future<ApiResponse<BackupSettings>> getSettings(String callsign) {
    return _api.get<BackupSettings>(
      callsign,
      '/api/backup/settings',
      fromJson: (json) => BackupSettings.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Update backup provider settings
  Future<ApiResponse<BackupSettings>> updateSettings(
    String callsign,
    BackupSettings settings,
  ) {
    return _api.put<BackupSettings>(
      callsign,
      '/api/backup/settings',
      body: settings.toJson(),
      fromJson: (json) => BackupSettings.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Check provider availability (for discovery)
  Future<ApiResponse<Map<String, dynamic>>> checkAvailability(String callsign) {
    return _api.get<Map<String, dynamic>>(
      callsign,
      '/api/backup/availability',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  // ============================================================
  // Client Operations (as backup requester)
  // ============================================================

  /// List backup providers
  Future<ApiListResponse<BackupProvider>> providers(String callsign) {
    return _api.list<BackupProvider>(
      callsign,
      '/api/backup/providers',
      itemFromJson: (json) => BackupProvider.fromJson(json as Map<String, dynamic>),
      listKey: 'providers',
    );
  }

  /// Send invite to a provider
  Future<ApiResponse<BackupProvider>> inviteProvider(
    String callsign,
    String providerCallsign,
  ) {
    return _api.post<BackupProvider>(
      callsign,
      '/api/backup/providers/$providerCallsign',
      fromJson: (json) => BackupProvider.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Remove a provider
  Future<ApiResponse<void>> removeProvider(
    String callsign,
    String providerCallsign,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/backup/providers/$providerCallsign',
    );
  }

  /// Start a backup to a provider
  Future<ApiResponse<BackupStatus>> startBackup(
    String callsign,
    String providerCallsign,
  ) {
    return _api.post<BackupStatus>(
      callsign,
      '/api/backup/start',
      body: {'provider': providerCallsign},
      fromJson: (json) => BackupStatus.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Start a restore from a provider
  Future<ApiResponse<BackupStatus>> startRestore(
    String callsign,
    String providerCallsign, {
    String? snapshotId,
  }) {
    return _api.post<BackupStatus>(
      callsign,
      '/api/backup/restore',
      body: {
        'provider': providerCallsign,
        if (snapshotId != null) 'snapshot': snapshotId,
      },
      fromJson: (json) => BackupStatus.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Get current backup/restore status
  Future<ApiResponse<BackupStatus>> status(String callsign) {
    return _api.get<BackupStatus>(
      callsign,
      '/api/backup/status',
      fromJson: (json) => BackupStatus.fromJson(json as Map<String, dynamic>),
    );
  }

  // ============================================================
  // Provider Operations (as backup provider)
  // ============================================================

  /// List backup clients
  Future<ApiListResponse<BackupClient>> clients(String callsign) {
    return _api.list<BackupClient>(
      callsign,
      '/api/backup/clients',
      itemFromJson: (json) => BackupClient.fromJson(json as Map<String, dynamic>),
      listKey: 'clients',
    );
  }

  /// Get specific client info
  Future<ApiResponse<BackupClient>> getClient(
    String callsign,
    String clientCallsign,
  ) {
    return _api.get<BackupClient>(
      callsign,
      '/api/backup/clients/$clientCallsign',
      fromJson: (json) => BackupClient.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Accept a client invite
  Future<ApiResponse<BackupClient>> acceptClient(
    String callsign,
    String clientCallsign,
  ) {
    return _api.put<BackupClient>(
      callsign,
      '/api/backup/clients/$clientCallsign',
      body: {'status': 'accepted'},
      fromJson: (json) => BackupClient.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Remove a client
  Future<ApiResponse<void>> removeClient(
    String callsign,
    String clientCallsign,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/backup/clients/$clientCallsign',
    );
  }

  /// List snapshots for a client
  Future<ApiListResponse<BackupSnapshot>> snapshots(
    String callsign,
    String clientCallsign,
  ) {
    return _api.list<BackupSnapshot>(
      callsign,
      '/api/backup/clients/$clientCallsign/snapshots',
      itemFromJson: (json) => BackupSnapshot.fromJson(json as Map<String, dynamic>),
      listKey: 'snapshots',
    );
  }

  /// Update snapshot note
  Future<ApiResponse<BackupSnapshot>> updateSnapshotNote(
    String callsign,
    String clientCallsign,
    String snapshotId,
    String note,
  ) {
    return _api.put<BackupSnapshot>(
      callsign,
      '/api/backup/clients/$clientCallsign/snapshots/$snapshotId/note',
      body: {'note': note},
      fromJson: (json) => BackupSnapshot.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Delete a snapshot
  Future<ApiResponse<void>> deleteSnapshot(
    String callsign,
    String clientCallsign,
    String snapshotId,
  ) {
    return _api.delete<void>(
      callsign,
      '/api/backup/clients/$clientCallsign/snapshots/$snapshotId',
    );
  }

  // ============================================================
  // Discovery
  // ============================================================

  /// Start provider discovery
  Future<ApiResponse<Map<String, dynamic>>> startDiscovery(String callsign) {
    return _api.post<Map<String, dynamic>>(
      callsign,
      '/api/backup/discover',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Get discovery status
  Future<ApiResponse<Map<String, dynamic>>> getDiscoveryStatus(
    String callsign,
    String discoveryId,
  ) {
    return _api.get<Map<String, dynamic>>(
      callsign,
      '/api/backup/discover/$discoveryId',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }
}
