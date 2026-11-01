package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 179: voice delay rules, files pause during calls, saved Accept, call alerts. */
class Call179Test {
    // ---- 1. voice delay ----
    // Bundle 184: the receive-line cut tests moved to Voice184Test (the
    // 179 cut rule itself is gone).

    @Test fun `sending line never holds more than 60 ms`() {
        var q = 0
        repeat(50) { q -= CallAudioLatencyPolicy.txFramesToDrop(q); q++ }
        assertEquals(CallAudioLatencyPolicy.TX_MAX_FRAMES, q)
        assertEquals(60, CallAudioLatencyPolicy.queueMs(q))
        assertEquals(0, CallAudioLatencyPolicy.txFramesToDrop(0))
        assertEquals(0, CallAudioLatencyPolicy.txFramesToDrop(2))
        assertEquals(1, CallAudioLatencyPolicy.txFramesToDrop(3))
        assertEquals(3, CallAudioLatencyPolicy.txFramesToDrop(5))
    }

    @Test fun `speaker and mic buffers are about 80 ms unless Android needs more`() {
        val frame = 640 // 20 ms of 16 kHz mono 16-bit
        assertEquals(2560, CallAudioLatencyPolicy.speakerBufferBytes(1000, frame))
        assertEquals(2560, CallAudioLatencyPolicy.micBufferBytes(1280, frame))
        assertEquals(4000, CallAudioLatencyPolicy.speakerBufferBytes(4000, frame))
        assertTrue(CallAudioLatencyPolicy.speakerBufferBytes(0, frame) < frame * 12)
        assertTrue(CallAudioLatencyPolicy.micBufferBytes(0, frame) < frame * 8)
    }

    @Test fun `speaker backlog in ms`() {
        assertEquals(80, CallAudioLatencyPolicy.speakerBacklogMs(16_000L + 1280L, 16_000L, 16_000))
        assertEquals(0, CallAudioLatencyPolicy.speakerBacklogMs(100L, 200L, 16_000))
        assertEquals(0, CallAudioLatencyPolicy.speakerBacklogMs(100L, 0L, 0))
    }

    @Test fun `delay log every 10 s`() {
        assertTrue(CallAudioLatencyPolicy.logDue(5_000L, 0L))
        assertFalse(CallAudioLatencyPolicy.logDue(15_000L, 6_000L))
        assertTrue(CallAudioLatencyPolicy.logDue(16_000L, 6_000L))
        assertTrue(CallAudioLatencyPolicy.logDue(1_000L, 6_000L)) // clock went back
        assertEquals("CALL_AUDIO_DELAY call=c1 rx_queue_ms=60 speaker_ms=80 tx_queue_ms=20 skipped=4",
            CallAudioLatencyPolicy.delayLogLine("c1", 60, 80, 20, 4L))
    }

    // ---- 1.6 files wait during a call ----
    @Test fun `no call never pauses a file`() {
        assertFalse(CallFilePausePolicy.shouldPause(false, null, 1_000L))
        assertFalse(CallFilePausePolicy.shouldPause(false, 500L, 1_000L))
    }

    @Test fun `live call pauses until the limit then never again in that call`() {
        assertTrue(CallFilePausePolicy.shouldPause(true, null, 1_000L))
        assertTrue(CallFilePausePolicy.shouldPause(true, 1_000L, 1_000L + CallFilePausePolicy.MAX_PAUSE_MS - 1L))
        assertFalse(CallFilePausePolicy.shouldPause(true, 1_000L, 1_000L + CallFilePausePolicy.MAX_PAUSE_MS))
        assertFalse(CallFilePausePolicy.shouldPause(true, -1L, 5_000L))
        assertTrue(CallFilePausePolicy.shouldPause(true, 9_000L, 5_000L)) // clock went back
    }

    @Test fun `pause limit stays under the other phone's 10 minute forget time`() {
        assertTrue(CallFilePausePolicy.MAX_PAUSE_MS < DirectFileTransferPolicy.IDLE_TIMEOUT_MS)
    }

    // ---- 2. saved Accept ----
    @Test fun `saved Accept lives 60 s`() {
        assertTrue(CallAcceptPolicy.valid(1_000L, 1_000L))
        assertTrue(CallAcceptPolicy.valid(1_000L, 61_000L))
        assertFalse(CallAcceptPolicy.valid(1_000L, 61_001L))
        assertFalse(CallAcceptPolicy.valid(0L, 10L))
        assertFalse(CallAcceptPolicy.valid(5_000L, 1_000L)) // clock went back
        assertEquals(45_000L, CallAcceptPolicy.remainingMs(1_000L, 16_000L))
        assertEquals(0L, CallAcceptPolicy.remainingMs(1_000L, 70_000L))
    }

    @Test fun `saved Accept answers only the same call from the same caller`() {
        assertTrue(CallAcceptPolicy.matches("c1", "p1", "c1", "p1"))
        assertFalse(CallAcceptPolicy.matches("c1", "p1", "c2", "p1"))
        assertFalse(CallAcceptPolicy.matches("c1", "p1", "c1", "p2"))
        assertFalse(CallAcceptPolicy.matches("", "", "", ""))
    }

    // ---- 3. call alerts ----
    @Test fun `call alert state`() {
        assertEquals(CallAlertPolicy.PERMISSION, CallAlertPolicy.state(false, true, 4, true))
        assertEquals(CallAlertPolicy.APP_OFF, CallAlertPolicy.state(true, false, 4, true))
        assertEquals(CallAlertPolicy.CATEGORY_OFF, CallAlertPolicy.state(true, true, 0, true))
        assertEquals(CallAlertPolicy.CATEGORY_OFF, CallAlertPolicy.state(true, true, 2, true))
        assertEquals(CallAlertPolicy.OK, CallAlertPolicy.state(true, true, 3, true))
        assertEquals(CallAlertPolicy.LOCKSCREEN_OFF, CallAlertPolicy.state(true, true, 4, false))
        assertEquals(CallAlertPolicy.OK, CallAlertPolicy.state(true, true, null, null))
    }

    @Test fun `blocked states still ring but post nothing`() {
        assertTrue(CallAlertPolicy.blocked(CallAlertPolicy.PERMISSION))
        assertTrue(CallAlertPolicy.blocked(CallAlertPolicy.APP_OFF))
        assertTrue(CallAlertPolicy.blocked(CallAlertPolicy.CATEGORY_OFF))
        assertFalse(CallAlertPolicy.blocked(CallAlertPolicy.LOCKSCREEN_OFF))
        assertFalse(CallAlertPolicy.blocked(CallAlertPolicy.OK))
    }

    @Test fun `full screen only when Android allows it - Realme fix`() {
        assertEquals(CallAlertPolicy.MODE_POPUP, CallAlertPolicy.mode(false))
        assertEquals(CallAlertPolicy.MODE_FULL_SCREEN, CallAlertPolicy.mode(true))
        assertEquals(CallAlertPolicy.MODE_FULL_SCREEN, CallAlertPolicy.mode(null))
    }
}
