package com.sajjad.locallink.mesh

import java.util.LinkedHashMap
import java.util.concurrent.ConcurrentHashMap

/**
 * Admission gate for route advertisements. Route advertisements are control-plane
 * traffic and therefore must have their own replay/rate/resource limits.
 */
class MeshRouteAdvertisementPolicy(
    private val maxRoutesPerAdvertisement: Int = MeshLimits.MAX_ROUTE_ADVERTISEMENT_ROUTES,
    private val maxAdvertisementsPerWindow: Int = MeshLimits.MAX_ROUTE_ADVERTISEMENTS_PER_PEER,
    private val windowMs: Long = MeshLimits.ROUTE_ADVERTISEMENT_WINDOW_MS,
    private val maxAgeMs: Long = MeshLimits.ROUTE_ADVERTISEMENT_MAX_AGE_MS,
    private val maxFutureSkewMs: Long = MeshLimits.ROUTE_ADVERTISEMENT_FUTURE_SKEW_MS,
    private val maxRememberedSessions: Int = 4,
) {
    data class Decision(val accepted: Boolean, val reason: String)

    private data class PeerState(
        var sessionId: String,
        var lastSequence: Long,
        var windowStartAt: Long,
        var windowCount: Int,
        val knownSessions: LinkedHashMap<String, Long>,
    )

    private val states = ConcurrentHashMap<String, PeerState>()

    fun evaluate(
        peerId: String,
        sessionId: String,
        sequence: Long,
        sentAt: Long,
        routeCount: Int,
        now: Long = System.currentTimeMillis(),
    ): Decision {
        if (!MeshIdPolicy.isValid(peerId) || peerId.isBlank()) return Decision(false, "invalid_sender")
        val cleanSession = sessionId.trim()
        if (cleanSession.length !in 8..128 || cleanSession.any { Character.isISOControl(it) }) {
            return Decision(false, "invalid_session")
        }
        if (sequence <= 0L) return Decision(false, "invalid_sequence")
        if (routeCount < 0 || routeCount > maxRoutesPerAdvertisement) return Decision(false, "route_count_exceeded")
        if (now <= 0L || sentAt <= 0L) return Decision(false, "invalid_timestamp")
        if (sentAt < now - maxAgeMs) return Decision(false, "stale_advertisement")
        if (sentAt > now + maxFutureSkewMs) return Decision(false, "future_advertisement")

        val state = states.computeIfAbsent(peerId) {
            PeerState(
                sessionId = cleanSession,
                lastSequence = 0L,
                windowStartAt = now,
                windowCount = 0,
                knownSessions = linkedMapOf(),
            )
        }

        synchronized(state) {
            if (now - state.windowStartAt >= windowMs) {
                state.windowStartAt = now
                state.windowCount = 0
            }
            if (state.windowCount >= maxAdvertisementsPerWindow) {
                return Decision(false, "rate_limited")
            }

            if (cleanSession == state.sessionId) {
                if (sequence <= state.lastSequence) return Decision(false, "replay_or_out_of_order")
            } else if (state.knownSessions.containsKey(cleanSession)) {
                return Decision(false, "old_session_replay")
            }

            state.windowCount += 1
            if (cleanSession != state.sessionId) {
                state.knownSessions[state.sessionId] = state.lastSequence
                state.knownSessions[cleanSession] = sequence
                while (state.knownSessions.size > maxRememberedSessions) {
                    state.knownSessions.remove(state.knownSessions.entries.firstOrNull()?.key)
                }
                state.sessionId = cleanSession
            }
            state.lastSequence = sequence
            return Decision(true, "accepted")
        }
    }

    fun clear() = states.clear()
}
