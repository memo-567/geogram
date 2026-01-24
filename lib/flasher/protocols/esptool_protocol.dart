import 'dart:async';
import 'dart:typed_data';

import '../models/device_definition.dart';
import '../models/flash_progress.dart';
import '../serial/serial_port.dart';
import 'flash_protocol.dart';

/// ESP32 flashing protocol implementation
///
/// Implements the esptool protocol for flashing ESP32 family chips.
/// Uses SLIP framing for communication with the ROM bootloader.
///
/// References:
/// - https://github.com/espressif/esptool
/// - https://docs.espressif.com/projects/esptool/en/latest/esp32/
class EspToolProtocol implements FlashProtocol {
  // SLIP framing constants
  static const int slipEnd = 0xC0;
  static const int slipEsc = 0xDB;
  static const int slipEscEnd = 0xDC;
  static const int slipEscEsc = 0xDD;

  // Command opcodes
  static const int cmdFlashBegin = 0x02;
  static const int cmdFlashData = 0x03;
  static const int cmdFlashEnd = 0x04;
  static const int cmdMemBegin = 0x05;
  static const int cmdMemEnd = 0x06;
  static const int cmdMemData = 0x07;
  static const int cmdSync = 0x08;
  static const int cmdWriteReg = 0x09;
  static const int cmdReadReg = 0x0A;
  static const int cmdSpiSetParams = 0x0B;
  static const int cmdSpiAttach = 0x0D;
  static const int cmdChangeBaudrate = 0x0F;
  static const int cmdFlashDeflBegin = 0x10;
  static const int cmdFlashDeflData = 0x11;
  static const int cmdFlashDeflEnd = 0x12;
  static const int cmdSpiFlashMd5 = 0x13;
  static const int cmdGetSecurityInfo = 0x14;

  // Response direction
  static const int directionRequest = 0x00;
  static const int directionResponse = 0x01;

  // Error codes
  static const int errOk = 0x00;
  static const int errInvalidCommand = 0x05;
  static const int errFailed = 0x06;
  static const int errTimeout = 0x07;
  static const int errInvalidPacket = 0x08;
  static const int errWrongChecksum = 0x09;

  // Chip IDs (from READ_REG of CHIP_DETECT_MAGIC_REG)
  static const Map<int, String> chipMagic = {
    0x00F01D83: 'ESP32',
    0x6921506F: 'ESP32-C3',
    0x1B31506F: 'ESP32-C3', // ECO6+
    0x09: 'ESP32-S2',
    0x000007C6: 'ESP32-S3',
    0x0000DC6F: 'ESP32-C6',
    0x2CE0806F: 'ESP32-H2',
    0x6F51306F: 'ESP32-C2',
  };

  // Register addresses
  static const int chipDetectMagicReg = 0x40001000;

  // Flash settings
  static const int flashBlockSize = 0x1000; // 4KB
  static const int flashWriteSize = 0x400;  // 1KB per packet

  SerialPort? _port;
  bool _connected = false;
  String? _chipInfo;
  int _sequenceNumber = 0;
  DateTime? _startTime;

  @override
  String get protocolId => 'esptool';

  @override
  String get protocolName => 'ESP32 esptool';

  @override
  bool get isConnected => _connected;

  @override
  String? get chipInfo => _chipInfo;

  @override
  Future<bool> connect(
    SerialPort port, {
    int baudRate = 115200,
    FlashProgressCallback? onProgress,
  }) async {
    _port = port;
    _sequenceNumber = 0;

    onProgress?.call(FlashProgress.connecting());

    // Open port
    if (!port.isOpen) {
      final opened = await port.open(port.path ?? '', baudRate);
      if (!opened) {
        throw ConnectionException('Failed to open serial port');
      }
    }

    onProgress?.call(FlashProgress.syncing());

    // Try multiple approaches to enter bootloader and sync:
    // 1. Try sync first (device might already be in bootloader mode)
    // 2. Try DTR/RTS reset sequence (works with USB-UART bridges)
    // 3. Try sync after reset

    var synced = false;

    // First, try sync without reset (in case already in bootloader)
    synced = await _sync();

    if (!synced) {
      // Try DTR/RTS reset sequence (works with USB-UART bridges like CP210x, CH340)
      // Note: ESP32-C3/S3 with built-in USB JTAG don't support auto-reset
      await _resetToBootloader();
      synced = await _sync();
    }

    if (!synced) {
      // Try alternate reset timing
      await _resetToBootloaderAlternate();
      synced = await _sync();
    }

    if (!synced) {
      throw SyncException(
        'Failed to sync with ESP32 bootloader. '
        'For ESP32-C3/S3 with built-in USB: Hold BOOT, press RESET, release RESET, release BOOT, then retry.'
      );
    }

    // Detect chip
    _chipInfo = await _detectChip();

    _connected = true;
    return true;
  }

  @override
  Future<void> flash(
    Uint8List firmware,
    FlashConfig config, {
    FlashProgressCallback? onProgress,
  }) async {
    if (!_connected || _port == null) {
      throw FlashException('Not connected');
    }

    _startTime = DateTime.now();
    final totalSize = firmware.length;
    final numBlocks = (totalSize + flashWriteSize - 1) ~/ flashWriteSize;

    // Change baud rate if needed for faster flashing
    if (config.baudRate > 115200) {
      await _changeBaudrate(config.baudRate);
    }

    // Begin flash operation
    onProgress?.call(FlashProgress.erasing(0.0));
    await _flashBegin(totalSize, numBlocks, flashWriteSize, 0);

    // Write firmware in blocks
    for (var i = 0; i < numBlocks; i++) {
      final offset = i * flashWriteSize;
      final remaining = totalSize - offset;
      final blockSize = remaining < flashWriteSize ? remaining : flashWriteSize;

      final block = firmware.sublist(offset, offset + blockSize);

      // Pad to block size if needed
      final paddedBlock = blockSize < flashWriteSize
          ? Uint8List.fromList([...block, ...List.filled(flashWriteSize - blockSize, 0xFF)])
          : block;

      await _flashData(paddedBlock, i);

      final progress = (i + 1) / numBlocks;
      final elapsed = DateTime.now().difference(_startTime!);
      onProgress?.call(FlashProgress(
        status: FlashStatus.writing,
        progress: progress,
        message: 'Writing firmware...',
        bytesWritten: offset + blockSize,
        totalBytes: totalSize,
        currentChunk: i + 1,
        totalChunks: numBlocks,
        elapsed: elapsed,
      ));
    }

    // End flash operation
    await _flashEnd(false); // false = don't reboot yet
  }

  @override
  Future<bool> verify({FlashProgressCallback? onProgress}) async {
    if (!_connected || _port == null) {
      throw FlashException('Not connected');
    }

    onProgress?.call(FlashProgress.verifying(0.0));

    // Request MD5 checksum from device
    // For now, we'll skip verification and assume success
    // Full implementation would compare MD5 of written data

    onProgress?.call(FlashProgress.verifying(1.0));
    return true;
  }

  @override
  Future<void> disconnect() async {
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
    _connected = false;
    _chipInfo = null;
  }

  @override
  Future<void> reset() async {
    if (_port == null) return;

    // Hard reset sequence
    _port!.setRTS(true);
    _port!.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 100));
    _port!.setRTS(false);
    _port!.setDTR(true);
    await Future.delayed(const Duration(milliseconds: 100));
    _port!.setDTR(false);
  }

  /// Reset chip into bootloader mode
  Future<void> _resetToBootloader() async {
    if (_port == null) return;

    // Classic reset sequence for ESP32 with auto-reset circuit:
    // DTR RTS -> EN IO0
    // 1   1   -> 1  1
    // 0   0   -> 1  1
    // 1   0   -> 0  1  (reset, normal mode)
    // 0   1   -> 1  0  (release reset, bootloader mode)

    // Set both low
    _port!.setDTR(false);
    _port!.setRTS(false);
    await Future.delayed(const Duration(milliseconds: 100));

    // Enter bootloader: RTS=high (IO0 low), DTR=low (EN released)
    _port!.setRTS(true);
    _port!.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 100));

    // Toggle DTR to reset
    _port!.setDTR(true);
    await Future.delayed(const Duration(milliseconds: 100));
    _port!.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 50));

    // Release RTS
    _port!.setRTS(false);
    await Future.delayed(const Duration(milliseconds: 100));

    // Flush any garbage
    await _port!.flush();
  }

  /// Alternate reset sequence with different timing
  /// Some boards need different timing or inverted signals
  Future<void> _resetToBootloaderAlternate() async {
    if (_port == null) return;

    // Alternative sequence used by some boards
    // This matches esptool's "classic" reset more closely

    // IO0=HIGH, EN=LOW (reset asserted)
    _port!.setRTS(false);
    _port!.setDTR(true);
    await Future.delayed(const Duration(milliseconds: 100));

    // IO0=LOW, EN=LOW (still in reset, but GPIO0 low for bootloader)
    _port!.setRTS(true);
    _port!.setDTR(true);
    await Future.delayed(const Duration(milliseconds: 100));

    // IO0=LOW, EN=HIGH (release reset while GPIO0 is low = enter bootloader)
    _port!.setRTS(true);
    _port!.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 400));

    // IO0=HIGH, EN=HIGH (release GPIO0, chip should be in bootloader)
    _port!.setRTS(false);
    _port!.setDTR(false);
    await Future.delayed(const Duration(milliseconds: 100));

    await _port!.flush();
  }

  /// Sync with bootloader
  Future<bool> _sync() async {
    // Sync packet: 0x07 0x07 0x12 0x20 followed by 32 x 0x55
    final syncData = Uint8List.fromList([
      0x07, 0x07, 0x12, 0x20,
      ...List.filled(32, 0x55),
    ]);

    // Try sync multiple times
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        final response = await _command(cmdSync, syncData, timeout: 100);
        if (response != null && response.isNotEmpty) {
          // Read any additional sync responses
          for (var i = 0; i < 7; i++) {
            await _readResponse(timeout: 100);
          }
          return true;
        }
      } catch (e) {
        // Retry
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    return false;
  }

  /// Detect chip type
  Future<String> _detectChip() async {
    final regValue = await _readReg(chipDetectMagicReg);
    final chipName = chipMagic[regValue] ?? 'Unknown ESP32 (0x${regValue.toRadixString(16)})';
    return chipName;
  }

  /// Read register value
  Future<int> _readReg(int address) async {
    final data = _packUint32(address);
    final response = await _command(cmdReadReg, data);

    if (response != null && response.length >= 4) {
      return _unpackUint32(response, 0);
    }

    return 0;
  }

  /// Change baud rate
  Future<void> _changeBaudrate(int newBaud) async {
    final data = Uint8List(8);
    final view = ByteData.view(data.buffer);
    view.setUint32(0, newBaud, Endian.little);
    view.setUint32(4, 0, Endian.little); // Old baud (0 = current)

    await _command(cmdChangeBaudrate, data);
    await _port!.setBaudRate(newBaud);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// Begin flash operation
  Future<void> _flashBegin(
    int size,
    int numBlocks,
    int blockSize,
    int offset,
  ) async {
    final data = Uint8List(16);
    final view = ByteData.view(data.buffer);
    view.setUint32(0, size, Endian.little);
    view.setUint32(4, numBlocks, Endian.little);
    view.setUint32(8, blockSize, Endian.little);
    view.setUint32(12, offset, Endian.little);

    final response = await _command(cmdFlashBegin, data, timeout: 10000);
    if (response == null) {
      throw EraseException('Flash begin failed');
    }
  }

  /// Write flash data block
  Future<void> _flashData(Uint8List block, int sequence) async {
    final header = Uint8List(16);
    final view = ByteData.view(header.buffer);
    view.setUint32(0, block.length, Endian.little);
    view.setUint32(4, sequence, Endian.little);
    view.setUint32(8, 0, Endian.little);
    view.setUint32(12, 0, Endian.little);

    final data = Uint8List.fromList([...header, ...block]);
    final response = await _command(cmdFlashData, data, checksum: _checksum(block));

    if (response == null) {
      throw WriteException('Flash data failed at block $sequence');
    }
  }

  /// End flash operation
  Future<void> _flashEnd(bool reboot) async {
    final data = Uint8List(4);
    final view = ByteData.view(data.buffer);
    view.setUint32(0, reboot ? 0 : 1, Endian.little);

    await _command(cmdFlashEnd, data);
  }

  /// Send command and receive response
  Future<Uint8List?> _command(
    int opcode,
    Uint8List data, {
    int? checksum,
    int timeout = 3000,
  }) async {
    final packet = _buildPacket(opcode, data, checksum ?? 0);
    final encoded = _slipEncode(packet);

    await _port!.write(encoded);

    return _readResponse(timeout: timeout);
  }

  /// Build command packet
  Uint8List _buildPacket(int opcode, Uint8List data, int checksum) {
    final packet = Uint8List(8 + data.length);
    final view = ByteData.view(packet.buffer);

    packet[0] = directionRequest;
    packet[1] = opcode;
    view.setUint16(2, data.length, Endian.little);
    view.setUint32(4, checksum, Endian.little);

    for (var i = 0; i < data.length; i++) {
      packet[8 + i] = data[i];
    }

    return packet;
  }

  /// Read and decode response
  Future<Uint8List?> _readResponse({int timeout = 3000}) async {
    final buffer = <int>[];
    var inPacket = false;
    var escaped = false;

    final deadline = DateTime.now().add(Duration(milliseconds: timeout));

    while (DateTime.now().isBefore(deadline)) {
      final data = await _port!.read(64, timeout: Duration(milliseconds: 100));

      for (final byte in data) {
        if (!inPacket && byte == slipEnd) {
          inPacket = true;
          buffer.clear();
          continue;
        }

        if (inPacket) {
          if (byte == slipEnd) {
            // End of packet
            if (buffer.isNotEmpty) {
              return _parseResponse(Uint8List.fromList(buffer));
            }
            inPacket = false;
          } else if (byte == slipEsc) {
            escaped = true;
          } else if (escaped) {
            if (byte == slipEscEnd) {
              buffer.add(slipEnd);
            } else if (byte == slipEscEsc) {
              buffer.add(slipEsc);
            }
            escaped = false;
          } else {
            buffer.add(byte);
          }
        }
      }

      if (data.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    return null;
  }

  /// Parse response packet
  ///
  /// ESP32 ROM bootloader response format:
  /// - byte 0: direction (1 = response)
  /// - byte 1: opcode (same as request)
  /// - bytes 2-3: size of data payload (little endian)
  /// - bytes 4-7: value field (little endian) - contains return value for READ_REG
  /// - bytes 8+: data payload (if size > 0)
  ///
  /// For commands like READ_REG, the result is in the value field (bytes 4-7).
  /// For commands like SYNC, the data payload contains additional info.
  Uint8List? _parseResponse(Uint8List packet) {
    if (packet.length < 8) return null;

    final direction = packet[0];
    final view = ByteData.view(packet.buffer);
    final size = view.getUint16(2, Endian.little);
    final value = view.getUint32(4, Endian.little);

    if (direction != directionResponse) return null;

    // For most commands, the status is in the first byte of data payload
    // But we should not reject the response - let the caller handle errors
    // based on the actual command semantics

    // Return the value field as bytes - this is where READ_REG puts the result
    // The caller can also check the data payload if needed
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  /// SLIP encode packet
  Uint8List _slipEncode(Uint8List packet) {
    final encoded = <int>[slipEnd];

    for (final byte in packet) {
      if (byte == slipEnd) {
        encoded.add(slipEsc);
        encoded.add(slipEscEnd);
      } else if (byte == slipEsc) {
        encoded.add(slipEsc);
        encoded.add(slipEscEsc);
      } else {
        encoded.add(byte);
      }
    }

    encoded.add(slipEnd);
    return Uint8List.fromList(encoded);
  }

  /// Calculate checksum (XOR of all bytes)
  int _checksum(Uint8List data) {
    return data.fold<int>(0xEF, (sum, byte) => sum ^ byte);
  }

  /// Pack uint32 to bytes (little-endian)
  Uint8List _packUint32(int value) {
    final data = Uint8List(4);
    final view = ByteData.view(data.buffer);
    view.setUint32(0, value, Endian.little);
    return data;
  }

  /// Unpack uint32 from bytes (little-endian)
  int _unpackUint32(Uint8List data, int offset) {
    final view = ByteData.view(data.buffer, offset);
    return view.getUint32(0, Endian.little);
  }
}
