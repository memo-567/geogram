/// Device definition model for the Flasher app.
///
/// Represents a flashable device with its configuration, USB identifiers,
/// and flashing parameters.

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
  final String id;
  final String family;
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

  // Runtime properties (not serialized)
  String? _basePath;

  DeviceDefinition({
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
  });

  /// Set base path for resolving media paths
  void setBasePath(String path) {
    _basePath = path;
  }

  /// Get full path to photo
  String? get photoPath {
    if (media?.photo == null || _basePath == null) return null;
    return '$_basePath/media/${media!.photo}';
  }

  /// Get description in specified language, falling back to default
  String getDescription(String language) {
    return translations?.getField(language, 'description') ?? description;
  }

  factory DeviceDefinition.fromJson(Map<String, dynamic> json) {
    return DeviceDefinition(
      id: json['id'] as String,
      family: json['family'] as String,
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
    );
  }

  Map<String, dynamic> toJson() => {
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
      };
}

/// Device family metadata
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

/// Flasher collection metadata
class FlasherMetadata {
  final String version;
  final String name;
  final String description;
  final List<DeviceFamily> families;
  final String createdAt;
  final String modifiedAt;

  const FlasherMetadata({
    required this.version,
    required this.name,
    required this.description,
    required this.families,
    required this.createdAt,
    required this.modifiedAt,
  });

  factory FlasherMetadata.fromJson(Map<String, dynamic> json) {
    return FlasherMetadata(
      version: json['version'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      families: (json['families'] as List<dynamic>)
          .map((e) => DeviceFamily.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] as String,
      modifiedAt: json['modified_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'description': description,
        'families': families.map((e) => e.toJson()).toList(),
        'created_at': createdAt,
        'modified_at': modifiedAt,
      };
}
