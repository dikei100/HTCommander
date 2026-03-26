package com.htcommander.htcommander_flutter

import android.annotation.SuppressLint
import android.content.Context
import android.media.*
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel

/**
 * Handles audio playback (AudioTrack) and microphone capture (AudioRecord).
 *
 * Playback: Receives 16-bit mono PCM at 32kHz from Dart, writes to AudioTrack.
 * Capture: Records at 44100Hz mono, sends PCM chunks to Dart via EventChannel.
 */
class AudioService(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "AudioService"
        private const val PLAYBACK_SAMPLE_RATE = 32000
        private const val CAPTURE_SAMPLE_RATE = 44100
    }

    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var audioRecord: AudioRecord? = null
    private var captureJob: Job? = null
    private var writeJob: Job? = null
    private var pcmQueue = Channel<ByteArray>(capacity = 64)
    @Volatile private var micEventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var audioFocusRequest: AudioFocusRequest? = null

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
        stopCapture()
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

        // Build AudioTrack first, then request focus — avoids focus leak
        // if the AudioTrack constructor throws
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        // Request audio focus so other apps pause/duck
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val focusReq = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attributes)
            .build()
        audioManager.requestAudioFocus(focusReq)
        audioFocusRequest = focusReq

        audioTrack = track
        track.play()

        // Validate that play() actually started
        if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
            Log.e(TAG, "AudioTrack failed to start, state=${track.playState}")
            track.release()
            audioTrack = null
            releaseAudioFocus()
            return
        }

        Log.i(TAG, "AudioTrack started (${PLAYBACK_SAMPLE_RATE}Hz mono)")

        // Single consumer coroutine drains the bounded PCM queue.
        // This replaces per-packet scope.launch to provide backpressure.
        writeJob = scope.launch {
            try {
                for (data in pcmQueue) {
                    val track = audioTrack ?: break
                    var offset = 0
                    while (offset < data.size) {
                        val written = track.write(data, offset, data.size - offset)
                        if (written <= 0) break
                        offset += written
                    }
                }
            } catch (e: Exception) {
                if (e !is CancellationException) {
                    Log.e(TAG, "AudioTrack write error: ${e.message}")
                }
            } finally {
                releaseAudioFocus()
            }
        }
    }

    private fun writePcm(data: ByteArray) {
        val result = pcmQueue.trySend(data)
        if (result.isFailure) {
            Log.w(TAG, "PCM queue full, dropping packet")
        }
    }

    private fun stopPlayback() {
        val job = writeJob
        writeJob = null
        // Close the channel first so the consumer loop exits, then cancel
        // and wait for the job to finish — avoids ClosedSendChannelException
        // while track.write() is in progress
        pcmQueue.close()
        job?.cancel()
        runBlocking { job?.join() }
        pcmQueue = Channel(capacity = 64) // fresh channel for next session

        try {
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null

        releaseAudioFocus()
    }

    private fun releaseAudioFocus() {
        audioFocusRequest?.let {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.abandonAudioFocusRequest(it)
        }
        audioFocusRequest = null
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
        if (minBufSize <= 0) {
            result.error("AUDIO_ERROR", "Failed to get AudioRecord buffer size", null)
            return
        }
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
            if (audioRecord?.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                audioRecord?.release()
                audioRecord = null
                result.error("AUDIO_ERROR", "AudioRecord failed to start recording", null)
                return
            }
            result.success(null)
            Log.i(TAG, "AudioRecord started (${CAPTURE_SAMPLE_RATE}Hz mono, buf=${bufferSize})")

            // Capture the AudioRecord reference once before the loop so
            // stopCapture() nulling audioRecord doesn't race with read()
            val rec = audioRecord!!
            captureJob = scope.launch {
                val buffer = ByteArray(minBufSize)
                while (isActive) {
                    val bytesRead = try {
                        rec.read(buffer, 0, buffer.size)
                    } catch (_: Exception) { -1 }
                    if (bytesRead < 0) {
                        Log.d(TAG, "AudioRecord.read error: $bytesRead")
                        break
                    }
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
        val job = captureJob
        captureJob = null
        job?.cancel()
        // Wait for capture loop to exit before releasing AudioRecord
        // to prevent read() on a released native object
        runBlocking { job?.join() }
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
