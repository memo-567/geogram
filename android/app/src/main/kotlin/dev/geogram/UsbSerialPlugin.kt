package dev.geogram

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * USB Serial Plugin using Android USB Host API (CDC-ACM protocol)
 *
 * This plugin provides USB serial communication for ESP32 devices connected
 * via USB OTG without requiring any external libraries or system installations.
 *
 * Uses built-in Android USB Host API (android.hardware.usb.*) which is part of
 * the Android SDK since API level 12.
 */
class UsbSerialPlugin(
    private val context: Context,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "UsbSerialPlugin"
        private const val CHANNEL = "dev.geogram/usb_serial"
        private const val ACTION_USB_PERMISSION = "dev.geogram.USB_PERMISSION"

        // CDC-ACM class constants
        private const val CDC_ACM_CLASS = 0x02
        private const val CDC_DATA_CLASS = 0x0A

        // CDC-ACM control requests (USB specification)
        private const val SET_LINE_CODING = 0x20
        private const val GET_LINE_CODING = 0x21
        private const val SET_CONTROL_LINE_STATE = 0x22

        // Control line state bits
        private const val DTR_BIT = 0x01
        private const val RTS_BIT = 0x02

        // Known ESP32 USB identifiers
        val ESP32_IDENTIFIERS = listOf(
            Pair(0x303A, 0x1001), // Espressif native USB (ESP32-C3/S2/S3)
            Pair(0x303A, 0x0002), // Espressif USB Bridge
            Pair(0x10C4, 0xEA60), // CP210x USB-UART
            Pair(0x1A86, 0x7523), // CH340 USB-UART
            Pair(0x1A86, 0x55D4), // CH9102 USB-UART
            Pair(0x0403, 0x6001), // FTDI FT232
            Pair(0x0403, 0x6015), // FTDI FT231X
        )

        // Timeout values
        private const val USB_TIMEOUT_MS = 1000
        private const val READ_BUFFER_SIZE = 4096
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()

    private var usbManager: UsbManager? = null
    private val openConnections = ConcurrentHashMap<String, UsbSerialConnection>()
    private var permissionReceiver: BroadcastReceiver? = null
    private var pendingPermissionResults = ConcurrentHashMap<String, MethodChannel.Result>()

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

        usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager

        registerPermissionReceiver()

        Log.d(TAG, "UsbSerialPlugin initialized, USB manager available: ${usbManager != null}")
    }

    /**
     * Clean up resources
     */
    fun dispose() {
        closeAll()
        unregisterPermissionReceiver()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        executor.shutdown()
    }

    /**
     * Handle method calls from Dart
     */
    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listDevices" -> listDevices(result)

            "requestPermission" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName != null) {
                    requestPermission(deviceName, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "hasPermission" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName != null) {
                    hasPermission(deviceName, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "open" -> {
                val deviceName = call.argument<String>("deviceName")
                val baudRate = call.argument<Int>("baudRate") ?: 115200
                if (deviceName != null) {
                    openDevice(deviceName, baudRate, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "close" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName != null) {
                    closeDevice(deviceName)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "read" -> {
                val deviceName = call.argument<String>("deviceName")
                val maxBytes = call.argument<Int>("maxBytes") ?: READ_BUFFER_SIZE
                val timeoutMs = call.argument<Int>("timeoutMs") ?: USB_TIMEOUT_MS
                if (deviceName != null) {
                    readData(deviceName, maxBytes, timeoutMs, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "write" -> {
                val deviceName = call.argument<String>("deviceName")
                val data = call.argument<ByteArray>("data")
                if (deviceName != null && data != null) {
                    writeData(deviceName, data, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name and data required", null)
                }
            }

            "setDTR" -> {
                val deviceName = call.argument<String>("deviceName")
                val value = call.argument<Boolean>("value") ?: false
                if (deviceName != null) {
                    setDTR(deviceName, value, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "setRTS" -> {
                val deviceName = call.argument<String>("deviceName")
                val value = call.argument<Boolean>("value") ?: false
                if (deviceName != null) {
                    setRTS(deviceName, value, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "setBaudRate" -> {
                val deviceName = call.argument<String>("deviceName")
                val baudRate = call.argument<Int>("baudRate") ?: 115200
                if (deviceName != null) {
                    setBaudRate(deviceName, baudRate, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            "flush" -> {
                val deviceName = call.argument<String>("deviceName")
                if (deviceName != null) {
                    flush(deviceName, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Device name required", null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * List all USB serial devices
     */
    private fun listDevices(result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.error("UNAVAILABLE", "USB manager not available", null)
            return
        }

        val devices = mutableListOf<Map<String, Any?>>()

        for ((_, device) in manager.deviceList) {
            // Check if it's a known ESP32 device or a CDC-ACM device
            val isEsp32 = ESP32_IDENTIFIERS.any { (vid, pid) ->
                device.vendorId == vid && device.productId == pid
            }

            val isCdcAcm = isCdcAcmDevice(device)

            if (isEsp32 || isCdcAcm) {
                devices.add(mapOf(
                    "deviceName" to device.deviceName,
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "manufacturerName" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) device.manufacturerName else null),
                    "productName" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) device.productName else null),
                    "serialNumber" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        try { device.serialNumber } catch (e: SecurityException) { null }
                    } else null),
                    "deviceClass" to device.deviceClass,
                    "deviceSubclass" to device.deviceSubclass,
                    "interfaceCount" to device.interfaceCount,
                    "isEsp32" to isEsp32,
                    "hasPermission" to manager.hasPermission(device)
                ))
            }
        }

        Log.d(TAG, "Found ${devices.size} USB serial devices")
        result.success(devices)
    }

    /**
     * Check if a device is CDC-ACM class
     */
    private fun isCdcAcmDevice(device: UsbDevice): Boolean {
        // Check device class
        if (device.deviceClass == CDC_ACM_CLASS) return true

        // Check interface classes
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == CDC_ACM_CLASS || iface.interfaceClass == CDC_DATA_CLASS) {
                return true
            }
        }

        return false
    }

    /**
     * Check if we have permission for a device
     */
    private fun hasPermission(deviceName: String, result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.error("UNAVAILABLE", "USB manager not available", null)
            return
        }

        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.success(false)
            return
        }

        result.success(manager.hasPermission(device))
    }

    /**
     * Request permission for a USB device
     */
    private fun requestPermission(deviceName: String, result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.error("UNAVAILABLE", "USB manager not available", null)
            return
        }

        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("NOT_FOUND", "Device not found: $deviceName", null)
            return
        }

        if (manager.hasPermission(device)) {
            result.success(true)
            return
        }

        // Store pending result
        pendingPermissionResults[deviceName] = result

        // Request permission
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION).apply {
                putExtra(UsbManager.EXTRA_DEVICE, device)
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        manager.requestPermission(device, permissionIntent)
        Log.d(TAG, "Permission requested for device: $deviceName")
    }

    /**
     * Open a USB serial device
     */
    private fun openDevice(deviceName: String, baudRate: Int, result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.error("UNAVAILABLE", "USB manager not available", null)
            return
        }

        if (openConnections.containsKey(deviceName)) {
            result.success(true)
            return
        }

        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("NOT_FOUND", "Device not found: $deviceName", null)
            return
        }

        if (!manager.hasPermission(device)) {
            result.error("PERMISSION_DENIED", "No permission for device: $deviceName", null)
            return
        }

        executor.execute {
            try {
                val connection = manager.openDevice(device)
                if (connection == null) {
                    mainHandler.post {
                        result.error("OPEN_FAILED", "Failed to open device connection", null)
                    }
                    return@execute
                }

                // Find CDC-ACM interfaces and endpoints
                val cdcConnection = findCdcAcmEndpoints(device, connection)
                if (cdcConnection == null) {
                    connection.close()
                    mainHandler.post {
                        result.error("NOT_SUPPORTED", "Device doesn't support CDC-ACM", null)
                    }
                    return@execute
                }

                // Configure serial parameters
                if (!setLineCoding(cdcConnection, baudRate, 8, 0, 0)) {
                    Log.w(TAG, "Failed to set line coding, continuing anyway")
                }

                // Enable DTR and RTS (required for ESP32 bootloader)
                if (!setControlLineState(cdcConnection, dtr = true, rts = true)) {
                    Log.w(TAG, "Failed to set control line state, continuing anyway")
                }

                openConnections[deviceName] = cdcConnection
                Log.d(TAG, "Device opened: $deviceName at $baudRate baud")

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "Error opening device: ${e.message}")
                mainHandler.post {
                    result.error("OPEN_FAILED", "Failed to open device: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Find CDC-ACM control and data interfaces/endpoints
     */
    private fun findCdcAcmEndpoints(device: UsbDevice, connection: UsbDeviceConnection): UsbSerialConnection? {
        var controlInterface: UsbInterface? = null
        var dataInterface: UsbInterface? = null
        var readEndpoint: UsbEndpoint? = null
        var writeEndpoint: UsbEndpoint? = null

        // Find interfaces
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)

            when (iface.interfaceClass) {
                CDC_ACM_CLASS -> {
                    // CDC Control interface (for baud rate, DTR/RTS)
                    controlInterface = iface
                }
                CDC_DATA_CLASS -> {
                    // CDC Data interface (for read/write)
                    dataInterface = iface
                }
                UsbConstants.USB_CLASS_VENDOR_SPEC -> {
                    // Some devices use vendor-specific class but still work as CDC
                    if (dataInterface == null) {
                        dataInterface = iface
                    }
                }
            }
        }

        // If no data interface found, try to use any interface with bulk endpoints
        if (dataInterface == null) {
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                for (j in 0 until iface.endpointCount) {
                    val ep = iface.getEndpoint(j)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                        dataInterface = iface
                        break
                    }
                }
                if (dataInterface != null) break
            }
        }

        // Use data interface as control if no dedicated control interface
        if (controlInterface == null) {
            controlInterface = dataInterface
        }

        if (dataInterface == null) {
            Log.e(TAG, "No data interface found")
            return null
        }

        // Find bulk endpoints
        for (i in 0 until dataInterface.endpointCount) {
            val ep = dataInterface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) {
                    readEndpoint = ep
                } else {
                    writeEndpoint = ep
                }
            }
        }

        if (readEndpoint == null || writeEndpoint == null) {
            Log.e(TAG, "Missing bulk endpoints: read=$readEndpoint, write=$writeEndpoint")
            return null
        }

        // Claim interfaces
        if (!connection.claimInterface(dataInterface, true)) {
            Log.e(TAG, "Failed to claim data interface")
            return null
        }

        if (controlInterface != null && controlInterface != dataInterface) {
            if (!connection.claimInterface(controlInterface, true)) {
                Log.w(TAG, "Failed to claim control interface")
            }
        }

        Log.d(TAG, "Found CDC-ACM endpoints: read=${readEndpoint.address}, write=${writeEndpoint.address}")

        return UsbSerialConnection(
            connection = connection,
            controlInterface = controlInterface,
            dataInterface = dataInterface,
            readEndpoint = readEndpoint,
            writeEndpoint = writeEndpoint
        )
    }

    /**
     * Set line coding (baud rate, data bits, parity, stop bits)
     */
    private fun setLineCoding(
        conn: UsbSerialConnection,
        baudRate: Int,
        dataBits: Int = 8,
        stopBits: Int = 0,  // 0 = 1 stop bit
        parity: Int = 0     // 0 = none
    ): Boolean {
        // Line coding structure: 7 bytes
        // bytes 0-3: baud rate (little endian)
        // byte 4: stop bits (0=1, 1=1.5, 2=2)
        // byte 5: parity (0=none, 1=odd, 2=even)
        // byte 6: data bits
        val lineCoding = ByteArray(7)
        lineCoding[0] = (baudRate and 0xFF).toByte()
        lineCoding[1] = ((baudRate shr 8) and 0xFF).toByte()
        lineCoding[2] = ((baudRate shr 16) and 0xFF).toByte()
        lineCoding[3] = ((baudRate shr 24) and 0xFF).toByte()
        lineCoding[4] = stopBits.toByte()
        lineCoding[5] = parity.toByte()
        lineCoding[6] = dataBits.toByte()

        val result = conn.connection.controlTransfer(
            0x21,  // bmRequestType: Host to device, class request, interface recipient
            SET_LINE_CODING,
            0,
            conn.controlInterface?.id ?: 0,
            lineCoding,
            lineCoding.size,
            USB_TIMEOUT_MS
        )

        if (result < 0) {
            Log.w(TAG, "SET_LINE_CODING failed: $result")
            return false
        }

        conn.baudRate = baudRate
        return true
    }

    /**
     * Set DTR and RTS control signals
     */
    private fun setControlLineState(conn: UsbSerialConnection, dtr: Boolean, rts: Boolean): Boolean {
        val value = (if (dtr) DTR_BIT else 0) or (if (rts) RTS_BIT else 0)

        val result = conn.connection.controlTransfer(
            0x21,  // bmRequestType: Host to device, class request, interface recipient
            SET_CONTROL_LINE_STATE,
            value,
            conn.controlInterface?.id ?: 0,
            null,
            0,
            USB_TIMEOUT_MS
        )

        if (result < 0) {
            Log.w(TAG, "SET_CONTROL_LINE_STATE failed: $result")
            return false
        }

        conn.dtr = dtr
        conn.rts = rts
        return true
    }

    /**
     * Close a device
     */
    private fun closeDevice(deviceName: String) {
        val conn = openConnections.remove(deviceName)
        if (conn != null) {
            try {
                conn.connection.releaseInterface(conn.dataInterface)
                if (conn.controlInterface != null && conn.controlInterface != conn.dataInterface) {
                    conn.connection.releaseInterface(conn.controlInterface)
                }
                conn.connection.close()
                Log.d(TAG, "Device closed: $deviceName")
            } catch (e: Exception) {
                Log.e(TAG, "Error closing device: ${e.message}")
            }
        }
    }

    /**
     * Close all open connections
     */
    private fun closeAll() {
        for (deviceName in openConnections.keys.toList()) {
            closeDevice(deviceName)
        }
    }

    /**
     * Read data from device
     */
    private fun readData(deviceName: String, maxBytes: Int, timeoutMs: Int, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        executor.execute {
            try {
                val buffer = ByteArray(minOf(maxBytes, READ_BUFFER_SIZE))
                val bytesRead = conn.connection.bulkTransfer(
                    conn.readEndpoint,
                    buffer,
                    buffer.size,
                    timeoutMs
                )

                if (bytesRead > 0) {
                    mainHandler.post { result.success(buffer.copyOf(bytesRead)) }
                } else if (bytesRead == 0) {
                    mainHandler.post { result.success(ByteArray(0)) }
                } else {
                    // Negative return usually means timeout, return empty
                    mainHandler.post { result.success(ByteArray(0)) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Read error: ${e.message}")
                mainHandler.post {
                    result.error("READ_ERROR", "Failed to read: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Write data to device
     */
    private fun writeData(deviceName: String, data: ByteArray, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        executor.execute {
            try {
                var totalWritten = 0
                var offset = 0
                val maxPacketSize = conn.writeEndpoint.maxPacketSize

                while (offset < data.size) {
                    val chunkSize = minOf(maxPacketSize, data.size - offset)
                    val chunk = data.copyOfRange(offset, offset + chunkSize)

                    val bytesWritten = conn.connection.bulkTransfer(
                        conn.writeEndpoint,
                        chunk,
                        chunk.size,
                        USB_TIMEOUT_MS
                    )

                    if (bytesWritten < 0) {
                        Log.e(TAG, "Write error at offset $offset: $bytesWritten")
                        break
                    }

                    totalWritten += bytesWritten
                    offset += bytesWritten
                }

                mainHandler.post { result.success(totalWritten) }
            } catch (e: Exception) {
                Log.e(TAG, "Write error: ${e.message}")
                mainHandler.post {
                    result.error("WRITE_ERROR", "Failed to write: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Set DTR signal
     */
    private fun setDTR(deviceName: String, value: Boolean, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        val success = setControlLineState(conn, dtr = value, rts = conn.rts)
        result.success(success)
    }

    /**
     * Set RTS signal
     */
    private fun setRTS(deviceName: String, value: Boolean, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        val success = setControlLineState(conn, dtr = conn.dtr, rts = value)
        result.success(success)
    }

    /**
     * Set baud rate
     */
    private fun setBaudRate(deviceName: String, baudRate: Int, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        val success = setLineCoding(conn, baudRate)
        result.success(success)
    }

    /**
     * Flush buffers (not directly supported by USB, just clears any pending reads)
     */
    private fun flush(deviceName: String, result: MethodChannel.Result) {
        val conn = openConnections[deviceName]
        if (conn == null) {
            result.error("NOT_OPEN", "Device not open: $deviceName", null)
            return
        }

        // USB doesn't have explicit flush, but we can do a quick read to clear buffer
        executor.execute {
            try {
                val buffer = ByteArray(READ_BUFFER_SIZE)
                // Non-blocking read with short timeout to clear any pending data
                conn.connection.bulkTransfer(conn.readEndpoint, buffer, buffer.size, 50)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.success(true) }
            }
        }
    }

    /**
     * Register broadcast receiver for USB permission results
     */
    private fun registerPermissionReceiver() {
        permissionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != ACTION_USB_PERMISSION) return

                synchronized(this) {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }

                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val deviceName = device?.deviceName

                    Log.d(TAG, "Permission result for $deviceName: $granted")

                    if (deviceName != null) {
                        val pendingResult = pendingPermissionResults.remove(deviceName)
                        mainHandler.post {
                            pendingResult?.success(granted)
                        }

                        // Notify Dart of permission change
                        mainHandler.post {
                            methodChannel?.invokeMethod("onPermissionChanged", mapOf(
                                "deviceName" to deviceName,
                                "granted" to granted
                            ))
                        }
                    }
                }
            }
        }

        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(permissionReceiver, filter)
        }
    }

    /**
     * Unregister permission receiver
     */
    private fun unregisterPermissionReceiver() {
        permissionReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Receiver not registered
            }
        }
        permissionReceiver = null
    }

    /**
     * Data class for holding USB serial connection info
     */
    private data class UsbSerialConnection(
        val connection: UsbDeviceConnection,
        val controlInterface: UsbInterface?,
        val dataInterface: UsbInterface,
        val readEndpoint: UsbEndpoint,
        val writeEndpoint: UsbEndpoint,
        var baudRate: Int = 115200,
        var dtr: Boolean = true,
        var rts: Boolean = true
    )
}
