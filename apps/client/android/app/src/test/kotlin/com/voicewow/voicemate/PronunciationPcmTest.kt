package com.voicewow.voicemate

import org.junit.Assert.*
import org.junit.Test

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
        val normalized = PronunciationPcm.normalize(raw, 16000)
        assertEquals(1.0, normalized[0].toDouble(), 1e-5)
        assertEquals(-1.0, normalized[1].toDouble(), 1e-5)
        for (invalid in listOf(FloatArray(3200), FloatArray(3199), FloatArray(320001),
            raw.copyOf().also { it[0] = Float.NaN }, raw.copyOf().also { it[0] = 2f })) {
            assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.normalize(invalid, 16000) }
        }
        assertThrows(IllegalArgumentException::class.java) { PronunciationPcm.normalize(raw, 48000) }
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
