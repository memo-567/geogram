/// A period of proximity with a contact
class ProximityPeriod {
  final String startedAt;
  final String endedAt;
  final int durationSeconds;

  const ProximityPeriod({
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'started_at': startedAt,
        'ended_at': endedAt,
        'duration_seconds': durationSeconds,
      };

  factory ProximityPeriod.fromJson(Map<String, dynamic> json) {
    return ProximityPeriod(
      startedAt: json['started_at'] as String,
      endedAt: json['ended_at'] as String,
      durationSeconds: json['duration_seconds'] as int,
    );
  }
}

/// Session with a contact for a day
class ProximitySession {
  final String contactCallsign;
  final String? contactNpub;
  final String? contactName;
  final List<ProximityPeriod> periods;
  final int totalSeconds;
  final int totalPeriods;

  const ProximitySession({
    required this.contactCallsign,
    this.contactNpub,
    this.contactName,
    this.periods = const [],
    this.totalSeconds = 0,
    this.totalPeriods = 0,
  });

  String get totalFormatted {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  Map<String, dynamic> toJson() => {
        'contact_callsign': contactCallsign,
        if (contactNpub != null) 'contact_npub': contactNpub,
        if (contactName != null) 'contact_name': contactName,
        'periods': periods.map((p) => p.toJson()).toList(),
        'total_seconds': totalSeconds,
        'total_periods': totalPeriods,
      };

  factory ProximitySession.fromJson(Map<String, dynamic> json) {
    return ProximitySession(
      contactCallsign: json['contact_callsign'] as String,
      contactNpub: json['contact_npub'] as String?,
      contactName: json['contact_name'] as String?,
      periods: (json['periods'] as List<dynamic>?)
              ?.map((p) => ProximityPeriod.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      totalSeconds: json['total_seconds'] as int? ?? 0,
      totalPeriods: json['total_periods'] as int? ?? 0,
    );
  }

  ProximitySession copyWith({
    String? contactCallsign,
    String? contactNpub,
    String? contactName,
    List<ProximityPeriod>? periods,
    int? totalSeconds,
    int? totalPeriods,
  }) {
    return ProximitySession(
      contactCallsign: contactCallsign ?? this.contactCallsign,
      contactNpub: contactNpub ?? this.contactNpub,
      contactName: contactName ?? this.contactName,
      periods: periods ?? this.periods,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      totalPeriods: totalPeriods ?? this.totalPeriods,
    );
  }

  /// Add a new period and recalculate totals
  ProximitySession addPeriod(ProximityPeriod period) {
    final newPeriods = [...periods, period];
    final newTotalSeconds = newPeriods.fold<int>(
        0, (sum, p) => sum + p.durationSeconds);
    return copyWith(
      periods: newPeriods,
      totalSeconds: newTotalSeconds,
      totalPeriods: newPeriods.length,
    );
  }
}

/// Daily summary of proximity
class DailyProximitySummary {
  final int totalContacts;
  final int totalSeconds;
  final String? mostTimeWith;

  const DailyProximitySummary({
    this.totalContacts = 0,
    this.totalSeconds = 0,
    this.mostTimeWith,
  });

  Map<String, dynamic> toJson() => {
        'total_contacts': totalContacts,
        'total_seconds': totalSeconds,
        if (mostTimeWith != null) 'most_time_with': mostTimeWith,
      };

  factory DailyProximitySummary.fromJson(Map<String, dynamic> json) {
    return DailyProximitySummary(
      totalContacts: json['total_contacts'] as int? ?? 0,
      totalSeconds: json['total_seconds'] as int? ?? 0,
      mostTimeWith: json['most_time_with'] as String?,
    );
  }

  factory DailyProximitySummary.calculate(List<ProximitySession> sessions) {
    if (sessions.isEmpty) {
      return const DailyProximitySummary();
    }

    final totalSeconds =
        sessions.fold<int>(0, (sum, s) => sum + s.totalSeconds);

    String? mostTimeWith;
    int maxTime = 0;
    for (final session in sessions) {
      if (session.totalSeconds > maxTime) {
        maxTime = session.totalSeconds;
        mostTimeWith = session.contactCallsign;
      }
    }

    return DailyProximitySummary(
      totalContacts: sessions.length,
      totalSeconds: totalSeconds,
      mostTimeWith: mostTimeWith,
    );
  }
}

/// Daily proximity data file (proximity_YYYYMMDD.json)
class DailyProximityData {
  final String date; // YYYY-MM-DD
  final String ownerCallsign;
  final List<ProximitySession> sessions;
  final DailyProximitySummary? dailySummary;

  const DailyProximityData({
    required this.date,
    required this.ownerCallsign,
    this.sessions = const [],
    this.dailySummary,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'owner_callsign': ownerCallsign,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        if (dailySummary != null) 'daily_summary': dailySummary!.toJson(),
      };

  factory DailyProximityData.fromJson(Map<String, dynamic> json) {
    return DailyProximityData(
      date: json['date'] as String,
      ownerCallsign: json['owner_callsign'] as String,
      sessions: (json['sessions'] as List<dynamic>?)
              ?.map(
                  (s) => ProximitySession.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      dailySummary: json['daily_summary'] != null
          ? DailyProximitySummary.fromJson(
              json['daily_summary'] as Map<String, dynamic>)
          : null,
    );
  }

  DailyProximityData copyWith({
    String? date,
    String? ownerCallsign,
    List<ProximitySession>? sessions,
    DailyProximitySummary? dailySummary,
  }) {
    return DailyProximityData(
      date: date ?? this.date,
      ownerCallsign: ownerCallsign ?? this.ownerCallsign,
      sessions: sessions ?? this.sessions,
      dailySummary: dailySummary ?? this.dailySummary,
    );
  }

  /// Get or create session for a contact
  ProximitySession? getSession(String callsign) {
    return sessions.cast<ProximitySession?>().firstWhere(
          (s) => s?.contactCallsign == callsign,
          orElse: () => null,
        );
  }

  /// Update or add a session
  DailyProximityData updateSession(ProximitySession session) {
    final index =
        sessions.indexWhere((s) => s.contactCallsign == session.contactCallsign);
    List<ProximitySession> newSessions;
    if (index >= 0) {
      newSessions = List<ProximitySession>.from(sessions);
      newSessions[index] = session;
    } else {
      newSessions = [...sessions, session];
    }
    return copyWith(
      sessions: newSessions,
      dailySummary: DailyProximitySummary.calculate(newSessions),
    );
  }
}

/// Statistics for a single contact
class ContactProximityStats {
  final String contactCallsign;
  final String period; // YYYY-MM format
  final int totalSeconds;
  final int daysDetected;
  final int avgSecondsPerDay;
  final int longestSessionSeconds;
  final String? firstDetection;
  final String? lastDetection;

  const ContactProximityStats({
    required this.contactCallsign,
    required this.period,
    this.totalSeconds = 0,
    this.daysDetected = 0,
    this.avgSecondsPerDay = 0,
    this.longestSessionSeconds = 0,
    this.firstDetection,
    this.lastDetection,
  });

  Map<String, dynamic> toJson() => {
        'contact_callsign': contactCallsign,
        'period': period,
        'total_seconds': totalSeconds,
        'days_detected': daysDetected,
        'avg_seconds_per_day': avgSecondsPerDay,
        'longest_session_seconds': longestSessionSeconds,
        if (firstDetection != null) 'first_detection': firstDetection,
        if (lastDetection != null) 'last_detection': lastDetection,
      };

  factory ContactProximityStats.fromJson(Map<String, dynamic> json) {
    return ContactProximityStats(
      contactCallsign: json['contact_callsign'] as String,
      period: json['period'] as String,
      totalSeconds: json['total_seconds'] as int? ?? 0,
      daysDetected: json['days_detected'] as int? ?? 0,
      avgSecondsPerDay: json['avg_seconds_per_day'] as int? ?? 0,
      longestSessionSeconds: json['longest_session_seconds'] as int? ?? 0,
      firstDetection: json['first_detection'] as String?,
      lastDetection: json['last_detection'] as String?,
    );
  }
}
