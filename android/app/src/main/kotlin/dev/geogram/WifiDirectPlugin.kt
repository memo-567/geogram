package dev.geogram

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pGroup
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi Direct plugin for creating a hotspot (Group Owner mode)
 * Allows other devices to connect directly without a router
 *
 * Key concepts:
 * - Group Owner (GO): The device acting as the access point
 * - P2P Group: A Wi-Fi Direct network with one GO and multiple clients
 * - When we create a group, we become the GO and other devices can connect
 * - On Android 10+, we can set custom SSID like "DIRECT-XX-StationName"
 */
class WifiDirectPlugin(
    private val context: Context,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "WifiDirectPlugin"
        private const val CHANNEL = "dev.geogram/wifi_direct"
    }

    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var methodChannel: MethodChannel? = null
    private var receiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Current group state - always kept in sync via requestGroupInfo
    private var currentGroup: WifiP2pGroup? = null
    private var isP2pEnabled = false

    fun initialize() {
        Log.d(TAG, "Initializing Wi-Fi Direct plugin")

        manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        if (manager == null) {
            Log.e(TAG, "Wi-Fi Direct not supported on this device")
            return
        }

        channel = manager?.initialize(context, Looper.getMainLooper()) {
            // Channel disconnected callback
            Log.w(TAG, "Wi-Fi P2P channel disconnected")
            currentGroup = null
        }

        if (channel == null) {
            Log.e(TAG, "Failed to initialize Wi-Fi Direct channel")
            return
        }

        // Set up method channel for Flutter communication
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableHotspot" -> {
                    val stationName = call.argument<String>("stationName") ?: "Station"
                    enableHotspot(result, stationName)
                }
                "disableHotspot" -> disableHotspot(result)
                "isHotspotEnabled" -> checkHotspotEnabled(result)
                "getHotspotInfo" -> getHotspotInfo(result)
                else -> result.notImplemented()
            }
        }

        // Register broadcast receiver for Wi-Fi P2P events
        registerReceiver()

        // Query initial state
        refreshGroupInfo()

        Log.d(TAG, "Wi-Fi Direct plugin initialized")
    }

    private fun registerReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        isP2pEnabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Log.d(TAG, "Wi-Fi P2P state changed: enabled=$isP2pEnabled")

                        if (!isP2pEnabled) {
                            currentGroup = null
                        }
                        notifyStateChange(isP2pEnabled)
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        // Connection state changed - refresh our group info
                        Log.d(TAG, "Wi-Fi P2P connection changed")
                        refreshGroupInfo()
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, intentFilter)
        }
    }

    /**
     * Refresh our cached group info from the system
     */
    private fun refreshGroupInfo(callback: ((WifiP2pGroup?) -> Unit)? = null) {
        if (manager == null || channel == null) {
            callback?.invoke(null)
            return
        }

        try {
            manager?.requestGroupInfo(channel) { group ->
                currentGroup = group
                if (group != null) {
                    Log.d(TAG, "Current group: SSID=${group.networkName}, isGO=${group.isGroupOwner}, clients=${group.clientList.size}")
                } else {
                    Log.d(TAG, "No active P2P group")
                }
                callback?.invoke(group)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception requesting group info: ${e.message}")
            currentGroup = null
            callback?.invoke(null)
        }
    }

    /**
     * Build the desired SSID for the hotspot
     */
    private fun buildSsid(stationName: String): String {
        return "DIRECT-XX-$stationName"
    }

    /**
     * Enable hotspot - the main entry point
     *
     * Flow:
     * 1. Check if we already have a group where we're the GO with correct name -> return it
     * 2. If there's an existing group with wrong name or we're not GO -> remove it first
     * 3. If no group -> create one with the station name
     */
    private fun enableHotspot(result: MethodChannel.Result, stationName: String) {
        val desiredSsid = buildSsid(stationName)
        Log.d(TAG, "enableHotspot called, desired SSID: $desiredSsid")

        if (manager == null || channel == null) {
            result.error("NOT_SUPPORTED", "Wi-Fi Direct not available", null)
            return
        }

        // First, get the current group state
        refreshGroupInfo { group ->
            when {
                // Case 1: We already have a group, we're the GO, and SSID matches - just return it
                group != null && group.isGroupOwner && group.networkName == desiredSsid -> {
                    Log.d(TAG, "Already Group Owner with correct SSID, returning existing group info")
                    returnGroupInfo(group, result)
                }

                // Case 2: We're GO but SSID is wrong - need to recreate with correct name
                group != null && group.isGroupOwner && group.networkName != desiredSsid -> {
                    Log.d(TAG, "Group Owner but wrong SSID (${group.networkName}), recreating with $desiredSsid")
                    removeGroupThenCreate(result, stationName)
                }

                // Case 3: There's a group but we're not the owner - need to leave first
                group != null && !group.isGroupOwner -> {
                    Log.d(TAG, "Existing group where we're client, removing first")
                    removeGroupThenCreate(result, stationName)
                }

                // Case 4: No group exists - create one
                else -> {
                    Log.d(TAG, "No existing group, creating new one with SSID: $desiredSsid")
                    createNewGroup(result, stationName)
                }
            }
        }
    }

    /**
     * Remove existing group, then create a new one where we're the GO
     */
    private fun removeGroupThenCreate(result: MethodChannel.Result, stationName: String) {
        try {
            manager?.removeGroup(channel!!, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    Log.d(TAG, "Removed existing group, now creating new one")
                    // Small delay to let the framework clean up
                    mainHandler.postDelayed({
                        createNewGroup(result, stationName)
                    }, 500)
                }

                override fun onFailure(reason: Int) {
                    Log.w(TAG, "Failed to remove group: ${getErrorMessage(reason)}, trying to create anyway")
                    // Try to create anyway - the group might have been removed by the other device
                    mainHandler.postDelayed({
                        createNewGroup(result, stationName)
                    }, 500)
                }
            })
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception removing group: ${e.message}")
            // Try to create anyway
            createNewGroup(result, stationName)
        }
    }

    /**
     * Create a new P2P group where we're the Group Owner
     */
    private fun createNewGroup(result: MethodChannel.Result, stationName: String) {
        Log.d(TAG, "Creating new P2P group as Group Owner")

        try {
            // First, stop any ongoing peer discovery to free up the framework
            manager?.stopPeerDiscovery(channel, null)

            // Cancel any pending connect operations
            manager?.cancelConnect(channel, null)

            // Small delay to let cancellations complete
            mainHandler.postDelayed({
                doCreateGroup(result, stationName)
            }, 200)
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception during cleanup: ${e.message}")
            doCreateGroup(result, stationName)
        }
    }

    /**
     * Generate a random passphrase for the hotspot
     */
    private fun generatePassphrase(): String {
        val chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
        return (1..10).map { chars.random() }.joinToString("")
    }

    private fun doCreateGroup(result: MethodChannel.Result, stationName: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ - use custom config with station name in SSID
                val ssid = buildSsid(stationName)
                val passphrase = generatePassphrase()

                Log.d(TAG, "Creating group with custom SSID: $ssid (Android 10+)")

                val config = WifiP2pConfig.Builder()
                    .setNetworkName(ssid)
                    .setPassphrase(passphrase)
                    .build()

                manager?.createGroup(channel!!, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "Group creation initiated successfully with custom SSID")
                        handleGroupCreationSuccess(result)
                    }

                    override fun onFailure(reason: Int) {
                        val errorMsg = getErrorMessage(reason)
                        Log.e(TAG, "Failed to create group with custom config: $errorMsg (reason=$reason)")
                        result.error("CREATE_GROUP_FAILED", errorMsg, null)
                    }
                })
            } else {
                // Android 9 and below - use default (auto-generated name)
                Log.d(TAG, "Creating group with default SSID (Android 9 or below)")

                manager?.createGroup(channel!!, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "Group creation initiated successfully")
                        handleGroupCreationSuccess(result)
                    }

                    override fun onFailure(reason: Int) {
                        val errorMsg = getErrorMessage(reason)
                        Log.e(TAG, "Failed to create group: $errorMsg (reason=$reason)")
                        result.error("CREATE_GROUP_FAILED", errorMsg, null)
                    }
                })
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception creating group: ${e.message}")
            result.error("PERMISSION_DENIED", "Wi-Fi Direct permission denied: ${e.message}", null)
        }
    }

    private fun handleGroupCreationSuccess(result: MethodChannel.Result) {
        // Group info isn't immediately available, wait a bit then query
        mainHandler.postDelayed({
            refreshGroupInfo { group ->
                if (group != null && group.isGroupOwner) {
                    returnGroupInfo(group, result)
                } else {
                    // Sometimes it takes a moment, try once more
                    mainHandler.postDelayed({
                        refreshGroupInfo { retryGroup ->
                            if (retryGroup != null) {
                                returnGroupInfo(retryGroup, result)
                            } else {
                                result.error("CREATE_GROUP_FAILED", "Group created but info not available", null)
                            }
                        }
                    }, 500)
                }
            }
        }, 300)
    }

    /**
     * Return group info to Flutter
     */
    private fun returnGroupInfo(group: WifiP2pGroup, result: MethodChannel.Result) {
        val response = mapOf(
            "ssid" to (group.networkName ?: ""),
            "passphrase" to (group.passphrase ?: ""),
            "clientCount" to group.clientList.size
        )
        Log.d(TAG, "Returning group info: SSID=${group.networkName}")
        result.success(response)
    }

    /**
     * Disable hotspot - remove the P2P group
     */
    private fun disableHotspot(result: MethodChannel.Result) {
        Log.d(TAG, "disableHotspot called")

        if (manager == null || channel == null) {
            currentGroup = null
            result.success(true)
            return
        }

        // Check if we even have a group to remove
        refreshGroupInfo { group ->
            if (group == null) {
                Log.d(TAG, "No group to remove")
                result.success(true)
                return@refreshGroupInfo
            }

            try {
                manager?.removeGroup(channel!!, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        Log.d(TAG, "Group removed successfully")
                        currentGroup = null
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        Log.e(TAG, "Failed to remove group: ${getErrorMessage(reason)}")
                        // Consider it removed anyway - the group might have been removed by disconnect
                        currentGroup = null
                        result.success(true)
                    }
                })
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception removing group: ${e.message}")
                currentGroup = null
                result.success(true)
            }
        }
    }

    /**
     * Check if hotspot is currently enabled (we're a Group Owner)
     */
    private fun checkHotspotEnabled(result: MethodChannel.Result) {
        refreshGroupInfo { group ->
            val enabled = group != null && group.isGroupOwner
            result.success(enabled)
        }
    }

    /**
     * Get current hotspot info
     */
    private fun getHotspotInfo(result: MethodChannel.Result) {
        refreshGroupInfo { group ->
            if (group != null && group.isGroupOwner) {
                result.success(mapOf(
                    "ssid" to (group.networkName ?: ""),
                    "passphrase" to (group.passphrase ?: ""),
                    "clientCount" to group.clientList.size
                ))
            } else {
                result.success(null)
            }
        }
    }

    private fun notifyStateChange(enabled: Boolean) {
        methodChannel?.invokeMethod("onStateChanged", mapOf("enabled" to enabled))
    }

    private fun getErrorMessage(reason: Int): String {
        return when (reason) {
            WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct not supported"
            WifiP2pManager.ERROR -> "Internal error"
            WifiP2pManager.BUSY -> "Framework busy - try again"
            else -> "Unknown error (code=$reason)"
        }
    }

    fun dispose() {
        Log.d(TAG, "Disposing Wi-Fi Direct plugin")

        // Remove group if we're the owner
        if (currentGroup?.isGroupOwner == true) {
            try {
                manager?.removeGroup(channel, null)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing group on dispose: ${e.message}")
            }
        }

        // Unregister receiver
        try {
            receiver?.let { context.unregisterReceiver(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering receiver: ${e.message}")
        }

        receiver = null
        currentGroup = null
    }
}
