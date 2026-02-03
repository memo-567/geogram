package dev.geogram;

import android.app.AlarmManager;
import android.app.Application;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

import io.flutter.plugin.common.MethodChannel;

/**
 * Custom Application class for global crash handling and auto-restart.
 *
 * This class:
 * 1. Catches uncaught exceptions from any thread
 * 2. Logs crash details to persistent storage
 * 3. Schedules app restart via BLEForegroundService or AlarmManager
 * 4. Prevents crash loops by tracking crash frequency
 */
public class GeogramApplication extends Application {
    private static final String TAG = "GeogramApplication";
    private static GeogramApplication instance;

    // Crash loop prevention
    private static final String PREFS_NAME = "CrashPrefs";
    private static final String KEY_LAST_CRASH = "lastCrashTime";
    private static final String KEY_CRASH_COUNT = "crashCount";
    private static final long CRASH_WINDOW_MS = 60 * 1000; // 1 minute
    private static final int MAX_CRASHES_IN_WINDOW = 3;

    // Restart delay
    private static final long RESTART_DELAY_MS = 2000; // 2 seconds

    // Method channel for Flutter communication (set from MainActivity)
    private static MethodChannel crashChannel;

    // Track if we should auto-restart
    private static boolean restartOnCrash = true;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;

        // Set global uncaught exception handler
        final Thread.UncaughtExceptionHandler defaultHandler =
            Thread.getDefaultUncaughtExceptionHandler();

        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            Log.e(TAG, "Uncaught exception in thread " + thread.getName(), throwable);

            // Check if this is Android 15+ foreground service timeout exception
            // This is expected and already handled by BLEForegroundService.onTimeout()
            // Just log it and return without crashing
            if (isForegroundServiceTimeoutException(throwable)) {
                Log.w(TAG, "Suppressing ForegroundServiceDidNotStopInTimeException - already handled by onTimeout()");
                logCrashToFile(throwable, "ForegroundServiceTimeout_Suppressed");
                return; // Don't crash - the service already stopped itself
            }

            // Log crash to file synchronously
            logCrashToFile(throwable, "NativeUncaughtException");

            // Schedule restart before dying (if not in crash loop)
            if (restartOnCrash && shouldRestart()) {
                scheduleRestart();
            }

            // Call default handler (this will kill the process)
            if (defaultHandler != null) {
                defaultHandler.uncaughtException(thread, throwable);
            }
        });

        Log.d(TAG, "GeogramApplication initialized with crash handler");
    }

    public static GeogramApplication getInstance() {
        return instance;
    }

    /**
     * Check if the exception is a ForegroundServiceDidNotStopInTimeException.
     * This exception is thrown by Android 15+ when a foreground service with a time limit
     * (like dataSync) doesn't stop within its timeout. Since BLEForegroundService.onTimeout()
     * already handles this gracefully, we suppress this exception to prevent crashes.
     */
    private static boolean isForegroundServiceTimeoutException(Throwable throwable) {
        if (throwable == null) return false;

        // Check exception class name (using string to avoid compile-time dependency on API 35)
        String className = throwable.getClass().getName();
        if (className.contains("ForegroundServiceDidNotStopInTimeException")) {
            return true;
        }

        // Also check the message for the specific service
        String message = throwable.getMessage();
        if (message != null && message.contains("did not stop within its timeout")) {
            return true;
        }

        return false;
    }

    public static void setCrashChannel(MethodChannel channel) {
        crashChannel = channel;
    }

    public static void setRestartOnCrash(boolean enabled) {
        restartOnCrash = enabled;
        Log.d(TAG, "Restart on crash set to: " + enabled);
    }

    /**
     * Called from Flutter when Flutter isolate crashes.
     * This allows the native side to trigger restart even if Flutter is dead.
     */
    public static void onFlutterCrash(String error, long timestamp, String stackTrace,
                                       String appVersion, String recentLogs) {
        Log.e(TAG, "Flutter crash reported: " + error);

        if (instance != null) {
            // Log to native crash file as well
            instance.logFlutterCrashToFile(error, timestamp, stackTrace, appVersion, recentLogs);

            if (restartOnCrash && instance.shouldRestart()) {
                instance.scheduleRestart();
            }
        }
    }

    /**
     * Log crash details to persistent storage.
     * Uses synchronous file I/O to ensure the log is written before the process dies.
     */
    private void logCrashToFile(Throwable throwable, String crashType) {
        try {
            File crashDir = new File(getFilesDir(), "geogram/logs");
            if (!crashDir.exists()) {
                crashDir.mkdirs();
            }

            File crashFile = new File(crashDir, "crashes.txt");
            FileOutputStream fos = new FileOutputStream(crashFile, true);

            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US);
            String timestamp = sdf.format(new Date());

            StringBuilder sb = new StringBuilder();
            sb.append("=== CRASH REPORT ===\n");
            sb.append("Timestamp: ").append(timestamp).append("\n");
            sb.append("Type: ").append(crashType).append("\n");
            sb.append("Android Version: ").append(Build.VERSION.RELEASE)
              .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
            sb.append("Device: ").append(Build.MANUFACTURER).append(" ")
              .append(Build.MODEL).append("\n");

            // Get stack trace
            StringWriter sw = new StringWriter();
            PrintWriter pw = new PrintWriter(sw);
            throwable.printStackTrace(pw);
            sb.append("Error: ").append(throwable.getMessage()).append("\n");
            sb.append("Stack Trace:\n").append(sw.toString());
            sb.append("=== END CRASH REPORT ===\n\n");

            fos.write(sb.toString().getBytes());
            fos.flush();
            fos.close();

            Log.d(TAG, "Crash logged to: " + crashFile.getAbsolutePath());
        } catch (Exception e) {
            Log.e(TAG, "Failed to write crash log", e);
        }
    }

    /**
     * Log Flutter crash to native crash file for unified crash log access.
     * Includes stack trace and recent logs for comprehensive debugging.
     */
    private void logFlutterCrashToFile(String error, long timestamp, String stackTrace,
                                        String appVersion, String recentLogs) {
        try {
            File crashDir = new File(getFilesDir(), "geogram/logs");
            if (!crashDir.exists()) {
                crashDir.mkdirs();
            }

            File crashFile = new File(crashDir, "crashes.txt");
            FileOutputStream fos = new FileOutputStream(crashFile, true);

            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US);
            String timestampStr = sdf.format(new Date(timestamp));

            StringBuilder sb = new StringBuilder();
            sb.append("=== CRASH REPORT ===\n");
            sb.append("Timestamp: ").append(timestampStr).append("\n");
            sb.append("Type: FlutterCrash\n");

            // App version
            if (appVersion != null && !appVersion.isEmpty()) {
                sb.append("App Version: ").append(appVersion).append("\n");
            }

            // Device info
            sb.append("Android Version: ").append(Build.VERSION.RELEASE)
              .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
            sb.append("Device: ").append(Build.MANUFACTURER).append(" ")
              .append(Build.MODEL).append("\n");
            sb.append("Device Product: ").append(Build.PRODUCT).append("\n");
            sb.append("Device Hardware: ").append(Build.HARDWARE).append("\n");

            // Error message
            sb.append("\nError: ").append(error).append("\n");

            // Stack trace
            if (stackTrace != null && !stackTrace.isEmpty()) {
                sb.append("\nStack Trace:\n");
                sb.append(stackTrace).append("\n");
            }

            // Recent logs for context
            if (recentLogs != null && !recentLogs.isEmpty()) {
                sb.append("\n--- Recent Log Entries (before crash) ---\n");
                sb.append(recentLogs).append("\n");
                sb.append("--- End Recent Logs ---\n");
            }

            sb.append("=== END CRASH REPORT ===\n\n");

            fos.write(sb.toString().getBytes());
            fos.flush();
            fos.close();

            Log.d(TAG, "Flutter crash logged to: " + crashFile.getAbsolutePath());
        } catch (Exception e) {
            Log.e(TAG, "Failed to write Flutter crash log", e);
        }
    }

    /**
     * Check if we should restart based on crash frequency.
     * Prevents crash loops by disabling restart after too many crashes in a short window.
     */
    private boolean shouldRestart() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        long lastCrash = prefs.getLong(KEY_LAST_CRASH, 0);
        int crashCount = prefs.getInt(KEY_CRASH_COUNT, 0);
        long now = System.currentTimeMillis();

        // Reset counter if outside window
        if (now - lastCrash > CRASH_WINDOW_MS) {
            crashCount = 0;
        }

        crashCount++;
        prefs.edit()
            .putLong(KEY_LAST_CRASH, now)
            .putInt(KEY_CRASH_COUNT, crashCount)
            .apply();

        if (crashCount > MAX_CRASHES_IN_WINDOW) {
            Log.w(TAG, "Too many crashes (" + crashCount + ") in " + CRASH_WINDOW_MS + "ms window, not auto-restarting");
            return false;
        }

        Log.d(TAG, "Crash count: " + crashCount + " (max: " + MAX_CRASHES_IN_WINDOW + ")");
        return true;
    }

    /**
     * Schedule app restart.
     * First tries to use BLEForegroundService (if running), falls back to AlarmManager.
     */
    private void scheduleRestart() {
        Log.d(TAG, "Scheduling app restart...");

        try {
            // Try to use the existing foreground service for restart
            Intent intent = new Intent(this, BLEForegroundService.class);
            intent.setAction("SCHEDULE_RESTART");

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }
            Log.d(TAG, "Restart scheduled via BLEForegroundService");
        } catch (Exception e) {
            Log.e(TAG, "Failed to schedule restart via service, using AlarmManager", e);
            scheduleRestartWithAlarm();
        }
    }

    /**
     * Fallback restart using AlarmManager if service-based restart fails.
     */
    private void scheduleRestartWithAlarm() {
        try {
            Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                                      Intent.FLAG_ACTIVITY_CLEAR_TASK);

                int flags = PendingIntent.FLAG_ONE_SHOT;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    flags |= PendingIntent.FLAG_IMMUTABLE;
                }

                PendingIntent pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    launchIntent,
                    flags
                );

                AlarmManager alarmManager =
                    (AlarmManager) getSystemService(Context.ALARM_SERVICE);

                if (alarmManager == null) {
                    Log.e(TAG, "AlarmManager not available");
                    return;
                }

                // Restart after delay
                long restartTime = System.currentTimeMillis() + RESTART_DELAY_MS;

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        restartTime,
                        pendingIntent
                    );
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        restartTime,
                        pendingIntent
                    );
                }

                Log.d(TAG, "Restart scheduled via AlarmManager for " + restartTime);
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to schedule restart with AlarmManager", e);
        }
    }

    /**
     * Read native crash logs.
     * Called from Flutter via MethodChannel.
     */
    public String readCrashLogs() {
        try {
            File crashFile = new File(getFilesDir(), "geogram/logs/crashes.txt");
            if (crashFile.exists()) {
                java.io.FileInputStream fis = new java.io.FileInputStream(crashFile);
                byte[] data = new byte[(int) crashFile.length()];
                fis.read(data);
                fis.close();
                return new String(data);
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to read crash logs", e);
        }
        return null;
    }

    /**
     * Clear native crash logs.
     * Called from Flutter via MethodChannel.
     */
    public boolean clearCrashLogs() {
        try {
            File crashFile = new File(getFilesDir(), "geogram/logs/crashes.txt");
            if (crashFile.exists()) {
                return crashFile.delete();
            }
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to clear crash logs", e);
            return false;
        }
    }

    /**
     * Mark that we recovered from a crash (for showing notification).
     */
    public void markRecoveredFromCrash() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putBoolean("recoveredFromCrash", true).apply();
    }

    /**
     * Check if we just recovered from a crash.
     */
    public boolean didRecoverFromCrash() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        return prefs.getBoolean("recoveredFromCrash", false);
    }

    /**
     * Clear the recovered from crash flag.
     */
    public void clearRecoveredFromCrash() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().remove("recoveredFromCrash").apply();
    }
}
