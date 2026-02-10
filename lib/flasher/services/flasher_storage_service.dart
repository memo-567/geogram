import 'dart:convert';

import '../models/device_definition.dart';
import '../../services/profile_storage.dart';

/// Service for loading and managing device definitions
///
/// Supports both v1.0 and v2.0 directory structures:
/// - v1.0: flasher/{family}/{device}.json
/// - v2.0: flasher/{project}/{architecture}/{model}/device.json
class FlasherStorageService {
  /// Base path for flasher data
  final String basePath;

  /// Profile storage for file operations (encrypted or filesystem)
  final ProfileStorage _storage;

  FlasherStorageService(this.basePath, this._storage);

  /// Expose the underlying ProfileStorage (for passing to other widgets)
  ProfileStorage get profileStorage => _storage;

  /// Check if a file exists at the given relative path
  Future<bool> fileExists(String relativePath) async {
    return _storage.exists(relativePath);
  }

  /// Load metadata.json
  Future<FlasherMetadata?> loadMetadata() async {
    try {
      final content = await _storage.readString('metadata.json');
      if (content == null) return null;

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
    if (!await _storage.directoryExists('')) return [];

    final entries = await _storage.listDirectory('');
    final projects = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        // Check if it's a project folder (contains architecture subfolders)
        if (await _isProjectFolder(entry.name)) {
          projects.add(entry.name);
        }
      }
    }

    return projects;
  }

  /// Check if a folder is a v2.0 project folder
  Future<bool> _isProjectFolder(String relativePath) async {
    if (!await _storage.directoryExists(relativePath)) return false;

    final entries = await _storage.listDirectory(relativePath);
    for (final entry in entries) {
      if (entry.isDirectory) {
        // Check if subfolders contain model folders with device.json
        final subPath = '$relativePath/${entry.name}';
        final subEntries = await _storage.listDirectory(subPath);
        for (final subEntry in subEntries) {
          if (subEntry.isDirectory) {
            final devicePath = '$subPath/${subEntry.name}/device.json';
            if (await _storage.exists(devicePath)) {
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
    final relativePath = project;
    if (!await _storage.directoryExists(relativePath)) return [];

    final entries = await _storage.listDirectory(relativePath);
    final architectures = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        architectures.add(entry.name);
      }
    }

    return architectures;
  }

  /// List models in a project/architecture (v2.0)
  Future<List<String>> listModels(String project, String architecture) async {
    final relativePath = '$project/$architecture';
    if (!await _storage.directoryExists(relativePath)) return [];

    final entries = await _storage.listDirectory(relativePath);
    final models = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        // Check if it has device.json
        final devicePath = '$relativePath/${entry.name}/device.json';
        if (await _storage.exists(devicePath)) {
          models.add(entry.name);
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
    final relativePath = '$project/$architecture/$model/device.json';
    try {
      final content = await _storage.readString(relativePath);
      if (content == null) return null;

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
    final relativePath = '$project/$architecture/$model';
    if (!await _storage.directoryExists(relativePath)) return [];

    final entries = await _storage.listDirectory(relativePath);
    final versions = <FirmwareVersion>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        final name = entry.name;
        // Skip non-version folders (like 'media', 'latest')
        if (name == 'media') continue;

        // Check for version.json or firmware.bin
        final versionPath = '$relativePath/$name/version.json';
        final firmwarePath = '$relativePath/$name/firmware.bin';

        if (await _storage.exists(versionPath)) {
          try {
            final content = await _storage.readString(versionPath);
            if (content != null) {
              final json = jsonDecode(content) as Map<String, dynamic>;
              versions.add(FirmwareVersion.fromJson(json));
            }
          } catch (e) {
            print('Error loading version $name: $e');
          }
        } else if (await _storage.exists(firmwarePath)) {
          // Create version from folder name (size not available via storage)
          versions.add(FirmwareVersion(
            version: name,
            size: 0, // Size not available without reading entire file
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
    if (!await _storage.directoryExists('')) return [];

    final entries = await _storage.listDirectory('');
    final families = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        final name = entry.name;
        // Skip extra folder and v2.0 project folders
        if (name != 'extra' && !await _isProjectFolder(name)) {
          // Check if it contains .json files (v1.0 format)
          final subEntries = await _storage.listDirectory(name);
          for (final subEntry in subEntries) {
            if (!subEntry.isDirectory && subEntry.name.endsWith('.json')) {
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
    if (!await _storage.directoryExists(family)) return [];

    final entries = await _storage.listDirectory(family);
    final devices = <String>[];
    for (final entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.json')) {
        devices.add(entry.name.replaceAll('.json', ''));
      }
    }

    return devices;
  }

  /// Load a device definition (v1.0)
  Future<DeviceDefinition?> loadDevice(String family, String deviceId) async {
    final relativePath = '$family/$deviceId.json';
    try {
      final content = await _storage.readString(relativePath);
      if (content == null) return null;

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
    final relativePath = '${device.family}/${device.id}.json';

    try {
      // Ensure directory exists
      await _storage.createDirectory(device.family);

      // Write JSON
      final json = device.toJson();
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await _storage.writeString(relativePath, content);

      return true;
    } catch (e) {
      print('Error saving device ${device.id}: $e');
      return false;
    }
  }

  /// Check if media file exists
  Future<bool> mediaExists(String family, String filename) async {
    final relativePath = '$family/media/$filename';
    return _storage.exists(relativePath);
  }

  /// Get media file path (returns absolute path for display)
  /// Note: For encrypted storage, this returns the virtual path which
  /// won't work for direct file access. Use readMediaBytes() instead.
  String getMediaPath(String family, String filename) {
    return '$basePath/$family/media/$filename';
  }

  /// Get media file path for v2.0 structure
  /// Note: For encrypted storage, this returns the virtual path which
  /// won't work for direct file access. Use readMediaBytesV2() instead.
  String getMediaPathV2(
    String project,
    String architecture,
    String model,
    String filename,
  ) {
    return '$basePath/$project/$architecture/$model/media/$filename';
  }

  /// Read media file bytes (works with encrypted storage)
  Future<List<int>?> readMediaBytes(String family, String filename) async {
    final relativePath = '$family/media/$filename';
    return _storage.readBytes(relativePath);
  }

  /// Read media file bytes for v2.0 structure (works with encrypted storage)
  Future<List<int>?> readMediaBytesV2(
    String project,
    String architecture,
    String model,
    String filename,
  ) async {
    final relativePath = '$project/$architecture/$model/media/$filename';
    return _storage.readBytes(relativePath);
  }

  /// Read firmware bytes (works with encrypted storage)
  Future<List<int>?> readFirmwareBytes(String relativePath) async {
    return _storage.readBytes(relativePath);
  }

  /// Check if storage is encrypted
  bool get isEncrypted => _storage.isEncrypted;
}
