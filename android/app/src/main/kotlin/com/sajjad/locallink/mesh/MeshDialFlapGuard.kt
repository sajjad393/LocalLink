package com.sajjad.locallink.mesh

/**
 * Bundle 224 (E): stop the quick reconnect loop.
 *
 * 2026-11-07 04:56-05:05: one phone dialled another every 2-5 s; each link
 * was closed within 0.1 s (153 times in 10 min). Contacts had no cooldown.
 *
 * Per peer: a link that lived less than [QUICK_MS] is a quick drop. After
 * [DROPS_FOR_HOLD] quick drops within [WINDOW_MS] dialling that peer is held
 * for 30 s, then 60 s, 120 s, max 300 s. A link that lives [GOOD_MS] or
 * more, a network change, or the user's Pair tap resets the peer. Answering
 * incoming links is never blocked. Thread-safe.
 */
class MeshDialFlapGuard {
    companion object {
        const val QUICK_MS = 10_000L
        const val GOOD_MS = 60_000L
        const val WINDOW_MS = 120_000L
        const val DROPS_FOR_HOLD = 3
        val HOLDS_MS = longArrayOf(30_000L, 60_000L, 120_000L, 300_000L)
        private const val MAX_PEERS = 256
    }

    private class Peer {
        val drops = ArrayList<Long>()
        var level = 0
        var holdUntil = 0L
        var freeLogged = true
    }

    private val peers = HashMap<String, Peer>()

    /** A link to [peer] ended after [livedMs]. Returns the new hold in ms
     *  (log `LINK_FLAP hold`), or 0. */
    @Synchronized
    fun onLinkEnded(peer: String, livedMs: Long, now: Long): Long {
        if (livedMs >= GOOD_MS) { peers.remove(peer); return 0L }
        if (livedMs >= QUICK_MS) return 0L
        if (peers.size >= MAX_PEERS && !peers.containsKey(peer)) {
            peers.entries.removeIf { it.value.holdUntil <= now }
            if (peers.size >= MAX_PEERS) return 0L
        }
        val p = peers.getOrPut(peer) { Peer() }
        p.drops.removeAll { now - it > WINDOW_MS || it > now }
        p.drops.add(now)
        if (p.drops.size < DROPS_FOR_HOLD) return 0L
        val hold = HOLDS_MS[p.level.coerceAtMost(HOLDS_MS.size - 1)]
        if (p.level < HOLDS_MS.size - 1) p.level++
        p.holdUntil = now + hold
        p.drops.clear()
        p.freeLogged = false
        return hold
    }

    /** Ms left on the hold for [peer] (0 = may dial). */
    @Synchronized
    fun holdLeftMs(peer: String, now: Long): Long {
        val p = peers[peer] ?: return 0L
        return if (p.holdUntil > now) p.holdUntil - now else 0L
    }

    /** True once when a hold has ended (log `LINK_FLAP free`). */
    @Synchronized
    fun takeFreed(peer: String, now: Long): Boolean {
        val p = peers[peer] ?: return false
        if (p.freeLogged || p.holdUntil > now) return false
        p.freeLogged = true
        return true
    }

    fun mayDial(peer: String, now: Long): Boolean = holdLeftMs(peer, now) == 0L

    /** The user's Pair tap. */
    @Synchronized
    fun reset(peer: String) { peers.remove(peer) }

    /** A network change. */
    @Synchronized
    fun resetAll() { peers.clear() }
}
