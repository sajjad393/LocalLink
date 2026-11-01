package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 188 (B3): what LinkUp was doing when it was killed. */
class Exit188Test {
    private val main = File("main/kotlin/com/sajjad/locallink")
    private val t = 1_793_548_900L // seconds

    @Test fun `note is short plain text`() {
        val n = ProcessStateNote.summary(true, 2, 1, t)
        assertEquals("v1 call=1 fin=2 fout=1 fat=$t", n)
        assertTrue(n.toByteArray().size <= ProcessStateNote.MAX_BYTES)
        assertEquals("v1 call=0 fin=99 fout=0 fat=0", ProcessStateNote.summary(false, 500, -3, -5))
    }

    @Test fun `doing names the call and recent files`() {
        val exitMs = (t + 20) * 1000L
        assertEquals("call", ProcessStateNote.doing("v1 call=1 fin=0 fout=0 fat=0", exitMs))
        assertEquals("file_in", ProcessStateNote.doing("v1 call=0 fin=1 fout=0 fat=$t", exitMs))
        assertEquals("call+file_in+file_out", ProcessStateNote.doing("v1 call=1 fin=1 fout=2 fat=$t", exitMs))
        assertEquals("none", ProcessStateNote.doing("v1 call=0 fin=0 fout=0 fat=0", exitMs))
    }

    @Test fun `a file that stopped moving long before the death does not count`() {
        val exitMs = (t + 61) * 1000L
        assertEquals("none", ProcessStateNote.doing("v1 call=0 fin=1 fout=1 fat=$t", exitMs))
        assertEquals("file_out", ProcessStateNote.doing("v1 call=0 fin=0 fout=1 fat=$t", (t + 60) * 1000L))
    }

    @Test fun `no note or a strange note is a dash`() {
        assertEquals("-", ProcessStateNote.doing(null, 0L))
        assertEquals("-", ProcessStateNote.doing("", 0L))
        assertEquals("-", ProcessStateNote.doing("hello", 0L))
        assertEquals("none", ProcessStateNote.doing("v1 call=x fin=? fat=", 0L))
    }

    @Test fun `note is written only on a change or every 10 s of file activity`() {
        assertTrue(ProcessStateNote.shouldWrite(null, false, 0, 0, 0))
        val last = ProcessStateNote.summary(false, 1, 0, t)
        assertFalse(ProcessStateNote.shouldWrite(last, false, 1, 0, t))
        assertFalse(ProcessStateNote.shouldWrite(last, false, 1, 0, t + 9))
        assertTrue(ProcessStateNote.shouldWrite(last, false, 1, 0, t + 10))
        assertTrue(ProcessStateNote.shouldWrite(last, true, 1, 0, t + 1))
        assertTrue(ProcessStateNote.shouldWrite(last, false, 0, 0, t + 1))
    }

    @Test fun `exit line gets doing before the text, old form unchanged`() {
        val line = AppHealthPolicy.exitLine(10, 125, 1_000_000L, 1_065_000L, 150_000L, 210_000L, "by superkiller", "call+file_out")
        assertEquals("APP_LAST_EXIT reason=force_stop code=10 was=service ago_s=65 mem_mb=146 rss_mb=205 " +
            "doing=call+file_out text=by superkiller", line)
        assertFalse(AppHealthPolicy.exitLine(3, 400, 0, 0, 0, 0, null).contains("doing="))
    }

    @Test fun `wiring - note is set and read back`() {
        val health = File(main, "AppHealth.kt").readText()
        assertTrue(health.contains("am.setProcessStateSummary("))
        assertTrue(health.contains("e.processStateSummary?.toString(Charsets.US_ASCII)"))
        assertTrue(health.contains("ProcessStateNote.doing(note, e.timestamp)"))
        val s = File(main, "LocalLinkTransportService.kt").readText()
        assertTrue(s.contains("if (type.startsWith(\"file_\")) noteFileState(type)"))
        assertTrue(s.contains("AppHealth.noteCall(true)"))
        assertTrue(s.contains("AppHealth.noteCall(false)"))
    }
}
