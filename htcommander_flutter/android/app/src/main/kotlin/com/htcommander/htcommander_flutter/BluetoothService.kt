package com.htcommander.htcommander_flutter

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/**
 * Manages Bluetooth Classic RFCOMM connections to compatible ham radios.
 *
 * Runs all blocking I/O on Dispatchers.IO coroutines and communicates with
 * Dart via MethodChannel (commands) and EventChannel (events/data).
 *
 * Raw socket bytes are sent to Dart as-is; GAIA frame decoding happens on
 * the Dart side in AndroidRadioBluetooth.
 */
class BluetoothService(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "BT-Service"
        private const val CONNECT_TIMEOUT_MS = 30_000L
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
        private val TARGET_NAMES = listOf(
            "UV-PRO", "UV-50PRO", "GA-5WB",
            "VR-N75", "VR-N76", "VR-N7500", "VR-N7600", "RT-660"
        )
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var inputStream: InputStream? = null
    @Volatile private var outputStream: OutputStream? = null
    private var readJob: Job? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter? by lazy {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        manager?.adapter
    }

    // ── MethodChannel handler ───────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanDevices" -> scanDevices(result)
            "connect" -> {
                val mac = call.argument<String>("mac")
                if (mac == null) {
                    result.error("INVALID_ARG", "Missing 'mac' argument", null)
                } else {
                    connect(mac, result)
                }
            }
            "disconnect" -> {
                disconnect()
                result.success(null)
            }
            "write" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("INVALID_ARG", "Missing 'data' argument", null)
                } else {
                    write(data, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── EventChannel handler ────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ── Scanning ────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun scanDevices(result: MethodChannel.Result) {
        val bt = adapter
        if (bt == null || !bt.isEnabled) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        try {
            val devices = bt.bondedDevices
                .filter { it.name in TARGET_NAMES }
                .map { mapOf("name" to it.name, "mac" to it.address) }
            result.success(devices)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Bluetooth permission denied", e.message)
        }
    }

    // ── Connection ──────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun connect(mac: String, result: MethodChannel.Result) {
        // Guard against double-connect
        if (socket != null) {
            disconnect()
        }

        val bt = adapter
        if (bt == null) {
            result.error("BT_UNAVAILABLE", "Bluetooth not available", null)
            return
        }

        // Format MAC with colons if needed (e.g., AABBCCDDEEFF -> AA:BB:CC:DD:EE:FF)
        val formattedMac = if (mac.contains(":")) mac else {
            if (mac.length != 12) {
                result.error("INVALID_ARG", "Invalid MAC address: $mac", null)
                return
            }
            mac.chunked(2).joinToString(":")
        }

        scope.launch {
            try {
                withTimeout(CONNECT_TIMEOUT_MS) {
                    val device = bt.getRemoteDevice(formattedMac)
                    sendLog("Connecting to $formattedMac...")

                    // Try UUID-based connection first (standard SPP)
                    var sock = tryConnectWithUuid(device)

                    // Fallback: probe RFCOMM channels 1-30 via reflection
                    if (sock == null) {
                        sendLog("SPP UUID failed, probing channels 1-30...")
                        sock = probeChannels(device)
                    }

                    if (sock == null) {
                        withContext(Dispatchers.Main) {
                            result.error("CONNECT_FAILED",
                                "Could not connect to any RFCOMM channel", null)
                        }
                        return@withTimeout
                    }

                    socket = sock
                    inputStream = sock.inputStream
                    outputStream = sock.outputStream

                    sendLog("Connected successfully")

                    withContext(Dispatchers.Main) {
                        result.success(null)
                        sendEvent(mapOf("event" to "connected"))
                    }

                    // Start read loop
                    startReadLoop()
                }
            } catch (e: TimeoutCancellationException) {
                sendLog("Connection timed out after ${CONNECT_TIMEOUT_MS}ms")
                closeSocket()
                withContext(Dispatchers.Main) {
                    result.error("CONNECT_TIMEOUT", "Connection timed out", null)
                }
            } catch (e: SecurityException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION", "Bluetooth permission denied", e.message)
                }
            } catch (e: Exception) {
                closeSocket()
                withContext(Dispatchers.Main) {
                    result.error("CONNECT_FAILED", e.message, null)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun tryConnectWithUuid(device: BluetoothDevice): BluetoothSocket? {
        return try {
            val sock = device.createRfcommSocketToServiceRecord(SPP_UUID)
            sock.connect()
            sendLog("Connected via SPP UUID")
            sock
        } catch (e: IOException) {
            Log.d(TAG, "SPP UUID connection failed: ${e.message}")
            null
        }
    }

    @SuppressLint("MissingPermission")
    private fun probeChannels(device: BluetoothDevice): BluetoothSocket? {
        for (channel in 1..30) {
            try {
                val sock = device.javaClass
                    .getMethod("createRfcommSocket", Int::class.java)
                    .invoke(device, channel) as BluetoothSocket
                sock.connect()
                sendLog("Connected on RFCOMM channel $channel")
                return sock
            } catch (e: Exception) {
                Log.v(TAG, "Channel $channel failed: ${e.message}")
            }
        }
        return null
    }

    // ── Read loop ───────────────────────────────────────────────────────

    private fun startReadLoop() {
        readJob = scope.launch {
            val buffer = ByteArray(4096)
            try {
                while (isActive) {
                    val stream = inputStream ?: break
                    val bytesRead = try {
                        stream.read(buffer)
                    } catch (e: IOException) {
                        Log.d(TAG, "Read error: ${e.message}")
                        -1
                    }
                    if (bytesRead < 0) break

                    val data = buffer.copyOf(bytesRead)
                    withContext(Dispatchers.Main) {
                        sendEvent(mapOf("event" to "data", "payload" to data))
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Read loop ended: ${e.message}")
            }

            // Connection lost
            withContext(Dispatchers.Main) {
                sendEvent(mapOf("event" to "disconnected", "msg" to "Connection lost"))
            }
            closeSocket()
        }
    }

    // ── Write ───────────────────────────────────────────────────────────

    private fun write(data: ByteArray, result: MethodChannel.Result) {
        val stream = outputStream
        if (stream == null) {
            result.error("NOT_CONNECTED", "No active connection", null)
            return
        }

        scope.launch {
            try {
                stream.write(data)
                stream.flush()
                withContext(Dispatchers.Main) { result.success(null) }
            } catch (e: IOException) {
                withContext(Dispatchers.Main) {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }
        }
    }

    // ── Disconnect ──────────────────────────────────────────────────────

    fun disconnect() {
        readJob?.cancel()
        readJob = null
        closeSocket()
    }

    private fun closeSocket() {
        try { inputStream?.close() } catch (_: IOException) {}
        try { outputStream?.close() } catch (_: IOException) {}
        try { socket?.close() } catch (_: IOException) {}
        inputStream = null
        outputStream = null
        socket = null
    }

    fun dispose() {
        disconnect()
        scope.cancel()
    }

    // ── Event helpers ───────────────────────────────────────────────────

    private fun sendEvent(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    private fun sendLog(msg: String) {
        Log.i(TAG, msg)
        scope.launch(Dispatchers.Main) {
            sendEvent(mapOf("event" to "log", "msg" to msg))
        }
    }
}
