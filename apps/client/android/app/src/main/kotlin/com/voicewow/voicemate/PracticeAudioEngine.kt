package com.voicewow.voicemate

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal object NativePracticeAudio {
    init { System.loadLibrary("voicemate_audio") }
    external fun create(noiseReductionEnabled: Boolean, voiceActivityEnabled: Boolean): Long
    external fun process(handle: Long, pcm: ShortArray): FloatArray
    external fun destroy(handle: Long)
}

/** Processing only: the record plugin owns microphone permissions and capture. */
class PracticeAudioEngine(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<Long, Session>()
    @Volatile private var closed = false
    private class Session(val handle: Long, noiseReductionEnabled: Boolean, voiceActivityEnabled: Boolean) {
        val processor = PracticeAudioProcessor(noiseReductionEnabled, voiceActivityEnabled) { NativePracticeAudio.process(handle, it) }
        var nextSequence = 0
    }

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val value = arguments?.get("session")
        val id = if (value is Int || value is Long) (value as Number).toLong() else null
        if (closed || id == null || id < 1) {
            result.error("invalid_request", "음성 처리를 다시 시작해야 한다.", null)
            return
        }
        worker.execute {
            try {
                check(!closed)
                val response: Any? = when (call.method) {
                    "create" -> {
                        require(!sessions.containsKey(id))
                        val noiseReductionEnabled = arguments?.get("noiseReductionEnabled") ?: true
                        val voiceActivityEnabled = arguments?.get("voiceActivityEnabled") ?: true
                        require(noiseReductionEnabled is Boolean)
                        require(voiceActivityEnabled is Boolean)
                        val handle = NativePracticeAudio.create(noiseReductionEnabled, voiceActivityEnabled)
                        check(handle != 0L)
                        sessions[id] = Session(handle, noiseReductionEnabled, voiceActivityEnabled)
                        mapOf("inputSampleRate" to 48000, "sampleRate" to 16000)
                    }
                    "process" -> {
                        val session = sessions[id] ?: error("Unknown processing session")
                        val bytes = arguments?.get("pcm") as? ByteArray ?: error("PCM16 bytes required")
                        require(bytes.size <= 48000)
                        require(arguments["sequence"] == session.nextSequence)
                        session.nextSequence++
                        response(session.processor.add(bytes), session)
                    }
                    "finish" -> {
                        val session = sessions.remove(id) ?: error("Unknown processing session")
                        try { response(session.processor.finish(), session) }
                        finally { NativePracticeAudio.destroy(session.handle) }
                    }
                    "cancel" -> {
                        sessions.remove(id)?.let { NativePracticeAudio.destroy(it.handle) }
                        null
                    }
                    else -> throw IllegalArgumentException("Unknown processing method")
                }
                main.post { result.success(response) }
            } catch (_: Throwable) {
                sessions.remove(id)?.let { NativePracticeAudio.destroy(it.handle) }
                main.post { result.error("audio_processing_failed", "소음 처리를 마치지 못했다. 다시 녹음해야 한다.", null) }
            }
        }
    }

    private fun response(chunk: PracticeAudioChunk, session: Session) = mapOf(
        "samples" to chunk.samples, "speech" to chunk.speech,
        "inputSamples" to session.processor.inputSamples,
        "outputSamples" to session.processor.outputSamples,
        "rawVariance" to session.processor.rawVariance,
    )

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        worker.execute {
            sessions.values.forEach { NativePracticeAudio.destroy(it.handle) }
            sessions.clear()
        }
        worker.shutdown()
    }
}
