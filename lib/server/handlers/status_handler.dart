// Status and stats HTTP handlers for station server
import 'dart:convert';
import 'dart:io';

import '../station_settings.dart';
import '../station_stats.dart';
import '../../version.dart';

/// Handler for status-related HTTP endpoints
class StatusHandler {
  final StationSettings Function() getSettings;
  final StationStats Function() getStats;
  final int Function() getConnectedDevices;
  final DateTime? Function() getStartTime;
  final List<Map<String, dynamic>> Function() getClients;
  final List<Map<String, dynamic>> Function() getBackupProviders;
  final void Function(String, String) log;

  StatusHandler({
    required this.getSettings,
    required this.getStats,
    required this.getConnectedDevices,
    required this.getStartTime,
    required this.getClients,
    required this.getBackupProviders,
    required this.log,
  });

  /// Handle GET /api/status
  Future<void> handleStatus(HttpRequest request) async {
    final settings = getSettings();
    final startTime = getStartTime();

    final status = {
      'station_mode': true,
      'callsign': settings.callsign,
      'npub': settings.npub,
      'name': settings.name,
      'description': settings.description,
      'location': settings.location,
      'latitude': settings.latitude,
      'longitude': settings.longitude,
      'version': appVersion,
      'uptime': startTime != null
          ? DateTime.now().difference(startTime).inSeconds
          : 0,
      'connected_devices': getConnectedDevices(),
      'tile_server_enabled': settings.tileServerEnabled,
      'update_mirror_enabled': settings.updateMirrorEnabled,
      'stun_server_enabled': settings.stunServerEnabled,
      'ssl_enabled': settings.enableSsl,
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(status));
  }

  /// Handle GET /station/status (detailed relay status)
  Future<void> handleRelayStatus(HttpRequest request) async {
    final settings = getSettings();
    final stats = getStats();
    final startTime = getStartTime();
    final clients = getClients();

    final status = {
      'station': {
        'callsign': settings.callsign,
        'npub': settings.npub,
        'name': settings.name,
        'description': settings.description,
        'location': settings.location,
        'latitude': settings.latitude,
        'longitude': settings.longitude,
        'role': settings.stationRole,
        'network_id': settings.networkId,
        'parent_station_url': settings.parentStationUrl,
      },
      'server': {
        'version': appVersion,
        'uptime': startTime != null
            ? DateTime.now().difference(startTime).inSeconds
            : 0,
        'http_port': settings.httpPort,
        'https_port': settings.httpsPort,
        'ssl_enabled': settings.enableSsl,
        'ssl_domain': settings.sslDomain,
      },
      'services': {
        'tile_server': settings.tileServerEnabled,
        'osm_fallback': settings.osmFallbackEnabled,
        'update_mirror': settings.updateMirrorEnabled,
        'stun_server': settings.stunServerEnabled,
        'smtp_server': settings.smtpServerEnabled,
        'nostr_require_auth': settings.nostrRequireAuthForWrites,
      },
      'connections': {
        'count': getConnectedDevices(),
        'max': settings.maxConnectedDevices,
        'clients': clients,
      },
      'stats': stats.toJson(),
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(status));
  }

  /// Handle GET /api/stats
  Future<void> handleStats(HttpRequest request) async {
    final stats = getStats();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(stats.toJson()));
  }

  /// Handle GET /api/clients or /api/devices
  Future<void> handleClients(HttpRequest request) async {
    final clients = getClients();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'count': clients.length,
      'clients': clients,
    }));
  }

  /// Handle GET /api/backup/providers/available
  Future<void> handleBackupProvidersAvailable(HttpRequest request) async {
    final providers = getBackupProviders();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'providers': providers,
    }));
  }
}
