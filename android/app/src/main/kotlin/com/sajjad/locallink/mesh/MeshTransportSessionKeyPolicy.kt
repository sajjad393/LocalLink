package com.sajjad.locallink.mesh

import java.nio.charset.StandardCharsets
import java.security.MessageDigest

/** Rolling per-hop transport-key derivation with a one-epoch grace window. */
object MeshTransportSessionKeyPolicy {
    const val ROTATION_MS = 15L * 60L * 1000L
    private const val DOMAIN = "locallink-hop-session-v2"

    fun currentEpoch(now: Long = System.currentTimeMillis()): Long {
        require(now > 0L) { "invalid timestamp" }
        return now / ROTATION_MS
    }

    fun acceptedEpochs(now: Long = System.currentTimeMillis()): Set<Long> {
        val current = currentEpoch(now)
        return linkedSetOf(current, current - 1L, current + 1L)
    }

    fun deriveKey(
        sharedKey: String,
        senderNodeId: String,
        receiverNodeId: String,
        epoch: Long,
    ): ByteArray {
        require(sharedKey.isNotBlank()) { "shared key is required" }
        require(MeshIdPolicy.isValid(senderNodeId)) { "invalid sender" }
        require(MeshIdPolicy.isValid(receiverNodeId)) { "invalid receiver" }
        require(epoch >= 0L) { "invalid epoch" }
        val material = "$DOMAIN|$sharedKey|$senderNodeId|$receiverNodeId|$epoch"
            .toByteArray(StandardCharsets.UTF_8)
        return MessageDigest.getInstance("SHA-256").digest(material)
    }
}
