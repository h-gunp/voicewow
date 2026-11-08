package com.voicewow.voicemate

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PronunciationDownloadCleanupTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun removesInterruptedDownloadButKeepsCachedModelsAndOtherFiles() {
        val directory = temporary.newFolder("revision")
        val orphan = File.createTempFile("model-", ".part", directory).also { it.writeText("incomplete") }
        val cached = File(directory, "onnx_model_quantized.onnx").also { it.writeText("verified-cache") }
        val config = File(directory, "config.json").also { it.writeText("config") }
        val unrelated = File(directory, "other.part").also { it.writeText("keep") }
        val nested = File(directory, "model-folder.part").also { assertTrue(it.mkdir()) }
        val nestedPart = File(nested, "model-nested.part").also { it.writeText("keep") }

        removeInterruptedModelParts(directory)

        assertFalse(orphan.exists())
        assertEquals("verified-cache", cached.readText())
        assertEquals("config", config.readText())
        assertEquals("keep", unrelated.readText())
        assertEquals("keep", nestedPart.readText())
        removeInterruptedModelParts(directory)
        assertEquals("verified-cache", cached.readText())
    }

    @Test fun absentCacheNeedsNoCleanupAndInvalidCachePathFails() {
        removeInterruptedModelParts(File(temporary.root, "not-created"))
        val invalid = temporary.newFile("file-instead-of-directory")
        assertThrows(IllegalStateException::class.java) { removeInterruptedModelParts(invalid) }
        assertTrue(invalid.isFile)
    }
}
