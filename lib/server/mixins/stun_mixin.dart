// STUN server mixin for station server (WebRTC NAT traversal)
import '../../services/stun_server_service.dart';
import '../station_settings.dart';

/// Mixin providing STUN server functionality for WebRTC
mixin StunMixin {
  // Abstract methods to be implemented by the using class
  void log(String level, String message);
  StationSettings get settings;

  /// Start STUN server
  Future<bool> startStunServer() async {
    if (!settings.stunServerEnabled) {
      log('INFO', 'STUN server is disabled');
      return false;
    }

    try {
      final started = await StunServerService().start(port: settings.stunServerPort);
      if (started) {
        log('INFO', 'STUN server started on UDP port ${settings.stunServerPort}');
        return true;
      } else {
        log('WARN', 'Failed to start STUN server (WebRTC may require external STUN)');
        return false;
      }
    } catch (e) {
      log('ERROR', 'Failed to start STUN server: $e');
      return false;
    }
  }

  /// Stop STUN server
  Future<void> stopStunServer() async {
    await StunServerService().stop();
    log('INFO', 'STUN server stopped');
  }

  /// Check if STUN server is running
  bool get isStunRunning => StunServerService().isRunning;

  /// Get STUN server status
  Map<String, dynamic> getStunStatus() {
    final service = StunServerService();
    return {
      'enabled': settings.stunServerEnabled,
      'running': service.isRunning,
      'port': settings.stunServerPort,
      'requests_handled': service.requestsHandled,
    };
  }
}
