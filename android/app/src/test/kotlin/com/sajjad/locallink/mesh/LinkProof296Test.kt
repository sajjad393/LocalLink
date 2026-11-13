package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 296 (H1): a link is proven only by a fresh own pong (or bulk data in). */
class LinkProof296Test {
    private val t0 = 1_700_000_000_000L

    @Test
    fun freshPongProves() {
        assertTrue(LinkProof296.proven(t0 + 12_000, t0, t0 + 5_000, 0L))
        assertTrue("10 s is still proven", LinkProof296.proven(t0 + 15_000, t0, t0 + 5_000, 0L))
        assertFalse("10 s + 1 ms is not", LinkProof296.proven(t0 + 15_001, t0, t0 + 5_000, 0L))
    }

    @Test
    fun noPongSinceConnectIsNotProof() {
        // lastPongAt starts at connectedAt: no answer came yet.
        assertFalse(LinkProof296.proven(t0 + 1_000, t0, t0, 0L))
        assertEquals(0L, LinkProof296.lastPong(t0, t0))
        assertEquals(t0 + 5_000, LinkProof296.lastPong(t0, t0 + 5_000))
    }

    @Test
    fun bulkDataInProvesABusyLink() {
        assertTrue(LinkProof296.proven(t0 + 30_000, t0, t0 + 5_000, t0 + 25_000))
        assertFalse(LinkProof296.proven(t0 + 40_000, t0, t0 + 5_000, t0 + 25_000))
    }

    @Test
    fun snapshotCarriesProofAndCloseRuleUnchanged() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(src.contains("\"proven\" to open.any { LinkProof296.proven(proofNow, it.connectedAt, it.lastPongAt, it.lastBulkInAt) }"))
        assertTrue(src.contains("\"last_pong_at\" to"))
        assertTrue(src.contains("if (line.length >= LinkProof296.BULK_LINE_CHARS) connection.lastBulkInAt = connection.lastSeenAt"))
        val policy = File("main/kotlin/com/sajjad/locallink/mesh/MeshTransportPolicy.kt").readText()
        assertTrue("5 s ping unchanged", policy.contains("HEARTBEAT_INTERVAL_MS: Long = 5_000L"))
        assertTrue("15 s close rule unchanged", policy.contains("HEARTBEAT_TIMEOUT_MS: Long = 15_000L"))
        // Routing still uses its own proof (not the 10 s map flag).
        assertTrue(src.contains("MeshRouteChoicePolicy.linkProven(it.connectedAt, it.lastPongAt)"))
    }
}
