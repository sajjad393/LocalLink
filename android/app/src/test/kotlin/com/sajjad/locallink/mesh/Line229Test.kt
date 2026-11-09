package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader
import java.io.StringReader
import java.net.SocketTimeoutException

/** Bundle 229 (S1): size limits for the nearby link sockets. */
class Line229Test {
    private fun r(text: String, buf: Int = 8192) = BoundedLineReader(StringReader(text), buf)

    @Test
    fun readsLinesLikeBufferedReader() {
        for (buf in listOf(1, 2, 3, 8192)) {
            val x = r("a\nbb\r\nccc\rdd\n\neee", buf)
            assertEquals("a", x.readLine(100))
            assertEquals("bb", x.readLine(100))
            assertEquals("ccc", x.readLine(100))
            assertEquals("dd", x.readLine(100))
            assertEquals("", x.readLine(100))
            assertFalse(x.droppedLast)
            assertEquals("eee", x.readLine(100))
            assertNull(x.readLine(100))
            assertNull(x.readLine(100))
        }
    }

    @Test
    fun crLfSplitAcrossChunks() {
        val x = r("ab\r\ncd\n", 3) // "ab\r" | "\ncd" | "\n"
        assertEquals("ab", x.readLine(10))
        assertEquals("cd", x.readLine(10))
        assertNull(x.readLine(10))
    }

    @Test
    fun emptyStreamIsNull() {
        assertNull(r("").readLine(10))
    }

    @Test
    fun exactlyKeepMaxIsKept() {
        val x = r("12345\n")
        assertEquals("12345", x.readLine(5, 50))
        assertFalse(x.droppedLast)
    }

    @Test
    fun longerThanKeepIsSkippedAndTheLinkGoesOn() {
        for (buf in listOf(2, 4, 8192)) {
            val x = r("123456\nok\n", buf)
            assertEquals("", x.readLine(5, 50))
            assertTrue(x.droppedLast)
            assertEquals(6L, x.droppedLastChars)
            assertEquals("ok", x.readLine(5, 50))
            assertFalse(x.droppedLast)
            assertNull(x.readLine(5, 50))
        }
    }

    @Test
    fun skippedLineAtEndOfStream() {
        val x = r("1234567")
        assertEquals("", x.readLine(5, 50))
        assertTrue(x.droppedLast)
        assertNull(x.readLine(5, 50))
    }

    @Test
    fun pastHardMaxThrows() {
        val x = r("x".repeat(60) + "\n", 4)
        try {
            x.readLine(5, 50)
            fail("expected LineTooLongException")
        } catch (e: LineTooLongException) {
            assertEquals(50, e.max)
            assertTrue(e.chars > 50)
        }
    }

    @Test
    fun handshakeLimitThrowsJustPastIt() {
        val ok = r("y".repeat(LineLimits.HANDSHAKE_MAX_CHARS) + "\n")
        assertEquals(LineLimits.HANDSHAKE_MAX_CHARS, ok.readLine(LineLimits.HANDSHAKE_MAX_CHARS)!!.length)
        val bad = r("y".repeat(LineLimits.HANDSHAKE_MAX_CHARS + 1) + "\n")
        try {
            bad.readLine(LineLimits.HANDSHAKE_MAX_CHARS)
            fail("expected LineTooLongException")
        } catch (_: LineTooLongException) {
        }
    }

    /** A sender that never sends a newline: stopped at the hard limit, never kept. */
    @Test
    fun endlessLineIsStopped() {
        val endless = object : Reader() {
            override fun read(cbuf: CharArray, off: Int, len: Int): Int {
                java.util.Arrays.fill(cbuf, off, off + len, 'a')
                return len
            }
            override fun close() {}
        }
        val x = BoundedLineReader(endless)
        try {
            x.readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS)
            fail("expected LineTooLongException")
        } catch (e: LineTooLongException) {
            assertTrue(e.chars > LineLimits.DATA_HARD_MAX_CHARS)
        }
    }

    /** Real traffic sizes: a 200 KB video packet line is kept as before. */
    @Test
    fun realVideoLineIsKept() {
        val line = "{\"type\":\"data\",\"payload\":\"" + "v".repeat(200 * 1024) + "\"}"
        val x = r(line + "\n{\"type\":\"ping\"}\n")
        assertEquals(line, x.readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS))
        assertEquals("{\"type\":\"ping\"}", x.readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS))
    }

    /** The old loop dropped lines over 256 KB too: same result, without keeping them. */
    @Test
    fun over256kIsDroppedLikeBefore() {
        val x = r("z".repeat(256 * 1024 + 1) + "\nnext\n")
        assertEquals("", x.readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS))
        assertTrue(x.droppedLast)
        assertEquals("next", x.readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS))
    }

    /** Urdu text arriving one byte at a time (UTF-8 split everywhere). */
    @Test
    fun utf8OneByteAtATime() {
        val text = "سلام دوست\nLinkUp ✓\n"
        val bytes = text.toByteArray(Charsets.UTF_8)
        val slow = object : InputStream() {
            var i = 0
            override fun read(): Int = if (i < bytes.size) bytes[i++].toInt() and 0xFF else -1
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (len == 0) return 0
                val c = read()
                if (c < 0) return -1
                b[off] = c.toByte()
                return 1
            }
        }
        val x = BoundedLineReader(InputStreamReader(slow, Charsets.UTF_8), 2)
        assertEquals("سلام دوست", x.readLine(100))
        assertEquals("LinkUp ✓", x.readLine(100))
        assertNull(x.readLine(100))
        val y = BoundedLineReader(InputStreamReader(ByteArrayInputStream(bytes), Charsets.UTF_8))
        assertEquals("سلام دوست", y.readLine(100))
    }

    /** A read timeout in the middle of a line keeps what was read. */
    @Test
    fun timeoutKeepsThePartialLine() {
        val parts = ArrayDeque(listOf("hel", "!timeout", "lo\nnext\n"))
        val flaky = object : Reader() {
            override fun read(cbuf: CharArray, off: Int, len: Int): Int {
                val p = parts.removeFirstOrNull() ?: return -1
                if (p == "!timeout") throw SocketTimeoutException("quiet")
                p.toCharArray().copyInto(cbuf, off)
                return p.length
            }
            override fun close() {}
        }
        val x = BoundedLineReader(flaky)
        try {
            x.readLine(100)
            fail("expected timeout")
        } catch (_: SocketTimeoutException) {
        }
        assertEquals("hello", x.readLine(100))
        assertEquals("next", x.readLine(100))
        assertNull(x.readLine(100))
    }

    @Test
    fun handshakeGate() {
        assertTrue(LineLimits.handshakeAllowed(1))
        assertTrue(LineLimits.handshakeAllowed(LineLimits.MAX_PENDING_HANDSHAKES))
        assertFalse(LineLimits.handshakeAllowed(LineLimits.MAX_PENDING_HANDSHAKES + 1))
    }

    @Test
    fun limitsAreFarAboveRealTraffic() {
        assertEquals(256 * 1024, LineLimits.DATA_KEEP_MAX_CHARS)
        assertTrue(LineLimits.DATA_HARD_MAX_CHARS >= 8 * 1024 * 1024)
        assertTrue(LineLimits.HANDSHAKE_MAX_CHARS >= 16 * 1024)
    }

    /** The service reads every nearby socket line through the limits. */
    @Test
    fun serviceUsesTheLimits() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        val code = src.lines().filterNot { val t = it.trim(); t.startsWith("//") || t.startsWith("*") }.joinToString("\n")
        assertFalse("a socket line is read without a limit", code.contains(".readLine()"))
        assertFalse(code.contains("BufferedReader(InputStreamReader(socket"))
        assertEquals(2, Regex("BoundedLineReader\\(InputStreamReader\\(socket\\.getInputStream\\(\\)").findAll(code).count())
        assertEquals(4, Regex("readLine\\(LineLimits\\.HANDSHAKE_MAX_CHARS\\)").findAll(code).count())
        assertTrue(code.contains("readLine(LineLimits.DATA_KEEP_MAX_CHARS, LineLimits.DATA_HARD_MAX_CHARS)"))
        assertTrue(code.contains("val reader: BoundedLineReader,"))
        assertTrue(code.contains("if (connection.reader.droppedLast) { noteVideoDrop(\"wire_line_over_256k\"); continue }"))
        assertTrue(code.contains("exitCause = \"line_too_long\""))
        assertTrue(code.contains("LineLimits.handshakeAllowed(pendingHandshakes.incrementAndGet())"))
    }
}
