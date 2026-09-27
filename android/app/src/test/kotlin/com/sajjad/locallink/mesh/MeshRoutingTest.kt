package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRoutingTest {

    @Test
    fun packetIdStaysIdenticalAcrossEveryForwardingHop() {
        var packet = MeshPacket.new("A", "I", "direct_message", JSONObject(), 8, packetId = "packet-stable", createdAt = System.currentTimeMillis())
        val expectedTtls = listOf(7, 6, 5, 4, 3, 2, 1, 0)
        val nodes = listOf("B", "C", "D", "E", "F", "G", "H", "I")
        nodes.forEachIndexed { index, node ->
            val relay = if (index == 0) "A" else nodes[index - 1]
            val forwarded = packet.copyForForwarding(node, relay)
            assertEquals("packet-stable", forwarded.packetId)
            assertEquals(expectedTtls[index], forwarded.ttl)
            assertEquals(index + 1, forwarded.hopCount)
            packet = forwarded
        }
        assertEquals(0, packet.ttl)
        assertEquals(8, packet.hopCount)
    }

    @Test
    fun zeroTtlIsAcceptedOnlyForFinalDeliveryAtMaximumHopCount() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = true
            override fun send(peerNodeId: String, packet: MeshPacket) = false
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "I" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "I", "direct_message", JSONObject(), 0, packetId = "packet-final", createdAt = System.currentTimeMillis())
            .copy(hopCount = 8)
        assertEquals(MeshRouteResult.LOCAL_DELIVERY, router.route(packet))
    }

    @Test
    fun zeroTtlCannotBeForwardedByRelay() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("C", "test", 1L)
        table.upsert("D", MeshRoute("D", "C", 1, Long.MAX_VALUE, 1L, 10L, listOf("B", "C", "D")))
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "B" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "packet-expired", createdAt = System.currentTimeMillis()).copy(ttl = 0, hopCount = 7)
        assertEquals(MeshRouteResult.DROPPED, router.route(packet))
    }

    @Test
    fun malformedPacketDoesNotPassIncomingValidation() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = true
            override fun send(peerNodeId: String, packet: MeshPacket) = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "B" }, table, peers, transport, maxHops = 8)
        val malformed = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "p-bad", createdAt = System.currentTimeMillis())
            .copy(payload = JSONObject().put("mesh_path", JSONArray().put("Z")))
        assertFalse(router.validateForProcessing(malformed))
    }

    @Test
    fun packetRoundTripsCanonicalFields() {
        val packet = MeshPacket.new(
            sourceNodeId = "A",
            destinationNodeId = "C",
            type = "direct_message",
            payload = JSONObject().put("id", "m1"),
            ttl = 8,
            packetId = "p1",
            createdAt = 100L,
        ).withOriginAuth("0".repeat(64))
        val parsed = MeshPacket.fromJson(packet.toJson())!!
        assertEquals("p1", parsed.packetId)
        assertEquals("A", parsed.sourceNodeId)
        assertEquals("C", parsed.destinationNodeId)
        assertEquals(8, parsed.ttl)
        assertEquals("direct_message", parsed.type)
        assertEquals("m1", parsed.payload.optString("id"))
        assertEquals("auth", parsed.originAuth)
        assertEquals(MeshPacket.PROTOCOL_VERSION, parsed.protocolVersion)
    }

    @Test
    fun originAuthInputDoesNotChangeWhenHopPathChanges() {
        val base = MeshPacket.new("A", "D", "direct_message", JSONObject().put("body", "ciphertext"), 8, packetId = "p1", createdAt = System.currentTimeMillis())
            .copy(payload = JSONObject().put("body", "ciphertext").put("mesh_path", JSONArray().put("A")))
        val forwarded = base.copyForForwarding("B", "A")
        assertEquals(base.originAuthInput(), forwarded.originAuthInput())
    }

    @Test
    fun routeTableKeepsAlternativesAndCanInvalidatePrimaryNextHop() {
        val table = MeshRouteTable()
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D")))
        table.upsert("D", MeshRoute("D", "C", 3, Long.MAX_VALUE, 100L, 11L, listOf("A", "C", "D")))
        assertEquals(2, table.allFor("D").size)
        assertEquals("B", table["D"]!!.nextHopNodeId)
        val affected = table.invalidateVia("B")
        assertTrue(affected.contains("D"))
        assertEquals("C", table["D"]!!.nextHopNodeId)
        table.removeVia("B")
        assertEquals(1, table.allFor("D").size)
    }

    @Test
    fun routerSupportsMoreThanOneIntermediateHop() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 1L)
        table.upsert("E", MeshRoute("E", "B", 4, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "C", "D", "E")))

        var sent: MeshPacket? = null
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean { sent = packet; return true }
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "E", "direct_message", JSONObject().put("id", "m1").put("mesh_path", JSONArray().put("A")), 8, packetId = "p1", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet))
        assertEquals("B", sent!!.nextHopNodeId)
        assertEquals(7, sent!!.ttl)
        assertEquals(1, sent!!.hopCount)
    }


    @Test
    fun packetTravelsAcrossThreeIntermediateNodes() {
        val ids = listOf("A", "B", "C", "D", "E")
        val tables = ids.associateWith { MeshRouteTable() }
        val peers = ids.associateWith { MeshPeerRegistry() }
        ids.drop(1).forEach { peers["A"]!!.connected(it, "test", 1L) }
        peers["B"]!!.connected("C", "test", 1L)
        peers["C"]!!.connected("D", "test", 1L)
        peers["D"]!!.connected("E", "test", 1L)
        tables["A"]!!.upsert("E", MeshRoute("E", "B", 4, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "C", "D", "E")))
        tables["B"]!!.upsert("E", MeshRoute("E", "C", 3, Long.MAX_VALUE, 1L, 10L, listOf("B", "C", "D", "E")))
        tables["C"]!!.upsert("E", MeshRoute("E", "D", 2, Long.MAX_VALUE, 1L, 10L, listOf("C", "D", "E")))
        tables["D"]!!.upsert("E", MeshRoute("E", "E", 1, Long.MAX_VALUE, 1L, 10L, listOf("D", "E")))

        val delivered = mutableListOf<String>()
        fun routerFor(id: String): MeshRouter {
            val transport = object : MeshTransport {
                override val name = "test"
                override fun isPeerAvailable(nodeId: String) = peers[id]!!.isAvailable(nodeId)
                override fun send(peerNodeId: String, packet: MeshPacket): Boolean {
                    if (peerNodeId == "E") { delivered += packet.packetId; return packet.destinationNodeId == "E" }
                    return routerFor(peerNodeId).route(packet, incomingPeerId = id, allowQueue = false) == MeshRouteResult.FORWARDED
                }
                override fun disconnect(peerNodeId: String) {}
            }
            return MeshRouter({ id }, tables[id]!!, peers[id]!!, transport, maxHops = 8)
        }
        val packet = MeshPacket.new("A", "E", "direct_message", JSONObject().put("mesh_path", JSONArray().put("A")), 8, packetId = "p-multi", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.FORWARDED, routerFor("A").route(packet))
        assertEquals(listOf("p-multi"), delivered)
    }

    @Test
    fun routerDropsLoopAndNeverSendsBackToIncomingPeer() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 1L)
        peers.connected("C", "lan", 1L)
        table.upsert("D", MeshRoute("D", "B", 3, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "C", "D")))
        table.upsert("D", MeshRoute("D", "C", 3, Long.MAX_VALUE, 1L, 11L, listOf("A", "C", "D")))
        val attempts = mutableListOf<String>()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean { attempts += peerNodeId; return true }
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "B" }, table, peers, transport, maxHops = 8)
        val looped = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "p2", createdAt = System.currentTimeMillis())
            .copy(hopCount = 1, ttl = 7, payload = JSONObject().put("mesh_path", JSONArray().put("A").put("B")))
        assertEquals(MeshRouteResult.DROPPED, router.route(looped, incomingPeerId = "A"))

        val fromB = MeshPacket.new("A", "D", "direct_message", JSONObject().put("mesh_path", JSONArray().put("A")), 8, packetId = "p3", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.FORWARDED, router.route(fromB, incomingPeerId = "B"))
        assertFalse(attempts.contains("B"))
        assertEquals(listOf("C"), attempts)
    }


    @Test
    fun callMediaPacketUsesNormalMultiHopEnvelope() {
        val packet = MeshPacket.new(
            sourceNodeId = "A",
            destinationNodeId = "D",
            type = "call_media",
            payload = JSONObject().put("call_id", "call-1").put("sequence", 7).put("audio_enc", "ciphertext"),
            ttl = 8,
            packetId = "media-7",
            createdAt = 100L,
        ).withOriginAuth("0".repeat(64))
        val forwarded = packet.copyForForwarding("B", "A")
        assertEquals("call_media", forwarded.type)
        assertEquals("A", forwarded.sourceNodeId)
        assertEquals("D", forwarded.destinationNodeId)
        assertEquals("B", forwarded.nextHopNodeId)
        assertEquals(7, forwarded.ttl)
        assertEquals(1, forwarded.hopCount)
        assertEquals("ciphertext", forwarded.payload.optString("audio_enc"))
        assertEquals(packet.originAuthInput(), forwarded.originAuthInput())
    }

    @Test
    fun routerQueuesExactlyOnceWhenNoRouteExists() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        var queueCalls = 0
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = false
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean = false
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport, enqueue = { queueCalls++; true }, maxHops = 8)
        val packet = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "p-queue", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.QUEUED, router.route(packet))
        assertEquals(1, queueCalls)
        assertEquals(MeshRouteResult.NO_ROUTE, router.route(packet, allowQueue = false))
        assertEquals(1, queueCalls)
    }

    @Test
    fun stalePeerDisconnectCannotRemoveReplacement() {
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 10L)
        peers.connected("B", "wifi_direct", 20L)
        assertEquals("wifi_direct", peers.get("B")!!.transport)
        peers.available("B", "wifi_direct", 30L)
        assertTrue(peers.isAvailable("B"))
    }

    @Test
    fun routerDropsExpiredTtl() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 1L)
        table.upsert("C", MeshRoute("C", "B", 2, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "C")))
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = true
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "C", "direct_message", JSONObject(), 1, packetId = "p4", createdAt = System.currentTimeMillis()).copy(hopCount = 1)
        assertEquals(MeshRouteResult.DROPPED, router.route(packet))
    }

    @Test
    fun routerTriesAlternateRouteAfterPrimaryFails() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 1L)
        peers.connected("C", "lan", 1L)
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "D")))
        table.upsert("D", MeshRoute("D", "C", 3, Long.MAX_VALUE, 1L, 11L, listOf("A", "C", "D")))
        val attempts = mutableListOf<String>()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean { attempts += peerNodeId; return peerNodeId == "C" }
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "D", "direct_message", JSONObject().put("id", "m1"), 8, packetId = "p5", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet))
        assertEquals(listOf("B", "C"), attempts)
        assertEquals("C", table["D"]!!.nextHopNodeId)
        assertEquals(1, table.allFor("D").size)
    }
    @Test
    fun invalidatingPrimaryKeepsLiveMediaOnAlternateRouteWithoutChangingPacketIdentity() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "lan", 1L)
        peers.connected("C", "lan", 1L)
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "D")))
        table.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 1L, 11L, listOf("A", "C", "D")))
        val attempts = mutableListOf<MeshPacket>()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean {
                attempts += packet
                return peerNodeId == "C"
            }
            override fun disconnect(peerNodeId: String) {}
            override fun onRouteFailure(destinationNodeId: String, failedNextHopNodeId: String) {
                table.invalidateVia(failedNextHopNodeId)
            }
        }
        val router = MeshRouter({ "A" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new(
            sourceNodeId = "A",
            destinationNodeId = "D",
            type = "call_video_frame",
            payload = JSONObject().put("call_id", "call-1").put("sequence", 42).put("timestamp_ms", 1000L).put("video_enc", "ciphertext"),
            ttl = 8,
            packetId = "video-42",
            createdAt = 1000L,
        ).withOriginAuth("0".repeat(64))
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet))
        assertEquals(listOf("B", "C"), attempts.map { it.nextHopNodeId })
        assertEquals(listOf("video-42", "video-42"), attempts.map { it.packetId })
        assertEquals(42, attempts.last().payload.optInt("sequence"))
        assertEquals("C", table["D"]!!.nextHopNodeId)
    }

    @Test
    fun unavailablePrimaryRouteIsInvalidatedAndAlternateIsUsed() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("C", "lan", 1L)
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "D")))
        table.upsert("D", MeshRoute("D", "C", 3, Long.MAX_VALUE, 1L, 11L, listOf("A", "C", "D")))
        val failures = mutableListOf<String>()
        val attempts = mutableListOf<String>()
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean { attempts += peerNodeId; return true }
            override fun disconnect(peerNodeId: String) {}
            override fun onRouteFailure(destinationNodeId: String, failedNextHopNodeId: String) { failures += failedNextHopNodeId }
        }
        val router = MeshRouter({ "A" }, table, peers, transport, maxHops = 8)
        val packet = MeshPacket.new("A", "D", "call_media", JSONObject().put("call_id", "call-1").put("sequence", 1), 8, packetId = "audio-1", createdAt = 1000L).withOriginAuth("0".repeat(64))
        assertEquals(MeshRouteResult.FORWARDED, router.route(packet))
        assertEquals(listOf("B"), failures)
        assertEquals(listOf("C"), attempts)
        assertEquals("C", table["D"]!!.nextHopNodeId)
    }




    @Test
    fun aToBToCToDOnlyFinalDeviceReturnsLocalDelivery() {
        val nodes = listOf("A", "B", "C", "D")
        val tables = nodes.associateWith { MeshRouteTable() }
        val peers = nodes.associateWith { MeshPeerRegistry() }
        val forwarded = mutableListOf<MeshPacket>()

        peers["A"]!!.connected("B", "test", 1L)
        peers["B"]!!.connected("C", "test", 1L)
        peers["C"]!!.connected("D", "test", 1L)

        tables["A"]!!.upsert("D", MeshRoute("D", "B", 3, Long.MAX_VALUE, 1L, 1L, listOf("A", "B", "C", "D")))
        tables["B"]!!.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 1L, 1L, listOf("B", "C", "D")))
        tables["C"]!!.upsert("D", MeshRoute("D", "D", 1, Long.MAX_VALUE, 1L, 1L, listOf("C", "D")))

        fun transportFor(node: String) = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers[node]!!.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket): Boolean {
                forwarded += packet
                return true
            }
            override fun disconnect(peerNodeId: String) {}
        }

        val payload = JSONObject().put(MeshPacket.MESH_PATH_KEY, JSONArray().put("A")).put("id", "m1")
        val original = MeshPacket.new("A", "D", "direct_message", payload, 8, packetId = "mesh-final-test", createdAt = System.currentTimeMillis())

        val a = MeshRouter({ "A" }, tables["A"]!!, peers["A"]!!, transportFor("A"))
        val b = MeshRouter({ "B" }, tables["B"]!!, peers["B"]!!, transportFor("B"))
        val c = MeshRouter({ "C" }, tables["C"]!!, peers["C"]!!, transportFor("C"))
        val d = MeshRouter({ "D" }, tables["D"]!!, peers["D"]!!, transportFor("D"))

        assertEquals(MeshRouteResult.FORWARDED, a.route(original))
        val atB = forwarded.removeFirst()
        assertEquals("mesh-final-test", atB.packetId)
        assertEquals("B", atB.nextHopNodeId)
        assertEquals(MeshRouteResult.FORWARDED, b.route(atB, incomingPeerId = "A"))
        val atC = forwarded.removeFirst()
        assertEquals("mesh-final-test", atC.packetId)
        assertEquals("C", atC.nextHopNodeId)
        assertEquals(MeshRouteResult.FORWARDED, c.route(atC, incomingPeerId = "B"))
        val atD = forwarded.removeFirst()
        assertEquals("mesh-final-test", atD.packetId)
        assertEquals("D", atD.nextHopNodeId)

        assertEquals(MeshRouteResult.LOCAL_DELIVERY, d.route(atD, incomingPeerId = "C"))
        assertTrue(forwarded.isEmpty())
    }

    @Test
    fun forwardingWithoutExistingPathPreservesOriginalSource() {
        val packet = MeshPacket.new("A", "C", "direct_message", JSONObject(), 8, packetId = "p-path", createdAt = System.currentTimeMillis())
        val forwarded = packet.copyForForwarding("B", "A")
        val path = forwarded.payload.getJSONArray(MeshPacket.MESH_PATH_KEY)
        assertEquals("A", path.getString(0))
        assertEquals(1, path.length())
        assertEquals(1, forwarded.hopCount)
    }

    @Test
    fun routerRejectsIncomingPacketWhosePathDoesNotEndAtPreviousHop() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("C", "test", 1L)
        table.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 1L, 10L, listOf("B", "C", "D")))
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket) = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "B" }, table, peers, transport, maxHops = 8)
        val tamperedHop = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "p-hop-tamper", createdAt = System.currentTimeMillis())
            .copy(ttl = 7, hopCount = 0)
        assertFalse(router.validateForProcessing(tamperedHop, incomingPeerId = "C"))
        val wrongPreviousHop = MeshPacket.new("A", "D", "direct_message", JSONObject(), 8, packetId = "p-path-tamper", createdAt = System.currentTimeMillis())
            .copy(ttl = 6, hopCount = 2, payload = JSONObject().put(MeshPacket.MESH_PATH_KEY, JSONArray().put("A").put("C")))
        assertFalse(router.validateForProcessing(wrongPreviousHop, incomingPeerId = "B"))
    }

    @Test
    fun routerRejectsMalformedPacketPathThatDoesNotStartAtSource() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "test", 1L)
        table.upsert("C", MeshRoute("C", "B", 2, Long.MAX_VALUE, 1L, 10L, listOf("A", "B", "C")))
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket) = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport)
        val malformed = MeshPacket.new("A", "C", "direct_message", JSONObject()
            .put(MeshPacket.MESH_PATH_KEY, JSONArray().put("X").put("B")), 8, packetId = "p-bad-path", createdAt = System.currentTimeMillis())
        assertEquals(MeshRouteResult.DROPPED, router.route(malformed))
    }

    @Test
    fun routeTableRejectsPathWithWrongHopCountOrDestination() {
        val table = MeshRouteTable()
        assertFalse(table.upsert("D", MeshRoute("D", "B", 3, Long.MAX_VALUE, 1L, 1L, listOf("A", "B", "D"))))
        assertFalse(table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 2L, listOf("A", "B", "C"))))
        assertTrue(table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 3L, listOf("A", "B", "D"))))
    }

    @Test
    fun packetParserRejectsBlankAndSelfTargetIds() {
        val blank = JSONObject().put("mesh_version", MeshPacket.PROTOCOL_VERSION)
            .put("packet_id", " ").put("source_node_id", "A").put("destination_node_id", "B")
            .put("type", "direct_message").put("payload", JSONObject()).put("created_at", 1L).put("ttl", 8).put("hop_count", 0)
        assertEquals(null, MeshPacket.fromJson(blank))

        val selfTarget = MeshPacket.new("A", "B", "direct_message", JSONObject(), 8, packetId = "self", createdAt = System.currentTimeMillis())
            .toJson()
            .put("source_node_id", "A")
            .put("destination_node_id", "A")
        assertEquals(null, MeshPacket.fromJson(selfTarget))
    }

}

class MeshHopLimitTest {
    @Test
    fun hopBudgetAllowsZeroTtlOnlyAtMaximumHopCount() {
        assertTrue(MeshLimits.hasValidHopBudget(8, 0))
        assertTrue(MeshLimits.hasValidHopBudget(0, 8))
        assertTrue(MeshLimits.hasValidHopBudget(1, 7))
        assertFalse(MeshLimits.hasValidHopBudget(0, 7))
        assertFalse(MeshLimits.hasValidHopBudget(8, 1))
        assertFalse(MeshLimits.hasValidHopBudget(9, 0))
        assertFalse(MeshLimits.hasValidHopBudget(0, 9))
    }

    @Test
    fun canonicalPacketParserRejectsHopBudgetOverflow() {
        val unsigned = MeshPacket.new(
            "A", "B", "direct_message", JSONObject(), 8,
            packetId = "packet-overflow", createdAt = System.currentTimeMillis(),
        ).copy(ttl = 8, hopCount = 1)
        val json = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, "overflow-key")).toJson()
        assertEquals(null, MeshPacket.fromJson(json))
    }

    @Test
    fun canonicalPacketParserAcceptsFinalHopWithZeroTtl() {
        val unsigned = MeshPacket.new(
            "A", "I", "direct_message", JSONObject(), 8,
            packetId = "packet-final-hop", createdAt = System.currentTimeMillis(),
        ).copy(ttl = 0, hopCount = 8)
        val json = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, "final-hop-key")).toJson()
        val parsed = MeshPacket.fromJson(json)
        assertEquals(0, parsed!!.ttl)
        assertEquals(8, parsed.hopCount)
    }
}


class MeshCanonicalPacketTest {
    @Test
    fun parserRejectsMissingOrLegacyProtocolVersion() {
        val packet = MeshPacket.new(
            "A", "D", "direct_message", JSONObject().put("body", "ciphertext"), 8,
            packetId = "canonical-1", createdAt = System.currentTimeMillis(),
        )
        val legacy = packet.toJson().apply { put("mesh_version", MeshPacket.LEGACY_PROTOCOL_VERSION) }
        val missing = packet.toJson().apply { remove("mesh_version") }
        assertEquals(null, MeshPacket.fromJson(legacy))
        assertEquals(null, MeshPacket.fromJson(missing))
        assertEquals(MeshPacket.PROTOCOL_VERSION, MeshPacket.fromJson(packet.toJson())!!.protocolVersion)
    }

    @Test
    fun legacyVersionPacketIsConstructibleOnlyForFixturesAndRouterRejectsIt() {
        val legacy = MeshPacket(
            packetId = "legacy-1",
            sourceNodeId = "A",
            destinationNodeId = "B",
            nextHopNodeId = null,
            ttl = 8,
            hopCount = 0,
            type = "direct_message",
            payload = JSONObject().put("body", "ciphertext"),
            createdAt = System.currentTimeMillis(),
            originAuth = null,
            protocolVersion = MeshPacket.LEGACY_PROTOCOL_VERSION,
        )
        assertEquals(MeshPacket.LEGACY_PROTOCOL_VERSION, legacy.protocolVersion)
    }

    @Test
    fun applicationAdapterCannotBeParsedBackAsCanonicalMeshPacket() {
        val packet = MeshPacket.new(
            "A", "B", "direct_message", JSONObject().put("body", "ciphertext"), 8,
            packetId = "adapter-1", createdAt = System.currentTimeMillis(),
        ).withOriginAuth(MeshPacketAuthentication.signOrigin(
            MeshPacket.new(
                "A", "B", "direct_message", JSONObject().put("body", "ciphertext"), 8,
                packetId = "adapter-1", createdAt = System.currentTimeMillis(),
            ),
            "adapter-key",
        ))
        val applicationPayload = packet.toApplicationPayload()
        assertEquals(null, MeshPacket.fromJson(applicationPayload))
    }

    @Test
    fun canonicalForwardingPreservesPacketIdentityAndProtocol() {
        val packet = MeshPacket.new(
            "A", "D", "direct_message", JSONObject().put("body", "ciphertext"), 8,
            packetId = "stable-packet", createdAt = System.currentTimeMillis(),
        )
        val forwarded = packet.copyForForwarding("B", "A")
        assertEquals(packet.packetId, forwarded.packetId)
        assertEquals(packet.sourceNodeId, forwarded.sourceNodeId)
        assertEquals(packet.destinationNodeId, forwarded.destinationNodeId)
        assertEquals(MeshPacket.PROTOCOL_VERSION, forwarded.protocolVersion)
        assertEquals(listOf("A", "B"), forwarded.normalizedPath())
    }

    @Test
    fun originAuthInputStaysStableWhenRelaysRewriteHopLocalFields() {
        val packet = MeshPacket.new(
            "A", "D", "direct_message", JSONObject().put("body", "ciphertext"), 8,
            packetId = "auth-stable", createdAt = System.currentTimeMillis(),
        )
        val input = packet.originAuthInput()
        val forwarded = packet.copyForForwarding("B", "A").copy(ttl = 7, hopCount = 1, nextHopNodeId = "C")
        assertEquals(input, forwarded.originAuthInput())
    }

    @Test
    fun routerRejectsNonCanonicalLegacyPacket() {
        val table = MeshRouteTable()
        val peers = MeshPeerRegistry()
        peers.connected("B", "test", 1L)
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 1L, 1L, listOf("A", "B", "D")))
        val transport = object : MeshTransport {
            override val name = "test"
            override fun isPeerAvailable(nodeId: String) = peers.isAvailable(nodeId)
            override fun send(peerNodeId: String, packet: MeshPacket) = true
            override fun disconnect(peerNodeId: String) {}
        }
        val router = MeshRouter({ "A" }, table, peers, transport)
        val legacy = MeshPacket(
            packetId = "legacy-1",
            sourceNodeId = "A",
            destinationNodeId = "D",
            nextHopNodeId = null,
            ttl = 8,
            hopCount = 0,
            type = "direct_message",
            payload = JSONObject(),
            createdAt = System.currentTimeMillis(),
            originAuth = null,
            protocolVersion = MeshPacket.LEGACY_PROTOCOL_VERSION,
        )
        assertEquals(MeshRouteResult.DROPPED, router.route(legacy))
    }
}


class MeshRouteStateCorrectnessTest {
    @Test
    fun routeTableRejectsEqualVersionTopologyMutation() {
        val table = MeshRouteTable { "A" }
        assertTrue(table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D"))))
        assertFalse(table.upsert("D", MeshRoute("D", "B", 3, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "C", "D"))))
        assertEquals(2, table["D"]!!.hopCount)
        assertEquals(listOf("A", "B", "D"), table["D"]!!.path)
    }

    @Test
    fun routeTableRejectsNextHopThatIsNotTheFirstRelay() {
        val table = MeshRouteTable { "A" }
        assertFalse(table.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D"))))
    }

    @Test
    fun routeTableRequiresLocalOriginInPathWhenBound() {
        val table = MeshRouteTable { "A" }
        assertFalse(table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("X", "B", "D"))))
        assertTrue(table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 11L, listOf("A", "B", "D"))))
    }

    @Test
    fun invalidatingPeerMovesRoutesOutOfActiveState() {
        val table = MeshRouteTable { "A" }
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D")))
        assertEquals(listOf("D"), table.invalidateVia("B"))
        assertEquals(null, table["D"])
        assertEquals(MeshRouteState.INVALID, table.all()["D"]!!.single().state)
    }

    @Test
    fun routeRecoveryStateIsNotSelectedUntilFreshRouteIsLearned() {
        val table = MeshRouteTable { "A" }
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D")))
        assertTrue(table.markRecovering("D", "B"))
        assertEquals(null, table["D"])
        assertTrue(table.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 101L, 11L, listOf("A", "C", "D"))))
        assertEquals("C", table["D"]!!.nextHopNodeId)
    }

    @Test
    fun routeTableKeepsAlternateRouteWhenFailedNextHopIsInvalidated() {
        val table = MeshRouteTable { "A" }
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D")))
        table.upsert("D", MeshRoute("D", "C", 3, Long.MAX_VALUE, 100L, 11L, listOf("A", "C", "X", "D")))
        table.invalidateVia("B")
        assertEquals("C", table["D"]!!.nextHopNodeId)
    }

    @Test
    fun routeTableRejectsAlreadyExpiredRoute() {
        val table = MeshRouteTable { "A" }
        val now = System.currentTimeMillis()
        assertFalse(table.upsert("D", MeshRoute("D", "B", 2, now - 1L, now - 1000L, 9L, listOf("A", "B", "D"))))
    }

    @Test
    fun routeTableSelectsDeterministicallyAmongEqualCostAlternates() {
        val table = MeshRouteTable { "A" }
        table.upsert("D", MeshRoute("D", "C", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "C", "D")))
        table.upsert("D", MeshRoute("D", "B", 2, Long.MAX_VALUE, 100L, 10L, listOf("A", "B", "D")))
        assertEquals("B", table["D"]!!.nextHopNodeId)
    }

    @Test
    fun routeTableBoundsDestinationsAndAlternatesPerDestination() {
        val table = MeshRouteTable()
        var acceptedDestinations = 0
        for (i in 0 until MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS + 16) {
            val destination = "D$i"
            if (table.upsert(destination, MeshRoute(destination, destination, 1, Long.MAX_VALUE, 1L, 1L, listOf("A", destination)))) acceptedDestinations++
        }
        assertEquals(MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS, table.all().size)
        assertEquals(MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS, acceptedDestinations)

        val destination = "HOT"
        table.clear()
        repeat(MeshLimits.MAX_ROUTES_PER_DESTINATION) { index ->
            assertTrue(table.upsert(destination, MeshRoute(destination, "N$index", 2, Long.MAX_VALUE, 1L, index + 1L, listOf("A", "N$index", destination))))
        }
        assertEquals(MeshLimits.MAX_ROUTES_PER_DESTINATION, table.allFor(destination).size)
        assertTrue(table.allFor(destination).none { it.nextHopNodeId == "N99" })
    }

    @Test
    fun oneNextHopCannotMonopolizeAllDestinationSlots() {
        val table = MeshRouteTable()
        var accepted = 0
        for (i in 0 until MeshLimits.MAX_ROUTES_PER_NEXT_HOP + 8) {
            val destination = "Q$i"
            val route = MeshRoute(destination, "MALICIOUS", 2, Long.MAX_VALUE, 1L, i.toLong() + 1L, listOf("A", "MALICIOUS", destination))
            if (table.upsert(destination, route)) accepted++
        }
        assertEquals(MeshLimits.MAX_ROUTES_PER_NEXT_HOP, accepted)
        assertEquals(MeshLimits.MAX_ROUTES_PER_NEXT_HOP, table.all().size)
    }

}
