/// Backup app data models
///
/// This file contains all data classes for the Backup app including:
/// - Provider settings and client relationships
/// - Client provider relationships
/// - Snapshot metadata and file entries
/// - Progress status for backup/restore operations
/// - Discovery status for account restoration

/// Relationship status between backup client and provider
enum BackupRelationshipStatus {
  /// Invitation sent, awaiting response
  pending,

  /// Relationship is active, backups can proceed
  active,

  /// Relationship is temporarily paused
  paused,

  /// Relationship has been terminated
  terminated,

  /// Invitation was declined
  declined,
}

/// Parse relationship status from string
BackupRelationshipStatus parseBackupRelationshipStatus(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return BackupRelationshipStatus.pending;
    case 'active':
      return BackupRelationshipStatus.active;
    case 'paused':
      return BackupRelationshipStatus.paused;
    case 'terminated':
      return BackupRelationshipStatus.terminated;
    case 'declined':
      return BackupRelationshipStatus.declined;
    default:
      return BackupRelationshipStatus.pending;
  }
}

/// Provider global settings for backup functionality
class BackupProviderSettings {
  /// Whether this device is accepting backup clients
  bool enabled;

  /// Maximum total storage across all clients (bytes)
  int maxTotalStorageBytes;

  /// Default max storage per client (bytes)
  int defaultMaxClientStorageBytes;

  /// Default max snapshots per client
  int defaultMaxSnapshots;

  /// Auto-accept invitations from contacts
  bool autoAcceptFromContacts;

  /// When settings were last updated
  DateTime updatedAt;

  BackupProviderSettings({
    this.enabled = false,
    this.maxTotalStorageBytes = 10737418240, // 10 GB default
    this.defaultMaxClientStorageBytes = 1073741824, // 1 GB default
    this.defaultMaxSnapshots = 10,
    this.autoAcceptFromContacts = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory BackupProviderSettings.fromJson(Map<String, dynamic> json) {
    return BackupProviderSettings(
      enabled: json['enabled'] as bool? ?? false,
      maxTotalStorageBytes: json['max_total_storage_bytes'] as int? ?? 10737418240,
      defaultMaxClientStorageBytes: json['default_max_client_storage_bytes'] as int? ?? 1073741824,
      defaultMaxSnapshots: json['default_max_snapshots'] as int? ?? 10,
      autoAcceptFromContacts: json['auto_accept_from_contacts'] as bool? ?? false,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'max_total_storage_bytes': maxTotalStorageBytes,
      'default_max_client_storage_bytes': defaultMaxClientStorageBytes,
      'default_max_snapshots': defaultMaxSnapshots,
      'auto_accept_from_contacts': autoAcceptFromContacts,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  BackupProviderSettings copyWith({
    bool? enabled,
    int? maxTotalStorageBytes,
    int? defaultMaxClientStorageBytes,
    int? defaultMaxSnapshots,
    bool? autoAcceptFromContacts,
    DateTime? updatedAt,
  }) {
    return BackupProviderSettings(
      enabled: enabled ?? this.enabled,
      maxTotalStorageBytes: maxTotalStorageBytes ?? this.maxTotalStorageBytes,
      defaultMaxClientStorageBytes: defaultMaxClientStorageBytes ?? this.defaultMaxClientStorageBytes,
      defaultMaxSnapshots: defaultMaxSnapshots ?? this.defaultMaxSnapshots,
      autoAcceptFromContacts: autoAcceptFromContacts ?? this.autoAcceptFromContacts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Provider-side client relationship
class BackupClientRelationship {
  /// Client's NPUB (bech32 encoded public key)
  String clientNpub;

  /// Client's callsign
  String clientCallsign;

  /// Maximum storage allocated for this client (bytes)
  int maxStorageBytes;

  /// Maximum snapshots to retain for this client
  int maxSnapshots;

  /// Current storage used by this client (bytes)
  int currentStorageBytes;

  /// Number of snapshots currently stored
  int snapshotCount;

  /// Relationship status
  BackupRelationshipStatus status;

  /// When relationship was created
  DateTime createdAt;

  /// When last backup completed
  DateTime? lastBackupAt;

  /// Status of last backup (complete, partial, failed)
  String? lastBackupStatus;

  BackupClientRelationship({
    required this.clientNpub,
    required this.clientCallsign,
    this.maxStorageBytes = 1073741824, // 1 GB default
    this.maxSnapshots = 10,
    this.currentStorageBytes = 0,
    this.snapshotCount = 0,
    this.status = BackupRelationshipStatus.pending,
    DateTime? createdAt,
    this.lastBackupAt,
    this.lastBackupStatus,
  }) : createdAt = createdAt ?? DateTime.now();

  factory BackupClientRelationship.fromJson(Map<String, dynamic> json) {
    return BackupClientRelationship(
      clientNpub: json['client_npub'] as String,
      clientCallsign: json['client_callsign'] as String,
      maxStorageBytes: json['max_storage_bytes'] as int? ?? 1073741824,
      maxSnapshots: json['max_snapshots'] as int? ?? 10,
      currentStorageBytes: json['current_storage_bytes'] as int? ?? 0,
      snapshotCount: json['snapshot_count'] as int? ?? 0,
      status: parseBackupRelationshipStatus(json['status'] as String? ?? 'pending'),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      lastBackupAt: json['last_backup_at'] != null
          ? DateTime.parse(json['last_backup_at'] as String)
          : null,
      lastBackupStatus: json['last_backup_status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'client_npub': clientNpub,
      'client_callsign': clientCallsign,
      'max_storage_bytes': maxStorageBytes,
      'max_snapshots': maxSnapshots,
      'current_storage_bytes': currentStorageBytes,
      'snapshot_count': snapshotCount,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      if (lastBackupAt != null) 'last_backup_at': lastBackupAt!.toIso8601String(),
      if (lastBackupStatus != null) 'last_backup_status': lastBackupStatus,
    };
  }

  BackupClientRelationship copyWith({
    String? clientNpub,
    String? clientCallsign,
    int? maxStorageBytes,
    int? maxSnapshots,
    int? currentStorageBytes,
    int? snapshotCount,
    BackupRelationshipStatus? status,
    DateTime? createdAt,
    DateTime? lastBackupAt,
    String? lastBackupStatus,
  }) {
    return BackupClientRelationship(
      clientNpub: clientNpub ?? this.clientNpub,
      clientCallsign: clientCallsign ?? this.clientCallsign,
      maxStorageBytes: maxStorageBytes ?? this.maxStorageBytes,
      maxSnapshots: maxSnapshots ?? this.maxSnapshots,
      currentStorageBytes: currentStorageBytes ?? this.currentStorageBytes,
      snapshotCount: snapshotCount ?? this.snapshotCount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastBackupStatus: lastBackupStatus ?? this.lastBackupStatus,
    );
  }
}

/// Client-side provider relationship
class BackupProviderRelationship {
  /// Provider's NPUB (bech32 encoded public key)
  String providerNpub;

  /// Provider's callsign
  String providerCallsign;

  /// Backup interval in days
  int backupIntervalDays;

  /// Relationship status
  BackupRelationshipStatus status;

  /// Maximum storage allocated by provider (bytes)
  int maxStorageBytes;

  /// Maximum snapshots allowed by provider
  int maxSnapshots;

  /// When last successful backup completed
  DateTime? lastSuccessfulBackup;

  /// When next backup is scheduled
  DateTime? nextScheduledBackup;

  /// When relationship was created
  DateTime createdAt;

  BackupProviderRelationship({
    required this.providerNpub,
    required this.providerCallsign,
    this.backupIntervalDays = 3,
    this.status = BackupRelationshipStatus.pending,
    this.maxStorageBytes = 0,
    this.maxSnapshots = 0,
    this.lastSuccessfulBackup,
    this.nextScheduledBackup,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory BackupProviderRelationship.fromJson(Map<String, dynamic> json) {
    return BackupProviderRelationship(
      providerNpub: json['provider_npub'] as String,
      providerCallsign: json['provider_callsign'] as String,
      backupIntervalDays: json['backup_interval_days'] as int? ?? 3,
      status: parseBackupRelationshipStatus(json['status'] as String? ?? 'pending'),
      maxStorageBytes: json['max_storage_bytes'] as int? ?? 0,
      maxSnapshots: json['max_snapshots'] as int? ?? 0,
      lastSuccessfulBackup: json['last_successful_backup'] != null
          ? DateTime.parse(json['last_successful_backup'] as String)
          : null,
      nextScheduledBackup: json['next_scheduled_backup'] != null
          ? DateTime.parse(json['next_scheduled_backup'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_npub': providerNpub,
      'provider_callsign': providerCallsign,
      'backup_interval_days': backupIntervalDays,
      'status': status.name,
      'max_storage_bytes': maxStorageBytes,
      'max_snapshots': maxSnapshots,
      if (lastSuccessfulBackup != null) 'last_successful_backup': lastSuccessfulBackup!.toIso8601String(),
      if (nextScheduledBackup != null) 'next_scheduled_backup': nextScheduledBackup!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  BackupProviderRelationship copyWith({
    String? providerNpub,
    String? providerCallsign,
    int? backupIntervalDays,
    BackupRelationshipStatus? status,
    int? maxStorageBytes,
    int? maxSnapshots,
    DateTime? lastSuccessfulBackup,
    DateTime? nextScheduledBackup,
    DateTime? createdAt,
  }) {
    return BackupProviderRelationship(
      providerNpub: providerNpub ?? this.providerNpub,
      providerCallsign: providerCallsign ?? this.providerCallsign,
      backupIntervalDays: backupIntervalDays ?? this.backupIntervalDays,
      status: status ?? this.status,
      maxStorageBytes: maxStorageBytes ?? this.maxStorageBytes,
      maxSnapshots: maxSnapshots ?? this.maxSnapshots,
      lastSuccessfulBackup: lastSuccessfulBackup ?? this.lastSuccessfulBackup,
      nextScheduledBackup: nextScheduledBackup ?? this.nextScheduledBackup,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Snapshot metadata
class BackupSnapshot {
  /// Snapshot ID (YYYY-MM-DD format)
  String snapshotId;

  /// Snapshot status (in_progress, complete, partial, failed)
  String status;

  /// Total number of files in snapshot
  int totalFiles;

  /// Total bytes in snapshot (unencrypted)
  int totalBytes;

  /// When backup started
  DateTime startedAt;

  /// When backup completed
  DateTime? completedAt;

  BackupSnapshot({
    required this.snapshotId,
    this.status = 'in_progress',
    this.totalFiles = 0,
    this.totalBytes = 0,
    DateTime? startedAt,
    this.completedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    return BackupSnapshot(
      snapshotId: json['snapshot_id'] as String,
      status: json['status'] as String? ?? 'in_progress',
      totalFiles: json['total_files'] as int? ?? 0,
      totalBytes: json['total_bytes'] as int? ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'snapshot_id': snapshotId,
      'status': status,
      'total_files': totalFiles,
      'total_bytes': totalBytes,
      'started_at': startedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    };
  }

  BackupSnapshot copyWith({
    String? snapshotId,
    String? status,
    int? totalFiles,
    int? totalBytes,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return BackupSnapshot(
      snapshotId: snapshotId ?? this.snapshotId,
      status: status ?? this.status,
      totalFiles: totalFiles ?? this.totalFiles,
      totalBytes: totalBytes ?? this.totalBytes,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Manifest file entry
class BackupFileEntry {
  /// Relative path within working folder
  String path;

  /// SHA1 hash of original file content
  String sha1;

  /// Size of original file (bytes)
  int size;

  /// Size of encrypted file (bytes)
  int encryptedSize;

  /// Name of encrypted file (e.g., "abc123.enc")
  String encryptedName;

  /// File modification time
  DateTime modifiedAt;

  BackupFileEntry({
    required this.path,
    required this.sha1,
    required this.size,
    required this.encryptedSize,
    required this.encryptedName,
    required this.modifiedAt,
  });

  factory BackupFileEntry.fromJson(Map<String, dynamic> json) {
    return BackupFileEntry(
      path: json['path'] as String,
      sha1: json['sha1'] as String,
      size: json['size'] as int,
      encryptedSize: json['encrypted_size'] as int,
      encryptedName: json['encrypted_name'] as String,
      modifiedAt: DateTime.parse(json['modified_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'sha1': sha1,
      'size': size,
      'encrypted_size': encryptedSize,
      'encrypted_name': encryptedName,
      'modified_at': modifiedAt.toIso8601String(),
    };
  }
}

/// Backup manifest containing all file entries
class BackupManifest {
  /// Manifest version
  String version;

  /// Snapshot ID (YYYY-MM-DD)
  String snapshotId;

  /// Client NPUB
  String clientNpub;

  /// Client callsign
  String clientCallsign;

  /// When backup started
  DateTime startedAt;

  /// When backup completed
  DateTime? completedAt;

  /// Total files in backup
  int totalFiles;

  /// Total bytes (unencrypted)
  int totalBytes;

  /// List of file entries
  List<BackupFileEntry> files;

  BackupManifest({
    this.version = '1.0',
    required this.snapshotId,
    required this.clientNpub,
    required this.clientCallsign,
    required this.startedAt,
    this.completedAt,
    this.totalFiles = 0,
    this.totalBytes = 0,
    List<BackupFileEntry>? files,
  }) : files = files ?? [];

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    return BackupManifest(
      version: json['version'] as String? ?? '1.0',
      snapshotId: json['snapshot_id'] as String,
      clientNpub: json['client_npub'] as String,
      clientCallsign: json['client_callsign'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      totalFiles: json['total_files'] as int? ?? 0,
      totalBytes: json['total_bytes'] as int? ?? 0,
      files: (json['files'] as List<dynamic>?)
              ?.map((f) => BackupFileEntry.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'snapshot_id': snapshotId,
      'client_npub': clientNpub,
      'client_callsign': clientCallsign,
      'started_at': startedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      'total_files': totalFiles,
      'total_bytes': totalBytes,
      'files': files.map((f) => f.toJson()).toList(),
    };
  }
}

/// Backup/restore progress status
class BackupStatus {
  /// Provider callsign (if in progress)
  String? providerCallsign;

  /// Snapshot ID (if in progress)
  String? snapshotId;

  /// Status (idle, in_progress, complete, failed)
  String status;

  /// Progress percentage (0-100)
  int progressPercent;

  /// Files transferred so far
  int filesTransferred;

  /// Total files to transfer
  int filesTotal;

  /// Bytes transferred so far
  int bytesTransferred;

  /// Total bytes to transfer
  int bytesTotal;

  /// When operation started
  DateTime? startedAt;

  /// Error message (if failed)
  String? error;

  BackupStatus({
    this.providerCallsign,
    this.snapshotId,
    this.status = 'idle',
    this.progressPercent = 0,
    this.filesTransferred = 0,
    this.filesTotal = 0,
    this.bytesTransferred = 0,
    this.bytesTotal = 0,
    this.startedAt,
    this.error,
  });

  factory BackupStatus.idle() {
    return BackupStatus(status: 'idle');
  }

  factory BackupStatus.fromJson(Map<String, dynamic> json) {
    return BackupStatus(
      providerCallsign: json['provider_callsign'] as String?,
      snapshotId: json['snapshot_id'] as String?,
      status: json['status'] as String? ?? 'idle',
      progressPercent: json['progress_percent'] as int? ?? 0,
      filesTransferred: json['files_transferred'] as int? ?? 0,
      filesTotal: json['files_total'] as int? ?? 0,
      bytesTransferred: json['bytes_transferred'] as int? ?? 0,
      bytesTotal: json['bytes_total'] as int? ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (providerCallsign != null) 'provider_callsign': providerCallsign,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      'status': status,
      'progress_percent': progressPercent,
      'files_transferred': filesTransferred,
      'files_total': filesTotal,
      'bytes_transferred': bytesTransferred,
      'bytes_total': bytesTotal,
      if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }

  BackupStatus copyWith({
    String? providerCallsign,
    String? snapshotId,
    String? status,
    int? progressPercent,
    int? filesTransferred,
    int? filesTotal,
    int? bytesTransferred,
    int? bytesTotal,
    DateTime? startedAt,
    String? error,
  }) {
    return BackupStatus(
      providerCallsign: providerCallsign ?? this.providerCallsign,
      snapshotId: snapshotId ?? this.snapshotId,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      filesTransferred: filesTransferred ?? this.filesTransferred,
      filesTotal: filesTotal ?? this.filesTotal,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      startedAt: startedAt ?? this.startedAt,
      error: error ?? this.error,
    );
  }

  bool get isIdle => status == 'idle';
  bool get isInProgress => status == 'in_progress';
  bool get isComplete => status == 'complete';
  bool get isFailed => status == 'failed';
}

/// Discovered provider during account restoration
class DiscoveredProvider {
  /// Provider callsign
  String callsign;

  /// Provider NPUB
  String npub;

  /// Maximum storage available
  int maxStorageBytes;

  /// Number of snapshots stored
  int snapshotCount;

  /// Latest snapshot ID (if any)
  String? latestSnapshot;

  DiscoveredProvider({
    required this.callsign,
    required this.npub,
    this.maxStorageBytes = 0,
    this.snapshotCount = 0,
    this.latestSnapshot,
  });

  factory DiscoveredProvider.fromJson(Map<String, dynamic> json) {
    return DiscoveredProvider(
      callsign: json['callsign'] as String,
      npub: json['npub'] as String,
      maxStorageBytes: json['max_storage_bytes'] as int? ?? 0,
      snapshotCount: json['snapshot_count'] as int? ?? 0,
      latestSnapshot: json['latest_snapshot'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'callsign': callsign,
      'npub': npub,
      'max_storage_bytes': maxStorageBytes,
      'snapshot_count': snapshotCount,
      if (latestSnapshot != null) 'latest_snapshot': latestSnapshot,
    };
  }
}

/// Discovery status for account restoration
class DiscoveryStatus {
  /// Unique discovery ID
  String discoveryId;

  /// Status (in_progress, complete)
  String status;

  /// Total devices to query
  int devicesToQuery;

  /// Devices queried so far
  int devicesQueried;

  /// Devices that responded
  int devicesResponded;

  /// Providers found with backups
  List<DiscoveredProvider> providersFound;

  DiscoveryStatus({
    required this.discoveryId,
    this.status = 'in_progress',
    this.devicesToQuery = 0,
    this.devicesQueried = 0,
    this.devicesResponded = 0,
    List<DiscoveredProvider>? providersFound,
  }) : providersFound = providersFound ?? [];

  factory DiscoveryStatus.fromJson(Map<String, dynamic> json) {
    return DiscoveryStatus(
      discoveryId: json['discovery_id'] as String,
      status: json['status'] as String? ?? 'in_progress',
      devicesToQuery: json['devices_to_query'] as int? ?? 0,
      devicesQueried: json['devices_queried'] as int? ?? 0,
      devicesResponded: json['devices_responded'] as int? ?? 0,
      providersFound: (json['providers_found'] as List<dynamic>?)
              ?.map((p) => DiscoveredProvider.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'discovery_id': discoveryId,
      'status': status,
      'devices_to_query': devicesToQuery,
      'devices_queried': devicesQueried,
      'devices_responded': devicesResponded,
      'providers_found': providersFound.map((p) => p.toJson()).toList(),
    };
  }

  bool get isInProgress => status == 'in_progress';
  bool get isComplete => status == 'complete';

  DiscoveryStatus copyWith({
    String? discoveryId,
    String? status,
    int? devicesToQuery,
    int? devicesQueried,
    int? devicesResponded,
    List<DiscoveredProvider>? providersFound,
  }) {
    return DiscoveryStatus(
      discoveryId: discoveryId ?? this.discoveryId,
      status: status ?? this.status,
      devicesToQuery: devicesToQuery ?? this.devicesToQuery,
      devicesQueried: devicesQueried ?? this.devicesQueried,
      devicesResponded: devicesResponded ?? this.devicesResponded,
      providersFound: providersFound ?? this.providersFound,
    );
  }
}
