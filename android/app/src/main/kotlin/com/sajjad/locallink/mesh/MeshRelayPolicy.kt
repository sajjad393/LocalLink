package com.sajjad.locallink.mesh

import java.util.concurrent.ConcurrentHashMap

/**
 * Bundle 156: rules for links to LocalLink phones that are NOT contacts
 * ("relay" links).
 *
 * A relay link may carry only end-to-end sealed packets (types [SEALED] and
 * [SEALED_LIVE]) plus route adverts and heartbeats. Plain data — which a relay
 * could read — never crosses it, and nothing from a relay link is delivered to
 * the UI unless the sealed packet opens with a contact's key (checked in Dart).
 */
object MeshRelayPolicy {
    const val TRUST_CONTACT: String = "contact"
    const val TRUST_RELAY: String = "relay"

    /** Sealed, store-and-forward (chat, receipts, call signals). */
    const val SEALED: String = "sealed"

    /** Sealed, best effort (presence, heartbeats, probes). */
    const val SEALED_LIVE: String = "sealed_x"

    /** Bundle 159: locked call voice (only the two call phones hold the key).
     *  Live only: never queued, never stored. */
    const val SEALED_VOICE: String = "sealed_v"

    /** Kill switch for relay links (D11). */
    const val RELAY_ENABLED: Boolean = true

    /** D12: start with a fixed number of relay neighbours (Phase 7 tunes it). */
    const val MAX_RELAY_LINKS: Int = 3

    /** Per relay peer, per minute. Generous for chat; stops floods. */
    const val MAX_RELAY_PACKETS_PER_MINUTE: Int = 600
    const val MAX_RELAY_BYTES_PER_MINUTE: Long = 4L * 1024L * 1024L

    /** A relay that breaks the limits is dropped and not used for 10 min. */
    const val RELAY_PAUSE_MS: Long = 10L * 60L * 1000L

    /** Do not re-dial a stranger more often than this. */
    const val RELAY_DIAL_COOLDOWN_MS: Long = 60_000L

    fun isSealed(type: String?): Boolean = type == SEALED || type == SEALED_LIVE

    /** Bundle 159: a locked voice frame. */
    fun isSealedVoice(type: String?): Boolean = type == SEALED_VOICE

    /** May a link with [trust] carry a packet of [type] (either direction)? */
    fun canCarry(trust: String, type: String?): Boolean =
        trust == TRUST_CONTACT || (trust == TRUST_RELAY && (isSealed(type) || isSealedVoice(type)))

    /**
     * Trust for a peer at handshake time, or null = refuse the link.
     * Contacts are always accepted (as before). A stranger is accepted as a
     * relay only when both phones offer relaying, it is not blocked, it is
     * not paused for abuse and there is still room for another relay link.
     */
    fun trustFor(
        peerId: String,
        isContact: Boolean,
        isBlocked: Boolean,
        peerOffersRelay: Boolean,
        relayLinks: Int,
        isPaused: Boolean = false,
    ): String? {
        if (peerId.isBlank()) return null
        // Bundle 164 (5.7): a blocked person never connects - not as a
        // contact and not as a relay.
        if (isBlocked) return null
        if (isContact) return TRUST_CONTACT
        if (!RELAY_ENABLED || !peerOffersRelay || isPaused) return null
        if (relayLinks >= MAX_RELAY_LINKS) return null
        return TRUST_RELAY
    }

    /** Only one side dials a stranger, so two phones don't race each other. */
    fun shouldDialRelay(selfId: String, peerId: String): Boolean = selfId < peerId
}

/** Bundle 156: per-relay flood limits (packets and bytes per minute). */
class MeshRelayRateLimiter(
    private val maxPackets: Int = MeshRelayPolicy.MAX_RELAY_PACKETS_PER_MINUTE,
    private val maxBytes: Long = MeshRelayPolicy.MAX_RELAY_BYTES_PER_MINUTE,
    private val pauseMs: Long = MeshRelayPolicy.RELAY_PAUSE_MS,
    private val windowMs: Long = 60_000L,
) {
    private class Window(var startedAt: Long, var packets: Int, var bytes: Long)

    private val windows = ConcurrentHashMap<String, Window>()
    private val pausedUntil = ConcurrentHashMap<String, Long>()

    fun isPaused(peerId: String, now: Long = System.currentTimeMillis()): Boolean {
        val until = pausedUntil[peerId] ?: return false
        if (now >= until) {
            pausedUntil.remove(peerId)
            return false
        }
        return true
    }

    /** Counts one packet. Returns false (and pauses the peer) on abuse. */
    fun allow(peerId: String, bytes: Int, now: Long = System.currentTimeMillis()): Boolean {
        if (isPaused(peerId, now)) return false
        val window = windows.compute(peerId) { _, old ->
            if (old == null || now - old.startedAt >= windowMs) Window(now, 0, 0L) else old
        }!!
        synchronized(window) {
            window.packets += 1
            window.bytes += bytes.coerceAtLeast(0)
            if (window.packets > maxPackets || window.bytes > maxBytes) {
                pausedUntil[peerId] = now + pauseMs
                windows.remove(peerId)
                return false
            }
        }
        return true
    }

    fun forget(peerId: String) {
        windows.remove(peerId)
    }
}
