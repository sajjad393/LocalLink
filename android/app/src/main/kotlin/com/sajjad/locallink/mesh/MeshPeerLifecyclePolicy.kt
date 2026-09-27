package com.sajjad.locallink.mesh

/**
 * Explicit peer lifecycle contract. Discovery must never downgrade an already
 * connected peer, while failures and disconnects are allowed to recover into a
 * fresh discovery/connection cycle.
 */
object MeshPeerLifecyclePolicy {
    fun canTransition(from: MeshPeerState?, to: MeshPeerState): Boolean {
        if (from == null || from == to) return true
        return when (from) {
            MeshPeerState.DISCOVERED -> to in setOf(
                MeshPeerState.CONNECTING,
                MeshPeerState.CONNECTED,
                MeshPeerState.AVAILABLE,
                MeshPeerState.UNAVAILABLE,
                MeshPeerState.DISCONNECTED,
                MeshPeerState.FAILED,
            )
            MeshPeerState.CONNECTING -> to in setOf(
                MeshPeerState.CONNECTED,
                MeshPeerState.AVAILABLE,
                MeshPeerState.UNAVAILABLE,
                MeshPeerState.DISCONNECTED,
                MeshPeerState.FAILED,
            )
            MeshPeerState.CONNECTED -> to in setOf(
                MeshPeerState.AVAILABLE,
                MeshPeerState.UNAVAILABLE,
                MeshPeerState.DISCONNECTED,
                MeshPeerState.FAILED,
            )
            MeshPeerState.AVAILABLE -> to in setOf(
                MeshPeerState.CONNECTING,
                MeshPeerState.CONNECTED,
                MeshPeerState.UNAVAILABLE,
                MeshPeerState.DISCONNECTED,
                MeshPeerState.FAILED,
            )
            MeshPeerState.UNAVAILABLE -> to in setOf(
                MeshPeerState.DISCOVERED,
                MeshPeerState.CONNECTING,
                MeshPeerState.CONNECTED,
                MeshPeerState.AVAILABLE,
                MeshPeerState.DISCONNECTED,
                MeshPeerState.FAILED,
            )
            MeshPeerState.DISCONNECTED -> to in setOf(
                MeshPeerState.DISCOVERED,
                MeshPeerState.CONNECTING,
                MeshPeerState.CONNECTED,
                MeshPeerState.AVAILABLE,
                MeshPeerState.FAILED,
            )
            MeshPeerState.FAILED -> to in setOf(
                MeshPeerState.DISCOVERED,
                MeshPeerState.CONNECTING,
                MeshPeerState.CONNECTED,
                MeshPeerState.AVAILABLE,
                MeshPeerState.DISCONNECTED,
            )
        }
    }

    /** Discovery observations are advisory and cannot demote a live link. */
    fun shouldIgnoreObservation(from: MeshPeerState?, to: MeshPeerState): Boolean =
        from != null && from != to && !canTransition(from, to)
}
