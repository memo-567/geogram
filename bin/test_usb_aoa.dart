// Test script for USB AOA Linux implementation
// Run with: dart run bin/test_usb_aoa.dart

import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Constants
const O_RDWR = 0x0002;
const USBDEVFS_CONTROL = 0xC0185500;
const USB_DIR_IN = 0x80;
const USB_DIR_OUT = 0x00;
const USB_TYPE_VENDOR = 0x40;
const USB_RECIP_DEVICE = 0x00;
const AOA_GET_PROTOCOL = 51;
const AOA_SEND_STRING = 52;
const AOA_START = 53;

// Known Android VIDs
const androidVids = <int>{
  0x18D1, // Google
  0x04E8, // Samsung
  0x22B8, // Motorola
  0x0BB4, // HTC
  0x12D1, // Huawei
  0x2717, // Xiaomi
  0x1949, // OnePlus
  0x0FCE, // Sony
  0x2A70, // OnePlus (alternate)
  0x05C6, // Qualcomm
  0x1004, // LG
  0x2916, // Realme
  0x2B4C, // Vivo
  0x1782, // Spreadtrum
};

// FFI
final class UsbCtrlTransfer extends Struct {
  @Uint8() external int bRequestType;
  @Uint8() external int bRequest;
  @Uint16() external int wValue;
  @Uint16() external int wIndex;
  @Uint16() external int wLength;
  @Uint32() external int timeout;
  external Pointer<Void> data;
}

typedef OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef OpenDart = int Function(Pointer<Utf8> path, int flags);
typedef CloseNative = Int32 Function(Int32 fd);
typedef CloseDart = int Function(int fd);
typedef IoctlPtrNative = Int32 Function(Int32 fd, Uint64 request, Pointer<Void> arg);
typedef IoctlPtrDart = int Function(int fd, int request, Pointer<Void> arg);
typedef ErrnoLocNative = Pointer<Int32> Function();
typedef ErrnoLocDart = Pointer<Int32> Function();

void main() async {
  print('=== USB AOA Linux Test ===\n');

  // Load libc
  final lib = DynamicLibrary.open('libc.so.6');
  final open = lib.lookupFunction<OpenNative, OpenDart>('open');
  final close = lib.lookupFunction<CloseNative, CloseDart>('close');
  final ioctl = lib.lookupFunction<IoctlPtrNative, IoctlPtrDart>('ioctl');
  final errnoLoc = lib.lookupFunction<ErrnoLocNative, ErrnoLocDart>('__errno_location');

  int getErrno() => errnoLoc().value;

  // Enumerate devices
  print('Scanning /sys/bus/usb/devices/...\n');

  final sysDir = Directory('/sys/bus/usb/devices');
  final devices = <Map<String, dynamic>>[];

  for (final entry in sysDir.listSync()) {
    final name = entry.path.split('/').last;
    print('  Checking: $name (${entry.runtimeType})');
    if (name.contains(':')) continue; // Skip interface entries

    try {
      final vidFile = File('${entry.path}/idVendor');
      final pidFile = File('${entry.path}/idProduct');

      if (!vidFile.existsSync() || !pidFile.existsSync()) continue;

      final vid = int.tryParse(vidFile.readAsStringSync().trim(), radix: 16);
      final pid = int.tryParse(pidFile.readAsStringSync().trim(), radix: 16);

      if (vid == null || pid == null) continue;

      final busnumFile = File('${entry.path}/busnum');
      final devnumFile = File('${entry.path}/devnum');

      if (!busnumFile.existsSync() || !devnumFile.existsSync()) continue;

      final busnum = int.tryParse(busnumFile.readAsStringSync().trim()) ?? 0;
      final devnum = int.tryParse(devnumFile.readAsStringSync().trim()) ?? 0;

      String? manufacturer;
      String? product;
      final mfFile = File('${entry.path}/manufacturer');
      if (mfFile.existsSync()) manufacturer = mfFile.readAsStringSync().trim();
      final prodFile = File('${entry.path}/product');
      if (prodFile.existsSync()) product = prodFile.readAsStringSync().trim();

      final isAndroid = androidVids.contains(vid);
      final devPath = '/dev/bus/usb/${busnum.toString().padLeft(3, '0')}/${devnum.toString().padLeft(3, '0')}';

      devices.add({
        'name': name,
        'vid': vid,
        'pid': pid,
        'devPath': devPath,
        'sysPath': entry.path,
        'manufacturer': manufacturer,
        'product': product,
        'isAndroid': isAndroid,
      });

      final vidHex = '0x${vid.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      final pidHex = '0x${pid.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      final androidTag = isAndroid ? ' [ANDROID]' : '';

      print('  $name: $vidHex:$pidHex$androidTag');
      print('    Manufacturer: ${manufacturer ?? "unknown"}');
      print('    Product: ${product ?? "unknown"}');
      print('    Path: $devPath');
      print('');
    } catch (e) {
      continue;
    }
  }

  // Find Android devices
  final androidDevices = devices.where((d) => d['isAndroid'] == true).toList();

  if (androidDevices.isEmpty) {
    print('No Android devices found!');
    return;
  }

  print('Found ${androidDevices.length} Android device(s)\n');

  // Try AOA handshake on first Android device
  final device = androidDevices.first;
  final devPath = device['devPath'] as String;

  print('=== Attempting AOA handshake on ${device['name']} ===\n');
  print('Device path: $devPath');

  // Open device
  final pathPtr = devPath.toNativeUtf8();
  final fd = open(pathPtr, O_RDWR);
  calloc.free(pathPtr);

  if (fd < 0) {
    print('ERROR: Failed to open device, errno=${getErrno()}');
    if (getErrno() == 13) {
      print('Permission denied! Try running with sudo or add udev rules.');
    }
    return;
  }
  print('Opened device, fd=$fd');

  // GET_PROTOCOL
  print('\n--- GET_PROTOCOL ---');
  final buffer = calloc<Uint8>(2);
  final ctrl = calloc<UsbCtrlTransfer>();

  ctrl.ref.bRequestType = USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_DEVICE;
  ctrl.ref.bRequest = AOA_GET_PROTOCOL;
  ctrl.ref.wValue = 0;
  ctrl.ref.wIndex = 0;
  ctrl.ref.wLength = 2;
  ctrl.ref.timeout = 1000;
  ctrl.ref.data = buffer.cast();

  final result = ioctl(fd, USBDEVFS_CONTROL, ctrl.cast());
  print('ioctl result: $result');

  if (result < 0) {
    print('ERROR: GET_PROTOCOL failed, errno=${getErrno()}');
    close(fd);
    calloc.free(buffer);
    calloc.free(ctrl);
    return;
  }

  final version = buffer[0] | (buffer[1] << 8);
  print('AOA Protocol Version: $version');

  if (version < 1) {
    print('Device does not support AOA!');
    close(fd);
    calloc.free(buffer);
    calloc.free(ctrl);
    return;
  }

  // SEND_STRING
  print('\n--- SEND_STRING ---');
  final strings = [
    'Geogram',           // Manufacturer
    'Geogram Device',    // Model
    'Geogram USB Link',  // Description
    '1.0',               // Version
    'https://geogram.dev', // URI
    'geogram-linux',     // Serial
  ];

  for (var i = 0; i < strings.length; i++) {
    final str = strings[i];
    final bytes = Uint8List.fromList(str.codeUnits);
    final strBuffer = calloc<Uint8>(bytes.length + 1);

    for (var j = 0; j < bytes.length; j++) {
      strBuffer[j] = bytes[j];
    }
    strBuffer[bytes.length] = 0;

    ctrl.ref.bRequestType = USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE;
    ctrl.ref.bRequest = AOA_SEND_STRING;
    ctrl.ref.wValue = 0;
    ctrl.ref.wIndex = i;
    ctrl.ref.wLength = bytes.length + 1;
    ctrl.ref.timeout = 1000;
    ctrl.ref.data = strBuffer.cast();

    final sendResult = ioctl(fd, USBDEVFS_CONTROL, ctrl.cast());
    print('  String[$i] "$str": result=$sendResult');

    if (sendResult < 0) {
      print('  ERROR: Failed to send string[$i], errno=${getErrno()}');
    }

    calloc.free(strBuffer);
  }

  // START
  print('\n--- START ---');
  ctrl.ref.bRequestType = USB_DIR_OUT | USB_TYPE_VENDOR | USB_RECIP_DEVICE;
  ctrl.ref.bRequest = AOA_START;
  ctrl.ref.wValue = 0;
  ctrl.ref.wIndex = 0;
  ctrl.ref.wLength = 0;
  ctrl.ref.timeout = 1000;
  ctrl.ref.data = nullptr;

  final startResult = ioctl(fd, USBDEVFS_CONTROL, ctrl.cast());
  print('START result: $startResult');

  if (startResult < 0) {
    print('ERROR: START failed, errno=${getErrno()}');
  } else {
    print('SUCCESS! Device should re-enumerate as AOA accessory.');
    print('Check with: lsusb | grep 18d1');
    print('Expected PIDs: 2d00 (AOA) or 2d01 (AOA+ADB)');
  }

  close(fd);
  calloc.free(buffer);
  calloc.free(ctrl);

  print('\n=== Test complete ===');
}
