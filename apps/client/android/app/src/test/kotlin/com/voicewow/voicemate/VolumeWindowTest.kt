package com.voicewow.voicemate

import org.junit.Assert.*
import org.junit.Test

class VolumeWindowTest {
    @Test fun computesRmsFromEnergyAcrossDisjointFrames() {
        val meter = VolumeWindow()
        repeat(5) { assertNull(meter.add(0.5, 0.75, 480)) }
        repeat(4) { assertNull(meter.add(0.0, 0.0, 480)) }
        val result = meter.add(0.0, 0.0, 480)!!
        assertEquals(kotlin.math.sqrt(0.125), result["rms"] as Double, 1e-12)
        assertEquals(0.75, result["peak"] as Double, 1e-12)
        assertEquals(-9.030899869919436, result["dbfs"] as Double, 1e-9)
        assertEquals(4800, result["sampleCount"])
    }

    @Test fun zeroWindowClearsPreviousEnergyAndHasNoInfiniteLevel() {
        val meter = VolumeWindow()
        repeat(10) { meter.add(1.0, 1.0, 480) }
        repeat(9) { assertNull(meter.add(0.0, 0.0, 480)) }
        val silence = meter.add(0.0, 0.0, 480)!!
        assertEquals(0.0, silence["rms"] as Double, 0.0)
        assertEquals(0.0, silence["peak"] as Double, 0.0)
        assertEquals(0.0, silence["normalized"] as Double, 0.0)
        assertNull(silence["dbfs"])
        assertThrows(IllegalArgumentException::class.java) { meter.add(Double.NaN, 0.0, 480) }
    }
}
