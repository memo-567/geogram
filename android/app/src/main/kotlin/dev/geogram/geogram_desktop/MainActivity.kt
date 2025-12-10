package dev.geogram.geogram_desktop

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dev.geogram/updates"
    private val ARGS_CHANNEL = "dev.geogram/args"
    private val BLE_CHANNEL = "dev.geogram/ble_service"
    private var bluetoothClassicPlugin: BluetoothClassicPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Bluetooth Classic plugin for BLE+ functionality
        bluetoothClassicPlugin = BluetoothClassicPlugin(this, flutterEngine)
        bluetoothClassicPlugin?.initialize()

        // BLE foreground service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBLEService" -> {
                    BLEForegroundService.start(this)
                    result.success(true)
                }
                "stopBLEService" -> {
                    BLEForegroundService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Args channel for getting intent extras (test mode support)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ARGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIntentExtras" -> {
                    val extras = mutableMapOf<String, Any?>()
                    intent?.extras?.let { bundle ->
                        extras["test_mode"] = bundle.getBoolean("test_mode", false)
                        extras["debug_api"] = bundle.getBoolean("debug_api", false)
                        extras["http_api"] = bundle.getBoolean("http_api", false)
                        extras["skip_intro"] = bundle.getBoolean("skip_intro", false)
                        extras["new_identity"] = bundle.getBoolean("new_identity", false)
                    }
                    android.util.Log.d("GeogramArgs", "Intent extras: $extras")
                    result.success(extras)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val success = installApk(filePath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }
                "canInstallPackages" -> {
                    result.success(canInstallPackages())
                }
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(true)
                }
                "getCurrentApkPath" -> {
                    val apkPath = applicationContext.applicationInfo.sourceDir
                    android.util.Log.d("GeogramUpdate", "Current APK path: $apkPath")
                    result.success(apkPath)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Check if the app has permission to install packages (Android 8.0+)
     */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true // Pre-Oreo doesn't need this permission
        }
    }

    /**
     * Open the system settings to allow installing unknown apps
     */
    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            intent.data = Uri.parse("package:$packageName")
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
        }
    }

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            android.util.Log.d("GeogramUpdate", "Attempting to install APK: $filePath")
            android.util.Log.d("GeogramUpdate", "File exists: ${file.exists()}, size: ${file.length()} bytes")

            if (!file.exists()) {
                android.util.Log.e("GeogramUpdate", "APK file does not exist: $filePath")
                return false
            }

            if (file.length() < 1000) {
                android.util.Log.e("GeogramUpdate", "APK file too small (${file.length()} bytes), likely corrupted")
                return false
            }

            // Check permission first on Android 8.0+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    android.util.Log.w("GeogramUpdate", "Install permission not granted, opening settings")
                    openInstallPermissionSettings()
                    return false
                }
            }

            val intent = Intent(Intent.ACTION_VIEW)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7.0+ requires FileProvider
                android.util.Log.d("GeogramUpdate", "Using FileProvider for Android 7.0+")
                val authority = "${applicationContext.packageName}.fileprovider"
                android.util.Log.d("GeogramUpdate", "FileProvider authority: $authority")

                val uri = FileProvider.getUriForFile(this, authority, file)
                android.util.Log.d("GeogramUpdate", "FileProvider URI: $uri")

                intent.setDataAndType(uri, "application/vnd.android.package-archive")
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                // Older Android versions can use file:// URI
                android.util.Log.d("GeogramUpdate", "Using file:// URI for older Android")
                intent.setDataAndType(
                    android.net.Uri.fromFile(file),
                    "application/vnd.android.package-archive"
                )
            }

            android.util.Log.d("GeogramUpdate", "Starting APK installer intent")
            startActivity(intent)
            android.util.Log.d("GeogramUpdate", "APK installer started successfully")
            true
        } catch (e: IllegalArgumentException) {
            // FileProvider couldn't find the file path in its configuration
            android.util.Log.e("GeogramUpdate", "FileProvider error - path not configured: ${e.message}")
            e.printStackTrace()
            false
        } catch (e: Exception) {
            android.util.Log.e("GeogramUpdate", "Error installing APK: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    override fun onDestroy() {
        bluetoothClassicPlugin?.dispose()
        bluetoothClassicPlugin = null
        super.onDestroy()
    }
}
