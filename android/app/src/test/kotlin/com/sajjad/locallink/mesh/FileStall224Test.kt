package com.sajjad.locallink.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 224 (G2): "RELAY file stalled" wrote a line every ~20 s for 11 h. */
class FileStall224Test {
    private val min = 60_000L

    @Test fun `224-G2 the first stalls are logged as before`() {
        for (n in 1..FileStallLog224.FIRST_LINES) {
            assertTrue("stall $n", FileStallLog224.shouldLog(n, 5_000L, 6_000L))
        }
    }

    @Test fun `224-G2 after that one line per 10 min`() {
        val n = FileStallLog224.FIRST_LINES + 1
        assertTrue("never logged after the first lines", FileStallLog224.shouldLog(n, 0L, 100 * min))
        assertFalse(FileStallLog224.shouldLog(n, 100 * min, 105 * min))
        assertFalse(FileStallLog224.shouldLog(n + 50, 100 * min, 109 * min))
        assertTrue(FileStallLog224.shouldLog(n + 60, 100 * min, 110 * min))
        assertTrue("clock went back", FileStallLog224.shouldLog(n, 100 * min, 50 * min))
    }

    @Test fun `224-G2 only the log is throttled, the resend still runs`() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        val body = src.substringAfter("private fun noteFileStall(").substringBefore("override fun onDestroy")
        assertTrue(body.contains("FileStallLog224.shouldLog("))
        assertTrue("counting and switching unchanged", body.contains("fileStalls.merge(t.transferId,1,Int::plus)"))
        assertTrue(body.contains("FileSealPolicy.flipFor(stalls)"))
    }
}
