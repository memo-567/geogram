package dev.geogram.geogram_desktop

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Bluetooth Classic (SPP/RFCOMM) plugin for BLE+ functionality
 *
 * Provides:
 * - SPP server socket for accepting connections from desktop clients
 * - Client connections to other Android devices
 * - Pairing management
 * - Data transfer via RFCOMM
 */
class BluetoothClassicPlugin(
    private val context: Context,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "BluetoothClassic"
        private const val CHANNEL = "geogram/bluetooth_classic"

        // Standard SPP UUID
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")

        // Service name for SDP record
        private const val SERVICE_NAME = "Geogram BLE+"

        // Buffer size for data transfer
        private const val BUFFER_SIZE = 4096
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var serverSocket: BluetoothServerSocket? = null
    private var isServerRunning = false

    // Active connections by MAC address
    private val connections = ConcurrentHashMap<String, ConnectionThread>()

    // Pairing receiver
    private var pairingReceiver: BroadcastReceiver? = null

    /**
     * Initialize the plugin and set up method channel
     */
    fun initialize() {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }

        // Get Bluetooth adapter
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        // Register pairing receiver
        registerPairingReceiver()

        Log.d(TAG, "BluetoothClassicPlugin initialized, adapter available: ${bluetoothAdapter != null}")
    }

    /**
     * Clean up resources
     */
    fun dispose() {
        stopServer()
        disconnectAll()
        unregisterPairingReceiver()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        executor.shutdown()
    }

    /**
     * Handle method calls from Dart
     */
    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                result.success(bluetoothAdapter != null)
            }

            "getLocalMacAddress" -> {
                getLocalMacAddress(result)
            }

            "startServer" -> {
                val uuid = call.argument<String>("uuid")
                val name = call.argument<String>("name") ?: SERVICE_NAME
                startServer(uuid, name, result)
            }

            "stopServer" -> {
                stopServer()
                result.success(true)
            }

            "connect" -> {
                val macAddress = call.argument<String>("macAddress")
                val uuid = call.argument<String>("uuid")
                if (macAddress != null) {
                    connect(macAddress, uuid, result)
                } else {
                    result.error("INVALID_ARGUMENT", "MAC address required", null)
                }
            }

            "disconnect" -> {
                val macAddress = call.argument<String>("macAddress")
                if (macAddress != null) {
                    disconnect(macAddress)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "MAC address required", null)
                }
            }

            "sendData" -> {
                val macAddress = call.argument<String>("macAddress")
                val data = call.argument<ByteArray>("data")
                if (macAddress != null && data != null) {
                    sendData(macAddress, data, result)
                } else {
                    result.error("INVALID_ARGUMENT", "MAC address and data required", null)
                }
            }

            "requestPairing" -> {
                val macAddress = call.argument<String>("macAddress")
                if (macAddress != null) {
                    requestPairing(macAddress, result)
                } else {
                    result.error("INVALID_ARGUMENT", "MAC address required", null)
                }
            }

            "getPairedDevices" -> {
                getPairedDevices(result)
            }

            "isPaired" -> {
                val macAddress = call.argument<String>("macAddress")
                if (macAddress != null) {
                    isPaired(macAddress, result)
                } else {
                    result.error("INVALID_ARGUMENT", "MAC address required", null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Get local Bluetooth MAC address
     */
    private fun getLocalMacAddress(result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        try {
            // Note: On Android 6.0+, this returns 02:00:00:00:00:00 for privacy
            // We need to use reflection or Settings.Secure to get the real MAC
            val adapter = bluetoothAdapter
            if (adapter == null) {
                result.error("UNAVAILABLE", "Bluetooth not available", null)
                return
            }

            // Try to get MAC via reflection (works on some devices)
            try {
                val method = adapter.javaClass.getMethod("getAddress")
                val mac = method.invoke(adapter) as? String
                if (mac != null && mac != "02:00:00:00:00:00") {
                    result.success(mac)
                    return
                }
            } catch (e: Exception) {
                Log.d(TAG, "Reflection method failed: ${e.message}")
            }

            // Try to get from Settings.Secure
            try {
                val mac = android.provider.Settings.Secure.getString(
                    context.contentResolver,
                    "bluetooth_address"
                )
                if (mac != null) {
                    result.success(mac)
                    return
                }
            } catch (e: Exception) {
                Log.d(TAG, "Settings.Secure method failed: ${e.message}")
            }

            // Fallback: Return the adapter's name as identifier (not ideal but works)
            result.success(adapter.name ?: "unknown")
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        }
    }

    /**
     * Start SPP server socket
     */
    private fun startServer(uuid: String?, name: String, result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        if (isServerRunning) {
            result.success(true)
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        executor.execute {
            try {
                val serverUuid = if (uuid != null) UUID.fromString(uuid) else SPP_UUID

                serverSocket = adapter.listenUsingRfcommWithServiceRecord(name, serverUuid)
                isServerRunning = true

                Log.d(TAG, "SPP server started: $name ($serverUuid)")
                mainHandler.post { result.success(true) }

                // Accept loop
                acceptConnections()
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception starting server: ${e.message}")
                mainHandler.post {
                    result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
                }
            } catch (e: IOException) {
                Log.e(TAG, "IOException starting server: ${e.message}")
                mainHandler.post {
                    result.error("IO_ERROR", "Failed to start server: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Accept incoming connections in a loop
     */
    private fun acceptConnections() {
        while (isServerRunning) {
            try {
                val socket = serverSocket?.accept() ?: break
                val device = socket.remoteDevice
                val macAddress = device.address

                Log.d(TAG, "Incoming connection from: $macAddress")

                // Create connection thread
                val connectionThread = ConnectionThread(socket, macAddress)
                connections[macAddress] = connectionThread
                connectionThread.start()

                // Notify Dart
                mainHandler.post {
                    methodChannel?.invokeMethod("onServerClientConnected", mapOf(
                        "macAddress" to macAddress,
                        "callsign" to device.name
                    ))
                }
            } catch (e: IOException) {
                if (isServerRunning) {
                    Log.e(TAG, "Accept failed: ${e.message}")
                }
                break
            }
        }
    }

    /**
     * Stop SPP server
     */
    private fun stopServer() {
        isServerRunning = false
        try {
            serverSocket?.close()
            serverSocket = null
            Log.d(TAG, "SPP server stopped")
        } catch (e: IOException) {
            Log.e(TAG, "Error stopping server: ${e.message}")
        }
    }

    /**
     * Connect to a remote device
     */
    private fun connect(macAddress: String, uuid: String?, result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        // Check if already connected
        if (connections.containsKey(macAddress)) {
            result.success(true)
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        executor.execute {
            try {
                val device = adapter.getRemoteDevice(macAddress)
                val connectUuid = if (uuid != null) UUID.fromString(uuid) else SPP_UUID

                // Cancel discovery before connecting
                adapter.cancelDiscovery()

                val socket = device.createRfcommSocketToServiceRecord(connectUuid)

                notifyConnectionState(macAddress, "connecting", null)

                socket.connect()

                Log.d(TAG, "Connected to: $macAddress")

                // Create connection thread
                val connectionThread = ConnectionThread(socket, macAddress)
                connections[macAddress] = connectionThread
                connectionThread.start()

                notifyConnectionState(macAddress, "connected", device.name)
                mainHandler.post { result.success(true) }
            } catch (e: SecurityException) {
                Log.e(TAG, "Security exception connecting: ${e.message}")
                notifyConnectionState(macAddress, "disconnected", null)
                mainHandler.post {
                    result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
                }
            } catch (e: IOException) {
                Log.e(TAG, "IOException connecting to $macAddress: ${e.message}")
                notifyConnectionState(macAddress, "disconnected", null)
                mainHandler.post {
                    result.error("CONNECTION_FAILED", "Failed to connect: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Disconnect from a device
     */
    private fun disconnect(macAddress: String) {
        connections[macAddress]?.cancel()
        connections.remove(macAddress)
        notifyConnectionState(macAddress, "disconnected", null)
    }

    /**
     * Disconnect all connections
     */
    private fun disconnectAll() {
        connections.forEach { (mac, thread) ->
            thread.cancel()
            notifyConnectionState(mac, "disconnected", null)
        }
        connections.clear()
    }

    /**
     * Send data to a connected device
     */
    private fun sendData(macAddress: String, data: ByteArray, result: MethodChannel.Result) {
        val connection = connections[macAddress]
        if (connection == null) {
            result.error("NOT_CONNECTED", "Not connected to $macAddress", null)
            return
        }

        executor.execute {
            val success = connection.write(data)
            mainHandler.post {
                if (success) {
                    result.success(true)
                } else {
                    result.error("SEND_FAILED", "Failed to send data", null)
                }
            }
        }
    }

    /**
     * Request pairing with a device
     */
    private fun requestPairing(macAddress: String, result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        try {
            val device = adapter.getRemoteDevice(macAddress)

            // Check if already bonded
            if (device.bondState == BluetoothDevice.BOND_BONDED) {
                result.success(true)
                return
            }

            // Request bonding
            val bondResult = device.createBond()
            Log.d(TAG, "Pairing request initiated for $macAddress: $bondResult")

            // Result will be received via BroadcastReceiver
            // For now, return true if createBond() didn't fail immediately
            result.success(bondResult)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        } catch (e: Exception) {
            result.error("PAIRING_FAILED", "Failed to initiate pairing: ${e.message}", null)
        }
    }

    /**
     * Get list of paired devices
     */
    private fun getPairedDevices(result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        try {
            val bondedDevices = adapter.bondedDevices
            val deviceList = bondedDevices.map { device ->
                mapOf(
                    "macAddress" to device.address,
                    "name" to device.name
                )
            }
            result.success(deviceList)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        }
    }

    /**
     * Check if a device is paired
     */
    private fun isPaired(macAddress: String, result: MethodChannel.Result) {
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        try {
            val device = adapter.getRemoteDevice(macAddress)
            result.success(device.bondState == BluetoothDevice.BOND_BONDED)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Bluetooth permission denied", null)
        } catch (e: IllegalArgumentException) {
            result.success(false)
        }
    }

    /**
     * Notify Dart of connection state change
     */
    private fun notifyConnectionState(macAddress: String, state: String, callsign: String?) {
        mainHandler.post {
            methodChannel?.invokeMethod("onConnectionStateChanged", mapOf(
                "macAddress" to macAddress,
                "state" to state,
                "callsign" to callsign
            ))
        }
    }

    /**
     * Notify Dart of received data
     */
    private fun notifyDataReceived(macAddress: String, data: ByteArray) {
        mainHandler.post {
            methodChannel?.invokeMethod("onDataReceived", mapOf(
                "macAddress" to macAddress,
                "data" to data
            ))
        }
    }

    /**
     * Register broadcast receiver for pairing events
     */
    private fun registerPairingReceiver() {
        pairingReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }

                        val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)

                        device?.let {
                            when (bondState) {
                                BluetoothDevice.BOND_BONDED -> {
                                    Log.d(TAG, "Device bonded: ${device.address}")
                                }
                                BluetoothDevice.BOND_NONE -> {
                                    Log.d(TAG, "Device unbonded: ${device.address}")
                                }
                                BluetoothDevice.BOND_BONDING -> {
                                    Log.d(TAG, "Device bonding: ${device.address}")
                                }
                            }
                        }
                    }
                }
            }
        }

        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        context.registerReceiver(pairingReceiver, filter)
    }

    /**
     * Unregister pairing receiver
     */
    private fun unregisterPairingReceiver() {
        pairingReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Receiver not registered
            }
        }
        pairingReceiver = null
    }

    /**
     * Check Bluetooth permissions
     */
    private fun checkBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ requires BLUETOOTH_CONNECT
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Older versions need BLUETOOTH
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Thread for managing a Bluetooth connection
     */
    private inner class ConnectionThread(
        private val socket: BluetoothSocket,
        private val macAddress: String
    ) : Thread() {
        private val inputStream: InputStream? = socket.inputStream
        private val outputStream: OutputStream? = socket.outputStream
        private val buffer = ByteArray(BUFFER_SIZE)

        override fun run() {
            Log.d(TAG, "ConnectionThread started for $macAddress")

            // Read loop
            while (true) {
                try {
                    val bytesRead = inputStream?.read(buffer) ?: -1
                    if (bytesRead == -1) {
                        break
                    }

                    val data = buffer.copyOf(bytesRead)
                    notifyDataReceived(macAddress, data)
                } catch (e: IOException) {
                    Log.d(TAG, "Connection lost for $macAddress: ${e.message}")
                    break
                }
            }

            // Connection ended
            connections.remove(macAddress)
            notifyConnectionState(macAddress, "disconnected", null)
        }

        /**
         * Write data to the socket
         */
        fun write(data: ByteArray): Boolean {
            return try {
                outputStream?.write(data)
                outputStream?.flush()
                true
            } catch (e: IOException) {
                Log.e(TAG, "Write failed for $macAddress: ${e.message}")
                false
            }
        }

        /**
         * Close the connection
         */
        fun cancel() {
            try {
                socket.close()
            } catch (e: IOException) {
                Log.e(TAG, "Error closing socket for $macAddress: ${e.message}")
            }
        }
    }
}
