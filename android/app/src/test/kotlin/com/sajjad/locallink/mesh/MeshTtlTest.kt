package com.sajjad.locallink.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshTtlTest {
    @Test
    fun canonicalLimitsStayAtEight() {
        assertEquals(8, MeshLimits.MAX_TTL)
        assertEquals(8, MeshLimits.MAX_HOPS)
        assertTrue(MeshLimits.isValidInitialTtl(1))
        assertTrue(MeshLimits.isValidInitialTtl(8))
        assertFalse(MeshLimits.isValidInitialTtl(0))
        assertFalse(MeshLimits.isValidInitialTtl(9))
    }

    @Test
    fun hopBudgetCannotBeNegativeOverflowedOrZeroAtOrigin() {
        assertTrue(MeshLimits.hasValidHopBudget(8, 0))
        assertTrue(MeshLimits.hasValidHopBudget(1, 7))
        assertTrue(MeshLimits.hasValidHopBudget(0, 1))
        assertTrue(MeshLimits.hasValidHopBudget(0, 8))
        assertFalse(MeshLimits.hasValidHopBudget(0, 0))
        assertFalse(MeshLimits.hasValidHopBudget(8, 1))
        assertFalse(MeshLimits.hasValidHopBudget(9, 0))
        assertFalse(MeshLimits.hasValidHopBudget(0, 9))
    }

    @Test
    fun forwardingConsumesExactlyOneTtlAndOneHop() {
        var packet = MeshPacket.new(
            "A", "I", "direct_message", JSONObject(), 8,
            packetId = "ttl-chain", createdAt = System.currentTimeMillis(),
        )
        for (node in listOf("B", "C", "D", "E", "F", "G", "H", "I")) {
            val oldTtl = packet.ttl
            val oldHops = packet.hopCount
            val relay = if (oldHops == 0) "A" else node
            packet = packet.copyForForwarding(node, relay)
            assertEquals(oldTtl - 1, packet.ttl)
            assertEquals(oldHops + 1, packet.hopCount)
            assertEquals(8, packet.ttl + packet.hopCount)
        }
        assertEquals(0, packet.ttl)
        assertEquals(8, packet.hopCount)
    }

    @Test
    fun forwardingWithZeroTtlIsRejected() {
        val terminal = MeshPacket.new(
            "A", "B", "direct_message", JSONObject(), 1,
            packetId = "terminal", createdAt = System.currentTimeMillis(),
        ).copy(ttl = 0, hopCount = 1)
        try {
            terminal.copyForForwarding("C", "B")
            throw AssertionError("zero-TTL packet was forwarded")
        } catch (_: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun packetPathLengthTracksConsumedForwardingHops() {
        var packet = MeshPacket.new(
            "A", "D", "direct_message", JSONObject(), 8,
            packetId = "path-budget", createdAt = System.currentTimeMillis(),
        )
        assertEquals(listOf("A"), packet.normalizedPath())
        packet = packet.copyForForwarding("B", "A")
        assertEquals(listOf("A"), packet.normalizedPath())
        packet = packet.copyForForwarding("C", "B")
        assertEquals(listOf("A", "B"), packet.normalizedPath())
        packet = packet.copyForForwarding("D", "C")
        assertEquals(listOf("A", "B", "C"), packet.normalizedPath())
        assertEquals(packet.hopCount, packet.normalizedPath().size)
    }

    @Test
    fun forwardingCannotSilentlyRepairAPathMismatchOrLoop() {
        val base = MeshPacket.new(
            "A", "D", "direct_message", JSONObject(), 8,
            packetId = "bad-path", createdAt = System.currentTimeMillis(),
        )
        val mismatch = base.copy(payload = JSONObject(base.payload.toString()).put(MeshPacket.MESH_PATH_KEY, org.json.JSONArray().put("A").put("B")))
        try {
            mismatch.copyForForwarding("C", "A")
            throw AssertionError("path mismatch was silently repaired")
        } catch (_: IllegalArgumentException) {
            // expected
        }
        val loop = base.copyForForwarding("B", "A").copyForForwarding("C", "B")
        try {
            loop.copyForForwarding("D", "B")
            throw AssertionError("looping relay was accepted")
        } catch (_: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun parserRejectsInconsistentTtlHopOrPathState() {
        val packet = MeshPacket.new(
            "A", "D", "direct_message", JSONObject(), 8,
            packetId = "parser-budget", createdAt = System.currentTimeMillis(),
        ).withOriginAuth("0".repeat(64))
        assertEquals(null, MeshPacket.fromJson(packet.toJson().put("ttl", 8).put("hop_count", 1)))
        assertEquals(null, MeshPacket.fromJson(packet.toJson().put("ttl", 0).put("hop_count", 0)))
        assertEquals(null, MeshPacket.fromJson(packet.toJson().put("ttl", 7).put("hop_count", 1)
            .put("payload", JSONObject().put(MeshPacket.MESH_PATH_KEY, org.json.JSONArray().put("A")))))
    }
}
