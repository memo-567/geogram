/// Device definition model for the Flasher app.
///
/// Represents a flashable device with its configuration, USB identifiers,
/// and flashing parameters.

/// Firmware version information
class FirmwareVersion {
  final String version;
  final String? releaseNotes;
  final String? releaseDate;
  final String? checksum; // SHA256
  final int? size; // Bytes

  const FirmwareVersion({
    required this.version,
    this.releaseNotes,
    this.releaseDate,
    this.checksum,
    this.size,
  });

  /// Path relative to device folder
  String get firmwarePath => '$version/firmware.bin';

  factory FirmwareVersion.fromJson(Map<String, dynamic> json) {
    return FirmwareVersion(
      version: json['version'] as String,
      releaseNotes: json['release_notes'] as String?,
      releaseDate: json['release_date'] as String?,
      checksum: json['checksum'] as String?,
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        if (releaseNotes != null) 'release_notes': releaseNotes,
        if (releaseDate != null) 'release_date': releaseDate,
        if (checksum != null) 'checksum': checksum,
        if (size != null) 'size': size,
      };

  @override
  String toString() => 'FirmwareVersion(version: $version)';
}

/// USB identification for a device
class UsbIdentifier {
  final String vid;
  final String pid;
  final String? description;

  const UsbIdentifier({
    required this.vid,
    required this.pid,
    this.description,
  });

  /// Parse VID as integer (handles 0x prefix)
  int get vidInt => int.parse(vid.replaceFirst('0x', ''), radix: 16);

  /// Parse PID as integer (handles 0x prefix)
  int get pidInt => int.parse(pid.replaceFirst('0x', ''), radix: 16);

  factory UsbIdentifier.fromJson(Map<String, dynamic> json) {
    return UsbIdentifier(
      vid: json['vid'] as String,
      pid: json['pid'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'vid': vid,
        'pid': pid,
        if (description != null) 'description': description,
      };
}

/// Flash configuration for a device
class FlashConfig {
  final String protocol;
  final int baudRate;
  final String? flashMode;
  final String? flashFreq;
  final String? flashSize;
  final String? partitions;
  final String? firmwareAsset;
  final String? firmwareUrl;
  final int bootDelayMs;
  final bool stubRequired;
  final int flashOffset;

  const FlashConfig({
    required this.protocol,
    this.baudRate = 115200,
    this.flashMode,
    this.flashFreq,
    this.flashSize,
    this.partitions,
    this.firmwareAsset,
    this.firmwareUrl,
    this.bootDelayMs = 100,
    this.stubRequired = false,
    this.flashOffset = 0x10000,
  });

  factory FlashConfig.fromJson(Map<String, dynamic> json) {
    return FlashConfig(
      protocol: json['protocol'] as String,
      baudRate: json['baud_rate'] as int? ?? 115200,
      flashMode: json['flash_mode'] as String?,
      flashFreq: json['flash_freq'] as String?,
      flashSize: json['flash_size'] as String?,
      partitions: json['partitions'] as String?,
      firmwareAsset: json['firmware_asset'] as String?,
      firmwareUrl: json['firmware_url'] as String?,
      bootDelayMs: json['boot_delay_ms'] as int? ?? 100,
      stubRequired: json['stub_required'] as bool? ?? false,
      flashOffset: json['flash_offset'] as int? ?? 0x10000,
    );
  }

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'baud_rate': baudRate,
        if (flashMode != null) 'flash_mode': flashMode,
        if (flashFreq != null) 'flash_freq': flashFreq,
        if (flashSize != null) 'flash_size': flashSize,
        if (partitions != null) 'partitions': partitions,
        if (firmwareAsset != null) 'firmware_asset': firmwareAsset,
        if (firmwareUrl != null) 'firmware_url': firmwareUrl,
        if (bootDelayMs != 100) 'boot_delay_ms': bootDelayMs,
        if (stubRequired) 'stub_required': stubRequired,
        if (flashOffset != 0x10000) 'flash_offset': flashOffset,
      };
}

/// Media references for a device
class DeviceMedia {
  final String? photo;
  final String? photoHash;

  const DeviceMedia({
    this.photo,
    this.photoHash,
  });

  factory DeviceMedia.fromJson(Map<String, dynamic> json) {
    return DeviceMedia(
      photo: json['photo'] as String?,
      photoHash: json['photo_hash'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (photo != null) 'photo': photo,
        if (photoHash != null) 'photo_hash': photoHash,
      };
}

/// Purchase link for a device
class PurchaseLink {
  final String vendor;
  final String url;

  const PurchaseLink({
    required this.vendor,
    required this.url,
  });

  factory PurchaseLink.fromJson(Map<String, dynamic> json) {
    return PurchaseLink(
      vendor: json['vendor'] as String,
      url: json['url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'vendor': vendor,
        'url': url,
      };
}

/// External links for a device
class DeviceLinks {
  final String? documentation;
  final String? datasheet;
  final List<PurchaseLink> purchase;

  const DeviceLinks({
    this.documentation,
    this.datasheet,
    this.purchase = const [],
  });

  factory DeviceLinks.fromJson(Map<String, dynamic> json) {
    return DeviceLinks(
      documentation: json['documentation'] as String?,
      datasheet: json['datasheet'] as String?,
      purchase: (json['purchase'] as List<dynamic>?)
              ?.map((e) => PurchaseLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        if (documentation != null) 'documentation': documentation,
        if (datasheet != null) 'datasheet': datasheet,
        if (purchase.isNotEmpty)
          'purchase': purchase.map((e) => e.toJson()).toList(),
      };
}

/// Translations for a device
class DeviceTranslations {
  final Map<String, Map<String, String>> _translations;

  const DeviceTranslations(this._translations);

  factory DeviceTranslations.fromJson(Map<String, dynamic> json) {
    final translations = <String, Map<String, String>>{};
    for (final entry in json.entries) {
      translations[entry.key] =
          Map<String, String>.from(entry.value as Map<String, dynamic>);
    }
    return DeviceTranslations(translations);
  }

  Map<String, dynamic> toJson() => _translations;

  /// Get translated field for a language
  String? getField(String language, String field) {
    return _translations[language]?[field];
  }

  /// Get list of available languages
  List<String> get languages => _translations.keys.toList();
}

/// Device definition for a flashable device
class DeviceDefinition {
  // New hierarchical identifiers (v2.0)
  final String? project; // e.g., "geogram", "quansheng"
  final String? architecture; // e.g., "esp32" (chip family)
  final String? model; // e.g., "esp32-c3-mini" (board)

  // Legacy identifiers (v1.0 - kept for backward compatibility)
  final String id; // Legacy: same as model
  final String family; // Legacy: same as architecture

  final String chip;
  final String title;
  final String description;
  final DeviceTranslations? translations;
  final DeviceMedia? media;
  final DeviceLinks? links;
  final FlashConfig flash;
  final UsbIdentifier? usb;
  final String createdAt;
  final String modifiedAt;

  // Version tracking (v2.0)
  final List<FirmwareVersion> versions;
  final String? latestVersion;
  final FirmwareVersion? selectedVersion; // Runtime selection

  // Runtime properties (not serialized)
  String? _basePath;

  DeviceDefinition({
    this.project,
    this.architecture,
    this.model,
    required this.id,
    required this.family,
    required this.chip,
    required this.title,
    required this.description,
    this.translations,
    this.media,
    this.links,
    required this.flash,
    this.usb,
    required this.createdAt,
    required this.modifiedAt,
    this.versions = const [],
    this.latestVersion,
    this.selectedVersion,
  });

  /// Create a generic ESP32 device definition for custom firmware flashing
  factory DeviceDefinition.genericEsp32() {
    return DeviceDefinition(
      id: 'generic-esp32',
      family: 'esp32',
      chip: 'ESP32',
      title: 'Generic ESP32',
      description: 'Generic ESP32 device for custom firmware',
      flash: const FlashConfig(protocol: 'esptool'),
      createdAt: '',
      modifiedAt: '',
    );
  }

  /// Get effective model ID (new or legacy)
  String get effectiveModel => model ?? id;

  /// Get effective architecture (new or legacy)
  String get effectiveArchitecture => architecture ?? family;

  /// Get effective project (defaults to "geogram")
  String get effectiveProject => project ?? 'geogram';

  /// Set base path for resolving media paths
  void setBasePath(String path) {
    _basePath = path;
  }

  /// Get base path
  String? get basePath => _basePath;

  /// Get full path to photo
  String? get photoPath {
    if (media?.photo == null || _basePath == null) return null;
    return '$_basePath/media/${media!.photo}';
  }

  /// Get description in specified language, falling back to default
  String getDescription(String language) {
    return translations?.getField(language, 'description') ?? description;
  }

  /// Get the latest firmware version object
  FirmwareVersion? get latestFirmwareVersion {
    if (versions.isEmpty) return null;
    if (latestVersion != null) {
      return versions.cast<FirmwareVersion?>().firstWhere(
            (v) => v?.version == latestVersion,
            orElse: () => null,
          );
    }
    return versions.first;
  }

  /// Create a copy with a selected version
  DeviceDefinition withSelectedVersion(FirmwareVersion? version) {
    return DeviceDefinition(
      project: project,
      architecture: architecture,
      model: model,
      id: id,
      family: family,
      chip: chip,
      title: title,
      description: description,
      translations: translations,
      media: media,
      links: links,
      flash: flash,
      usb: usb,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      versions: versions,
      latestVersion: latestVersion,
      selectedVersion: version,
    ).._basePath = _basePath;
  }

  factory DeviceDefinition.fromJson(Map<String, dynamic> json) {
    // Support both v1.0 (family/id) and v2.0 (project/architecture/model)
    final architecture = json['architecture'] as String?;
    final family = json['family'] as String? ?? architecture ?? 'unknown';

    final model = json['model'] as String?;
    final id = json['id'] as String? ?? model ?? 'unknown';

    return DeviceDefinition(
      project: json['project'] as String?,
      architecture: architecture,
      model: model,
      id: id,
      family: family,
      chip: json['chip'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      translations: json['translations'] != null
          ? DeviceTranslations.fromJson(
              json['translations'] as Map<String, dynamic>)
          : null,
      media: json['media'] != null
          ? DeviceMedia.fromJson(json['media'] as Map<String, dynamic>)
          : null,
      links: json['links'] != null
          ? DeviceLinks.fromJson(json['links'] as Map<String, dynamic>)
          : null,
      flash: FlashConfig.fromJson(json['flash'] as Map<String, dynamic>),
      usb: json['usb'] != null
          ? UsbIdentifier.fromJson(json['usb'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as String,
      modifiedAt: json['modified_at'] as String,
      versions: (json['versions'] as List<dynamic>?)
              ?.map((e) => FirmwareVersion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      latestVersion: json['latest_version'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (project != null) 'project': project,
        if (architecture != null) 'architecture': architecture,
        if (model != null) 'model': model,
        'id': id,
        'family': family,
        'chip': chip,
        'title': title,
        'description': description,
        if (translations != null) 'translations': translations!.toJson(),
        if (media != null) 'media': media!.toJson(),
        if (links != null) 'links': links!.toJson(),
        'flash': flash.toJson(),
        if (usb != null) 'usb': usb!.toJson(),
        'created_at': createdAt,
        'modified_at': modifiedAt,
        if (versions.isNotEmpty)
          'versions': versions.map((v) => v.toJson()).toList(),
        if (latestVersion != null) 'latest_version': latestVersion,
      };
}

/// Device family metadata (v1.0 format)
class DeviceFamily {
  final String id;
  final String name;
  final String description;
  final String protocol;

  const DeviceFamily({
    required this.id,
    required this.name,
    required this.description,
    required this.protocol,
  });

  factory DeviceFamily.fromJson(Map<String, dynamic> json) {
    return DeviceFamily(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      protocol: json['protocol'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'protocol': protocol,
      };
}

/// Project metadata (v2.0 format)
class FlasherProject {
  final String id;
  final String name;
  final String? description;
  final List<String> architectures;

  const FlasherProject({
    required this.id,
    required this.name,
    this.description,
    required this.architectures,
  });

  factory FlasherProject.fromJson(Map<String, dynamic> json) {
    return FlasherProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      architectures: (json['architectures'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'architectures': architectures,
      };
}

/// Flasher collection metadata
class FlasherMetadata {
  final String version;
  final String name;
  final String description;
  final List<DeviceFamily> families; // v1.0 format
  final List<FlasherProject> projects; // v2.0 format
  final String createdAt;
  final String modifiedAt;

  const FlasherMetadata({
    required this.version,
    required this.name,
    required this.description,
    this.families = const [],
    this.projects = const [],
    required this.createdAt,
    required this.modifiedAt,
  });

  /// Check if this is v2.0 format
  bool get isV2 => version.startsWith('2');

  factory FlasherMetadata.fromJson(Map<String, dynamic> json) {
    return FlasherMetadata(
      version: json['version'] as String,
      name: json['name'] as String? ?? 'Flasher',
      description: json['description'] as String? ?? '',
      families: (json['families'] as List<dynamic>?)
              ?.map((e) => DeviceFamily.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      projects: (json['projects'] as List<dynamic>?)
              ?.map((e) => FlasherProject.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] as String? ?? '',
      modifiedAt: json['modified_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'description': description,
        if (families.isNotEmpty)
          'families': families.map((e) => e.toJson()).toList(),
        if (projects.isNotEmpty)
          'projects': projects.map((e) => e.toJson()).toList(),
        'created_at': createdAt,
        'modified_at': modifiedAt,
      };
}
