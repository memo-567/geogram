/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Backup Service Implementation
 * Manages backup operations for both client (backing up to remote) and provider (storing backups for others)
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../connection/connection_manager.dart';
import '../models/backup_models.dart';
import '../util/backup_encryption.dart';
import '../util/nostr_crypto.dart';
import '../util/nostr_event.dart';
import 'config_service.dart';
import 'devices_service.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'security_service.dart';
import 'storage_config.dart';
import 'websocket_service.dart';

/// Backup service singleton managing both client and provider operations
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  // === State ===
  bool _initialized = false;
  String? _basePath;

  // Provider state
  BackupProviderSettings? _providerSettings;
  final Map<String, BackupClientRelationship> _clients = {};

  // Client state
  final Map<String, BackupProviderRelationship> _providers = {};
  BackupStatus _backupStatus = BackupStatus.idle();
  BackupStatus _restoreStatus = BackupStatus.idle();

  // Discovery state
  final Map<String, DiscoveryStatus> _activeDiscoveries = {};

  // Pending invitations (client waiting for provider response)
  final Map<String, Completer<BackupProviderRelationship>> _pendingInvites = {};

  // === Stream controllers ===
  final _statusController = StreamController<BackupStatus>.broadcast();
  final _providersController = StreamController<List<BackupProviderRelationship>>.broadcast();
  final _clientsController = StreamController<List<BackupClientRelationship>>.broadcast();

  /// Stream of backup/restore status updates
  Stream<BackupStatus> get statusStream => _statusController.stream;

  /// Stream of provider relationship changes (for client)
  Stream<List<BackupProviderRelationship>> get providersStream => _providersController.stream;

  /// Stream of client relationship changes (for provider)
  Stream<List<BackupClientRelationship>> get clientsStream => _clientsController.stream;

  // === Initialization ===

  /// Initialize the backup service
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _log('BackupService: Web platform not supported');
      return;
    }

    try {
      final storageConfig = StorageConfig();
      if (!storageConfig.isInitialized) {
        await storageConfig.init();
      }

      _basePath = storageConfig.baseDir;

      // Ensure directories exist
      await _ensureDirectories();

      // Load settings
      await _loadProviderSettings();
      await _loadClients();
      await _loadProviders();

      _initialized = true;
      _log('BackupService initialized');
    } catch (e) {
      _log('BackupService initialization error: $e');
    }
  }

  /// Ensure required directories exist
  Future<void> _ensureDirectories() async {
    final backupsDir = Directory(p.join(_basePath!, 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }

    final configDir = Directory(p.join(_basePath!, 'backup-config'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    final providersDir = Directory(p.join(_basePath!, 'backup-config', 'providers'));
    if (!await providersDir.exists()) {
      await providersDir.create(recursive: true);
    }
  }

  // ============================================================
  // PROVIDER METHODS
  // ============================================================

  /// Get provider settings
  BackupProviderSettings? get providerSettings => _providerSettings;

  /// Enable provider mode with default settings
  Future<void> enableProviderMode({
    required int maxTotalStorageBytes,
    required int defaultMaxClientStorageBytes,
    required int defaultMaxSnapshots,
  }) async {
    final settings = BackupProviderSettings(
      enabled: true,
      maxTotalStorageBytes: maxTotalStorageBytes,
      defaultMaxClientStorageBytes: defaultMaxClientStorageBytes,
      defaultMaxSnapshots: defaultMaxSnapshots,
    );
    await saveProviderSettings(settings);
    _log('Provider mode enabled');
  }

  /// Disable provider mode
  Future<void> disableProviderMode() async {
    if (_providerSettings != null) {
      _providerSettings!.enabled = false;
      await saveProviderSettings(_providerSettings!);
      _log('Provider mode disabled');
    }
  }

  /// Update provider settings with named parameters
  Future<void> updateProviderSettings({
    int? maxTotalStorageBytes,
    int? defaultMaxClientStorageBytes,
    int? defaultMaxSnapshots,
    bool? autoAcceptFromContacts,
  }) async {
    final settings = _providerSettings ?? BackupProviderSettings();
    if (maxTotalStorageBytes != null) {
      settings.maxTotalStorageBytes = maxTotalStorageBytes;
    }
    if (defaultMaxClientStorageBytes != null) {
      settings.defaultMaxClientStorageBytes = defaultMaxClientStorageBytes;
    }
    if (defaultMaxSnapshots != null) {
      settings.defaultMaxSnapshots = defaultMaxSnapshots;
    }
    if (autoAcceptFromContacts != null) {
      settings.autoAcceptFromContacts = autoAcceptFromContacts;
    }
    await saveProviderSettings(settings);
    _log('Provider settings updated');
  }

  /// Load provider settings from disk
  Future<void> _loadProviderSettings() async {
    final settingsFile = File(p.join(_basePath!, 'backups', 'settings.json'));
    if (await settingsFile.exists()) {
      try {
        final json = jsonDecode(await settingsFile.readAsString());
        _providerSettings = BackupProviderSettings.fromJson(json);
      } catch (e) {
        _log('Error loading provider settings: $e');
        _providerSettings = BackupProviderSettings();
      }
    } else {
      _providerSettings = BackupProviderSettings();
    }
  }

  /// Save provider settings to disk
  Future<void> saveProviderSettings(BackupProviderSettings settings) async {
    _providerSettings = settings;
    final settingsFile = File(p.join(_basePath!, 'backups', 'settings.json'));
    await settingsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  /// Load all client relationships from disk
  Future<void> _loadClients() async {
    final backupsDir = Directory(p.join(_basePath!, 'backups'));
    if (!await backupsDir.exists()) return;

    await for (final entity in backupsDir.list()) {
      if (entity is Directory) {
        final configFile = File(p.join(entity.path, 'config.json'));
        if (await configFile.exists()) {
          try {
            final json = jsonDecode(await configFile.readAsString());
            final relationship = BackupClientRelationship.fromJson(json);
            _clients[relationship.clientCallsign] = relationship;
          } catch (e) {
            _log('Error loading client config from ${entity.path}: $e');
          }
        }
      }
    }
  }

  /// Get all backup clients
  List<BackupClientRelationship> getClients() {
    return _clients.values.toList();
  }

  /// Get a specific client by callsign
  BackupClientRelationship? getClient(String callsign) {
    return _clients[callsign.toUpperCase()];
  }

  /// Accept a backup invitation from a client
  Future<void> acceptInvite(String clientNpub, String clientCallsign, int maxStorageBytes, int maxSnapshots) async {
    final relationship = BackupClientRelationship(
      clientNpub: clientNpub,
      clientCallsign: clientCallsign.toUpperCase(),
      maxStorageBytes: maxStorageBytes,
      maxSnapshots: maxSnapshots,
      status: BackupRelationshipStatus.active,
    );

    await _saveClientRelationship(relationship);
    _clients[clientCallsign.toUpperCase()] = relationship;
    _clientsController.add(getClients());

    // Send response to client
    _sendInviteResponse(clientNpub, clientCallsign, true, maxStorageBytes, maxSnapshots);
  }

  /// Decline a backup invitation from a client
  Future<void> declineInvite(String clientNpub, String clientCallsign) async {
    _sendInviteResponse(clientNpub, clientCallsign, false, 0, 0);
  }

  /// Remove a client (optionally delete their data)
  Future<void> removeClient(String callsign, {bool deleteData = false}) async {
    final normalized = callsign.toUpperCase();
    final client = _clients[normalized];
    if (client == null) return;

    if (deleteData) {
      final clientDir = Directory(p.join(_basePath!, 'backups', normalized));
      if (await clientDir.exists()) {
        await clientDir.delete(recursive: true);
      }
    } else {
      // Just mark as terminated
      final updated = client.copyWith(status: BackupRelationshipStatus.terminated);
      await _saveClientRelationship(updated);
      _clients[normalized] = updated;
    }

    _clientsController.add(getClients());
  }

  /// Save client relationship to disk
  Future<void> _saveClientRelationship(BackupClientRelationship relationship) async {
    final clientDir = Directory(p.join(_basePath!, 'backups', relationship.clientCallsign));
    if (!await clientDir.exists()) {
      await clientDir.create(recursive: true);
    }

    final configFile = File(p.join(clientDir.path, 'config.json'));
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(relationship.toJson()),
    );
  }

  /// Get snapshots for a client
  Future<List<BackupSnapshot>> getSnapshots(String clientCallsign) async {
    final snapshots = <BackupSnapshot>[];
    final clientDir = Directory(p.join(_basePath!, 'backups', clientCallsign.toUpperCase()));

    if (!await clientDir.exists()) return snapshots;

    await for (final entity in clientDir.list()) {
      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        // Check if it's a date folder (YYYY-MM-DD)
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dirName)) {
          final statusFile = File(p.join(entity.path, 'status.json'));
          if (await statusFile.exists()) {
            try {
              final json = jsonDecode(await statusFile.readAsString());
              snapshots.add(BackupSnapshot.fromJson(json));
            } catch (e) {
              _log('Error loading snapshot status from ${entity.path}: $e');
            }
          }
        }
      }
    }

    // Sort by date descending
    snapshots.sort((a, b) => b.snapshotId.compareTo(a.snapshotId));
    return snapshots;
  }

  /// Get manifest for a snapshot
  Future<Uint8List?> getManifest(String clientCallsign, String snapshotId) async {
    final manifestFile = File(p.join(
      _basePath!,
      'backups',
      clientCallsign.toUpperCase(),
      snapshotId,
      'manifest.json',
    ));

    if (await manifestFile.exists()) {
      return await manifestFile.readAsBytes();
    }
    return null;
  }

  /// Get encrypted file from a snapshot
  Future<Uint8List?> getEncryptedFile(String clientCallsign, String snapshotId, String fileName) async {
    final filePath = p.join(
      _basePath!,
      'backups',
      clientCallsign.toUpperCase(),
      snapshotId,
      'files',
      fileName,
    );
    final file = File(filePath);

    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// Save encrypted file to a snapshot
  Future<void> saveEncryptedFile(
    String clientCallsign,
    String snapshotId,
    String fileName,
    Uint8List data,
  ) async {
    final filesDir = Directory(p.join(
      _basePath!,
      'backups',
      clientCallsign.toUpperCase(),
      snapshotId,
      'files',
    ));

    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }

    final file = File(p.join(filesDir.path, fileName));
    await file.writeAsBytes(data);

    // Update client storage stats
    final client = _clients[clientCallsign.toUpperCase()];
    if (client != null) {
      final newSize = client.currentStorageBytes + data.length;
      final updated = client.copyWith(currentStorageBytes: newSize);
      _clients[clientCallsign.toUpperCase()] = updated;
      await _saveClientRelationship(updated);
    }
  }

  /// Save manifest for a snapshot
  Future<void> saveManifest(String clientCallsign, String snapshotId, Uint8List data) async {
    final snapshotDir = Directory(p.join(
      _basePath!,
      'backups',
      clientCallsign.toUpperCase(),
      snapshotId,
    ));

    if (!await snapshotDir.exists()) {
      await snapshotDir.create(recursive: true);
    }

    final file = File(p.join(snapshotDir.path, 'manifest.json'));
    await file.writeAsBytes(data);
  }

  /// Update snapshot status
  Future<void> updateSnapshotStatus(String clientCallsign, BackupSnapshot snapshot) async {
    final snapshotDir = Directory(p.join(
      _basePath!,
      'backups',
      clientCallsign.toUpperCase(),
      snapshot.snapshotId,
    ));

    if (!await snapshotDir.exists()) {
      await snapshotDir.create(recursive: true);
    }

    final file = File(p.join(snapshotDir.path, 'status.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );

    // Update client relationship stats
    final client = _clients[clientCallsign.toUpperCase()];
    if (client != null) {
      final snapshots = await getSnapshots(clientCallsign);
      final updated = client.copyWith(
        snapshotCount: snapshots.length,
        lastBackupAt: snapshot.completedAt ?? snapshot.startedAt,
        lastBackupStatus: snapshot.status,
      );
      _clients[clientCallsign.toUpperCase()] = updated;
      await _saveClientRelationship(updated);
    }
  }

  /// Check if client has quota available
  bool hasQuotaAvailable(String clientCallsign, int additionalBytes) {
    final client = _clients[clientCallsign.toUpperCase()];
    if (client == null) return false;
    return (client.currentStorageBytes + additionalBytes) <= client.maxStorageBytes;
  }

  // ============================================================
  // CLIENT METHODS
  // ============================================================

  /// Load provider relationships from disk
  Future<void> _loadProviders() async {
    final providersDir = Directory(p.join(_basePath!, 'backup-config', 'providers'));
    if (!await providersDir.exists()) return;

    await for (final entity in providersDir.list()) {
      if (entity is Directory) {
        final configFile = File(p.join(entity.path, 'config.json'));
        if (await configFile.exists()) {
          try {
            final json = jsonDecode(await configFile.readAsString());
            final relationship = BackupProviderRelationship.fromJson(json);
            _providers[relationship.providerCallsign] = relationship;
          } catch (e) {
            _log('Error loading provider config from ${entity.path}: $e');
          }
        }
      }
    }
  }

  /// Get all backup providers (as client)
  List<BackupProviderRelationship> getProviders() {
    return _providers.values.toList();
  }

  /// Get a specific provider by callsign
  BackupProviderRelationship? getProvider(String callsign) {
    return _providers[callsign.toUpperCase()];
  }

  /// Send backup invitation to a provider
  Future<BackupProviderRelationship?> sendInvite(String providerCallsign, int intervalDays) async {
    final profile = ProfileService().getProfile();
    final myNpub = profile.npub;
    final myCallsign = profile.callsign;

    if (myNpub.isEmpty || myCallsign.isEmpty) {
      _log('Cannot send invite: identity not available');
      return null;
    }

    // Create pending relationship
    final relationship = BackupProviderRelationship(
      providerNpub: '', // Will be filled when provider responds
      providerCallsign: providerCallsign.toUpperCase(),
      backupIntervalDays: intervalDays,
      status: BackupRelationshipStatus.pending,
    );

    // Save locally
    await _saveProviderRelationship(relationship);
    _providers[providerCallsign.toUpperCase()] = relationship;
    _providersController.add(getProviders());

    // Create signed invite event
    final event = _createInviteEvent(providerCallsign, intervalDays);

    // Send via WebSocket
    WebSocketService().send({
      'type': 'backup_invite',
      'target': providerCallsign,
      'event': event.toJson(),
    });

    // Wait for response (with timeout)
    final completer = Completer<BackupProviderRelationship>();
    _pendingInvites[providerCallsign.toUpperCase()] = completer;

    try {
      return await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _pendingInvites.remove(providerCallsign.toUpperCase());
          throw TimeoutException('Invite timed out');
        },
      );
    } catch (e) {
      _log('Invite failed: $e');
      return null;
    }
  }

  /// Save provider relationship to disk
  Future<void> _saveProviderRelationship(BackupProviderRelationship relationship) async {
    final providerDir = Directory(p.join(
      _basePath!,
      'backup-config',
      'providers',
      relationship.providerCallsign,
    ));

    if (!await providerDir.exists()) {
      await providerDir.create(recursive: true);
    }

    final configFile = File(p.join(providerDir.path, 'config.json'));
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(relationship.toJson()),
    );
  }

  /// Remove a provider relationship
  Future<void> removeProvider(String providerCallsign) async {
    final normalized = providerCallsign.toUpperCase();
    final provider = _providers[normalized];
    if (provider == null) return;

    // Mark as terminated
    final updated = provider.copyWith(status: BackupRelationshipStatus.terminated);
    await _saveProviderRelationship(updated);
    _providers[normalized] = updated;
    _providersController.add(getProviders());

    // Notify provider
    WebSocketService().send({
      'type': 'backup_status_change',
      'target': providerCallsign,
      'status': 'terminated',
    });
  }

  /// Update a provider relationship
  Future<void> updateProvider(BackupProviderRelationship provider) async {
    final normalized = provider.providerCallsign.toUpperCase();
    _providers[normalized] = provider;
    await _saveProviderRelationship(provider);
    _providersController.add(getProviders());
  }

  /// Get current backup status
  BackupStatus get backupStatus => _backupStatus;

  /// Get current restore status
  BackupStatus get restoreStatus => _restoreStatus;

  /// Start a backup to a provider
  Future<BackupStatus> startBackup(String providerCallsign) async {
    if (_backupStatus.isInProgress) {
      return _backupStatus.copyWith(error: 'Backup already in progress');
    }

    final provider = _providers[providerCallsign.toUpperCase()];
    if (provider == null || provider.status != BackupRelationshipStatus.active) {
      return BackupStatus(status: 'failed', error: 'Provider not active');
    }

    final snapshotId = _generateSnapshotId();
    _backupStatus = BackupStatus(
      providerCallsign: providerCallsign,
      snapshotId: snapshotId,
      status: 'in_progress',
      startedAt: DateTime.now(),
    );
    _statusController.add(_backupStatus);

    // Run backup in background
    _runBackup(providerCallsign, snapshotId);

    return _backupStatus;
  }

  /// Run the backup process
  Future<void> _runBackup(String providerCallsign, String snapshotId) async {
    try {
      final profile = ProfileService().getProfile();
      final myNsec = profile.nsec;
      final myNpub = profile.npub;
      final myCallsign = profile.callsign;

      if (myNsec.isEmpty || myNpub.isEmpty || myCallsign.isEmpty) {
        throw Exception('Identity not available');
      }

      // Get list of files to backup (entire working folder)
      final workingDir = Directory(_basePath!);
      final files = await _enumerateFilesForBackup(workingDir);

      _backupStatus = _backupStatus.copyWith(
        filesTotal: files.length,
        bytesTotal: files.fold<int>(0, (sum, f) => sum + f.lengthSync()),
      );
      _statusController.add(_backupStatus);

      // Create manifest
      final manifest = BackupManifest(
        snapshotId: snapshotId,
        clientNpub: myNpub,
        clientCallsign: myCallsign,
        startedAt: DateTime.now(),
      );

      // Process each file
      int filesTransferred = 0;
      int bytesTransferred = 0;

      for (final file in files) {
        final relativePath = p.relative(file.path, from: _basePath!);

        // Skip backup-related directories
        if (relativePath.startsWith('backups') || relativePath.startsWith('backup-config')) {
          continue;
        }

        final content = await file.readAsBytes();
        final sha1Hash = sha1.convert(content).toString();

        // Encrypt file
        final encrypted = BackupEncryption.encryptFile(Uint8List.fromList(content), myNpub);
        final encryptedName = _generateEncryptedFileName();

        // Upload to provider
        final uploaded = await _uploadEncryptedFile(
          providerCallsign,
          snapshotId,
          encryptedName,
          encrypted,
        );

        if (!uploaded) {
          throw Exception('Failed to upload file: $relativePath');
        }

        // Add to manifest
        manifest.files.add(BackupFileEntry(
          path: relativePath,
          sha1: sha1Hash,
          size: content.length,
          encryptedSize: encrypted.length,
          encryptedName: encryptedName,
          modifiedAt: await file.lastModified(),
        ));

        filesTransferred++;
        bytesTransferred += content.length;

        _backupStatus = _backupStatus.copyWith(
          filesTransferred: filesTransferred,
          bytesTransferred: bytesTransferred,
          progressPercent: (filesTransferred * 100 ~/ files.length).clamp(0, 100),
        );
        _statusController.add(_backupStatus);
      }

      // Finalize manifest
      manifest.totalFiles = manifest.files.length;
      manifest.totalBytes = manifest.files.fold(0, (sum, f) => sum + f.size);
      manifest.completedAt = DateTime.now();

      // Encrypt and upload manifest
      final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest.toJson());
      final encryptedManifest = BackupEncryption.encryptManifest(manifestJson, myNsec);

      await _uploadManifest(providerCallsign, snapshotId, encryptedManifest);

      // Mark complete
      _backupStatus = _backupStatus.copyWith(
        status: 'complete',
        progressPercent: 100,
      );
      _statusController.add(_backupStatus);

      // Update provider relationship
      final provider = _providers[providerCallsign.toUpperCase()];
      if (provider != null) {
        final updated = provider.copyWith(
          lastSuccessfulBackup: DateTime.now(),
          nextScheduledBackup: DateTime.now().add(Duration(days: provider.backupIntervalDays)),
        );
        await _saveProviderRelationship(updated);
        _providers[providerCallsign.toUpperCase()] = updated;
        _providersController.add(getProviders());
      }

      // Notify provider
      WebSocketService().send({
        'type': 'backup_complete',
        'target': providerCallsign,
        'snapshot_id': snapshotId,
        'total_files': manifest.totalFiles,
        'total_bytes': manifest.totalBytes,
      });

      _log('Backup completed: $snapshotId, ${manifest.totalFiles} files, ${manifest.totalBytes} bytes');
    } catch (e) {
      _backupStatus = _backupStatus.copyWith(
        status: 'failed',
        error: e.toString(),
      );
      _statusController.add(_backupStatus);
      _log('Backup failed: $e');
    }
  }

  /// Enumerate files for backup (excluding certain directories)
  Future<List<File>> _enumerateFilesForBackup(Directory dir) async {
    final files = <File>[];
    final excludeDirs = {'backups', 'backup-config', 'updates', '.dart_tool', 'build'};

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: dir.path);
        final parts = p.split(relativePath);

        // Skip excluded directories
        if (parts.any((part) => excludeDirs.contains(part))) {
          continue;
        }

        files.add(entity);
      }
    }

    return files;
  }

  /// Start restore from a provider
  Future<void> startRestore(String providerCallsign, String snapshotId) async {
    if (_restoreStatus.isInProgress) {
      return;
    }

    final provider = _providers[providerCallsign.toUpperCase()];
    if (provider == null) {
      _restoreStatus = BackupStatus(status: 'failed', error: 'Provider not found');
      _statusController.add(_restoreStatus);
      return;
    }

    _restoreStatus = BackupStatus(
      providerCallsign: providerCallsign,
      snapshotId: snapshotId,
      status: 'in_progress',
      startedAt: DateTime.now(),
    );
    _statusController.add(_restoreStatus);

    // Run restore in background
    _runRestore(providerCallsign, snapshotId);
  }

  /// Run the restore process
  Future<void> _runRestore(String providerCallsign, String snapshotId) async {
    try {
      final profile = ProfileService().getProfile();
      final myNsec = profile.nsec;

      if (myNsec.isEmpty) {
        throw Exception('Identity not available');
      }

      // Download encrypted manifest
      final encryptedManifest = await _downloadManifest(providerCallsign, snapshotId);
      if (encryptedManifest == null) {
        throw Exception('Failed to download manifest');
      }

      // Decrypt manifest
      final manifestJson = BackupEncryption.decryptManifest(encryptedManifest, myNsec);
      final manifest = BackupManifest.fromJson(jsonDecode(manifestJson));

      _restoreStatus = _restoreStatus.copyWith(
        filesTotal: manifest.totalFiles,
        bytesTotal: manifest.totalBytes,
      );
      _statusController.add(_restoreStatus);

      int filesTransferred = 0;
      int bytesTransferred = 0;

      // Restore each file
      for (final entry in manifest.files) {
        // Download encrypted file
        final encrypted = await _downloadEncryptedFile(
          providerCallsign,
          snapshotId,
          entry.encryptedName,
        );

        if (encrypted == null) {
          throw Exception('Failed to download file: ${entry.path}');
        }

        // Decrypt file
        final decrypted = BackupEncryption.decryptFile(encrypted, myNsec);

        // Verify SHA1
        final actualSha1 = sha1.convert(decrypted).toString();
        if (actualSha1 != entry.sha1) {
          throw Exception('SHA1 mismatch for file: ${entry.path}');
        }

        // Write to disk
        final targetPath = p.join(_basePath!, entry.path);
        final targetDir = Directory(p.dirname(targetPath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final file = File(targetPath);
        await file.writeAsBytes(decrypted);

        filesTransferred++;
        bytesTransferred += decrypted.length;

        _restoreStatus = _restoreStatus.copyWith(
          filesTransferred: filesTransferred,
          bytesTransferred: bytesTransferred,
          progressPercent: (filesTransferred * 100 ~/ manifest.totalFiles).clamp(0, 100),
        );
        _statusController.add(_restoreStatus);
      }

      // Mark complete
      _restoreStatus = _restoreStatus.copyWith(
        status: 'complete',
        progressPercent: 100,
      );
      _statusController.add(_restoreStatus);

      _log('Restore completed: $snapshotId, ${manifest.totalFiles} files');
    } catch (e) {
      _restoreStatus = _restoreStatus.copyWith(
        status: 'failed',
        error: e.toString(),
      );
      _statusController.add(_restoreStatus);
      _log('Restore failed: $e');
    }
  }

  // ============================================================
  // DISCOVERY (Account Restoration)
  // ============================================================

  /// Start discovery to find backup providers for account restoration
  Future<String> startDiscovery(int timeoutSeconds) async {
    final discoveryId = _generateDiscoveryId();
    final discovery = DiscoveryStatus(
      discoveryId: discoveryId,
      status: 'in_progress',
    );
    _activeDiscoveries[discoveryId] = discovery;

    // Run discovery in background
    _runDiscovery(discoveryId, timeoutSeconds);

    return discoveryId;
  }

  /// Get discovery status
  DiscoveryStatus? getDiscoveryStatus(String discoveryId) {
    return _activeDiscoveries[discoveryId];
  }

  /// Run the discovery process
  Future<void> _runDiscovery(String discoveryId, int timeoutSeconds) async {
    try {
      final profile = ProfileService().getProfile();
      final myNsec = profile.nsec;
      final myNpub = profile.npub;

      if (myNsec.isEmpty || myNpub.isEmpty) {
        throw Exception('Identity not available');
      }

      // Get list of connected devices from station
      final devices = DevicesService().getAllDevices();
      final onlineDevices = devices.where((d) => d.isOnline).toList();

      var discovery = _activeDiscoveries[discoveryId]!;
      discovery = DiscoveryStatus(
        discoveryId: discoveryId,
        status: 'in_progress',
        devicesToQuery: onlineDevices.length,
      );
      _activeDiscoveries[discoveryId] = discovery;

      // Generate random challenge
      final challenge = _generateChallenge();

      // Query each device
      for (final device in onlineDevices) {
        // Create signed discovery query
        final event = _createDiscoveryQueryEvent(myNpub, challenge, device.callsign);

        // Send query
        WebSocketService().send({
          'type': 'backup_discovery_challenge',
          'target': device.callsign,
          'event': event.toJson(),
          'discovery_id': discoveryId,
        });

        discovery = discovery.copyWith(devicesQueried: discovery.devicesQueried + 1);
        _activeDiscoveries[discoveryId] = discovery;
      }

      // Wait for responses (with timeout)
      await Future.delayed(Duration(seconds: timeoutSeconds));

      // Mark complete
      discovery = _activeDiscoveries[discoveryId]!;
      discovery = DiscoveryStatus(
        discoveryId: discoveryId,
        status: 'complete',
        devicesToQuery: discovery.devicesToQuery,
        devicesQueried: discovery.devicesQueried,
        devicesResponded: discovery.devicesResponded,
        providersFound: discovery.providersFound,
      );
      _activeDiscoveries[discoveryId] = discovery;
    } catch (e) {
      _log('Discovery failed: $e');
      final discovery = _activeDiscoveries[discoveryId];
      if (discovery != null) {
        _activeDiscoveries[discoveryId] = DiscoveryStatus(
          discoveryId: discoveryId,
          status: 'complete',
          devicesToQuery: discovery.devicesToQuery,
          devicesQueried: discovery.devicesQueried,
          devicesResponded: discovery.devicesResponded,
          providersFound: discovery.providersFound,
        );
      }
    }
  }

  // ============================================================
  // PROTOCOL MESSAGE HANDLERS
  // ============================================================

  /// Handle incoming backup invite (provider side)
  void handleBackupInvite(Map<String, dynamic> message) {
    try {
      final eventData = message['event'] as Map<String, dynamic>;
      final event = NostrEvent.fromJson(eventData);

      // Verify signature
      if (!event.verify()) {
        _log('Backup invite: invalid signature');
        return;
      }

      // Check timestamp (5 min freshness)
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if ((now - event.createdAt).abs() > 300) {
        _log('Backup invite: event too old');
        return;
      }

      final clientNpub = event.npub;
      final clientCallsign = event.getTagValue('callsign') ?? '';
      final intervalDays = int.tryParse(event.getTagValue('interval_days') ?? '3') ?? 3;

      _log('Received backup invite from $clientCallsign ($clientNpub)');

      // Check if provider is enabled
      if (_providerSettings?.enabled != true) {
        declineInvite(clientNpub, clientCallsign);
        return;
      }

      // Check if auto-accept is enabled for contacts
      // For now, always require manual acceptance
      // Store as pending
      final relationship = BackupClientRelationship(
        clientNpub: clientNpub,
        clientCallsign: clientCallsign,
        maxStorageBytes: _providerSettings?.defaultMaxClientStorageBytes ?? 1073741824,
        maxSnapshots: _providerSettings?.defaultMaxSnapshots ?? 10,
        status: BackupRelationshipStatus.pending,
      );

      _clients[clientCallsign.toUpperCase()] = relationship;
      _saveClientRelationship(relationship);
      _clientsController.add(getClients());

      // TODO: Emit event for UI to show pending invite
    } catch (e) {
      _log('Error handling backup invite: $e');
    }
  }

  /// Handle backup invite response (client side)
  void handleBackupInviteResponse(Map<String, dynamic> message) {
    try {
      final accepted = message['accepted'] as bool? ?? false;
      final providerNpub = message['provider_npub'] as String? ?? '';
      final providerCallsign = message['from'] as String? ?? '';
      final maxStorageBytes = message['max_storage_bytes'] as int? ?? 0;
      final maxSnapshots = message['max_snapshots'] as int? ?? 0;

      _log('Received backup invite response from $providerCallsign: ${accepted ? 'accepted' : 'declined'}');

      final completer = _pendingInvites.remove(providerCallsign.toUpperCase());
      final provider = _providers[providerCallsign.toUpperCase()];

      if (provider != null) {
        final updated = provider.copyWith(
          providerNpub: providerNpub,
          status: accepted ? BackupRelationshipStatus.active : BackupRelationshipStatus.declined,
          maxStorageBytes: maxStorageBytes,
          maxSnapshots: maxSnapshots,
        );

        _providers[providerCallsign.toUpperCase()] = updated;
        _saveProviderRelationship(updated);
        _providersController.add(getProviders());

        completer?.complete(updated);
      }
    } catch (e) {
      _log('Error handling invite response: $e');
    }
  }

  /// Handle backup start notification (provider side)
  void handleBackupStart(Map<String, dynamic> message) {
    final clientCallsign = message['from'] as String? ?? '';
    final snapshotId = message['snapshot_id'] as String? ?? '';

    _log('Backup started by $clientCallsign: $snapshotId');

    // Create snapshot status
    final snapshot = BackupSnapshot(
      snapshotId: snapshotId,
      status: 'in_progress',
      startedAt: DateTime.now(),
    );

    updateSnapshotStatus(clientCallsign, snapshot);
  }

  /// Handle backup complete notification (provider side)
  void handleBackupComplete(Map<String, dynamic> message) {
    final clientCallsign = message['from'] as String? ?? '';
    final snapshotId = message['snapshot_id'] as String? ?? '';
    final totalFiles = message['total_files'] as int? ?? 0;
    final totalBytes = message['total_bytes'] as int? ?? 0;

    _log('Backup completed by $clientCallsign: $snapshotId ($totalFiles files, $totalBytes bytes)');

    // Update snapshot status
    final snapshot = BackupSnapshot(
      snapshotId: snapshotId,
      status: 'complete',
      totalFiles: totalFiles,
      totalBytes: totalBytes,
      completedAt: DateTime.now(),
    );

    updateSnapshotStatus(clientCallsign, snapshot);
  }

  /// Handle discovery challenge (provider side - checking if we have backups for this npub)
  void handleDiscoveryChallenge(Map<String, dynamic> message) {
    try {
      final eventData = message['event'] as Map<String, dynamic>;
      final event = NostrEvent.fromJson(eventData);
      final discoveryId = message['discovery_id'] as String? ?? '';

      // Verify signature
      if (!event.verify()) {
        _log('Discovery challenge: invalid signature');
        return;
      }

      // Check timestamp (5 min freshness)
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if ((now - event.createdAt).abs() > 300) {
        _log('Discovery challenge: event too old');
        return;
      }

      final targetNpub = event.getTagValue('target');
      final challenge = event.getTagValue('challenge');
      final fromCallsign = event.getTagValue('callsign') ?? '';

      if (targetNpub == null || challenge == null) {
        return;
      }

      // Check if we have backups for this npub
      bool hasBackups = false;
      BackupClientRelationship? foundClient;
      List<BackupSnapshot>? snapshots;

      for (final client in _clients.values) {
        if (client.clientNpub == targetNpub && client.status == BackupRelationshipStatus.active) {
          hasBackups = true;
          foundClient = client;
          break;
        }
      }

      if (hasBackups && foundClient != null) {
        // Get snapshots
        getSnapshots(foundClient.clientCallsign).then((snapshotList) {
          // Send response
          _sendDiscoveryResponse(
            fromCallsign,
            discoveryId,
            challenge,
            true,
            foundClient!,
            snapshotList,
          );
        });
      } else {
        // Send negative response (all devices respond to prevent identification)
        _sendDiscoveryResponse(fromCallsign, discoveryId, challenge, false, null, null);
      }
    } catch (e) {
      _log('Error handling discovery challenge: $e');
    }
  }

  /// Handle discovery response (client side)
  void handleDiscoveryResponse(Map<String, dynamic> message) {
    try {
      final eventData = message['event'] as Map<String, dynamic>;
      final event = NostrEvent.fromJson(eventData);
      final discoveryId = message['discovery_id'] as String? ?? '';
      final hasBackups = message['has_backups'] as bool? ?? false;

      // Verify signature
      if (!event.verify()) {
        _log('Discovery response: invalid signature');
        return;
      }

      var discovery = _activeDiscoveries[discoveryId];
      if (discovery == null) return;

      discovery = discovery.copyWith(devicesResponded: discovery.devicesResponded + 1);

      if (hasBackups) {
        final providerCallsign = message['from'] as String? ?? '';
        final providerNpub = event.npub;
        final maxStorageBytes = message['max_storage_bytes'] as int? ?? 0;
        final snapshotCount = message['snapshot_count'] as int? ?? 0;
        final latestSnapshot = message['latest_snapshot'] as String?;

        final provider = DiscoveredProvider(
          callsign: providerCallsign,
          npub: providerNpub,
          maxStorageBytes: maxStorageBytes,
          snapshotCount: snapshotCount,
          latestSnapshot: latestSnapshot,
        );

        discovery = DiscoveryStatus(
          discoveryId: discovery.discoveryId,
          status: discovery.status,
          devicesToQuery: discovery.devicesToQuery,
          devicesQueried: discovery.devicesQueried,
          devicesResponded: discovery.devicesResponded,
          providersFound: [...discovery.providersFound, provider],
        );

        _log('Discovered backup provider: $providerCallsign with $snapshotCount snapshots');
      }

      _activeDiscoveries[discoveryId] = discovery;
    } catch (e) {
      _log('Error handling discovery response: $e');
    }
  }

  /// Handle status change notification
  void handleStatusChange(Map<String, dynamic> message) {
    final fromCallsign = message['from'] as String? ?? '';
    final status = message['status'] as String? ?? '';

    _log('Status change from $fromCallsign: $status');

    // Update client relationship if we're provider
    final client = _clients[fromCallsign.toUpperCase()];
    if (client != null) {
      final newStatus = parseBackupRelationshipStatus(status);
      final updated = client.copyWith(status: newStatus);
      _clients[fromCallsign.toUpperCase()] = updated;
      _saveClientRelationship(updated);
      _clientsController.add(getClients());
    }

    // Update provider relationship if we're client
    final provider = _providers[fromCallsign.toUpperCase()];
    if (provider != null) {
      final newStatus = parseBackupRelationshipStatus(status);
      final updated = provider.copyWith(status: newStatus);
      _providers[fromCallsign.toUpperCase()] = updated;
      _saveProviderRelationship(updated);
      _providersController.add(getProviders());
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Create signed invite event
  NostrEvent _createInviteEvent(String targetCallsign, int intervalDays) {
    final profile = ProfileService().getProfile();
    final myCallsign = profile.callsign;
    final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);

    final event = NostrEvent.textNote(
      pubkeyHex: pubkeyHex,
      content: 'Backup provider invitation',
      tags: [
        ['action', 'backup_invite'],
        ['target', targetCallsign],
        ['callsign', myCallsign],
        ['interval_days', intervalDays.toString()],
      ],
    );
    event.sign(NostrCrypto.decodeNsec(profile.nsec));
    return event;
  }

  /// Create signed discovery query event
  NostrEvent _createDiscoveryQueryEvent(String targetNpub, String challenge, String targetCallsign) {
    final profile = ProfileService().getProfile();
    final myCallsign = profile.callsign;
    final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);

    final event = NostrEvent.textNote(
      pubkeyHex: pubkeyHex,
      content: 'Backup discovery query',
      tags: [
        ['action', 'discovery_query'],
        ['target', targetNpub],
        ['challenge', challenge],
        ['callsign', myCallsign],
        ['target_callsign', targetCallsign],
      ],
    );
    event.sign(NostrCrypto.decodeNsec(profile.nsec));
    return event;
  }

  /// Send invite response
  void _sendInviteResponse(
    String clientNpub,
    String clientCallsign,
    bool accepted,
    int maxStorageBytes,
    int maxSnapshots,
  ) {
    final profile = ProfileService().getProfile();

    WebSocketService().send({
      'type': 'backup_invite_response',
      'target': clientCallsign,
      'accepted': accepted,
      'provider_npub': profile.npub,
      'max_storage_bytes': maxStorageBytes,
      'max_snapshots': maxSnapshots,
    });
  }

  /// Send discovery response
  void _sendDiscoveryResponse(
    String targetCallsign,
    String discoveryId,
    String challenge,
    bool hasBackups,
    BackupClientRelationship? client,
    List<BackupSnapshot>? snapshots,
  ) {
    final profile = ProfileService().getProfile();
    final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);

    // Create signed response event
    final event = NostrEvent.textNote(
      pubkeyHex: pubkeyHex,
      content: 'Backup discovery response',
      tags: [
        ['action', 'discovery_response'],
        ['challenge', challenge],
        ['has_backups', hasBackups.toString()],
      ],
    );
    event.sign(NostrCrypto.decodeNsec(profile.nsec));

    final message = <String, dynamic>{
      'type': 'backup_discovery_response',
      'target': targetCallsign,
      'discovery_id': discoveryId,
      'event': event.toJson(),
      'has_backups': hasBackups,
    };

    if (hasBackups && client != null && snapshots != null) {
      message['max_storage_bytes'] = client.maxStorageBytes;
      message['snapshot_count'] = snapshots.length;
      if (snapshots.isNotEmpty) {
        message['latest_snapshot'] = snapshots.first.snapshotId;
      }
    }

    WebSocketService().send(message);
  }

  /// Upload encrypted file to provider via ConnectionManager
  Future<bool> _uploadEncryptedFile(
    String providerCallsign,
    String snapshotId,
    String fileName,
    Uint8List data,
  ) async {
    try {
      final myCallsign = ProfileService().getProfile().callsign;
      final result = await ConnectionManager().apiRequest(
        callsign: providerCallsign,
        method: 'PUT',
        path: '/api/backup/clients/$myCallsign/snapshots/$snapshotId/files/$fileName',
        body: base64Encode(data),
      );
      return result.success;
    } catch (e) {
      _log('Upload file error: $e');
      return false;
    }
  }

  /// Upload manifest to provider via ConnectionManager
  Future<bool> _uploadManifest(
    String providerCallsign,
    String snapshotId,
    Uint8List data,
  ) async {
    try {
      final myCallsign = ProfileService().getProfile().callsign;
      final result = await ConnectionManager().apiRequest(
        callsign: providerCallsign,
        method: 'PUT',
        path: '/api/backup/clients/$myCallsign/snapshots/$snapshotId',
        body: base64Encode(data),
      );
      return result.success;
    } catch (e) {
      _log('Upload manifest error: $e');
      return false;
    }
  }

  /// Download manifest from provider via ConnectionManager
  Future<Uint8List?> _downloadManifest(String providerCallsign, String snapshotId) async {
    try {
      final myCallsign = ProfileService().getProfile().callsign;
      final result = await ConnectionManager().apiRequest(
        callsign: providerCallsign,
        method: 'GET',
        path: '/api/backup/clients/$myCallsign/snapshots/$snapshotId',
      );
      if (result.success && result.responseData != null) {
        final data = result.responseData;
        if (data is Map && data['data'] != null) {
          return base64Decode(data['data'] as String);
        }
      }
      return null;
    } catch (e) {
      _log('Download manifest error: $e');
      return null;
    }
  }

  /// Download encrypted file from provider via ConnectionManager
  Future<Uint8List?> _downloadEncryptedFile(
    String providerCallsign,
    String snapshotId,
    String fileName,
  ) async {
    try {
      final myCallsign = ProfileService().getProfile().callsign;
      final result = await ConnectionManager().apiRequest(
        callsign: providerCallsign,
        method: 'GET',
        path: '/api/backup/clients/$myCallsign/snapshots/$snapshotId/files/$fileName',
      );
      if (result.success && result.responseData != null) {
        final data = result.responseData;
        if (data is Map && data['data'] != null) {
          return base64Decode(data['data'] as String);
        }
      }
      return null;
    } catch (e) {
      _log('Download file error: $e');
      return null;
    }
  }

  /// Generate snapshot ID (YYYY-MM-DD format)
  String _generateSnapshotId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Generate encrypted file name
  String _generateEncryptedFileName() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return '${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}.enc';
  }

  /// Generate discovery ID
  String _generateDiscoveryId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generate random challenge for discovery
  String _generateChallenge() {
    final random = Random.secure();
    final bytes = List.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _log(String message) {
    LogService().log(message);
  }

  /// Dispose resources
  void dispose() {
    _statusController.close();
    _providersController.close();
    _clientsController.close();
  }
}
