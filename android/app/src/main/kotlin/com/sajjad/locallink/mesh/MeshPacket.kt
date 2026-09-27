package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Canonical mesh routing envelope.
 *
 * New traffic MUST use protocol version 1. Relays may rewrite only hop-local
 * fields (next hop, TTL, hop count and path). Application payload remains
 * opaque to the mesh layer and should contain its own end-to-end ciphertext.
 */
data class MeshPacket(
    val packetId: String,
    val sourceNodeId: String,
    val destinationNodeId: String,
    val nextHopNodeId: String?,
    val ttl: Int,
    val hopCount: Int,
    val type: String,
    val payload: JSONObject,
    val createdAt: Long,
    val originAuth: String? = null,
    val protocolVersion: Int = PROTOCOL_VERSION,
) {
    fun copyForForwarding(nextHop: String, localNodeId: String, maxHops: Int = MeshLimits.MAX_HOPS): MeshPacket {
        require(protocolVersion == PROTOCOL_VERSION) { "non-canonical packet cannot be forwarded" }
        require(MeshIdPolicy.isValid(packetId)) { "invalid packet id" }
        require(MeshIdPolicy.isValid(sourceNodeId)) { "invalid source node" }
        require(MeshIdPolicy.isValid(destinationNodeId)) { "invalid destination node" }
        require(MeshIdPolicy.isValid(nextHop)) { "invalid next hop" }
        require(MeshIdPolicy.isValid(localNodeId)) { "invalid local node" }
        require(MeshLimits.hasValidHopBudget(ttl, hopCount, maxHops)) { "invalid hop budget" }
        require(MeshLimits.canForward(ttl, hopCount, maxHops)) { "hop limit reached" }
        val nextPath = forwardedPath(localNodeId)
        val nextTtl = ttl - 1
        val nextHopCount = hopCount + 1
        require(MeshLimits.hasValidHopBudget(nextTtl, nextHopCount, maxHops)) { "forwarded hop budget invalid" }
        return copy(
            nextHopNodeId = nextHop,
            // Packet identity and origin metadata are immutable across all hops.
            packetId = packetId,
            sourceNodeId = sourceNodeId,
            destinationNodeId = destinationNodeId,
            ttl = nextTtl,
            hopCount = nextHopCount,
            payload = JSONObject(payload.toString()).put(MESH_PATH_KEY, JSONArray(nextPath)),
        )
    }

    fun toJson(): JSONObject = JSONObject()
        .put(PROTOCOL_VERSION_KEY, protocolVersion)
        .put("packet_id", packetId)
        .put("source_node_id", sourceNodeId)
        .put("destination_node_id", destinationNodeId)
        .put("next_hop_node_id", nextHopNodeId)
        .put("ttl", ttl)
        .put("hop_count", hopCount)
        .put("type", type)
        .put("payload", JSONObject(payload.toString()))
        .put("created_at", createdAt)
        .putOpt("origin_auth", originAuth)

    fun withOriginAuth(value: String): MeshPacket {
        val normalized = value.trim().ifBlank { null }
        require(normalized == null || MeshPacketAuthentication.isValidOriginAuth(normalized)) { "invalid origin auth" }
        return copy(originAuth = normalized)
    }

    /** Stable, unambiguous representation used for end-to-end origin authentication. */
    fun originAuthInput(): String {
        val immutablePayload = JSONObject(payload.toString()).also { it.remove(MESH_PATH_KEY) }
        val envelope = JSONObject()
            .put(PROTOCOL_VERSION_KEY, PROTOCOL_VERSION)
            .put("packet_id", packetId)
            .put("source_node_id", sourceNodeId)
            .put("destination_node_id", destinationNodeId)
            .put("type", type)
            .put("created_at", createdAt)
            .put("payload", immutablePayload)
        return canonicalJson(envelope)
    }

    fun normalizedPath(): List<String> {
        val value = payload.optJSONArray(MESH_PATH_KEY) ?: return emptyList()
        val result = mutableListOf<String>()
        for (i in 0 until value.length()) {
            result.add(value.optString(i).trim())
        }
        return result
    }

    /**
     * Adapts a validated canonical packet to the application event payload used
     * by the Flutter bridge. This is an application adapter, not a legacy wire
     * format and must never be fed back into mesh routing.
     */
    fun toApplicationPayload(): JSONObject {
        val out = JSONObject(payload.toString())
        out.put("sender_id", sourceNodeId)
        out.put("recipient_id", destinationNodeId)
        out.put("mesh_packet_id", packetId)
        if (!out.has("type")) out.put("type", type)
        return out
    }

    private fun forwardedPath(localNodeId: String): List<String> {
        val path = normalizedPath().toMutableList()
        val expectedCurrentSize = maxOf(1, hopCount)
        require(path.isNotEmpty()) { "mesh path is required" }
        require(path.first() == sourceNodeId) { "mesh path must start at source" }
        require(path.distinct().size == path.size) { "mesh path contains a duplicate node" }
        require(path.size == expectedCurrentSize) { "mesh path length does not match hop count" }

        // The origin is already present at hop 0. Every relay must add itself exactly
        // once before forwarding, and a relay that already appears in the path is a loop.
        if (hopCount == 0) {
            require(localNodeId == sourceNodeId) { "origin forwarding must start at source" }
            return path
        }
        require(localNodeId != sourceNodeId && localNodeId !in path) { "forwarding loop detected" }
        path.add(localNodeId)
        require(path.size == hopCount + 1) { "forwarded mesh path length mismatch" }
        return path
    }

    companion object {
        const val PROTOCOL_VERSION: Int = 1
        const val LEGACY_PROTOCOL_VERSION: Int = 0
        const val PROTOCOL_VERSION_KEY: String = "mesh_version"
        const val MESH_PATH_KEY: String = "mesh_path"

        fun new(
            sourceNodeId: String,
            destinationNodeId: String,
            type: String,
            payload: JSONObject,
            ttl: Int,
            nextHopNodeId: String? = null,
            packetId: String = UUID.randomUUID().toString(),
            createdAt: Long = System.currentTimeMillis(),
        ): MeshPacket {
            val source = sourceNodeId.trim()
            val destination = destinationNodeId.trim()
            val id = packetId.trim()
            val nextHop = nextHopNodeId?.trim()?.ifBlank { null }
            val packetType = type.trim()
            require(MeshIdPolicy.isValid(source)) { "invalid source node id" }
            require(MeshIdPolicy.isValid(destination)) { "invalid destination node id" }
            require(source != destination) { "source and destination must differ" }
            require(MeshIdPolicy.isValid(packetType)) { "invalid packet type" }
            require(MeshIdPolicy.isValid(id)) { "invalid packet id" }
            require(createdAt > 0L) { "invalid created timestamp" }
            require(MeshLimits.isValidInitialTtl(ttl)) { "invalid initial TTL" }
            require(nextHop == null || MeshIdPolicy.isValid(nextHop)) { "invalid next hop id" }
            val canonicalPayload = JSONObject(payload.toString()).apply {
                remove(MESH_PATH_KEY)
                put(MESH_PATH_KEY, JSONArray().put(source))
            }
            return MeshPacket(
                packetId = id,
                sourceNodeId = source,
                destinationNodeId = destination,
                nextHopNodeId = nextHop,
                ttl = ttl,
                hopCount = 0,
                type = packetType,
                payload = canonicalPayload,
                createdAt = createdAt,
                protocolVersion = PROTOCOL_VERSION,
            )
        }

        /** Parses only the canonical version-1 wire packet. */
        fun fromJson(json: JSONObject): MeshPacket? {
            if (!json.has(PROTOCOL_VERSION_KEY)) return null
            val version = json.optInt(PROTOCOL_VERSION_KEY, -1)
            if (version != PROTOCOL_VERSION) return null
            val packetId = json.optString("packet_id").trim()
            val source = json.optString("source_node_id").trim()
            val destination = json.optString("destination_node_id").trim()
            val type = json.optString("type").trim()
            val payload = json.optJSONObject("payload") ?: return null
            val ttl = json.optInt("ttl", -1)
            val hopCount = json.optInt("hop_count", -1)
            val createdAt = json.optLong("created_at", 0L)
            if (!MeshIdPolicy.isValid(packetId) || !MeshIdPolicy.isValid(source) ||
                !MeshIdPolicy.isValid(destination) || source == destination ||
                !MeshIdPolicy.isValidType(type)) return null
            if (createdAt <= 0L || !MeshLimits.hasValidHopBudget(ttl, hopCount)) return null
            val path = payload.optJSONArray(MESH_PATH_KEY) ?: return null
            val pathIds = mutableListOf<String>()
            for (i in 0 until path.length()) {
                val id = path.optString(i).trim()
                if (!MeshIdPolicy.isValid(id)) return null
                pathIds += id
            }
            val expectedPathSize = maxOf(1, hopCount)
            if (pathIds.size != expectedPathSize || pathIds.firstOrNull() != source || pathIds.distinct().size != pathIds.size) return null
            val nextHop = json.optString("next_hop_node_id").trim().ifBlank { null }
            if (nextHop != null && !MeshIdPolicy.isValid(nextHop)) return null
            val originAuth = json.optString("origin_auth").trim().ifBlank { null }
            if (originAuth == null || !MeshPacketAuthentication.isValidOriginAuth(originAuth)) return null
            return MeshPacket(packetId, source, destination, nextHop, ttl, hopCount, type, JSONObject(payload.toString()), createdAt, originAuth, version)
        }

        private fun canonicalJson(value: Any?): String = when (value) {
            is JSONObject -> {
                val keys = mutableListOf<String>()
                val iterator = value.keys()
                while (iterator.hasNext()) keys.add(iterator.next())
                keys.sort()
                buildString {
                    append('{')
                    keys.forEachIndexed { index, key ->
                        if (index > 0) append(',')
                        append(JSONObject.quote(key)).append(':').append(canonicalJson(value.opt(key)))
                    }
                    append('}')
                }
            }
            is JSONArray -> buildString {
                append('[')
                for (i in 0 until value.length()) {
                    if (i > 0) append(',')
                    append(canonicalJson(value.opt(i)))
                }
                append(']')
            }
            JSONObject.NULL -> "null"
            is String -> JSONObject.quote(value)
            is Number, is Boolean -> value.toString()
            else -> JSONObject.quote(value.toString())
        }
    }
}
