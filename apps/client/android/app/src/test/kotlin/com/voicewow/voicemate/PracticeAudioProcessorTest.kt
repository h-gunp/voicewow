package com.voicewow.voicemate

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

class PracticeAudioProcessorTest {
    private fun processor(decision: Int = 1): PracticeAudioProcessor {
        var previous: ShortArray? = null
        return PracticeAudioProcessor { frame ->
            val old = previous
            previous = frame.copyOf()
            if (old == null) floatArrayOf()
            else FloatArray(481) { index -> if (index == 0) decision.toFloat() else old[index - 1] / 32768f }
        }
    }

    private fun bytes(samples: ShortArray) = ByteArray(samples.size * 2) { index ->
        val value = samples[index / 2].toInt()
        (if (index % 2 == 0) value else value shr 8).toByte()
    }

    @Test fun arbitraryByteChunksAndFinalPartialFramePreserveOneContinuousSignal() {
        val source = bytes(ShortArray(1433) { (sin(it * .07) * 20000).toInt().toShort() })
        fun run(chunk: Int): Pair<FloatArray, IntArray> {
            val engine = processor(2)
            val output = mutableListOf<Float>()
            val speech = mutableListOf<Int>()
            for (start in source.indices step chunk) {
                val result = engine.add(source.copyOfRange(start, minOf(start + chunk, source.size)))
                output.addAll(result.samples.toList())
                speech.addAll(result.speech.toList())
            }
            val tail = engine.finish()
            output.addAll(tail.samples.toList())
            speech.addAll(tail.speech.toList())
            assertEquals(1433, engine.inputSamples)
            assertEquals(478, engine.outputSamples)
            return output.toFloatArray() to speech.toIntArray()
        }
        val whole = run(source.size)
        val oddChunks = run(317)
        assertArrayEquals(whole.first, oddChunks.first, 0f)
        assertArrayEquals(intArrayOf(2, 2, 2), oddChunks.second)
        assertTrue(oddChunks.first.takeLast(10).any { kotlin.math.abs(it) > .01f })
    }

    @Test fun primingAndSilenceDoNotInsertOrRemoveSamples() {
        val engine = processor(0)
        assertEquals(0, engine.add(ByteArray(960)).samples.size)
        val tail = engine.finish()
        assertEquals(160, tail.samples.size)
        assertTrue(tail.samples.all { it == 0f })
        assertArrayEquals(intArrayOf(0), tail.speech)
        assertThrows(IllegalStateException::class.java) { engine.finish() }
    }

    @Test fun aFinalSingleSampleIsFlushedAndUnpairedBytesFail() {
        val engine = processor()
        engine.add(bytes(shortArrayOf(20000)))
        val tail = engine.finish()
        assertEquals(1, tail.samples.size)
        assertTrue(tail.samples.single() > 0)
        val broken = processor()
        broken.add(byteArrayOf(1))
        assertThrows(IllegalArgumentException::class.java) { broken.finish() }
    }

    @Test fun resamplingAttenuatesEnergyAboveThe16kNyquistLimit() {
        fun rms(frequency: Double): Double {
            val engine = processor()
            val values = ShortArray(4800) { (16000 * sin(2 * PI * frequency * it / 48000)).toInt().toShort() }
            val output = engine.add(bytes(values)).samples.toList() + engine.finish().samples.toList()
            val middle = output.drop(50).dropLast(50)
            return sqrt(middle.sumOf { it.toDouble() * it } / middle.size)
        }
        assertTrue(rms(2000.0) > .3)
        assertTrue(rms(12000.0) < .005)
    }

    @Test fun rawPronunciationHasImmediateVADAndNoPrimingOrDrainFrame() {
        var calls = 0
        val engine = PracticeAudioProcessor(noiseReductionEnabled = false) { frame ->
            calls++
            FloatArray(481) { index -> if (index == 0) 0f else frame[index - 1] / 32768f }
        }
        val first = engine.add(bytes(ShortArray(480) { 12000 }))
        assertEquals(150, first.samples.size)
        assertArrayEquals(intArrayOf(0), first.speech)
        assertTrue(first.samples.any { it > .3f })
        val tail = engine.finish()
        assertEquals(10, tail.samples.size)
        assertArrayEquals(intArrayOf(), tail.speech)
        assertEquals(1, calls)
        assertEquals(160, engine.outputSamples)
    }

    @Test fun rawPronunciationOddChunksAndPartialTailMatchTheSameDryFir() {
        val pcm = bytes(ShortArray(1433) { (sin(it * .07) * 20000).toInt().toShort() })
        var calls = 0
        val raw = PracticeAudioProcessor(noiseReductionEnabled = false) { frame ->
            calls++
            FloatArray(481) { index -> if (index == 0) 1f else frame[index - 1] / 32768f }
        }
        val actual = mutableListOf<Float>()
        for (start in pcm.indices step 317) {
            actual.addAll(raw.add(pcm.copyOfRange(start, minOf(start + 317, pcm.size))).samples.toList())
        }
        actual.addAll(raw.finish().samples.toList())
        val delayedDry = processor()
        val expected = delayedDry.add(pcm).samples.toList() + delayedDry.finish().samples.toList()
        assertArrayEquals(expected.toFloatArray(), actual.toFloatArray(), 0f)
        assertEquals(478, actual.size)
        assertEquals(3, calls)
    }

    @Test fun disabledVadPreservesEverySampleAndEmitsNoDecisions() {
        val pcm = bytes(ShortArray(1433) { (sin(it * .07) * 20000).toInt().toShort() })
        var calls = 0
        val raw = PracticeAudioProcessor(noiseReductionEnabled = false, voiceActivityEnabled = false) { frame ->
            calls++
            FloatArray(481) { index -> if (index == 0) -1f else frame[index - 1] / 32768f }
        }
        val output = mutableListOf<Float>()
        for (start in pcm.indices step 317) {
            val chunk = raw.add(pcm.copyOfRange(start, minOf(start + 317, pcm.size)))
            output.addAll(chunk.samples.toList())
            assertTrue(chunk.speech.isEmpty())
        }
        val tail = raw.finish()
        output.addAll(tail.samples.toList())
        assertTrue(tail.speech.isEmpty())
        val withVad = processor()
        val expected = withVad.add(pcm).samples.toList() + withVad.finish().samples.toList()
        assertArrayEquals(expected.toFloatArray(), output.toFloatArray(), 0f)
        assertEquals(478, raw.outputSamples)
        assertEquals(3, calls)
    }

    @Test fun disabledVadRejectsAFabricatedNonSpeechDecision() {
        val raw = PracticeAudioProcessor(noiseReductionEnabled = false, voiceActivityEnabled = false) {
            FloatArray(481)
        }
        assertThrows(IllegalStateException::class.java) { raw.add(ByteArray(960)) }
    }
}
