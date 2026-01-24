import 'dart:io';
import 'dart:typed_data';

import 'native_serial_linux.dart';

// Android implementation uses Flutter's MethodChannel which requires dart:ui
// Use conditional import: stub for pure Dart CLI, real impl for Flutter
import 'native_serial_android_stub.dart'
    if (dart.library.ui) 'native_serial_android.dart';

/// Serial port information
class PortInfo {
  /// Device path (e.g., /dev/ttyUSB0, COM3) or Android device name
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

/// Cross-platform serial port implementation
///
/// Uses native platform APIs without requiring third-party library installations:
/// - **Android**: Android USB Host API (built into Android SDK)
/// - **Linux**: libc termios (built into Linux kernel)
/// - **macOS**: libc termios (built into macOS) [TODO]
/// - **Windows**: kernel32 (built into Windows) [TODO]
class SerialPort {
  // Platform-specific implementation
  NativeSerialLinux? _linuxPort;
  String? _androidDeviceName;

  String? _path;
  bool _dtr = false;
  bool _rts = false;

  /// List available serial ports with USB info
  static Future<List<PortInfo>> listPorts() async {
    if (Platform.isAndroid) {
      return _listPortsAndroid();
    } else if (Platform.isLinux) {
      return _listPortsLinux();
    } else if (Platform.isMacOS) {
      // TODO: Implement macOS support
      return [];
    } else if (Platform.isWindows) {
      // TODO: Implement Windows support
      return [];
    }
    return [];
  }

  static Future<List<PortInfo>> _listPortsAndroid() async {
    try {
      final devices = await NativeSerialAndroid.listDevices();
      return devices.map((d) {
        return PortInfo(
          path: d['deviceName'] as String,
          vid: d['vendorId'] as int?,
          pid: d['productId'] as int?,
          manufacturer: d['manufacturerName'] as String?,
          product: d['productName'] as String?,
          serialNumber: d['serialNumber'] as String?,
          description: d['isEsp32'] == true ? 'ESP32 Device' : null,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<PortInfo>> _listPortsLinux() async {
    try {
      final linuxPorts = await NativeSerialLinux.listPorts();
      return linuxPorts.map((p) {
        return PortInfo(
          path: p.path,
          vid: p.vid,
          pid: p.pid,
          manufacturer: p.manufacturer,
          product: p.product,
          serialNumber: p.serialNumber,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Request permission for a USB device (Android only)
  ///
  /// On other platforms, returns true immediately.
  static Future<bool> requestPermission(String path) async {
    if (Platform.isAndroid) {
      return NativeSerialAndroid.requestPermission(path);
    }
    return true;
  }

  /// Check if we have permission for a USB device (Android only)
  ///
  /// On other platforms, returns true immediately.
  static Future<bool> hasPermission(String path) async {
    if (Platform.isAndroid) {
      return NativeSerialAndroid.hasPermission(path);
    }
    return true;
  }

  /// Open the port with specified baud rate
  Future<bool> open(String path, int baudRate) async {
    try {
      if (Platform.isAndroid) {
        // Check/request permission first
        if (!await NativeSerialAndroid.hasPermission(path)) {
          final granted = await NativeSerialAndroid.requestPermission(path);
          if (!granted) {
            throw SerialPortException('Permission denied', path: path);
          }
        }

        final success = await NativeSerialAndroid.open(path, baudRate: baudRate);
        if (success) {
          _androidDeviceName = path;
          _path = path;
          return true;
        }
        return false;
      } else if (Platform.isLinux) {
        _linuxPort = NativeSerialLinux();
        final success = await _linuxPort!.open(path, baudRate);
        if (success) {
          _path = path;
          return true;
        }
        _linuxPort = null;
        return false;
      } else {
        throw SerialPortException('Platform not supported');
      }
    } catch (e) {
      if (e is SerialPortException) rethrow;
      return false;
    }
  }

  /// Read up to [maxBytes] bytes from the port
  ///
  /// Returns an empty list if no data is available within timeout.
  Future<Uint8List> read(int maxBytes, {Duration? timeout}) async {
    final timeoutMs = timeout?.inMilliseconds ?? 1000;

    if (Platform.isAndroid && _androidDeviceName != null) {
      return NativeSerialAndroid.read(
        _androidDeviceName!,
        maxBytes: maxBytes,
        timeoutMs: timeoutMs,
      );
    } else if (Platform.isLinux && _linuxPort != null) {
      return _linuxPort!.read(maxBytes, timeoutMs: timeoutMs);
    }

    throw SerialPortException('Port not open');
  }

  /// Read with blocking timeout (simpler API for protocols)
  Future<Uint8List> readBytes(int count, {int timeoutMs = 1000}) async {
    if (Platform.isAndroid && _androidDeviceName != null) {
      // Accumulate data until we have enough or timeout
      final data = <int>[];
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

      while (data.length < count && DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now()).inMilliseconds;
        if (remaining <= 0) break;

        final chunk = await NativeSerialAndroid.read(
          _androidDeviceName!,
          maxBytes: count - data.length,
          timeoutMs: remaining,
        );
        data.addAll(chunk);
      }

      return Uint8List.fromList(data);
    } else if (Platform.isLinux && _linuxPort != null) {
      return _linuxPort!.readBytes(count, timeoutMs: timeoutMs);
    }

    throw SerialPortException('Port not open');
  }

  /// Write data to the port
  ///
  /// Returns the number of bytes written.
  Future<int> write(Uint8List data) async {
    if (Platform.isAndroid && _androidDeviceName != null) {
      return NativeSerialAndroid.write(_androidDeviceName!, data);
    } else if (Platform.isLinux && _linuxPort != null) {
      return _linuxPort!.write(data);
    }

    throw SerialPortException('Port not open');
  }

  /// Close the port
  Future<void> close() async {
    if (Platform.isAndroid && _androidDeviceName != null) {
      await NativeSerialAndroid.close(_androidDeviceName!);
      _androidDeviceName = null;
      _path = null;
    } else if (Platform.isLinux && _linuxPort != null) {
      await _linuxPort!.close();
      _linuxPort = null;
      _path = null;
    }
  }

  /// Set DTR (Data Terminal Ready) signal
  void setDTR(bool value) {
    _dtr = value;
    if (Platform.isAndroid && _androidDeviceName != null) {
      NativeSerialAndroid.setDTR(_androidDeviceName!, value);
    } else if (Platform.isLinux && _linuxPort != null) {
      _linuxPort!.setDTR(value);
    }
  }

  /// Set RTS (Request To Send) signal
  void setRTS(bool value) {
    _rts = value;
    if (Platform.isAndroid && _androidDeviceName != null) {
      NativeSerialAndroid.setRTS(_androidDeviceName!, value);
    } else if (Platform.isLinux && _linuxPort != null) {
      _linuxPort!.setRTS(value);
    }
  }

  /// Get DTR state
  bool get dtr => _dtr;

  /// Get RTS state
  bool get rts => _rts;

  /// Check if port is open
  bool get isOpen {
    if (Platform.isAndroid) {
      return _androidDeviceName != null;
    } else if (Platform.isLinux) {
      return _linuxPort?.isOpen ?? false;
    }
    return false;
  }

  /// Get the port path
  String? get path => _path;

  /// Flush input and output buffers
  Future<void> flush() async {
    if (Platform.isAndroid && _androidDeviceName != null) {
      await NativeSerialAndroid.flush(_androidDeviceName!);
    } else if (Platform.isLinux && _linuxPort != null) {
      await _linuxPort!.flush();
    }
  }

  /// Set baud rate
  Future<void> setBaudRate(int baudRate) async {
    if (Platform.isAndroid && _androidDeviceName != null) {
      await NativeSerialAndroid.setBaudRate(_androidDeviceName!, baudRate);
    } else if (Platform.isLinux && _linuxPort != null) {
      await _linuxPort!.setBaudRate(baudRate);
    }
  }

  /// Drain output buffer (wait for all data to be sent)
  Future<void> drain() async {
    if (Platform.isLinux && _linuxPort != null) {
      await _linuxPort!.drain();
    }
    // Android USB doesn't have explicit drain, writes are synchronous to USB buffer
  }
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
