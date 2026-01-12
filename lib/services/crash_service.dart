/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'storage_config.dart';
import '../version.dart';

/// Service to manage crash handling and recovery on Android.
///
/// This service:
/// - Logs crashes synchronously to ensure they're written before process dies
/// - Communicates with native Android side to trigger restarts
/// - Provides access to crash logs for debugging
class CrashService {
  static final CrashService _instance = CrashService._internal();
  factory CrashService() => _instance;
  CrashService._internal();

  static const _channel = MethodChannel('dev.geogram/crash');

  File? _crashLogFile;
  bool _initialized = false;

  /// Whether the crash service has been initialized
  bool get isInitialized => _initialized;

  /// Get the crash log file path
  String? get crashLogPath => _crashLogFile?.path;

  /// Initialize crash handling
  /// Call this BEFORE runApp() to catch early crashes
  Future<void> initialize() async {
    if (_initialized) return;

    // On web, we don't need file-based crash logging
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      // Use StorageConfig's logsDir if available, otherwise use a fallback
      String logsDir;
      if (StorageConfig().isInitialized) {
        logsDir = StorageConfig().logsDir;
      } else {
        // Fallback: StorageConfig not yet initialized
        // This can happen during early crash handling
        logsDir = '/tmp';
      }

      final crashDir = Directory(logsDir);
      if (!await crashDir.exists()) {
        await crashDir.create(recursive: true);
      }

      _crashLogFile = File(path.join(logsDir, 'crashes.log'));
      _initialized = true;
    } catch (e) {
      // Can't do much here, just mark as initialized for in-memory operation
      stderr.writeln('CrashService: Failed to initialize crash log file: $e');
      _initialized = true;
    }
  }

  /// Re-initialize with proper paths after StorageConfig is ready
  Future<void> reinitialize() async {
    if (kIsWeb) return;

    if (StorageConfig().isInitialized) {
      final logsDir = StorageConfig().logsDir;
      final crashDir = Directory(logsDir);
      if (!await crashDir.exists()) {
        await crashDir.create(recursive: true);
      }
      _crashLogFile = File(path.join(logsDir, 'crashes.log'));
    }
  }

  /// Log crash synchronously (blocking) to ensure it's written before process dies
  void logCrashSync(String type, dynamic error, StackTrace? stackTrace) {
    if (kIsWeb) {
      // On web, just print to console
      print('CRASH [$type]: $error');
      if (stackTrace != null) {
        print('Stack trace:\n$stackTrace');
      }
      return;
    }

    if (!_initialized || _crashLogFile == null) {
      stderr.writeln('CRASH [$type]: $error');
      if (stackTrace != null) {
        stderr.writeln('Stack trace:\n$stackTrace');
      }
      return;
    }

    final crashEntry = _buildCrashEntry(type, error, stackTrace);

    try {
      // Use sync write to ensure crash is logged before process dies
      _crashLogFile!.writeAsStringSync(
        crashEntry,
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Last resort: print to stderr
      stderr.writeln('CRASH: $crashEntry');
    }
  }

  /// Build a crash report entry
  String _buildCrashEntry(String type, dynamic error, StackTrace? stackTrace) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();

    buffer.writeln('=== CRASH REPORT ===');
    buffer.writeln('Timestamp: $timestamp');
    buffer.writeln('Type: $type');
    buffer.writeln('App Version: $appVersion ($appBuildNumber)');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Error: $error');
    if (stackTrace != null) {
      buffer.writeln('Stack Trace:');
      buffer.writeln(stackTrace.toString());
    }
    buffer.writeln('=== END CRASH REPORT ===');
    buffer.writeln();

    return buffer.toString();
  }

  /// Notify native side that Flutter crashed (for restart logic)
  Future<void> notifyNativeCrash(String error) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('onFlutterCrash', {
        'error': error,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // Native side might already be dead, ignore
    }
  }

  /// Enable or disable auto-restart on crash
  Future<void> setRestartOnCrash(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('setRestartOnCrash', {'enabled': enabled});
    } catch (e) {
      stderr.writeln('CrashService: Failed to set restart on crash: $e');
    }
  }

  /// Read Flutter crash logs
  Future<String?> readCrashLogs() async {
    if (kIsWeb) return null;

    if (_crashLogFile == null || !await _crashLogFile!.exists()) {
      return null;
    }

    try {
      return await _crashLogFile!.readAsString();
    } catch (e) {
      return null;
    }
  }

  /// Read native Android crash logs
  Future<String?> readNativeCrashLogs() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<String?>('getCrashLogs');
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Read all crash logs (Flutter + Native)
  Future<String?> readAllCrashLogs() async {
    final flutterLogs = await readCrashLogs();
    final nativeLogs = await readNativeCrashLogs();

    final parts = <String>[];
    if (flutterLogs != null && flutterLogs.isNotEmpty) {
      parts.add('=== FLUTTER CRASHES ===\n$flutterLogs');
    }
    if (nativeLogs != null && nativeLogs.isNotEmpty) {
      parts.add('=== NATIVE CRASHES ===\n$nativeLogs');
    }

    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  /// Clear Flutter crash logs
  Future<void> clearCrashLogs() async {
    if (kIsWeb) return;

    if (_crashLogFile != null && await _crashLogFile!.exists()) {
      await _crashLogFile!.delete();
    }
  }

  /// Clear native Android crash logs
  Future<void> clearNativeCrashLogs() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('clearNativeCrashLogs');
    } catch (e) {
      // Ignore
    }
  }

  /// Clear all crash logs
  Future<void> clearAllCrashLogs() async {
    await clearCrashLogs();
    await clearNativeCrashLogs();
  }

  /// Check if there are any crash logs from a previous session
  Future<bool> hasCrashLogs() async {
    final flutterLogs = await readCrashLogs();
    if (flutterLogs != null && flutterLogs.isNotEmpty) return true;

    final nativeLogs = await readNativeCrashLogs();
    if (nativeLogs != null && nativeLogs.isNotEmpty) return true;

    return false;
  }

  /// Check if the app just recovered from a crash
  Future<bool> didRecoverFromCrash() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('didRecoverFromCrash');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Clear the crash recovery flag
  Future<void> clearRecoveredFromCrash() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('clearRecoveredFromCrash');
    } catch (e) {
      // Ignore
    }
  }
}
