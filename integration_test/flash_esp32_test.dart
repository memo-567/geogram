/// ESP32 Flash Integration Test
///
/// Tests flashing firmware to an ESP32-C3-mini device using the internal
/// esptool protocol implementation.
///
/// This test must be run with Flutter to load native serial port bindings:
///   flutter test integration_test/flash_esp32_test.dart -d linux
///
/// Or run as a headless app:
///   flutter run -d linux integration_test/flash_esp32_test.dart
///
/// WARNING: This test will overwrite the firmware on the connected ESP32!

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/flasher/models/device_definition.dart';
import '../lib/flasher/models/flash_progress.dart';
import '../lib/flasher/protocols/esptool_protocol.dart';
import '../lib/flasher/serial/serial_port.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('ESP32 Flash Test', () {
    late Uint8List firmwareBytes;
    late PortInfo targetPort;

    setUpAll(() async {
      // Load firmware
      final firmwarePath = 'tests/flasher/geogram-ESP32C3-mini.bin';
      final firmwareFile = File(firmwarePath);

      if (!await firmwareFile.exists()) {
        fail('Firmware file not found at $firmwarePath');
      }

      firmwareBytes = await firmwareFile.readAsBytes();
      print('Loaded firmware: ${firmwareBytes.length} bytes');
    });

    test('detect ESP32 device', () async {
      final ports = await SerialPort.listPorts();
      print('Found ${ports.length} serial ports');

      for (final port in ports) {
        print('  - ${port.path} VID=${port.vidHex} PID=${port.pidHex} ${port.product ?? ""}');
      }

      final esp32Ports = await Esp32UsbIdentifiers.findEsp32Ports();
      expect(esp32Ports, isNotEmpty, reason: 'No ESP32 device found');

      final (port, desc) = esp32Ports.first;
      targetPort = port;
      print('Using ESP32: ${port.path} - $desc');
    });

    test('flash firmware to ESP32', () async {
      final protocol = EspToolProtocol();
      final serialPort = SerialPort();

      try {
        // Open port
        print('Opening ${targetPort.path}...');
        final opened = await serialPort.open(targetPort.path, 115200);
        expect(opened, isTrue, reason: 'Failed to open serial port');

        // Connect to bootloader
        print('Connecting to bootloader...');
        final connected = await protocol.connect(
          serialPort,
          baudRate: 115200,
          onProgress: (p) => print('  ${p.status}: ${p.message}'),
        );
        expect(connected, isTrue, reason: 'Failed to connect to bootloader');
        print('Chip detected: ${protocol.chipInfo}');

        // Flash
        print('Flashing ${firmwareBytes.length} bytes...');
        final startTime = DateTime.now();

        await protocol.flash(
          firmwareBytes,
          FlashConfig(protocol: 'esptool', baudRate: 921600),
          onProgress: (p) {
            if (p.status == FlashStatus.writing) {
              print('  Writing: ${p.percentage}% (${p.currentChunk}/${p.totalChunks})');
            }
          },
        );

        final elapsed = DateTime.now().difference(startTime);
        print('Flash completed in ${elapsed.inSeconds}s');

        // Verify
        print('Verifying...');
        final verified = await protocol.verify();
        expect(verified, isTrue, reason: 'Verification failed');

        // Reset
        print('Resetting device...');
        await protocol.reset();

        print('SUCCESS: Firmware flashed and verified!');
      } finally {
        await protocol.disconnect();
        await serialPort.close();
      }
    });
  });
}
