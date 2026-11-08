package com.voicewow.voicemate

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.sqrt

class PronunciationPcmTest {
    private val vocab = Array(45) { "phone$it" }.also {
        it[40] = "|"; it[41] = "[UNK]"; it[42] = "[PAD]"; it[43] = "<s>"; it[44] = "</s>"
    }

    @Test fun ctcPreservesRepeatsAfterBlankAndUnknownTokens() {
        val ids = intArrayOf(9, 9, 42, 9, 40, 0, 41, 43, 44)
        val logits = FloatArray(ids.size * 45) { -1f }
        ids.forEachIndexed { frame, id -> logits[frame * 45 + id] = 1f }
        assertEquals(listOf("phone9", "phone9", "phone0", "[UNK]", "<s>", "</s>"),
            PronunciationPcm.decode(logits, longArrayOf(1, ids.size.toLong(), 45), vocab))
    }

    @Test fun normalizationUsesRawPcmAndRejectsInvalidOrSilentAudio() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.5f else -0.5f }
        val original = raw.copyOf()
        val normalized = PronunciationPcm.normalize(raw, 16000)
        assertEquals(16000, normalized.size)
        assertEquals(sqrt(5.0), normalized[6400].toDouble(), 1e-5)
        assertEquals(-sqrt(5.0), normalized[6401].toDouble(), 1e-5)
        assertArrayEquals(original, raw, 0f)
        for (invalid in listOf(FloatArray(3200), FloatArray(3199), FloatArray(320001),
            FloatArray(3200) { 0.01f }, FloatArray(3200) { if (it % 2 == 0) 1e-6f else -1e-6f },
            raw.copyOf().also { it[0] = Float.NaN }, raw.copyOf().also { it[0] = Float.POSITIVE_INFINITY },
            raw.copyOf().also { it[0] = 2f })) {
            assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.normalize(invalid, 16000) }
        }
        assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.normalize(raw, 48000) }
    }

    @Test fun outerSilenceDoesNotChangeSamplesEvenWithoutFrameAlignment() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.25f else -0.25f }
        val expected = PronunciationPcm.normalize(raw, 16000)
        for (padding in listOf(16001, 16080, 16159)) {
            val padded = FloatArray(raw.size + padding * 2)
            raw.copyInto(padded, padding)
            assertArrayEquals(expected, PronunciationPcm.normalize(padded, 16000), 0f)
        }
    }

    @Test fun contextPreservesQuietEdgesAndInternalPauses() {
        val raw = FloatArray(20000)
        raw[1700] = 0.002f
        raw[8000] = 0.5f
        raw[10000] = -0.002f
        raw[12000] = -0.5f
        raw[18300] = 0.003f
        val original = raw.copyOf()
        val expectedContext = raw.copyOfRange(1600, 18401)
        assertArrayEquals(standardize(expectedContext), PronunciationPcm.normalize(raw, 16000), 0f)
        assertArrayEquals(original, raw, 0f)
    }

    @Test fun quietGainKeepsNormalizedSamplesWithoutVarianceEpsilon() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.1f else -0.1f }
        val quiet = FloatArray(raw.size) { raw[it] * 0.01f }
        assertArrayEquals(PronunciationPcm.normalize(raw, 16000),
            PronunciationPcm.normalize(quiet, 16000), 1e-6f)
    }

    @Test fun contextNeverTruncatesAudioToFitTheTwentySecondLimit() {
        val raw = FloatArray(320000) { if (it % 2 == 0) 0.25f else -0.25f }
        val original = raw.copyOf()
        assertArrayEquals(standardize(raw), PronunciationPcm.normalize(raw, 16000), 0f)
        assertArrayEquals(original, raw, 0f)

        val atLimit = FloatArray(307200) { if (it % 2 == 0) 0.25f else -0.25f }
        assertEquals(320000, PronunciationPcm.normalize(atLimit, 16000).size)
        val exceeds = FloatArray(307201) { if (it % 2 == 0) 0.25f else -0.25f }
        assertArrayEquals(standardize(exceeds), PronunciationPcm.normalize(exceeds, 16000), 0f)
    }

    @Test fun validSignalBelowTheBoundaryThresholdKeepsItsOriginalExtent() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 5e-5f else -5e-5f }
        assertArrayEquals(standardize(raw), PronunciationPcm.normalize(raw, 16000), 0f)
    }

    private fun standardize(samples: FloatArray): FloatArray {
        val mean = samples.sumOf { it.toDouble() } / samples.size
        val variance = samples.sumOf { (it - mean) * (it - mean) } / samples.size
        return FloatArray(samples.size) { ((samples[it] - mean) / sqrt(variance)).toFloat() }
    }

    @Test fun malformedOutputIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PronunciationPcm.decode(FloatArray(45), longArrayOf(1, 1, 44), vocab)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PronunciationPcm.decode(FloatArray(45).also { it[4] = Float.NaN }, longArrayOf(1, 1, 45), vocab)
        }
    }

    @Test fun staleOwnerCannotCancelOrDisposeNewSession() {
        val lease = PronunciationLease()
        val old = lease.claim(1)
        val current = lease.claim(2)
        assertFalse(lease.current(1, old))
        assertTrue(lease.current(2, current))
        assertFalse(lease.cancel(1))
        assertTrue(lease.current(2, current))
        assertTrue(lease.cancel(2))
        assertFalse(lease.current(2, current))
    }
}
