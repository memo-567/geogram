/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Email Account Model - Represents an email identity tied to a station
 */

/// Represents an email account/identity tied to a specific station.
///
/// A user can have multiple email accounts, one per connected station.
/// Each station provides a different email domain.
///
/// Example:
/// - alice@p2p.radio (connected to p2p.radio station)
/// - alice@community.net (connected to community.net station)
class EmailAccount {
  /// Station domain (e.g., "p2p.radio", "community.net")
  final String station;

  /// Local part of email address (e.g., "alice")
  final String localPart;

  /// User's callsign (e.g., "X1ALICE")
  final String callsign;

  /// User's NOSTR public key
  final String npub;

  /// Whether currently connected to this station
  bool isConnected;

  /// Station display name (optional)
  final String? stationName;

  EmailAccount({
    required this.station,
    required this.localPart,
    required this.callsign,
    required this.npub,
    this.isConnected = false,
    this.stationName,
  });

  /// Full email address (e.g., "alice@p2p.radio")
  String get email => '$localPart@$station';

  /// Station domain (alias for clarity)
  String get domain => station;

  /// NIP-05 identifier (same as email for our purposes)
  String get nip05 => email;

  /// Display name for UI (station name or domain)
  String get displayName => stationName ?? station;

  /// Create from station connection info
  factory EmailAccount.fromStation({
    required String stationDomain,
    required String nickname,
    required String callsign,
    required String npub,
    String? stationName,
  }) {
    return EmailAccount(
      station: stationDomain.toLowerCase(),
      localPart: nickname.toLowerCase(),
      callsign: callsign.toUpperCase(),
      npub: npub,
      stationName: stationName,
    );
  }

  /// Create from JSON
  factory EmailAccount.fromJson(Map<String, dynamic> json) {
    return EmailAccount(
      station: json['station'] as String,
      localPart: json['localPart'] as String,
      callsign: json['callsign'] as String,
      npub: json['npub'] as String,
      isConnected: json['isConnected'] as bool? ?? false,
      stationName: json['stationName'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'station': station,
        'localPart': localPart,
        'callsign': callsign,
        'npub': npub,
        'isConnected': isConnected,
        'stationName': stationName,
      };

  /// Create a copy with modified fields
  EmailAccount copyWith({
    String? station,
    String? localPart,
    String? callsign,
    String? npub,
    bool? isConnected,
    String? stationName,
  }) {
    return EmailAccount(
      station: station ?? this.station,
      localPart: localPart ?? this.localPart,
      callsign: callsign ?? this.callsign,
      npub: npub ?? this.npub,
      isConnected: isConnected ?? this.isConnected,
      stationName: stationName ?? this.stationName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmailAccount &&
        other.station == station &&
        other.npub == npub;
  }

  @override
  int get hashCode => Object.hash(station, npub);

  @override
  String toString() => 'EmailAccount($email, connected: $isConnected)';
}
