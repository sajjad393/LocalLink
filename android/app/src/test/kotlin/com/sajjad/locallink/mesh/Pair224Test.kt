package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import com.sajjad.locallink.mesh.PairEndpointWait.Step

/** Bundle 224 (C): Add contact over Wi-Fi Direct failed at once with "not visible yet". */
class Pair224Test {
    @Test fun `224-C1 wait up to 10 s for the other phone's beacon`() {
        assertEquals(Step.WAIT, PairEndpointWait.next(0L, false))
        assertEquals(Step.WAIT, PairEndpointWait.next(9_500L, false))
        assertEquals(Step.GIVE_UP, PairEndpointWait.next(10_000L, false))
        assertEquals(Step.SEND, PairEndpointWait.next(0L, true))
        assertEquals(Step.SEND, PairEndpointWait.next(9_500L, true))
        assertEquals(500L, PairEndpointWait.STEP_MS)
    }

    @Test fun `224-C1 after a give-up fail fast for 30 s (the app retries 4 times)`() {
        assertTrue("never gave up", PairEndpointWait.mayWait(0L, 1_000_000L))
        assertFalse(PairEndpointWait.mayWait(1_000_000L, 1_010_000L))
        assertFalse(PairEndpointWait.mayWait(1_000_000L, 1_029_999L))
        assertTrue(PairEndpointWait.mayWait(1_000_000L, 1_030_000L))
        assertTrue("clock went back", PairEndpointWait.mayWait(1_000_000L, 900_000L))
    }

    @Test fun `224-C1 same error text, one waiter per phone, found is logged`() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(src.contains("\"peer is not visible on the local network yet — wait for it to appear under On this network\""))
        assertTrue(src.contains("pair-packet endpoint found after_ms="))
        val body = src.substringAfter("private fun waitForPairEndpoint(").substringBefore("private fun sendPairDatagrams(")
        assertTrue("a second tap joins the running wait", body.contains("if (list != null) { list.add(PendingPair(pair, body, cb)); return true }"))
        assertTrue("our beacon goes out first", body.indexOf("broadcastLanBeacon(") < body.indexOf("PairEndpointWait.next("))
    }
}
