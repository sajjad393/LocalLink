package com.sajjad.locallink.mesh

/**
 * Defines the only node that is allowed to perform local application delivery.
 * Relays must forward the packet and must never surface a user message locally.
 */
object MeshFinalRecipientPolicy {
    fun isFinalRecipient(
        sourceNodeId: String,
        destinationNodeId: String,
        nextHopNodeId: String?,
        localNodeId: String,
    ): Boolean {
        val source = sourceNodeId.trim()
        val destination = destinationNodeId.trim()
        val local = localNodeId.trim()
        val nextHop = nextHopNodeId?.trim().orEmpty()
        if (!MeshIdPolicy.isValid(source) ||
            !MeshIdPolicy.isValid(destination) ||
            !MeshIdPolicy.isValid(local)) return false
        if (source == destination) return false
        if (destination != local) return false
        // A packet addressed to this device may carry itself as next hop when
        // it was explicitly forwarded by the previous relay. Any other next-hop
        // value means the packet was not intended for local consumption.
        if (nextHop.isNotEmpty() && nextHop != local) return false
        return true
    }
}
