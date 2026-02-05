/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/qr_code.dart';
import 'log_service.dart';
import 'profile_storage.dart';

/// Service for managing QR codes collection
class QrCodeService {
  static final QrCodeService _instance = QrCodeService._internal();
  factory QrCodeService() => _instance;
  QrCodeService._internal();

  /// Profile storage for file operations (encrypted or filesystem)
  late ProfileStorage _storage;

  String? _appPath;

  /// Get the current collection path
  String? get appPath => _appPath;

  /// Whether using encrypted storage
  bool get useEncryptedStorage => _storage.isEncrypted;

  /// Set the profile storage for file operations
  void setStorage(ProfileStorage storage) {
    _storage = storage;
  }

  /// Initialize QR code service for a collection
  Future<void> initializeApp(String appPath) async {
    LogService().log('QrCodeService: Initializing with collection path: $appPath');
    _appPath = appPath;

    // Create directory structure
    await _storage.createDirectory('');
    await _storage.createDirectory('created');
    await _storage.createDirectory('scanned');
    await _storage.createDirectory('extra');

    LogService().log('QrCodeService: Initialized with storage abstraction');
  }

  /// Generate timestamp-based filename
  String _generateTimestampFilename() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.json';
  }

  /// Sanitize name for use as filename
  String _sanitizeFilename(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Get relative path from absolute path
  String _getRelativePath(String fullPath) {
    if (_appPath == null) return fullPath;
    if (fullPath.startsWith(_appPath!)) {
      final rel = fullPath.substring(_appPath!.length);
      return rel.startsWith('/') ? rel.substring(1) : rel;
    }
    return fullPath;
  }

  /// Save a QR code
  /// Returns the saved QrCode with updated filePath
  Future<QrCode> saveQrCode(QrCode code, {String? customName, String? subfolder}) async {
    if (_appPath == null) {
      throw StateError('QrCodeService not initialized');
    }

    // Determine base directory based on source
    final baseDir = code.source == QrCodeSource.created ? 'created' : 'scanned';

    // Build path
    String relativePath = baseDir;
    if (subfolder != null && subfolder.isNotEmpty) {
      relativePath = '$baseDir/$subfolder';
      // Ensure subfolder exists
      await _storage.createDirectory(relativePath);
    }

    // Generate filename
    String filename;
    if (customName != null && customName.isNotEmpty) {
      filename = '${_sanitizeFilename(customName)}.json';
    } else {
      filename = _generateTimestampFilename();
    }

    // Check for existing file and add suffix if needed
    String finalPath = '$relativePath/$filename';
    int counter = 1;
    while (await _storage.exists(finalPath)) {
      final baseName = filename.replaceAll('.json', '');
      finalPath = '$relativePath/${baseName}_$counter.json';
      counter++;
    }

    // Update code with category if using subfolder
    final updatedCode = code.copyWith(
      category: subfolder,
      filePath: _storage.getAbsolutePath(finalPath),
    );

    // Write JSON file
    final jsonContent = updatedCode.toJsonString();
    await _storage.writeString(finalPath, jsonContent);

    LogService().log('QrCodeService: Saved QR code to $finalPath');

    return updatedCode;
  }

  /// Update an existing QR code
  Future<QrCode> updateQrCode(QrCode code) async {
    if (code.filePath == null) {
      throw ArgumentError('QrCode must have a filePath to update');
    }

    final relativePath = _getRelativePath(code.filePath!);
    final updatedCode = code.copyWith(modifiedAt: DateTime.now());

    final jsonContent = updatedCode.toJsonString();
    await _storage.writeString(relativePath, jsonContent);

    LogService().log('QrCodeService: Updated QR code at $relativePath');

    return updatedCode;
  }

  /// Delete a QR code
  Future<void> deleteQrCode(String filePath) async {
    final relativePath = _getRelativePath(filePath);
    await _storage.delete(relativePath);
    LogService().log('QrCodeService: Deleted QR code at $relativePath');
  }

  /// Load a single QR code by file path
  Future<QrCode?> loadQrCode(String filePath) async {
    try {
      final relativePath = _getRelativePath(filePath);
      final content = await _storage.readString(relativePath);
      if (content == null) return null;

      return QrCode.fromJsonString(content, filePath: filePath);
    } catch (e) {
      LogService().log('QrCodeService: Error loading QR code from $filePath: $e');
      return null;
    }
  }

  /// Load all QR codes from a directory (created or scanned)
  Future<List<QrCode>> loadQrCodes({
    required QrCodeSource source,
    String? subfolder,
  }) async {
    if (_appPath == null) return [];

    final codes = <QrCode>[];
    final baseDir = source == QrCodeSource.created ? 'created' : 'scanned';
    final relativePath = subfolder != null ? '$baseDir/$subfolder' : baseDir;

    await _loadCodesRecursively(relativePath, codes);

    // Sort by creation date, newest first
    codes.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return codes;
  }

  /// Recursively load codes from directory
  Future<void> _loadCodesRecursively(String relativePath, List<QrCode> codes) async {
    try {
      final entries = await _storage.listDirectory(relativePath);

      for (final entry in entries) {
        if (entry.isDirectory) {
          // Recurse into subdirectories
          await _loadCodesRecursively(entry.path, codes);
        } else if (entry.name.endsWith('.json') && !entry.name.startsWith('.')) {
          try {
            final content = await _storage.readString(entry.path);
            if (content != null) {
              final fullPath = _storage.getAbsolutePath(entry.path);
              final code = QrCode.fromJsonString(content, filePath: fullPath);
              codes.add(code);
            }
          } catch (e) {
            LogService().log('QrCodeService: Error loading ${entry.path}: $e');
          }
        }
      }
    } catch (e) {
      LogService().log('QrCodeService: Error listing directory $relativePath: $e');
    }
  }

  /// Load QR code summaries for fast listing
  Future<List<QrCodeSummary>> loadSummaries({QrCodeSource? source}) async {
    final summaries = <QrCodeSummary>[];

    if (source == null || source == QrCodeSource.created) {
      final createdCodes = await loadQrCodes(source: QrCodeSource.created);
      summaries.addAll(createdCodes.map(QrCodeSummary.fromQrCode));
    }

    if (source == null || source == QrCodeSource.scanned) {
      final scannedCodes = await loadQrCodes(source: QrCodeSource.scanned);
      summaries.addAll(scannedCodes.map(QrCodeSummary.fromQrCode));
    }

    // Sort by creation date, newest first
    summaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return summaries;
  }

  /// Get list of subfolders in a source directory
  Future<List<String>> getSubfolders(QrCodeSource source) async {
    if (_appPath == null) return [];

    final folders = <String>[];
    final baseDir = source == QrCodeSource.created ? 'created' : 'scanned';

    try {
      final entries = await _storage.listDirectory(baseDir);
      for (final entry in entries) {
        if (entry.isDirectory) {
          folders.add(entry.name);
        }
      }
    } catch (e) {
      LogService().log('QrCodeService: Error listing subfolders in $baseDir: $e');
    }

    folders.sort();
    return folders;
  }

  /// Create a subfolder
  Future<void> createSubfolder(QrCodeSource source, String name) async {
    if (_appPath == null) {
      throw StateError('QrCodeService not initialized');
    }

    final baseDir = source == QrCodeSource.created ? 'created' : 'scanned';
    final safeName = _sanitizeFilename(name);
    final path = '$baseDir/$safeName';

    await _storage.createDirectory(path);
    LogService().log('QrCodeService: Created subfolder $path');
  }

  /// Move a QR code to a different subfolder
  Future<QrCode> moveQrCode(QrCode code, String? targetSubfolder) async {
    if (code.filePath == null) {
      throw ArgumentError('QrCode must have a filePath to move');
    }

    // Delete from current location
    await deleteQrCode(code.filePath!);

    // Save to new location
    return saveQrCode(
      code.copyWith(category: targetSubfolder),
      customName: _getFilenameWithoutExtension(code.filePath!),
      subfolder: targetSubfolder,
    );
  }

  /// Get filename without extension from path
  String _getFilenameWithoutExtension(String path) {
    final filename = path.split('/').last;
    final dotIndex = filename.lastIndexOf('.');
    return dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
  }

  /// Search QR codes by name, content, or tags
  Future<List<QrCode>> searchQrCodes(String query) async {
    if (_appPath == null) return [];

    final queryLower = query.toLowerCase();
    final results = <QrCode>[];

    // Search in both created and scanned
    for (final source in QrCodeSource.values) {
      final codes = await loadQrCodes(source: source);
      for (final code in codes) {
        if (_matchesSearch(code, queryLower)) {
          results.add(code);
        }
      }
    }

    // Sort by relevance (name match first, then by date)
    results.sort((a, b) {
      final aNameMatch = a.name.toLowerCase().contains(queryLower);
      final bNameMatch = b.name.toLowerCase().contains(queryLower);
      if (aNameMatch && !bNameMatch) return -1;
      if (!aNameMatch && bNameMatch) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return results;
  }

  /// Check if a code matches search query
  bool _matchesSearch(QrCode code, String queryLower) {
    if (code.name.toLowerCase().contains(queryLower)) return true;
    if (code.content.toLowerCase().contains(queryLower)) return true;
    if (code.notes?.toLowerCase().contains(queryLower) ?? false) return true;
    if (code.category?.toLowerCase().contains(queryLower) ?? false) return true;
    for (final tag in code.tags) {
      if (tag.toLowerCase().contains(queryLower)) return true;
    }
    return false;
  }

  /// Get count of codes by source
  Future<Map<QrCodeSource, int>> getCounts() async {
    final createdCodes = await loadQrCodes(source: QrCodeSource.created);
    final scannedCodes = await loadQrCodes(source: QrCodeSource.scanned);

    return {
      QrCodeSource.created: createdCodes.length,
      QrCodeSource.scanned: scannedCodes.length,
    };
  }
}
