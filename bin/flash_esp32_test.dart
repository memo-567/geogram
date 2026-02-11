/// ESP32 Flash Test - Flutter CLI
///
/// Tests flashing firmware to an ESP32-C3-mini device using the internal
/// esptool protocol implementation.
///
/// Run with Flutter to load native serial port bindings:
///   flutter run -d linux bin/flash_esp32_test.dart
///
/// WARNING: This test will overwrite the firmware on the connected ESP32!

import 'dart:io';
import 'dart:typed_data';

import '../lib/flasher/models/device_definition.dart';
import '../lib/flasher/models/flash_progress.dart';
import '../lib/flasher/protocols/esptool_protocol.dart';
import '../lib/flasher/serial/serial_port.dart';

DateTime? _startTime;

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

void _progress(FlashProgress p) {
  final elapsed = _startTime != null
      ? DateTime.now().difference(_startTime!).inSeconds
      : 0;

  switch (p.status) {
    case FlashStatus.connecting:
      print('  [....] Connecting to device...');
    case FlashStatus.syncing:
      print('  [....] Syncing with bootloader...');
    case FlashStatus.erasing:
      print('  [${(p.progress * 100).toInt().toString().padLeft(3)}%] Erasing flash...');
    case FlashStatus.writing:
      final pct = (p.progress * 100).toInt();
      final speed = elapsed > 0 ? (p.bytesWritten / elapsed / 1024).toStringAsFixed(1) : '---';
      print(
        '  [${pct.toString().padLeft(3)}%] Writing: ${_formatBytes(p.bytesWritten)} / ${_formatBytes(p.totalBytes)} '
        '(${p.currentChunk}/${p.totalChunks}) @ $speed KB/s',
      );
    case FlashStatus.verifying:
      print('  [${(p.progress * 100).toInt().toString().padLeft(3)}%] Verifying...');
    case FlashStatus.reading:
      print('  [${(p.progress * 100).toInt().toString().padLeft(3)}%] Reading flash...');
    case FlashStatus.resetting:
      print('  [....] Resetting device...');
    case FlashStatus.completed:
      print('  [DONE] Flash completed!');
    case FlashStatus.error:
      print('  [ERR!] ${p.error}');
    case FlashStatus.idle:
      break;
  }
}

Future<void> main(List<String> args) async {
  print('');
  print('=' * 70);
  print('ESP32 Flash Test (Geogram Internal Libraries)');
  print('=' * 70);
  print('');

  final dryRun = args.contains('--dry-run');
  final portArg = args.where((a) => a.startsWith('--port=')).firstOrNull;
  final specifiedPort = portArg?.substring(7);

  if (dryRun) {
    print('*** DRY RUN MODE ***');
    print('');
  }

  // Load firmware
  print('Step 1: Load Firmware');
  print('-' * 40);

  final firmwarePath = 'tests/flasher/geogram-ESP32C3-mini.bin';
  final firmwareFile = File(firmwarePath);

  if (!await firmwareFile.exists()) {
    print('  [FAIL] Firmware not found: $firmwarePath');
    exit(1);
  }

  final firmwareBytes = await firmwareFile.readAsBytes();
  print('  [OK] Loaded: ${_formatBytes(firmwareBytes.length)}');
  print('');

  // Detect device
  print('Step 2: Detect ESP32 Device');
  print('-' * 40);

  final ports = await SerialPort.listPorts();
  print('  Found ${ports.length} serial port(s)');

  for (final port in ports) {
    final esp32Desc = Esp32UsbIdentifiers.matchEsp32(port);
    final marker = esp32Desc != null ? ' <-- ESP32' : '';
    print('    ${port.path}: VID=${port.vidHex ?? "?"} PID=${port.pidHex ?? "?"}$marker');
  }

  PortInfo? targetPort;

  if (specifiedPort != null) {
    targetPort = ports.where((p) => p.path == specifiedPort).firstOrNull;
    if (targetPort == null) {
      print('  [FAIL] Specified port not found: $specifiedPort');
      exit(1);
    }
  } else {
    final esp32Ports = await Esp32UsbIdentifiers.findEsp32Ports();
    if (esp32Ports.isEmpty) {
      print('  [FAIL] No ESP32 device detected');
      print('');
      print('  Use --port=/dev/ttyXXX to specify manually');
      exit(1);
    }
    final (port, desc) = esp32Ports.first;
    targetPort = port;
    print('  [OK] Using: ${port.path} ($desc)');
  }

  print('');

  if (dryRun) {
    print('Step 3: Dry Run Complete');
    print('-' * 40);
    print('  Device: ${targetPort.path}');
    print('  Firmware: ${_formatBytes(firmwareBytes.length)}');
    print('  Chunks: ${(firmwareBytes.length / 1024).ceil()}');
    print('');
    print('  To actually flash, run without --dry-run');
    exit(0);
  }

  // Flash
  print('Step 3: Flash Firmware');
  print('-' * 40);
  print('');
  print('  WARNING: Flashing will begin in 3 seconds...');
  print('  Press Ctrl+C to abort');
  print('');

  await Future.delayed(const Duration(seconds: 3));

  final protocol = EspToolProtocol();
  final serialPort = SerialPort();

  try {
    // Open port
    print('  Opening serial port...');
    final opened = await serialPort.open(targetPort.path, 115200);
    if (!opened) {
      print('  [FAIL] Cannot open ${targetPort.path}');
      exit(1);
    }
    print('  [OK] Port opened');

    // Connect
    print('  Connecting to bootloader...');
    _startTime = DateTime.now();

    final connected = await protocol.connect(
      serialPort,
      baudRate: 115200,
      onProgress: _progress,
    );

    if (!connected) {
      print('  [FAIL] Cannot connect to bootloader');
      exit(1);
    }

    print('  [OK] Connected - Chip: ${protocol.chipInfo ?? "unknown"}');
    print('');
    print('  Flashing...');
    print('');

    // Flash with high baud rate
    await protocol.flash(
      firmwareBytes,
      FlashConfig(protocol: 'esptool', baudRate: 921600),
      onProgress: _progress,
    );

    print('');
    print('  [OK] Firmware written');

    // Verify
    final verified = await protocol.verify(onProgress: _progress);
    if (verified) {
      print('  [OK] Verified');
    } else {
      print('  [WARN] Verification skipped');
    }

    // Reset
    await protocol.reset();
    print('  [OK] Device reset');

    final elapsed = DateTime.now().difference(_startTime!);
    final speed = (firmwareBytes.length / elapsed.inSeconds / 1024).toStringAsFixed(1);

    print('');
    print('=' * 70);
    print('SUCCESS: Flashed ${_formatBytes(firmwareBytes.length)} in ${elapsed.inSeconds}s ($speed KB/s)');
    print('=' * 70);
    print('');

  } catch (e, stack) {
    print('');
    print('  [FAIL] $e');
    print('');
    print('Stack trace:');
    print(stack);
    exit(1);
  } finally {
    await protocol.disconnect();
    await serialPort.close();
  }

  exit(0);
}
