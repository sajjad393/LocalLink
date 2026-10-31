package com.sajjad.locallink.mesh

/**
 * Bundle 172: a message from this phone may ask to leave the send queue
 * sooner than the normal 24 h. Call invites ask for 60 s — a phone rings for
 * about a minute, so an older invite must never be delivered (a cancelled
 * call used to ring when the other phone came back hours later).
 *
 * * Only this phone's own packets use the hint; packets passed on for
 *   others keep their normal rules.
 * * The hint can only make the wait shorter, never longer (min 5 s).
 */
object MeshQueueLifetimePolicy {
    /** Payload field (milliseconds), readable outside the lock. */
    const val FIELD: String = "qt"
    const val MIN_MS: Long = 5_000L

    fun expiresAt(now: Long, normalExpiry: Long, requestedMs: Long, ownPacket: Boolean): Long {
        if (!ownPacket || requestedMs <= 0L) return normalExpiry
        return minOf(normalExpiry, now + requestedMs.coerceAtLeast(MIN_MS))
    }
}
