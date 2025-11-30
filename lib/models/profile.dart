/// User profile model - represents a single identity/callsign
class Profile {
  /// Unique identifier for this profile (UUID)
  final String id;
  String callsign;
  String nickname;
  String description;
  String? profileImagePath;
  String npub; // NOSTR public key
  String nsec; // NOSTR private key (secret)
  String preferredColor;
  double? latitude; // User's current latitude
  double? longitude; // User's current longitude
  String? locationName; // Human-readable location
  DateTime createdAt; // When this profile was created

  Profile({
    String? id,
    this.callsign = '',
    this.nickname = '',
    this.description = '',
    this.profileImagePath,
    this.npub = '',
    this.nsec = '',
    this.preferredColor = 'blue',
    this.latitude,
    this.longitude,
    this.locationName,
    DateTime? createdAt,
  }) : id = id ?? _generateId(),
       createdAt = createdAt ?? DateTime.now();

  /// Generate a simple unique ID
  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().microsecond).toRadixString(36);
  }

  /// Create a Profile from JSON map
  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String?,
      callsign: json['callsign'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      description: json['description'] as String? ?? '',
      profileImagePath: json['profileImagePath'] as String?,
      npub: json['npub'] as String? ?? '',
      nsec: json['nsec'] as String? ?? '',
      preferredColor: json['preferredColor'] as String? ?? 'blue',
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      locationName: json['locationName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  /// Convert Profile to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'callsign': callsign,
      'nickname': nickname,
      'description': description,
      if (profileImagePath != null) 'profileImagePath': profileImagePath,
      'npub': npub,
      'nsec': nsec,
      'preferredColor': preferredColor,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationName != null) 'locationName': locationName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create a copy of this profile
  Profile copyWith({
    String? callsign,
    String? nickname,
    String? description,
    String? profileImagePath,
    String? npub,
    String? nsec,
    String? preferredColor,
    double? latitude,
    double? longitude,
    String? locationName,
  }) {
    return Profile(
      id: id, // Preserve the ID
      callsign: callsign ?? this.callsign,
      nickname: nickname ?? this.nickname,
      description: description ?? this.description,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      npub: npub ?? this.npub,
      nsec: nsec ?? this.nsec,
      preferredColor: preferredColor ?? this.preferredColor,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      createdAt: createdAt, // Preserve creation time
    );
  }

  /// Display name for this profile (nickname or callsign)
  String get displayName => nickname.isNotEmpty ? nickname : callsign;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Profile(id: $id, callsign: $callsign, nickname: $nickname)';
}
