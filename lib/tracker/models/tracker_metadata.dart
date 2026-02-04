/// NOSTR signature metadata for tracker items
class TrackerNostrMetadata {
  final String npub;
  final String? signature;
  final String? createdAt;
  final List<String>? signedFields;
  final String? signatureVersion;

  const TrackerNostrMetadata({
    required this.npub,
    this.signature,
    this.createdAt,
    this.signedFields,
    this.signatureVersion,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'npub': npub,
    };

    if (signature != null) json['signature'] = signature;
    if (createdAt != null) json['created_at'] = createdAt;
    if (signedFields != null && signedFields!.isNotEmpty) {
      json['signed_fields'] = signedFields;
    }
    if (signatureVersion != null) {
      json['signature_version'] = signatureVersion;
    }

    return json;
  }

  factory TrackerNostrMetadata.fromJson(Map<String, dynamic> json) {
    return TrackerNostrMetadata(
      npub: json['npub'] as String,
      signature: json['signature'] as String?,
      createdAt: json['created_at'] as String?,
      signedFields: (json['signed_fields'] as List<dynamic>?)
          ?.map((s) => s as String)
          .toList(),
      signatureVersion: json['signature_version'] as String?,
    );
  }

  TrackerNostrMetadata copyWith({
    String? npub,
    String? signature,
    String? createdAt,
    List<String>? signedFields,
    String? signatureVersion,
  }) {
    return TrackerNostrMetadata(
      npub: npub ?? this.npub,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
      signedFields: signedFields ?? this.signedFields,
      signatureVersion: signatureVersion ?? this.signatureVersion,
    );
  }
}

/// App metadata for tracker
class TrackerAppMetadata {
  final String id;
  final String type;
  final String version;
  final String title;
  final String? description;
  final String createdAt;
  final String updatedAt;
  final String ownerCallsign;
  final TrackerFeatures features;
  final TrackerNostrMetadata? metadata;

  const TrackerAppMetadata({
    required this.id,
    this.type = 'tracker',
    this.version = '1.0.0',
    required this.title,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerCallsign,
    this.features = const TrackerFeatures(),
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'version': version,
        'title': title,
        if (description != null) 'description': description,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'owner_callsign': ownerCallsign,
        'features': features.toJson(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory TrackerAppMetadata.fromJson(Map<String, dynamic> json) {
    return TrackerAppMetadata(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'tracker',
      version: json['version'] as String? ?? '1.0.0',
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      ownerCallsign: json['owner_callsign'] as String,
      features: json['features'] != null
          ? TrackerFeatures.fromJson(json['features'] as Map<String, dynamic>)
          : const TrackerFeatures(),
      metadata: json['metadata'] != null
          ? TrackerNostrMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  TrackerAppMetadata copyWith({
    String? id,
    String? type,
    String? version,
    String? title,
    String? description,
    String? createdAt,
    String? updatedAt,
    String? ownerCallsign,
    TrackerFeatures? features,
    TrackerNostrMetadata? metadata,
  }) {
    return TrackerAppMetadata(
      id: id ?? this.id,
      type: type ?? this.type,
      version: version ?? this.version,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      features: features ?? this.features,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Features enabled for a tracker app
class TrackerFeatures {
  final bool paths;
  final bool measurements;
  final bool exercises;
  final bool plans;
  final bool sharing;
  final bool proximity;
  final bool visits;

  const TrackerFeatures({
    this.paths = true,
    this.measurements = true,
    this.exercises = true,
    this.plans = true,
    this.sharing = true,
    this.proximity = true,
    this.visits = true,
  });

  Map<String, dynamic> toJson() => {
        'paths': paths,
        'measurements': measurements,
        'exercises': exercises,
        'plans': plans,
        'sharing': sharing,
        'proximity': proximity,
        'visits': visits,
      };

  factory TrackerFeatures.fromJson(Map<String, dynamic> json) {
    return TrackerFeatures(
      paths: json['paths'] as bool? ?? true,
      measurements: json['measurements'] as bool? ?? true,
      exercises: json['exercises'] as bool? ?? true,
      plans: json['plans'] as bool? ?? true,
      sharing: json['sharing'] as bool? ?? true,
      proximity: json['proximity'] as bool? ?? true,
      visits: json['visits'] as bool? ?? true,
    );
  }

  TrackerFeatures copyWith({
    bool? paths,
    bool? measurements,
    bool? exercises,
    bool? plans,
    bool? sharing,
    bool? proximity,
    bool? visits,
  }) {
    return TrackerFeatures(
      paths: paths ?? this.paths,
      measurements: measurements ?? this.measurements,
      exercises: exercises ?? this.exercises,
      plans: plans ?? this.plans,
      sharing: sharing ?? this.sharing,
      proximity: proximity ?? this.proximity,
      visits: visits ?? this.visits,
    );
  }
}
