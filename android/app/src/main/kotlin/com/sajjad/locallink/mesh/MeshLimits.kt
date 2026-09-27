package com.sajjad.locallink.mesh

/**
 * Canonical mesh safety limits. Packet TTL is the remaining forwarding budget
 * and hopCount is the number of forwarding hops already consumed.
 *
 * The production origin always starts with MAX_TTL (8). A source may choose a
 * smaller positive TTL for a deliberately shorter-lived packet. In every case,
 * a relay must decrement TTL exactly once and increment hopCount exactly once.
 */
object MeshLimits {
    const val MAX_HOPS = 8
    const val MAX_TTL = 8
    const val MIN_INITIAL_TTL = 1
    const val TERMINAL_TTL = 0

    // A canonical packet may remain valid for this long, so durable replay entries
    // must not expire earlier than the packet validity window.
    const val MAX_PACKET_AGE_MS = 24L * 60L * 60L * 1000L
    const val SEEN_RETENTION_MS = MAX_PACKET_AGE_MS

    // Live call packets are deliberately short-lived and are never persisted to disk.
    const val MAX_EPHEMERAL_SEEN_PACKETS = 4096
    const val EPHEMERAL_SEEN_RETENTION_MS = 2L * 60L * 1000L

    const val MAX_SEEN_PACKETS = 8192
    const val MAX_FUTURE_SKEW_MS = 5L * 60L * 1000L

    // Mesh control-plane bounds. These prevent an authenticated peer from
    // consuming unbounded memory or CPU by flooding route advertisements.
    const val MAX_ROUTE_TABLE_DESTINATIONS = 512
    const val MAX_ROUTES_PER_DESTINATION = 4
    const val MAX_ROUTES_PER_NEXT_HOP = 64
    const val MAX_ROUTE_ADVERTISEMENT_ROUTES = 128
    const val MAX_ROUTE_ADVERTISEMENTS_PER_PEER = 30
    const val ROUTE_ADVERTISEMENT_WINDOW_MS = 60_000L
    const val ROUTE_ADVERTISEMENT_MAX_AGE_MS = 90_000L
    const val ROUTE_ADVERTISEMENT_FUTURE_SKEW_MS = 5_000L
    const val MAX_ROUTE_VERSION_FUTURE_SKEW_MS = 5L * 60L * 1000L
    const val MAX_ROUTE_VERSION_ADVANCE_MS = 10L * 60L * 1000L
    const val ROUTE_FLAP_WINDOW_MS = 30_000L
    const val MAX_ROUTE_CHANGES_BEFORE_HOLDDOWN = 3
    const val ROUTE_HOLDDOWN_MS = 15_000L
    const val ROUTE_STALE_GRACE_MS = 5_000L
    const val MAX_ROUTE_RECOVERY_DESTINATIONS = MAX_ROUTE_TABLE_DESTINATIONS

    /** Validates an origin-created TTL. Zero is never a valid new packet TTL. */
    fun isValidInitialTtl(ttl: Int, maxTtl: Int = MAX_TTL): Boolean =
        ttl in MIN_INITIAL_TTL..maxTtl

    /**
     * Validates the packet's remaining forwarding budget.
     *
     * A packet with ttl == 0 is terminal only after at least one forwarding hop.
     * The sum ttl + hopCount can never exceed the maximum protocol budget, so a
     * relay cannot reset or increase TTL during retries or route recovery.
     */
    fun hasValidHopBudget(ttl: Int, hopCount: Int, maxHops: Int = MAX_HOPS, maxTtl: Int = MAX_TTL): Boolean {
        if (maxHops < 1 || maxTtl < 1) return false
        if (hopCount !in 0..maxHops) return false
        if (ttl !in TERMINAL_TTL..maxTtl) return false
        if (ttl == TERMINAL_TTL && hopCount == 0) return false
        if (hopCount == maxHops && ttl != TERMINAL_TTL) return false
        return ttl + hopCount <= maxHops
    }

    fun canForward(ttl: Int, hopCount: Int, maxHops: Int = MAX_HOPS): Boolean =
        ttl > TERMINAL_TTL && hopCount < maxHops && hasValidHopBudget(ttl, hopCount, maxHops)

    fun isWithinPacketLifetime(
        createdAt: Long,
        now: Long = System.currentTimeMillis(),
        maxAgeMs: Long = MAX_PACKET_AGE_MS,
        maxFutureSkewMs: Long = MAX_FUTURE_SKEW_MS,
    ): Boolean {
        if (createdAt <= 0L || now <= 0L || maxAgeMs <= 0L || maxFutureSkewMs < 0L) return false
        return createdAt >= now - maxAgeMs && createdAt <= now + maxFutureSkewMs
    }

    fun packetExpiryAt(createdAt: Long, maxAgeMs: Long = MAX_PACKET_AGE_MS): Long {
        require(createdAt > 0L) { "invalid packet creation time" }
        require(maxAgeMs > 0L) { "invalid packet age limit" }
        return if (Long.MAX_VALUE - createdAt < maxAgeMs) Long.MAX_VALUE else createdAt + maxAgeMs
    }
}
