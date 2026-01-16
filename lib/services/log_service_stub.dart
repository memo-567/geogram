import 'dart:collection';

/// Log levels for filtering
enum LogLevel { debug, info, warn, error }

/// Result of reading log file
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

/// Console-only log service for CLI and web
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final int maxLogMessages = 1000;
  final Queue<String> _logMessages = Queue<String>();
  final List<Function(String)> _listeners = [];
  bool _initialized = false;

  // Loop detection
  final Map<String, _LogCounter> _recentMessages = {};
  static const int _loopDetectionWindowMs = 5000;
  static const int _loopThreshold = 50;
  String? _suppressedMessage;
  int _suppressedCount = 0;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    print('=== Application Started: ${DateTime.now()} ===');
  }

  Future<void> dispose() async {}

  void addListener(Function(String) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(String) listener) {
    _listeners.remove(listener);
  }

  List<String> get messages => _logMessages.toList();

  void log(String message, {LogLevel level = LogLevel.info}) {
    final now = DateTime.now();

    final pattern = _extractPattern(message);
    final counter = _recentMessages[pattern] ??= _LogCounter();

    counter.cleanOld(now, _loopDetectionWindowMs);
    counter.increment(now);

    if (counter.count >= _loopThreshold) {
      if (_suppressedMessage != pattern) {
        if (_suppressedMessage != null && _suppressedCount > 0) {
          _emitLog(now, '[LOOP] Suppressed $_suppressedCount repetitions of: $_suppressedMessage', LogLevel.warn);
        }
        _suppressedMessage = pattern;
        _suppressedCount = 0;
        _emitLog(now, '[LOOP DETECTED] Message repeated ${counter.count}x in ${_loopDetectionWindowMs}ms: $message', LogLevel.warn);
      }
      _suppressedCount++;

      if (_suppressedCount % 100 != 0) {
        return;
      }
    } else if (_suppressedMessage == pattern && counter.count < _loopThreshold ~/ 2) {
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

    if (_logMessages.length > maxLogMessages) {
      _logMessages.removeFirst();
    }

    // Console output for errors
    if (level == LogLevel.error) {
      print(logEntry);
    }

    for (var listener in _listeners) {
      listener(logEntry);
    }
  }

  String _extractPattern(String message) {
    return message
        .replaceAll(RegExp(r'\b[0-9a-fA-F]{8,}\b'), '<HEX>')
        .replaceAll(RegExp(r'\b\d+\.\d+\b'), '<NUM>')
        .replaceAll(RegExp(r'\b\d{4,}\b'), '<ID>')
        .replaceAll(RegExp(r'\b\d+\b'), '<N>');
  }

  void debug(String message) => log(message, level: LogLevel.debug);
  void info(String message) => log(message, level: LogLevel.info);
  void warn(String message) => log(message, level: LogLevel.warn);
  void error(String message) => log(message, level: LogLevel.error);

  Future<String?> readTodayLog() async => null;
  Future<LogReadResult> readTodayLogAsync({int maxLines = 1000}) async {
    return LogReadResult(lines: [], totalLines: 0, truncated: false);
  }
  Future<String?> readCrashLog() async => null;
  Future<void> clearCrashLog() async {}
  Future<void> adoptStorageConfigLogsDir() async {}
  Future<Map<String, dynamic>?> readHeartbeat() async => null;

  void clear() {
    _logMessages.clear();
    _recentMessages.clear();
    _suppressedMessage = null;
    _suppressedCount = 0;
    for (var listener in _listeners) {
      listener('');
    }
  }
}

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
