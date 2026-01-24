import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ============================================================================
// Linux Serial Port Implementation using libc termios
// ============================================================================
// This is a pure-Dart implementation using FFI to call libc functions.
// No external libraries required - libc is always present on Linux.
// ============================================================================

// -----------------------------------------------------------------------------
// Constants from fcntl.h
// -----------------------------------------------------------------------------
const O_RDWR = 0x0002;
const O_NOCTTY = 0x0100;
const O_NONBLOCK = 0x0800;

// -----------------------------------------------------------------------------
// Constants from termios.h (Linux x86_64)
// -----------------------------------------------------------------------------
const TCSANOW = 0;
const TCSADRAIN = 1;
const TCSAFLUSH = 2;

const TCIFLUSH = 0;
const TCOFLUSH = 1;
const TCIOFLUSH = 2;

// Input flags
const IGNBRK = 0x0001;
const BRKINT = 0x0002;
const IGNPAR = 0x0004;
const PARMRK = 0x0008;
const INPCK = 0x0010;
const ISTRIP = 0x0020;
const INLCR = 0x0040;
const IGNCR = 0x0080;
const ICRNL = 0x0100;
const IXON = 0x0400;
const IXOFF = 0x1000;
const IXANY = 0x0800;

// Output flags
const OPOST = 0x0001;

// Control flags
const CSIZE = 0x0030;
const CS5 = 0x0000;
const CS6 = 0x0010;
const CS7 = 0x0020;
const CS8 = 0x0030;
const CSTOPB = 0x0040;
const CREAD = 0x0080;
const PARENB = 0x0100;
const PARODD = 0x0200;
const HUPCL = 0x0400;
const CLOCAL = 0x0800;
const CRTSCTS = 0x80000000;

// Local flags
const ISIG = 0x0001;
const ICANON = 0x0002;
const ECHO = 0x0008;
const ECHOE = 0x0010;
const ECHOK = 0x0020;
const ECHONL = 0x0040;
const NOFLSH = 0x0080;
const IEXTEN = 0x8000;

// Special character indices
const VMIN = 6;
const VTIME = 5;

// IOCTL for DTR/RTS control
const TIOCMGET = 0x5415;
const TIOCMSET = 0x5418;
const TIOCMBIS = 0x5416; // Set bits
const TIOCMBIC = 0x5417; // Clear bits

const TIOCM_DTR = 0x002;
const TIOCM_RTS = 0x004;

// Baud rate constants (Linux termios2 style - actual baud value)
// For standard termios, we map to B* constants
const Map<int, int> _baudRateMap = {
  0: 0x0000, // B0
  50: 0x0001, // B50
  75: 0x0002, // B75
  110: 0x0003, // B110
  134: 0x0004, // B134
  150: 0x0005, // B150
  200: 0x0006, // B200
  300: 0x0007, // B300
  600: 0x0008, // B600
  1200: 0x0009, // B1200
  1800: 0x000A, // B1800
  2400: 0x000B, // B2400
  4800: 0x000C, // B4800
  9600: 0x000D, // B9600
  19200: 0x000E, // B19200
  38400: 0x000F, // B38400
  57600: 0x1001, // B57600
  115200: 0x1002, // B115200
  230400: 0x1003, // B230400
  460800: 0x1004, // B460800
  500000: 0x1005, // B500000
  576000: 0x1006, // B576000
  921600: 0x1007, // B921600
  1000000: 0x1008, // B1000000
  1152000: 0x1009, // B1152000
  1500000: 0x100A, // B1500000
  2000000: 0x100B, // B2000000
  2500000: 0x100C, // B2500000
  3000000: 0x100D, // B3000000
  3500000: 0x100E, // B3500000
  4000000: 0x100F, // B4000000
};

const CBAUD = 0x100F;
const CBAUDEX = 0x1000;

// -----------------------------------------------------------------------------
// Termios structure for Linux x86_64
// -----------------------------------------------------------------------------
// Must match kernel's struct termios (NOT termios2)
// See /usr/include/bits/termios.h
final class Termios extends Struct {
  @Uint32()
  external int c_iflag; // Input mode flags

  @Uint32()
  external int c_oflag; // Output mode flags

  @Uint32()
  external int c_cflag; // Control mode flags

  @Uint32()
  external int c_lflag; // Local mode flags

  @Uint8()
  external int c_line; // Line discipline

  @Array(32)
  external Array<Uint8> c_cc; // Control characters

  @Uint32()
  external int c_ispeed; // Input baud rate

  @Uint32()
  external int c_ospeed; // Output baud rate
}

// -----------------------------------------------------------------------------
// FFI function signatures
// -----------------------------------------------------------------------------

// File operations
typedef OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef OpenDart = int Function(Pointer<Utf8> path, int flags);

typedef CloseNative = Int32 Function(Int32 fd);
typedef CloseDart = int Function(int fd);

typedef ReadNative = IntPtr Function(Int32 fd, Pointer<Uint8> buf, IntPtr count);
typedef ReadDart = int Function(int fd, Pointer<Uint8> buf, int count);

typedef WriteNative = IntPtr Function(
    Int32 fd, Pointer<Uint8> buf, IntPtr count);
typedef WriteDart = int Function(int fd, Pointer<Uint8> buf, int count);

// Terminal control
typedef TcgetattrNative = Int32 Function(Int32 fd, Pointer<Termios> termios);
typedef TcgetattrDart = int Function(int fd, Pointer<Termios> termios);

typedef TcsetattrNative = Int32 Function(
    Int32 fd, Int32 action, Pointer<Termios> termios);
typedef TcsetattrDart = int Function(int fd, int action, Pointer<Termios> termios);

typedef TcflushNative = Int32 Function(Int32 fd, Int32 queue);
typedef TcflushDart = int Function(int fd, int queue);

typedef TcdrainNative = Int32 Function(Int32 fd);
typedef TcdrainDart = int Function(int fd);

typedef CfsetispeedNative = Int32 Function(
    Pointer<Termios> termios, Uint32 speed);
typedef CfsetispeedDart = int Function(Pointer<Termios> termios, int speed);

typedef CfsetospeedNative = Int32 Function(
    Pointer<Termios> termios, Uint32 speed);
typedef CfsetospeedDart = int Function(Pointer<Termios> termios, int speed);

// IOCTL for modem control
typedef IoctlIntNative = Int32 Function(
    Int32 fd, Uint64 request, Pointer<Int32> arg);
typedef IoctlIntDart = int Function(int fd, int request, Pointer<Int32> arg);

// Poll for non-blocking reads
typedef PollNative = Int32 Function(Pointer<Void> fds, Uint64 nfds, Int32 timeout);
typedef PollDart = int Function(Pointer<Void> fds, int nfds, int timeout);

// -----------------------------------------------------------------------------
// pollfd structure
// -----------------------------------------------------------------------------
final class PollFd extends Struct {
  @Int32()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

const POLLIN = 0x0001;

// -----------------------------------------------------------------------------
// Native Serial Port for Linux
// -----------------------------------------------------------------------------

class NativeSerialLinux {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  // Function pointers
  static late OpenDart _open;
  static late CloseDart _close;
  static late ReadDart _read;
  static late WriteDart _write;
  static late TcgetattrDart _tcgetattr;
  static late TcsetattrDart _tcsetattr;
  static late TcflushDart _tcflush;
  static late TcdrainDart _tcdrain;
  static late CfsetispeedDart _cfsetispeed;
  static late CfsetospeedDart _cfsetospeed;
  static late IoctlIntDart _ioctl;
  static late PollDart _poll;

  int? _fd;
  String? _path;
  bool _dtr = false;
  bool _rts = false;

  /// Check if libc is available
  static bool get isAvailable {
    if (!Platform.isLinux) return false;
    try {
      _loadLibrary();
      return true;
    } catch (e) {
      return false;
    }
  }

  static void _loadLibrary() {
    if (_lib != null) return;

    // libc.so.6 is present on every Linux system
    final paths = ['libc.so.6', 'libc.so'];
    for (final path in paths) {
      try {
        _lib = DynamicLibrary.open(path);
        return;
      } catch (e) {
        continue;
      }
    }
    throw UnsupportedError('Could not load libc');
  }

  static void _initialize() {
    if (_initialized) return;
    _loadLibrary();

    _open = _lib!.lookupFunction<OpenNative, OpenDart>('open');
    _close = _lib!.lookupFunction<CloseNative, CloseDart>('close');
    _read = _lib!.lookupFunction<ReadNative, ReadDart>('read');
    _write = _lib!.lookupFunction<WriteNative, WriteDart>('write');
    _tcgetattr = _lib!.lookupFunction<TcgetattrNative, TcgetattrDart>('tcgetattr');
    _tcsetattr = _lib!.lookupFunction<TcsetattrNative, TcsetattrDart>('tcsetattr');
    _tcflush = _lib!.lookupFunction<TcflushNative, TcflushDart>('tcflush');
    _tcdrain = _lib!.lookupFunction<TcdrainNative, TcdrainDart>('tcdrain');
    _cfsetispeed =
        _lib!.lookupFunction<CfsetispeedNative, CfsetispeedDart>('cfsetispeed');
    _cfsetospeed =
        _lib!.lookupFunction<CfsetospeedNative, CfsetospeedDart>('cfsetospeed');
    _ioctl = _lib!.lookupFunction<IoctlIntNative, IoctlIntDart>('ioctl');
    _poll = _lib!.lookupFunction<PollNative, PollDart>('poll');

    _initialized = true;
  }

  /// List available serial ports by scanning sysfs
  static Future<List<LinuxPortInfo>> listPorts() async {
    final ports = <LinuxPortInfo>[];

    // Scan for ttyACM* and ttyUSB* devices
    final ttyDir = Directory('/sys/class/tty');
    if (!ttyDir.existsSync()) return ports;

    for (final entry in ttyDir.listSync()) {
      final name = entry.path.split('/').last;

      // Only include USB serial devices
      if (!name.startsWith('ttyACM') && !name.startsWith('ttyUSB')) {
        continue;
      }

      final devicePath = '/dev/$name';
      final sysPath = entry.path;

      // Read USB info from sysfs
      int? vid;
      int? pid;
      String? manufacturer;
      String? product;
      String? serial;

      // Navigate to the USB device directory
      // /sys/class/tty/ttyACM0/device -> ../../tty/ttyACM0
      // The USB device is at /sys/class/tty/ttyACM0/device/../..
      final usbDevicePaths = [
        '$sysPath/device/../idVendor',
        '$sysPath/device/../../idVendor',
        '$sysPath/../idVendor',
      ];

      for (final basePath in usbDevicePaths) {
        final baseDir = basePath.replaceAll('/idVendor', '');
        final vidFile = File('$baseDir/idVendor');
        if (vidFile.existsSync()) {
          try {
            vid = int.tryParse(vidFile.readAsStringSync().trim(), radix: 16);
            pid = int.tryParse(
                File('$baseDir/idProduct').readAsStringSync().trim(),
                radix: 16);

            final mfFile = File('$baseDir/manufacturer');
            if (mfFile.existsSync()) {
              manufacturer = mfFile.readAsStringSync().trim();
            }

            final prodFile = File('$baseDir/product');
            if (prodFile.existsSync()) {
              product = prodFile.readAsStringSync().trim();
            }

            final serialFile = File('$baseDir/serial');
            if (serialFile.existsSync()) {
              serial = serialFile.readAsStringSync().trim();
            }

            break;
          } catch (e) {
            // Ignore read errors
          }
        }
      }

      ports.add(LinuxPortInfo(
        path: devicePath,
        vid: vid,
        pid: pid,
        manufacturer: manufacturer,
        product: product,
        serialNumber: serial,
      ));
    }

    return ports;
  }

  /// Open the serial port
  Future<bool> open(String path, int baudRate) async {
    _initialize();

    if (_fd != null) {
      await close();
    }

    final pathPtr = path.toNativeUtf8();
    try {
      final fd = _open(pathPtr, O_RDWR | O_NOCTTY | O_NONBLOCK);
      if (fd < 0) {
        return false;
      }

      _fd = fd;
      _path = path;

      // Configure terminal settings
      if (!_configure(baudRate)) {
        _close(fd);
        _fd = null;
        _path = null;
        return false;
      }

      // Set initial DTR/RTS state
      setDTR(true);
      setRTS(true);

      return true;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Configure terminal for raw serial communication
  bool _configure(int baudRate) {
    if (_fd == null) return false;

    final termios = calloc<Termios>();
    try {
      // Get current settings
      if (_tcgetattr(_fd!, termios) != 0) {
        return false;
      }

      // Configure for raw serial communication
      final ref = termios.ref;

      // Input flags - disable all processing
      ref.c_iflag = 0;
      ref.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR |
          ICRNL | IXON | IXOFF | IXANY);

      // Output flags - disable all processing
      ref.c_oflag = 0;
      ref.c_oflag &= ~OPOST;

      // Control flags - 8N1, no flow control
      ref.c_cflag &= ~(CSIZE | PARENB | PARODD | CSTOPB | CRTSCTS);
      ref.c_cflag |= CS8 | CREAD | CLOCAL;

      // Local flags - disable canonical mode, echo, signals
      ref.c_lflag = 0;
      ref.c_lflag &= ~(ICANON | ECHO | ECHOE | ECHOK | ECHONL | ISIG | IEXTEN);

      // Special characters
      ref.c_cc[VMIN] = 0; // Non-blocking read
      ref.c_cc[VTIME] = 0; // No timeout

      // Set baud rate
      final baudCode = _baudRateMap[baudRate];
      if (baudCode == null) {
        // Try to find closest supported baud rate
        final closest = _baudRateMap.keys
            .reduce((a, b) => (a - baudRate).abs() < (b - baudRate).abs() ? a : b);
        final closestCode = _baudRateMap[closest]!;
        _cfsetispeed(termios, closestCode);
        _cfsetospeed(termios, closestCode);
      } else {
        _cfsetispeed(termios, baudCode);
        _cfsetospeed(termios, baudCode);
      }

      // Apply settings
      if (_tcsetattr(_fd!, TCSANOW, termios) != 0) {
        return false;
      }

      // Flush buffers
      _tcflush(_fd!, TCIOFLUSH);

      return true;
    } finally {
      calloc.free(termios);
    }
  }

  /// Read data from the port
  Future<Uint8List> read(int maxBytes, {int timeoutMs = 1000}) async {
    if (_fd == null) {
      throw StateError('Port not open');
    }

    final buffer = calloc<Uint8>(maxBytes);
    final pollFd = calloc<PollFd>();

    try {
      pollFd.ref.fd = _fd!;
      pollFd.ref.events = POLLIN;
      pollFd.ref.revents = 0;

      // Poll for available data
      final pollResult = _poll(pollFd.cast<Void>(), 1, timeoutMs);

      if (pollResult <= 0) {
        // Timeout or error
        return Uint8List(0);
      }

      if ((pollFd.ref.revents & POLLIN) == 0) {
        return Uint8List(0);
      }

      // Read available data
      final bytesRead = _read(_fd!, buffer, maxBytes);

      if (bytesRead <= 0) {
        return Uint8List(0);
      }

      final result = Uint8List(bytesRead);
      for (var i = 0; i < bytesRead; i++) {
        result[i] = buffer[i];
      }
      return result;
    } finally {
      calloc.free(buffer);
      calloc.free(pollFd);
    }
  }

  /// Read with blocking timeout (simpler API for protocols)
  Future<Uint8List> readBytes(int count, {int timeoutMs = 1000}) async {
    final data = <int>[];
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (data.length < count && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now()).inMilliseconds;
      if (remaining <= 0) break;

      final chunk = await read(count - data.length, timeoutMs: remaining);
      data.addAll(chunk);
    }

    return Uint8List.fromList(data);
  }

  /// Write data to the port
  Future<int> write(Uint8List data) async {
    if (_fd == null) {
      throw StateError('Port not open');
    }

    final buffer = calloc<Uint8>(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        buffer[i] = data[i];
      }

      final bytesWritten = _write(_fd!, buffer, data.length);
      return bytesWritten > 0 ? bytesWritten : 0;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Set DTR signal
  void setDTR(bool value) {
    if (_fd == null) return;
    _dtr = value;
    _setModemBit(TIOCM_DTR, value);
  }

  /// Set RTS signal
  void setRTS(bool value) {
    if (_fd == null) return;
    _rts = value;
    _setModemBit(TIOCM_RTS, value);
  }

  void _setModemBit(int bit, bool value) {
    final arg = calloc<Int32>();
    try {
      arg.value = bit;
      _ioctl(_fd!, value ? TIOCMBIS : TIOCMBIC, arg);
    } finally {
      calloc.free(arg);
    }
  }

  /// Get DTR state
  bool get dtr => _dtr;

  /// Get RTS state
  bool get rts => _rts;

  /// Flush buffers
  Future<void> flush() async {
    if (_fd != null) {
      _tcflush(_fd!, TCIOFLUSH);
    }
  }

  /// Drain output buffer
  Future<void> drain() async {
    if (_fd != null) {
      _tcdrain(_fd!);
    }
  }

  /// Set baud rate
  Future<void> setBaudRate(int baudRate) async {
    if (_fd == null) return;
    _configure(baudRate);
  }

  /// Close the port
  Future<void> close() async {
    if (_fd != null) {
      _close(_fd!);
      _fd = null;
      _path = null;
    }
  }

  /// Check if port is open
  bool get isOpen => _fd != null;

  /// Get port path
  String? get path => _path;
}

/// Port information from sysfs
class LinuxPortInfo {
  final String path;
  final int? vid;
  final int? pid;
  final String? manufacturer;
  final String? product;
  final String? serialNumber;

  const LinuxPortInfo({
    required this.path,
    this.vid,
    this.pid,
    this.manufacturer,
    this.product,
    this.serialNumber,
  });

  String? get vidHex =>
      vid != null ? '0x${vid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  String? get pidHex =>
      pid != null ? '0x${pid!.toRadixString(16).toUpperCase().padLeft(4, '0')}' : null;

  @override
  String toString() => 'LinuxPortInfo($path, vid=$vidHex, pid=$pidHex)';
}
