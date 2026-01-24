import 'dart:convert';
import 'dart:io';

import '../models/device_definition.dart';

/// Service for loading and managing device definitions
///
/// Reads device definitions from the flasher/ directory structure.
class FlasherStorageService {
  /// Base path for flasher data
  final String basePath;

  FlasherStorageService(this.basePath);

  /// Load metadata.json
  Future<FlasherMetadata?> loadMetadata() async {
    final file = File('$basePath/metadata.json');
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return FlasherMetadata.fromJson(json);
    } catch (e) {
      print('Error loading flasher metadata: $e');
      return null;
    }
  }

  /// List all device families
  Future<List<String>> listFamilies() async {
    final dir = Directory(basePath);
    if (!await dir.exists()) return [];

    final families = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Skip extra folder
        if (name != 'extra') {
          families.add(name);
        }
      }
    }

    return families;
  }

  /// List devices in a family
  Future<List<String>> listDevices(String family) async {
    final dir = Directory('$basePath/$family');
    if (!await dir.exists()) return [];

    final devices = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final name = entity.path.split(Platform.pathSeparator).last;
        devices.add(name.replaceAll('.json', ''));
      }
    }

    return devices;
  }

  /// Load a device definition
  Future<DeviceDefinition?> loadDevice(String family, String deviceId) async {
    final file = File('$basePath/$family/$deviceId.json');
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final device = DeviceDefinition.fromJson(json);
      device.setBasePath('$basePath/$family');
      return device;
    } catch (e) {
      print('Error loading device $family/$deviceId: $e');
      return null;
    }
  }

  /// Load all devices
  Future<List<DeviceDefinition>> loadAllDevices() async {
    final devices = <DeviceDefinition>[];

    final families = await listFamilies();
    for (final family in families) {
      final deviceIds = await listDevices(family);
      for (final deviceId in deviceIds) {
        final device = await loadDevice(family, deviceId);
        if (device != null) {
          devices.add(device);
        }
      }
    }

    return devices;
  }

  /// Load devices by family
  Future<Map<String, List<DeviceDefinition>>> loadDevicesByFamily() async {
    final result = <String, List<DeviceDefinition>>{};

    final families = await listFamilies();
    for (final family in families) {
      final devices = <DeviceDefinition>[];
      final deviceIds = await listDevices(family);

      for (final deviceId in deviceIds) {
        final device = await loadDevice(family, deviceId);
        if (device != null) {
          devices.add(device);
        }
      }

      if (devices.isNotEmpty) {
        result[family] = devices;
      }
    }

    return result;
  }

  /// Find device by USB VID/PID
  Future<DeviceDefinition?> findDeviceByUsb(int vid, int pid) async {
    final devices = await loadAllDevices();

    for (final device in devices) {
      if (device.usb != null) {
        if (device.usb!.vidInt == vid && device.usb!.pidInt == pid) {
          return device;
        }
      }
    }

    return null;
  }

  /// Find devices matching VID (may have multiple PIDs)
  Future<List<DeviceDefinition>> findDevicesByVid(int vid) async {
    final devices = await loadAllDevices();
    return devices.where((d) => d.usb?.vidInt == vid).toList();
  }

  /// Save a device definition
  Future<bool> saveDevice(DeviceDefinition device) async {
    final file = File('$basePath/${device.family}/${device.id}.json');

    try {
      // Ensure directory exists
      await file.parent.create(recursive: true);

      // Write JSON
      final json = device.toJson();
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString(content);

      return true;
    } catch (e) {
      print('Error saving device ${device.id}: $e');
      return false;
    }
  }

  /// Check if media file exists
  Future<bool> mediaExists(String family, String filename) async {
    final file = File('$basePath/$family/media/$filename');
    return file.exists();
  }

  /// Get media file path
  String getMediaPath(String family, String filename) {
    return '$basePath/$family/media/$filename';
  }
}
