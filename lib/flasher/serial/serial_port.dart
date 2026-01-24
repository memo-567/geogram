import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart' as libsp;

/// Serial port information
class PortInfo {
  /// Device path (e.g., /dev/ttyUSB0, COM3)
  final String path;

  /// Human-readable description
  final String? description;

  /// USB Vendor ID
  final int? vid;

  /// USB Product ID
  final int? pid;

  /// Manufacturer name
  final String? manufacturer;

  /// Product name
  final String? product;

  /// Serial number
  final String? serialNumber;

  const PortInfo({
    required this.path,
    this.description,
    this.vid,
    this.pid,
    this.manufacturer,
    this.product,
    this.serialNumber,
  });

  /// Get VID as hex string
  String? get vidHex =>
      vid != null ? '0x${vid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  /// Get PID as hex string
  String? get pidHex =>
      pid != null ? '0x${pid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  /// Get display name for port
  String get displayName {
    if (product != null) return '$path ($product)';
    if (description != null) return '$path ($description)';
    return path;
  }

  @override
  String toString() => 'PortInfo($path, vid=$vidHex, pid=$pidHex)';
}

/// Serial port exception
class SerialPortException implements Exception {
  final String message;
  final String? path;
  final int? errorCode;

  const SerialPortException(this.message, {this.path, this.errorCode});

  @override
  String toString() {
    if (path != null) {
      return 'SerialPortException: $message (port: $path, code: $errorCode)';
    }
    return 'SerialPortException: $message';
  }
}

/// Serial port timeout exception
class SerialTimeoutException extends SerialPortException {
  final Duration timeout;

  const SerialTimeoutException(String message, this.timeout, {String? path})
      : super(message, path: path);

  @override
  String toString() =>
      'SerialTimeoutException: $message (timeout: ${timeout.inMilliseconds}ms)';
}

/// Serial port wrapper using flutter_libserialport
///
/// Provides cross-platform USB serial communication for:
/// - Linux
/// - macOS
/// - Windows
/// - Android (USB OTG)
///
/// The native library is bundled automatically by Flutter's build system.
class SerialPort {
  libsp.SerialPort? _port;
  libsp.SerialPortReader? _reader;
  String? _path;
  bool _dtr = false;
  bool _rts = false;

  /// List available serial ports with USB info
  static Future<List<PortInfo>> listPorts() async {
    final ports = <PortInfo>[];

    try {
      final names = libsp.SerialPort.availablePorts;

      for (final name in names) {
        final port = libsp.SerialPort(name);
        try {
          ports.add(PortInfo(
            path: name,
            description: port.description,
            vid: port.vendorId,
            pid: port.productId,
            manufacturer: port.manufacturer,
            product: port.productName,
            serialNumber: port.serialNumber,
          ));
        } finally {
          port.dispose();
        }
      }
    } catch (e) {
      // Return empty list on error (e.g., library not available)
    }

    return ports;
  }

  /// Open the port with specified baud rate
  Future<bool> open(String path, int baudRate) async {
    try {
      _port = libsp.SerialPort(path);

      if (!_port!.openReadWrite()) {
        final error = libsp.SerialPort.lastError;
        throw SerialPortException(
          'Failed to open port: ${error?.message ?? "unknown error"}',
          path: path,
        );
      }

      _path = path;

      // Configure port
      final config = libsp.SerialPortConfig();
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = libsp.SerialPortParity.none;
      config.setFlowControl(libsp.SerialPortFlowControl.none);
      _port!.config = config;
      config.dispose();

      // Create reader for async reads
      _reader = libsp.SerialPortReader(_port!);

      return true;
    } catch (e) {
      if (_port != null) {
        _port!.dispose();
        _port = null;
      }
      return false;
    }
  }

  /// Read up to [maxBytes] bytes from the port
  ///
  /// Returns an empty list if no data is available within timeout.
  Future<Uint8List> read(int maxBytes, {Duration? timeout}) async {
    if (_port == null || _reader == null) {
      throw SerialPortException('Port not open');
    }

    final timeoutDuration = timeout ?? const Duration(seconds: 1);

    try {
      final stream = _reader!.stream.timeout(
        timeoutDuration,
        onTimeout: (sink) => sink.close(),
      );

      final data = <int>[];
      await for (final chunk in stream) {
        data.addAll(chunk);
        if (data.length >= maxBytes) break;
      }

      return Uint8List.fromList(data.take(maxBytes).toList());
    } catch (e) {
      return Uint8List(0);
    }
  }

  /// Read with blocking timeout (simpler API for protocols)
  Future<Uint8List> readBytes(int count, {int timeoutMs = 1000}) async {
    if (_port == null) {
      throw SerialPortException('Port not open');
    }

    try {
      final data = _port!.read(count, timeout: timeoutMs);
      return data;
    } catch (e) {
      return Uint8List(0);
    }
  }

  /// Write data to the port
  ///
  /// Returns the number of bytes written.
  Future<int> write(Uint8List data) async {
    if (_port == null) {
      throw SerialPortException('Port not open');
    }

    return _port!.write(data);
  }

  /// Close the port
  Future<void> close() async {
    _reader = null;

    if (_port != null) {
      _port!.close();
      _port!.dispose();
      _port = null;
      _path = null;
    }
  }

  /// Set DTR (Data Terminal Ready) signal
  void setDTR(bool value) {
    _dtr = value;
    if (_port != null) {
      final config = _port!.config;
      config.dtr = value ? libsp.SerialPortDtr.on : libsp.SerialPortDtr.off;
      _port!.config = config;
    }
  }

  /// Set RTS (Request To Send) signal
  void setRTS(bool value) {
    _rts = value;
    if (_port != null) {
      final config = _port!.config;
      config.rts = value ? libsp.SerialPortRts.on : libsp.SerialPortRts.off;
      _port!.config = config;
    }
  }

  /// Get DTR state
  bool get dtr => _dtr;

  /// Get RTS state
  bool get rts => _rts;

  /// Check if port is open
  bool get isOpen => _port != null && _port!.isOpen;

  /// Get the port path
  String? get path => _path;

  /// Flush input and output buffers
  Future<void> flush() async {
    if (_port != null) {
      _port!.flush();
    }
  }

  /// Set baud rate
  Future<void> setBaudRate(int baudRate) async {
    if (_port != null) {
      final config = _port!.config;
      config.baudRate = baudRate;
      _port!.config = config;
      config.dispose();
    }
  }

  /// Drain output buffer (wait for all data to be sent)
  Future<void> drain() async {
    if (_port != null) {
      _port!.drain();
    }
  }

  /// Get underlying port handle (for advanced operations)
  libsp.SerialPort? get handle => _port;
}

/// Known USB identifiers for ESP32 devices
class Esp32UsbIdentifiers {
  static const List<(int, int, String)> identifiers = [
    (0x303A, 0x1001, 'Espressif native USB (ESP32-C3/S2/S3)'),
    (0x303A, 0x0002, 'Espressif USB Bridge'),
    (0x10C4, 0xEA60, 'CP210x USB-UART'),
    (0x1A86, 0x7523, 'CH340 USB-UART'),
    (0x1A86, 0x55D4, 'CH9102 USB-UART'),
    (0x0403, 0x6001, 'FTDI FT232'),
    (0x0403, 0x6015, 'FTDI FT231X'),
  ];

  /// Check if a port matches known ESP32 identifiers
  static String? matchEsp32(PortInfo port) {
    if (port.vid == null || port.pid == null) return null;

    for (final (vid, pid, desc) in identifiers) {
      if (port.vid == vid && port.pid == pid) {
        return desc;
      }
    }
    return null;
  }

  /// Find all ESP32-compatible ports
  static Future<List<(PortInfo, String)>> findEsp32Ports() async {
    final ports = await SerialPort.listPorts();
    final matches = <(PortInfo, String)>[];

    for (final port in ports) {
      final desc = matchEsp32(port);
      if (desc != null) {
        matches.add((port, desc));
      }
    }

    return matches;
  }
}
