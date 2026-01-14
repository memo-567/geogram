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
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  VmFileInfo({required this.name, required this.size, required this.sha256});

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
      updated:
          DateTime.tryParse(json['updated'] as String? ?? '') ?? DateTime.now(),
      files:
          (json['files'] as List<dynamic>?)
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

  /// Directory for storing emulator binaries (e.g., Android QEMU)
  String? _emuPath;

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
    'x86emu-wasm.js',
    'x86emu-wasm.wasm',
    'kernel-x86.bin',
    'alpine-x86.cfg',
    'alpine-x86-rootfs.cpio.gz',
    'alpine-x86-rootfs.tar.gz',
  ];

  /// Fallback source for emulator binaries (when station manifest is missing entries)
  static const String _fallbackBaseUrl = 'https://bellard.org/jslinux';

  /// Optional Android QEMU archive (downloaded when running natively on Android)
  static const String androidQemuArchive = 'qemu-android-aarch64.tar.gz';

  /// Binary name inside the Android QEMU archive
  static const String androidQemuBinary = 'qemu-system-x86_64';

  /// Optional files that shouldn't block the console from loading
  static const Set<String> _optionalFiles = {androidQemuArchive};

  /// Pre-defined file metadata for fallback downloads
  static const Map<String, _FallbackFile> _fallbackFiles = {
    'jslinux.js': _FallbackFile(
      size: 19916,
      sha256: '51899d47b3d70dd1f353448d9a543f7d8c5e0f8a7a237d55ed6e7e358c97a7dc',
      baseUrl: _fallbackBaseUrl,
    ),
    'term.js': _FallbackFile(
      size: 44481,
      sha256: '099b7bfbee0d22461893a24b5801d90ad971ca04c607fc8cf3cc0346750b4b9f',
      baseUrl: _fallbackBaseUrl,
    ),
    'x86emu-wasm.js': _FallbackFile(
      size: 66395,
      sha256: 'f9de7279cf69102c6f317c67bacde4dbbedac91771819a86df09692b1c39a5db',
      baseUrl: _fallbackBaseUrl,
    ),
    'x86emu-wasm.wasm': _FallbackFile(
      size: 518190,
      sha256: '636d65d3ab45457356dcea3a3c0166123f9cb61d7b6521714c06cd8ed992b1ba',
      baseUrl: _fallbackBaseUrl,
    ),
    'kernel-x86.bin': _FallbackFile(
      size: 4969920,
      sha256: '4c9c95eed718c0e1c78525a22f89adb3ab028a2ade70f1900f6f326de4bc9ae4',
      baseUrl: _fallbackBaseUrl,
    ),
    'alpine-x86.cfg': _FallbackFile(
      size: 305,
      sha256: 'e034273b72c4b1fb728e6a7846429f03653e3e774527624d0510451789294ce6',
      baseUrl: _fallbackBaseUrl,
    ),
    'alpine-x86-rootfs.cpio.gz': _FallbackFile(
      size: 5430398,
      sha256: 'e8bbf890fcfee4f2b6fba78bf50435bbfc303f0b89837c1eb7bd04e26224b6bb',
      baseUrl: 'https://p2p.radio/console/vm',
    ),
    'alpine-x86-rootfs.tar.gz': _FallbackFile(
      size: 2719349,
      sha256: 'f06ae2ed0b5f52457a9762ddfcd067f559d35f92b83b4d0a294e3001e5070a62',
      baseUrl: _fallbackBaseUrl,
      urlOverride:
          'https://dl-cdn.alpinelinux.org/alpine/v3.12/releases/x86/alpine-minirootfs-3.12.0-x86.tar.gz',
    ),
    androidQemuArchive: _FallbackFile(
      size: 13009603,
      sha256: '8fe750754687c4b4b13f25c9de68e5cf703665d8715b7e79567207fca91ae47b',
      baseUrl: 'https://p2p.radio/console/vm',
    ),
  };

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

    _emuPath = p.join(storageConfig.baseDir, 'console', 'emu');
    final emuDir = Directory(_emuPath!);
    if (!await emuDir.exists()) {
      await emuDir.create(recursive: true);
    }

    LogService().log('ConsoleVmManager: Initialized at $_vmPath (emu: $_emuPath)');
  }

  /// Get path to VM files directory
  Future<String> get vmPath async {
    if (_vmPath == null) {
      await initialize();
    }
    return _vmPath!;
  }

  /// Get path to emulator files directory
  Future<String> get emuPath async {
    if (_emuPath == null) {
      await initialize();
    }
    return _emuPath!;
  }

  /// Get path to a specific VM file
  String getVmFilePath(String filename) {
    if (_vmPath == null) {
      throw StateError('ConsoleVmManager not initialized');
    }
    return p.join(_vmPath!, filename);
  }

  /// Check if all required VM files are present
  Future<bool> ensureVmReady({bool? includeRootfsTar}) async {
    await initialize();

    final needsRootfsTar = includeRootfsTar ?? _shouldIncludeRootfsTar();
    final files = requiredFilesForPlatform(includeRootfsTar: needsRootfsTar);

    for (final filename in files) {
      final file = File(getVmFilePath(filename));
      if (!await file.exists()) {
        LogService().log('ConsoleVmManager: Missing $filename, downloading...');
        final success = await downloadVmFiles(
          includeRootfsTar: needsRootfsTar,
        );
        return success;
      }
    }

    return true;
  }

  /// Get required files for the current platform (optionally overriding tar usage)
  List<String> requiredFilesForPlatform({bool? includeRootfsTar}) {
    final needsRootfsTar = includeRootfsTar ?? _shouldIncludeRootfsTar();
    return _requiredFiles(includeRootfsTar: needsRootfsTar);
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

  /// Ensure the Alpine rootfs tarball is extracted for offline 9p usage.
  /// Returns the rootfs directory path when successful.
  Future<String?> ensureRootfsExtracted() async {
    await initialize();

    final rootfsDir = p.join(_vmPath!, 'rootfs');
    final markerFile = File(p.join(_vmPath!, '.rootfs_extracted'));
    final tarballPath = getVmFilePath('alpine-x86-rootfs.tar.gz');

    // Reuse existing extraction if present
    if (await markerFile.exists() && await Directory(rootfsDir).exists()) {
      return rootfsDir;
    }

    if (!await File(tarballPath).exists()) {
      LogService().log(
        'ConsoleVmManager: rootfs tarball missing at $tarballPath',
      );
      return null;
    }

    try {
      LogService().log(
        'ConsoleVmManager: Extracting rootfs for offline use...',
      );
      final bytes = await File(tarballPath).readAsBytes();
      final archive = TarDecoder().decodeBytes(
        GZipDecoder().decodeBytes(bytes),
      );

      for (final file in archive) {
        final destPath = p.join(rootfsDir, file.name);
        if (file.isFile) {
          final outFile = File(destPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(destPath).create(recursive: true);
        }
      }

      await markerFile.writeAsString(DateTime.now().toIso8601String());
      LogService().log('ConsoleVmManager: Rootfs extracted to $rootfsDir');
      return rootfsDir;
    } catch (e) {
      LogService().log('ConsoleVmManager: Failed to extract rootfs: $e');
      return null;
    }
  }

  /// Ensure an Android-ready QEMU binary is available locally.
  ///
  /// Returns the executable path when available, otherwise null.
  Future<String?> ensureAndroidQemuBinary() async {
    if (!Platform.isAndroid) return null;
    await initialize();

    final emuDir = _emuPath!;
    final binaryPath = p.join(emuDir, androidQemuBinary);
    final archivePath = p.join(emuDir, androidQemuArchive);

    // Reuse existing binary if already present
    if (await File(binaryPath).exists()) {
      return binaryPath;
    }

    final stationUrl = _getStationUrl();
    final url = '$stationUrl/console/emu/$androidQemuArchive';
    LogService().log('ConsoleVmManager: Downloading Android QEMU from $url');

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send().timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        LogService().log(
          'ConsoleVmManager: Failed to download Android QEMU (status ${response.statusCode})',
        );
        return null;
      }

      final sink = File(archivePath).openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      final extracted = await _extractTarGz(
        archivePath: archivePath,
        destinationDir: emuDir,
      );
      if (!extracted) {
        return null;
      }

      try {
        await Process.run('chmod', ['755', binaryPath]);
      } catch (e) {
        LogService().log('ConsoleVmManager: chmod failed for QEMU binary: $e');
      }

      if (await File(binaryPath).exists()) {
        LogService().log('ConsoleVmManager: Android QEMU ready at $binaryPath');
        return binaryPath;
      }
    } catch (e) {
      LogService().log('ConsoleVmManager: Error downloading Android QEMU: $e');
    }

    return null;
  }

  /// Default station URL for VM file downloads
  static const String _defaultStationUrl = 'https://p2p.radio';

  /// Get station URL for VM file downloads (with fallback to default).
  ///
  /// IMPORTANT: Station URLs are stored as WebSocket URLs (wss://host or ws://host)
  /// but we need HTTP/HTTPS URLs to download files via HTTP requests.
  /// This method MUST convert ws:// -> http:// and wss:// -> https://
  String _getStationUrl() {
    final station = StationService().getPreferredStation();

    // Use default station if no valid station URL
    if (station == null || station.url.isEmpty) {
      LogService().log(
        'ConsoleVmManager: Using default station URL: $_defaultStationUrl',
      );
      return _defaultStationUrl;
    }

    // CRITICAL: Convert WebSocket URL to HTTP/HTTPS for file downloads
    // Station URLs are WebSocket format but HTTP requests need http(s):// URLs
    var stationUrl = station.url;
    if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    } else if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    }

    // Remove trailing slash if present
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }

    LogService().log(
      'ConsoleVmManager: Station URL converted (ws: ${station.url} -> http: $stationUrl)',
    );
    return stationUrl;
  }

  /// Fetch manifest from station
  Future<VmManifest?> fetchManifest() async {
    final stationUrl = _getStationUrl();
    LogService().log('ConsoleVmManager: Fetching manifest from $stationUrl');

    try {
      final url = '$stationUrl/console/vm/manifest.json';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _manifest = VmManifest.fromJson(json);
        return _manifest;
      } else {
        LogService().log(
          'ConsoleVmManager: Failed to fetch manifest: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      LogService().log('ConsoleVmManager: Error fetching manifest: $e');
      return null;
    }
  }

  /// Download all required VM files from station
  Future<bool> downloadVmFiles({
    bool? includeRootfsTar,
    bool? includeAndroidQemu,
  }) async {
    await initialize();

    final needsRootfsTar = includeRootfsTar ?? _shouldIncludeRootfsTar();
    final wantsAndroidQemu =
        includeAndroidQemu ?? _shouldIncludeAndroidQemu();

    final manifest = await fetchManifest();
    if (manifest == null) {
      LogService().log(
        'ConsoleVmManager: Manifest unavailable, will use fallback sources where possible',
      );
    }

    final stationUrl = _getStationUrl();
    LogService().log('ConsoleVmManager: Downloading VM files from $stationUrl');

    final List<_DownloadTarget> targets = buildDownloadTargets(
      manifest: manifest,
      stationUrl: stationUrl,
      includeRootfsTar: needsRootfsTar,
      includeAndroidQemu: wantsAndroidQemu,
    );

    bool allSuccess = true;

    for (final target in targets) {
      // Skip if already downloaded and verified
      if (await _isFileValid(target.fileInfo)) {
        LogService().log(
          'ConsoleVmManager: ${target.fileInfo.name} already valid, skipping',
        );
        continue;
      }

      var success = await _downloadFile(
        target.baseUrl,
        target.fileInfo,
        overrideUrl: target.overrideUrl,
      );

      // Retry with fallback host if primary station fails and a fallback exists
      if (!success &&
          !target.isFallback &&
          _fallbackFiles.containsKey(target.fileInfo.name)) {
        LogService().log(
          'ConsoleVmManager: Retrying ${target.fileInfo.name} from fallback host',
        );
        final fallbackInfo = _fallbackFiles[target.fileInfo.name]!;
        success = await _downloadFile(
          fallbackInfo.baseUrl,
          VmFileInfo(
            name: target.fileInfo.name,
            size: fallbackInfo.size,
            sha256: fallbackInfo.sha256,
          ),
          overrideUrl: fallbackInfo.urlOverride,
        );
      }

      if (!success) {
        // Optional artifacts (e.g., Android QEMU experiments) should not block the console
        if (_optionalFiles.contains(target.fileInfo.name)) {
          LogService().log(
            'ConsoleVmManager: Optional download failed for ${target.fileInfo.name}, continuing',
          );
        } else {
          allSuccess = false;
        }
      }
    }

    return allSuccess;
  }

  /// Check if a file exists and matches expected hash
  Future<bool> _isFileValid(VmFileInfo fileInfo) async {
    final file = File(getVmFilePath(fileInfo.name));
    if (!await file.exists()) return false;

    // Check size (skip if manifest doesn't specify a meaningful size)
    final actualSize = await file.length();
    if (fileInfo.size > 0 && actualSize != fileInfo.size) return false;

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
  Future<bool> _downloadFile(
    String baseUrl,
    VmFileInfo fileInfo, {
    String? overrideUrl,
  }) async {
    final url = overrideUrl ??
        (baseUrl.endsWith('/')
            ? '$baseUrl${fileInfo.name}'
            : '$baseUrl/${fileInfo.name}');
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
          'ConsoleVmManager: Download failed: ${response.statusCode}',
        );
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

      // Normalize gzipped WASM files to raw bytes so instantiateStreaming works in WebView
      if (fileInfo.name.endsWith('.wasm')) {
        try {
          final bytes = await file.readAsBytes();
          final isGzip =
              bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
          if (isGzip) {
            final decompressed = gzip.decode(bytes);
            await file.writeAsBytes(decompressed, flush: true);
            LogService().log(
              'ConsoleVmManager: Decompressed ${fileInfo.name} (gzip -> wasm)',
            );
          }
        } catch (e) {
          LogService().log(
            'ConsoleVmManager: Failed to decompress ${fileInfo.name}: $e',
          );
        }
      }

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

  /// Extract a .tar.gz archive into [destinationDir].
  Future<bool> _extractTarGz({
    required String archivePath,
    required String destinationDir,
  }) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      return false;
    }

    try {
      final bytes = await archiveFile.readAsBytes();
      final archive =
          TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));

      for (final file in archive) {
        final destPath = p.normalize(p.join(destinationDir, file.name));

        // Prevent directory traversal
        if (!destPath.startsWith(p.normalize(destinationDir))) {
          LogService().log(
            'ConsoleVmManager: Skipping suspicious path ${file.name}',
          );
          continue;
        }

        if (file.isFile) {
          final outFile = File(destPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(destPath).create(recursive: true);
        }
      }

      return true;
    } catch (e) {
      LogService().log('ConsoleVmManager: Failed to extract $archivePath: $e');
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

  /// Internal helper describing a download target and its origin
  /// [isFallback] is true when the file is sourced from a known upstream host
  /// because the station manifest didn't include it.
  static List<_DownloadTarget> buildDownloadTargets({
    VmManifest? manifest,
    required String stationUrl,
    bool includeRootfsTar = true,
    bool includeAndroidQemu = false,
  }) {
    final List<_DownloadTarget> targets = [];
    final stationBase = '$stationUrl/console/vm';

    if (manifest != null) {
      for (final fileInfo in manifest.files) {
        if (!includeRootfsTar && fileInfo.name == 'alpine-x86-rootfs.tar.gz') {
          continue;
        }
        if (!includeAndroidQemu && fileInfo.name == androidQemuArchive) {
          continue;
        }
        targets.add(
          _DownloadTarget(
            fileInfo: fileInfo,
            baseUrl: stationBase,
            isFallback: false,
          ),
        );
      }
    }

    for (final entry in _fallbackFiles.entries) {
      if (!includeRootfsTar && entry.key == 'alpine-x86-rootfs.tar.gz') {
        continue;
      }
      if (!includeAndroidQemu && entry.key == androidQemuArchive) {
        continue;
      }

      final existsInTargets = targets.any(
        (t) => t.fileInfo.name == entry.key,
      );
      if (!existsInTargets) {
        final info = entry.value;
        targets.add(
          _DownloadTarget(
            fileInfo: VmFileInfo(
              name: entry.key,
              size: info.size,
              sha256: info.sha256,
            ),
            baseUrl: info.baseUrl,
            isFallback: true,
            overrideUrl: info.urlOverride,
          ),
        );
      }
    }

    return targets;
  }

  /// Whether the tarball is needed for the current platform (native TinyEMU/QEMU)
  bool _shouldIncludeRootfsTar() {
    if (kIsWeb) return false;
    // Native console currently only runs on Linux; WebView/mobile path uses initrd only
    return Platform.isLinux;
  }

  /// Whether we should attempt to fetch the Android QEMU bundle (disabled by default)
  bool _shouldIncludeAndroidQemu() {
    return false;
  }

  List<String> _requiredFiles({required bool includeRootfsTar}) {
    final files = List<String>.from(requiredFiles);
    if (!includeRootfsTar) {
      files.remove('alpine-x86-rootfs.tar.gz');
    }
    return files;
  }

  /// Expose default includeRootfsTar decision for UI callers
  bool shouldIncludeRootfsTar() => _shouldIncludeRootfsTar();

  /// Dispose resources
  void dispose() {
    _downloadStateController.close();
  }
}

class _DownloadTarget {
  final VmFileInfo fileInfo;
  final String baseUrl;
  final bool isFallback;
  final String? overrideUrl;

  const _DownloadTarget({
    required this.fileInfo,
    required this.baseUrl,
    required this.isFallback,
    this.overrideUrl,
  });
}

class _FallbackFile {
  final int size;
  final String sha256;
  final String baseUrl;
  final String? urlOverride;

  const _FallbackFile({
    required this.size,
    required this.sha256,
    required this.baseUrl,
    this.urlOverride,
  });
}
