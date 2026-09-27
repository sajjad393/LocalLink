package com.sajjad.locallink.mesh

import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Authentication primitives for the canonical mesh envelope.
 *
 * Origin authentication is end-to-end: the source signs immutable packet
 * identity/content, and only the final recipient verifies it with the
 * source↔destination shared key.
 *
 * Hop authentication is provided by the authenticated transport envelope.
 * The transport binds the two peer identities as AEAD associated data, while
 * the complete MeshPacket envelope is encrypted/authenticated by AES-GCM.
 */
object MeshPacketAuthentication {
    const val ORIGIN_AUTH_ALGORITHM = "HMAC-SHA256"
    const val ORIGIN_AUTH_VERSION = "1"
    private const val ORIGIN_AUTH_DOMAIN = "locallink-mesh-origin-v1"
    private const val HOP_AUTH_DOMAIN = "locallink-mesh-hop-aead-v1"
    private const val HEX_LENGTH = 64

    fun signOrigin(packet: MeshPacket, sharedKey: String): String {
        require(packet.protocolVersion == MeshPacket.PROTOCOL_VERSION) { "canonical v1 packet required" }
        require(sharedKey.isNotBlank()) { "origin shared key is required" }
        return hmacSha256(sharedKey, originSigningInput(packet))
    }

    fun verifyOrigin(packet: MeshPacket, sharedKey: String): Boolean {
        if (packet.protocolVersion != MeshPacket.PROTOCOL_VERSION ||
            sharedKey.isBlank() || packet.sourceNodeId == packet.destinationNodeId) return false
        val provided = packet.originAuth ?: return false
        if (!isValidOriginAuth(provided)) return false
        val expected = signOrigin(packet, sharedKey)
        return MessageDigest.isEqual(
            expected.toByteArray(StandardCharsets.US_ASCII),
            provided.toByteArray(StandardCharsets.US_ASCII),
        )
    }

    fun isValidOriginAuth(value: String): Boolean =
        value.length == HEX_LENGTH && value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

    /**
     * Binds source/destination/type/timestamp/packet-id and the immutable
     * application payload. mesh_path is intentionally hop-local and is
     * excluded by MeshPacket.originAuthInput().
     */
    fun originSigningInput(packet: MeshPacket): String =
        listOf(ORIGIN_AUTH_DOMAIN, ORIGIN_AUTH_VERSION, packet.originAuthInput())
            .joinToString("|")

    /**
     * AEAD associated data for a single authenticated transport hop. The
     * connection has already authenticated the peer key, and this AAD binds
     * the identities carried outside the encrypted packet body. The packet
     * envelope itself is encrypted/authenticated by AES-GCM, so changing any
     * packet header field (including next-hop, TTL, or hop-count) also fails
     * the GCM tag.
     */
    fun hopIdentityAad(senderNodeId: String, receiverNodeId: String): ByteArray =
        buildHopIdentityAad(senderNodeId, receiverNodeId, null)

    /** AAD variant that also binds the rolling transport-key epoch. */
    fun hopIdentityAad(senderNodeId: String, receiverNodeId: String, keyEpoch: Long): ByteArray =
        buildHopIdentityAad(senderNodeId, receiverNodeId, keyEpoch)

    private fun buildHopIdentityAad(senderNodeId: String, receiverNodeId: String, keyEpoch: Long?): ByteArray {
        require(MeshIdPolicy.isValid(senderNodeId)) { "invalid hop sender" }
        require(MeshIdPolicy.isValid(receiverNodeId)) { "invalid hop receiver" }
        if (keyEpoch != null) require(keyEpoch >= 0L) { "invalid key epoch" }
        val aad = JSONObject()
            .put("domain", HOP_AUTH_DOMAIN)
            .put("sender_node_id", senderNodeId)
            .put("receiver_node_id", receiverNodeId)
        if (keyEpoch != null) aad.put("key_epoch", keyEpoch)
        return canonicalJson(aad).toByteArray(StandardCharsets.UTF_8)
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

    private fun hmacSha256(sharedKey: String, value: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(sharedKey.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(value.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
