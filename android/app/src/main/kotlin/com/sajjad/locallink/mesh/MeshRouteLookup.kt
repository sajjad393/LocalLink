package com.sajjad.locallink.mesh

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

/**
 * Bundle 160 (plan 160.2): "who can reach X?".
 *
 * When this phone has no route to X it asks its neighbours (`route_query`,
 * up to 2 hops). A neighbour that has a route answers (`route_answer`) with
 * its path; the answer is kept as a normal route for 5 min. A neighbour
 * without a route asks its own neighbours once (ttl 2 -> 1) and passes the
 * answer back.
 *
 * Limits: one question per destination per 30 s, 64 open questions, 20
 * questions per neighbour per minute, every question id handled once.
 */
object MeshRouteLookupRules {
    const val MAX_TTL = 2
    const val ASK_AGAIN_MS = 30_000L
    const val ANSWER_TTL_MS = 5L * 60L * 1000L
    const val PENDING_MS = 10_000L
    const val MAX_PENDING = 64
    const val MAX_QUERIES_PER_PEER = 20
    const val QUERY_WINDOW_MS = 60_000L
    const val MAX_SEEN = 512
    private val idPattern = Regex("^[0-9a-f]{16}$")

    fun validQueryId(id: String?): Boolean = id != null && idPattern.matches(id)
}

class MeshRouteLookup(private val random: SecureRandom = SecureRandom()) {
    /** Who asked (null = this phone itself). */
    data class Pending(val target: String, val askedBy: String?, val at: Long)

    private val lastAsked = ConcurrentHashMap<String, Long>()
    private val pending = ConcurrentHashMap<String, Pending>()
    private val seen = LinkedHashMap<String, Long>()
    private val perPeer = ConcurrentHashMap<String, LongArray>() // [windowStart, count]

    /** Should this phone ask about [target] now? Returns a new query id or null. */
    fun ask(target: String, now: Long): String? {
        if (!MeshIdPolicy.isValid(target)) return null
        prune(now)
        val last = lastAsked[target]
        if (last != null && now - last < MeshRouteLookupRules.ASK_AGAIN_MS) return null
        if (pending.size >= MeshRouteLookupRules.MAX_PENDING) return null
        lastAsked[target] = now
        val id = newId()
        pending[id] = Pending(target, null, now)
        markSeen(id, now)
        return id
    }

    enum class QueryAction { DROP, ANSWER, PASS_ON, NOTHING }

    /**
     * A neighbour asked. [haveRoute] = this phone has a usable route to the
     * target that does not go back through the asker.
     */
    fun onQuery(fromPeer: String, queryId: String, target: String, ttl: Int, haveRoute: Boolean, now: Long): QueryAction {
        if (!MeshRouteLookupRules.validQueryId(queryId) || !MeshIdPolicy.isValid(target) || !MeshIdPolicy.isValid(fromPeer)) return QueryAction.DROP
        if (ttl !in 1..MeshRouteLookupRules.MAX_TTL) return QueryAction.DROP
        if (!allowPeer(fromPeer, now)) return QueryAction.DROP
        prune(now)
        if (!markSeen(queryId, now)) return QueryAction.DROP
        if (haveRoute) return QueryAction.ANSWER
        if (ttl <= 1 || pending.size >= MeshRouteLookupRules.MAX_PENDING) return QueryAction.NOTHING
        pending[queryId] = Pending(target, fromPeer, now)
        return QueryAction.PASS_ON
    }

    /** An answer arrived: the open question it belongs to (removed), or null. */
    fun onAnswer(queryId: String, target: String, now: Long): Pending? {
        prune(now)
        val p = pending[queryId] ?: return null
        if (p.target != target) return null
        pending.remove(queryId, p)
        return p
    }

    fun pendingCount(): Int = pending.size

    fun clear() {
        lastAsked.clear()
        pending.clear()
        synchronized(seen) { seen.clear() }
        perPeer.clear()
    }

    private fun allowPeer(peer: String, now: Long): Boolean {
        val w = perPeer.computeIfAbsent(peer) { longArrayOf(now, 0L) }
        synchronized(w) {
            if (now - w[0] >= MeshRouteLookupRules.QUERY_WINDOW_MS) { w[0] = now; w[1] = 0L }
            if (w[1] >= MeshRouteLookupRules.MAX_QUERIES_PER_PEER) return false
            w[1] += 1
            return true
        }
    }

    /** True the first time [id] is seen. */
    private fun markSeen(id: String, now: Long): Boolean = synchronized(seen) {
        if (seen.containsKey(id)) return false
        seen[id] = now
        while (seen.size > MeshRouteLookupRules.MAX_SEEN) seen.remove(seen.keys.first())
        true
    }

    private fun prune(now: Long) {
        pending.entries.removeIf { now - it.value.at > MeshRouteLookupRules.PENDING_MS }
        lastAsked.entries.removeIf { now - it.value > MeshRouteLookupRules.ASK_AGAIN_MS * 4 }
    }

    private fun newId(): String {
        val b = ByteArray(8)
        random.nextBytes(b)
        return b.joinToString("") { "%02x".format(it) }
    }
}
