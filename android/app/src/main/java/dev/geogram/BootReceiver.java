package dev.geogram;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

/**
 * Broadcast receiver that starts the BLE foreground service when the device boots.
 * This ensures Geogram can maintain network connectivity and BLE operations
 * even after a device restart.
 *
 * Listens for:
 * - BOOT_COMPLETED: Standard Android boot completed intent
 * - QUICKBOOT_POWERON: Quick boot/restart on some devices
 * - HTC QUICKBOOT_POWERON: HTC-specific quick boot intent
 *
 * Note: On Android 15+ (API 35+), BOOT_COMPLETED receivers cannot start foreground
 * services with certain types (dataSync, camera, etc.). We pass a flag to the service
 * so it can use only the allowed connectedDevice type when started from boot.
 *
 * The auto-start behavior can be disabled in Settings > Security > Background.
 */
public class BootReceiver extends BroadcastReceiver {

    private static final String TAG = "BootReceiver";
    private static final String PREFS_NAME = "FlutterSharedPreferences";
    private static final String AUTO_START_KEY = "flutter.auto_start_on_boot";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "Received boot intent: " + action);

        if (Intent.ACTION_BOOT_COMPLETED.equals(action) ||
            "android.intent.action.QUICKBOOT_POWERON".equals(action) ||
            "com.htc.intent.action.QUICKBOOT_POWERON".equals(action)) {

            // Check if auto-start is enabled in settings (defaults to true)
            SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
            boolean autoStartEnabled = prefs.getBoolean(AUTO_START_KEY, true);

            if (!autoStartEnabled) {
                Log.i(TAG, "Device boot detected, but auto-start is disabled in settings. Skipping.");
                return;
            }

            Log.i(TAG, "Device boot detected, starting BLE foreground service");

            // Start the foreground service with boot flag for Android 15+ compatibility
            // The service will use only connectedDevice type (not dataSync) when from boot
            BLEForegroundService.startFromBoot(context);

            Log.d(TAG, "BLE foreground service start requested after boot");
        }
    }
}
