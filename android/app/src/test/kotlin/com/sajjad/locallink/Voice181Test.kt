package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 181: joining voice note parts (pause / continue). */
class Voice181Test {
    @Test fun `one AAC frame at 44100 Hz is about 23 ms`() {
        assertEquals(23_219L, VoiceJoinPolicy.frameUs(44_100))
        assertEquals(23_220L, VoiceJoinPolicy.frameUs(0))
    }

    @Test fun `parts follow each other with no gap and no overlap`() {
        val frame = VoiceJoinPolicy.frameUs(44_100)
        // part 1: samples 0 .. 2_000_000 us, part 2: 0 .. 1_000_000 us
        val off2 = VoiceJoinPolicy.nextOffsetUs(0L, 2_000_000L, frame)
        assertEquals(2_000_000L + frame, off2)
        val firstOfPart2 = VoiceJoinPolicy.sampleTimeUs(off2, 0L)
        assertTrue(firstOfPart2 > 2_000_000L)
        assertEquals(frame, firstOfPart2 - 2_000_000L)
        val off3 = VoiceJoinPolicy.nextOffsetUs(off2, 1_000_000L, frame)
        assertEquals(off2 + 1_000_000L + frame, off3)
    }

    @Test fun `negative sample times never go before the part start`() {
        assertEquals(500L, VoiceJoinPolicy.sampleTimeUs(500L, -40L))
        assertEquals(501L, VoiceJoinPolicy.nextOffsetUs(500L, -40L, 0L))
    }

    @Test fun `empty or missing parts are skipped, order kept`() {
        val parts = listOf("a.m4a" to 100L, "b.m4a" to 0L, "" to 50L, "c.m4a" to 7L)
        assertEquals(listOf("a.m4a", "c.m4a"), VoiceJoinPolicy.usableParts(parts))
        assertEquals(listOf("x.m4a"), VoiceJoinPolicy.usableParts(listOf("x.m4a" to 1L)))
        assertTrue(VoiceJoinPolicy.usableParts(listOf("y.m4a" to 0L)).isEmpty())
    }
}
