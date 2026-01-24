// Client adapter for backward compatibility
// Allows gradual migration from old client classes to unified StationClient

import 'dart:io';
import '../station_client.dart';

/// Convert App's ConnectedClient to unified StationClient
StationClient fromAppClient(
  WebSocket socket,
  String id, {
  String? callsign,
  String? nickname,
  String? npub,
  String? deviceType,
  String? platform,
  String? version,
  String? remoteAddress,
  double? latitude,
  double? longitude,
  DateTime? connectedAt,
}) {
  final client = StationClient(
    socket: socket,
    id: id,
    callsign: callsign,
    nickname: nickname,
    npub: npub,
    deviceType: deviceType,
    platform: platform,
    version: version,
    remoteAddress: remoteAddress,
    connectionType: StationClient.detectConnectionType(remoteAddress),
    latitude: latitude,
    longitude: longitude,
  );
  if (connectedAt != null) {
    client.connectedAt = connectedAt;
  }
  return client;
}

/// Convert CLI's PureConnectedClient to unified StationClient
StationClient fromCliClient(
  WebSocket socket,
  String id, {
  String? callsign,
  String? nickname,
  String? color,
  String? npub,
  String? deviceType,
  String? platform,
  String? version,
  String? address,
  double? latitude,
  double? longitude,
  DateTime? connectedAt,
  DateTime? lastActivity,
}) {
  final client = StationClient(
    socket: socket,
    id: id,
    callsign: callsign,
    nickname: nickname,
    color: color,
    npub: npub,
    deviceType: deviceType,
    platform: platform,
    version: version,
    remoteAddress: address,
    connectionType: StationClient.detectConnectionType(address),
    latitude: latitude,
    longitude: longitude,
  );
  if (connectedAt != null) {
    client.connectedAt = connectedAt;
  }
  if (lastActivity != null) {
    client.lastActivity = lastActivity;
  }
  return client;
}

/// Extension to add toJson that matches the old format
extension StationClientCompat on StationClient {
  /// Convert to App's ConnectedClient JSON format
  Map<String, dynamic> toAppJson() {
    return {
      'id': id,
      'callsign': callsign ?? 'Unknown',
      'nickname': nickname ?? callsign,
      'npub': npub,
      'deviceType': deviceType ?? 'Unknown',
      'platform': platform,
      'version': version,
      'address': remoteAddress,
      'connectionType': connectionType.code,
      'latitude': latitude,
      'longitude': longitude,
      'connectedAt': connectedAt.toIso8601String(),
    };
  }

  /// Convert to CLI's PureConnectedClient JSON format
  Map<String, dynamic> toCliJson() {
    return {
      'id': id,
      'callsign': callsign ?? 'Unknown',
      'nickname': nickname ?? callsign,
      'color': color,
      'npub': npub,
      'device_type': deviceType ?? 'Unknown',
      'platform': platform,
      'version': version,
      'address': remoteAddress,
      'connection_type': connectionType.code,
      'latitude': latitude,
      'longitude': longitude,
      'connected_at': connectedAt.toIso8601String(),
      'last_activity': lastActivity.toIso8601String(),
    };
  }
}
