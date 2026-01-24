import 'dart:convert';
import 'dart:io';

import '../models/device_definition.dart';

/// Service for loading and managing device definitions
///
/// Supports both v1.0 and v2.0 directory structures:
/// - v1.0: flasher/{family}/{device}.json
/// - v2.0: flasher/{project}/{architecture}/{model}/device.json
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

  // ==================== v2.0 Directory Structure ====================

  /// List all projects (v2.0)
  Future<List<String>> listProjects() async {
    final dir = Directory(basePath);
    if (!await dir.exists()) return [];

    final projects = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Check if it's a project folder (contains architecture subfolders)
        if (await _isProjectFolder(entity.path)) {
          projects.add(name);
        }
      }
    }

    return projects;
  }

  /// Check if a folder is a v2.0 project folder
  Future<bool> _isProjectFolder(String path) async {
    final dir = Directory(path);
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        // Check if subfolders contain model folders with device.json
        final subDir = Directory(entity.path);
        await for (final subEntity in subDir.list()) {
          if (subEntity is Directory) {
            final deviceFile = File('${subEntity.path}/device.json');
            if (await deviceFile.exists()) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// List architectures in a project (v2.0)
  Future<List<String>> listArchitectures(String project) async {
    final dir = Directory('$basePath/$project');
    if (!await dir.exists()) return [];

    final architectures = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        architectures.add(name);
      }
    }

    return architectures;
  }

  /// List models in a project/architecture (v2.0)
  Future<List<String>> listModels(String project, String architecture) async {
    final dir = Directory('$basePath/$project/$architecture');
    if (!await dir.exists()) return [];

    final models = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Check if it has device.json
        final deviceFile = File('${entity.path}/device.json');
        if (await deviceFile.exists()) {
          models.add(name);
        }
      }
    }

    return models;
  }

  /// Load device definition from v2.0 structure
  Future<DeviceDefinition?> loadDeviceV2(
    String project,
    String architecture,
    String model,
  ) async {
    final file = File('$basePath/$project/$architecture/$model/device.json');
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final device = DeviceDefinition.fromJson(json);
      device.setBasePath('$basePath/$project/$architecture/$model');
      return device;
    } catch (e) {
      print('Error loading device $project/$architecture/$model: $e');
      return null;
    }
  }

  /// Load firmware versions for a device (v2.0)
  Future<List<FirmwareVersion>> loadVersions(
    String project,
    String architecture,
    String model,
  ) async {
    final deviceDir = Directory('$basePath/$project/$architecture/$model');
    if (!await deviceDir.exists()) return [];

    final versions = <FirmwareVersion>[];
    await for (final entity in deviceDir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Skip non-version folders (like 'media', 'latest')
        if (name == 'media') continue;

        // Check for version.json or firmware.bin
        final versionFile = File('${entity.path}/version.json');
        final firmwareFile = File('${entity.path}/firmware.bin');

        if (await versionFile.exists()) {
          try {
            final content = await versionFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            versions.add(FirmwareVersion.fromJson(json));
          } catch (e) {
            print('Error loading version $name: $e');
          }
        } else if (await firmwareFile.exists()) {
          // Create version from folder name
          final stat = await firmwareFile.stat();
          versions.add(FirmwareVersion(
            version: name,
            size: stat.size,
          ));
        }
      }
    }

    // Sort versions (newest first)
    versions.sort((a, b) => b.version.compareTo(a.version));
    return versions;
  }

  // ==================== v1.0 Directory Structure (Legacy) ====================

  /// List all device families (v1.0)
  Future<List<String>> listFamilies() async {
    final dir = Directory(basePath);
    if (!await dir.exists()) return [];

    final families = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Skip extra folder and v2.0 project folders
        if (name != 'extra' && !await _isProjectFolder(entity.path)) {
          // Check if it contains .json files (v1.0 format)
          final subDir = Directory(entity.path);
          await for (final subEntity in subDir.list()) {
            if (subEntity is File && subEntity.path.endsWith('.json')) {
              families.add(name);
              break;
            }
          }
        }
      }
    }

    return families;
  }

  /// List devices in a family (v1.0)
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

  /// Load a device definition (v1.0)
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

  // ==================== Unified Loading ====================

  /// Load all devices (both v1.0 and v2.0)
  Future<List<DeviceDefinition>> loadAllDevices() async {
    final devices = <DeviceDefinition>[];

    // Load v2.0 devices first
    final projects = await listProjects();
    for (final project in projects) {
      final architectures = await listArchitectures(project);
      for (final arch in architectures) {
        final models = await listModels(project, arch);
        for (final model in models) {
          final device = await loadDeviceV2(project, arch, model);
          if (device != null) {
            devices.add(device);
          }
        }
      }
    }

    // Then load v1.0 devices (legacy)
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

  /// Load devices organized by project/architecture/model hierarchy
  Future<Map<String, Map<String, List<DeviceDefinition>>>>
      loadDevicesByHierarchy() async {
    final result = <String, Map<String, List<DeviceDefinition>>>{};

    // Load v2.0 devices
    final projects = await listProjects();
    for (final project in projects) {
      result[project] = {};
      final architectures = await listArchitectures(project);
      for (final arch in architectures) {
        result[project]![arch] = [];
        final models = await listModels(project, arch);
        for (final model in models) {
          final device = await loadDeviceV2(project, arch, model);
          if (device != null) {
            result[project]![arch]!.add(device);
          }
        }
      }
    }

    // Load v1.0 devices under "geogram" project
    final families = await listFamilies();
    for (final family in families) {
      if (!result.containsKey('geogram')) {
        result['geogram'] = {};
      }
      if (!result['geogram']!.containsKey(family)) {
        result['geogram']![family] = [];
      }

      final deviceIds = await listDevices(family);
      for (final deviceId in deviceIds) {
        final device = await loadDevice(family, deviceId);
        if (device != null) {
          result['geogram']![family]!.add(device);
        }
      }
    }

    return result;
  }

  /// Load devices by family (v1.0 compatibility)
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

  /// Get media file path for v2.0 structure
  String getMediaPathV2(
    String project,
    String architecture,
    String model,
    String filename,
  ) {
    return '$basePath/$project/$architecture/$model/media/$filename';
  }
}
