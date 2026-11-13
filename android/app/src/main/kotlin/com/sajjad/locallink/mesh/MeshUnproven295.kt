package com.sajjad.locallink.mesh

import java.util.concurrent.ConcurrentHashMap

/**
 * Bundle 295 (G1): a call to a friend got no answer in 6 s although a stored
 * mesh way to them existed. That way is dropped and, for [holdMs], adverts
 * and lookup answers for that friend through the SAME next phone are not
 * taken (its own table is old too, it would only bring the dead way back).
 * Other next phones are asked and taken as usual.
 *
 * Proof from the friend (any packet from them, or a direct link to them)
 * ends the hold at once.
 */
class MeshUnproven295(private val holdMs: Long = HOLD_MS) {
    companion object {
        const val HOLD_MS = 15_000L
    }

    /** destination -> (next hop -> held until). */
    private val held = ConcurrentHashMap<String, ConcurrentHashMap<String, Long>>()

    fun hold(destination: String, nextHops: Collection<String>, now: Long) {
        if (destination.isBlank() || nextHops.isEmpty()) return
        val hops = held.computeIfAbsent(destination) { ConcurrentHashMap() }
        for (hop in nextHops) if (hop.isNotBlank() && hop != destination) hops[hop] = now + holdMs
        if (hops.isEmpty()) held.remove(destination, hops)
    }

    /** True = do not take a way to [destination] through [nextHop] now. */
    fun blocks(destination: String, nextHop: String, now: Long): Boolean {
        val hops = held[destination] ?: return false
        val until = hops[nextHop] ?: return false
        if (now < until) return true
        hops.remove(nextHop, until)
        if (hops.isEmpty()) held.remove(destination, hops)
        return false
    }

    /** Proof from [destination]: the hold ends. True when one was running. */
    fun proven(destination: String): Boolean = held.remove(destination) != null

    fun isHeld(destination: String, now: Long): Boolean =
        held[destination]?.values?.any { now < it } == true
}
