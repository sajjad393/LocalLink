package com.sajjad.locallink.mesh

/** Transport-neutral capability required by MeshRouter. */
interface MeshTransport {
    val name: String
    fun isPeerAvailable(nodeId: String): Boolean
    fun send(peerNodeId: String, packet: MeshPacket): Boolean
    fun disconnect(peerNodeId: String)
    fun onRouteFailure(destinationNodeId: String, failedNextHopNodeId: String) {}
}
