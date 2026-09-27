package com.sajjad.locallink.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * AUDIT-012: verifies that application delivery is terminal-only while the
 * same canonical packet continues unchanged through relay nodes.
 */
class MeshFinalRecipientDeliveryTest {
    @Test
    fun aToBToCToDOnlyDCanReturnLocalDelivery() {
        val routes = mapOf(
            "A" to routeTable("A", "D", "B", listOf("A", "B", "D")),
            "B" to routeTable("B", "D", "C", listOf("A", "B", "C", "D")),
            "C" to routeTable("C", "D", "D", listOf("A", "B", "C", "D")),
            "D" to routeTable("D", "A", "A", emptyList()),
        )
        val peers = mapOf("A" to peers("B"), "B" to peers("C"), "C" to peers("D"), "D" to peers("C"))
        val sent = mutableListOf<Pair<String, MeshPacket>>()

        fun router(node: String, route: MeshRouteTable): MeshRouter = MeshRouter(
            localNodeId = { node },
            routeTable = route,
            peerRegistry = peers[node]!!,
            transport = object : MeshTransport {
                override val name: String = "test"
                override fun isPeerAvailable(nodeId: String): Boolean = peers[node]!!.isAvailable(nodeId)
                override fun send(peerNodeId: String, packet: MeshPacket): Boolean {
                    sent += peerNodeId to packet
                    return true
                }
                override fun disconnect(peerNodeId: String) = Unit
            },
        )

        val original = MeshPacket.new(
            sourceNodeId = "A",
            destinationNodeId = "D",
            type = "direct_message",
            payload = JSONObject().put("ciphertext", "opaque"),
            ttl = 8,
            packetId = "audit012-final-recipient",
            createdAt = System.currentTimeMillis(),
        )

        val a = router("A", routes["A"]!!)
        val b = router("B", routes["B"]!!)
        val c = router("C", routes["C"]!!)
        val d = router("D", routes["D"]!!)

        assertEquals(MeshRouteResult.FORWARDED, a.route(original))
        val atB = sent.removeFirst().second
        assertEquals("A", atB.sourceNodeId)
        assertEquals("D", atB.destinationNodeId)
        assertEquals("B", atB.nextHopNodeId)
        assertEquals(1, atB.hopCount)
        assertEquals(MeshRouteResult.FORWARDED, b.route(atB, incomingPeerId = "A"))
        val atC = sent.removeFirst().second
        assertEquals("A", atC.sourceNodeId)
        assertEquals("D", atC.destinationNodeId)
        assertEquals("C", atC.nextHopNodeId)
        assertEquals(2, atC.hopCount)
        assertEquals(MeshRouteResult.FORWARDED, c.route(atC, incomingPeerId = "B"))
        val atD = sent.removeFirst().second
        assertEquals("A", atD.sourceNodeId)
        assertEquals("D", atD.destinationNodeId)
        assertEquals("D", atD.nextHopNodeId)
        assertEquals(3, atD.hopCount)

        // Relays never reach LOCAL_DELIVERY; only the final destination does.
        assertEquals(MeshRouteResult.LOCAL_DELIVERY, d.route(atD, incomingPeerId = "C"))
        assertTrue(sent.isEmpty())
        assertEquals(true, MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "D", "D"))
        assertEquals(false, MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "D", "B"))
        assertEquals(false, MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "D", "C"))
    }

    private fun routeTable(local: String, destination: String, nextHop: String, path: List<String>): MeshRouteTable {
        val table = MeshRouteTable { local }
        if (path.isNotEmpty()) {
            table.upsert(
                destination,
                MeshRoute(
                    destinationNodeId = destination,
                    nextHopNodeId = nextHop,
                    hopCount = path.size - 1,
                    expiresAt = Long.MAX_VALUE,
                    lastSeenAt = 1L,
                    routeVersion = 1L,
                    path = path,
                ),
            )
        }
        return table
    }

    private fun peers(vararg ids: String): MeshPeerRegistry {
        val peers = MeshPeerRegistry()
        ids.forEachIndexed { index, id -> peers.connected(id, "test", index.toLong() + 1L) }
        return peers
    }
}
