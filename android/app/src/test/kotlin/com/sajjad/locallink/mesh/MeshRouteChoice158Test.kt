package com.sajjad.locallink.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 158: route order, make-before-break, failover, relay hold, bridge tag. */
class MeshRouteChoice158Test {
    private val now = System.currentTimeMillis()

    private fun route(dest: String, hop: String, hops: Int, path: List<String>, seen: Long = now) =
        MeshRoute(dest, hop, hops, now + 60_000L, seen, seen, path)

    // ----------------------------------------------------- order (158.2)

    @Test fun `direct beats relayed and fewest hops goes first`() {
        val direct = route("z", "z", 1, listOf("me", "z"))
        val two = route("z", "a", 2, listOf("me", "a", "z"))
        val three = route("z", "b", 3, listOf("me", "b", "c", "z"))
        val order = MeshRouteChoicePolicy.order(listOf(three, two, direct))
        assertEquals(listOf("z", "a", "b"), order.map { it.nextHopNodeId })
    }

    @Test fun `same hops - LAN next hop before Wi-Fi Direct`() {
        val viaWd = route("z", "a", 2, listOf("me", "a", "z"))
        val viaLan = route("z", "b", 2, listOf("me", "b", "z"))
        val rank = mapOf("a" to MeshRouteChoicePolicy.RANK_WIFI_DIRECT, "b" to MeshRouteChoicePolicy.RANK_LAN)
        val order = MeshRouteChoicePolicy.order(listOf(viaWd, viaLan), { rank[it] ?: 2 })
        assertEquals(listOf("b", "a"), order.map { it.nextHopNodeId })
    }

    @Test fun `link ranks follow the transport`() {
        assertEquals(0, MeshRouteChoicePolicy.linkRank(MeshTransportPolicy.LAN))
        assertEquals(1, MeshRouteChoicePolicy.linkRank(MeshTransportPolicy.WIFI_DIRECT))
        assertEquals(2, MeshRouteChoicePolicy.linkRank(null))
    }

    // ------------------------------------------ make-before-break (158.3)

    @Test fun `a new shorter route waits until it is proven`() {
        val old = route("z", "a", 3, listOf("me", "a", "b", "z"))
        val fresh = route("z", "c", 2, listOf("me", "c", "z"))
        val provenHops = mutableSetOf("a")
        val before = MeshRouteChoicePolicy.order(listOf(fresh, old), proven = { it.nextHopNodeId in provenHops })
        assertEquals("a", before.first().nextHopNodeId)
        // The old one is still there as the backup.
        assertEquals(listOf("a", "c"), before.map { it.nextHopNodeId })
        provenHops += "c"
        val after = MeshRouteChoicePolicy.order(listOf(fresh, old), proven = { it.nextHopNodeId in provenHops })
        assertEquals(listOf("c", "a"), after.map { it.nextHopNodeId })
    }

    @Test fun `with nothing proven the new route is still used`() {
        val fresh = route("z", "c", 2, listOf("me", "c", "z"))
        assertEquals(listOf(fresh), MeshRouteChoicePolicy.order(listOf(fresh), proven = { false }))
    }

    @Test fun `a link is proven only by a pong after it connected`() {
        assertFalse(MeshRouteChoicePolicy.linkProven(connectedAt = 1_000L, lastPongAt = 1_000L))
        assertTrue(MeshRouteChoicePolicy.linkProven(connectedAt = 1_000L, lastPongAt = 1_050L))
    }

    @Test fun `the table keeps the old route when a better one arrives`() {
        val table = MeshRouteTable { "me" }
        assertTrue(table.upsert("z", route("z", "a", 3, listOf("me", "a", "b", "z"))))
        assertTrue(table.upsert("z", route("z", "c", 2, listOf("me", "c", "z"))))
        assertEquals(listOf("c", "a"), table.allFor("z").map { it.nextHopNodeId })
    }

    // ------------------------------------------------- failover (158.3)

    private class Recording(private val failFor: Set<String>) : MeshTransport {
        override val name = "test"
        val tried = mutableListOf<String>()
        override fun isPeerAvailable(nodeId: String) = true
        override fun send(peerNodeId: String, packet: MeshPacket): Boolean { tried += peerNodeId; return peerNodeId !in failFor }
        override fun disconnect(peerNodeId: String) {}
    }

    private fun packet(): MeshPacket = MeshPacket.new(
        sourceNodeId = "me", destinationNodeId = "z", type = "direct_message",
        payload = JSONObject().put("recipient_id", "z").put(MeshPacket.MESH_PATH_KEY, org.json.JSONArray().put("me")),
        ttl = MeshLimits.MAX_TTL,
    )

    private fun table(): MeshRouteTable = MeshRouteTable { "me" }.apply {
        upsert("z", route("z", "a", 2, listOf("me", "a", "z")))
        upsert("z", route("z", "b", 2, listOf("me", "b", "z")))
        upsert("z", route("z", "c", 3, listOf("me", "c", "d", "z")))
    }

    private fun peers(vararg ids: String) = MeshPeerRegistry().apply {
        ids.forEach { connected(it, MeshTransportPolicy.LAN); available(it, MeshTransportPolicy.LAN) }
    }

    @Test fun `router tries LAN first then fails over at once before the outbox`() {
        val transport = Recording(failFor = setOf("b", "a"))
        var queued = 0
        val rank = mapOf("a" to 1, "b" to 0, "c" to 0)
        val router = MeshRouter({ "me" }, table(), peers("a", "b", "c"), transport,
            enqueue = { queued++; true }, linkRank = { rank[it] ?: 2 })
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet()))
        assertEquals(listOf("b", "a", "c"), transport.tried)
        assertEquals(0, queued)
    }

    @Test fun `only when every route fails it goes to the outbox`() {
        val transport = Recording(failFor = setOf("a", "b", "c"))
        var queued = 0
        val router = MeshRouter({ "me" }, table(), peers("a", "b", "c"), transport, enqueue = { queued++; true })
        assertEquals(MeshRouteResult.QUEUED, router.route(packet()))
        assertEquals(3, transport.tried.size)
        assertEquals(1, queued)
    }

    @Test fun `router keeps a proven route first`() {
        val transport = Recording(failFor = emptySet())
        val router = MeshRouter({ "me" }, table(), peers("a", "b", "c"), transport,
            routeProven = { it.nextHopNodeId == "c" })
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet()))
        assertEquals(listOf("c"), transport.tried)
    }

    // ------------------------------------------------ relay hold (158.3)

    @Test fun `only someone else's sealed packet is a short relay hold`() {
        assertTrue(MeshRelayHoldPolicy.isRelayHold("bilal", "me", MeshRelayPolicy.SEALED))
        assertFalse(MeshRelayHoldPolicy.isRelayHold("me", "me", MeshRelayPolicy.SEALED))
        assertFalse(MeshRelayHoldPolicy.isRelayHold("bilal", "me", "direct_message"))
        assertFalse(MeshRelayHoldPolicy.isRelayHold("bilal", null, MeshRelayPolicy.SEALED))
    }

    @Test fun `relay hold is two minutes and has a size cap`() {
        assertEquals(1_000L + 120_000L, MeshRelayHoldPolicy.expiresAt(1_000L, 10_000_000L))
        assertEquals(50_000L, MeshRelayHoldPolicy.expiresAt(1_000L, 50_000L))
        assertTrue(MeshRelayHoldPolicy.admits(0, 0L, 1_000L))
        assertFalse(MeshRelayHoldPolicy.admits(MeshRelayHoldPolicy.MAX_PACKETS, 0L, 1L))
        assertFalse(MeshRelayHoldPolicy.admits(1, MeshRelayHoldPolicy.MAX_BYTES, 1L))
    }

    // ------------------------------------------------ bridge tag (158.1)

    @Test fun `bridge tag only for a phone in a group`() {
        val id = "0123456789abcdef"
        val member = NearbyTagPolicy.encode(id, host = false, member = true, members = 0, groupName = "DIRECT-LL-abc123", bridge = true)
        assertEquals("1", member["br"])
        val idle = NearbyTagPolicy.encode(id, host = false, member = false, members = 0, bridge = true)
        assertNull(idle["br"])
        val decoded = NearbyTagPolicy.decode("LocalLink._locallink._tcp.local.", member, "aa:bb:cc:dd:ee:ff", 5L)!!
        assertEquals(true, decoded["bridge"])
        val plain = NearbyTagPolicy.decode(null, NearbyTagPolicy.encode(id, true, false, 1), "aa:bb:cc:dd:ee:ff", 5L)!!
        assertNull(plain["bridge"])
    }
}
