package com.sajjad.locallink.mesh

enum class MeshPeerState {
    DISCOVERED,
    CONNECTING,
    CONNECTED,
    AVAILABLE,
    UNAVAILABLE,
    DISCONNECTED,
    FAILED,
}

data class MeshPeerStateSnapshot(
    val nodeId: String,
    val state: MeshPeerState,
    val transport: String,
    val lastSeenAt: Long,
    val connectedAt: Long?,
)
