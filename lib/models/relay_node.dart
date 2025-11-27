/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Relay node types
enum RelayType {
  root,
  node,
}

/// Relay node status
enum RelayNodeStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// Power source types for relay
enum PowerSource {
  grid,
  solar,
  battery,
  solarBattery,
  fuel,
  wind,
  gridUps,
  vehicle,
}

/// Binary caching policy
enum BinaryPolicy {
  textOnly,
  thumbnailsOnly,
  onDemand,
  fullCache,
}

/// Storage configuration for relay node
class RelayStorageConfig {
  final int allocatedMb;
  final BinaryPolicy binaryPolicy;
  final int thumbnailMaxKb;
  final int retentionDays;
  final int chatRetentionDays;
  final int resolvedReportRetentionDays;

  const RelayStorageConfig({
    this.allocatedMb = 500,
    this.binaryPolicy = BinaryPolicy.textOnly,
    this.thumbnailMaxKb = 10,
    this.retentionDays = 365,
    this.chatRetentionDays = 90,
    this.resolvedReportRetentionDays = 180,
  });

  factory RelayStorageConfig.fromJson(Map<String, dynamic> json) {
    return RelayStorageConfig(
      allocatedMb: json['allocatedMb'] as int? ?? 500,
      binaryPolicy: BinaryPolicy.values.firstWhere(
        (e) => e.name == json['binaryPolicy'],
        orElse: () => BinaryPolicy.textOnly,
      ),
      thumbnailMaxKb: json['thumbnailMaxKb'] as int? ?? 10,
      retentionDays: json['retentionDays'] as int? ?? 365,
      chatRetentionDays: json['chatRetentionDays'] as int? ?? 90,
      resolvedReportRetentionDays: json['resolvedReportRetentionDays'] as int? ?? 180,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'allocatedMb': allocatedMb,
      'binaryPolicy': binaryPolicy.name,
      'thumbnailMaxKb': thumbnailMaxKb,
      'retentionDays': retentionDays,
      'chatRetentionDays': chatRetentionDays,
      'resolvedReportRetentionDays': resolvedReportRetentionDays,
    };
  }

  RelayStorageConfig copyWith({
    int? allocatedMb,
    BinaryPolicy? binaryPolicy,
    int? thumbnailMaxKb,
    int? retentionDays,
    int? chatRetentionDays,
    int? resolvedReportRetentionDays,
  }) {
    return RelayStorageConfig(
      allocatedMb: allocatedMb ?? this.allocatedMb,
      binaryPolicy: binaryPolicy ?? this.binaryPolicy,
      thumbnailMaxKb: thumbnailMaxKb ?? this.thumbnailMaxKb,
      retentionDays: retentionDays ?? this.retentionDays,
      chatRetentionDays: chatRetentionDays ?? this.chatRetentionDays,
      resolvedReportRetentionDays: resolvedReportRetentionDays ?? this.resolvedReportRetentionDays,
    );
  }
}

/// Geographic coverage configuration
class GeographicCoverage {
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String? locationName;

  const GeographicCoverage({
    required this.latitude,
    required this.longitude,
    this.radiusKm = 50.0,
    this.locationName,
  });

  factory GeographicCoverage.fromJson(Map<String, dynamic> json) {
    return GeographicCoverage(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 50.0,
      locationName: json['locationName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'radiusKm': radiusKm,
      if (locationName != null) 'locationName': locationName,
    };
  }

  GeographicCoverage copyWith({
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? locationName,
  }) {
    return GeographicCoverage(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      locationName: locationName ?? this.locationName,
    );
  }
}

/// Power configuration for relay
class PowerConfig {
  final PowerSource primarySource;
  final bool gridConnected;
  final int? batteryPercent;
  final int? solarWatts;
  final int? estimatedRuntimeHours;

  const PowerConfig({
    this.primarySource = PowerSource.grid,
    this.gridConnected = true,
    this.batteryPercent,
    this.solarWatts,
    this.estimatedRuntimeHours,
  });

  factory PowerConfig.fromJson(Map<String, dynamic> json) {
    return PowerConfig(
      primarySource: PowerSource.values.firstWhere(
        (e) => e.name == json['primarySource'],
        orElse: () => PowerSource.grid,
      ),
      gridConnected: json['gridConnected'] as bool? ?? true,
      batteryPercent: json['batteryPercent'] as int?,
      solarWatts: json['solarWatts'] as int?,
      estimatedRuntimeHours: json['estimatedRuntimeHours'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primarySource': primarySource.name,
      'gridConnected': gridConnected,
      if (batteryPercent != null) 'batteryPercent': batteryPercent,
      if (solarWatts != null) 'solarWatts': solarWatts,
      if (estimatedRuntimeHours != null) 'estimatedRuntimeHours': estimatedRuntimeHours,
    };
  }
}

/// Channel configuration
class ChannelConfig {
  final String type;
  final bool enabled;
  final String? interfaceName;
  final Map<String, dynamic> settings;

  const ChannelConfig({
    required this.type,
    this.enabled = false,
    this.interfaceName,
    this.settings = const {},
  });

  factory ChannelConfig.fromJson(Map<String, dynamic> json) {
    return ChannelConfig(
      type: json['type'] as String,
      enabled: json['enabled'] as bool? ?? false,
      interfaceName: json['interfaceName'] as String?,
      settings: (json['settings'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'enabled': enabled,
      if (interfaceName != null) 'interfaceName': interfaceName,
      if (settings.isNotEmpty) 'settings': settings,
    };
  }
}

/// Relay node configuration
class RelayNodeConfig {
  final RelayStorageConfig storage;
  final GeographicCoverage? coverage;
  final PowerConfig power;
  final List<ChannelConfig> channels;
  final List<String> supportedCollections;
  final bool acceptConnections;
  final int maxConnections;

  const RelayNodeConfig({
    this.storage = const RelayStorageConfig(),
    this.coverage,
    this.power = const PowerConfig(),
    this.channels = const [],
    this.supportedCollections = const ['reports', 'places', 'events'],
    this.acceptConnections = true,
    this.maxConnections = 50,
  });

  factory RelayNodeConfig.fromJson(Map<String, dynamic> json) {
    return RelayNodeConfig(
      storage: json['storage'] != null
          ? RelayStorageConfig.fromJson(json['storage'] as Map<String, dynamic>)
          : const RelayStorageConfig(),
      coverage: json['coverage'] != null
          ? GeographicCoverage.fromJson(json['coverage'] as Map<String, dynamic>)
          : null,
      power: json['power'] != null
          ? PowerConfig.fromJson(json['power'] as Map<String, dynamic>)
          : const PowerConfig(),
      channels: (json['channels'] as List<dynamic>?)
              ?.map((e) => ChannelConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      supportedCollections: (json['supportedCollections'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['reports', 'places', 'events'],
      acceptConnections: json['acceptConnections'] as bool? ?? true,
      maxConnections: json['maxConnections'] as int? ?? 50,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'storage': storage.toJson(),
      if (coverage != null) 'coverage': coverage!.toJson(),
      'power': power.toJson(),
      'channels': channels.map((e) => e.toJson()).toList(),
      'supportedCollections': supportedCollections,
      'acceptConnections': acceptConnections,
      'maxConnections': maxConnections,
    };
  }

  RelayNodeConfig copyWith({
    RelayStorageConfig? storage,
    GeographicCoverage? coverage,
    PowerConfig? power,
    List<ChannelConfig>? channels,
    List<String>? supportedCollections,
    bool? acceptConnections,
    int? maxConnections,
  }) {
    return RelayNodeConfig(
      storage: storage ?? this.storage,
      coverage: coverage ?? this.coverage,
      power: power ?? this.power,
      channels: channels ?? this.channels,
      supportedCollections: supportedCollections ?? this.supportedCollections,
      acceptConnections: acceptConnections ?? this.acceptConnections,
      maxConnections: maxConnections ?? this.maxConnections,
    );
  }
}

/// Statistics for relay node
class RelayNodeStats {
  final int connectedDevices;
  final int messagesRelayed;
  final int collectionsServed;
  final int storageUsedMb;
  final DateTime? lastActivity;
  final Duration uptime;

  const RelayNodeStats({
    this.connectedDevices = 0,
    this.messagesRelayed = 0,
    this.collectionsServed = 0,
    this.storageUsedMb = 0,
    this.lastActivity,
    this.uptime = Duration.zero,
  });

  factory RelayNodeStats.fromJson(Map<String, dynamic> json) {
    return RelayNodeStats(
      connectedDevices: json['connectedDevices'] as int? ?? 0,
      messagesRelayed: json['messagesRelayed'] as int? ?? 0,
      collectionsServed: json['collectionsServed'] as int? ?? 0,
      storageUsedMb: json['storageUsedMb'] as int? ?? 0,
      lastActivity: json['lastActivity'] != null
          ? DateTime.parse(json['lastActivity'] as String)
          : null,
      uptime: Duration(seconds: json['uptimeSeconds'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connectedDevices': connectedDevices,
      'messagesRelayed': messagesRelayed,
      'collectionsServed': collectionsServed,
      'storageUsedMb': storageUsedMb,
      if (lastActivity != null) 'lastActivity': lastActivity!.toIso8601String(),
      'uptimeSeconds': uptime.inSeconds,
    };
  }
}

/// Represents this device operating as a relay
class RelayNode {
  final String id;
  final String name;

  // Relay identity (X3 prefix) - the relay device's own keypair
  final String relayCallsign;  // X3 callsign derived from relay npub
  final String relayNpub;      // Relay's public key
  final String relayNsec;      // Relay's private key (secret)

  // Operator identity (X1 prefix) - the human managing this relay
  final String operatorCallsign;  // X1 callsign of the operator
  final String operatorNpub;      // Operator's public key

  final RelayType type;
  final String? networkId;
  final String? networkName;
  final String? rootNpub;
  final String? rootCallsign;
  final RelayNodeConfig config;
  final RelayNodeStatus status;
  final RelayNodeStats stats;
  final String? errorMessage;
  final DateTime created;
  final DateTime updated;

  const RelayNode({
    required this.id,
    required this.name,
    required this.relayCallsign,
    required this.relayNpub,
    required this.relayNsec,
    required this.operatorCallsign,
    required this.operatorNpub,
    required this.type,
    this.networkId,
    this.networkName,
    this.rootNpub,
    this.rootCallsign,
    this.config = const RelayNodeConfig(),
    this.status = RelayNodeStatus.stopped,
    this.stats = const RelayNodeStats(),
    this.errorMessage,
    required this.created,
    required this.updated,
  });

  /// Backwards compatibility: returns relay callsign
  String get callsign => relayCallsign;

  /// Backwards compatibility: returns relay npub
  String get npub => relayNpub;

  /// Check if this is a root relay
  bool get isRoot => type == RelayType.root;

  /// Check if this is a node relay
  bool get isNode => type == RelayType.node;

  /// Check if relay is running
  bool get isRunning => status == RelayNodeStatus.running;

  /// Get status display text
  String get statusDisplay {
    switch (status) {
      case RelayNodeStatus.stopped:
        return 'Stopped';
      case RelayNodeStatus.starting:
        return 'Starting...';
      case RelayNodeStatus.running:
        return 'Running';
      case RelayNodeStatus.stopping:
        return 'Stopping...';
      case RelayNodeStatus.error:
        return 'Error';
    }
  }

  /// Get type display text
  String get typeDisplay {
    switch (type) {
      case RelayType.root:
        return 'Root Relay';
      case RelayType.node:
        return 'Node Relay';
    }
  }

  factory RelayNode.fromJson(Map<String, dynamic> json) {
    // Handle backwards compatibility for old format
    final relayCallsign = json['relayCallsign'] as String? ?? json['callsign'] as String;
    final relayNpub = json['relayNpub'] as String? ?? json['npub'] as String;
    final relayNsec = json['relayNsec'] as String? ?? '';
    final operatorCallsign = json['operatorCallsign'] as String? ?? json['callsign'] as String;
    final operatorNpub = json['operatorNpub'] as String? ?? json['npub'] as String;

    return RelayNode(
      id: json['id'] as String,
      name: json['name'] as String,
      relayCallsign: relayCallsign,
      relayNpub: relayNpub,
      relayNsec: relayNsec,
      operatorCallsign: operatorCallsign,
      operatorNpub: operatorNpub,
      type: RelayType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RelayType.node,
      ),
      networkId: json['networkId'] as String?,
      networkName: json['networkName'] as String?,
      rootNpub: json['rootNpub'] as String?,
      rootCallsign: json['rootCallsign'] as String?,
      config: json['config'] != null
          ? RelayNodeConfig.fromJson(json['config'] as Map<String, dynamic>)
          : const RelayNodeConfig(),
      status: RelayNodeStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RelayNodeStatus.stopped,
      ),
      stats: json['stats'] != null
          ? RelayNodeStats.fromJson(json['stats'] as Map<String, dynamic>)
          : const RelayNodeStats(),
      errorMessage: json['errorMessage'] as String?,
      created: DateTime.parse(json['created'] as String),
      updated: DateTime.parse(json['updated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relayCallsign': relayCallsign,
      'relayNpub': relayNpub,
      'relayNsec': relayNsec,
      'operatorCallsign': operatorCallsign,
      'operatorNpub': operatorNpub,
      'type': type.name,
      if (networkId != null) 'networkId': networkId,
      if (networkName != null) 'networkName': networkName,
      if (rootNpub != null) 'rootNpub': rootNpub,
      if (rootCallsign != null) 'rootCallsign': rootCallsign,
      'config': config.toJson(),
      'status': status.name,
      'stats': stats.toJson(),
      if (errorMessage != null) 'errorMessage': errorMessage,
      'created': created.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  RelayNode copyWith({
    String? id,
    String? name,
    String? relayCallsign,
    String? relayNpub,
    String? relayNsec,
    String? operatorCallsign,
    String? operatorNpub,
    RelayType? type,
    String? networkId,
    String? networkName,
    String? rootNpub,
    String? rootCallsign,
    RelayNodeConfig? config,
    RelayNodeStatus? status,
    RelayNodeStats? stats,
    String? errorMessage,
    DateTime? created,
    DateTime? updated,
  }) {
    return RelayNode(
      id: id ?? this.id,
      name: name ?? this.name,
      relayCallsign: relayCallsign ?? this.relayCallsign,
      relayNpub: relayNpub ?? this.relayNpub,
      relayNsec: relayNsec ?? this.relayNsec,
      operatorCallsign: operatorCallsign ?? this.operatorCallsign,
      operatorNpub: operatorNpub ?? this.operatorNpub,
      type: type ?? this.type,
      networkId: networkId ?? this.networkId,
      networkName: networkName ?? this.networkName,
      rootNpub: rootNpub ?? this.rootNpub,
      rootCallsign: rootCallsign ?? this.rootCallsign,
      config: config ?? this.config,
      status: status ?? this.status,
      stats: stats ?? this.stats,
      errorMessage: errorMessage ?? this.errorMessage,
      created: created ?? this.created,
      updated: updated ?? this.updated,
    );
  }
}
