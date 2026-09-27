package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshPacketAuthenticationTest {
    private val key = "shared-secret-A-D"

    @Test
    fun originSignatureVerifiesWithCorrectKeyAndPacket() {
        val unsigned = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject().put("message_id", "m1").put("ciphertext", "abc"),
            8,
            packetId = "packet-auth-1",
            createdAt = 100L,
        )
        val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))

        assertTrue(MeshPacketAuthentication.verifyOrigin(signed, key))
        assertFalse(MeshPacketAuthentication.verifyOrigin(signed, "wrong-key"))
    }

    @Test
    fun originSignatureDetectsMutationOfEveryImmutableField() {
        val unsigned = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject().put("ciphertext", "abc"),
            8,
            packetId = "packet-auth-2",
            createdAt = 100L,
        )
        val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))

        val mutations = listOf(
            signed.copy(packetId = "packet-auth-2-mutated"),
            signed.copy(sourceNodeId = "B"),
            signed.copy(destinationNodeId = "E"),
            signed.copy(type = "call_media"),
            signed.copy(createdAt = 101L),
            signed.copy(payload = JSONObject().put("ciphertext", "tampered")),
        )

        mutations.forEach { mutated ->
            assertFalse(MeshPacketAuthentication.verifyOrigin(mutated, key))
        }
    }

    @Test
    fun originSignatureIgnoresOnlyHopLocalPathChanges() {
        val unsigned = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject()
                .put("ciphertext", "abc")
                .put(MeshPacket.MESH_PATH_KEY, JSONArray().put("A")),
            8,
            packetId = "packet-auth-3",
            createdAt = 100L,
        )
        val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))
        val forwarded = signed.copyForForwarding("B", "A")

        assertEquals(signed.originAuth, forwarded.originAuth)
        assertEquals(unsigned.originAuthInput(), forwarded.originAuthInput())
        assertTrue(MeshPacketAuthentication.verifyOrigin(forwarded, key))
    }

    @Test
    fun originSignatureDoesNotAllowChangingHopLocalMetadataWithoutResigning() {
        val unsigned = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject().put("ciphertext", "abc"),
            8,
            packetId = "packet-auth-4",
            createdAt = 100L,
        )
        val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))
        val altered = signed.copy(nextHopNodeId = "C", ttl = 7, hopCount = 1)

        assertTrue(MeshPacketAuthentication.verifyOrigin(altered, key))
    }

    @Test
    fun parserRejectsCanonicalPacketWithoutOriginAuthentication() {
        val packet = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject(),
            8,
            packetId = "packet-auth-required",
            createdAt = 100L,
        )
        assertTrue(MeshPacket.fromJson(packet.toJson()) == null)
    }

    @Test
    fun parserRejectsMalformedOriginAuthentication() {
        val packet = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject(),
            8,
            packetId = "packet-auth-5",
            createdAt = 100L,
        )
        assertTrue(MeshPacket.fromJson(packet.toJson().put("origin_auth", "too-short")) == null)
        assertTrue(MeshPacket.fromJson(packet.toJson().put("origin_auth", "z".repeat(64))) == null)
    }

    @Test
    fun originSigningInputIsStructurallyUnambiguousForPipeCharacters() {
        val first = MeshPacket.new(
            "source",
            "D",
            "type",
            JSONObject().put("ciphertext", "abc"),
            8,
            packetId = "p|source",
            createdAt = 100L,
        )
        val second = MeshPacket.new(
            "|source",
            "D",
            "type",
            JSONObject().put("ciphertext", "abc"),
            8,
            packetId = "p",
            createdAt = 100L,
        )
        assertNotEquals(first.originAuthInput(), second.originAuthInput())
    }

    @Test
    fun originVerificationRejectsNonCanonicalProtocolVersion() {
        val unsigned = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject(),
            8,
            packetId = "packet-auth-protocol",
            createdAt = 100L,
        )
        val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))
        assertFalse(MeshPacketAuthentication.verifyOrigin(signed.copy(protocolVersion = MeshPacket.LEGACY_PROTOCOL_VERSION), key))
    }

    @Test
    fun hopIdentityAadBindsBothPeers() {
        val ab = MeshPacketAuthentication.hopIdentityAad("A", "B")
        val ac = MeshPacketAuthentication.hopIdentityAad("A", "C")
        val ba = MeshPacketAuthentication.hopIdentityAad("B", "A")

        assertNotEquals(String(ab), String(ac))
        assertNotEquals(String(ab), String(ba))
        assertArrayEquals(ab, MeshPacketAuthentication.hopIdentityAad("A", "B"))
    }
}
