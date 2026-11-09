package com.voicewow.voicemate

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Properties

/** Opt-in local evidence only: latest complete payload <=4 MiB, two payloads during replacement. */
internal class LocalAudioDiagnostics(private val root: File) {
    fun save(raw: ByteArray?, samples: FloatArray, logits: FloatArray, shape: LongArray,
        speech: IntArray?, vocab: Array<String>, phones: List<String>, revision: String): Boolean = synchronized(storageLock) {
        if (raw == null) return@synchronized false
        var pending: File? = null
        try {
            require(raw.size in 1..1_920_000 && raw.size % 2 == 0)
            require(samples.size in 3200..320000 && samples.size == (raw.size / 2 + 2) / 3)
            require(samples.all { it.isFinite() && it in -1.001f..1.001f })
            require(shape.size == 3 && shape[0] == 1L && shape[1] in 1L..1000L && shape[2] == 55L)
            require(logits.size.toLong() == shape[1] * 55 && logits.all { it.isFinite() })
            require(speech == null || (speech.size == (samples.size + 159) / 160 && speech.all { it in 0..2 }))
            require(vocab.size == 55 && vocab.all { it.length <= 32 } && phones.size <= 1000 && phones.all { it in vocab })
            val files = linkedMapOf("raw48.pcm" to raw, "input16.f32" to floats(samples), "logits.f32" to floats(logits))
            val properties = Properties().apply {
                setProperty("schema", "1")
                setProperty("created.epochMillis", System.currentTimeMillis().toString())
                setProperty("raw.sampleRate", "48000")
                setProperty("raw.samples", (raw.size / 2).toString())
                setProperty("raw.format", "PCM16LE mono, before app RNNoise/FIR")
                setProperty("capture.requestedSource", "VOICE_RECOGNITION")
                setProperty("capture.requestedEffects", "autoGain=false,echoCancel=false,noiseSuppress=false")
                setProperty("input.sampleRate", "16000")
                setProperty("input.samples", samples.size.toString())
                setProperty("input.durationSeconds", (samples.size / 16000.0).toString())
                setProperty("input.format", "float32LE mono, exact prepared model input")
                setProperty("logits.shape", shape.joinToString(","))
                setProperty("logits.strideSamples", "320")
                setProperty("logits.receptiveFieldSamples", "400")
                setProperty("model.revision", revision)
                setProperty("decoder.blankBias", "0.5")
                setProperty("phones", phones.joinToString(" "))
                speech?.let { setProperty("vad.10ms", it.joinToString(",")) }
                vocab.forEachIndexed { index, phone -> setProperty("vocab.$index", phone) }
                files.forEach { (name, bytes) ->
                    setProperty("$name.bytes", bytes.size.toString())
                    setProperty("$name.sha256", MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) })
                }
            }
            val metadata = ByteArrayOutputStream().also { output ->
                output.writer(Charsets.UTF_8).use { properties.store(it, "Local audio diagnostic; no network transfer") }
            }.toByteArray()
            require(metadata.size <= 65536 && payloadBytes(raw.size, samples.size, logits.size, metadata.size) <= MAX_BYTES)
            files["metadata.properties"] = metadata
            check(root.isDirectory || root.mkdirs())
            val latest = File(root, "latest")
            val previous = File(root, "previous")
            pending = File(root, "pending")
            for (child in listOf(latest, previous, pending)) require(child.canonicalFile.parentFile == root.canonicalFile)
            // Recover a replacement interrupted after moving the old complete payload.
            if (previous.exists() && !latest.exists()) check(previous.renameTo(latest))
            if (previous.exists()) check(previous.deleteRecursively())
            if (pending.exists()) check(pending.deleteRecursively())
            check(pending.mkdir())
            files.forEach { (name, bytes) -> File(pending, name).outputStream().use { it.write(bytes) } }
            if (latest.exists()) check(latest.renameTo(previous))
            if (!pending.renameTo(latest)) {
                previous.renameTo(latest)
                error("Diagnostic replacement failed")
            }
            if (previous.exists()) check(previous.deleteRecursively())
            true
        } catch (_: Exception) {
            false
        } finally {
            runCatching { pending?.let { if (it.canonicalFile.parentFile == root.canonicalFile) it.deleteRecursively() } }
        }
    }

    companion object {
        private val storageLock = Any()
        const val MAX_BYTES = 4L * 1024 * 1024
        internal fun payloadBytes(rawBytes: Int, samples: Int, logits: Int, metadataBytes: Int): Long =
            rawBytes.toLong() + samples.toLong() * 4 + logits.toLong() * 4 + metadataBytes
        private fun floats(values: FloatArray): ByteArray = ByteBuffer.allocate(values.size * 4)
            .order(ByteOrder.LITTLE_ENDIAN).also { it.asFloatBuffer().put(values) }.array()
    }
}
