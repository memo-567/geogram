// SMTP server mixin for station server
import 'dart:async';

import '../../services/smtp_server.dart';
import '../../services/email_relay_service.dart';
import '../station_settings.dart';

/// Mixin providing SMTP server functionality
mixin SmtpMixin {
  // SMTP server state
  SMTPServer? _smtpServer;

  // Abstract methods to be implemented by the using class
  void log(String level, String message);
  StationSettings get settings;

  /// Get the SMTP server (if running)
  SMTPServer? get smtpServer => _smtpServer;

  /// Check if SMTP server is running
  bool get isSmtpRunning => _smtpServer != null;

  /// Configure email relay settings from station settings
  void configureEmailRelay() {
    final emailRelay = EmailRelayService();
    emailRelay.settings.stationDomain = settings.sslDomain ?? 'localhost';
    emailRelay.settings.smtpPort = settings.smtpPort;
    emailRelay.settings.smtpEnabled = settings.smtpEnabled;
    emailRelay.settings.dkimPrivateKey = settings.dkimPrivateKey;
    emailRelay.settings.dkimSelector = 'geogram';

    // SMTP relay settings
    emailRelay.settings.smtpRelayHost = settings.smtpRelayHost;
    emailRelay.settings.smtpRelayPort = settings.smtpRelayPort;
    emailRelay.settings.smtpRelayUsername = settings.smtpRelayUsername;
    emailRelay.settings.smtpRelayPassword = settings.smtpRelayPassword;
    emailRelay.settings.smtpRelayStartTls = settings.smtpRelayStartTls;

    log('INFO', 'Email relay configured: enabled=${settings.smtpEnabled}, '
        'domain=${settings.sslDomain}, relay=${settings.smtpRelayHost ?? "none"}');
  }

  /// Start SMTP server
  Future<bool> startSmtpServer({
    required OnMailReceivedCallback onMailReceived,
    required ValidateRecipientCallback validateRecipient,
  }) async {
    if (!settings.smtpServerEnabled) {
      log('INFO', 'SMTP server is disabled');
      return false;
    }

    if (settings.sslDomain == null || settings.sslDomain!.isEmpty) {
      log('WARN', 'Cannot start SMTP server: no domain configured');
      return false;
    }

    try {
      _smtpServer = SMTPServer(
        port: settings.smtpPort,
        domain: settings.sslDomain!,
      );

      // Set up mail delivery callbacks
      _smtpServer!.onMailReceived = onMailReceived;
      _smtpServer!.validateRecipient = validateRecipient;

      final started = await _smtpServer!.start();
      if (started) {
        log('INFO', 'SMTP server started on port ${settings.smtpPort} '
            'for domain ${settings.sslDomain}');
        return true;
      } else {
        log('WARN', 'Failed to start SMTP server on port ${settings.smtpPort}');
        _smtpServer = null;
        return false;
      }
    } catch (e) {
      log('ERROR', 'Failed to start SMTP server: $e');
      _smtpServer = null;
      return false;
    }
  }

  /// Stop SMTP server
  Future<void> stopSmtpServer() async {
    await _smtpServer?.stop();
    _smtpServer = null;
    log('INFO', 'SMTP server stopped');
  }

  /// Get SMTP status information
  Map<String, dynamic> getSmtpStatus() {
    return {
      'enabled': settings.smtpEnabled,
      'server_enabled': settings.smtpServerEnabled,
      'server_running': isSmtpRunning,
      'port': settings.smtpPort,
      'domain': settings.sslDomain,
      'relay_host': settings.smtpRelayHost,
      'relay_port': settings.smtpRelayPort,
      'relay_start_tls': settings.smtpRelayStartTls,
      'dkim_configured': settings.dkimPrivateKey != null && settings.dkimPrivateKey!.isNotEmpty,
    };
  }
}
