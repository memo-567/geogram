/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console widget for running Alpine Linux VM.
 * - Android/iOS/macOS: WebView with JSLinux (JavaScript x86 emulator)
 * - Linux: Native QEMU with xterm terminal widget
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart'
    show Platform, Process, Directory, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Conditional imports for Linux-only packages (PTY/terminal)
import 'console_pty_stub.dart' if (dart.library.io) 'package:flutter_pty/flutter_pty.dart';
import 'console_terminal_stub.dart' if (dart.library.io) 'package:xterm/xterm.dart';
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
  // WebView controller (Android/iOS/macOS)
  WebViewController? _controller;

  // Linux native terminal
  Terminal? _terminal;
  Pty? _pty;
  Process? _qemuProcess;

  bool _isReady = false;
  bool _isLoading = true;
  bool _platformSupported = false;
  bool _isLinux = false;
  String? _platformError;

  /// Check if current platform supports Console VM
  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return true;
    if (Platform.isLinux) return true; // Native QEMU support
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
  }

  void _checkPlatformAndInitialize() {
    if (!isPlatformSupported) {
      String platformName = 'this platform';
      if (!kIsWeb && Platform.isWindows) platformName = 'Windows';
      if (kIsWeb) platformName = 'Web browser';

      setState(() {
        _platformSupported = false;
        _platformError = 'Console VM is not yet supported on $platformName.\n\n'
            'Supported platforms: Android, iOS, macOS, Linux.';
        _isLoading = false;
      });
      LogService().log('Console: Platform not supported - $platformName');
      return;
    }

    _platformSupported = true;
    _isLinux = !kIsWeb && Platform.isLinux;

    if (_isLinux) {
      _initializeLinuxTerminal();
    } else {
      _initializeWebView();
    }
  }

  /// Initialize native terminal for Linux (TinyEMU or QEMU)
  Future<void> _initializeLinuxTerminal() async {
    LogService().log('Console: Initializing Linux native terminal');

    try {
      // Create terminal emulator
      _terminal = Terminal(
        maxLines: 10000,
      );

      // Check for emulator availability (TinyEMU preferred, QEMU fallback)
      final emulator = await _findEmulator();
      if (emulator == null) {
        setState(() {
          _platformError = 'No emulator found.\n\n'
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
          _platformError = 'VM files not downloaded.\n'
              'Please check your station connection.';
          _isLoading = false;
        });
        return;
      }

      // Get paths to VM files
      final vmPath = await vmManager.vmPath;

      if (emulator.isTinyEmu) {
        // Use TinyEMU with config file
        final configPath = '$vmPath/alpine-x86.cfg';
        await _startTinyEmu(emulator.path, configPath, vmPath);
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
      LogService().log('Console: Error initializing Linux terminal: $e');
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
    // First, check for bundled TinyEMU relative to the executable
    final execPath = Platform.resolvedExecutable;
    final execDir = Directory(execPath).parent.path;
    final bundledTemu = '$execDir/bin/temu';

    if (await File(bundledTemu).exists()) {
      LogService().log('Console: Found bundled TinyEMU at $bundledTemu');
      return (path: bundledTemu, isTinyEmu: true);
    }

    // Check for system TinyEMU
    final temuPaths = [
      '/usr/bin/temu',
      '/usr/local/bin/temu',
    ];

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
        'create', '-f', 'qcow2', diskPath, '256M'
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
    final rootfsDir = '$vmPath/rootfs';
    final rootfsTarball = '$vmPath/alpine-x86-rootfs.tar.gz';
    final markerFile = '$vmPath/.rootfs_extracted';

    // Check if already extracted
    if (await File(markerFile).exists()) {
      LogService().log('Console: Rootfs already extracted');
      return rootfsDir;
    }

    // Create rootfs directory
    final dir = Directory(rootfsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Extract rootfs tarball
    LogService().log('Console: Extracting rootfs from $rootfsTarball...');
    try {
      final result = await Process.run('tar', [
        'xzf', rootfsTarball,
        '-C', rootfsDir,
      ]);

      if (result.exitCode != 0) {
        LogService().log('Console: Failed to extract rootfs: ${result.stderr}');
        return null;
      }

      // Create marker file
      await File(markerFile).writeAsString(DateTime.now().toIso8601String());
      LogService().log('Console: Rootfs extracted successfully');
      return rootfsDir;
    } catch (e) {
      LogService().log('Console: Error extracting rootfs: $e');
      return null;
    }
  }

  /// Generate local TinyEMU config file
  Future<String?> _generateLocalConfig(String vmPath) async {
    final localConfigPath = '$vmPath/local-alpine-x86.cfg';
    final kernelPath = 'kernel-x86.bin';  // Relative to vmPath
    final rootfsDir = await _prepareRootfs(vmPath);

    if (rootfsDir == null) {
      return null;
    }

    // Generate config with local paths
    // Use init=/bin/sh to get a shell directly (rootfs doesn't have openrc)
    final config = '''{
    version: 1,
    machine: "pc",
    memory_size: ${widget.session.memory},
    kernel: "$kernelPath",
    cmdline: "loglevel=3 console=hvc0 root=root rootfstype=9p rootflags=trans=virtio rw init=/bin/sh",
    fs0: { file: "rootfs" },
    eth0: { driver: "user" },
}
''';

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
  Future<void> _startTinyEmu(String temuPath, String configPath, String vmPath) async {
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

    // Create PTY and spawn TinyEMU
    _pty = Pty.start(
      temuPath,
      arguments: args,
      workingDirectory: vmPath,  // Set working directory so relative paths in config work
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

  /// Start QEMU with PTY
  Future<void> _startQemu(String qemuPath, String kernelPath, String diskPath) async {
    LogService().log('Console: Starting QEMU...');

    // Build QEMU command line
    final args = [
      '-machine', 'pc',
      '-m', '${widget.session.memory}M',
      '-nographic',  // Use serial console
      '-kernel', kernelPath,
      '-append', 'console=ttyS0 root=/dev/sda rw',
      '-drive', 'file=$diskPath,format=qcow2,if=ide',
    ];

    // Add network if enabled
    if (widget.session.networkEnabled) {
      args.addAll(['-netdev', 'user,id=net0', '-device', 'virtio-net-pci,netdev=net0']);
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
      final vmManager = ConsoleVmManager();
      final ready = await vmManager.ensureVmReady();
      if (!ready) {
        LogService().log('Console: VM files not ready');
        return;
      }

      final html = await _generateEmulatorHtml();
      await _controller!.loadHtmlString(html);
    } catch (e) {
      LogService().log('Console: Error loading emulator: $e');
    }
  }

  String? _getStationUrl() {
    final station = StationService().getPreferredStation();
    if (station == null || station.url.isEmpty) return null;

    var stationUrl = station.url;
    if (stationUrl.startsWith('ws://')) {
      stationUrl = stationUrl.replaceFirst('ws://', 'http://');
    } else if (stationUrl.startsWith('wss://')) {
      stationUrl = stationUrl.replaceFirst('wss://', 'https://');
    }
    if (stationUrl.endsWith('/')) {
      stationUrl = stationUrl.substring(0, stationUrl.length - 1);
    }
    return stationUrl;
  }

  Future<String> _generateEmulatorHtml() async {
    final stationUrl = _getStationUrl();
    if (stationUrl == null) {
      return '<html><body style="background:#000;color:#f00;font-family:monospace;padding:20px;">'
          '<h2>Error: No Station Connected</h2></body></html>';
    }

    // Read locally cached JS files
    final vmManager = ConsoleVmManager();
    final vmPath = await vmManager.vmPath;

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
        LogService().log('Console: Local scripts not found, will load from network');
      }
    } catch (e) {
      LogService().log('Console: Error reading local scripts: $e');
    }

    final vmBaseUrl = '$stationUrl/console/vm';
    final vmConfig = jsonEncode({
      'memory_size': widget.session.memory,
      'network': widget.session.networkEnabled,
    });

    // If we have local scripts, embed them inline; otherwise load from network
    final useLocalScripts = termJs.isNotEmpty && jslinuxJs.isNotEmpty;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    #term { width: 100%; height: 100%; background: #000; }
    .loading { color: #0f0; font-family: monospace; padding: 20px; }
    .error { color: #f00; font-family: monospace; padding: 20px; white-space: pre-wrap; }
  </style>
</head>
<body>
  <div id="term"><div class="loading">Loading Alpine Linux VM...</div></div>
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
      onError: function(msg) { this.sendMessage('error', msg); }
    };
    var vmBaseUrl = '$vmBaseUrl';
    var sessionConfig = $vmConfig;

    function showError(msg) {
      document.getElementById('term').innerHTML = '<div class="error">' + msg + '</div>';
      window.geogramBridge.onError(msg);
    }

    function initVM() {
      try {
        document.getElementById('term').innerHTML = '';
        if (typeof pc_start !== 'function') {
          showError('JSLinux not loaded\\n\\nThe emulator scripts failed to load.\\nPlease check your station connection.');
          return;
        }
        window.vmStarted = true;
        pc_start({
          mem_size: sessionConfig.memory_size,
          cmdline: 'console=ttyS0 root=/dev/vda rw',
          kernel_url: vmBaseUrl + '/kernel-x86.bin',
          fs_url: vmBaseUrl + '/alpine-x86-rootfs.tar.gz',
          term_container: document.getElementById('term'),
          on_ready: function() { window.geogramBridge.onReady(); }
        });
      } catch (e) {
        showError('VM Error: ' + e.message);
      }
    }

    // Start VM after page load
    if (document.readyState === 'complete') {
      setTimeout(initVM, 100);
    } else {
      window.addEventListener('load', function() { setTimeout(initVM, 100); });
    }

    // Fallback timeout
    setTimeout(function() {
      if (!window.vmStarted) {
        if (typeof pc_start !== 'function') {
          showError('Timeout: JSLinux not loaded\\n\\nPlease check your network connection.');
        }
      }
    }, 15000);
  </script>
</body>
</html>
''';
  }

  void _handleJavaScriptMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final payload = data['data'];

      switch (type) {
        case 'state':
          widget.onStateChanged?.call(ConsoleSession.parseState(payload as String?));
          break;
        case 'ready':
          _isReady = true;
          widget.onReady?.call();
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
    if (_isLinux) {
      // For QEMU, we could use savevm but it's complex
      LogService().log('Console: Save state not implemented for Linux QEMU');
      return;
    }
    if (_controller == null) return;
    await _controller!.runJavaScript(
      'if (window.vm && window.vm.saveState) { window.geogramBridge.sendMessage("save_state", window.vm.saveState()); }'
    );
  }

  Future<void> loadState(String statePath) async {
    LogService().log('Console: Loading state from $statePath');
  }

  Future<void> resetVm() async {
    if (_isLinux) {
      _cleanup();
      await _initializeLinuxTerminal();
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
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
    if (_isLinux && _terminal != null) {
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
                  Text('Loading Alpine Linux...', style: TextStyle(color: Colors.green, fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
