/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/foundation.dart';

import 'encrypted_storage_service.dart';

/// Progress state for encryption/decryption operations
class EncryptionProgress {
  final int filesProcessed;
  final int totalFiles;
  final String? currentFile;
  final bool isEncrypting; // true=encrypt, false=decrypt

  const EncryptionProgress({
    required this.filesProcessed,
    required this.totalFiles,
    required this.isEncrypting,
    this.currentFile,
  });

  int get percent => totalFiles > 0 ? (filesProcessed * 100 ~/ totalFiles) : 0;

  EncryptionProgress copyWith({
    int? filesProcessed,
    int? totalFiles,
    String? currentFile,
    bool? isEncrypting,
  }) {
    return EncryptionProgress(
      filesProcessed: filesProcessed ?? this.filesProcessed,
      totalFiles: totalFiles ?? this.totalFiles,
      currentFile: currentFile ?? this.currentFile,
      isEncrypting: isEncrypting ?? this.isEncrypting,
    );
  }
}

/// Singleton controller for tracking encryption/decryption progress
///
/// Persists across page navigation, allowing users to navigate away
/// and return to see ongoing progress.
class EncryptionProgressController {
  static final EncryptionProgressController instance = EncryptionProgressController._();
  EncryptionProgressController._();

  final EncryptedStorageService _encryptedService = EncryptedStorageService();

  /// Notifier for UI binding - null when no operation is running
  final ValueNotifier<EncryptionProgress?> progressNotifier = ValueNotifier(null);

  /// Whether an operation is currently running
  bool get isRunning => progressNotifier.value != null;

  /// Run encryption operation with progress tracking
  Future<MigrationResult> runEncryption(String callsign, String nsec) async {
    if (isRunning) {
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Another operation is already running',
      );
    }

    progressNotifier.value = const EncryptionProgress(
      filesProcessed: 0,
      totalFiles: 0,
      isEncrypting: true,
    );

    try {
      final result = await _encryptedService.migrateToEncrypted(
        callsign,
        nsec,
        onProgress: _updateProgress,
      );
      return result;
    } finally {
      progressNotifier.value = null;
    }
  }

  /// Run decryption operation with progress tracking
  Future<MigrationResult> runDecryption(String callsign, String nsec) async {
    if (isRunning) {
      return MigrationResult(
        success: false,
        filesProcessed: 0,
        error: 'Another operation is already running',
      );
    }

    progressNotifier.value = const EncryptionProgress(
      filesProcessed: 0,
      totalFiles: 0,
      isEncrypting: false,
    );

    try {
      final result = await _encryptedService.migrateToFolders(
        callsign,
        nsec,
        onProgress: _updateProgress,
      );
      return result;
    } finally {
      progressNotifier.value = null;
    }
  }

  void _updateProgress(int filesProcessed, int totalFiles, String? currentFile) {
    final current = progressNotifier.value;
    if (current != null) {
      progressNotifier.value = EncryptionProgress(
        filesProcessed: filesProcessed,
        totalFiles: totalFiles,
        currentFile: currentFile,
        isEncrypting: current.isEncrypting,
      );
    }
  }
}
