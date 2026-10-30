package com.sajjad.locallink.mesh

import java.util.concurrent.ConcurrentHashMap

/**
 * Bundle 160 (plan 160.1): smaller route updates for 300+ phones.
 *
 * Before: every 10 s each phone sent its whole map (top 128 routes) to every
 * neighbour. Now, to neighbours whose app understands it (`rd=1` in the link
 * hello):
 *  * every 5-10 s only what CHANGED (new/changed routes + withdrawn ones),
 *    numbered per neighbour (`dseq` 1, 2, 3 ...);
 *  * every 60 s the full map, in pages of 128;
 *  * a phone that misses a number asks for the full map again
 *    (`route_full_request`).
 * Older phones keep getting the old full advertisement every 10 s.
 */
data class MeshAdvertisedRoute(
    val destination: String,
    val hopCount: Int,
    val routeVersion: Long,
    val path: List<String>,
)

object MeshRouteDeltaRules {
    const val MODE_FULL = "full"
    const val MODE_DELTA = "delta"
    /** Changes go out at most this often after something changed... */
    const val DELTA_MIN_GAP_MS = 5_000L
    /** ...and at least this often (an empty delta = "still here"). */
    const val DELTA_INTERVAL_MS = 10_000L
    const val FULL_REFRESH_MS = 60_000L
    const val PAGE_SIZE = MeshLimits.MAX_ROUTE_ADVERTISEMENT_ROUTES
    /** Routes learned from a delta neighbour live past one full refresh. */
    const val ROUTE_TTL_MS = 90_000L
    /** Routes learned from an older phone (full ad every 10 s), as before. */
    const val LEGACY_ROUTE_TTL_MS = 30_000L
    /** A neighbour gets at most one extra full map per this long. */
    const val FULL_REQUEST_MIN_GAP_MS = 15_000L

    /** Splits [routes] into pages of [pageSize] (always at least one page). */
    fun pages(routes: List<MeshAdvertisedRoute>, pageSize: Int = PAGE_SIZE): List<List<MeshAdvertisedRoute>> {
        require(pageSize > 0)
        if (routes.isEmpty()) return listOf(emptyList())
        return routes.chunked(pageSize)
    }
}

/** Sender side: what changed since the last delta, and per-neighbour numbers. */
class MeshRouteDeltaSender {
    data class Delta(val changed: List<MeshAdvertisedRoute>, val withdrawn: List<String>) {
        val isEmpty: Boolean get() = changed.isEmpty() && withdrawn.isEmpty()
        val size: Int get() = changed.size + withdrawn.size
    }

    private var last: Map<String, MeshAdvertisedRoute> = emptyMap()
    private val seq = ConcurrentHashMap<String, Long>()
    private val lastFullAt = ConcurrentHashMap<String, Long>()
    private val lastFullRequestAt = ConcurrentHashMap<String, Long>()

    /** Compares [current] with the previous call and remembers [current]. */
    @Synchronized
    fun diff(current: List<MeshAdvertisedRoute>): Delta {
        val now = LinkedHashMap<String, MeshAdvertisedRoute>()
        current.forEach { now.putIfAbsent(it.destination, it) }
        val changed = now.values.filter { last[it.destination] != it }
        val withdrawn = last.keys.filter { it !in now }.sorted()
        last = now
        return Delta(changed, withdrawn)
    }

    /** Splits a big delta so no message has more than [pageSize] of each kind. */
    fun chunks(delta: Delta, pageSize: Int = MeshRouteDeltaRules.PAGE_SIZE): List<Delta> {
        if (delta.changed.size <= pageSize && delta.withdrawn.size <= pageSize) return listOf(delta)
        val c = delta.changed.chunked(pageSize)
        val w = delta.withdrawn.chunked(pageSize)
        return (0 until maxOf(c.size, w.size)).map { i ->
            Delta(c.getOrElse(i) { emptyList() }, w.getOrElse(i) { emptyList() })
        }
    }

    fun needsFull(peerId: String, now: Long): Boolean {
        val at = lastFullAt[peerId] ?: return true
        return now - at >= MeshRouteDeltaRules.FULL_REFRESH_MS
    }

    fun markFull(peerId: String, now: Long) { lastFullAt[peerId] = now }

    /** The number full pages carry (the receiver's starting point). */
    fun currentSeq(peerId: String): Long = seq[peerId] ?: 0L

    /** Next delta number for [peerId] (1, 2, 3 ...). */
    fun nextSeq(peerId: String): Long = seq.merge(peerId, 1L, Long::plus) ?: 1L

    /** A neighbour missed a delta: full map again, at most once per 15 s. */
    fun requestFull(peerId: String, now: Long): Boolean {
        val last = lastFullRequestAt[peerId]
        if (last != null && now - last < MeshRouteDeltaRules.FULL_REQUEST_MIN_GAP_MS) return false
        lastFullRequestAt[peerId] = now
        lastFullAt.remove(peerId)
        return true
    }

    fun forget(peerId: String) {
        seq.remove(peerId)
        lastFullAt.remove(peerId)
        lastFullRequestAt.remove(peerId)
    }

    @Synchronized
    fun reset() {
        last = emptyMap()
        seq.clear()
        lastFullAt.clear()
        lastFullRequestAt.clear()
    }
}

/** Receiver side: notices a missed delta. */
class MeshRouteDeltaReceiver {
    private data class State(var session: String, var seq: Long, var lastRequestAt: Long = 0L)
    private val states = ConcurrentHashMap<String, State>()

    /** A full page arrived: its `dseq` is the new starting point. */
    fun onFull(peerId: String, session: String, dseq: Long) {
        val s = states[peerId]
        if (s == null || s.session != session) {
            states[peerId] = State(session, dseq)
        } else synchronized(s) { s.seq = dseq } // a full map is the new start
    }

    /** A delta arrived. False = something was missed (ask for the full map). */
    fun onDelta(peerId: String, session: String, dseq: Long): Boolean {
        val s = states[peerId]
        if (s == null || s.session != session) {
            states[peerId] = State(session, dseq)
            return false
        }
        synchronized(s) {
            if (dseq <= s.seq) return true // late duplicate: nothing missed
            val inOrder = dseq == s.seq + 1
            s.seq = dseq
            return inOrder
        }
    }

    /** At most one full-map request per neighbour per 15 s. */
    fun mayRequestFull(peerId: String, now: Long): Boolean {
        val s = states[peerId] ?: return true
        synchronized(s) {
            if (s.lastRequestAt != 0L && now - s.lastRequestAt < MeshRouteDeltaRules.FULL_REQUEST_MIN_GAP_MS) return false
            s.lastRequestAt = now
            return true
        }
    }

    fun forget(peerId: String) { states.remove(peerId) }
    fun clear() = states.clear()
}
