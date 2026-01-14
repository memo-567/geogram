import 'dart:collection';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'storage_config.dart';

/// Log levels for filtering
enum LogLevel { debug, info, warn, error }

/// Global singleton for logging with loop detection
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final int maxLogMessages = 1000;
  final Queue<String> _logMessages = Queue<String>();
  final List<Function(String)> _listeners = [];
  Directory? _logsDir;
  IOSink? _logSink;
  IOSink? _crashSink;
  DateTime? _currentLogDay;
  bool _initialized = false;

  // Loop detection: track recent messages to detect tight loops
  final Map<String, _LogCounter> _recentMessages = {};
  static const int _loopDetectionWindowMs = 5000; // 5 second window
  static const int _loopThreshold = 50; // warn if same message > 50 times in window
  DateTime? _lastLoopWarning;
  String? _suppressedMessage; // currently suppressed message pattern
  int _suppressedCount = 0;

  Future<void> init() async {
    if (_initialized) return;

    // On web, we only use in-memory logging
    if (kIsWeb) {
      _initialized = true;
      print('=== Application Started (Web): ${DateTime.now()} ===');
      return;
    }

    try {
      // Prefer StorageConfig location when available
      String basePath;
      if (StorageConfig().isInitialized) {
        basePath = StorageConfig().logsDir;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        basePath = p.join(appDir.path, 'geogram', 'logs');
      }

      _logsDir = Directory(basePath);
      if (!await _logsDir!.exists()) {
        await _logsDir!.create(recursive: true);
      }

      _openSinks(DateTime.now());
      _initialized = true;

      // Write startup marker
      _logSink?.writeln('\n=== Application Started: ${DateTime.now()} ===');
      await _logSink?.flush();
    } catch (e) {
      // Can't use log() here as we're in init(), use print on web or stderr on native
      print('Error initializing log file: $e');
      _initialized = true; // Still mark as initialized to allow in-memory logging
    }
  }

  void _rotateIfNeeded(DateTime now) {
    if (kIsWeb || _logsDir == null) return;

    final today = DateTime(now.year, now.month, now.day);
    if (_currentLogDay != null &&
        _currentLogDay!.year == today.year &&
        _currentLogDay!.month == today.month &&
        _currentLogDay!.day == today.day &&
        _logSink != null &&
        _crashSink != null) {
      return;
    }

    _openSinks(now);
  }

  void _writeToFile(String message, {bool isCrash = false}) {
    if (kIsWeb) return;

    try {
      _logSink?.writeln(message);
      if (isCrash) {
        _crashSink?.writeln(message);
      }
    } catch (e) {
      print('Error writing to log file: $e');
    }
  }

  void _openSinks(DateTime now) {
    if (_logsDir == null) return;
    if (!_logsDir!.existsSync()) {
      _logsDir!.createSync(recursive: true);
    }

    final crashFile = File(p.join(_logsDir!.path, 'crash.txt'));
    _crashSink ??= crashFile.openWrite(mode: FileMode.append);

    final today = DateTime(now.year, now.month, now.day);
    if (_currentLogDay != null &&
        _currentLogDay!.year == today.year &&
        _currentLogDay!.month == today.month &&
        _currentLogDay!.day == today.day &&
        _logSink != null) {
      return;
    }

    try {
      _logSink?.flush();
      _logSink?.close();
    } catch (_) {}

    final yearDir = Directory(p.join(_logsDir!.path, now.year.toString()));
    if (!yearDir.existsSync()) {
      yearDir.createSync(recursive: true);
    }

    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final logFile = File(p.join(yearDir.path, 'log-$dateStr.txt'));
    _logSink = logFile.openWrite(mode: FileMode.append);
    _currentLogDay = today;
    _logSink!.writeln('=== Log start ${now.toIso8601String()} ===');
  }

  Future<void> dispose() async {
    if (kIsWeb) return;

    try {
      await _logSink?.flush();
      await _logSink?.close();
      await _crashSink?.flush();
      await _crashSink?.close();
    } catch (e) {
      print('Error closing log file: $e');
    }
  }

  void addListener(Function(String) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(String) listener) {
    _listeners.remove(listener);
  }

  List<String> get messages => _logMessages.toList();

  void log(String message, {LogLevel level = LogLevel.info}) {
    final now = DateTime.now();
    _rotateIfNeeded(now);

    // Loop detection: extract message pattern (remove numbers/timestamps for grouping)
    final pattern = _extractPattern(message);
    final counter = _recentMessages[pattern] ??= _LogCounter();

    // Clean old entries and increment counter
    counter.cleanOld(now, _loopDetectionWindowMs);
    counter.increment(now);

    // Check for potential loop
    if (counter.count >= _loopThreshold) {
      // If this is a new loop detection or enough time passed, warn
      if (_suppressedMessage != pattern) {
        // Emit suppression start warning
        if (_suppressedMessage != null && _suppressedCount > 0) {
          _emitLog(now, '[LOOP] Suppressed $_suppressedCount repetitions of: $_suppressedMessage', LogLevel.warn);
        }
        _suppressedMessage = pattern;
        _suppressedCount = 0;
        _emitLog(now, '[LOOP DETECTED] Message repeated ${counter.count}x in ${_loopDetectionWindowMs}ms: $message', LogLevel.warn);
      }
      _suppressedCount++;

      // Only log every 100th message during loop
      if (_suppressedCount % 100 != 0) {
        return;
      }
    } else if (_suppressedMessage == pattern && counter.count < _loopThreshold ~/ 2) {
      // Loop ended, emit summary
      if (_suppressedCount > 0) {
        _emitLog(now, '[LOOP ENDED] Suppressed $_suppressedCount repetitions of: $_suppressedMessage', LogLevel.info);
      }
      _suppressedMessage = null;
      _suppressedCount = 0;
    }

    _emitLog(now, message, level);
  }

  void _emitLog(DateTime now, String message, LogLevel level) {
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final levelStr = level.name.toUpperCase().padRight(5);
    final logEntry = '$date $time [$levelStr] $message';

    _logMessages.add(logEntry);

    // Keep only the last maxLogMessages
    if (_logMessages.length > maxLogMessages) {
      _logMessages.removeFirst();
    }

    // Write to file asynchronously
    final isCrash = level == LogLevel.error ||
        message.toLowerCase().contains('exception') ||
        message.toLowerCase().contains('crash') ||
        message.toLowerCase().contains('fatal');

    _writeToFile(logEntry, isCrash: isCrash);

    // Notify all listeners
    for (var listener in _listeners) {
      listener(logEntry);
    }
  }

  /// Extract a pattern from message by removing variable parts (numbers, timestamps, IDs)
  String _extractPattern(String message) {
    // Replace hex strings, numbers, UUIDs with placeholders
    return message
        .replaceAll(RegExp(r'\b[0-9a-fA-F]{8,}\b'), '<HEX>')
        .replaceAll(RegExp(r'\b\d+\.\d+\b'), '<NUM>')
        .replaceAll(RegExp(r'\b\d{4,}\b'), '<ID>')
        .replaceAll(RegExp(r'\b\d+\b'), '<N>');
  }

  /// Log with specific level shortcuts
  void debug(String message) => log(message, level: LogLevel.debug);
  void info(String message) => log(message, level: LogLevel.info);
  void warn(String message) => log(message, level: LogLevel.warn);
  void error(String message) => log(message, level: LogLevel.error);

  void clear() {
    _logMessages.clear();
    _recentMessages.clear();
    _suppressedMessage = null;
    _suppressedCount = 0;
    for (var listener in _listeners) {
      listener('');
    }
  }

  Future<void> adoptStorageConfigLogsDir() async {
    if (kIsWeb || !StorageConfig().isInitialized) return;
    final desiredPath = StorageConfig().logsDir;

    if (_logsDir != null && p.equals(_logsDir!.path, desiredPath)) {
      return;
    }

    try {
      await _logSink?.flush();
      await _logSink?.close();
      await _crashSink?.flush();
      await _crashSink?.close();
    } catch (_) {}

    _logSink = null;
    _crashSink = null;
    _currentLogDay = null;

    _logsDir = Directory(desiredPath);
    if (!await _logsDir!.exists()) {
      await _logsDir!.create(recursive: true);
    }

    _openSinks(DateTime.now());
  }

  Future<String?> readTodayLog() async {
    if (kIsWeb) return null;
    if (!_initialized) {
      await init();
    }
    if (_logsDir == null) return null;

    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File(p.join(_logsDir!.path, '${now.year}', 'log-$dateStr.txt'));
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> readCrashLog() async {
    if (kIsWeb) return null;
    if (!_initialized) {
      await init();
    }
    if (_logsDir == null) return null;

    final crashFile = File(p.join(_logsDir!.path, 'crash.txt'));
    if (!await crashFile.exists()) return null;
    try {
      return await crashFile.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCrashLog() async {
    if (kIsWeb) return;
    if (!_initialized) {
      await init();
    }
    if (_logsDir == null) return;

    final crashFile = File(p.join(_logsDir!.path, 'crash.txt'));
    try {
      await _crashSink?.flush();
      await _crashSink?.close();
    } catch (_) {}
    _crashSink = null;

    if (await crashFile.exists()) {
      try {
        await crashFile.delete();
      } catch (_) {}
    }

    _rotateIfNeeded(DateTime.now());
  }

  Future<Map<String, dynamic>?> readHeartbeat() async {
    if (kIsWeb) return null;
    if (!_initialized) {
      await init();
    }
    if (_logsDir == null) return null;

    final file = File(p.join(_logsDir!.path, 'heartbeat.json'));
    if (!await file.exists()) return null;
    try {
      final contents = await file.readAsString();
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// Helper class for counting log message occurrences within a time window
class _LogCounter {
  final List<DateTime> _timestamps = [];

  int get count => _timestamps.length;

  void increment(DateTime now) {
    _timestamps.add(now);
  }

  void cleanOld(DateTime now, int windowMs) {
    final cutoff = now.subtract(Duration(milliseconds: windowMs));
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
  }
}
