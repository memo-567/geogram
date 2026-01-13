package dev.geogram;

import android.Manifest;
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

    // Restart delay after crash
    private static final long RESTART_DELAY_MS = 3000; // 3 seconds

    private PowerManager.WakeLock wakeLock;
    private Handler restartHandler;
    private Handler keepAliveHandler;
    private Runnable keepAliveRunnable;
    private boolean keepAliveEnabled = false;

    // Station info for notification display
    private static String stationName = null;
    private static String stationUrl = null;

    // Static reference to method channel for callbacks to Flutter
    private static MethodChannel methodChannel;

    public static void setMethodChannel(MethodChannel channel) {
        methodChannel = channel;
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
     * @param name The station name (optional, can be null)
     * @param url The station URL (e.g., "p2p.radio")
     */
    public static void enableKeepAlive(Context context, String name, String url) {
        // Store station info for notification
        stationName = name;
        stationUrl = url;

        Intent intent = new Intent(context, BLEForegroundService.class);
        intent.setAction("ENABLE_KEEPALIVE");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "WebSocket keep-alive enable requested for station: " + (name != null ? name : url));
    }

    /**
     * Enable WebSocket keep-alive (backwards compatible, no station info).
     */
    public static void enableKeepAlive(Context context) {
        enableKeepAlive(context, null, null);
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
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        Log.d(TAG, "Foreground service onStartCommand, action=" + action);

        Notification notification = createNotification();

        // Check if this is a boot start - Android 15+ restricts dataSync from BOOT_COMPLETED
        boolean isFromBoot = "START_FROM_BOOT".equals(action);

        // Use both connectedDevice (for BLE) and dataSync (for WebSocket/network) service types
        // This ensures network operations continue even when the display is off
        // Note: On Android 14+ (API 34+), CONNECTED_DEVICE type requires Bluetooth permissions
        // to be granted at runtime, not just declared in the manifest
        // Note: On Android 15+ (API 35+), dataSync cannot be started from BOOT_COMPLETED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            int serviceType;
            if (hasBluetoothPermissions()) {
                // On Android 15+ from boot, only use connectedDevice (dataSync is restricted)
                if (isFromBoot && Build.VERSION.SDK_INT >= 35) {
                    serviceType = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE;
                    Log.d(TAG, "Starting foreground service from boot with CONNECTED_DEVICE type only (Android 15+ restriction)");
                } else {
                    // Full service with BLE and network support
                    serviceType = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE |
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC;
                    Log.d(TAG, "Starting foreground service with CONNECTED_DEVICE|DATA_SYNC types");
                }
            } else {
                // No Bluetooth permissions - on Android 15+ from boot, we can't start at all
                // since dataSync is also restricted. Log warning and try anyway.
                if (isFromBoot && Build.VERSION.SDK_INT >= 35) {
                    Log.w(TAG, "Boot start on Android 15+ without Bluetooth permissions - service may fail");
                }
                serviceType = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC;
                Log.w(TAG, "Bluetooth permissions not granted, using DATA_SYNC type only");
            }
            startForeground(NOTIFICATION_ID, notification, serviceType);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        // Handle actions
        if ("ENABLE_KEEPALIVE".equals(action)) {
            startKeepAlive();
        } else if ("DISABLE_KEEPALIVE".equals(action)) {
            stopKeepAlive();
        } else if ("SCHEDULE_RESTART".equals(action)) {
            scheduleAppRestart();
            return START_STICKY;
        }

        // Keep the service running
        return START_STICKY;
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
        stopKeepAlive();
        releaseWakeLock();
        super.onDestroy();
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

    // Track consecutive MethodChannel failures
    private int consecutiveChannelFailures = 0;
    private static final int MAX_CHANNEL_FAILURES = 3;

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
            Log.w(TAG, "MethodChannel not set, cannot send keep-alive ping");
            consecutiveChannelFailures++;
            return;
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
                    }
                }

                @Override
                public void notImplemented() {
                    consecutiveChannelFailures++;
                    Log.w(TAG, "Keep-alive ping not implemented by Flutter side");
                }
            });
        } catch (Exception e) {
            consecutiveChannelFailures++;
            Log.e(TAG, "Exception sending keep-alive ping: " + e.getMessage() +
                   " (failures: " + consecutiveChannelFailures + ")");
            if (consecutiveChannelFailures >= MAX_CHANNEL_FAILURES) {
                Log.e(TAG, "Flutter engine likely destroyed. WebSocket will disconnect. " +
                      "App needs to be brought to foreground to reconnect.");
            }
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
            // Format: "Connected to Name (url)" or "Connected to url"
            // Skip parenthetical if name equals url to avoid redundancy like "p2p.radio (p2p.radio)"
            if (stationName != null && !stationName.isEmpty() && stationUrl != null && !stationUrl.isEmpty()) {
                if (stationName.equalsIgnoreCase(stationUrl)) {
                    contentText = "Connected to " + stationName;
                } else {
                    contentText = "Connected to " + stationName + " (" + stationUrl + ")";
                }
            } else if (stationUrl != null && !stationUrl.isEmpty()) {
                contentText = "Connected to " + stationUrl;
            } else if (stationName != null && !stationName.isEmpty()) {
                contentText = "Connected to " + stationName;
            } else {
                contentText = "Connected to station";
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
                .build();
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
