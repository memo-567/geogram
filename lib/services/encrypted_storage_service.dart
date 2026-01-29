/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'package:encrypted_archive/encrypted_archive.dart';

import 'storage_config.dart';
import 'log_service.dart';

/// Callback for migration progress updates
typedef MigrationProgressCallback = void Function(
  int filesProcessed,
  int totalFiles,
  String? currentFile,
);

/// Result of a migration operation
class MigrationResult {
  final bool success;
  final int filesProcessed;
  final String? error;

  MigrationResult({
    required this.success,
    required this.filesProcessed,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'files_processed': filesProcessed,
    if (error != null) 'error': error,
  };
}

/// Status of encrypted storage for a profile
class EncryptedStorageStatus {
  final bool enabled;
  final String? archivePath;
  final int? fileCount;
  final int? totalSize;

  EncryptedStorageStatus({
    required this.enabled,
    this.archivePath,
    this.fileCount,
    this.totalSize,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (archivePath != null) 'archive_path': archivePath,
    if (fileCount != null) 'file_count': fileCount,
    if (totalSize != null) 'total_size': totalSize,
  };
}

/// Service for managing encrypted profile storage
///
/// Uses the encrypted_archive package to store profile data in an encrypted
/// SQLite database. The database structure is browsable (files table, chunks table),
/// but the file content is AES-256-GCM encrypted.
///
/// Password is derived from the NOSTR nsec using HKDF.
class EncryptedStorageService {
  static final EncryptedStorageService _instance = EncryptedStorageService._internal();
  factory EncryptedStorageService() => _instance;
  EncryptedStorageService._internal();

  final StorageConfig _storageConfig = StorageConfig();
  final LogService _log = LogService();

  /// Derive encryption password from nsec
  /// Uses HKDF with SHA-256 to derive a stable password from the nsec
  String _derivePassword(String nsec) {
    // Use HKDF-like derivation: HMAC-SHA256(nsec, "geogram-encrypted-storage")
    final key = utf8.encode(nsec);
    final info = utf8.encode('geogram-encrypted-storage-v1');
    final hmac = crypto.Hmac(crypto.sha256, key);
    final digest = hmac.convert(info);
    // Return hex-encoded hash as password
    return digest.toString();
  }

  /// Get the archive path for a callsign
  String _getArchivePath(String callsign) {
    return _storageConfig.getEncryptedArchivePath(callsign);
  }

  /// Get the profile folder path for a callsign
  String _getProfilePath(String callsign) {
    return p.join(_storageConfig.devicesDir, callsign);
  }

  /// Check if encrypted storage is enabled for a profile
  bool isEncryptedStorageEnabled(String callsign) {
    final archivePath = _getArchivePath(callsign);
    return File(archivePath).existsSync();
  }

  /// Get status of encrypted storage for a profile
  Future<EncryptedStorageStatus> getStatus(String callsign) async {
    final archivePath = _getArchivePath(callsign);
    final archiveFile = File(archivePath);

    if (!await archiveFile.exists()) {
      return EncryptedStorageStatus(enabled: false);
    }

    // Get file size
    final stat = await archiveFile.stat();

    return EncryptedStorageStatus(
      enabled: true,
      archivePath: archivePath,
      totalSize: stat.size,
    );
  }

  /// Migrate profile from folders to encrypted archive
  Future<MigrationResult> migrateToEncrypted(
    String callsign,
    String nsec, {
    MigrationProgressCallback? onProgress,
  }) async {
    final profilePath = _getProfilePath(callsign);
    final archivePath = _getArchivePath(callsign);
    final profileDir = Directory(profilePath);

    if (!await profileDir.exists()) {
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Profile folder does not exist: $profilePath',
      );
    }

    // Check if archive already exists
    if (await File(archivePath).exists()) {
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Encrypted archive already exists',
      );
    }

    try {
      final password = _derivePassword(nsec);

      // Pre-scan to count total files
      final filesToProcess = <File>[];
      await for (final entity in profileDir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = p.relative(entity.path, from: profilePath);
          if (!relativePath.startsWith('.') && !relativePath.contains('/.')) {
            filesToProcess.add(entity);
          }
        }
      }
      final totalFiles = filesToProcess.length;

      // Create new encrypted archive
      final archive = await EncryptedArchive.create(
        archivePath,
        password,
        description: 'Geogram profile: $callsign',
      );

      int filesProcessed = 0;

      try {
        // Add all files from profile folder
        for (final file in filesToProcess) {
          final relativePath = p.relative(file.path, from: profilePath);

          _log.log('EncryptedStorage: Adding $relativePath');
          onProgress?.call(filesProcessed, totalFiles, relativePath);

          await archive.addFileFromDisk(relativePath, file.path);
          filesProcessed++;
        }

        // Final progress update
        onProgress?.call(filesProcessed, totalFiles, null);

        await archive.close();

        // Remove the original profile folder after successful migration
        await profileDir.delete(recursive: true);

        _log.log('EncryptedStorage: Migration complete, $filesProcessed files encrypted');

        return MigrationResult(
          success: true,
          filesProcessed: filesProcessed,
        );
      } catch (e) {
        await archive.close();
        // Clean up failed archive
        try {
          await File(archivePath).delete();
        } catch (_) {}
        rethrow;
      }
    } catch (e) {
      _log.log('EncryptedStorage: Migration failed: $e');
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: e.toString(),
      );
    }
  }

  /// Migrate profile from encrypted archive back to folders
  Future<MigrationResult> migrateToFolders(
    String callsign,
    String nsec, {
    MigrationProgressCallback? onProgress,
  }) async {
    final profilePath = _getProfilePath(callsign);
    final archivePath = _getArchivePath(callsign);
    final archiveFile = File(archivePath);

    if (!await archiveFile.exists()) {
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Encrypted archive does not exist',
      );
    }

    try {
      final password = _derivePassword(nsec);

      // Open encrypted archive
      final archive = await EncryptedArchive.open(archivePath, password);

      try {
        // Create profile directory
        final profileDir = Directory(profilePath);
        if (!await profileDir.exists()) {
          await profileDir.create(recursive: true);
        }

        // Get all file entries and count total
        final entries = await archive.listFiles();
        final fileEntries = entries.where((e) => e.isFile).toList();
        final totalFiles = fileEntries.length;
        int filesProcessed = 0;

        for (final entry in fileEntries) {
          final destPath = p.join(profilePath, entry.path);
          _log.log('EncryptedStorage: Extracting ${entry.path}');
          onProgress?.call(filesProcessed, totalFiles, entry.path);

          await archive.extractFile(entry.path, destPath);
          filesProcessed++;
        }

        // Final progress update
        onProgress?.call(filesProcessed, totalFiles, null);

        await archive.close();

        // Remove the archive after successful extraction
        await archiveFile.delete();

        _log.log('EncryptedStorage: Extraction complete, $filesProcessed files decrypted');

        return MigrationResult(
          success: true,
          filesProcessed: filesProcessed,
        );
      } catch (e) {
        await archive.close();
        rethrow;
      }
    } on ArchiveAuthenticationException {
      _log.log('EncryptedStorage: Invalid password');
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Invalid password (nsec mismatch)',
      );
    } catch (e) {
      _log.log('EncryptedStorage: Extraction failed: $e');
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: e.toString(),
      );
    }
  }

  /// Read a file from encrypted storage
  /// Returns null if file not found or encrypted storage not enabled
  Future<Uint8List?> readFile(String callsign, String nsec, String relativePath) async {
    final archivePath = _getArchivePath(callsign);

    if (!await File(archivePath).exists()) {
      return null;
    }

    try {
      final password = _derivePassword(nsec);
      final archive = await EncryptedArchive.open(archivePath, password);

      try {
        if (!await archive.exists(relativePath)) {
          await archive.close();
          return null;
        }

        final content = await archive.readFileBytes(relativePath);
        await archive.close();
        return content;
      } catch (e) {
        await archive.close();
        rethrow;
      }
    } catch (e) {
      _log.log('EncryptedStorage: Failed to read $relativePath: $e');
      return null;
    }
  }

  /// Write a file to encrypted storage
  Future<bool> writeFile(String callsign, String nsec, String relativePath, Uint8List content) async {
    final archivePath = _getArchivePath(callsign);

    if (!await File(archivePath).exists()) {
      return false;
    }

    try {
      final password = _derivePassword(nsec);
      final archive = await EncryptedArchive.open(archivePath, password);

      try {
        // Delete existing file if present
        if (await archive.exists(relativePath)) {
          await archive.delete(relativePath);
        }

        await archive.addBytes(relativePath, content);
        await archive.close();
        return true;
      } catch (e) {
        await archive.close();
        rethrow;
      }
    } catch (e) {
      _log.log('EncryptedStorage: Failed to write $relativePath: $e');
      return false;
    }
  }

  /// Delete a file from encrypted storage
  Future<bool> deleteFile(String callsign, String nsec, String relativePath) async {
    final archivePath = _getArchivePath(callsign);

    if (!await File(archivePath).exists()) {
      return false;
    }

    try {
      final password = _derivePassword(nsec);
      final archive = await EncryptedArchive.open(archivePath, password);

      try {
        if (await archive.exists(relativePath)) {
          await archive.delete(relativePath);
        }
        await archive.close();
        return true;
      } catch (e) {
        await archive.close();
        rethrow;
      }
    } catch (e) {
      _log.log('EncryptedStorage: Failed to delete $relativePath: $e');
      return false;
    }
  }

  /// List files in encrypted storage
  Future<List<String>?> listFiles(String callsign, String nsec, {String? prefix}) async {
    final archivePath = _getArchivePath(callsign);

    if (!await File(archivePath).exists()) {
      return null;
    }

    try {
      final password = _derivePassword(nsec);
      final archive = await EncryptedArchive.open(archivePath, password);

      try {
        final entries = await archive.listFiles(prefix: prefix);
        await archive.close();
        return entries.where((e) => e.isFile).map((e) => e.path).toList();
      } catch (e) {
        await archive.close();
        rethrow;
      }
    } catch (e) {
      _log.log('EncryptedStorage: Failed to list files: $e');
      return null;
    }
  }
}
