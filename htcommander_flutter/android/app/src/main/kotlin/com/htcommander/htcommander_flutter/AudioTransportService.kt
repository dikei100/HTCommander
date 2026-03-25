package com.htcommander.htcommander_flutter

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
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
 * Manages the audio RFCOMM channel to the radio.
 *
 * The radio uses a separate RFCOMM channel (GenericAudio UUID 00001203)
 * for SBC-encoded bidirectional audio, distinct from the command channel.
 */
class AudioTransportService(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "BT-AudioTransport"
        private const val CONNECT_TIMEOUT_MS = 30_000L
        private val GENERIC_AUDIO_UUID: UUID =
            UUID.fromString("00001203-0000-1000-8000-00805f9b34fb")
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
                    // Wait for command channel to stabilize
                    delay(2000)

                    val device = bt.getRemoteDevice(formattedMac)
                    Log.i(TAG, "Connecting audio channel to $formattedMac...")

                    // Try GenericAudio UUID first
                    var sock = try {
                        val s = device.createRfcommSocketToServiceRecord(GENERIC_AUDIO_UUID)
                        s.connect()
                        Log.i(TAG, "Connected via GenericAudio UUID")
                        s
                    } catch (e: IOException) {
                        Log.d(TAG, "GenericAudio UUID failed: ${e.message}")
                        null
                    }

                    // Fallback: probe channels (skip the command channel)
                    if (sock == null) {
                        Log.i(TAG, "Probing audio channels 1-30...")
                        sock = probeChannels(device)
                    }

                    if (sock == null) {
                        withContext(Dispatchers.Main) {
                            result.error("CONNECT_FAILED",
                                "Could not connect audio RFCOMM channel", null)
                        }
                        return@withTimeout
                    }

                    socket = sock
                    inputStream = sock.inputStream
                    outputStream = sock.outputStream

                    withContext(Dispatchers.Main) {
                        result.success(null)
                    }

                    Log.i(TAG, "Audio channel connected")

                    // Start read loop — sends raw audio bytes to Dart
                    startReadLoop()
                }
            } catch (e: TimeoutCancellationException) {
                Log.e(TAG, "Audio connect timed out")
                closeSocket()
                withContext(Dispatchers.Main) {
                    result.error("CONNECT_TIMEOUT", "Audio connection timed out", null)
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
    private fun probeChannels(device: android.bluetooth.BluetoothDevice): BluetoothSocket? {
        for (channel in 1..30) {
            try {
                val sock = device.javaClass
                    .getMethod("createRfcommSocket", Int::class.java)
                    .invoke(device, channel) as BluetoothSocket
                sock.connect()
                Log.i(TAG, "Audio connected on RFCOMM channel $channel")
                return sock
            } catch (e: Exception) {
                Log.v(TAG, "Audio channel $channel failed: ${e.message}")
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
                        Log.d(TAG, "Audio read error: ${e.message}")
                        -1
                    }
                    if (bytesRead < 0) break

                    val data = buffer.copyOf(bytesRead)
                    withContext(Dispatchers.Main) {
                        // Send raw audio bytes directly (not wrapped in a map)
                        eventSink?.success(data)
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Audio read loop ended: ${e.message}")
            }

            withContext(Dispatchers.Main) {
                eventSink?.success(mapOf("event" to "disconnected"))
            }
            closeSocket()
        }
    }

    // ── Write ───────────────────────────────────────────────────────────

    private fun write(data: ByteArray, result: MethodChannel.Result) {
        val stream = outputStream
        if (stream == null) {
            result.error("NOT_CONNECTED", "No active audio connection", null)
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
}
