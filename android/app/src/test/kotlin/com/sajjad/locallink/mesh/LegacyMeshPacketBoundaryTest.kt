package com.sajjad.locallink.mesh

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Test-only migration fixtures. No legacy decoder exists in production routing code. */
class LegacyMeshPacketBoundaryTest {
    @Test
    fun canonicalParserRejectsLegacyShapedApplicationPayload() {
        val legacyPayload = JSONObject()
            .put("mesh_packet_id", "legacy-1")
            .put("mesh_origin_id", "A")
            .put("recipient_id", "B")
            .put("mesh_ttl", 8)
            .put("mesh_hops", 0)
            .put("mesh_created_at", 1L)
            .put("type", "direct_message")
            .put("body", "ciphertext")
        assertNull(MeshPacket.fromJson(legacyPayload))
    }

    @Test
    fun canonicalPacketCanRoundTripOnlyThroughCanonicalWireEnvelope() {
        val packet = MeshPacket.new(
            "A", "B", "direct_message", JSONObject().put("body", "ciphertext"), 8,
            packetId = "canonical-boundary-1", createdAt = 1L,
        ).withOriginAuth(MeshPacketAuthentication.signOrigin(
            MeshPacket.new(
                "A", "B", "direct_message", JSONObject().put("body", "ciphertext"), 8,
                packetId = "canonical-boundary-1", createdAt = 1L,
            ),
            "canonical-boundary-key",
        ))
        val parsed = MeshPacket.fromJson(packet.toJson())
        assertNotNull(parsed)
        assertEquals(MeshPacket.PROTOCOL_VERSION, parsed!!.protocolVersion)
        assertEquals(packet.packetId, parsed.packetId)
    }
}
