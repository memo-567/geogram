# Logging System

Geogram uses a structured logging system with daily rotation and crash detection.

## Directory Structure

```
{dataDir}/logs/
├── crash.txt                    # Critical errors, exceptions, shutdowns
├── access-YYYY-MM-DD.txt        # HTTP request logs (forensics)
└── {YYYY}/                      # Year folder
    └── log-YYYY-MM-DD.txt       # Daily application logs
```

## Log Levels

| Level | Description |
|-------|-------------|
| `DEBUG` | Detailed debugging information |
| `INFO` | General operational messages |
| `WARN` | Warning conditions |
| `ERROR` | Error conditions (also written to crash.txt) |

## Log Entry Format

```
[YYYY-MM-DDTHH:MM:SS.mmm] [LEVEL] Message
```

Example:
```
[2026-01-15T03:42:05.616821] [ERROR] HTTPS server error: SocketException
[2026-01-15T03:42:06.123456] [INFO] Client connected: X3ABC1
```

## Crash Log (crash.txt)

The crash log captures critical events for forensics analysis. Entries are automatically written when:

- Log level is `ERROR`
- Message contains "exception", "fatal", or "crash"
- Process receives SIGTERM or SIGINT signal
- Uncaught exceptions occur

Example crash.txt:
```
[2026-01-15T03:42:05.616821] [ERROR] HTTPS server error: SocketException
[2026-01-15T03:58:00.000000] [SHUTDOWN] SIGTERM received - graceful shutdown requested
```

## Access Log (Forensics)

HTTP requests are logged to separate access log files for security forensics.

**Format:**
```
TIMESTAMP IP METHOD PATH STATUS TIMEms "USER-AGENT"
```

**Example:**
```
2026-01-15T03:42:05.123Z 192.168.1.1 GET /api/status 200 15ms "Mozilla/5.0..."
2026-01-15T03:42:06.456Z 10.0.0.5 POST /chat/message 201 45ms "Geogram/1.7.8"
```

## Log Rotation

- **Daily files**: New log file created at midnight (local time)
- **Yearly folders**: Logs organized by year for easy archival
- **No automatic cleanup**: Logs persist until manually deleted

## Implementation

### CLI Station Server
- File: `lib/cli/pure_station.dart`
- Methods: `_log()`, `_ensureLogSinks()`, `_logAccess()`
- Line: ~9684-9755

### Flutter Application
- File: `lib/services/log_service_native.dart`
- Class: `LogService` (singleton)
- Features: Loop detection, in-memory buffer (1000 entries)

## Loop Detection

The Flutter LogService includes loop detection to prevent log flooding:

- **Window**: 5 seconds
- **Threshold**: 50 identical messages
- **Behavior**: Suppresses repetitive messages, logs summary when loop ends

Example output:
```
[INFO] [LOOP DETECTED] Message repeated 50x in 5000ms: Connection timeout
[INFO] [LOOP ENDED] Suppressed 150 repetitions of: Connection timeout
```

## Reading Logs Programmatically

```dart
// Read today's log (returns full string - may block UI for large files)
final logService = LogService();
final todayLog = await logService.readTodayLog();

// Read today's log in isolate (non-blocking, returns last N lines)
final result = await logService.readTodayLogAsync(maxLines: 1000);
print('Lines: ${result.lines.length}');
print('Total: ${result.totalLines}');
print('Truncated: ${result.truncated}');

// Read crash log
final crashLog = await logService.readCrashLog();

// Clear crash log (after review)
await logService.clearCrashLog();
```

## Security Considerations

- Access logs truncate User-Agent to 50 characters
- Sensitive data (passwords, tokens) is never logged
- IP addresses are sanitized to prevent log injection
- Log files should have restricted permissions (600 or 640)
