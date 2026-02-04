/// Notification settings model
class NotificationSettings {
  bool enableNotifications;
  bool notifyNewMessages;
  bool notifyNearbyDevices;
  bool notifyAppUpdates;
  bool notifyStationStatus;
  bool notifySystemAlerts;
  bool soundEnabled;
  bool vibrationEnabled;

  NotificationSettings({
    this.enableNotifications = true,
    this.notifyNewMessages = true,
    this.notifyNearbyDevices = true,
    this.notifyAppUpdates = false,
    this.notifyStationStatus = false,
    this.notifySystemAlerts = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  /// Create from JSON
  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      enableNotifications: json['enableNotifications'] as bool? ?? true,
      notifyNewMessages: json['notifyNewMessages'] as bool? ?? true,
      notifyNearbyDevices: json['notifyNearbyDevices'] as bool? ?? true,
      notifyAppUpdates: json['notifyAppUpdates'] as bool? ?? false,
      notifyStationStatus: json['notifyStationStatus'] as bool? ?? false,
      notifySystemAlerts: json['notifySystemAlerts'] as bool? ?? true,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'enableNotifications': enableNotifications,
      'notifyNewMessages': notifyNewMessages,
      'notifyNearbyDevices': notifyNearbyDevices,
      'notifyAppUpdates': notifyAppUpdates,
      'notifyStationStatus': notifyStationStatus,
      'notifySystemAlerts': notifySystemAlerts,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
    };
  }

  /// Create a copy with updated fields
  NotificationSettings copyWith({
    bool? enableNotifications,
    bool? notifyNewMessages,
    bool? notifyNearbyDevices,
    bool? notifyAppUpdates,
    bool? notifyStationStatus,
    bool? notifySystemAlerts,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return NotificationSettings(
      enableNotifications: enableNotifications ?? this.enableNotifications,
      notifyNewMessages: notifyNewMessages ?? this.notifyNewMessages,
      notifyNearbyDevices: notifyNearbyDevices ?? this.notifyNearbyDevices,
      notifyAppUpdates: notifyAppUpdates ?? this.notifyAppUpdates,
      notifyStationStatus: notifyStationStatus ?? this.notifyStationStatus,
      notifySystemAlerts: notifySystemAlerts ?? this.notifySystemAlerts,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }
}
