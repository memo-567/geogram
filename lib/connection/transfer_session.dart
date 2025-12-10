/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import '../services/log_service.dart';
import '../services/bluetooth_classic_service.dart';
import '../services/bluetooth_classic_pairing_service.dart';

/// Manages batch transfer sessions for multi-request operations
///
/// Apps can declare a transfer session when they know an operation involves
/// multiple requests that together exceed the BLE+ threshold. This keeps
/// the Bluetooth Classic connection open for the duration of the session,
/// avoiding repeated connect/disconnect cycles.
///
/// Example usage:
/// ```dart
/// // App knows it will sync 50 small files (~100KB total)
/// final session = await TransferSession.start(
///   callsign: 'X1ABCD',
///   expectedTotalBytes: 100 * 1024,  // 100KB expected
/// );
///
/// try {
///   // Multiple small requests - all use BLE+ since session declared 100KB
///   for (final file in files) {
///     await connectionManager.send(callsign: 'X1ABCD', data: file.bytes);
///   }
/// } finally {
///   await session.end();  // Disconnect BLE+
/// }
/// ```
class TransferSession {
  /// Target device callsign
  final String targetCallsign;

  /// Expected total bytes for this session
  final int expectedTotalBytes;

  /// Maximum duration before auto-close
  final Duration maxDuration;

  /// When the session was started
  final DateTime startedAt;

  /// Session ID for logging
  final String sessionId;

  /// Whether this session is using BLE+ (Bluetooth Classic)
  bool _usingBLEPlus = false;
  bool get usingBLEPlus => _usingBLEPlus;

  /// Bluetooth Classic MAC address (if using BLE+)
  String? _classicMac;

  /// Timer for auto-close
  Timer? _autoCloseTimer;

  /// Active sessions by callsign
  static final Map<String, TransferSession> _activeSessions = {};

  /// Default threshold for using BLE+ (10KB)
  static const int defaultThreshold = 10 * 1024;

  TransferSession._({
    required this.targetCallsign,
    required this.expectedTotalBytes,
    required this.maxDuration,
    required this.startedAt,
    required this.sessionId,
  });

  /// Start a new transfer session
  ///
  /// If [expectedTotalBytes] exceeds the threshold and the target device
  /// is BLE+ paired, establishes a Bluetooth Classic connection that
  /// remains open until [end] is called or [maxDuration] expires.
  static Future<TransferSession> start({
    required String callsign,
    required int expectedTotalBytes,
    Duration maxDuration = const Duration(minutes: 2),
  }) async {
    // Check if there's already an active session for this callsign
    if (_activeSessions.containsKey(callsign)) {
      LogService().log('TransferSession: Session already active for $callsign, reusing');
      return _activeSessions[callsign]!;
    }

    final sessionId = _generateSessionId();
    final session = TransferSession._(
      targetCallsign: callsign,
      expectedTotalBytes: expectedTotalBytes,
      maxDuration: maxDuration,
      startedAt: DateTime.now(),
      sessionId: sessionId,
    );

    _activeSessions[callsign] = session;

    // Check if we should use BLE+
    final pairingService = BluetoothClassicPairingService();
    final threshold = pairingService.getAutoUpgradeThreshold();

    if (expectedTotalBytes >= threshold && pairingService.isBLEPlus(callsign)) {
      final classicMac = pairingService.getClassicMac(callsign);
      if (classicMac != null) {
        // Try to establish BLE+ connection
        final btService = BluetoothClassicService();
        final connected = await btService.connect(classicMac);

        if (connected) {
          session._usingBLEPlus = true;
          session._classicMac = classicMac;
          LogService().log(
            'TransferSession[$sessionId]: Started with BLE+ for $callsign '
            '(expected ${_formatBytes(expectedTotalBytes)})',
          );
        } else {
          LogService().log(
            'TransferSession[$sessionId]: BLE+ connection failed, falling back to BLE',
          );
        }
      }
    } else {
      LogService().log(
        'TransferSession[$sessionId]: Started with BLE for $callsign '
        '(expected ${_formatBytes(expectedTotalBytes)}, threshold ${_formatBytes(threshold)})',
      );
    }

    // Set up auto-close timer
    session._autoCloseTimer = Timer(maxDuration, () {
      LogService().log('TransferSession[$sessionId]: Auto-closing after $maxDuration');
      session.end();
    });

    return session;
  }

  /// End the transfer session
  ///
  /// Disconnects Bluetooth Classic if it was used and cleans up resources.
  Future<void> end() async {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;

    _activeSessions.remove(targetCallsign);

    if (_usingBLEPlus && _classicMac != null) {
      final btService = BluetoothClassicService();
      await btService.disconnect(_classicMac!);
      LogService().log('TransferSession[$sessionId]: Ended, disconnected BLE+');
    } else {
      LogService().log('TransferSession[$sessionId]: Ended');
    }

    _usingBLEPlus = false;
    _classicMac = null;
  }

  /// Check if there's an active session for a callsign
  static bool hasActiveSession(String callsign) {
    return _activeSessions.containsKey(callsign);
  }

  /// Get the active session for a callsign (if any)
  static TransferSession? getSession(String callsign) {
    return _activeSessions[callsign];
  }

  /// Get expected bytes for routing decision
  ///
  /// Returns the expected total bytes if there's an active session,
  /// or null if no session exists.
  static int? getExpectedBytes(String callsign) {
    return _activeSessions[callsign]?.expectedTotalBytes;
  }

  /// Check if BLE+ should be used for a callsign
  ///
  /// Returns true if there's an active session that established BLE+.
  static bool shouldUseBLEPlus(String callsign) {
    final session = _activeSessions[callsign];
    return session?.usingBLEPlus ?? false;
  }

  /// Get the Bluetooth Classic MAC for an active BLE+ session
  static String? getClassicMac(String callsign) {
    final session = _activeSessions[callsign];
    if (session != null && session.usingBLEPlus) {
      return session._classicMac;
    }
    return null;
  }

  /// Get all active sessions
  static List<TransferSession> getAllSessions() {
    return _activeSessions.values.toList();
  }

  /// End all active sessions
  static Future<void> endAllSessions() async {
    final sessions = _activeSessions.values.toList();
    for (final session in sessions) {
      await session.end();
    }
  }

  /// Generate a unique session ID
  static String _generateSessionId() {
    final now = DateTime.now();
    return '${now.millisecondsSinceEpoch.toRadixString(36)}';
  }

  /// Format bytes for logging
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() {
    return 'TransferSession('
        'callsign: $targetCallsign, '
        'expected: ${_formatBytes(expectedTotalBytes)}, '
        'usingBLEPlus: $usingBLEPlus, '
        'sessionId: $sessionId)';
  }
}
