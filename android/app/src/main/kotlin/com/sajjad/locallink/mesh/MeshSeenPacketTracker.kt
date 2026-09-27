package com.sajjad.locallink.mesh

import java.util.HashMap
import java.util.LinkedHashSet
import java.util.TreeMap

/**
 * Bounded duplicate/replay tracker keyed by immutable origin + packet ID.
 * A packet ID is retained across every hop; relays never mint a replacement ID.
 *
 * Cleanup is deliberately throttled because scanning the full cache on every packet
 * makes a large flood quadratic. Capacity eviction remains O(log n) using timestamp
 * buckets, so the memory bound stays strict without turning packet admission into a
 * CPU exhaustion vector.
 */
class MeshSeenPacketTracker(
    private val maxEntries: Int = MeshLimits.MAX_SEEN_PACKETS,
    private val retentionMs: Long = MeshLimits.SEEN_RETENTION_MS,
    private val onEvicted: ((String, Long) -> Unit)? = null,
    private val cleanupIntervalMs: Long = 1_000L,
) {
    init {
        require(maxEntries > 0) { "maxEntries must be positive" }
        require(retentionMs > 0L) { "retentionMs must be positive" }
        require(cleanupIntervalMs > 0L) { "cleanupIntervalMs must be positive" }
    }

    private val seen = HashMap<String, Long>()
    private val byTimestamp = TreeMap<Long, LinkedHashSet<String>>()
    private val separator = "\u0000"
    private var lastCleanupAt = Long.MIN_VALUE

    @Synchronized
    fun markSeen(sourceNodeId: String, packetId: String, now: Long = System.currentTimeMillis()): Boolean {
        val source = sourceNodeId.trim()
        val packet = packetId.trim()
        if (!MeshIdPolicy.isValid(source) || !MeshIdPolicy.isValid(packet) || now <= 0L) return false
        maybeCleanup(now)

        val key = key(source, packet)
        if (seen.containsKey(key)) return false
        put(key, now)
        enforceCapacity()
        return true
    }

    /**
     * Restores a durable entry only while its replay window is still valid.
     * Future-dated entries are rejected rather than extending the replay window.
     */
    @Synchronized
    fun restore(
        sourceNodeId: String,
        packetId: String,
        seenAt: Long,
        now: Long = System.currentTimeMillis(),
    ): Boolean {
        val source = sourceNodeId.trim()
        val packet = packetId.trim()
        if (!MeshIdPolicy.isValid(source) || !MeshIdPolicy.isValid(packet) || !isFresh(seenAt, now)) return false
        maybeCleanup(now)
        val key = key(source, packet)
        if (seen.containsKey(key)) return false
        put(key, seenAt)
        enforceCapacity()
        return true
    }

    @Synchronized
    fun cleanup(now: Long = System.currentTimeMillis()) {
        if (now <= 0L) return
        cleanupInternal(now)
    }

    @Synchronized
    fun size(): Int = seen.size

    @Synchronized
    fun clear() {
        seen.clear()
        byTimestamp.clear()
        lastCleanupAt = Long.MIN_VALUE
    }

    fun keyFor(sourceNodeId: String, packetId: String): String = key(sourceNodeId.trim(), packetId.trim())

    private fun key(sourceNodeId: String, packetId: String): String = "$sourceNodeId$separator$packetId"

    private fun isFresh(seenAt: Long, now: Long): Boolean =
        now > 0L && seenAt > 0L && seenAt <= now && now - seenAt <= retentionMs

    private fun maybeCleanup(now: Long) {
        if (lastCleanupAt == Long.MIN_VALUE || now < lastCleanupAt || now - lastCleanupAt >= cleanupIntervalMs) {
            cleanupInternal(now)
        }
    }

    private fun cleanupInternal(now: Long) {
        val cutoff = now - retentionMs
        val expiredKeys = mutableListOf<Pair<String, Long>>()

        val oldBuckets = byTimestamp.headMap(cutoff, false).entries.toList()
        oldBuckets.forEach { (timestamp, keys) ->
            keys.forEach { key -> expiredKeys += key to timestamp }
        }

        val futureBuckets = byTimestamp.tailMap(now, false).entries.toList()
        futureBuckets.forEach { (timestamp, keys) ->
            keys.forEach { key -> expiredKeys += key to timestamp }
        }

        expiredKeys.forEach { (key, timestamp) ->
            remove(key, timestamp)?.let { onEvicted?.invoke(key, it) }
        }
        lastCleanupAt = now
        enforceCapacity()
    }

    private fun put(key: String, seenAt: Long) {
        seen[key] = seenAt
        byTimestamp.getOrPut(seenAt) { LinkedHashSet() }.add(key)
    }

    private fun remove(key: String, expectedTimestamp: Long? = null): Long? {
        val value = seen.remove(key) ?: return null
        if (expectedTimestamp == null || expectedTimestamp == value) {
            byTimestamp[value]?.let { keys ->
                keys.remove(key)
                if (keys.isEmpty()) byTimestamp.remove(value)
            }
        } else {
            byTimestamp[expectedTimestamp]?.let { keys ->
                keys.remove(key)
                if (keys.isEmpty()) byTimestamp.remove(expectedTimestamp)
            }
            byTimestamp[value]?.let { keys ->
                keys.remove(key)
                if (keys.isEmpty()) byTimestamp.remove(value)
            }
        }
        return value
    }

    private fun enforceCapacity() {
        while (seen.size > maxEntries) {
            val bucket = byTimestamp.firstEntry() ?: break
            val key = bucket.value.iterator().next()
            val timestamp = bucket.key
            remove(key, timestamp)?.let { onEvicted?.invoke(key, it) }
        }
    }
}
