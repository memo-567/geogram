/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:typed_data';

import 'profile_storage.dart' show StorageEntry;

/// Stub for encrypted storage service - used in CLI/pure Dart builds
/// where Flutter dependencies are not available.
class EncryptedStorageService {
  static final EncryptedStorageService _instance =
      EncryptedStorageService._internal();
  factory EncryptedStorageService() => _instance;
  EncryptedStorageService._internal();

  /// Encrypted storage is never available in CLI mode
  bool isEncryptedStorageEnabled(String callsign) => false;

  /// Stub - read file (returns null in CLI mode)
  Future<Uint8List?> readFile(String callsign, String nsec, String relativePath) async {
    return null;
  }

  /// Stub - write file (returns false in CLI mode)
  Future<bool> writeFile(String callsign, String nsec, String relativePath, Uint8List content) async {
    return false;
  }

  /// Stub - delete file (returns false in CLI mode)
  Future<bool> deleteFile(String callsign, String nsec, String relativePath) async {
    return false;
  }

  /// Stub - file exists (returns false in CLI mode)
  Future<bool> fileExists(String callsign, String nsec, String relativePath) async {
    return false;
  }

  /// Stub - list directory (returns null in CLI mode)
  Future<List<StorageEntry>?> listDirectory(
    String callsign,
    String nsec,
    String relativePath, {
    bool recursive = false,
  }) async {
    return null;
  }

  /// Stub - close archive (no-op in CLI mode)
  Future<void> closeArchive(String callsign) async {}

  /// Stub - close all archives (no-op in CLI mode)
  Future<void> closeAllArchives() async {}
}
