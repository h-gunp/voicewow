package com.voicewow.voicemate

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

internal data class PracticeAudioChunk(val samples: FloatArray, val speech: IntArray)

/** Continuous 48 kHz PCM16 input, delayed RNNoise frames, then 16 kHz output. */
internal class PracticeAudioProcessor(private val denoise: (ShortArray) -> FloatArray) {
    private val frame = ShortArray(480)
    private val resampler = PracticeDownsampler()
    private var filled = 0
    private var lowByte: Int? = null
    private var pendingValid = 0
    private var primed = false
    private var finished = false
    private var rawSum = 0.0
    private var rawSquares = 0.0
    var inputSamples = 0
        private set
    var outputSamples = 0
        private set
    val rawVariance: Double get() = if (inputSamples == 0) 0.0 else
        (rawSquares / inputSamples - (rawSum / inputSamples) * (rawSum / inputSamples)).coerceAtLeast(0.0)

    fun add(bytes: ByteArray): PracticeAudioChunk {
        check(!finished)
        val output = ArrayList<Float>()
        val speech = ArrayList<Int>()
        for (byte in bytes) {
            val value = byte.toInt() and 255
            val low = lowByte
            if (low == null) lowByte = value
            else {
                lowByte = null
                require(inputSamples < 48000 * 20) { "Recording exceeds 20 seconds" }
                frame[filled++] = (low or (value shl 8)).toShort()
                val normalized = frame[filled - 1] / 32768.0
                rawSum += normalized
                rawSquares += normalized * normalized
                inputSamples++
                if (filled == 480) {
                    processFrame(480, output, speech)
                    filled = 0
                }
            }
        }
        return chunk(output, speech)
    }

    fun finish(): PracticeAudioChunk {
        check(!finished)
        finished = true
        require(lowByte == null) { "Incomplete PCM16 sample" }
        val output = ArrayList<Float>()
        val speech = ArrayList<Int>()
        if (filled > 0) {
            frame.fill(0, filled)
            processFrame(filled, output, speech)
        }
        if (primed) {
            frame.fill(0)
            processFrame(0, output, speech)
        }
        resampler.finish(output)
        val result = chunk(output, speech)
        check(outputSamples == (inputSamples + 2) / 3) { "Processed audio length mismatch" }
        return result
    }

    private fun processFrame(valid: Int, output: MutableList<Float>, speech: MutableList<Int>) {
        val processed = denoise(frame)
        if (!primed) {
            check(processed.isEmpty()) { "RNNoise priming frame must not be emitted" }
            primed = true
        } else {
            check(processed.size == 481 && processed.all { it.isFinite() })
            val decision = processed[0].toInt()
            check(decision in 0..2 && processed[0] == decision.toFloat())
            if (pendingValid > 0) {
                speech.add(decision)
                for (index in 1..pendingValid) resampler.add(processed[index], output)
            }
        }
        pendingValid = valid
    }

    private fun chunk(output: List<Float>, speech: List<Int>): PracticeAudioChunk {
        outputSamples += output.size
        return PracticeAudioChunk(output.toFloatArray(), speech.toIntArray())
    }
}

/** A centered low-pass FIR prevents 48 kHz energy aliasing into speech at 16 kHz. */
private class PracticeDownsampler {
    private val taps = FloatArray(63) { index ->
        val x = index - 31
        val lowpass = if (x == 0) .3 else sin(2 * PI * .15 * x) / (PI * x)
        (lowpass * (.54 - .46 * cos(2 * PI * index / 62))).toFloat()
    }.also { values ->
        val sum = values.sum()
        for (i in values.indices) values[i] /= sum
    }
    private val history = FloatArray(63)
    private var received = 0
    private var position = 0

    fun add(value: Float, output: MutableList<Float>) {
        history[position] = value
        val center = received - 31
        if (center >= 0 && center % 3 == 0) {
            var filtered = 0.0
            for (index in taps.indices) {
                filtered += taps[index] * history[(position - index + 63) % 63]
            }
            output.add(filtered.toFloat().coerceIn(-1f, 1f))
        }
        position = (position + 1) % 63
        received++
    }

    fun finish(output: MutableList<Float>) {
        if (received > 0) repeat(31) { add(0f, output) }
    }
}
