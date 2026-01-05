/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Manages Console VM files download and storage.
 * VM files are cached by station servers and downloaded by clients.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'log_service.dart';
import 'station_service.dart';
import 'storage_config.dart';

/// VM file manifest entry
class VmFileInfo {
  final String name;
  final int size;
  final String sha256;

  VmFileInfo({
    required this.name,
    required this.size,
    required this.sha256,
  });

  factory VmFileInfo.fromJson(Map<String, dynamic> json) {
    return VmFileInfo(
      name: json['name'] as String,
      size: json['size'] as int,
      sha256: json['sha256'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'sha256': sha256,
      };
}

/// VM manifest with version and file list
class VmManifest {
  final String version;
  final DateTime updated;
  final List<VmFileInfo> files;

  VmManifest({
    required this.version,
    required this.updated,
    required this.files,
  });

  factory VmManifest.fromJson(Map<String, dynamic> json) {
    return VmManifest(
      version: json['version'] as String? ?? '1.0.0',
      updated: DateTime.tryParse(json['updated'] as String? ?? '') ?? DateTime.now(),
      files: (json['files'] as List<dynamic>?)
              ?.map((f) => VmFileInfo.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'updated': updated.toIso8601String(),
        'files': files.map((f) => f.toJson()).toList(),
      };
}

/// Manages Console VM file downloads
class ConsoleVmManager {
  static final ConsoleVmManager _instance = ConsoleVmManager._internal();
  factory ConsoleVmManager() => _instance;
  ConsoleVmManager._internal();

  /// Directory for storing VM files
  String? _vmPath;

  /// Cached manifest
  VmManifest? _manifest;

  /// Active downloads (filename -> progress)
  final Map<String, double> _activeDownloads = {};

  /// Download state controller
  final StreamController<String> _downloadStateController =
      StreamController<String>.broadcast();

  /// Stream of filenames when their download state changes
  Stream<String> get downloadStateChanges => _downloadStateController.stream;

  /// Required VM files for Alpine x86
  static const List<String> requiredFiles = [
    'jslinux.js',
    'term.js',
    'kernel-x86.bin',
    'alpine-x86.cfg',
    'alpine-x86-rootfs.tar.gz',
  ];

  /// Initialize the manager
  Future<void> initialize() async {
    final storageConfig = StorageConfig();
    if (!storageConfig.isInitialized) {
      await storageConfig.init();
    }

    _vmPath = p.join(storageConfig.baseDir, 'console', 'vm');

    // Create directory if it doesn't exist
    final dir = Directory(_vmPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    LogService().log('ConsoleVmManager: Initialized at $_vmPath');
  }

  /// Get path to VM files directory
  Future<String> get vmPath async {
    if (_vmPath == null) {
      await initialize();
    }
    return _vmPath!;
  }

  /// Get path to a specific VM file
  String getVmFilePath(String filename) {
    if (_vmPath == null) {
      throw StateError('ConsoleVmManager not initialized');
    }
    return p.join(_vmPath!, filename);
  }

  /// Check if all required VM files are present
  Future<bool> ensureVmReady() async {
    await initialize();

    for (final filename in requiredFiles) {
      final file = File(getVmFilePath(filename));
      if (!await file.exists()) {
        LogService().log('ConsoleVmManager: Missing $filename, downloading...');
        final success = await downloadVmFiles();
        return success;
      }
    }

    return true;
  }

  /// Check if a specific file is downloaded
  Future<bool> isFileDownloaded(String filename) async {
    await initialize();
    final file = File(getVmFilePath(filename));
    return await file.exists();
  }

  /// Check if a file is currently downloading
  bool isDownloading(String filename) => _activeDownloads.containsKey(filename);

  /// Get download progress (0.0 - 1.0) for a file
  double getDownloadProgress(String filename) {
    return _activeDownloads[filename] ?? 0.0;
  }

  /// Get station URL for VM file downloads (with proper validation)
  String? _getStationUrl() {
    final station = StationService().getPreferredStation();

    // Check both null AND empty string (station can have empty url)
    if (station == null || station.url.isEmpty) {
      LogService().log('ConsoleVmManager: No valid station URL available');
      return null;
    }

    // Convert WebSocket URL to HTTP/HTTPS
    var stationUrl = station.url;
    if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    } else if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    }

    // Remove trailing slash if present
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }

    return stationUrl;
  }

  /// Fetch manifest from station
  Future<VmManifest?> fetchManifest() async {
    final stationUrl = _getStationUrl();
    if (stationUrl == null) {
      LogService().log('ConsoleVmManager: No station available for manifest');
      return null;
    }
    LogService().log('ConsoleVmManager: Fetching manifest from $stationUrl');

    try {
      final url = '$stationUrl/console/vm/manifest.json';
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _manifest = VmManifest.fromJson(json);
        return _manifest;
      } else {
        LogService().log(
            'ConsoleVmManager: Failed to fetch manifest: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      LogService().log('ConsoleVmManager: Error fetching manifest: $e');
      return null;
    }
  }

  /// Download all required VM files from station
  Future<bool> downloadVmFiles() async {
    await initialize();

    final manifest = await fetchManifest();
    if (manifest == null) {
      LogService().log('ConsoleVmManager: Cannot download without manifest');
      return false;
    }

    final stationUrl = _getStationUrl();
    if (stationUrl == null) {
      LogService().log('ConsoleVmManager: No station available for download');
      return false;
    }
    LogService().log('ConsoleVmManager: Downloading VM files from $stationUrl');

    bool allSuccess = true;

    for (final fileInfo in manifest.files) {
      // Skip if already downloaded and verified
      if (await _isFileValid(fileInfo)) {
        LogService().log('ConsoleVmManager: ${fileInfo.name} already valid, skipping');
        continue;
      }

      final success = await _downloadFile(stationUrl, fileInfo);
      if (!success) {
        allSuccess = false;
      }
    }

    return allSuccess;
  }

  /// Check if a file exists and matches expected hash
  Future<bool> _isFileValid(VmFileInfo fileInfo) async {
    final file = File(getVmFilePath(fileInfo.name));
    if (!await file.exists()) return false;

    // Check size
    final actualSize = await file.length();
    if (actualSize != fileInfo.size) return false;

    // Optionally verify hash (expensive for large files)
    if (fileInfo.sha256.isNotEmpty && fileInfo.size < 10 * 1024 * 1024) {
      // Only hash files < 10MB
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      if (hash != fileInfo.sha256) return false;
    }

    return true;
  }

  /// Download a single file with progress tracking
  Future<bool> _downloadFile(String stationUrl, VmFileInfo fileInfo) async {
    final url = '$stationUrl/console/vm/${fileInfo.name}';
    final localPath = getVmFilePath(fileInfo.name);

    LogService().log('ConsoleVmManager: Downloading ${fileInfo.name}');
    _activeDownloads[fileInfo.name] = 0.0;
    _downloadStateController.add(fileInfo.name);

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send().timeout(
            const Duration(minutes: 30),
          );

      if (response.statusCode != 200) {
        LogService().log(
            'ConsoleVmManager: Download failed: ${response.statusCode}');
        _activeDownloads.remove(fileInfo.name);
        _downloadStateController.add(fileInfo.name);
        return false;
      }

      final file = File(localPath);
      final sink = file.openWrite();
      int downloaded = 0;
      final total = response.contentLength ?? fileInfo.size;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        _activeDownloads[fileInfo.name] = downloaded / total;
        _downloadStateController.add(fileInfo.name);
      }

      await sink.close();

      _activeDownloads.remove(fileInfo.name);
      _downloadStateController.add(fileInfo.name);

      LogService().log('ConsoleVmManager: Downloaded ${fileInfo.name}');
      return true;
    } catch (e) {
      LogService().log('ConsoleVmManager: Download error: $e');
      _activeDownloads.remove(fileInfo.name);
      _downloadStateController.add(fileInfo.name);
      return false;
    }
  }

  /// Check for updates by comparing manifest versions
  Future<bool> hasUpdates() async {
    await initialize();

    // Load local manifest if exists
    final localManifestFile = File(getVmFilePath('manifest.json'));
    VmManifest? localManifest;
    if (await localManifestFile.exists()) {
      try {
        final content = await localManifestFile.readAsString();
        localManifest = VmManifest.fromJson(jsonDecode(content));
      } catch (e) {
        // Ignore parse errors
      }
    }

    // Fetch remote manifest
    final remoteManifest = await fetchManifest();
    if (remoteManifest == null) return false;

    // Compare versions
    if (localManifest == null) return true;
    return remoteManifest.version != localManifest.version ||
        remoteManifest.updated.isAfter(localManifest.updated);
  }

  /// Save manifest locally after successful download
  Future<void> saveManifest() async {
    if (_manifest == null) return;

    final file = File(getVmFilePath('manifest.json'));
    await file.writeAsString(jsonEncode(_manifest!.toJson()));
  }

  /// Get total size of all VM files
  int get totalSize {
    if (_manifest == null) return 0;
    return _manifest!.files.fold(0, (sum, f) => sum + f.size);
  }

  /// Dispose resources
  void dispose() {
    _downloadStateController.close();
  }
}
