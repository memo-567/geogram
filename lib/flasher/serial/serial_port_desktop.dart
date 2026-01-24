import 'dart:typed_data';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'serial_port.dart';

// libserialport FFI bindings
// These are minimal bindings for the subset of libserialport we need

/// Return values
const int SP_OK = 0;
const int SP_ERR_ARG = -1;
const int SP_ERR_FAIL = -2;
const int SP_ERR_MEM = -3;
const int SP_ERR_SUPP = -4;

/// Port modes
const int SP_MODE_READ = 1;
const int SP_MODE_WRITE = 2;
const int SP_MODE_READ_WRITE = 3;

/// Signal bits
const int SP_SIG_DTR = 1;
const int SP_SIG_RTS = 2;

/// Parity
const int SP_PARITY_NONE = 0;

/// Stop bits
const int SP_STOPBITS_1 = 1;

/// Flow control
const int SP_FLOWCONTROL_NONE = 0;

// Opaque struct pointer
typedef SpPort = Void;
typedef SpPortConfig = Void;

// Native function types
typedef SpListPortsNative = Int32 Function(Pointer<Pointer<Pointer<SpPort>>>);
typedef SpListPorts = int Function(Pointer<Pointer<Pointer<SpPort>>>);

typedef SpFreePortListNative = Void Function(Pointer<Pointer<SpPort>>);
typedef SpFreePortList = void Function(Pointer<Pointer<SpPort>>);

typedef SpGetPortNameNative = Pointer<Utf8> Function(Pointer<SpPort>);
typedef SpGetPortName = Pointer<Utf8> Function(Pointer<SpPort>);

typedef SpGetPortDescriptionNative = Pointer<Utf8> Function(Pointer<SpPort>);
typedef SpGetPortDescription = Pointer<Utf8> Function(Pointer<SpPort>);

typedef SpGetPortUsbVidPidNative = Int32 Function(
    Pointer<SpPort>, Pointer<Int32>, Pointer<Int32>);
typedef SpGetPortUsbVidPid = int Function(
    Pointer<SpPort>, Pointer<Int32>, Pointer<Int32>);

typedef SpGetPortUsbManufacturerNative = Pointer<Utf8> Function(
    Pointer<SpPort>);
typedef SpGetPortUsbManufacturer = Pointer<Utf8> Function(Pointer<SpPort>);

typedef SpGetPortUsbProductNative = Pointer<Utf8> Function(Pointer<SpPort>);
typedef SpGetPortUsbProduct = Pointer<Utf8> Function(Pointer<SpPort>);

typedef SpGetPortUsbSerialNative = Pointer<Utf8> Function(Pointer<SpPort>);
typedef SpGetPortUsbSerial = Pointer<Utf8> Function(Pointer<SpPort>);

typedef SpGetPortByNameNative = Int32 Function(
    Pointer<Utf8>, Pointer<Pointer<SpPort>>);
typedef SpGetPortByName = int Function(
    Pointer<Utf8>, Pointer<Pointer<SpPort>>);

typedef SpOpenNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpOpen = int Function(Pointer<SpPort>, int);

typedef SpCloseNative = Int32 Function(Pointer<SpPort>);
typedef SpClose = int Function(Pointer<SpPort>);

typedef SpFreePortNative = Void Function(Pointer<SpPort>);
typedef SpFreePort = void Function(Pointer<SpPort>);

typedef SpSetBaudrateNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpSetBaudrate = int Function(Pointer<SpPort>, int);

typedef SpSetBitsNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpSetBits = int Function(Pointer<SpPort>, int);

typedef SpSetParityNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpSetParity = int Function(Pointer<SpPort>, int);

typedef SpSetStopbitsNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpSetStopbits = int Function(Pointer<SpPort>, int);

typedef SpSetFlowcontrolNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpSetFlowcontrol = int Function(Pointer<SpPort>, int);

typedef SpBlockingReadNative = Int32 Function(
    Pointer<SpPort>, Pointer<Uint8>, Size, Uint32);
typedef SpBlockingRead = int Function(
    Pointer<SpPort>, Pointer<Uint8>, int, int);

typedef SpBlockingWriteNative = Int32 Function(
    Pointer<SpPort>, Pointer<Uint8>, Size, Uint32);
typedef SpBlockingWrite = int Function(
    Pointer<SpPort>, Pointer<Uint8>, int, int);

typedef SpFlushNative = Int32 Function(Pointer<SpPort>, Int32);
typedef SpFlush = int Function(Pointer<SpPort>, int);

typedef SpSetSignalsNative = Int32 Function(Pointer<SpPort>, Int32, Int32);
typedef SpSetSignals = int Function(Pointer<SpPort>, int, int);

/// libserialport library wrapper
class LibSerialPort {
  static DynamicLibrary? _lib;
  static bool _initialized = false;

  // Function pointers
  static late SpListPorts _listPorts;
  static late SpFreePortList _freePortList;
  static late SpGetPortName _getPortName;
  static late SpGetPortDescription _getPortDescription;
  static late SpGetPortUsbVidPid _getPortUsbVidPid;
  static late SpGetPortUsbManufacturer _getPortUsbManufacturer;
  static late SpGetPortUsbProduct _getPortUsbProduct;
  static late SpGetPortUsbSerial _getPortUsbSerial;
  static late SpGetPortByName _getPortByName;
  static late SpOpen _open;
  static late SpClose _close;
  static late SpFreePort _freePort;
  static late SpSetBaudrate _setBaudrate;
  static late SpSetBits _setBits;
  static late SpSetParity _setParity;
  static late SpSetStopbits _setStopbits;
  static late SpSetFlowcontrol _setFlowcontrol;
  static late SpBlockingRead _blockingRead;
  static late SpBlockingWrite _blockingWrite;
  static late SpFlush _flush;
  static late SpSetSignals _setSignals;

  static void _init() {
    if (_initialized) return;

    // Load library based on platform
    if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libserialport.so.0');
    } else if (Platform.isMacOS) {
      _lib = DynamicLibrary.open('libserialport.dylib');
    } else if (Platform.isWindows) {
      _lib = DynamicLibrary.open('serialport.dll');
    } else {
      throw SerialPortException('Unsupported platform: ${Platform.operatingSystem}');
    }

    // Load functions
    _listPorts = _lib!
        .lookupFunction<SpListPortsNative, SpListPorts>('sp_list_ports');
    _freePortList = _lib!
        .lookupFunction<SpFreePortListNative, SpFreePortList>('sp_free_port_list');
    _getPortName = _lib!
        .lookupFunction<SpGetPortNameNative, SpGetPortName>('sp_get_port_name');
    _getPortDescription = _lib!
        .lookupFunction<SpGetPortDescriptionNative, SpGetPortDescription>(
            'sp_get_port_description');
    _getPortUsbVidPid = _lib!
        .lookupFunction<SpGetPortUsbVidPidNative, SpGetPortUsbVidPid>(
            'sp_get_port_usb_vid_pid');
    _getPortUsbManufacturer = _lib!
        .lookupFunction<SpGetPortUsbManufacturerNative, SpGetPortUsbManufacturer>(
            'sp_get_port_usb_manufacturer');
    _getPortUsbProduct = _lib!
        .lookupFunction<SpGetPortUsbProductNative, SpGetPortUsbProduct>(
            'sp_get_port_usb_product');
    _getPortUsbSerial = _lib!
        .lookupFunction<SpGetPortUsbSerialNative, SpGetPortUsbSerial>(
            'sp_get_port_usb_serial');
    _getPortByName = _lib!
        .lookupFunction<SpGetPortByNameNative, SpGetPortByName>(
            'sp_get_port_by_name');
    _open = _lib!.lookupFunction<SpOpenNative, SpOpen>('sp_open');
    _close = _lib!.lookupFunction<SpCloseNative, SpClose>('sp_close');
    _freePort =
        _lib!.lookupFunction<SpFreePortNative, SpFreePort>('sp_free_port');
    _setBaudrate = _lib!
        .lookupFunction<SpSetBaudrateNative, SpSetBaudrate>('sp_set_baudrate');
    _setBits = _lib!.lookupFunction<SpSetBitsNative, SpSetBits>('sp_set_bits');
    _setParity =
        _lib!.lookupFunction<SpSetParityNative, SpSetParity>('sp_set_parity');
    _setStopbits = _lib!
        .lookupFunction<SpSetStopbitsNative, SpSetStopbits>('sp_set_stopbits');
    _setFlowcontrol = _lib!
        .lookupFunction<SpSetFlowcontrolNative, SpSetFlowcontrol>(
            'sp_set_flowcontrol');
    _blockingRead = _lib!
        .lookupFunction<SpBlockingReadNative, SpBlockingRead>(
            'sp_blocking_read');
    _blockingWrite = _lib!
        .lookupFunction<SpBlockingWriteNative, SpBlockingWrite>(
            'sp_blocking_write');
    _flush = _lib!.lookupFunction<SpFlushNative, SpFlush>('sp_flush');
    _setSignals = _lib!
        .lookupFunction<SpSetSignalsNative, SpSetSignals>('sp_set_signals');

    _initialized = true;
  }

  /// List available serial ports
  static List<PortInfo> listPorts() {
    _init();

    final portsPtr = calloc<Pointer<Pointer<SpPort>>>();
    final result = _listPorts(portsPtr);

    if (result != SP_OK) {
      calloc.free(portsPtr);
      throw SerialPortException('Failed to list ports', errorCode: result);
    }

    final ports = <PortInfo>[];
    final portList = portsPtr.value;

    if (portList != nullptr) {
      var i = 0;
      while (portList[i] != nullptr) {
        final port = portList[i];

        // Get port name
        final namePtr = _getPortName(port);
        final name = namePtr.toDartString();

        // Get description
        final descPtr = _getPortDescription(port);
        final description = descPtr != nullptr ? descPtr.toDartString() : null;

        // Get USB VID/PID
        final vidPtr = calloc<Int32>();
        final pidPtr = calloc<Int32>();
        final vidPidResult = _getPortUsbVidPid(port, vidPtr, pidPtr);
        final vid = vidPidResult == SP_OK ? vidPtr.value : null;
        final pid = vidPidResult == SP_OK ? pidPtr.value : null;
        calloc.free(vidPtr);
        calloc.free(pidPtr);

        // Get USB strings
        final manufacturerPtr = _getPortUsbManufacturer(port);
        final manufacturer =
            manufacturerPtr != nullptr ? manufacturerPtr.toDartString() : null;

        final productPtr = _getPortUsbProduct(port);
        final product =
            productPtr != nullptr ? productPtr.toDartString() : null;

        final serialPtr = _getPortUsbSerial(port);
        final serialNumber =
            serialPtr != nullptr ? serialPtr.toDartString() : null;

        ports.add(PortInfo(
          path: name,
          description: description,
          vid: vid,
          pid: pid,
          manufacturer: manufacturer,
          product: product,
          serialNumber: serialNumber,
        ));

        i++;
      }

      _freePortList(portList);
    }

    calloc.free(portsPtr);
    return ports;
  }

  /// Open a port by name
  static Pointer<SpPort> openPort(String path, int baudRate) {
    _init();

    final portPtr = calloc<Pointer<SpPort>>();
    final pathPtr = path.toNativeUtf8();

    var result = _getPortByName(pathPtr, portPtr);
    calloc.free(pathPtr);

    if (result != SP_OK) {
      calloc.free(portPtr);
      throw SerialPortException('Failed to get port: $path', path: path, errorCode: result);
    }

    final port = portPtr.value;
    calloc.free(portPtr);

    // Open port for read/write
    result = _open(port, SP_MODE_READ_WRITE);
    if (result != SP_OK) {
      _freePort(port);
      throw SerialPortException('Failed to open port: $path', path: path, errorCode: result);
    }

    // Configure port
    result = _setBaudrate(port, baudRate);
    if (result != SP_OK) {
      _close(port);
      _freePort(port);
      throw SerialPortException('Failed to set baud rate', path: path, errorCode: result);
    }

    result = _setBits(port, 8);
    if (result != SP_OK) {
      _close(port);
      _freePort(port);
      throw SerialPortException('Failed to set data bits', path: path, errorCode: result);
    }

    result = _setParity(port, SP_PARITY_NONE);
    if (result != SP_OK) {
      _close(port);
      _freePort(port);
      throw SerialPortException('Failed to set parity', path: path, errorCode: result);
    }

    result = _setStopbits(port, SP_STOPBITS_1);
    if (result != SP_OK) {
      _close(port);
      _freePort(port);
      throw SerialPortException('Failed to set stop bits', path: path, errorCode: result);
    }

    result = _setFlowcontrol(port, SP_FLOWCONTROL_NONE);
    if (result != SP_OK) {
      _close(port);
      _freePort(port);
      throw SerialPortException('Failed to set flow control', path: path, errorCode: result);
    }

    return port;
  }

  static void closePort(Pointer<SpPort> port) {
    _close(port);
    _freePort(port);
  }

  static Uint8List read(Pointer<SpPort> port, int maxBytes, int timeoutMs) {
    final buffer = calloc<Uint8>(maxBytes);
    final result = _blockingRead(port, buffer, maxBytes, timeoutMs);

    if (result < 0) {
      calloc.free(buffer);
      throw SerialPortException('Read failed', errorCode: result);
    }

    final data = Uint8List.fromList(buffer.asTypedList(result));
    calloc.free(buffer);
    return data;
  }

  static int write(Pointer<SpPort> port, Uint8List data, int timeoutMs) {
    final buffer = calloc<Uint8>(data.length);
    for (var i = 0; i < data.length; i++) {
      buffer[i] = data[i];
    }

    final result = _blockingWrite(port, buffer, data.length, timeoutMs);
    calloc.free(buffer);

    if (result < 0) {
      throw SerialPortException('Write failed', errorCode: result);
    }

    return result;
  }

  static void flush(Pointer<SpPort> port) {
    // SP_BUF_BOTH = 3
    _flush(port, 3);
  }

  static void setSignals(Pointer<SpPort> port, bool dtr, bool rts) {
    final mask = (dtr ? SP_SIG_DTR : 0) | (rts ? SP_SIG_RTS : 0);
    final value = mask;
    _setSignals(port, mask, value);
  }

  static void setBaudRate(Pointer<SpPort> port, int baudRate) {
    final result = _setBaudrate(port, baudRate);
    if (result != SP_OK) {
      throw SerialPortException('Failed to set baud rate', errorCode: result);
    }
  }
}

/// Desktop serial port implementation using libserialport
class DesktopSerialPort implements SerialPort {
  Pointer<SpPort>? _port;
  String? _path;
  bool _dtr = false;
  bool _rts = false;

  @override
  Future<bool> open(String path, int baudRate) async {
    try {
      _port = LibSerialPort.openPort(path, baudRate);
      _path = path;
      return true;
    } on SerialPortException {
      return false;
    }
  }

  @override
  Future<Uint8List> read(int maxBytes, {Duration? timeout}) async {
    if (_port == null) {
      throw SerialPortException('Port not open');
    }

    final timeoutMs = timeout?.inMilliseconds ?? 1000;
    try {
      return LibSerialPort.read(_port!, maxBytes, timeoutMs);
    } on SerialPortException {
      return Uint8List(0);
    }
  }

  @override
  Future<int> write(Uint8List data) async {
    if (_port == null) {
      throw SerialPortException('Port not open');
    }

    return LibSerialPort.write(_port!, data, 1000);
  }

  @override
  Future<void> close() async {
    if (_port != null) {
      LibSerialPort.closePort(_port!);
      _port = null;
      _path = null;
    }
  }

  @override
  void setDTR(bool value) {
    _dtr = value;
    if (_port != null) {
      LibSerialPort.setSignals(_port!, _dtr, _rts);
    }
  }

  @override
  void setRTS(bool value) {
    _rts = value;
    if (_port != null) {
      LibSerialPort.setSignals(_port!, _dtr, _rts);
    }
  }

  @override
  bool get dtr => _dtr;

  @override
  bool get rts => _rts;

  @override
  bool get isOpen => _port != null;

  @override
  String? get path => _path;

  @override
  Future<void> flush() async {
    if (_port != null) {
      LibSerialPort.flush(_port!);
    }
  }

  @override
  Future<void> setBaudRate(int baudRate) async {
    if (_port != null) {
      LibSerialPort.setBaudRate(_port!, baudRate);
    }
  }

  /// List available serial ports
  static Future<List<PortInfo>> listPorts() async {
    return LibSerialPort.listPorts();
  }
}
