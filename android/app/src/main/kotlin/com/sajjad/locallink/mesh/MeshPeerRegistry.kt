package com.sajjad.locallink.mesh

import java.util.concurrent.ConcurrentHashMap

/** Thread-safe mesh peer lifecycle registry. */
class MeshPeerRegistry {
    private val peers = ConcurrentHashMap<String, MeshPeerStateSnapshot>()

    fun discovered(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.DISCOVERED, transport, now, peers[nodeId]?.connectedAt)

    fun connecting(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.CONNECTING, transport, now, peers[nodeId]?.connectedAt)

    fun connected(nodeId: String, transport: String, connectedAt: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.CONNECTED, transport, connectedAt, connectedAt)

    fun available(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.AVAILABLE, transport, now, peers[nodeId]?.connectedAt)

    fun unavailable(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.UNAVAILABLE, transport, now, peers[nodeId]?.connectedAt)

    fun disconnected(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.DISCONNECTED, transport, now, peers[nodeId]?.connectedAt)

    fun failed(nodeId: String, transport: String, now: Long = System.currentTimeMillis()) =
        update(nodeId, MeshPeerState.FAILED, transport, now, peers[nodeId]?.connectedAt)

    fun get(nodeId: String): MeshPeerStateSnapshot? = peers[nodeId]

    fun all(): List<MeshPeerStateSnapshot> = peers.values.sortedBy { it.nodeId }

    fun isAvailable(nodeId: String): Boolean = when (peers[nodeId]?.state) {
        MeshPeerState.CONNECTED, MeshPeerState.AVAILABLE -> true
        else -> false
    }

    fun clear() = peers.clear()
    fun remove(nodeId: String) = peers.remove(nodeId)

    private fun update(
        nodeId: String,
        state: MeshPeerState,
        transport: String,
        lastSeenAt: Long,
        connectedAt: Long?,
    ) {
        val normalizedId = nodeId.trim()
        val normalizedTransport = transport.trim()
        if (!MeshIdPolicy.isValid(normalizedId) || !MeshTransportPolicy.isSupportedTransport(normalizedTransport) || lastSeenAt <= 0L) return
        peers.compute(normalizedId) { _, previous ->
            if (previous != null) {
                if (lastSeenAt < previous.lastSeenAt) return@compute previous
                if (MeshPeerLifecyclePolicy.shouldIgnoreObservation(previous.state, state)) {
                    // Discovery/control-plane observations must not regress a live link.
                    return@compute previous.copy(lastSeenAt = maxOf(previous.lastSeenAt, lastSeenAt))
                }
            }
            val preservedConnectedAt = connectedAt ?: previous?.connectedAt
            MeshPeerStateSnapshot(
                nodeId = normalizedId,
                state = state,
                transport = normalizedTransport,
                lastSeenAt = maxOf(previous?.lastSeenAt ?: lastSeenAt, lastSeenAt),
                connectedAt = preservedConnectedAt,
            )
        }
    }
}
