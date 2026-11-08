package com.voicewow.voicemate

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

internal object NativeNoiseMeter {
    init { System.loadLibrary("voicemate_audio") }
    external fun create(): Long
    external fun process(handle: Long, pcm: ShortArray): DoubleArray
    external fun destroy(handle: Long)
}

internal class VolumeWindow {
    private var count = 0
    private var energy = 0.0
    private var peak = 0.0

    fun add(rms: Double, framePeak: Double, samples: Int): Map<String, Any?>? {
        require(rms.isFinite() && rms >= 0 && framePeak.isFinite() && framePeak >= 0 && samples > 0)
        energy += rms * rms * samples
        peak = max(peak, framePeak)
        count += samples
        if (count < 4800) return null
        val resultRms = sqrt(energy / count)
        val dbfs = if (resultRms > 0) 20 * log10(resultRms) else null
        val result = mapOf("rms" to resultRms, "peak" to peak, "dbfs" to dbfs,
            "normalized" to (dbfs?.let { ((it + 80) / 80).coerceIn(0.0, 1.0) } ?: 0.0),
            "sampleCount" to count)
        count = 0
        energy = 0.0
        peak = 0.0
        return result
    }
}

/** Only aggregate levels and frame decisions cross the channel; PCM stays in the capture thread. */
class VolumeEngine(private val context: Context, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<Long, Session>()
    @Volatile private var active: Session? = null
    @Volatile private var closed = false

    private class Session(val id: Long, val denoise: Boolean, var startResult: MethodChannel.Result?) {
        @Volatile var cancelled = false
        @Volatile var lastSequence = -1L
        val pendingFrame = AtomicBoolean(false)
        val stops = mutableListOf<MethodChannel.Result>()
    }

    private class CaptureFailure(val reason: String) : Exception(reason)

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val rawId = arguments?.get("session")
        val id = if (rawId is Int || rawId is Long) (rawId as Number).toLong() else null
        if (id == null || id < 1 || closed) {
            result.error("unavailable", "마이크 연결을 다시 시작해야 한다.", null)
            return
        }
        when (call.method) {
            "start" -> {
                val denoise = arguments?.get("noiseReductionEnabled") as? Boolean
                if (denoise == null || sessions.containsKey(id)) {
                    result.error("invalid_request", "마이크 시작 요청을 확인해야 한다.", null)
                } else if (active != null) {
                    result.error("device_busy", "진행 중인 녹음을 먼저 마쳐야 한다.", null)
                } else {
                    val session = Session(id, denoise, result)
                    sessions[id] = session
                    active = session
                    worker.execute { capture(session) }
                }
            }
            "stop" -> {
                val session = sessions[id]
                if (session == null) result.success(null)
                else {
                    session.stops.add(result)
                    cancel(session)
                }
            }
            "sampleBoundary" -> {
                val session = active
                if (session == null || session.id != id || session.cancelled) {
                    result.error("unavailable", "측정을 시작한 뒤 환경음을 수집해야 한다.", null)
                } else result.success(session.lastSequence)
            }
            else -> result.notImplemented()
        }
    }

    private fun current(session: Session) = !closed && !session.cancelled && active === session

    private fun cancel(session: Session) {
        session.cancelled = true
        if (active === session) active = null
    }

    private fun capture(session: Session) {
        var recorder: AudioRecord? = null
        var processor = 0L
        var failure: String? = null
        val pcm = ShortArray(480)
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            if (!current(session)) return
            if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                throw CaptureFailure("permission_denied")
            }
            if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
                throw CaptureFailure("device_missing")
            }
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val source = if (audio.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true") {
                MediaRecorder.AudioSource.UNPROCESSED
            } else MediaRecorder.AudioSource.VOICE_RECOGNITION
            val minimum = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minimum <= 0) throw CaptureFailure("constraints_unavailable")
            if (session.denoise) {
                processor = NativeNoiseMeter.create()
                if (processor == 0L) throw CaptureFailure("noise_reduction_failed")
            }
            if (!current(session)) return
            val input = AudioRecord.Builder()
                .setAudioSource(source)
                .setAudioFormat(AudioFormat.Builder().setSampleRate(48000)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
                .setBufferSizeInBytes(max(minimum * 2, 19200))
                .build()
            recorder = input
            if (input.state != AudioRecord.STATE_INITIALIZED) throw CaptureFailure("device_busy")
            if (!current(session)) return
            input.startRecording()
            if (input.recordingState != AudioRecord.RECORDSTATE_RECORDING) throw CaptureFailure("device_busy")
            main.post {
                val result = session.startResult
                session.startResult = null
                if (current(session)) {
                    // Source selection does not establish physical input processing on every device.
                    result?.success(mapOf("sampleRate" to 48000, "channelCount" to 1,
                        "noiseReductionState" to if (session.denoise) "active" else "disabled",
                        "vadStatus" to if (session.denoise) "ready" else "disabled"))
                } else result?.error("cancelled", "마이크 시작을 취소했다.", null)
            }
            var filled = 0
            var lastInput = SystemClock.elapsedRealtime()
            var route = input.routedDevice?.id
            val window = VolumeWindow()
            var frames = mutableListOf<Map<String, Any>>()
            while (current(session)) {
                val read = input.read(pcm, filled, pcm.size - filled, AudioRecord.READ_NON_BLOCKING)
                if (read < 0) throw CaptureFailure(if (read == AudioRecord.ERROR_DEAD_OBJECT) "input_ended" else "processing_error")
                if (read == 0) {
                    if (SystemClock.elapsedRealtime() - lastInput > 3000) throw CaptureFailure("input_stalled")
                    Thread.sleep(2)
                    continue
                }
                lastInput = SystemClock.elapsedRealtime()
                filled += read
                if (filled != pcm.size) continue
                filled = 0
                val rawPower = pcm.sumOf { val value = it / 32768.0; value * value } / pcm.size
                val rawPeak = pcm.maxOf { abs(it / 32768.0) }
                var rms = sqrt(rawPower)
                var peak = rawPeak
                if (session.denoise) {
                    val analyzed = NativeNoiseMeter.process(processor, pcm)
                    if (analyzed.isNotEmpty()) {
                        if (analyzed.size != 6 || analyzed.any { !it.isFinite() }) throw CaptureFailure("noise_reduction_failed")
                        session.lastSequence = analyzed[0].toLong()
                        rms = analyzed[3]
                        peak = analyzed[5]
                        frames.add(mapOf("seq" to session.lastSequence, "power" to analyzed[1],
                            "clipped" to (analyzed[2] != 0.0), "meterRms" to rms,
                            "speech" to when (analyzed[4].toInt()) { 0 -> "nonSpeech"; 1 -> "speech"; else -> "uncertain" }))
                    } else {
                        // RNNoise needs its first 10 ms frame before the delayed analysis is available.
                        continue
                    }
                }
                val level = window.add(rms, peak, pcm.size) ?: continue
                if (audio.isMicrophoneMute || (Build.VERSION.SDK_INT >= 29 && input.activeRecordingConfiguration?.isClientSilenced == true)) {
                    throw CaptureFailure("input_muted")
                }
                val currentRoute = input.routedDevice?.id
                if (route != null && currentRoute != null && route != currentRoute) throw CaptureFailure("device_changed")
                if (route == null) route = currentRoute
                postFrames(session, frames, level)
                frames = mutableListOf()
            }
        } catch (_: SecurityException) {
            failure = "permission_denied"
        } catch (error: CaptureFailure) {
            failure = error.reason
        } catch (_: LinkageError) {
            failure = "noise_reduction_failed"
        } catch (_: Exception) {
            failure = "processing_error"
        } finally {
            pcm.fill(0)
            try { recorder?.stop() } catch (_: Exception) { }
            try { recorder?.release() } catch (_: Exception) { }
            if (processor != 0L) {
                try { NativeNoiseMeter.destroy(processor) } catch (_: Exception) { }
            }
            val reason = failure
            main.post {
                val wasCurrent = current(session)
                cancel(session)
                val result = session.startResult
                session.startResult = null
                if (result != null) {
                    result.error(if (wasCurrent) reason ?: "processing_error" else "cancelled", "마이크를 시작하지 못했다. 다시 시도해야 한다.", null)
                } else if (wasCurrent) {
                    channel.invokeMethod("state", mapOf("session" to session.id, "state" to "error", "reason" to reason))
                }
                sessions.remove(session.id)
                session.stops.forEach { it.success(null) }
                session.stops.clear()
            }
        }
    }

    private fun postFrames(session: Session, frames: List<Map<String, Any>>, level: Map<String, Any?>) {
        if (!session.pendingFrame.compareAndSet(false, true)) return
        val captured = SystemClock.elapsedRealtime()
        main.post {
            if (!current(session) || SystemClock.elapsedRealtime() - captured > 200) {
                session.pendingFrame.set(false)
                return@post
            }
            channel.invokeMethod("frames", mapOf("session" to session.id, "frames" to frames,
                "level" to level, "capturedAtMs" to captured), object : MethodChannel.Result {
                override fun success(result: Any?) { session.pendingFrame.set(false) }
                override fun error(code: String, message: String?, details: Any?) { session.pendingFrame.set(false) }
                override fun notImplemented() { session.pendingFrame.set(false) }
            })
        }
    }

    fun suspendCapture() {
        val session = active ?: return
        cancel(session)
        if (!closed) channel.invokeMethod("state", mapOf("session" to session.id, "state" to "idle", "reason" to "app_backgrounded"))
    }

    fun close() {
        if (closed) return
        closed = true
        sessions.values.forEach(::cancel)
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
