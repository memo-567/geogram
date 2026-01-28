// Test USB AOA device detection on Linux
// Run with: dart run bin/test_usb_detection.dart

import 'dart:io';

void main() async {
  print('=== USB AOA Device Detection Test ===\n');

  // Check platform
  print('Platform: ${Platform.operatingSystem}');
  if (!Platform.isLinux) {
    print('ERROR: This test only works on Linux');
    return;
  }

  // Scan sysfs for USB devices
  print('\nScanning /sys/bus/usb/devices/ ...\n');

  final devicesDir = Directory('/sys/bus/usb/devices');
  if (!await devicesDir.exists()) {
    print('ERROR: /sys/bus/usb/devices not found');
    return;
  }

  // AOA VID/PID
  const aoaVid = 0x18D1;
  const aoaPidAccessory = 0x2D00;
  const aoaPidAccessoryAdb = 0x2D01;

  // Known Android VIDs
  const androidVids = <int>{
    0x18D1, // Google
    0x04E8, // Samsung
    0x22B8, // Motorola
    0x0BB4, // HTC
    0x12D1, // Huawei
    0x2717, // Xiaomi
    0x1949, // OnePlus
  };

  var foundDevices = 0;
  var foundAoa = false;

  await for (final entry in devicesDir.list()) {
    if (entry is! Directory) continue;
    final name = entry.path.split('/').last;

    // Skip interface entries (contain ':')
    if (name.contains(':')) continue;

    final vidFile = File('${entry.path}/idVendor');
    final pidFile = File('${entry.path}/idProduct');

    if (!await vidFile.exists() || !await pidFile.exists()) continue;

    try {
      final vidStr = (await vidFile.readAsString()).trim();
      final pidStr = (await pidFile.readAsString()).trim();
      final vid = int.tryParse(vidStr, radix: 16);
      final pid = int.tryParse(pidStr, radix: 16);

      if (vid == null || pid == null) continue;

      // Check if Android or AOA device
      final isAndroid = androidVids.contains(vid);
      final isAoa = vid == aoaVid && (pid == aoaPidAccessory || pid == aoaPidAccessoryAdb);

      if (!isAndroid && !isAoa) continue;

      foundDevices++;

      // Get more info
      String? manufacturer;
      String? product;

      final mfFile = File('${entry.path}/manufacturer');
      if (await mfFile.exists()) {
        manufacturer = (await mfFile.readAsString()).trim();
      }

      final prodFile = File('${entry.path}/product');
      if (await prodFile.exists()) {
        product = (await prodFile.readAsString()).trim();
      }

      // Get bus/dev numbers
      final busnumFile = File('${entry.path}/busnum');
      final devnumFile = File('${entry.path}/devnum');
      var busnum = 0;
      var devnum = 0;

      if (await busnumFile.exists() && await devnumFile.exists()) {
        busnum = int.tryParse((await busnumFile.readAsString()).trim()) ?? 0;
        devnum = int.tryParse((await devnumFile.readAsString()).trim()) ?? 0;
      }

      final devPath = '/dev/bus/usb/${busnum.toString().padLeft(3, '0')}/${devnum.toString().padLeft(3, '0')}';

      print('Found device:');
      print('  sysPath: ${entry.path}');
      print('  devPath: $devPath');
      print('  VID:PID: ${vid.toRadixString(16).padLeft(4, '0')}:${pid.toRadixString(16).padLeft(4, '0')}');
      print('  Manufacturer: ${manufacturer ?? "unknown"}');
      print('  Product: ${product ?? "unknown"}');
      print('  Is AOA mode: $isAoa');

      if (isAoa) {
        foundAoa = true;
        print('  >>> THIS IS AN AOA DEVICE - Android is ready! <<<');

        // Check device permissions
        final devFile = File(devPath);
        if (await devFile.exists()) {
          print('  Device file exists: YES');
          try {
            // Try to open for reading
            final raf = await devFile.open(mode: FileMode.read);
            await raf.close();
            print('  Read permission: YES');
          } catch (e) {
            print('  Read permission: NO ($e)');
          }
        } else {
          print('  Device file exists: NO');
        }
      }
      print('');
    } catch (e) {
      // Skip devices with read errors
      continue;
    }
  }

  print('=== Summary ===');
  print('Android/AOA devices found: $foundDevices');
  print('Device in AOA mode: $foundAoa');

  if (!foundAoa) {
    print('\nWARNING: No AOA device found!');
    print('Make sure:');
    print('  1. Android is connected via USB');
    print('  2. Android app is running and has requested USB accessory mode');
    print('  3. Check lsusb output for 18d1:2d01 or 18d1:2d00');
  } else {
    print('\nSUCCESS: AOA device detected and ready!');
    print('The USB AOA Linux code should be able to connect to this device.');
  }
}
