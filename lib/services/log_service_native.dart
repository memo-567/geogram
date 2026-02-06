import 'dart:collection';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:path/path.dart' as p;
import 'storage_config.dart';

/// Result of reading log file in isolate
class LogReadResult {
  final List<String> lines;
  final int totalLines;
  final bool truncated;

  LogReadResult({
    required this.lines,
    required this.totalLines,
    required this.truncated,
  });
}

/// Parameters for reading log file in isolate
class _LogReadParams {
  final String filePath;
  final int maxLines;

  _LogReadParams(this.filePath, this.maxLines);
}

/// Read log file in isolate - returns last N lines
Future<LogReadResult> _readLogFileInIsolate(_LogReadParams params) async {
  try {
    final file = File(params.filePath);
    if (!await file.exists()) {
      return LogReadResult(lines: [], totalLines: 0, truncated: false);
    }

    final content = await file.readAsString();
    final allLines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final totalLines = allLines.length;

    if (totalLines <= params.maxLines) {
      return LogReadResult(lines: allLines, totalLines: totalLines, truncated: false);
    }

    // Return only last N lines
    final lines = allLines.sublist(totalLines - params.maxLines);
    return LogReadResult(lines: lines, totalLines: totalLines, truncated: true);
  } catch (e) {
    return LogReadResult(lines: ['Error reading log: $e'], totalLines: 1, truncated: false);
  }
}

/// Log levels for filtering
enum LogLevel { debug, info, warn, error }

/// Global singleton for logging with loop detection
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const int _maxLogFileSizeBytes = 30 * 1024 * 1024; // 30MB
  static const int _pruneTargetSizeBytes = 20 * 1024 * 1024; // Prune to 20MB

  final int maxLogMessages = 1000;
  final Queue<String> _logMessages = Queue<String>();
  int _writeCount = 0;
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
    _initialized = true;

    // On web, we only use in-memory logging
    if (kIsWeb) {
      print('=== Application Started (Web): ${DateTime.now()} ===');
      return;
    }

    // On native platforms, file logging is deferred until switchToProfile() is called.
    // This ensures logs go to the correct profile-specific directory.
    // In-memory logging is available immediately.
    print('=== Application Started (awaiting profile): ${DateTime.now()} ===');
  }

  /// Switch to profile-specific log directory
  ///
  /// Call this when a profile is activated to start writing logs to the
  /// profile's workspace: {devicesDir}/{CALLSIGN}/logs/
  Future<void> switchToProfile(String callsign) async {
    if (kIsWeb || !StorageConfig().isInitialized) return;

    final profileLogsDir = StorageConfig().logsDirForProfile(callsign);

    // Check if we're already using this profile's logs directory
    if (_logsDir != null && p.equals(_logsDir!.path, profileLogsDir)) {
      return;
    }

    // Close existing sinks if any
    try {
      await _logSink?.flush();
      await _logSink?.close();
      await _crashSink?.flush();
      await _crashSink?.close();
    } catch (_) {}

    _logSink = null;
    _crashSink = null;
    _currentLogDay = null;

    // Set up profile-specific logs directory
    _logsDir = Directory(profileLogsDir);
    if (!await _logsDir!.exists()) {
      await _logsDir!.create(recursive: true);
    }

    // Open sinks for current day
    _openSinks(DateTime.now());
    _logSink?.writeln('\n=== Profile activated: $callsign at ${DateTime.now()} ===');
    await _logSink?.flush();
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

      // Check file size every 1000 writes
      _writeCount++;
      if (_writeCount >= 1000) {
        _writeCount = 0;
        _checkAndPruneLogFile(); // Fire and forget
      }
    } catch (e) {
      print('Error writing to log file: $e');
    }
  }

  Future<void> _checkAndPruneLogFile() async {
    if (kIsWeb || _logsDir == null || _currentLogDay == null) return;

    final now = _currentLogDay!;
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final logPath = p.join(_logsDir!.path, '${now.year}', 'log-$dateStr.txt');
    final logFile = File(logPath);

    if (!await logFile.exists()) return;

    final size = await logFile.length();
    if (size <= _maxLogFileSizeBytes) return;

    // Close current sink
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;

    // Read file, keep last ~20MB worth of lines
    final content = await logFile.readAsString();
    final lines = content.split('\n');

    // Estimate bytes per line and calculate how many lines to keep
    final avgLineSize = size ~/ lines.length;
    final linesToKeep = _pruneTargetSizeBytes ~/ avgLineSize;

    final prunedLines = lines.length > linesToKeep
        ? lines.sublist(lines.length - linesToKeep)
        : lines;

    // Write pruned content
    final prunedContent = prunedLines.join('\n');
    await logFile.writeAsString(
        '=== Log pruned at ${DateTime.now().toIso8601String()} (was ${(size / 1024 / 1024).toStringAsFixed(1)}MB) ===\n$prunedContent');

    // Reopen sink
    _logSink = logFile.openWrite(mode: FileMode.append);
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

  @Deprecated('Use switchToProfile(callsign) instead for profile-specific logs')
  Future<void> adoptStorageConfigLogsDir() async {
    // This method is deprecated. Logs are now per-profile.
    // Call switchToProfile(callsign) instead.
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

  /// Read today's log file in a separate isolate for performance
  /// Returns last [maxLines] lines to avoid UI freeze
  Future<LogReadResult> readTodayLogAsync({int maxLines = 1000}) async {
    if (kIsWeb) {
      return LogReadResult(lines: [], totalLines: 0, truncated: false);
    }
    if (!_initialized) {
      await init();
    }
    if (_logsDir == null) {
      return LogReadResult(lines: [], totalLines: 0, truncated: false);
    }

    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final filePath = p.join(_logsDir!.path, '${now.year}', 'log-$dateStr.txt');

    return await compute(_readLogFileInIsolate, _LogReadParams(filePath, maxLines));
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
