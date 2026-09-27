package com.sajjad.locallink.mesh

/**
 * Tracks destinations temporarily affected by loss of a next-hop peer.
 * The tracker is deliberately transport-independent so disconnect/reconnect
 * behavior can be tested without Android sockets.
 */
class MeshRouteRecoveryTracker(
    private val retentionMs: Long = 60_000L,
    private val maxEntries: Int = MeshLimits.MAX_ROUTE_RECOVERY_DESTINATIONS,
) {
    data class RecoveryEntry(
        val destinationNodeId: String,
        val failedNextHopNodeId: String,
        val startedAt: Long,
        var lastSeenAt: Long,
    )

    init {
        require(retentionMs > 0L) { "retentionMs must be positive" }
        require(maxEntries > 0) { "maxEntries must be positive" }
    }

    private val entries = linkedMapOf<String, RecoveryEntry>()

    @Synchronized
    fun markPeerLost(failedNextHopNodeId: String, destinations: Collection<String>, now: Long): List<String> {
        if (!MeshIdPolicy.isValid(failedNextHopNodeId) || now <= 0L || maxEntries <= 0) return emptyList()
        val affected = destinations.filter { it.isNotBlank() }.distinct()
        val boundedAffected = affected.take(maxEntries)
        boundedAffected.forEach { destination ->
            val existing = entries[destination]
            if (existing == null && entries.size >= maxEntries) {
                val eldest = entries.entries.firstOrNull()?.key
                if (eldest != null) entries.remove(eldest)
            }
            entries[destination] = RecoveryEntry(
                destinationNodeId = destination,
                failedNextHopNodeId = failedNextHopNodeId,
                startedAt = existing?.startedAt ?: now,
                lastSeenAt = now,
            )
        }
        return boundedAffected
    }

    @Synchronized
    fun markRecovered(destinationNodeId: String): RecoveryEntry? = entries.remove(destinationNodeId)

    @Synchronized
    fun pendingForPeer(failedNextHopNodeId: String): List<RecoveryEntry> =
        entries.values.filter { it.failedNextHopNodeId == failedNextHopNodeId }.toList()

    @Synchronized
    fun prune(now: Long): List<RecoveryEntry> {
        val expired = entries.values.filter { now - it.lastSeenAt >= retentionMs }.toList()
        expired.forEach { entries.remove(it.destinationNodeId) }
        return expired
    }

    @Synchronized
    fun snapshot(): List<Map<String, Any?>> = entries.values.sortedBy { it.destinationNodeId }.map {
        mapOf(
            "destination_id" to it.destinationNodeId,
            "failed_next_hop" to it.failedNextHopNodeId,
            "started_at" to it.startedAt,
            "last_seen_at" to it.lastSeenAt,
        )
    }

    @Synchronized
    fun size(): Int = entries.size

    @Synchronized
    fun clear() = entries.clear()
}
