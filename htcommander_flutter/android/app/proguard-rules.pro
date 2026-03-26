# Preserve hidden BluetoothDevice.createRfcommSocket(int) used for
# RFCOMM channel probing in BluetoothService and AudioTransportService.
-keep class android.bluetooth.BluetoothDevice {
    android.bluetooth.BluetoothSocket createRfcommSocket(int);
}

# Preserve HTCommander service classes (MethodChannel/EventChannel handlers)
-keep class com.htcommander.htcommander_flutter.BluetoothService { *; }
-keep class com.htcommander.htcommander_flutter.AudioTransportService { *; }
-keep class com.htcommander.htcommander_flutter.AudioService { *; }
-keep class com.htcommander.htcommander_flutter.SpeechService { *; }
-keep class com.htcommander.htcommander_flutter.ConnectionForegroundService { *; }

# Preserve Kotlin coroutines internals
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
