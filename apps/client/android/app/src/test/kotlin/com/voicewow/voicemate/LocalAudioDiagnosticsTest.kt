package com.voicewow.voicemate

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Properties
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LocalAudioDiagnosticsTest {
    @get:Rule val temporary = TemporaryFolder()
    private val raw = ByteArray(19200) { (it % 251).toByte() }
    private val samples = FloatArray(3200) { if (it % 2 == 0) .125f else -.0625f }
    private val logits = FloatArray(9 * 55) { it / 100f }
    private val shape = longArrayOf(1, 9, 55)
    private val vocab = Array(55) { "phone$it" }.also { it[0] = "[PAD]"; it[2] = "ɯ"; it[3] = "ɾ" }
    private fun save(store: LocalAudioDiagnostics, pcm: ByteArray? = raw) =
        store.save(pcm, samples, logits, shape, IntArray(20) { 1 }, vocab, listOf("ɯ", "ɾ"), "pinned-revision")

    @Test fun absentPayloadWritesNothingAndEnabledPayloadPreservesExactBytesAndMetadata() {
        val root = File(temporary.root, "diagnostics")
        val store = LocalAudioDiagnostics(root)
        assertFalse(save(store, null))
        assertFalse(root.exists())
        assertTrue(save(store))
        val latest = File(root, "latest")
        assertArrayEquals(raw, File(latest, "raw48.pcm").readBytes())
        val restored = ByteBuffer.wrap(File(latest, "input16.f32").readBytes()).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        val values = FloatArray(restored.remaining()).also { restored.get(it) }
        assertArrayEquals(samples, values, 0f)
        val restoredLogits = ByteBuffer.wrap(File(latest, "logits.f32").readBytes()).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        assertArrayEquals(logits, FloatArray(restoredLogits.remaining()).also { restoredLogits.get(it) }, 0f)
        val metadata = Properties().also { File(latest, "metadata.properties").reader(Charsets.UTF_8).use(it::load) }
        assertEquals("16000", metadata.getProperty("input.sampleRate"))
        assertEquals("48000", metadata.getProperty("raw.sampleRate"))
        assertEquals("3200", metadata.getProperty("input.samples"))
        assertEquals("1,9,55", metadata.getProperty("logits.shape"))
        assertEquals("ɯ", metadata.getProperty("vocab.2"))
        assertEquals("ɯ ɾ", metadata.getProperty("phones"))
        assertEquals("pinned-revision", metadata.getProperty("model.revision"))
        for (name in listOf("raw48.pcm", "input16.f32", "logits.f32")) {
            val bytes = File(latest, name).readBytes()
            val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals(hash, metadata.getProperty("$name.sha256"))
        }
        assertTrue(latest.listFiles()!!.sumOf { it.length() } <= LocalAudioDiagnostics.MAX_BYTES)
    }

    @Test fun latestOnlyReplacesAfterCompleteWriteAndInvalidInputKeepsPrevious() {
        val root = File(temporary.root, "diagnostics")
        val store = LocalAudioDiagnostics(root)
        assertTrue(save(store))
        val replacement = raw.copyOf().also { it[0] = 99 }
        assertTrue(save(store, replacement))
        assertArrayEquals(replacement, File(root, "latest/raw48.pcm").readBytes())
        assertFalse(save(store, byteArrayOf(1)))
        assertArrayEquals(replacement, File(root, "latest/raw48.pcm").readBytes())
        assertEquals(listOf("latest"), root.list()!!.sorted())
        assertFalse(store.save(raw, samples, logits, longArrayOf(1, Long.MAX_VALUE, 55), null, vocab, emptyList(), "r"))
    }

    @Test fun storageFailureIsOptionalAndByteBoundsDoNotOverflow() {
        val badRoot = temporary.newFile("not-a-directory")
        assertFalse(save(LocalAudioDiagnostics(badRoot)))
        assertTrue(badRoot.isFile)
        assertTrue(LocalAudioDiagnostics.payloadBytes(1_920_000, 320000, 55000, 65536) < LocalAudioDiagnostics.MAX_BYTES)
        assertTrue(LocalAudioDiagnostics.payloadBytes(Int.MAX_VALUE, Int.MAX_VALUE, Int.MAX_VALUE, Int.MAX_VALUE) > LocalAudioDiagnostics.MAX_BYTES)
        val root = File(temporary.root, "too-large")
        val store = LocalAudioDiagnostics(root)
        assertFalse(save(store, ByteArray(1_920_002)))
        assertFalse(root.exists())
        assertFalse(store.save(raw, samples, logits, shape, IntArray(1), vocab, emptyList(), "r"))
        assertFalse(root.exists())
    }

    @Test fun fullTwentySecondPayloadFitsTheFixedBound() {
        val root = File(temporary.root, "maximum")
        val store = LocalAudioDiagnostics(root)
        assertTrue(store.save(ByteArray(1_920_000), FloatArray(320000), FloatArray(999 * 55),
            longArrayOf(1, 999, 55), IntArray(2000), vocab, emptyList(), "r"))
        assertTrue(File(root, "latest").listFiles()!!.sumOf { it.length() } <= LocalAudioDiagnostics.MAX_BYTES)
    }

    @Test fun twoStoreInstancesNeverMixConcurrentPayloads() {
        val root = File(temporary.root, "concurrent")
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val writes = (1..2).map { id ->
                pool.submit<Boolean> {
                    val store = LocalAudioDiagnostics(root)
                    val pcm = ByteArray(1_920_000) { id.toByte() }
                    val input = FloatArray(320000) { id / 10f }
                    val scores = FloatArray(999 * 55) { id.toFloat() }
                    check(start.await(2, TimeUnit.SECONDS))
                    (1..8).all { store.save(pcm, input, scores, longArrayOf(1, 999, 55), null, vocab, emptyList(), "writer$id") }
                }
            }
            start.countDown()
            writes.forEach { assertTrue(it.get(10, TimeUnit.SECONDS)) }
            val latest = File(root, "latest")
            val properties = Properties().also { File(latest, "metadata.properties").reader(Charsets.UTF_8).use(it::load) }
            val id = properties.getProperty("model.revision").removePrefix("writer").toInt()
            assertTrue(File(latest, "raw48.pcm").readBytes().all { it == id.toByte() })
            val input = ByteBuffer.wrap(File(latest, "input16.f32").readBytes()).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            assertTrue(FloatArray(input.remaining()).also { input.get(it) }.all { it == id / 10f })
            val scores = ByteBuffer.wrap(File(latest, "logits.f32").readBytes()).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            assertTrue(FloatArray(scores.remaining()).also { scores.get(it) }.all { it == id.toFloat() })
            assertEquals(listOf("latest"), root.list()!!.sorted())
        } finally {
            pool.shutdownNow()
        }
    }
}
