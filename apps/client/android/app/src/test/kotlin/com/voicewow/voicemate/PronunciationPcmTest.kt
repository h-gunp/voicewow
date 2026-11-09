package com.voicewow.voicemate

import org.junit.Assert.*
import org.junit.Test

class PronunciationPcmTest {
    private val vocab = Array(55) { "phone$it" }.also {
        it[0] = "[PAD]"; it[1] = "ɡ"; it[42] = "jʌ"
        it[51] = " "; it[52] = "[UNK]"; it[53] = "<s>"; it[54] = "</s>"
    }

    @Test fun ctcPreservesRepeatsAfterBlankAndUnknownTokens() {
        val ids = intArrayOf(0, 1, 1, 0, 1, 51, 42, 42, 52, 53, 54)
        val logits = FloatArray(ids.size * 55) { -1f }
        ids.forEachIndexed { frame, id -> logits[frame * 55 + id] = 1f }
        assertEquals(listOf("ɡ", "ɡ", "jʌ", "[UNK]", "<s>", "</s>"),
            PronunciationPcm.decode(logits, longArrayOf(1, ids.size.toLong(), 55), vocab))
    }

    @Test fun preprocessingPreservesRawPcmAndRejectsInvalidOrSilentAudio() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.5f else -0.5f }
        val original = raw.copyOf()
        val prepared = PronunciationPcm.prepareSamples(raw, 16000)
        assertArrayEquals(original, prepared, 0f)
        assertArrayEquals(original, raw, 0f)
        for (invalid in listOf(FloatArray(3200), FloatArray(3199), FloatArray(320001),
            FloatArray(3200) { 0.01f }, FloatArray(3200) { if (it % 2 == 0) 1e-6f else -1e-6f },
            raw.copyOf().also { it[0] = Float.NaN }, raw.copyOf().also { it[0] = Float.POSITIVE_INFINITY },
            raw.copyOf().also { it[0] = 2f })) {
            assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.prepareSamples(invalid, 16000) }
        }
        assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.prepareSamples(raw, 48000) }
    }

    @Test fun outerSilenceAndQuietEdgesKeepTheirOriginalSamplesAndPositions() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.25f else -0.25f }
        for (padding in listOf(16001, 16080, 16159)) {
            val padded = FloatArray(raw.size + padding * 2)
            raw.copyInto(padded, padding)
            padded[1] = 0.00001f
            padded[padded.lastIndex - 1] = -0.00001f
            assertArrayEquals(padded, PronunciationPcm.prepareSamples(padded, 16000), 0f)
        }
    }

    @Test fun microphoneGainAndDcOffsetAreNotChangedByPreprocessing() {
        val raw = FloatArray(3200) { if (it % 2 == 0) 0.1f else -0.1f }
        val quiet = FloatArray(raw.size) { raw[it] * 0.01f + 0.02f }
        assertArrayEquals(raw, PronunciationPcm.prepareSamples(raw, 16000), 0f)
        assertArrayEquals(quiet, PronunciationPcm.prepareSamples(quiet, 16000), 0f)
    }

    @Test fun maximumDurationAndLowAmplitudePreserveRawPcm() {
        val raw = FloatArray(320000) { if (it % 2 == 0) 0.25f else -0.25f }
        val original = raw.copyOf()
        assertArrayEquals(original, PronunciationPcm.prepareSamples(raw, 16000), 0f)
        assertArrayEquals(original, raw, 0f)

        val quiet = FloatArray(3200) { if (it % 2 == 0) 5e-5f else -5e-5f }
        assertArrayEquals(quiet, PronunciationPcm.prepareSamples(quiet, 16000), 0f)
    }

    @Test fun malformedOutputIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PronunciationPcm.decode(FloatArray(55), longArrayOf(1, 1, 45), vocab)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PronunciationPcm.decode(FloatArray(55).also { it[4] = Float.NaN }, longArrayOf(1, 1, 55), vocab)
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
