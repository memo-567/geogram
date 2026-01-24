import 'dart:io';
import 'dart:typed_data';

import 'serial_port.dart';

/// Native serial port detection using OS facilities
///
/// No external libraries required - uses:
/// - Linux: /sys/class/tty and /dev/ttyUSB*, /dev/ttyACM*
/// - macOS: /dev/cu.* and ioreg
/// - Windows: registry (limited support)
class NativeSerialPortDetector {
  /// List available serial ports using native OS facilities
  static Future<List<PortInfo>> listPorts() async {
    if (Platform.isLinux) {
      return _listPortsLinux();
    } else if (Platform.isMacOS) {
      return _listPortsMacOS();
    } else if (Platform.isWindows) {
      return _listPortsWindows();
    }
    return [];
  }

  /// Linux: Read from /sys/class/tty to find USB serial ports
  static Future<List<PortInfo>> _listPortsLinux() async {
    final ports = <PortInfo>[];

    // Check for ttyUSB* and ttyACM* devices
    final devDir = Directory('/dev');
    if (!await devDir.exists()) return ports;

    await for (final entity in devDir.list()) {
      final name = entity.path.split('/').last;
      if (name.startsWith('ttyUSB') || name.startsWith('ttyACM')) {
        final info = await _getLinuxPortInfo(entity.path, name);
        if (info != null) {
          ports.add(info);
        }
      }
    }

    return ports;
  }

  /// Get USB info for a Linux serial port from sysfs
  static Future<PortInfo?> _getLinuxPortInfo(String devPath, String name) async {
    try {
      final sysPath = '/sys/class/tty/$name';
      final sysDir = Directory(sysPath);

      if (!await sysDir.exists()) {
        return PortInfo(path: devPath);
      }

      // Follow device symlink to find USB device info
      final deviceLink = Link('$sysPath/device');
      if (!await deviceLink.exists()) {
        return PortInfo(path: devPath);
      }

      // Resolve the device path
      final devicePath = await deviceLink.resolveSymbolicLinks();

      // Navigate up to find the USB device
      String? vid, pid, manufacturer, product, serial;

      // Try to find USB info by walking up the device tree
      var currentPath = devicePath;
      for (var i = 0; i < 10; i++) {
        // Check for idVendor file (indicates USB device)
        final vidFile = File('$currentPath/idVendor');
        if (await vidFile.exists()) {
          vid = (await vidFile.readAsString()).trim();

          final pidFile = File('$currentPath/idProduct');
          if (await pidFile.exists()) {
            pid = (await pidFile.readAsString()).trim();
          }

          final mfrFile = File('$currentPath/manufacturer');
          if (await mfrFile.exists()) {
            manufacturer = (await mfrFile.readAsString()).trim();
          }

          final prodFile = File('$currentPath/product');
          if (await prodFile.exists()) {
            product = (await prodFile.readAsString()).trim();
          }

          final serialFile = File('$currentPath/serial');
          if (await serialFile.exists()) {
            serial = (await serialFile.readAsString()).trim();
          }

          break;
        }

        // Go up one directory
        final parent = Directory(currentPath).parent.path;
        if (parent == currentPath) break;
        currentPath = parent;
      }

      return PortInfo(
        path: devPath,
        description: product,
        vid: vid != null ? int.tryParse(vid, radix: 16) : null,
        pid: pid != null ? int.tryParse(pid, radix: 16) : null,
        manufacturer: manufacturer,
        product: product,
        serialNumber: serial,
      );
    } catch (e) {
      return PortInfo(path: devPath);
    }
  }

  /// macOS: List serial ports from /dev
  static Future<List<PortInfo>> _listPortsMacOS() async {
    final ports = <PortInfo>[];

    final devDir = Directory('/dev');
    if (!await devDir.exists()) return ports;

    await for (final entity in devDir.list()) {
      final name = entity.path.split('/').last;
      // Look for cu.* devices (callout devices, preferred for serial)
      if (name.startsWith('cu.usb') || name.startsWith('cu.wchusbserial')) {
        final info = await _getMacOSPortInfo(entity.path, name);
        ports.add(info);
      }
    }

    return ports;
  }

  /// Get USB info for a macOS serial port using ioreg
  static Future<PortInfo> _getMacOSPortInfo(String devPath, String name) async {
    try {
      // Use ioreg to get USB device info
      final result = await Process.run('ioreg', ['-r', '-c', 'IOUSBHostDevice', '-l']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Parse ioreg output to find matching device
        // This is a simplified parser - full implementation would parse the tree
        int? vid, pid;
        String? manufacturer, product, serial;

        final lines = output.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('"idVendor"')) {
            final match = RegExp(r'"idVendor"\s*=\s*(\d+)').firstMatch(line);
            if (match != null) vid = int.tryParse(match.group(1)!);
          }
          if (line.contains('"idProduct"')) {
            final match = RegExp(r'"idProduct"\s*=\s*(\d+)').firstMatch(line);
            if (match != null) pid = int.tryParse(match.group(1)!);
          }
          if (line.contains('"USB Vendor Name"')) {
            final match = RegExp(r'"USB Vendor Name"\s*=\s*"([^"]*)"').firstMatch(line);
            if (match != null) manufacturer = match.group(1);
          }
          if (line.contains('"USB Product Name"')) {
            final match = RegExp(r'"USB Product Name"\s*=\s*"([^"]*)"').firstMatch(line);
            if (match != null) product = match.group(1);
          }
        }

        return PortInfo(
          path: devPath,
          description: product,
          vid: vid,
          pid: pid,
          manufacturer: manufacturer,
          product: product,
          serialNumber: serial,
        );
      }
    } catch (e) {
      // Ignore errors
    }

    return PortInfo(path: devPath);
  }

  /// Windows: List COM ports from registry
  static Future<List<PortInfo>> _listPortsWindows() async {
    final ports = <PortInfo>[];

    try {
      // Use PowerShell to query COM ports
      final result = await Process.run('powershell', [
        '-Command',
        'Get-WmiObject Win32_SerialPort | Select-Object DeviceID, Description, PNPDeviceID | ConvertTo-Json'
      ]);

      if (result.exitCode == 0) {
        // Parse JSON output
        // This is simplified - full implementation would parse the JSON
        final output = result.stdout as String;
        if (output.isNotEmpty) {
          // Extract COM port info from PowerShell output
          final comPorts = RegExp(r'COM\d+').allMatches(output);
          for (final match in comPorts) {
            ports.add(PortInfo(path: match.group(0)!));
          }
        }
      }
    } catch (e) {
      // Fallback: try to enumerate COM ports directly
      for (var i = 1; i <= 20; i++) {
        final port = 'COM$i';
        // Could try to open each port to see if it exists
        // but that's invasive - just list common ones
      }
    }

    return ports;
  }
}

/// Native serial port implementation for Linux using termios
///
/// Opens and controls serial ports using POSIX terminal I/O
class NativeSerialPort implements SerialPort {
  RandomAccessFile? _file;
  String? _path;
  bool _dtr = false;
  bool _rts = false;

  @override
  Future<bool> open(String path, int baudRate) async {
    try {
      _file = await File(path).open(mode: FileMode.writeOnlyAppend);
      _path = path;

      // Configure port using stty command
      await _configurePort(path, baudRate);

      return true;
    } catch (e) {
      print('Failed to open port $path: $e');
      return false;
    }
  }

  Future<void> _configurePort(String path, int baudRate) async {
    if (Platform.isLinux || Platform.isMacOS) {
      // Use stty to configure the port
      await Process.run('stty', [
        '-F', path,
        '$baudRate',      // Baud rate
        'cs8',            // 8 data bits
        '-cstopb',        // 1 stop bit
        '-parenb',        // No parity
        'raw',            // Raw mode
        '-echo',          // No echo
        '-echoe',
        '-echok',
      ]);
    }
  }

  @override
  Future<Uint8List> read(int maxBytes, {Duration? timeout}) async {
    if (_file == null || _path == null) {
      throw SerialPortException('Port not open');
    }

    try {
      // Open for reading separately
      final readFile = await File(_path!).open(mode: FileMode.read);
      try {
        final buffer = Uint8List(maxBytes);
        final bytesRead = await readFile.readInto(buffer);
        return buffer.sublist(0, bytesRead);
      } finally {
        await readFile.close();
      }
    } catch (e) {
      return Uint8List(0);
    }
  }

  @override
  Future<int> write(Uint8List data) async {
    if (_file == null) {
      throw SerialPortException('Port not open');
    }

    await _file!.writeFrom(data);
    return data.length;
  }

  @override
  Future<void> close() async {
    if (_file != null) {
      await _file!.close();
      _file = null;
      _path = null;
    }
  }

  @override
  void setDTR(bool value) {
    _dtr = value;
    // On Linux, we could use ioctl to set DTR
    // For now, this is a stub
  }

  @override
  void setRTS(bool value) {
    _rts = value;
    // On Linux, we could use ioctl to set RTS
    // For now, this is a stub
  }

  @override
  bool get dtr => _dtr;

  @override
  bool get rts => _rts;

  @override
  bool get isOpen => _file != null;

  @override
  String? get path => _path;

  @override
  Future<void> flush() async {
    await _file?.flush();
  }

  @override
  Future<void> setBaudRate(int baudRate) async {
    if (_path != null) {
      await _configurePort(_path!, baudRate);
    }
  }
}
