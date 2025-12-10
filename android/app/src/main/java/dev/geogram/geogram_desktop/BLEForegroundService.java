package dev.geogram.geogram_desktop;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

/**
 * Foreground service to keep BLE connections active when app goes to background.
 * Android aggressively kills background BLE operations to save battery.
 * This service keeps the app alive with a persistent notification.
 */
public class BLEForegroundService extends Service {

    private static final String TAG = "BLEForegroundService";
    private static final String CHANNEL_ID = "geogram_ble_channel";
    private static final int NOTIFICATION_ID = 1001;

    private PowerManager.WakeLock wakeLock;

    public static void start(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
        Log.d(TAG, "BLE foreground service start requested");
    }

    public static void stop(Context context) {
        Intent intent = new Intent(context, BLEForegroundService.class);
        context.stopService(intent);
        Log.d(TAG, "BLE foreground service stop requested");
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "BLE foreground service created");
        createNotificationChannel();
        acquireWakeLock();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "BLE foreground service started");

        Notification notification = createNotification();
        startForeground(NOTIFICATION_ID, notification);

        // Keep the service running
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "BLE foreground service destroyed");
        releaseWakeLock();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "BLE",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("BLE active");
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

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Geogram")
                .setContentText("BLE active")
                .setSmallIcon(R.mipmap.ic_launcher)
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
                    "Geogram::BLEWakeLock"
            );
            wakeLock.acquire(60 * 60 * 1000L); // 1 hour max, released when service stops
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
