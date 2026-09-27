package com.sajjad.locallink.mesh

import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap

/**
 * Dampens rapid next-hop changes so a single noisy/malicious peer cannot cause
 * continuous route flapping. Healthy alternates remain in the route table.
 */
class MeshRouteStabilityPolicy(
    private val flapWindowMs: Long = MeshLimits.ROUTE_FLAP_WINDOW_MS,
    private val maxChangesBeforeHoldDown: Int = MeshLimits.MAX_ROUTE_CHANGES_BEFORE_HOLDDOWN,
    private val holdDownMs: Long = MeshLimits.ROUTE_HOLDDOWN_MS,
    private val staleGraceMs: Long = MeshLimits.ROUTE_STALE_GRACE_MS,
) {
    data class Decision(val accepted: Boolean, val reason: String)

    private data class State(
        val changes: ArrayDeque<Long> = ArrayDeque(),
        var holdDownUntil: Long = 0L,
    )

    private val states = ConcurrentHashMap<String, State>()

    fun beforeChange(
        destinationNodeId: String,
        currentBest: MeshRoute?,
        candidate: MeshRoute,
        now: Long = System.currentTimeMillis(),
    ): Decision {
        if (!MeshIdPolicy.isValid(destinationNodeId)) return Decision(false, "invalid_destination")
        if (currentBest == null || currentBest.nextHopNodeId == candidate.nextHopNodeId) {
            return Decision(true, "stable")
        }
        if (now >= currentBest.expiresAt || currentBest.expiresAt - now <= staleGraceMs) {
            return Decision(true, "current_route_near_expiry")
        }
        val state = states.computeIfAbsent(destinationNodeId) { State() }
        synchronized(state) {
            prune(state, now)
            if (state.holdDownUntil > now) return Decision(false, "route_hold_down")
            return Decision(true, "change_allowed")
        }
    }

    fun recordAcceptedChange(
        destinationNodeId: String,
        previousNextHopId: String?,
        newNextHopId: String?,
        now: Long = System.currentTimeMillis(),
    ) {
        if (!MeshIdPolicy.isValid(destinationNodeId) || previousNextHopId == null || newNextHopId == null ||
            previousNextHopId == newNextHopId || now <= 0L) return
        val state = states.computeIfAbsent(destinationNodeId) { State() }
        synchronized(state) {
            prune(state, now)
            state.changes.addLast(now)
            if (state.changes.size >= maxChangesBeforeHoldDown) {
                state.holdDownUntil = now + holdDownMs
            }
        }
    }

    fun reset(destinationNodeId: String) {
        states.remove(destinationNodeId)
    }

    fun clear() = states.clear()

    private fun prune(state: State, now: Long) {
        val cutoff = now - flapWindowMs
        while (state.changes.isNotEmpty() && state.changes.first < cutoff) state.changes.removeFirst()
        if (state.holdDownUntil <= now && state.changes.isEmpty()) state.holdDownUntil = 0L
    }
}
