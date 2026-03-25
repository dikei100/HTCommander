package com.htcommander.htcommander_flutter

import android.annotation.SuppressLint
import android.media.*
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * Handles audio playback (AudioTrack) and microphone capture (AudioRecord).
 *
 * Playback: Receives 16-bit mono PCM at 32kHz from Dart, writes to AudioTrack.
 * Capture: Records at 44100Hz mono, sends PCM chunks to Dart via EventChannel.
 */
class AudioService :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "AudioService"
        private const val PLAYBACK_SAMPLE_RATE = 32000
        private const val CAPTURE_SAMPLE_RATE = 44100
    }

    private var audioTrack: AudioTrack? = null
    private var audioRecord: AudioRecord? = null
    private var captureJob: Job? = null
    @Volatile private var micEventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── MethodChannel handler ───────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startPlayback" -> {
                startPlayback()
                result.success(null)
            }
            "stopPlayback" -> {
                stopPlayback()
                result.success(null)
            }
            "writePcm" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    writePcm(data)
                    result.success(null)
                } else {
                    result.error("INVALID_ARG", "Missing 'data'", null)
                }
            }
            "startCapture" -> {
                startCapture(result)
            }
            "stopCapture" -> {
                stopCapture()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── EventChannel handler (mic data) ─────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        micEventSink = events
    }

    override fun onCancel(arguments: Any?) {
        micEventSink = null
    }

    // ── Playback ────────────────────────────────────────────────────────

    private fun startPlayback() {
        if (audioTrack != null) return

        val bufferSize = AudioTrack.getMinBufferSize(
            PLAYBACK_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(PLAYBACK_SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .build()

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioTrack?.play()
        Log.i(TAG, "AudioTrack started (${PLAYBACK_SAMPLE_RATE}Hz mono)")
    }

    private fun writePcm(data: ByteArray) {
        val track = audioTrack ?: return
        // Write on IO thread to avoid blocking the main thread / causing ANR.
        // AudioTrack.write() can block when the buffer is full.
        scope.launch {
            track.write(data, 0, data.size)
        }
    }

    private fun stopPlayback() {
        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }

    // ── Capture ─────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startCapture(result: MethodChannel.Result) {
        if (audioRecord != null) {
            result.success(null)
            return
        }

        val minBufSize = AudioRecord.getMinBufferSize(
            CAPTURE_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        // Use 2x minimum buffer to prevent audio loss under load
        val bufferSize = minBufSize * 2

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                CAPTURE_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            audioRecord?.startRecording()
            result.success(null)
            Log.i(TAG, "AudioRecord started (${CAPTURE_SAMPLE_RATE}Hz mono, buf=${bufferSize})")

            // Start capture loop
            captureJob = scope.launch {
                val buffer = ByteArray(minBufSize)
                while (isActive) {
                    val rec = audioRecord ?: break
                    val bytesRead = rec.read(buffer, 0, buffer.size)
                    if (bytesRead > 0) {
                        val chunk = buffer.copyOf(bytesRead)
                        withContext(Dispatchers.Main) {
                            micEventSink?.success(chunk)
                        }
                    }
                }
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Microphone permission denied", e.message)
        } catch (e: Exception) {
            result.error("AUDIO_ERROR", "Failed to start capture: ${e.message}", null)
        }
    }

    private fun stopCapture() {
        captureJob?.cancel()
        captureJob = null
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
    }

    fun dispose() {
        stopPlayback()
        stopCapture()
        scope.cancel()
    }
}
