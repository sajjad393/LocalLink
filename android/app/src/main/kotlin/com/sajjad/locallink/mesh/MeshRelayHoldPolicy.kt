package com.sajjad.locallink.mesh

/**
 * Bundle 158 (plan 158.3): a phone that passes on someone else's SEALED
 * packet keeps it only briefly when the next hop is gone for a moment.
 *
 * - up to [HOLD_MS] (2 min), then it is dropped here; the sender's outbox
 *   still has the message (it is removed there only after the delivery ack),
 *   so it is sent again on a new route — nothing is lost, and the receiver's
 *   message-id check stops duplicates;
 * - at most [MAX_PACKETS] packets / [MAX_BYTES] bytes held for others, so a
 *   relay never fills its own outbox with strangers' traffic. When full the
 *   router answers "no route" for that packet.
 *
 * The phone's OWN packets (and plain packets between contacts) keep the
 * normal store-and-forward lifetime.
 */
object MeshRelayHoldPolicy {
    const val HOLD_MS: Long = 2L * 60L * 1000L
    const val MAX_PACKETS: Int = 64
    const val MAX_BYTES: Long = 512L * 1024L

    /** Is this a sealed packet we only carry for someone else? */
    fun isRelayHold(sourceNodeId: String, localNodeId: String?, type: String?): Boolean =
        !localNodeId.isNullOrBlank() && sourceNodeId != localNodeId && MeshRelayPolicy.isSealed(type)

    /** Expiry for a held packet: never later than the packet itself. */
    fun expiresAt(now: Long, packetExpiry: Long): Long = minOf(packetExpiry, now + HOLD_MS)

    /** Room for one more held packet of [size] bytes? */
    fun admits(heldPackets: Int, heldBytes: Long, size: Long): Boolean =
        heldPackets < MAX_PACKETS && heldBytes + size <= MAX_BYTES
}
