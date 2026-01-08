/// Status of a path recording
enum RecordingStatus {
  recording,
  paused,
}

/// State of an active path recording (persisted for crash recovery)
class TrackerRecordingState {
  final String activePathId;
  final int activePathYear;
  final RecordingStatus status;
  final int intervalSeconds;
  final String? lastPointTimestamp;
  final String? pausedAt;
  final String startedAt;
  final int pointCount;

  const TrackerRecordingState({
    required this.activePathId,
    required this.activePathYear,
    required this.status,
    required this.intervalSeconds,
    required this.startedAt,
    this.lastPointTimestamp,
    this.pausedAt,
    this.pointCount = 0,
  });

  bool get isRecording => status == RecordingStatus.recording;
  bool get isPaused => status == RecordingStatus.paused;

  TrackerRecordingState copyWith({
    String? activePathId,
    int? activePathYear,
    RecordingStatus? status,
    int? intervalSeconds,
    String? lastPointTimestamp,
    String? pausedAt,
    String? startedAt,
    int? pointCount,
  }) {
    return TrackerRecordingState(
      activePathId: activePathId ?? this.activePathId,
      activePathYear: activePathYear ?? this.activePathYear,
      status: status ?? this.status,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      lastPointTimestamp: lastPointTimestamp ?? this.lastPointTimestamp,
      pausedAt: pausedAt ?? this.pausedAt,
      startedAt: startedAt ?? this.startedAt,
      pointCount: pointCount ?? this.pointCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'active_path_id': activePathId,
        'active_path_year': activePathYear,
        'status': status.name,
        'interval_seconds': intervalSeconds,
        'started_at': startedAt,
        if (lastPointTimestamp != null)
          'last_point_timestamp': lastPointTimestamp,
        if (pausedAt != null) 'paused_at': pausedAt,
        'point_count': pointCount,
      };

  factory TrackerRecordingState.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'recording';
    final status = RecordingStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => RecordingStatus.recording,
    );

    return TrackerRecordingState(
      activePathId: json['active_path_id'] as String,
      activePathYear: json['active_path_year'] as int,
      status: status,
      intervalSeconds: json['interval_seconds'] as int? ?? 60,
      startedAt: json['started_at'] as String,
      lastPointTimestamp: json['last_point_timestamp'] as String?,
      pausedAt: json['paused_at'] as String?,
      pointCount: json['point_count'] as int? ?? 0,
    );
  }
}
