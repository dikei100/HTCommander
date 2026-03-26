package com.htcommander.htcommander_flutter

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var bluetoothService: BluetoothService
    private lateinit var audioTransportService: AudioTransportService
    private lateinit var audioService: AudioService
    private lateinit var speechService: SpeechService

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Bluetooth command channel
        bluetoothService = BluetoothService(this)
        MethodChannel(messenger, "com.htcommander/bluetooth")
            .setMethodCallHandler(bluetoothService)
        EventChannel(messenger, "com.htcommander/bluetooth_events")
            .setStreamHandler(bluetoothService)

        // Bluetooth audio transport channel
        audioTransportService = AudioTransportService(this)
        MethodChannel(messenger, "com.htcommander/audio_transport")
            .setMethodCallHandler(audioTransportService)
        EventChannel(messenger, "com.htcommander/audio_transport_events")
            .setStreamHandler(audioTransportService)

        // Audio playback/capture
        audioService = AudioService(this)
        MethodChannel(messenger, "com.htcommander/audio")
            .setMethodCallHandler(audioService)
        EventChannel(messenger, "com.htcommander/mic_events")
            .setStreamHandler(audioService)

        // Speech (TTS)
        speechService = SpeechService(this)
        MethodChannel(messenger, "com.htcommander/speech")
            .setMethodCallHandler(speechService)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestRequiredPermissions()
    }

    private fun requestRequiredPermissions() {
        val needed = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ requires these runtime permissions for Bluetooth
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)
                != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.BLUETOOTH_SCAN)
            }
        } else {
            // Android < 12 requires location for BT scanning
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }

        // Microphone for PTT
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }

        // Notification permission for foreground service (API 33+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                needed.toTypedArray(),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return

        val denied = permissions.zip(grantResults.toTypedArray())
            .filter { it.second != PackageManager.PERMISSION_GRANTED }
            .map { it.first }

        if (denied.isNotEmpty()) {
            // Notify Dart side so the UI can show a permissions dialog
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, "com.htcommander/bluetooth")
                    .invokeMethod("permissionsDenied", denied)
            }
        }
    }

    override fun onDestroy() {
        bluetoothService.dispose()
        audioTransportService.dispose()
        audioService.dispose()
        speechService.dispose()
        super.onDestroy()
    }
}
