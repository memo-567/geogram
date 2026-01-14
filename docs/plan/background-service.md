# Background service hardening plan

Context: the Android client sometimes crashes, which brings down the background WebSocket handler that the station server depends on. We now have daily/crash logs, but we need the app to self-recover on Android and keep the socket alive even under OS pressure.

Goals
- Auto-restart the background service on Android after crashes/process death.
- Keep the WebSocket reachable for station requests (foreground/keep-alive).
- Surface health/logs for forensics without losing user profiles/keys.

Current signals
- Foreground service wrapper: `lib/services/ble_foreground_service.dart` is already used by `websocket_service.dart` to keep the socket alive.
- Crash logging: `CrashService` + `LogService` write to `logs/<year>/log-YYYY-MM-DD.txt` and `logs/crash.txt`.
- StorageConfig drives the on-disk paths; logs follow it.

Plan (phased)
1) Crash-aware restart hook (Android)
   - On Flutter crash (`_setupCrashHandlers`), set a native flag via the existing crash channel and request a restart intent/service.
   - Add a lightweight Android `Service`/`BroadcastReceiver` that:
     - Starts on BOOT_COMPLETED and PACKAGE_REPLACED to recover after device reboot/app update.
     - Listens for the crash flag and relaunches the Flutter activity with minimal delay (guard with backoff to avoid loops).
   - Ensure the restart path rehydrates StorageConfig and LogService early so sockets reconnect with the right data dir.

2) Background watchdog for the WebSocket
   - Move WebSocket connection maintenance into a dedicated isolate/service-friendly class that can be driven from the foreground service.
   - Add a periodic health ping from `BLEForegroundService` → `websocket_service` (already has `onKeepAlivePing`) to detect dead sockets and reconnect.
   - Record watchdog events to the daily log and `crash.txt` when reconnection fails repeatedly (e.g., 3 consecutive failures with exponential backoff).

3) Make the foreground service resilient
   - Promote the existing BLE foreground service notification to an explicit “Station link” channel on Android so the OS treats it as user-visible/important.
   - Add an action button in the notification to “Restart link” which triggers a reconnection without opening the UI.
   - Ensure the service stops cleanly on sign-out/profile switch and rebinds on the next profile load to avoid using stale keys.

4) Persistence and key safety
   - Before reconnecting, validate that the active profile has a usable `nsec`; if missing, attempt repair from cached profiles (only those containing `nsec`), and log any recovery action.
   - Deny connecting without a valid `nsec` and raise a user notification plus log entry instead of creating a new account (prevents silent key loss).

5) Observability
   - Extend Log App to show a “Background service” status card (last ping, last reconnect, last crash) sourced from a small JSON heartbeat file under `logs/`.
   - Include a one-tap “export health bundle” that zips today’s log + crash.txt + heartbeat for support.

6) Testing & rollout
   - Unit: simulate crash handler → restart intent path; watchdog reconnection logic with forced socket failures.
   - Instrumented: Android background restrictions, Doze, and reboot to verify BOOT_COMPLETED receiver and foreground notification.
   - Beta gate: enable auto-restart + watchdog behind a feature flag, collect stability metrics from logs before full rollout.

Risks / mitigations
- Restart loop: add exponential backoff and cap retries; show notification if suppressed.
- Battery impact: keep pings sparse (e.g., 3–5 min) and only when station is configured; stop service when user signs out.
- Privacy: ensure logs/heartbeat contain no sensitive payloads—redact tokens/keys.
