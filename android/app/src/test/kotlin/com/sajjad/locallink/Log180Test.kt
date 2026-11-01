package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 180: last-hour log files (rules only; logcat is phone-only). */
class Log180Test {
    private fun f(name: String, slot: Long, size: Long) = LogFilePolicy.LogFileInfo(name, slot, size)

    @Test fun `slots are 10 minutes`() {
        assertEquals(0L, LogFilePolicy.slotOf(0L))
        assertEquals(1L, LogFilePolicy.slotOf(600_000L))
        assertEquals(6, LogFilePolicy.KEEP_SLOTS)
        assertEquals("native-7.log", LogFilePolicy.nativeFileName(7L))
    }

    @Test fun `names from both sides parse, others do not`() {
        assertEquals(2900000L, LogFilePolicy.slotFromName("native-2900000.log"))
        assertEquals(12L, LogFilePolicy.slotFromName("app-ui-12.log"))
        assertEquals(12L, LogFilePolicy.slotFromName("app-bg-12.log"))
        assertNull(LogFilePolicy.slotFromName("notes.txt"))
        assertNull(LogFilePolicy.slotFromName("native-12.log.bak"))
    }

    @Test fun `older than one hour is deleted`() {
        val files = (90L..100L).map { f("native-$it.log", it, 10L) }
        assertEquals(listOf("native-90.log", "native-91.log", "native-92.log", "native-93.log"),
            LogFilePolicy.filesToDelete(files, 100L))
    }

    @Test fun `over 10 MB oldest first and never the current file`() {
        val mb = 1024L * 1024L
        val files = listOf(f("native-98.log", 98, 5 * mb), f("app-ui-99.log", 99, 4 * mb), f("native-100.log", 100, 3 * mb))
        assertEquals(listOf("native-98.log"), LogFilePolicy.filesToDelete(files, 100L))
        assertTrue(LogFilePolicy.filesToDelete(listOf(f("native-100.log", 100, 50 * mb)), 100L).isEmpty())
    }

    @Test fun `logcat noise is skipped`() {
        assertTrue(LogFilePolicy.skipLine("--------- beginning of main"))
        assertTrue(LogFilePolicy.skipLine("   "))
        assertFalse(LogFilePolicy.skipLine("  1730460000.123  4321  4400 I RELAY: RELAY ok"))
    }

    @Test fun `epoch time is read from the line start`() {
        assertEquals("1730460000.123", LogFilePolicy.epochOf("  1730460000.123  4321  4400 I RELAY: RELAY ok"))
        assertNull(LogFilePolicy.epochOf("garbage line"))
        assertNull(LogFilePolicy.epochOf(""))
    }
}
