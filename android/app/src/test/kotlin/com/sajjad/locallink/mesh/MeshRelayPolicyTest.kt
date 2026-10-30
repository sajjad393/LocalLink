package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.json.JSONObject
import org.junit.Test

class MeshRelayPolicyTest {
    @Test fun `contacts are accepted as before`() {
        assertEquals(MeshRelayPolicy.TRUST_CONTACT, MeshRelayPolicy.trustFor("bilal", isContact = true, isBlocked = false, peerOffersRelay = false, relayLinks = 99))
    }

    @Test fun `a stranger is only a relay when it offers relaying and there is room`() {
        assertEquals(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.trustFor("bilal", isContact = false, isBlocked = false, peerOffersRelay = true, relayLinks = 0))
        assertNull(MeshRelayPolicy.trustFor("old", isContact = false, isBlocked = false, peerOffersRelay = false, relayLinks = 0))
        assertNull(MeshRelayPolicy.trustFor("bilal", isContact = false, isBlocked = false, peerOffersRelay = true, relayLinks = MeshRelayPolicy.MAX_RELAY_LINKS))
    }

    @Test fun `a blocked or paused user is never a relay`() {
        assertNull(MeshRelayPolicy.trustFor("spam", isContact = false, isBlocked = true, peerOffersRelay = true, relayLinks = 0))
        assertNull(MeshRelayPolicy.trustFor("spam", isContact = false, isBlocked = false, peerOffersRelay = true, relayLinks = 0, isPaused = true))
    }

    @Test fun `a relay link carries sealed packets only`() {
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED))
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED_LIVE))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "direct_message"))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "direct_file_chunk"))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "call_media"))
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_CONTACT, "direct_message"))
    }

    @Test fun `only one side dials a stranger`() {
        assertTrue(MeshRelayPolicy.shouldDialRelay("aaa", "bbb"))
        assertFalse(MeshRelayPolicy.shouldDialRelay("bbb", "aaa"))
    }

    @Test fun `a flood pauses the relay for ten minutes`() {
        val limiter = MeshRelayRateLimiter(maxPackets = 3, maxBytes = 1_000L, pauseMs = 600_000L)
        assertTrue(limiter.allow("bilal", 10, now = 0L))
        assertTrue(limiter.allow("bilal", 10, now = 1L))
        assertTrue(limiter.allow("bilal", 10, now = 2L))
        assertFalse(limiter.allow("bilal", 10, now = 3L))
        assertTrue(limiter.isPaused("bilal", now = 599_999L))
        assertFalse(limiter.isPaused("bilal", now = 600_004L))
        assertTrue(limiter.allow("bilal", 10, now = 600_004L))
    }

    @Test fun `too many bytes also pauses`() {
        val limiter = MeshRelayRateLimiter(maxPackets = 100, maxBytes = 100L)
        assertTrue(limiter.allow("bilal", 60, now = 0L))
        assertFalse(limiter.allow("bilal", 60, now = 1L))
    }

    @Test fun `a new minute starts a new window`() {
        val limiter = MeshRelayRateLimiter(maxPackets = 2, maxBytes = 1_000L)
        assertTrue(limiter.allow("bilal", 1, now = 0L))
        assertTrue(limiter.allow("bilal", 1, now = 1L))
        assertTrue(limiter.allow("bilal", 1, now = 60_001L))
    }

    private class RecordingTransport : MeshTransport {
        override val name = "test"
        val sentVia = mutableListOf<String>()
        var failures = 0
        override fun isPeerAvailable(nodeId: String) = true
        override fun send(peerNodeId: String, packet: MeshPacket): Boolean { sentVia += peerNodeId; return true }
        override fun disconnect(peerNodeId: String) {}
        override fun onRouteFailure(destinationNodeId: String, failedNextHopNodeId: String) { failures++ }
    }

    private fun routerWithRelay(transport: RecordingTransport): MeshRouter {
        val now = System.currentTimeMillis()
        val table = MeshRouteTable { "yasir" }
        // Best route to Zulfqar is through Bilal (relay, 2 hops); a longer
        // one goes through Sajjad (contact, 3 hops).
        table.upsert("zulfqar", MeshRoute("zulfqar", "bilal", 2, now + 60_000L, now, now, listOf("yasir", "bilal", "zulfqar")))
        table.upsert("zulfqar", MeshRoute("zulfqar", "sajjad", 3, now + 60_000L, now, now, listOf("yasir", "sajjad", "x1", "zulfqar")))
        val peers = MeshPeerRegistry()
        peers.connected("bilal", MeshTransportPolicy.LAN); peers.available("bilal", MeshTransportPolicy.LAN)
        peers.connected("sajjad", MeshTransportPolicy.LAN); peers.available("sajjad", MeshTransportPolicy.LAN)
        val trust = mapOf("bilal" to MeshRelayPolicy.TRUST_RELAY, "sajjad" to MeshRelayPolicy.TRUST_CONTACT)
        return MeshRouter({ "yasir" }, table, peers, transport, null, MeshLimits.MAX_TTL) { peer, packet ->
            MeshRelayPolicy.canCarry(trust[peer] ?: MeshRelayPolicy.TRUST_CONTACT, packet.type)
        }
    }

    @Test fun `router sends sealed packets through the relay`() {
        val transport = RecordingTransport()
        val packet = MeshPacket.new("yasir", "zulfqar", MeshRelayPolicy.SEALED, JSONObject().put("c", "x"), MeshLimits.MAX_TTL)
        assertEquals(MeshRouteResult.FORWARDED, routerWithRelay(transport).route(packet))
        assertEquals(listOf("bilal"), transport.sentVia)
    }

    @Test fun `router never sends plain packets through the relay`() {
        val transport = RecordingTransport()
        val packet = MeshPacket.new("yasir", "zulfqar", "direct_message", JSONObject().put("body", "hi"), MeshLimits.MAX_TTL)
        assertEquals(MeshRouteResult.FORWARDED, routerWithRelay(transport).route(packet))
        assertEquals(listOf("sajjad"), transport.sentVia)
        assertEquals("skipping a relay is not a route failure", 0, transport.failures)
    }
}
