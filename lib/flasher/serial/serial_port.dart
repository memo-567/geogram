import 'dart:typed_data';

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
  String? get vidHex => vid != null ? '0x${vid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  /// Get PID as hex string
  String? get pidHex => pid != null ? '0x${pid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  /// Get display name for port
  String get displayName {
    if (product != null) return '$path ($product)';
    if (description != null) return '$path ($description)';
    return path;
  }

  @override
  String toString() => 'PortInfo($path, vid=$vidHex, pid=$pidHex)';
}

/// Abstract serial port interface
///
/// Platform-specific implementations provide actual serial communication.
abstract class SerialPort {
  /// Open the port with specified baud rate
  Future<bool> open(String path, int baudRate);

  /// Read up to [maxBytes] bytes from the port
  ///
  /// Returns an empty list if no data is available within timeout.
  Future<Uint8List> read(int maxBytes, {Duration? timeout});

  /// Write data to the port
  ///
  /// Returns the number of bytes written.
  Future<int> write(Uint8List data);

  /// Close the port
  Future<void> close();

  /// Set DTR (Data Terminal Ready) signal
  void setDTR(bool value);

  /// Set RTS (Request To Send) signal
  void setRTS(bool value);

  /// Get DTR state
  bool get dtr;

  /// Get RTS state
  bool get rts;

  /// Check if port is open
  bool get isOpen;

  /// Get the port path
  String? get path;

  /// Flush input and output buffers
  Future<void> flush();

  /// Set baud rate
  Future<void> setBaudRate(int baudRate);

  /// List available serial ports
  static Future<List<PortInfo>> listPorts() async {
    // This should be overridden by platform-specific implementations
    throw UnimplementedError('listPorts() must be implemented by platform');
  }
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
  String toString() => 'SerialTimeoutException: $message (timeout: ${timeout.inMilliseconds}ms)';
}
