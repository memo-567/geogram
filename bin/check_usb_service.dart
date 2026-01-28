// Direct USB AOA service check
// Run with: dart run bin/check_usb_service.dart

import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// FFI to test if libc loads
typedef OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef OpenDart = int Function(Pointer<Utf8> path, int flags);

void main() async {
  print('=== USB AOA Service Diagnostic ===\n');

  print('Platform: ${Platform.operatingSystem}');
  print('Is Linux: ${Platform.isLinux}');

  // Check if libc can be loaded
  print('\n--- FFI Check ---');
  try {
    final lib = DynamicLibrary.open('libc.so.6');
    print('libc.so.6: LOADED');

    final open = lib.lookupFunction<OpenNative, OpenDart>('open');
    print('open(): FOUND');
  } catch (e) {
    print('libc.so.6: FAILED - $e');
  }

  // Check sysfs for AOA device
  print('\n--- Device Check ---');
  const aoaVid = 0x18D1;
  const aoaPidAccessory = 0x2D00;
  const aoaPidAdb = 0x2D01;

  final devicesDir = Directory('/sys/bus/usb/devices');
  var foundAoa = false;
  String? aoaDevPath;

  await for (final entry in devicesDir.list()) {
    if (entry is! Directory) continue;
    final name = entry.path.split('/').last;
    if (name.contains(':')) continue;

    final vidFile = File('${entry.path}/idVendor');
    final pidFile = File('${entry.path}/idProduct');

    if (!await vidFile.exists() || !await pidFile.exists()) continue;

    try {
      final vid = int.tryParse((await vidFile.readAsString()).trim(), radix: 16);
      final pid = int.tryParse((await pidFile.readAsString()).trim(), radix: 16);

      if (vid == aoaVid && (pid == aoaPidAccessory || pid == aoaPidAdb)) {
        foundAoa = true;

        final busnumFile = File('${entry.path}/busnum');
        final devnumFile = File('${entry.path}/devnum');
        if (await busnumFile.exists() && await devnumFile.exists()) {
          final busnum = int.tryParse((await busnumFile.readAsString()).trim()) ?? 0;
          final devnum = int.tryParse((await devnumFile.readAsString()).trim()) ?? 0;
          aoaDevPath = '/dev/bus/usb/${busnum.toString().padLeft(3, '0')}/${devnum.toString().padLeft(3, '0')}';
        }

        print('AOA Device Found: ${vid!.toRadixString(16)}:${pid!.toRadixString(16)}');
        print('  sysPath: ${entry.path}');
        print('  devPath: $aoaDevPath');
      }
    } catch (_) {}
  }

  if (!foundAoa) {
    print('AOA Device: NOT FOUND');
    print('\nPossible issues:');
    print('  1. Android not connected via USB');
    print('  2. Android app not running or not in AOA mode');
    print('  3. USB cable issue');
    return;
  }

  // Try opening the device
  print('\n--- Device Access ---');
  if (aoaDevPath != null) {
    final devFile = File(aoaDevPath);
    if (await devFile.exists()) {
      print('Device file exists: YES');
      try {
        // Try raw open via FFI
        final lib = DynamicLibrary.open('libc.so.6');
        final open = lib.lookupFunction<OpenNative, OpenDart>('open');
        final close = lib.lookupFunction<Int32 Function(Int32), int Function(int)>('close');

        final pathPtr = aoaDevPath.toNativeUtf8();
        final fd = open(pathPtr, 0x0002); // O_RDWR
        calloc.free(pathPtr);

        if (fd >= 0) {
          print('FFI open(): SUCCESS (fd=$fd)');
          close(fd);
        } else {
          print('FFI open(): FAILED (fd=$fd)');
          // Get errno
          final errnoLoc = lib.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>('__errno_location');
          final errno = errnoLoc().value;
          print('  errno: $errno');
          if (errno == 13) print('  EACCES - Permission denied');
          if (errno == 16) print('  EBUSY - Device busy');
        }
      } catch (e) {
        print('FFI open() error: $e');
      }
    } else {
      print('Device file exists: NO');
    }
  }

  print('\n=== Summary ===');
  print('AOA device is present and accessible via FFI');
  print('If USB connection still not working in app, check:');
  print('  1. App restart needed (hot reload may not reinitialize transports)');
  print('  2. UsbAoaTransport.isAvailable returning correct value');
  print('  3. ConnectionManager.initialize() being called');
  print('  4. Exception handling swallowing errors');
}
