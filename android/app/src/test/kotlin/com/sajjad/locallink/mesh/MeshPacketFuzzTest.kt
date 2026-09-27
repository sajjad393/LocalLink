package com.sajjad.locallink.mesh

import java.util.Random
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Exercises the real Android org.json + MeshPacket codec with deterministic mutations. */
class MeshPacketFuzzTest {
    private val key = "phase67-packet-fuzz-key"

    @Test
    fun canonicalRoundTripPreservesSecurityInvariantsAcrossFuzzCorpus() {
        val rng = Random(0x5041434b4554L)
        repeat(2_000) { index ->
            val unsigned = MeshPacket.new(
                sourceNodeId = "A",
                destinationNodeId = "D",
                type = when (index % 4) {
                    0 -> "direct_message"
                    1 -> "call_signal"
                    2 -> "file_control"
                    else -> "route_payload"
                },
                payload = JSONObject()
                    .put("ciphertext", randomAscii(rng, rng.nextInt(512)))
                    .put("message_id", "m-$index"),
                ttl = 1 + rng.nextInt(MeshLimits.MAX_TTL),
                nextHopNodeId = if (index % 2 == 0) "B" else null,
                packetId = "packet-$index",
                createdAt = 100_000L + index,
            )
            val signed = unsigned.withOriginAuth(MeshPacketAuthentication.signOrigin(unsigned, key))
            val parsed = MeshPacket.fromJson(signed.toJson())
            assertNotNull(parsed)
            assertTrue(MeshPacketAuthentication.verifyOrigin(parsed!!, key))
            assertEquals(MeshPacket.PROTOCOL_VERSION, parsed.protocolVersion)
            assertEquals(parsed.pathInvariant(), true)
        }
    }

    @Test
    fun malformedMutationsNeverThrowAndNeverProduceStructurallyInvalidPackets() {
        val rng = Random(0x46555a5aL)
        val base = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject().put("ciphertext", "abc"),
            8,
            nextHopNodeId = "B",
            packetId = "packet-fuzz-base",
            createdAt = 200_000L,
        ).withOriginAuth(MeshPacketAuthentication.signOrigin(
            MeshPacket.new(
                "A",
                "D",
                "direct_message",
                JSONObject().put("ciphertext", "abc"),
                8,
                nextHopNodeId = "B",
                packetId = "packet-fuzz-base",
                createdAt = 200_000L,
            ),
            key,
        ))

        repeat(4_000) { index ->
            val candidate = mutate(base.toJson(), rng, index)
            val parsed = runCatching { MeshPacket.fromJson(candidate) }.getOrNull()
            if (parsed != null) {
                assertEquals(MeshPacket.PROTOCOL_VERSION, parsed.protocolVersion)
                assertTrue(MeshIdPolicy.isValid(parsed.packetId))
                assertTrue(MeshIdPolicy.isValid(parsed.sourceNodeId))
                assertTrue(MeshIdPolicy.isValid(parsed.destinationNodeId))
                assertTrue(parsed.sourceNodeId != parsed.destinationNodeId)
                assertTrue(MeshLimits.hasValidHopBudget(parsed.ttl, parsed.hopCount))
                assertTrue(parsed.pathInvariant())
                assertTrue(MeshPacketAuthentication.isValidOriginAuth(parsed.originAuth.orEmpty()))
            }
        }
    }

    @Test
    fun routeControlFuzzNeverAcceptsTamperedAuthentication() {
        val rng = Random(0x524f555445L)
        repeat(3_000) { index ->
            val unsigned = JSONObject()
                .put("type", if (index % 2 == 0) "route_advertisement" else "route_withdrawal")
                .put("route_protocol_version", 2)
                .put("sender_id", "B")
                .put("session_id", "session-fuzz")
                .put("control_sequence", index + 1L)
                .put("advertisement_sequence", index + 1L)
                .put("sent_at", 500_000L + index)
                .put("routes", JSONArray().put(JSONObject()
                    .put("destination_node_id", "D")
                    .put("hop_count", 2)
                    .put("route_version", index + 1L)
                    .put("path", JSONArray().put("B").put("C").put("D"))))
                .put("destinations", JSONArray().put("D"))

            val signed = MeshRouteAdvertisementAuthenticator.withAuth(unsigned, "route-fuzz-key")
            check(MeshRouteAdvertisementAuthenticator.verify(signed, "route-fuzz-key"))

            val mutated = JSONObject(signed.toString())
            when (rng.nextInt(7)) {
                0 -> mutated.put("sender_id", "EVIL")
                1 -> mutated.put("control_sequence", Long.MAX_VALUE)
                2 -> mutated.put("advertisement_sequence", Long.MAX_VALUE)
                3 -> mutated.put("sent_at", 0L)
                4 -> mutated.put("routes", JSONArray())
                5 -> mutated.put("route_auth", "0".repeat(64))
                else -> mutated.put("destinations", JSONArray().put("EVIL"))
            }
            check(!MeshRouteAdvertisementAuthenticator.verify(mutated, "route-fuzz-key"))
        }
    }

    @Test
    fun malformedPayloadShapesAreRejectedOrSafelyIgnored() {
        val packet = MeshPacket.new(
            "A",
            "D",
            "direct_message",
            JSONObject().put("ciphertext", "abc"),
            8,
            packetId = "payload-shape-base",
            createdAt = 300_000L,
        ).withOriginAuth(MeshPacketAuthentication.signOrigin(
            MeshPacket.new(
                "A",
                "D",
                "direct_message",
                JSONObject().put("ciphertext", "abc"),
                8,
                packetId = "payload-shape-base",
                createdAt = 300_000L,
            ),
            key,
        ))
        val variants = listOf(
            packet.toJson().put("payload", "not-object"),
            packet.toJson().put("ttl", "8"),
            packet.toJson().put("hop_count", "0"),
            packet.toJson().put("mesh_version", 0),
            packet.toJson().put("packet_id", JSONObject()),
            packet.toJson().put("origin_auth", JSONArray()),
            packet.toJson().put("source_node_id", "A D"),
        )
        variants.forEach { json -> assertNull(runCatching { MeshPacket.fromJson(json) }.getOrNull()) }
    }

    private fun mutate(source: JSONObject, rng: Random, index: Int): JSONObject {
        val json = JSONObject(source.toString())
        when (rng.nextInt(12)) {
            0 -> json.remove("packet_id")
            1 -> json.put("mesh_version", rng.nextInt(5) - 1)
            2 -> json.put("ttl", rng.nextInt(15) - 3)
            3 -> json.put("hop_count", rng.nextInt(15) - 3)
            4 -> json.put("source_node_id", randomAscii(rng, rng.nextInt(150)))
            5 -> json.put("destination_node_id", randomAscii(rng, rng.nextInt(150)))
            6 -> json.put("next_hop_node_id", randomAscii(rng, rng.nextInt(150)))
            7 -> json.put("created_at", if (index % 2 == 0) 0L else Long.MAX_VALUE)
            8 -> json.put("origin_auth", randomHexish(rng, rng.nextInt(100)))
            9 -> json.put("payload", JSONObject().put(MeshPacket.MESH_PATH_KEY, randomPath(rng)))
            10 -> json.put("payload", JSONObject().put(MeshPacket.MESH_PATH_KEY, "not-array"))
            else -> json.put("type", randomAscii(rng, rng.nextInt(150)))
        }
        return json
    }

    private fun randomPath(rng: Random): JSONArray {
        val array = JSONArray()
        repeat(rng.nextInt(10)) { array.put(randomAscii(rng, rng.nextInt(30))) }
        return array
    }

    private fun randomAscii(rng: Random, length: Int): String = buildString(length) {
        repeat(length) { append(('a'.code + rng.nextInt(26)).toChar()) }
    }

    private fun randomHexish(rng: Random, length: Int): String {
        val alphabet = "0123456789abcdefXYZ"
        return buildString(length) { repeat(length) { append(alphabet[rng.nextInt(alphabet.length)]) } }
    }

    private fun MeshPacket.pathInvariant(): Boolean {
        val path = normalizedPath()
        if (path.isEmpty() || path.firstOrNull() != sourceNodeId) return false
        if (path.size != maxOf(1, hopCount)) return false
        if (path.distinct().size != path.size) return false
        return path.all(MeshIdPolicy::isValid)
    }
}
