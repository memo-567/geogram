import 'tracker_metadata.dart';

/// Share type
enum ShareType {
  group,
  temporary,
}

/// Share accuracy level
enum ShareAccuracy {
  precise, // ~10m
  approximate, // ~500m
  city, // City level
}

/// Member of a group share
class ShareMember {
  final String callsign;
  final String npub;
  final String addedAt;

  const ShareMember({
    required this.callsign,
    required this.npub,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        'npub': npub,
        'added_at': addedAt,
      };

  factory ShareMember.fromJson(Map<String, dynamic> json) {
    return ShareMember(
      callsign: json['callsign'] as String,
      npub: json['npub'] as String,
      addedAt: json['added_at'] as String,
    );
  }
}

/// Schedule for a share
class ShareSchedule {
  final bool alwaysOn;
  final List<TimeRange>? timeRanges;

  const ShareSchedule({
    this.alwaysOn = true,
    this.timeRanges,
  });

  Map<String, dynamic> toJson() => {
        'always_on': alwaysOn,
        if (timeRanges != null)
          'time_ranges': timeRanges!.map((t) => t.toJson()).toList(),
      };

  factory ShareSchedule.fromJson(Map<String, dynamic> json) {
    return ShareSchedule(
      alwaysOn: json['always_on'] as bool? ?? true,
      timeRanges: (json['time_ranges'] as List<dynamic>?)
          ?.map((t) => TimeRange.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Time range for scheduled sharing
class TimeRange {
  final List<String> days;
  final String startTime; // HH:MM
  final String endTime; // HH:MM

  const TimeRange({
    required this.days,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
        'days': days,
        'start_time': startTime,
        'end_time': endTime,
      };

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(
      days: (json['days'] as List<dynamic>).map((d) => d as String).toList(),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
    );
  }
}

/// Group-based location share
class GroupShare {
  final String id;
  final ShareType type;
  final String groupId;
  final String groupName;
  final bool active;
  final String createdAt;
  final String updatedAt;
  final int updateIntervalSeconds;
  final ShareAccuracy shareAccuracy;
  final List<ShareMember> members;
  final ShareSchedule? schedule;
  final String? lastBroadcast;
  final String ownerCallsign;
  final TrackerNostrMetadata? metadata;

  const GroupShare({
    required this.id,
    this.type = ShareType.group,
    required this.groupId,
    required this.groupName,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
    this.updateIntervalSeconds = 300,
    this.shareAccuracy = ShareAccuracy.approximate,
    this.members = const [],
    this.schedule,
    this.lastBroadcast,
    required this.ownerCallsign,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'group_id': groupId,
        'group_name': groupName,
        'active': active,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'update_interval_seconds': updateIntervalSeconds,
        'share_accuracy': shareAccuracy.name,
        'members': members.map((m) => m.toJson()).toList(),
        if (schedule != null) 'schedule': schedule!.toJson(),
        if (lastBroadcast != null) 'last_broadcast': lastBroadcast,
        'owner_callsign': ownerCallsign,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory GroupShare.fromJson(Map<String, dynamic> json) {
    final accuracyStr = json['share_accuracy'] as String? ?? 'approximate';
    final accuracy = ShareAccuracy.values.firstWhere(
      (a) => a.name == accuracyStr,
      orElse: () => ShareAccuracy.approximate,
    );

    return GroupShare(
      id: json['id'] as String,
      type: ShareType.group,
      groupId: json['group_id'] as String,
      groupName: json['group_name'] as String,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      updateIntervalSeconds: json['update_interval_seconds'] as int? ?? 300,
      shareAccuracy: accuracy,
      members: (json['members'] as List<dynamic>?)
              ?.map((m) => ShareMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          const [],
      schedule: json['schedule'] != null
          ? ShareSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
          : null,
      lastBroadcast: json['last_broadcast'] as String?,
      ownerCallsign: json['owner_callsign'] as String,
      metadata: json['metadata'] != null
          ? TrackerNostrMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  GroupShare copyWith({
    String? id,
    String? groupId,
    String? groupName,
    bool? active,
    String? createdAt,
    String? updatedAt,
    int? updateIntervalSeconds,
    ShareAccuracy? shareAccuracy,
    List<ShareMember>? members,
    ShareSchedule? schedule,
    String? lastBroadcast,
    String? ownerCallsign,
    TrackerNostrMetadata? metadata,
  }) {
    return GroupShare(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updateIntervalSeconds:
          updateIntervalSeconds ?? this.updateIntervalSeconds,
      shareAccuracy: shareAccuracy ?? this.shareAccuracy,
      members: members ?? this.members,
      schedule: schedule ?? this.schedule,
      lastBroadcast: lastBroadcast ?? this.lastBroadcast,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Recipient for a temporary share
class ShareRecipient {
  final String callsign;
  final String npub;

  const ShareRecipient({
    required this.callsign,
    required this.npub,
  });

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        'npub': npub,
      };

  factory ShareRecipient.fromJson(Map<String, dynamic> json) {
    return ShareRecipient(
      callsign: json['callsign'] as String,
      npub: json['npub'] as String,
    );
  }
}

/// Temporary location share
class TemporaryShare {
  final String id;
  final ShareType type;
  final List<ShareRecipient> recipients;
  final bool active;
  final String createdAt;
  final String expiresAt;
  final int durationMinutes;
  final String? reason;
  final int updateIntervalSeconds;
  final ShareAccuracy shareAccuracy;
  final String? lastBroadcast;
  final String ownerCallsign;
  final TrackerNostrMetadata? metadata;

  const TemporaryShare({
    required this.id,
    this.type = ShareType.temporary,
    this.recipients = const [],
    this.active = true,
    required this.createdAt,
    required this.expiresAt,
    required this.durationMinutes,
    this.reason,
    this.updateIntervalSeconds = 60,
    this.shareAccuracy = ShareAccuracy.precise,
    this.lastBroadcast,
    required this.ownerCallsign,
    this.metadata,
  });

  DateTime get expiresAtDateTime {
    try {
      return DateTime.parse(expiresAt);
    } catch (e) {
      return DateTime.now();
    }
  }

  bool get hasExpired => DateTime.now().isAfter(expiresAtDateTime);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'recipients': recipients.map((r) => r.toJson()).toList(),
        'active': active,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'duration_minutes': durationMinutes,
        if (reason != null) 'reason': reason,
        'update_interval_seconds': updateIntervalSeconds,
        'share_accuracy': shareAccuracy.name,
        if (lastBroadcast != null) 'last_broadcast': lastBroadcast,
        'owner_callsign': ownerCallsign,
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory TemporaryShare.fromJson(Map<String, dynamic> json) {
    final accuracyStr = json['share_accuracy'] as String? ?? 'precise';
    final accuracy = ShareAccuracy.values.firstWhere(
      (a) => a.name == accuracyStr,
      orElse: () => ShareAccuracy.precise,
    );

    return TemporaryShare(
      id: json['id'] as String,
      type: ShareType.temporary,
      recipients: (json['recipients'] as List<dynamic>?)
              ?.map((r) => ShareRecipient.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as String,
      expiresAt: json['expires_at'] as String,
      durationMinutes: json['duration_minutes'] as int,
      reason: json['reason'] as String?,
      updateIntervalSeconds: json['update_interval_seconds'] as int? ?? 60,
      shareAccuracy: accuracy,
      lastBroadcast: json['last_broadcast'] as String?,
      ownerCallsign: json['owner_callsign'] as String,
      metadata: json['metadata'] != null
          ? TrackerNostrMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  TemporaryShare copyWith({
    String? id,
    List<ShareRecipient>? recipients,
    bool? active,
    String? createdAt,
    String? expiresAt,
    int? durationMinutes,
    String? reason,
    int? updateIntervalSeconds,
    ShareAccuracy? shareAccuracy,
    String? lastBroadcast,
    String? ownerCallsign,
    TrackerNostrMetadata? metadata,
  }) {
    return TemporaryShare(
      id: id ?? this.id,
      recipients: recipients ?? this.recipients,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      reason: reason ?? this.reason,
      updateIntervalSeconds:
          updateIntervalSeconds ?? this.updateIntervalSeconds,
      shareAccuracy: shareAccuracy ?? this.shareAccuracy,
      lastBroadcast: lastBroadcast ?? this.lastBroadcast,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Location received from another user
class ReceivedLocation {
  final String callsign;
  final String? displayName;
  final String npub;
  final String lastUpdate;
  final LocationData location;
  final ShareInfo shareInfo;
  final String? expiresAt;
  final List<LocationHistoryEntry>? history;
  final int historyMaxEntries;

  const ReceivedLocation({
    required this.callsign,
    this.displayName,
    required this.npub,
    required this.lastUpdate,
    required this.location,
    required this.shareInfo,
    this.expiresAt,
    this.history,
    this.historyMaxEntries = 10,
  });

  Map<String, dynamic> toJson() => {
        'callsign': callsign,
        if (displayName != null) 'display_name': displayName,
        'npub': npub,
        'last_update': lastUpdate,
        'location': location.toJson(),
        'share_info': shareInfo.toJson(),
        if (expiresAt != null) 'expires_at': expiresAt,
        if (history != null) 'history': history!.map((h) => h.toJson()).toList(),
        'history_max_entries': historyMaxEntries,
      };

  factory ReceivedLocation.fromJson(Map<String, dynamic> json) {
    return ReceivedLocation(
      callsign: json['callsign'] as String,
      displayName: json['display_name'] as String?,
      npub: json['npub'] as String,
      lastUpdate: json['last_update'] as String,
      location:
          LocationData.fromJson(json['location'] as Map<String, dynamic>),
      shareInfo:
          ShareInfo.fromJson(json['share_info'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] as String?,
      history: (json['history'] as List<dynamic>?)
          ?.map((h) => LocationHistoryEntry.fromJson(h as Map<String, dynamic>))
          .toList(),
      historyMaxEntries: json['history_max_entries'] as int? ?? 10,
    );
  }
}

/// Location data
class LocationData {
  final double lat;
  final double lon;
  final ShareAccuracy accuracyLevel;
  final double? accuracyMeters;

  const LocationData({
    required this.lat,
    required this.lon,
    required this.accuracyLevel,
    this.accuracyMeters,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'accuracy_level': accuracyLevel.name,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      };

  factory LocationData.fromJson(Map<String, dynamic> json) {
    final accuracyStr = json['accuracy_level'] as String? ?? 'approximate';
    final accuracy = ShareAccuracy.values.firstWhere(
      (a) => a.name == accuracyStr,
      orElse: () => ShareAccuracy.approximate,
    );

    return LocationData(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      accuracyLevel: accuracy,
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
    );
  }
}

/// Share information for a received location
class ShareInfo {
  final ShareType type;
  final String shareId;
  final String? shareName;

  const ShareInfo({
    required this.type,
    required this.shareId,
    this.shareName,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'share_id': shareId,
        if (shareName != null) 'share_name': shareName,
      };

  factory ShareInfo.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'group';
    final type = ShareType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ShareType.group,
    );

    return ShareInfo(
      type: type,
      shareId: json['share_id'] as String,
      shareName: json['share_name'] as String?,
    );
  }
}

/// History entry for location tracking
class LocationHistoryEntry {
  final String timestamp;
  final double lat;
  final double lon;

  const LocationHistoryEntry({
    required this.timestamp,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'lat': lat,
        'lon': lon,
      };

  factory LocationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocationHistoryEntry(
      timestamp: json['timestamp'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}
