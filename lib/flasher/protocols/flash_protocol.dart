import 'dart:typed_data';

import '../models/device_definition.dart';
import '../models/flash_progress.dart';
import '../serial/serial_port.dart';

/// Progress callback for flash operations
typedef FlashProgressCallback = void Function(FlashProgress progress);

/// Abstract flash protocol interface
///
/// Each device family implements its own protocol for communicating
/// with the bootloader and flashing firmware.
abstract class FlashProtocol {
  /// Protocol identifier (e.g., "esptool", "quansheng")
  String get protocolId;

  /// Protocol display name
  String get protocolName;

  /// Connect to device via serial port
  ///
  /// Returns true if connection and sync with bootloader succeeded.
  Future<bool> connect(
    SerialPort port, {
    int baudRate = 115200,
    FlashProgressCallback? onProgress,
  });

  /// Flash firmware to device
  ///
  /// [firmware] - The firmware binary data to flash
  /// [config] - Flash configuration from device definition
  /// [onProgress] - Progress callback for UI updates
  Future<void> flash(
    Uint8List firmware,
    FlashConfig config, {
    FlashProgressCallback? onProgress,
  });

  /// Verify flashed firmware
  ///
  /// Returns true if verification passed.
  Future<bool> verify({FlashProgressCallback? onProgress});

  /// Disconnect from device
  Future<void> disconnect();

  /// Reset device to run firmware
  Future<void> reset();

  /// Check if currently connected
  bool get isConnected;

  /// Get detected chip information (after connect)
  String? get chipInfo;
}

/// Flash operation exception
class FlashException implements Exception {
  final String message;
  final String? phase;
  final int? errorCode;

  const FlashException(this.message, {this.phase, this.errorCode});

  @override
  String toString() {
    if (phase != null) {
      return 'FlashException during $phase: $message (code: $errorCode)';
    }
    return 'FlashException: $message';
  }
}

/// Connection failed exception
class ConnectionException extends FlashException {
  const ConnectionException(String message, {int? errorCode})
      : super(message, phase: 'connection', errorCode: errorCode);
}

/// Sync with bootloader failed exception
class SyncException extends FlashException {
  const SyncException(String message, {int? errorCode})
      : super(message, phase: 'sync', errorCode: errorCode);
}

/// Erase failed exception
class EraseException extends FlashException {
  const EraseException(String message, {int? errorCode})
      : super(message, phase: 'erase', errorCode: errorCode);
}

/// Write failed exception
class WriteException extends FlashException {
  const WriteException(String message, {int? errorCode})
      : super(message, phase: 'write', errorCode: errorCode);
}

/// Verify failed exception
class VerifyException extends FlashException {
  const VerifyException(String message, {int? errorCode})
      : super(message, phase: 'verify', errorCode: errorCode);
}

/// Chip mismatch exception — firmware target chip doesn't match hardware
class ChipMismatchException extends FlashException {
  final String firmwareChip;
  final String detectedChip;

  const ChipMismatchException({
    required this.firmwareChip,
    required this.detectedChip,
  }) : super(
    'Firmware is built for $firmwareChip but the connected device is $detectedChip',
    phase: 'compatibility check',
  );
}
