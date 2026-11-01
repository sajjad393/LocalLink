package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 187 (A2): was the screen frozen while a slow storage step ran? */
class Store187Test {
    private val main = File("main/kotlin/com/sajjad/locallink")

    @Test fun `stall inside the window is y`() {
        // stall 10_000..11_200, step window 10_800..12_000
        assertEquals("y", StallRules.overlap(12_000L, 1_200L, 11_200L, 1_200L, false))
        // stall started before the window and ended inside it
        assertEquals("y", StallRules.overlap(12_000L, 500L, 11_600L, 3_000L, true))
    }

    @Test fun `old stall is n while watching, dash when not watched`() {
        assertEquals("n", StallRules.overlap(20_000L, 1_000L, 11_200L, 1_200L, true))
        assertEquals("-", StallRules.overlap(20_000L, 1_000L, 11_200L, 1_200L, false))
        assertEquals("n", StallRules.overlap(20_000L, 1_000L, 0L, 0L, true))
        assertEquals("-", StallRules.overlap(20_000L, 1_000L, 0L, 0L, false))
    }

    @Test fun `short stalls are remembered but only long ones are logged`() {
        assertEquals(300L, StallRules.NOTE_MS)
        assertTrue(StallRules.NOTE_MS < StallRules.STALL_MS)
        val health = File(main, "AppHealth.kt").readText()
        assertTrue(health.contains("if (stall >= StallRules.NOTE_MS) { lastStallMs = stall; lastStallEnd = end }"))
        assertTrue(health.contains("fun stallOverlap(windowMs: Long): String"))
    }

    @Test fun `device channel answers stallOverlap`() {
        val activity = File(main, "MainActivity.kt").readText()
        val device = activity.indexOf("\"locallink/device\")")
        val method = activity.indexOf("call.method == \"stallOverlap\"")
        assertTrue(device > 0 && method > device && method - device < 1200)
        assertTrue(activity.contains("AppHealth.stallOverlap((call.argument<Number>(\"window_ms\") ?: 0).toLong())"))
    }
}
