package dev.geogram;

import android.Manifest;
import android.app.ForegroundServiceStartNotAllowedException;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import io.flutter.plugin.common.MethodChannel;

/**
 * Foreground service to keep BLE and WebSocket connections active when app goes to background.
 * Android aggressively throttles background operations to save battery.
 * This service keeps the app alive with a persistent notification and handles:
 * 1. BLE GATT server operations
 * 2. WebSocket keep-alive pings to the internet station (p2p.radio)
 *
 * The WebSocket keep-alive is critical because Android devices are servers that need
 * to be reachable by outside visitors even when the display is off.
 */
public class BLEForegroundService extends Service {

    private static final String TAG = "BLEForegroundService";
    private static final String CHANNEL_ID = "geogram_ble_channel";
    private static final int NOTIFICATION_ID = 1001;

    // WebSocket keep-alive interval (55 seconds - slightly less than the 60s Dart timer
    // to ensure we always beat the server's idle timeout)
    private static final long KEEPALIVE_INTERVAL_MS = 55 * 1000;

    // BLE advertising refresh interval (30 seconds - matches the Dart timer interval)
    private static final long BLE_ADVERTISE_INTERVAL_MS = 30 * 1000;

    // BLE scan interval (60 seconds - for proximity detection)
    private static final long BLE_SCAN_INTERVAL_MS = 60 * 1000;

    // Restart delay after crash
    private static final long RESTART_DELAY_MS = 3000; // 3 seconds

    private PowerManager.WakeLock wakeLock;
    private Handler restartHandler;
    private Handler keepAliveHandler;
    private Runnable keepAliveRunnable;
    private boolean keepAliveEnabled = false;

    // BLE advertising keep-alive (separate from WebSocket)
    private Handler bleAdvertiseHandler;
    private Runnable bleAdvertiseRunnable;
    private boolean bleAdvertiseEnabled = false;

    // BLE scan keep-alive (for proximity detection)
    private Handler bleScanHandler;
    private Runnable bleScanRunnable;
    private boolean bleScanEnabled = false;

    // Track if dataSync type is available (Android 15+ has 6-hour limit)
    private boolean dataSyncExhausted = false;

    // Track if service is already in foreground to avoid duplicate startForeground calls
    private boolean isInForeground = false;

    // Station info for notification display
    private static String userCallsign = null;
    private static String stationName = null;
    private static String stationUrl = null;

    // Track if BLE keepalive was requested (survives service restart)
    private static boolean bleKeepAliveRequested = false;

    // Track if BLE scan keepalive was requested (survives service restart)
    private static boolean bleScanKeepAliveRequested = false;

    // Static reference to method channel for callbacks to Flutter
    private static MethodChannel methodChannel;

    // Track consecutive MethodChannel failures (static to survive service restarts)
    private static int consecutiveChannelFailures = 0;
    private static final int MAX_CHANNEL_FAILURES = 3;

    public static void setMethodChannel(MethodChannel channel) {
        Log.d(TAG, "setMethodChannel called - resetting failure counter");
        methodChannel = channel;
        consecutiveChannelFailures = 0;  // CRITICAL: Reset on new channel
    }

    public static void clearMethodChannel() {
        Log.d(TAG, "clearMethodChannel called");
        methodChannel = null;
    }

    public static void start(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "Foreground service start requested");
    }

    /**
     * Start the service from a boot receiver.
     * On Android 15+ (API 35+), BOOT_COMPLETED receivers cannot start foreground services
     * with dataSync type, so we pass a flag to use only connectedDevice type.
     */
    public static void startFromBoot(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("START_FROM_BOOT");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "Foreground service start requested from boot");
    }

    public static void stop(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        context.stopService(intent);
        Log.d(TAG, "Foreground service stop requested");
    }

    /**
     * Enable WebSocket keep-alive from the foreground service.
     * This should be called after WebSocket connects to the station.
     * @param context The application context
     * @param callsign The user's callsign (e.g., "X1ABCD")
     * @param name The station name (optional, can be null)
     * @param url The station URL (e.g., "p2p.radio")
     */
    public static void enableKeepAlive(Context context, String callsign, String name, String url) {
        // Store user and station info for notification
        userCallsign = callsign;
        stationName = name;
        stationUrl = url;

        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("ENABLE_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "WebSocket keep-alive enable requested for " + (callsign != null ? callsign : "user") + " at station: " + (name != null ? name : url));
    }

    /**
     * Enable WebSocket keep-alive (backwards compatible, no station info).
     */
    public static void enableKeepAlive(Context context) {
        enableKeepAlive(context, null, null, null);
    }

    /**
     * Disable WebSocket keep-alive (called when WebSocket disconnects).
     */
    public static void disableKeepAlive(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("DISABLE_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "WebSocket keep-alive disable requested");
    }

    /**
     * Enable BLE advertising keep-alive from the foreground service.
     * This triggers periodic BLE advertising pings even when the screen is off.
     */
    public static void enableBleKeepAlive(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("ENABLE_BLE_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "BLE advertising keep-alive enable requested");
    }

    /**
     * Disable BLE advertising keep-alive.
     */
    public static void disableBleKeepAlive(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("DISABLE_BLE_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "BLE advertising keep-alive disable requested");
    }

    /**
     * Enable BLE scan keep-alive from the foreground service.
     * This triggers periodic BLE scan pings for proximity detection even when the screen is off.
     */
    public static void enableBleScanKeepAlive(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("ENABLE_BLE_SCAN_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "BLE scan keep-alive enable requested");
    }

    /**
     * Disable BLE scan keep-alive.
     */
    public static void disableBleScanKeepAlive(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("DISABLE_BLE_SCAN_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "BLE scan keep-alive disable requested");
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Foreground service created");
        createNotificationChannel();
        acquireWakeLock();

        // Initialize handlers on main looper
        keepAliveHandler = new Handler(Looper.getMainLooper());
        restartHandler = new Handler(Looper.getMainLooper());
        keepAliveRunnable = new Runnable() {
            @Override
            public void run() {
                if (keepAliveEnabled) {
                    sendKeepAlivePing();
                    // Schedule next ping
                    keepAliveHandler.postDelayed(this, KEEPALIVE_INTERVAL_MS);
                }
            }
        };

        // Initialize BLE advertising handler (separate from WebSocket)
        bleAdvertiseHandler = new Handler(Looper.getMainLooper());
        bleAdvertiseRunnable = new Runnable() {
            @Override
            public void run() {
                if (bleAdvertiseEnabled) {
                    sendBleAdvertisePing();
                    // Schedule next ping
                    bleAdvertiseHandler.postDelayed(this, BLE_ADVERTISE_INTERVAL_MS);
                }
            }
        };

        // Initialize BLE scan handler (for proximity detection)
        bleScanHandler = new Handler(Looper.getMainLooper());
        bleScanRunnable = new Runnable() {
            @Override
            public void run() {
                if (bleScanEnabled) {
                    sendBleScanPing();
                    // Schedule next ping
                    bleScanHandler.postDelayed(this, BLE_SCAN_INTERVAL_MS);
                }
            }
        };
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        Log.d(TAG, "Foreground service onStartCommand, action=" + action);

        // Only call startForeground if not already in foreground
        // This prevents crashes when Android 15+ dataSync limit is exhausted
        if (!isInForeground) {
            if (!tryStartForeground(action)) {
                // Failed to start foreground - stop self to avoid crash
                Log.e(TAG, "Failed to start foreground service, stopping");
                stopSelf();
                return START_NOT_STICKY;
            }
            isInForeground = true;
        }

        // Handle boot start: create headless FlutterEngine
        if ("START_FROM_BOOT".equals(action)) {
            Log.d(TAG, "Started from boot - ensuring FlutterEngine exists");
            GeogramApplication app = GeogramApplication.getInstance();
            if (app != null) {
                app.ensureFlutterEngine();
            }
        }

        // Handle actions
        if ("ENABLE_KEEPALIVE".equals(action)) {
            startKeepAlive();
        } else if ("DISABLE_KEEPALIVE".equals(action)) {
            stopKeepAlive();
        } else if ("ENABLE_BLE_KEEPALIVE".equals(action)) {
            startBleAdvertise();
        } else if ("DISABLE_BLE_KEEPALIVE".equals(action)) {
            stopBleAdvertise();
        } else if ("ENABLE_BLE_SCAN_KEEPALIVE".equals(action)) {
            startBleScan();
        } else if ("DISABLE_BLE_SCAN_KEEPALIVE".equals(action)) {
            stopBleScan();
        } else if ("SCHEDULE_RESTART".equals(action)) {
            scheduleAppRestart();
            return START_STICKY;
        } else if ("RESTART_LINK".equals(action)) {
            Log.d(TAG, "Manual restart link requested from notification action");
            startKeepAlive();
            sendKeepAlivePing();
        } else if ("RESTART_WITHOUT_DATASYNC".equals(action)) {
            Log.d(TAG, "Restarted without dataSync type after timeout");

            // Notify Flutter to check connection (may need reconnection)
            notifyServiceRestarted();

            // Re-enable keep-alive if it was previously enabled
            if (stationUrl != null || stationName != null) {
                startKeepAlive();
            }

            // Re-enable BLE advertising if it was previously enabled
            if (bleKeepAliveRequested) {
                startBleAdvertise();
                sendBleAdvertisePing();
            }

            // Re-enable BLE scan if it was previously enabled
            if (bleScanKeepAliveRequested) {
                startBleScan();
                sendBleScanPing();
            }
        }

        // Keep the service running
        return START_STICKY;
    }

    /**
     * Try to start the foreground service with appropriate service types.
     * Handles Android 15+ dataSync time limit exceptions gracefully.
     * @return true if successful, false if failed
     */
    private boolean tryStartForeground(String action) {
        Notification notification = createNotification();

        // Check if this is a boot start - Android 15+ restricts dataSync from BOOT_COMPLETED
        boolean isFromBoot = "START_FROM_BOOT".equals(action);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            int serviceType = determineServiceType(isFromBoot);

            try {
                startForeground(NOTIFICATION_ID, notification, serviceType);
                Log.d(TAG, "Started foreground service with type: " + serviceType);
                return true;
            } catch (Exception e) {
                // Handle Android 15+ ForegroundServiceStartNotAllowedException
                if (Build.VERSION.SDK_INT >= 34 && e instanceof ForegroundServiceStartNotAllowedException) {
                    Log.w(TAG, "ForegroundServiceStartNotAllowedException: " + e.getMessage());
                    dataSyncExhausted = true;

                    // Retry with connectedDevice only if we have Bluetooth permissions
                    if (hasBluetoothPermissions()) {
                        try {
                            int fallbackType = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE;
                            startForeground(NOTIFICATION_ID, notification, fallbackType);
                            Log.d(TAG, "Fallback: started with CONNECTED_DEVICE only");
                            return true;
                        } catch (Exception e2) {
                            Log.e(TAG, "Fallback also failed: " + e2.getMessage());
                            return false;
                        }
                    }
                    return false;
                }
                Log.e(TAG, "Failed to start foreground: " + e.getMessage());
                return false;
            }
        } else {
            try {
                startForeground(NOTIFICATION_ID, notification);
                return true;
            } catch (Exception e) {
                Log.e(TAG, "Failed to start foreground (pre-Q): " + e.getMessage());
                return false;
            }
        }
    }

    /**
     * Determine the appropriate foreground service type based on permissions and restrictions.
     */
    private int determineServiceType(boolean isFromBoot) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0;
        }

        if (hasBluetoothPermissions()) {
            // On Android 15+ from boot or when dataSync is exhausted, only use connectedDevice
            if ((isFromBoot && Build.VERSION.SDK_INT >= 35) || dataSyncExhausted) {
                Log.d(TAG, "Using CONNECTED_DEVICE type only (Android 15+ restriction or dataSync exhausted)");
                return android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE;
            } else {
                // Full service with BLE and network support
                Log.d(TAG, "Using CONNECTED_DEVICE|DATA_SYNC types");
                return android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE |
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC;
            }
        } else {
            // No Bluetooth permissions - on Android 15+ from boot, we can't use dataSync either
            if ((isFromBoot && Build.VERSION.SDK_INT >= 35) || dataSyncExhausted) {
                Log.w(TAG, "No Bluetooth permissions and dataSync restricted - service may fail");
                return 0; // Will likely fail, but let it try
            }
            Log.w(TAG, "Bluetooth permissions not granted, using DATA_SYNC type only");
            return android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC;
        }
    }

    /**
     * Check if any of the Bluetooth permissions required for FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
     * are granted. On Android 12+ (API 31+), we need BLUETOOTH_CONNECT, BLUETOOTH_SCAN, or BLUETOOTH_ADVERTISE.
     * On older versions, the legacy BLUETOOTH permission is sufficient.
     */
    private boolean hasBluetoothPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ requires new Bluetooth permissions
            return ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED ||
                   ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED ||
                   ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED;
        } else {
            // Pre-Android 12 uses legacy BLUETOOTH permission (normal permission, auto-granted)
            return ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED;
        }
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "Foreground service destroyed");
        isInForeground = false;
        stopKeepAlive();
        stopBleAdvertise();
        stopBleScan();
        releaseWakeLock();

        // Self-restart broadcast (Telegram pattern) — BootReceiver will restart the service
        try {
            Intent restartIntent = new Intent("dev.geogram.RESTART");
            restartIntent.setPackage(getPackageName());
            sendBroadcast(restartIntent);
            Log.d(TAG, "Self-restart broadcast sent");
        } catch (Exception e) {
            Log.e(TAG, "Failed to send self-restart broadcast: " + e.getMessage());
        }

        super.onDestroy();
    }

    /**
     * Called on Android 14 (API 34) when a foreground service with a time limit
     * (like dataSync) reaches its timeout.
     */
    @Override
    public void onTimeout(int startId) {
        handleTimeout(startId);
    }

    /**
     * Called on Android 15+ (API 35) with the foreground service type that timed out.
     * This is the preferred overload on API 35+.
     */
    @Override
    public void onTimeout(int startId, int fgsType) {
        Log.w(TAG, "onTimeout(startId=" + startId + ", fgsType=" + fgsType + ")");
        handleTimeout(startId);
    }

    /**
     * Shared timeout handler. Must stop the service very quickly or Android will crash the app.
     */
    private void handleTimeout(int startId) {
        Log.w(TAG, "Foreground service timeout (dataSync limit reached), stopping immediately");
        dataSyncExhausted = true;
        isInForeground = false;

        // Stop keep-alive handlers to prevent any pending callbacks
        if (keepAliveHandler != null) {
            keepAliveHandler.removeCallbacksAndMessages(null);
        }
        if (bleAdvertiseHandler != null) {
            bleAdvertiseHandler.removeCallbacksAndMessages(null);
        }
        if (bleScanHandler != null) {
            bleScanHandler.removeCallbacksAndMessages(null);
        }
        keepAliveEnabled = false;
        bleAdvertiseEnabled = false;
        bleScanEnabled = false;

        // CRITICAL: Stop foreground FIRST, then stopSelf
        // Android 15+ requires very fast response to onTimeout
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }

        // Schedule restart BEFORE calling stopSelf so the handler is still valid
        // Use application context since service is about to be destroyed
        final Context appContext = getApplicationContext();
        final boolean canRestart = hasBluetoothPermissions();

        // Stop the service immediately
        stopSelf(startId);

        // Restart with connectedDevice only (no dataSync) after a brief delay
        if (canRestart) {
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                try {
                    Log.d(TAG, "Restarting service without dataSync type");
                    Intent intent = new Intent(appContext, BLEForegroundService.class);
                    intent.setAction("RESTART_WITHOUT_DATASYNC");
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startForegroundService(intent);
                    } else {
                        appContext.startService(intent);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Failed to restart service: " + e.getMessage());
                }
            }, 500);
        }
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void startKeepAlive() {
        if (!keepAliveEnabled) {
            keepAliveEnabled = true;
            Log.d(TAG, "WebSocket keep-alive started (interval=" + KEEPALIVE_INTERVAL_MS + "ms)");
            // Start the first ping after the interval
            keepAliveHandler.postDelayed(keepAliveRunnable, KEEPALIVE_INTERVAL_MS);
            // Update notification to reflect connected state
            updateNotification();
        }
    }

    private void stopKeepAlive() {
        if (keepAliveEnabled) {
            keepAliveEnabled = false;
            keepAliveHandler.removeCallbacks(keepAliveRunnable);
            Log.d(TAG, "WebSocket keep-alive stopped");
            // Update notification to reflect disconnected state
            updateNotification();
        }
    }

    private void startBleAdvertise() {
        bleKeepAliveRequested = true;
        if (!bleAdvertiseEnabled) {
            bleAdvertiseEnabled = true;
            Log.d(TAG, "BLE advertising keep-alive started (interval=" + BLE_ADVERTISE_INTERVAL_MS + "ms)");
            // Send first ping immediately, then schedule periodic pings
            sendBleAdvertisePing();
            bleAdvertiseHandler.postDelayed(bleAdvertiseRunnable, BLE_ADVERTISE_INTERVAL_MS);
        }
    }

    private void stopBleAdvertise() {
        bleKeepAliveRequested = false;
        if (bleAdvertiseEnabled) {
            bleAdvertiseEnabled = false;
            bleAdvertiseHandler.removeCallbacks(bleAdvertiseRunnable);
            Log.d(TAG, "BLE advertising keep-alive stopped");
        }
    }

    private void startBleScan() {
        bleScanKeepAliveRequested = true;
        if (!bleScanEnabled) {
            bleScanEnabled = true;
            Log.d(TAG, "BLE scan keep-alive started (interval=" + BLE_SCAN_INTERVAL_MS + "ms)");
            // Send first ping immediately, then schedule periodic pings
            sendBleScanPing();
            bleScanHandler.postDelayed(bleScanRunnable, BLE_SCAN_INTERVAL_MS);
        }
    }

    private void stopBleScan() {
        bleScanKeepAliveRequested = false;
        if (bleScanEnabled) {
            bleScanEnabled = false;
            bleScanHandler.removeCallbacks(bleScanRunnable);
            Log.d(TAG, "BLE scan keep-alive stopped");
        }
    }

    /**
     * Send BLE scan ping by invoking the Dart callback via MethodChannel.
     * This triggers the Dart side to perform proximity detection.
     */
    private void sendBleScanPing() {
        if (methodChannel == null) {
            Log.w(TAG, "MethodChannel not set, cannot send BLE scan ping");
            return;
        }

        try {
            Log.d(TAG, "Sending BLE scan ping via MethodChannel");
            methodChannel.invokeMethod("onBleScanPing", null, new io.flutter.plugin.common.MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    Log.d(TAG, "BLE scan ping delivered to Flutter successfully");
                }

                @Override
                public void error(String errorCode, String errorMessage, Object errorDetails) {
                    Log.w(TAG, "BLE scan ping failed: " + errorCode + " - " + errorMessage);
                }

                @Override
                public void notImplemented() {
                    Log.w(TAG, "BLE scan ping not implemented by Flutter side");
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Exception sending BLE scan ping: " + e.getMessage());
        }
    }

    /**
     * Send BLE advertising ping by invoking the Dart callback via MethodChannel.
     * This triggers the Dart side to refresh BLE advertising.
     */
    private void sendBleAdvertisePing() {
        if (methodChannel == null) {
            Log.w(TAG, "MethodChannel not set, cannot send BLE advertising ping");
            return;
        }

        try {
            Log.d(TAG, "Sending BLE advertising ping via MethodChannel");
            methodChannel.invokeMethod("onBleAdvertisePing", null, new io.flutter.plugin.common.MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    Log.d(TAG, "BLE advertising ping delivered to Flutter successfully");
                }

                @Override
                public void error(String errorCode, String errorMessage, Object errorDetails) {
                    Log.w(TAG, "BLE advertising ping failed: " + errorCode + " - " + errorMessage);
                }

                @Override
                public void notImplemented() {
                    Log.w(TAG, "BLE advertising ping not implemented by Flutter side");
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Exception sending BLE advertising ping: " + e.getMessage());
        }
    }

    /**
     * Schedule app restart from the foreground service.
     * Called when a crash is detected and the service is still running.
     * Shows a notification indicating restart is in progress.
     */
    private void scheduleAppRestart() {
        Log.d(TAG, "Scheduling app restart from foreground service");

        // Update notification to show restart in progress
        NotificationManager notificationManager = getSystemService(NotificationManager.class);
        if (notificationManager != null) {
            Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Geogram")
                .setContentText("Recovering from error...")
                .setSmallIcon(R.drawable.ic_notification)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build();
            notificationManager.notify(NOTIFICATION_ID, notification);
        }

        // Mark that we're recovering from a crash
        GeogramApplication app = GeogramApplication.getInstance();
        if (app != null) {
            app.markRecoveredFromCrash();
        }

        // Delay restart to allow crash logging to complete
        restartHandler.postDelayed(() -> {
            try {
                Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                                          Intent.FLAG_ACTIVITY_CLEAR_TASK);
                    startActivity(launchIntent);
                    Log.d(TAG, "App restart initiated");
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to restart app", e);
            }
        }, RESTART_DELAY_MS);
    }

    /**
     * Update the notification to reflect the current keep-alive state.
     */
    private void updateNotification() {
        NotificationManager notificationManager = getSystemService(NotificationManager.class);
        if (notificationManager != null) {
            notificationManager.notify(NOTIFICATION_ID, createNotification());
        }
    }


    /**
     * Send keep-alive ping by invoking the Dart callback via MethodChannel.
     * This runs on the main thread which is required for MethodChannel calls.
     *
     * If the Flutter engine has been destroyed (Activity killed by Android),
     * the MethodChannel call will fail. We track consecutive failures and log
     * warnings to help diagnose connection issues.
     */
    private void sendKeepAlivePing() {
        if (methodChannel == null) {
            Log.d(TAG, "MethodChannel not set, skipping ping (waiting for engine)");
            return;  // Don't increment failures - transient state
        }

        try {
            Log.d(TAG, "Sending WebSocket keep-alive ping via MethodChannel");
            methodChannel.invokeMethod("onKeepAlivePing", null, new io.flutter.plugin.common.MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    consecutiveChannelFailures = 0;
                    Log.d(TAG, "Keep-alive ping delivered to Flutter successfully");
                }

                @Override
                public void error(String errorCode, String errorMessage, Object errorDetails) {
                    consecutiveChannelFailures++;
                    Log.w(TAG, "Keep-alive ping failed: " + errorCode + " - " + errorMessage +
                           " (failures: " + consecutiveChannelFailures + ")");
                    if (consecutiveChannelFailures >= MAX_CHANNEL_FAILURES) {
                        Log.e(TAG, "Flutter engine may be destroyed. WebSocket connection at risk. " +
                              "Consecutive failures: " + consecutiveChannelFailures);
                        scheduleAppRestart();
                    }
                }

                @Override
                public void notImplemented() {
                    consecutiveChannelFailures++;
                    Log.w(TAG, "Keep-alive ping not implemented by Flutter side");
                    if (consecutiveChannelFailures >= MAX_CHANNEL_FAILURES) {
                        scheduleAppRestart();
                    }
                }
            });
        } catch (Exception e) {
            consecutiveChannelFailures++;
            Log.e(TAG, "Exception sending keep-alive ping: " + e.getMessage() +
                   " (failures: " + consecutiveChannelFailures + ")");
            if (consecutiveChannelFailures >= MAX_CHANNEL_FAILURES) {
                Log.e(TAG, "Flutter engine likely destroyed. WebSocket will disconnect. " +
                      "App needs to be brought to foreground to reconnect.");
                scheduleAppRestart();
            }
        }
    }

    /**
     * Notify Flutter that the service has restarted after dataSync timeout.
     * This allows the WebSocket connection to be checked and reconnected if needed.
     */
    private void notifyServiceRestarted() {
        if (methodChannel == null) {
            Log.w(TAG, "MethodChannel not set, cannot notify service restart");
            return;
        }

        try {
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    methodChannel.invokeMethod("onServiceRestarted", null);
                    Log.d(TAG, "Notified Flutter of service restart");
                } catch (Exception e) {
                    Log.e(TAG, "Failed to notify Flutter of restart: " + e.getMessage());
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Exception notifying service restart: " + e.getMessage());
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Normal low-priority channel for ongoing BLE notification
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "Network",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Keeping connections active");
            channel.setShowBadge(false);

            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }

    private Notification createNotification() {
        // Intent to open the app when notification is tapped
        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, flags);

        String contentText;
        if (keepAliveEnabled) {
            // Build station display: prefer URL, then name
            String stationDisplay;
            if (stationUrl != null && !stationUrl.isEmpty()) {
                stationDisplay = stationUrl;
            } else if (stationName != null && !stationName.isEmpty()) {
                stationDisplay = stationName;
            } else {
                stationDisplay = "station";
            }

            // Format: "CALLSIGN is connected to station" or "Connected to station"
            if (userCallsign != null && !userCallsign.isEmpty()) {
                contentText = userCallsign + " is connected to " + stationDisplay;
            } else {
                contentText = "Connected to " + stationDisplay;
            }
        } else {
            contentText = "BLE active";
        }

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Geogram")
                .setContentText(contentText)
                .setSmallIcon(R.drawable.ic_notification)
                .setOngoing(true)
                .setContentIntent(pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .addAction(new NotificationCompat.Action(
                        R.drawable.ic_notification,
                        "Restart link",
                        createRestartPendingIntent()))
                .build();
    }

    private PendingIntent createRestartPendingIntent() {
        Intent restartIntent = new Intent(this, BLEForegroundService.class);
        restartIntent.setAction("RESTART_LINK");
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getService(this, 1, restartIntent, flags);
    }

    private void acquireWakeLock() {
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (powerManager != null) {
            wakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "Geogram::NetworkWakeLock"
            );
            // Acquire indefinitely while service runs (released in onDestroy)
            wakeLock.acquire();
            Log.d(TAG, "Wake lock acquired");
        }
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
            Log.d(TAG, "Wake lock released");
        }
        wakeLock = null;
    }
}
