/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Node registration policy
enum NodeRegistrationPolicy {
  open,
  approval,
  invite,
}

/// User registration policy
enum UserRegistrationPolicy {
  open,
  approval,
}

/// Network policy configuration
class NetworkPolicy {
  final NodeRegistrationPolicy nodeRegistration;
  final UserRegistrationPolicy userRegistration;
  final bool enableCommunityFlagging;
  final int flagThresholdHide;
  final int flagThresholdReview;
  final bool allowFederation;
  final bool autoAcceptFederation;

  const NetworkPolicy({
    this.nodeRegistration = NodeRegistrationPolicy.open,
    this.userRegistration = UserRegistrationPolicy.open,
    this.enableCommunityFlagging = true,
    this.flagThresholdHide = 5,
    this.flagThresholdReview = 10,
    this.allowFederation = true,
    this.autoAcceptFederation = false,
  });

  factory NetworkPolicy.fromJson(Map<String, dynamic> json) {
    return NetworkPolicy(
      nodeRegistration: NodeRegistrationPolicy.values.firstWhere(
        (e) => e.name == json['nodeRegistration'],
        orElse: () => NodeRegistrationPolicy.open,
      ),
      userRegistration: UserRegistrationPolicy.values.firstWhere(
        (e) => e.name == json['userRegistration'],
        orElse: () => UserRegistrationPolicy.open,
      ),
      enableCommunityFlagging: json['enableCommunityFlagging'] as bool? ?? true,
      flagThresholdHide: json['flagThresholdHide'] as int? ?? 5,
      flagThresholdReview: json['flagThresholdReview'] as int? ?? 10,
      allowFederation: json['allowFederation'] as bool? ?? true,
      autoAcceptFederation: json['autoAcceptFederation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeRegistration': nodeRegistration.name,
      'userRegistration': userRegistration.name,
      'enableCommunityFlagging': enableCommunityFlagging,
      'flagThresholdHide': flagThresholdHide,
      'flagThresholdReview': flagThresholdReview,
      'allowFederation': allowFederation,
      'autoAcceptFederation': autoAcceptFederation,
    };
  }

  NetworkPolicy copyWith({
    NodeRegistrationPolicy? nodeRegistration,
    UserRegistrationPolicy? userRegistration,
    bool? enableCommunityFlagging,
    int? flagThresholdHide,
    int? flagThresholdReview,
    bool? allowFederation,
    bool? autoAcceptFederation,
  }) {
    return NetworkPolicy(
      nodeRegistration: nodeRegistration ?? this.nodeRegistration,
      userRegistration: userRegistration ?? this.userRegistration,
      enableCommunityFlagging: enableCommunityFlagging ?? this.enableCommunityFlagging,
      flagThresholdHide: flagThresholdHide ?? this.flagThresholdHide,
      flagThresholdReview: flagThresholdReview ?? this.flagThresholdReview,
      allowFederation: allowFederation ?? this.allowFederation,
      autoAcceptFederation: autoAcceptFederation ?? this.autoAcceptFederation,
    );
  }
}

/// Collections configuration for network
class NetworkCollections {
  final List<String> community;
  final List<String> public;
  final List<String> userApprovalRequired;

  const NetworkCollections({
    this.community = const ['reports', 'places', 'events'],
    this.public = const ['forum', 'chat', 'announcements'],
    this.userApprovalRequired = const ['shops', 'services'],
  });

  factory NetworkCollections.fromJson(Map<String, dynamic> json) {
    return NetworkCollections(
      community: (json['community'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['reports', 'places', 'events'],
      public: (json['public'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['forum', 'chat', 'announcements'],
      userApprovalRequired: (json['userApprovalRequired'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['shops', 'services'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'community': community,
      'public': public,
      'userApprovalRequired': userApprovalRequired,
    };
  }

  /// Get all supported collection types
  List<String> get all => [...community, ...public, ...userApprovalRequired];
}

/// Network statistics
class NetworkStats {
  final int totalNodes;
  final int onlineNodes;
  final int totalUsers;
  final int activeUsers;
  final DateTime? lastActivity;

  const NetworkStats({
    this.totalNodes = 0,
    this.onlineNodes = 0,
    this.totalUsers = 0,
    this.activeUsers = 0,
    this.lastActivity,
  });

  factory NetworkStats.fromJson(Map<String, dynamic> json) {
    return NetworkStats(
      totalNodes: json['totalNodes'] as int? ?? 0,
      onlineNodes: json['onlineNodes'] as int? ?? 0,
      totalUsers: json['totalUsers'] as int? ?? 0,
      activeUsers: json['activeUsers'] as int? ?? 0,
      lastActivity: json['lastActivity'] != null
          ? DateTime.parse(json['lastActivity'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalNodes': totalNodes,
      'onlineNodes': onlineNodes,
      'totalUsers': totalUsers,
      'activeUsers': activeUsers,
      if (lastActivity != null) 'lastActivity': lastActivity!.toIso8601String(),
    };
  }
}

/// Represents a station network
class StationNetwork {
  final String id;
  final String name;
  final String description;
  final String rootNpub;
  final String rootCallsign;
  final String? rootUrl;
  final NetworkPolicy policy;
  final NetworkCollections collections;
  final NetworkStats stats;
  final DateTime founded;
  final DateTime updated;

  const StationNetwork({
    required this.id,
    required this.name,
    this.description = '',
    required this.rootNpub,
    required this.rootCallsign,
    this.rootUrl,
    this.policy = const NetworkPolicy(),
    this.collections = const NetworkCollections(),
    this.stats = const NetworkStats(),
    required this.founded,
    required this.updated,
  });

  factory StationNetwork.fromJson(Map<String, dynamic> json) {
    return StationNetwork(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      rootNpub: json['rootNpub'] as String,
      rootCallsign: json['rootCallsign'] as String,
      rootUrl: json['rootUrl'] as String?,
      policy: json['policy'] != null
          ? NetworkPolicy.fromJson(json['policy'] as Map<String, dynamic>)
          : const NetworkPolicy(),
      collections: json['collections'] != null
          ? NetworkCollections.fromJson(json['collections'] as Map<String, dynamic>)
          : const NetworkCollections(),
      stats: json['stats'] != null
          ? NetworkStats.fromJson(json['stats'] as Map<String, dynamic>)
          : const NetworkStats(),
      founded: DateTime.parse(json['founded'] as String),
      updated: DateTime.parse(json['updated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'rootNpub': rootNpub,
      'rootCallsign': rootCallsign,
      if (rootUrl != null) 'rootUrl': rootUrl,
      'policy': policy.toJson(),
      'collections': collections.toJson(),
      'stats': stats.toJson(),
      'founded': founded.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  StationNetwork copyWith({
    String? id,
    String? name,
    String? description,
    String? rootNpub,
    String? rootCallsign,
    String? rootUrl,
    NetworkPolicy? policy,
    NetworkCollections? collections,
    NetworkStats? stats,
    DateTime? founded,
    DateTime? updated,
  }) {
    return StationNetwork(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rootNpub: rootNpub ?? this.rootNpub,
      rootCallsign: rootCallsign ?? this.rootCallsign,
      rootUrl: rootUrl ?? this.rootUrl,
      policy: policy ?? this.policy,
      collections: collections ?? this.collections,
      stats: stats ?? this.stats,
      founded: founded ?? this.founded,
      updated: updated ?? this.updated,
    );
  }
}
