// SSL/HTTPS mixin for station server
import 'dart:io';

import '../station_settings.dart';

/// Mixin providing SSL/HTTPS server functionality
mixin SslMixin {
  // HTTPS server state
  HttpServer? _httpsServer;

  // Abstract methods to be implemented by the using class
  void log(String level, String message);
  String? get dataDir;
  StationSettings get settings;
  void Function(HttpRequest) get httpRequestHandler;

  /// Get the HTTPS server (if running)
  HttpServer? get httpsServer => _httpsServer;

  /// Check if HTTPS server is running
  bool get isHttpsRunning => _httpsServer != null;

  /// Start HTTPS server with SSL certificates
  Future<bool> startHttpsServer() async {
    if (!settings.enableSsl) {
      log('INFO', 'SSL is disabled');
      return false;
    }

    // Find certificate and key files
    final certKeyPaths = await _findCertificateFiles();
    if (certKeyPaths == null) {
      log('WARN', 'SSL enabled but no certificates found');
      return false;
    }

    final (certPath, keyPath) = certKeyPaths;

    try {
      final context = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);

      _httpsServer = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        settings.httpsPort,
        context,
        shared: true,
      );

      log('INFO', 'HTTPS server started on port ${settings.httpsPort}');

      _httpsServer!.listen(httpRequestHandler, onError: (error) {
        log('ERROR', 'HTTPS server error: $error');
      });

      return true;
    } catch (e) {
      log('ERROR', 'Failed to start HTTPS server: $e');
      log('ERROR', 'Certificate: $certPath');
      log('ERROR', 'Key: $keyPath');
      return false;
    }
  }

  /// Stop HTTPS server
  Future<void> stopHttpsServer() async {
    await _httpsServer?.close(force: true);
    _httpsServer = null;
    log('INFO', 'HTTPS server stopped');
  }

  /// Find certificate and key files
  /// Returns (certPath, keyPath) or null if not found
  Future<(String, String)?> _findCertificateFiles() async {
    final sslDir = dataDir != null ? '$dataDir/ssl' : null;

    // Check default ssl directory first
    if (sslDir != null) {
      final defaultCert = '$sslDir/fullchain.pem';
      final defaultKey = '$sslDir/domain.key';
      final altKey = '$sslDir/privkey.pem';

      if (await File(defaultCert).exists()) {
        // Check for domain.key first, then privkey.pem
        if (await File(defaultKey).exists()) {
          log('INFO', 'Using certificates from ssl directory (domain.key)');
          return (defaultCert, defaultKey);
        }
        if (await File(altKey).exists()) {
          log('INFO', 'Using certificates from ssl directory (privkey.pem)');
          return (defaultCert, altKey);
        }
      }
    }

    // Check configured paths
    if (settings.sslCertPath != null && settings.sslKeyPath != null) {
      if (await File(settings.sslCertPath!).exists() &&
          await File(settings.sslKeyPath!).exists()) {
        log('INFO', 'Using certificates from configured paths');
        return (settings.sslCertPath!, settings.sslKeyPath!);
      }
    }

    return null;
  }

  /// Check if SSL certificates exist
  Future<bool> hasSslCertificates() async {
    return await _findCertificateFiles() != null;
  }

  /// Handle ACME challenge requests for Let's Encrypt
  Future<void> handleAcmeChallenge(HttpRequest request) async {
    final path = request.uri.path;
    if (!path.startsWith('/.well-known/acme-challenge/')) {
      request.response.statusCode = 404;
      request.response.write('Not found');
      return;
    }

    final token = path.substring('/.well-known/acme-challenge/'.length);
    final challengeDir = dataDir != null
        ? '$dataDir/ssl/.well-known/acme-challenge'
        : null;

    if (challengeDir == null) {
      request.response.statusCode = 404;
      request.response.write('Not found');
      return;
    }

    final challengeFile = File('$challengeDir/$token');
    if (await challengeFile.exists()) {
      final content = await challengeFile.readAsString();
      request.response.headers.contentType = ContentType.text;
      request.response.write(content);
      log('INFO', 'Served ACME challenge for token: $token');
    } else {
      request.response.statusCode = 404;
      request.response.write('Challenge not found');
      log('WARN', 'ACME challenge not found: $token');
    }
  }

  /// Get SSL status information
  Map<String, dynamic> getSslStatus() {
    return {
      'enabled': settings.enableSsl,
      'https_running': isHttpsRunning,
      'https_port': settings.httpsPort,
      'domain': settings.sslDomain,
      'auto_renew': settings.sslAutoRenew,
      'cert_path': settings.sslCertPath,
      'key_path': settings.sslKeyPath,
    };
  }
}
