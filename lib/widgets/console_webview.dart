/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console widget for running Alpine Linux VM.
 * - Android: Native TinyEMU binary (no WebView)
 * - iOS/macOS: WebView with JSLinux (JavaScript x86 emulator)
 * - Linux: Native TinyEMU/QEMU with xterm terminal widget
 */

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io'
    if (dart.library.html) '../platform/io_stub.dart'
    show
        Platform,
        Process,
        Directory,
        File,
        HttpServer,
        InternetAddress,
        HttpRequest,
        HttpStatus,
        ContentType,
        gzip;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';
// Conditional imports for Linux-only packages (PTY/terminal)
import 'console_pty_stub.dart'
    if (dart.library.io) 'package:flutter_pty/flutter_pty.dart';
import 'console_terminal_stub.dart'
    if (dart.library.io) 'package:xterm/xterm.dart';
import '../models/console_session.dart';
import '../services/console_vm_manager.dart';
import '../services/log_service.dart';
import '../services/station_service.dart';
import '../services/storage_config.dart';

/// Callback for VM state changes
typedef ConsoleStateCallback = void Function(ConsoleSessionState state);

/// Callback for VM output messages
typedef ConsoleOutputCallback = void Function(String message);

/// Console widget that runs Alpine Linux VM
class ConsoleWebView extends StatefulWidget {
  final ConsoleSession session;
  final ConsoleStateCallback? onStateChanged;
  final ConsoleOutputCallback? onOutput;
  final VoidCallback? onReady;

  const ConsoleWebView({
    super.key,
    required this.session,
    this.onStateChanged,
    this.onOutput,
    this.onReady,
  });

  @override
  State<ConsoleWebView> createState() => ConsoleWebViewState();
}

class ConsoleWebViewState extends State<ConsoleWebView> {
  // WebView controller (iOS/macOS)
  WebViewController? _controller;

  // Linux native terminal
  Terminal? _terminal;
  Pty? _pty;
  Process? _qemuProcess;
  HttpServer? _localVmServer;

  bool _isReady = false;
  bool _isLoading = true;
  bool _platformSupported = false;
  bool _useNativeTerminal = false;
  bool _isAndroidNative = false;
  String? _platformError;

  /// Check if current platform supports Console VM
  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return true;
    if (Platform.isLinux) return true; // Native TinyEMU/QEMU support
    return false;
  }

  @override
  void initState() {
    super.initState();
    _checkPlatformAndInitialize();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    _pty?.kill();
    _qemuProcess?.kill();
    _localVmServer?.close(force: true);
    _localVmServer = null;
  }

  void _checkPlatformAndInitialize() {
    if (!isPlatformSupported) {
      String platformName = 'this platform';
      if (!kIsWeb && Platform.isWindows) platformName = 'Windows';
      if (kIsWeb) platformName = 'Web browser';

      setState(() {
        _platformSupported = false;
        _platformError =
            'Console VM is not yet supported on $platformName.\n\n'
            'Supported platforms: Android, iOS, macOS, Linux.';
        _isLoading = false;
      });
      LogService().log('Console: Platform not supported - $platformName');
      return;
    }

    _platformSupported = true;
    _useNativeTerminal = !kIsWeb && (Platform.isLinux || Platform.isAndroid);
    _isAndroidNative = !kIsWeb && Platform.isAndroid;

    if (_useNativeTerminal) {
      _initializeNativeTerminal();
    } else {
      _initializeWebView();
    }
  }

  /// Initialize native terminal (TinyEMU or QEMU)
  Future<void> _initializeNativeTerminal() async {
    LogService().log('Console: Initializing native terminal');

    try {
      // Create terminal emulator
      _terminal = Terminal(maxLines: 10000);

      // Check for emulator availability (TinyEMU preferred, QEMU fallback)
      final emulator = await _findEmulator();
      if (emulator == null) {
        setState(() {
          _platformError = _isAndroidNative
              ? 'No emulator found.\n\nThe bundled TinyEMU binary is missing from the Android build.'
              : 'No emulator found.\n\n'
                  'The bundled TinyEMU binary is missing.\n'
                  'Alternatively, install QEMU:\n'
                  'sudo apt install qemu-system-x86';
          _isLoading = false;
        });
        return;
      }

      // Ensure VM files are ready
      final vmManager = ConsoleVmManager();
      final ready = await vmManager.ensureVmReady();
      if (!ready) {
        setState(() {
          _platformError =
              'VM files not downloaded.\n'
              'Please check your station connection.';
          _isLoading = false;
        });
        return;
      }

      // Get paths to VM files
      final vmPath = await vmManager.vmPath;

      if (emulator.isTinyEmu) {
        // Prepare rootfs for TinyEMU 9p usage
        final rootfsDir = await vmManager.ensureRootfsExtracted();
        if (rootfsDir == null) {
          setState(() {
            _platformError = 'Failed to prepare VM filesystem.';
            _isLoading = false;
          });
          return;
        }
        LogService().log('Console: Rootfs ready at $rootfsDir');

        // Use TinyEMU with config file
        await _startTinyEmu(emulator.path, vmPath);
      } else {
        // Use QEMU with kernel and disk
        final kernelPath = '$vmPath/kernel-x86.bin';
        final rootfsPath = '$vmPath/alpine-x86-rootfs.tar.gz';

        // Create a disk image from the rootfs if needed
        final diskPath = await _prepareDiskImage(vmPath, rootfsPath);
        if (diskPath == null) {
          setState(() {
            _platformError = 'Failed to prepare VM disk image.';
            _isLoading = false;
          });
          return;
        }

        await _startQemu(emulator.path, kernelPath, diskPath);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReady = true;
        });
        widget.onReady?.call();
        widget.onStateChanged?.call(ConsoleSessionState.running);
      }
    } catch (e) {
      LogService().log('Console: Error initializing native terminal: $e');
      if (mounted) {
        setState(() {
          _platformError = 'Failed to initialize terminal: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Find emulator executable (bundled TinyEMU preferred, system QEMU as fallback)
  Future<({String path, bool isTinyEmu})?> _findEmulator() async {
    if (_isAndroidNative) {
      final temuPath = await _installBundledTemu();
      if (temuPath != null) {
        LogService().log('Console: Using bundled TinyEMU for Android at $temuPath');
        return (path: temuPath, isTinyEmu: true);
      }
      LogService().log('Console: Bundled TinyEMU for Android not found');
      return null;
    }

    // First, check for bundled TinyEMU relative to the executable
    final execPath = Platform.resolvedExecutable;
    final execDir = Directory(execPath).parent.path;
    final bundledTemu = '$execDir/bin/temu';

    if (await File(bundledTemu).exists()) {
      LogService().log('Console: Found bundled TinyEMU at $bundledTemu');
      return (path: bundledTemu, isTinyEmu: true);
    }

    // Check for system TinyEMU
    final temuPaths = ['/usr/bin/temu', '/usr/local/bin/temu'];

    for (final path in temuPaths) {
      if (await File(path).exists()) {
        LogService().log('Console: Found system TinyEMU at $path');
        return (path: path, isTinyEmu: true);
      }
    }

    // Fall back to QEMU
    final qemuPaths = [
      '/usr/bin/qemu-system-x86_64',
      '/usr/local/bin/qemu-system-x86_64',
      '/snap/bin/qemu-system-x86_64',
    ];

    for (final path in qemuPaths) {
      if (await File(path).exists()) {
        LogService().log('Console: Found system QEMU at $path');
        return (path: path, isTinyEmu: false);
      }
    }

    // Try which command for QEMU
    try {
      final result = await Process.run('which', ['qemu-system-x86_64']);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) {
          LogService().log('Console: Found QEMU via which: $path');
          return (path: path, isTinyEmu: false);
        }
      }
    } catch (_) {}

    LogService().log('Console: No emulator found');
    return null;
  }

  /// Install bundled TinyEMU binary for Android and return its path
  Future<String?> _installBundledTemu() async {
    const assetPath = 'android/tinyemu/arm64-v8a/temu';

    try {
      // Prefer packaged native library if present (installed with APK)
      final execDir = Directory(Platform.resolvedExecutable).parent.path;
      final libTemu = p.join(execDir, 'libtemu.so');
      if (await File(libTemu).exists()) {
        LogService().log('Console: Using TinyEMU from native lib dir: $libTemu');
        return libTemu;
      }

      final storage = StorageConfig();
      if (!storage.isInitialized) {
        await storage.init();
      }

      final emuDir = p.join(storage.baseDir, 'console', 'emu');
      await Directory(emuDir).create(recursive: true);
      final outputPath = p.join(emuDir, 'temu');

      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      final outFile = File(outputPath);
      final needsWrite =
          !(await outFile.exists()) || (await outFile.length()) != bytes.length;
      if (needsWrite) {
        await outFile.writeAsBytes(bytes, flush: true);
        LogService().log('Console: Installed TinyEMU asset to $outputPath');
      } else {
        LogService().log('Console: TinyEMU asset already present at $outputPath');
      }

      // Dart doesn't expose chmod directly; use process call to set exec bit
      try {
        await Process.run('chmod', ['755', outputPath]);
      } catch (e) {
        LogService().log('Console: Failed to chmod TinyEMU binary: $e');
      }
      return outputPath;
    } catch (e) {
      LogService().log('Console: Failed to install bundled TinyEMU: $e');
      return null;
    }
  }

  /// Prepare disk image from rootfs tarball
  Future<String?> _prepareDiskImage(String vmPath, String rootfsPath) async {
    final diskPath = '$vmPath/alpine-disk.qcow2';
    final diskFile = File(diskPath);

    // Check if disk already exists
    if (await diskFile.exists()) {
      LogService().log('Console: Using existing disk image');
      return diskPath;
    }

    LogService().log('Console: Creating disk image from rootfs...');

    try {
      // Create a qcow2 disk image (256MB should be enough for Alpine)
      var result = await Process.run('qemu-img', [
        'create',
        '-f',
        'qcow2',
        diskPath,
        '256M',
      ]);

      if (result.exitCode != 0) {
        LogService().log('Console: Failed to create disk: ${result.stderr}');
        return null;
      }

      LogService().log('Console: Disk image created at $diskPath');
      return diskPath;
    } catch (e) {
      LogService().log('Console: Error creating disk image: $e');
      return null;
    }
  }

  /// Prepare rootfs directory for TinyEMU 9p filesystem
  Future<String?> _prepareRootfs(String vmPath) async {
    try {
      final vmManager = ConsoleVmManager();
      final rootfsDir = await vmManager.ensureRootfsExtracted();
      if (rootfsDir != null) {
        LogService().log('Console: Rootfs ready at $rootfsDir');
      }
      return rootfsDir;
    } catch (e) {
      LogService().log('Console: Error preparing rootfs: $e');
      return null;
    }
  }

  /// Generate local TinyEMU config file
  Future<String?> _generateLocalConfig(String vmPath) async {
    final localConfigPath = '$vmPath/local-alpine-x86.cfg';
    final kernelPath = 'kernel-x86.bin'; // Relative to vmPath
    final rootfsDir = await _prepareRootfs(vmPath);

    if (rootfsDir == null) {
      return null;
    }

    final buffer = StringBuffer()
      ..writeln('{')
      ..writeln('    version: 1,')
      ..writeln('    machine: "pc",')
      ..writeln('    memory_size: ${widget.session.memory},')
      ..writeln('    kernel: "$kernelPath",')
      ..writeln(
        '    cmdline: "loglevel=3 console=hvc0 root=root rootfstype=9p rootflags=trans=virtio rw init=/bin/sh",',
      )
      ..writeln('    fs0: { file: "rootfs" },');

    if (widget.session.networkEnabled) {
      buffer.writeln('    eth0: { driver: "user" },');
    }

    buffer.writeln('}');

    final config = buffer.toString();

    try {
      await File(localConfigPath).writeAsString(config);
      LogService().log('Console: Generated local config at $localConfigPath');
      return localConfigPath;
    } catch (e) {
      LogService().log('Console: Error writing config: $e');
      return null;
    }
  }

  /// Start TinyEMU with PTY
  Future<void> _startTinyEmu(
    String temuPath,
    String vmPath,
  ) async {
    LogService().log('Console: Starting TinyEMU...');

    // Generate local config with proper paths (the downloaded config has URLs)
    final localConfig = await _generateLocalConfig(vmPath);
    if (localConfig == null) {
      if (mounted) {
        setState(() {
          _platformError = 'Failed to prepare VM filesystem.';
          _isLoading = false;
        });
      }
      return;
    }

    // TinyEMU takes a config file as argument
    final args = [localConfig];

    LogService().log('Console: TinyEMU command: $temuPath ${args.join(' ')}');

    if (_isAndroidNative) {
      await _startTinyEmuProcess(temuPath, args, vmPath);
      return;
    }

    // Create PTY and spawn TinyEMU
    _pty = Pty.start(
      temuPath,
      arguments: args,
      workingDirectory:
          vmPath, // Set working directory so relative paths in config work
      environment: Platform.environment,
    );

    // Connect PTY output to terminal
    _pty!.output.listen((data) {
      _terminal?.write(String.fromCharCodes(data));
    });

    // Connect terminal input to PTY
    _terminal?.onOutput = (data) {
      _pty?.write(const Utf8Encoder().convert(data));
    };

    _pty!.exitCode.then((code) {
      LogService().log('Console: TinyEMU exited with code $code');
      if (mounted) {
        widget.onStateChanged?.call(ConsoleSessionState.stopped);
      }
    });
  }

  /// Start TinyEMU on Android using a normal process (no PTY available)
  Future<void> _startTinyEmuProcess(
    String temuPath,
    List<String> args,
    String vmPath,
  ) async {
    final shellCmd = '$temuPath ${args.map((a) => '"${a.replaceAll('"', '\\"')}"').join(' ')}';

    try {
      final process = await Process.start('/system/bin/sh', ['-c', shellCmd],
          workingDirectory: vmPath, environment: Platform.environment);
      _qemuProcess = process;

      process.stdout.transform(utf8.decoder).listen((data) {
        _terminal?.write(data);
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        _terminal?.write(data);
      });

      _terminal?.onOutput = (data) {
        process.stdin.add(const Utf8Encoder().convert(data));
      };

      process.exitCode.then((code) {
        LogService().log('Console: TinyEMU exited with code $code');
        if (mounted) {
          widget.onStateChanged?.call(ConsoleSessionState.stopped);
        }
      });
    } catch (e) {
      LogService().log('Console: Failed to start TinyEMU process: $e\nCmd: $shellCmd');
      if (mounted) {
        setState(() {
          _platformError = 'Failed to start TinyEMU: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Start QEMU with PTY
  Future<void> _startQemu(
    String qemuPath,
    String kernelPath,
    String diskPath,
  ) async {
    LogService().log('Console: Starting QEMU...');

    // Build QEMU command line
    final args = [
      '-machine', 'pc',
      '-m', '${widget.session.memory}M',
      '-nographic', // Use serial console
      '-kernel', kernelPath,
      '-append', 'console=ttyS0 root=/dev/sda rw',
      '-drive', 'file=$diskPath,format=qcow2,if=ide',
    ];

    // Add network if enabled
    if (widget.session.networkEnabled) {
      args.addAll([
        '-netdev',
        'user,id=net0',
        '-device',
        'virtio-net-pci,netdev=net0',
      ]);
    }

    // Enable KVM if available
    if (await File('/dev/kvm').exists()) {
      args.addAll(['-enable-kvm', '-cpu', 'host']);
      LogService().log('Console: KVM acceleration enabled');
    }

    LogService().log('Console: QEMU args: ${args.join(' ')}');

    // Create PTY and spawn QEMU
    _pty = Pty.start(
      qemuPath,
      arguments: args,
      environment: Platform.environment,
    );

    // Connect PTY output to terminal
    _pty!.output.listen((data) {
      _terminal?.write(String.fromCharCodes(data));
    });

    // Connect terminal input to PTY
    _terminal?.onOutput = (data) {
      _pty?.write(const Utf8Encoder().convert(data));
    };

    _pty!.exitCode.then((code) {
      LogService().log('Console: QEMU exited with code $code');
      if (mounted) {
        widget.onStateChanged?.call(ConsoleSessionState.stopped);
      }
    });
  }

  /// Initialize WebView for mobile/macOS
  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'GeogramBridge',
        onMessageReceived: _handleJavaScriptMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
              _onPageLoaded();
            }
          },
          onWebResourceError: (error) {
            LogService().log('Console WebView error: ${error.description}');
          },
        ),
      );

    _loadEmulator();
  }

  Future<void> _loadEmulator() async {
    if (_controller == null) return;

    try {
      // First show loading status
      await _controller!.loadHtmlString(
        _buildStatusHtml('Initializing Console VM...'),
      );

      // Show download status and retry up to 3 times
      final vmManager = ConsoleVmManager();
      bool ready = false;
      for (var attempt = 1; attempt <= 3; attempt++) {
        await _controller!.loadHtmlString(
          _buildStatusHtml('Downloading VM files... (attempt $attempt/3)'),
        );
        ready = await vmManager.ensureVmReady();
        if (ready) break;
        LogService().log(
          'Console: Download attempt $attempt failed, retrying...',
        );
        await Future.delayed(const Duration(seconds: 2));
      }

      if (!ready) {
        await _controller!.loadHtmlString(
          _buildErrorHtml(
            'Failed to download VM files after 3 attempts.\n\n'
            'Check your internet connection and try again.',
          ),
        );
        LogService().log('Console: VM files not ready after retries');
        return;
      }

      // Load the emulator
      await _controller!.loadHtmlString(
        _buildStatusHtml('Starting Alpine Linux...'),
      );
      final vmPath = await vmManager.vmPath;
      final initrdFile = File('$vmPath/alpine-x86-rootfs.cpio.gz');
      if (!await initrdFile.exists()) {
        await _controller!.loadHtmlString(
          _buildErrorHtml(
            'VM initrd missing. Please ensure alpine-x86-rootfs.cpio.gz is present.',
          ),
        );
        return;
      }
      final vmBaseUrl = await _ensureLocalVmServer(vmPath);
      final html = await _generateEmulatorHtml(vmBaseUrl, vmPath);
      await _controller!.loadHtmlString(html.html, baseUrl: html.baseUrl);
    } catch (e) {
      LogService().log('Console: Error loading emulator: $e');
      await _controller!.loadHtmlString(_buildErrorHtml('Error: $e'));
    }
  }

  String _buildStatusHtml(String message) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { background: #000; color: #0f0; font-family: monospace; padding: 20px; }
    .spinner { display: inline-block; width: 12px; height: 12px; border: 2px solid #0f0;
               border-radius: 50%; border-top-color: transparent; animation: spin 1s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="spinner"></div> $message
</body>
</html>
''';
  }

  String _buildErrorHtml(String message) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { background: #000; color: #f00; font-family: monospace; padding: 20px; white-space: pre-wrap; }
  </style>
</head>
<body>$message</body>
</html>
''';
  }

  /// Default station URL for VM file downloads
  static const String _defaultStationUrl = 'https://p2p.radio';

  /// Get station URL for loading VM files in the emulator HTML.
  ///
  /// IMPORTANT: Station URLs are stored as WebSocket URLs (wss://host or ws://host)
  /// but we need HTTP/HTTPS URLs for the browser to fetch kernel/rootfs files.
  /// This method MUST convert ws:// -> http:// and wss:// -> https://
  String _getStationUrl() {
    final station = StationService().getPreferredStation();
    if (station == null || station.url.isEmpty) {
      LogService().log(
        'Console: Using default station URL: $_defaultStationUrl',
      );
      return _defaultStationUrl;
    }

    // CRITICAL: Convert WebSocket URL to HTTP/HTTPS
    // The emulator HTML fetches files via HTTP, not WebSocket
    var stationUrl = station.url;
    if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    } else if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    }
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }
    return stationUrl;
  }

  /// Start a loopback HTTP server that serves VM assets from disk so the WebView
  /// can load everything offline via http://127.0.0.1:<port>/console/vm/...
  Future<String> _ensureLocalVmServer(String vmPath) async {
    if (_localVmServer != null) {
      return 'http://127.0.0.1:${_localVmServer!.port}/console/vm';
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _localVmServer = server;

    server.listen((HttpRequest request) async {
      final relativePath = request.uri.path.replaceFirst(
        RegExp(r'^/console/vm/?'),
        '',
      );
      final target = p.normalize(p.join(vmPath, relativePath));

      void respondNotFound() {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }

      // Prevent directory traversal
      if (!target.startsWith(p.normalize(vmPath))) {
        respondNotFound();
        return;
      }

      final file = File(target);
      if (!await file.exists()) {
        respondNotFound();
        return;
      }

      final ext = p.extension(target).toLowerCase();
      switch (ext) {
        case '.js':
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
          );
          break;
        case '.wasm':
          request.response.headers.contentType = ContentType(
            'application',
            'wasm',
          );
          break;
        case '.gz':
          request.response.headers.contentType = ContentType(
            'application',
            'gzip',
          );
          break;
        case '.json':
          request.response.headers.contentType = ContentType.json;
          break;
        case '.cfg':
        case '.txt':
          request.response.headers.contentType = ContentType.text;
          break;
        default:
          request.response.headers.contentType = ContentType.binary;
      }

      Stream<List<int>> stream = file.openRead();

      if (ext == '.wasm') {
        try {
          final header = await file.openRead(0, 2).first;
          final isGzip =
              header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b;
          if (isGzip) {
            LogService().log(
              'Console: Decompressing gzipped WASM before serving (${p.basename(target)})',
            );
            stream = file.openRead().transform(gzip.decoder);
          }
        } catch (e) {
          LogService().log('Console: Error preparing WASM response: $e');
        }
      }

      await stream.pipe(request.response);
    });

    return 'http://127.0.0.1:${server.port}/console/vm';
  }

  Future<({String html, String baseUrl})> _generateEmulatorHtml(
    String vmBaseUrl,
    String vmPath,
  ) async {
    final emulatorBaseUrl = vmBaseUrl; // Host for JSLinux assets
    final configPath = await _writeOfflineConfig(vmPath);
    final configUrl = '$vmBaseUrl/${p.basename(configPath)}';

    // Read locally cached JS files
    String termJs = '';
    String jslinuxJs = '';

    try {
      final termFile = File('$vmPath/term.js');
      final jslinuxFile = File('$vmPath/jslinux.js');

      if (await termFile.exists() && await jslinuxFile.exists()) {
        termJs = await termFile.readAsString();
        jslinuxJs = await jslinuxFile.readAsString();
        LogService().log('Console: Loaded scripts from local cache');
      } else {
        LogService().log(
          'Console: Local scripts not found, will load from network',
        );
      }
    } catch (e) {
      LogService().log('Console: Error reading local scripts: $e');
    }

    final queryString = Uri(
      queryParameters: {
        'url': configUrl,
        'mem': widget.session.memory.toString(),
        if (!widget.session.networkEnabled) 'net_url': '',
      },
    ).query;

    final targetLocation = '$emulatorBaseUrl/vm.html?$queryString';

    // If we have local scripts, embed them inline; otherwise load from network
    final useLocalScripts = termJs.isNotEmpty && jslinuxJs.isNotEmpty;

    final html =
        '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <base href="$vmBaseUrl/">
  <style>
    * { margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    #term_wrap { display: none; width: 100%; height: 100%; }
    #term_container { width: 100%; height: calc(100% - 24px); background: #000; }
    #term_bar { height: 24px; background: #111; color: #0f0; font-family: monospace; display: flex; align-items: center; padding: 0 8px; gap: 8px; }
    #term_bar progress { width: 140px; }
    #status { color: #0f0; font-family: monospace; padding: 16px; }
    .error { color: #f00; font-family: monospace; padding: 20px; white-space: pre-wrap; }
    #term_paste { position: absolute; left: -9999px; opacity: 0; }
  </style>
</head>
<body>
  <div id="status">Loading Alpine Linux VM...</div>
  <div id="term_wrap">
    <div id="term_container"></div>
    <textarea id="term_paste"></textarea>
    <div id="term_bar">
      <span>Console VM</span>
      <progress id="net_progress" value="0" max="1"></progress>
    </div>
  </div>
  ${useLocalScripts ? '''
  <!-- Locally cached scripts -->
  <script>
$termJs
  </script>
  <script>
$jslinuxJs
  </script>
''' : '''
  <!-- Network loaded scripts -->
  <script src="$vmBaseUrl/term.js"></script>
  <script src="$vmBaseUrl/jslinux.js"></script>
'''}
  <script>
    window.geogramBridge = {
      sendMessage: function(type, data) {
        if (window.GeogramBridge) GeogramBridge.postMessage(JSON.stringify({type: type, data: data}));
      },
      onReady: function() { this.sendMessage('ready', true); },
      onError: function(msg) { this.sendMessage('error', msg); },
      log: function(msg) { this.sendMessage('log', msg); }
    };

    // Force the page location to the VM host so jslinux resolves relative assets correctly
    (function() {
      try {
        history.replaceState({}, '', '$targetLocation');
        window.geogramBridge.log('Location set to: ' + window.location.href);
      } catch (e) {
        window.geogramBridge.log('Failed to update history: ' + e);
      }
    })();

    window.addEventListener('error', function(event) {
      var message = event && event.message ? event.message : event.toString();
      window.geogramBridge.onError('JS error: ' + message);
    });
  </script>

  <script>
    // Notify Flutter when the emulator runtime comes up
    window.Module = window.Module || {};
    window.Module.onRuntimeInitialized = function() {
      var status = document.getElementById('status');
      var termWrap = document.getElementById('term_wrap');
      if (status) status.style.display = 'none';
      if (termWrap) termWrap.style.display = 'block';
      window.geogramBridge.log('JSLinux runtime initialized');
      window.geogramBridge.onReady();
    };

    // Extra guard: surface a timeout if the emulator doesn't load
    setTimeout(function() {
      if (!window.Module || !window.Module.calledRun) {
        window.geogramBridge.onError('Timeout: JSLinux not loaded\\n\\nCheck your connection or station assets.');
      }
    }, 20000);
  </script>
</body>
</html>
''';

    return (html: html, baseUrl: targetLocation);
  }

  /// Generate a local config that points to offline assets
  Future<String> _writeOfflineConfig(String vmPath) async {
    final configPath = p.join(vmPath, 'local-alpine-x86.cfg');
    // Always use local initrd for fully offline operation
    final config =
        '''{
    version: 1,
    machine: "pc",
    memory_size: ${widget.session.memory},
    kernel: "kernel-x86.bin",
    initrd: "alpine-x86-rootfs.cpio.gz",
    cmdline: "loglevel=3 console=hvc0 root=/dev/ram0 rw rdinit=/bin/sh",
    eth0: { driver: "user" },
}
''';

    try {
      await File(configPath).writeAsString(config);
      return configPath;
    } catch (e) {
      LogService().log('Console: Failed to write offline config: $e');
      return p.join(vmPath, 'alpine-x86.cfg');
    }
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final payload = data['data'];

      switch (type) {
        case 'state':
          widget.onStateChanged?.call(
            ConsoleSession.parseState(payload as String?),
          );
          break;
        case 'ready':
          _isReady = true;
          widget.onReady?.call();
          break;
        case 'log':
          LogService().log('Console VM log: $payload');
          break;
        case 'error':
          LogService().log('Console VM error: $payload');
          break;
      }
    } catch (e) {
      LogService().log('Console: Error parsing JS message: $e');
    }
  }

  void _onPageLoaded() {
    LogService().log('Console: WebView page loaded');
  }

  Future<void> saveState() async {
    if (_useNativeTerminal) {
      // For QEMU, we could use savevm but it's complex
      LogService().log('Console: Save state not implemented for Linux QEMU');
      return;
    }
    if (_controller == null) return;
    await _controller!.runJavaScript(
      'if (window.vm && window.vm.saveState) { window.geogramBridge.sendMessage("save_state", window.vm.saveState()); }',
    );
  }

  Future<void> loadState(String statePath) async {
    LogService().log('Console: Loading state from $statePath');
  }

  Future<void> resetVm() async {
    if (_useNativeTerminal) {
      _cleanup();
      await _initializeNativeTerminal();
      return;
    }
    if (_controller == null) return;
    await _controller!.runJavaScript('location.reload()');
  }

  @override
  Widget build(BuildContext context) {
    // Show error if platform not supported
    if (!_platformSupported || _platformError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 64),
                const SizedBox(height: 16),
                Text(
                  _platformError != null ? 'Error' : 'Platform Not Supported',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _platformError ?? 'WebView is not available.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Build appropriate widget
    Widget content;
    if (_useNativeTerminal && _terminal != null) {
      content = TerminalView(
        _terminal!,
        textStyle: const TerminalStyle(fontSize: 14),
      );
    } else if (_controller != null) {
      content = WebViewWidget(controller: _controller!);
    } else {
      content = const SizedBox.shrink();
    }

    return Stack(
      children: [
        content,
        if (_isLoading)
          Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'Loading Alpine Linux...',
                    style: TextStyle(
                      color: Colors.green,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
