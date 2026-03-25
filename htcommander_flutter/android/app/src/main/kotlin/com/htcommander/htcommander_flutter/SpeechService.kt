package com.htcommander.htcommander_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android TTS service using the platform TextToSpeech API.
 * Bridges to Dart via MethodChannel for voice listing, selection, and synthesis.
 */
class SpeechService(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SpeechService"
    }

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                Log.i(TAG, "TTS initialized")
            } else {
                Log.e(TAG, "TTS initialization failed")
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(ttsReady)
            "getVoices" -> getVoices(result)
            "selectVoice" -> {
                val voice = call.argument<String>("voice")
                if (voice != null) selectVoice(voice, result)
                else result.error("INVALID_ARG", "Missing 'voice'", null)
            }
            "synthesizeToWav" -> {
                val text = call.argument<String>("text")
                val sampleRate = call.argument<Int>("sampleRate") ?: 32000
                if (text != null) synthesizeToWav(text, sampleRate, result)
                else result.error("INVALID_ARG", "Missing 'text'", null)
            }
            else -> result.notImplemented()
        }
    }

    private fun getVoices(result: MethodChannel.Result) {
        if (!ttsReady) {
            result.success(emptyList<String>())
            return
        }
        try {
            val voices = tts?.voices?.map { it.name } ?: emptyList()
            result.success(voices)
        } catch (e: Exception) {
            result.success(emptyList<String>())
        }
    }

    private fun selectVoice(voiceName: String, result: MethodChannel.Result) {
        if (!ttsReady) {
            result.success(null)
            return
        }
        try {
            val voice = tts?.voices?.find { it.name == voiceName }
            if (voice != null) {
                tts?.voice = voice
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("TTS_ERROR", e.message, null)
        }
    }

    private fun synthesizeToWav(text: String, sampleRate: Int, result: MethodChannel.Result) {
        if (!ttsReady) {
            result.success(null)
            return
        }

        try {
            val tempFile = File.createTempFile("tts_", ".wav", context.cacheDir)
            val utteranceId = "htcommander_${System.currentTimeMillis()}"

            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onError(id: String?) {
                    if (id == utteranceId) {
                        // UtteranceProgressListener runs on TTS thread —
                        // MethodChannel.Result must be called on main thread
                        mainHandler.post {
                            result.error("TTS_ERROR", "Synthesis failed", null)
                        }
                        tempFile.delete()
                    }
                }
                override fun onDone(id: String?) {
                    if (id == utteranceId) {
                        mainHandler.post {
                            try {
                                val bytes = tempFile.readBytes()
                                result.success(bytes)
                            } catch (e: Exception) {
                                result.error("TTS_ERROR", e.message, null)
                            } finally {
                                tempFile.delete()
                            }
                        }
                    }
                }
            })

            tts?.synthesizeToFile(text, null, tempFile, utteranceId)
        } catch (e: Exception) {
            result.error("TTS_ERROR", e.message, null)
        }
    }

    fun dispose() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }
}
