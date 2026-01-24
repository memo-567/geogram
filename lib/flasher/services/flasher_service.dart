import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/device_definition.dart';
import '../models/flash_progress.dart';
import '../protocols/flash_protocol.dart';
import '../protocols/protocol_registry.dart';
import '../serial/serial_port.dart';
import '../serial/serial_port_desktop.dart';
import 'flasher_storage_service.dart';

/// Main flasher service
///
/// Orchestrates the complete flashing process including:
/// - Device discovery
/// - Firmware download
/// - Protocol selection
/// - Flash execution
/// - Progress reporting
class FlasherService {
  final FlasherStorageService _storage;

  FlashProtocol? _currentProtocol;
  SerialPort? _currentPort;
  StreamController<FlashProgress>? _progressController;

  FlasherService(this._storage);

  /// Create with default storage path
  factory FlasherService.withPath(String basePath) {
    return FlasherService(FlasherStorageService(basePath));
  }

  /// Get storage service
  FlasherStorageService get storage => _storage;

  /// Progress stream for current operation
  Stream<FlashProgress>? get progressStream => _progressController?.stream;

  /// List available serial ports
  Future<List<PortInfo>> listPorts() async {
    if (Platform.isAndroid) {
      // Use Android implementation
      throw UnimplementedError('Android port listing not yet implemented');
    } else {
      // Desktop implementation
      return DesktopSerialPort.listPorts();
    }
  }

  /// Find ports matching a device definition
  Future<List<PortInfo>> findMatchingPorts(DeviceDefinition device) async {
    if (device.usb == null) return [];

    final ports = await listPorts();
    final vid = device.usb!.vidInt;
    final pid = device.usb!.pidInt;

    return ports.where((p) => p.vid == vid && p.pid == pid).toList();
  }

  /// Auto-detect connected device
  Future<DeviceDefinition?> autoDetectDevice() async {
    final ports = await listPorts();

    for (final port in ports) {
      if (port.vid != null && port.pid != null) {
        final device = await _storage.findDeviceByUsb(port.vid!, port.pid!);
        if (device != null) {
          return device;
        }
      }
    }

    return null;
  }

  /// Download firmware from URL
  Future<Uint8List> downloadFirmware(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw FlashException('Failed to download firmware: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    final bytes = <int>[];
    var received = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;

      if (contentLength > 0 && onProgress != null) {
        onProgress(received / contentLength);
      }
    }

    return Uint8List.fromList(bytes);
  }

  /// Load firmware from file
  Future<Uint8List> loadFirmwareFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FlashException('Firmware file not found: $path');
    }

    return file.readAsBytes();
  }

  /// Flash device with firmware
  ///
  /// [device] - Device definition with flash configuration
  /// [portPath] - Serial port path (e.g., /dev/ttyUSB0)
  /// [firmware] - Firmware binary data (or null to download from device.flash.firmwareUrl)
  /// [firmwarePath] - Local firmware file path (alternative to [firmware])
  /// [onProgress] - Progress callback
  Future<bool> flashDevice({
    required DeviceDefinition device,
    required String portPath,
    Uint8List? firmware,
    String? firmwarePath,
    FlashProgressCallback? onProgress,
  }) async {
    _progressController = StreamController<FlashProgress>.broadcast();

    void reportProgress(FlashProgress progress) {
      onProgress?.call(progress);
      _progressController?.add(progress);
    }

    try {
      // Load firmware
      Uint8List firmwareData;
      if (firmware != null) {
        firmwareData = firmware;
      } else if (firmwarePath != null) {
        reportProgress(FlashProgress(
          status: FlashStatus.idle,
          message: 'Loading firmware...',
        ));
        firmwareData = await loadFirmwareFromFile(firmwarePath);
      } else if (device.flash.firmwareUrl != null) {
        reportProgress(FlashProgress(
          status: FlashStatus.idle,
          message: 'Downloading firmware...',
        ));
        firmwareData = await downloadFirmware(
          device.flash.firmwareUrl!,
          onProgress: (progress) {
            reportProgress(FlashProgress(
              status: FlashStatus.idle,
              progress: progress,
              message: 'Downloading firmware...',
            ));
          },
        );
      } else {
        throw FlashException('No firmware source specified');
      }

      // Create protocol
      _currentProtocol = ProtocolRegistry.create(device.flash.protocol);
      if (_currentProtocol == null) {
        throw FlashException('Unsupported protocol: ${device.flash.protocol}');
      }

      // Create serial port
      if (Platform.isAndroid) {
        throw UnimplementedError('Android flashing not yet implemented');
      } else {
        _currentPort = DesktopSerialPort();
      }

      // Connect
      final connected = await _currentProtocol!.connect(
        _currentPort!,
        baudRate: device.flash.baudRate,
        onProgress: reportProgress,
      );

      if (!connected) {
        throw ConnectionException('Failed to connect to device');
      }

      // Flash
      await _currentProtocol!.flash(
        firmwareData,
        device.flash,
        onProgress: reportProgress,
      );

      // Verify
      final verified = await _currentProtocol!.verify(onProgress: reportProgress);
      if (!verified) {
        throw VerifyException('Firmware verification failed');
      }

      // Reset to run new firmware
      reportProgress(FlashProgress.resetting());
      await _currentProtocol!.reset();

      // Complete
      reportProgress(FlashProgress.completed(
        DateTime.now().difference(DateTime.now()), // Will be replaced with actual elapsed
      ));

      return true;
    } catch (e) {
      reportProgress(FlashProgress.error(e.toString()));
      rethrow;
    } finally {
      await _cleanup();
    }
  }

  /// Cancel current flash operation
  Future<void> cancel() async {
    await _cleanup();
    _progressController?.add(FlashProgress.error('Flash cancelled by user'));
  }

  /// Clean up resources
  Future<void> _cleanup() async {
    if (_currentProtocol != null) {
      await _currentProtocol!.disconnect();
      _currentProtocol = null;
    }

    if (_currentPort != null) {
      await _currentPort!.close();
      _currentPort = null;
    }

    await _progressController?.close();
    _progressController = null;
  }
}
