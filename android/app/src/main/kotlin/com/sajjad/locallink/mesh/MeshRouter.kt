package com.sajjad.locallink.mesh

import org.json.JSONArray

enum class MeshRouteResult {
    LOCAL_DELIVERY,
    FORWARDED,
    QUEUED,
    NO_ROUTE,
    DROPPED,
}

/** Transport-independent mesh routing engine. */
class MeshRouter(
    private val localNodeId: () -> String?,
    private val routeTable: MeshRouteTable,
    private val peerRegistry: MeshPeerRegistry,
    private val transport: MeshTransport,
    private val enqueue: ((MeshPacket) -> Boolean)? = null,
    private val maxHops: Int = 8,
    /** Bundle 158: LAN (0) before Wi-Fi Direct (1) for the same hop count. */
    private val linkRank: ((String) -> Int)? = null,
    /** Bundle 158: make-before-break — proven routes are tried first. */
    private val routeProven: ((MeshRoute) -> Boolean)? = null,
    /** Bundle 160 (two-level map): no route at all -> this neighbour (the
     *  group host) may carry it, or null. Never used when routes exist. */
    private val defaultNextHop: ((MeshPacket) -> String?)? = null,
    /** Bundle 160: called with the destination when there is no route at
     *  all (ask the neighbours "who can reach X?"). */
    private val onNoRoute: ((String) -> Unit)? = null,
    /** Bundle 156: false = this next hop may not carry this packet (a relay
     *  link only carries sealed packets). Skipped quietly — not a failure.
     *  Kept LAST so a trailing lambda still means canCarry. */
    private val canCarry: ((String, MeshPacket) -> Boolean)? = null,
) {
    /** Validates an incoming packet before callers reserve it in replay state. */
    fun validateForProcessing(packet: MeshPacket, incomingPeerId: String? = null): Boolean {
        val self = localNodeId()?.trim().orEmpty()
        if (self.isEmpty() || !validate(packet, self)) return false
        if (!MeshLimits.hasValidHopBudget(packet.ttl, packet.hopCount, maxHops)) return false
        val path = packetPath(packet)
        val isLocalOrigin = packet.sourceNodeId == self && packet.hopCount == 0 && incomingPeerId.isNullOrBlank() && path == setOf(self)
        if (!isLocalOrigin && path.contains(self)) return false
        val incoming = incomingPeerId?.trim().orEmpty()
        if (incoming.isNotEmpty()) {
            if (!MeshIdPolicy.isValid(incoming) || incoming == self) return false
            if (path.lastOrNull() != incoming) return false
        }
        return true
    }

    fun route(
        packet: MeshPacket,
        incomingPeerId: String? = null,
        allowQueue: Boolean = true,
    ): MeshRouteResult {
        val self = localNodeId()?.trim().orEmpty()
        if (!validateForProcessing(packet, incomingPeerId)) return MeshRouteResult.DROPPED

        val path = packetPath(packet)
        val isLocalOrigin = packet.sourceNodeId == self && packet.hopCount == 0 && path == setOf(self)
        if (path.contains(self) && !isLocalOrigin) return MeshRouteResult.DROPPED
        if (packet.destinationNodeId == self) {
            if (!MeshLimits.hasValidHopBudget(packet.ttl, packet.hopCount, maxHops)) return MeshRouteResult.DROPPED
            return if (MeshFinalRecipientPolicy.isFinalRecipient(
                    sourceNodeId = packet.sourceNodeId,
                    destinationNodeId = packet.destinationNodeId,
                    nextHopNodeId = packet.nextHopNodeId,
                    localNodeId = self,
                )
            ) MeshRouteResult.LOCAL_DELIVERY else MeshRouteResult.DROPPED
        }
        if (packet.ttl <= 0 || packet.hopCount >= maxHops) return MeshRouteResult.DROPPED

        val excluded = buildSet {
            if (!incomingPeerId.isNullOrBlank()) add(incomingPeerId)
            addAll(path)
        }
        val usable = routeTable.allFor(packet.destinationNodeId)
            .filter { it.nextHopNodeId !in excluded }
            .filter { it.hopCount <= packet.ttl }
            .filter { route -> route.path.drop(1).none(excluded::contains) }
        // Bundle 158: proven first, fewest hops, LAN before Wi-Fi Direct.
        val candidates = MeshRouteChoicePolicy.order(
            usable,
            linkRank ?: { MeshRouteChoicePolicy.RANK_UNKNOWN },
            routeProven ?: { true },
        )

        for (route in candidates) {
            val peerId = route.nextHopNodeId
            if (canCarry?.invoke(peerId, packet) == false) continue
            if (!peerRegistry.isAvailable(peerId)) {
                routeTable.markRecoveringVia(peerId)
                transport.onRouteFailure(packet.destinationNodeId, peerId)
                continue
            }
            val forwarded = try {
                packet.copyForForwarding(peerId, self, maxHops)
            } catch (_: IllegalArgumentException) {
                return MeshRouteResult.DROPPED
            }
            if (!MeshLimits.hasValidHopBudget(forwarded.ttl, forwarded.hopCount, maxHops)) return MeshRouteResult.DROPPED
            if (transport.send(peerId, forwarded)) return MeshRouteResult.FORWARDED
            routeTable.markRecoveringVia(peerId)
            transport.onRouteFailure(packet.destinationNodeId, peerId)
        }

        if (usable.isEmpty()) {
            try { onNoRoute?.invoke(packet.destinationNodeId) } catch (_: Exception) {}
            val hop = try { defaultNextHop?.invoke(packet)?.trim() } catch (_: Exception) { null }
            if (!hop.isNullOrEmpty() && hop != self && hop !in excluded &&
                MeshIdPolicy.isValid(hop) &&
                canCarry?.invoke(hop, packet) != false &&
                peerRegistry.isAvailable(hop)
            ) {
                val forwarded = try {
                    packet.copyForForwarding(hop, self, maxHops)
                } catch (_: IllegalArgumentException) {
                    null
                }
                if (forwarded != null && MeshLimits.hasValidHopBudget(forwarded.ttl, forwarded.hopCount, maxHops) &&
                    transport.send(hop, forwarded)
                ) return MeshRouteResult.FORWARDED
            }
        }

        if (allowQueue && enqueue?.invoke(packet) == true) return MeshRouteResult.QUEUED
        return MeshRouteResult.NO_ROUTE
    }

    private fun validate(packet: MeshPacket, self: String): Boolean {
        if (packet.protocolVersion != MeshPacket.PROTOCOL_VERSION) return false
        if (!MeshIdPolicy.isValid(self) ||
            !MeshIdPolicy.isValid(packet.packetId) ||
            !MeshIdPolicy.isValid(packet.sourceNodeId) ||
            !MeshIdPolicy.isValid(packet.destinationNodeId) ||
            !MeshIdPolicy.isValidType(packet.type)) return false
        if (packet.sourceNodeId == packet.destinationNodeId) return packet.destinationNodeId == self
        if (packet.createdAt <= 0L || !MeshLimits.hasValidHopBudget(packet.ttl, packet.hopCount, maxHops)) return false
        if (!MeshLimits.isWithinPacketLifetime(packet.createdAt)) return false
        val path = packetPathList(packet)
        if (path.isEmpty()) return false
        if (path.first() != packet.sourceNodeId) return false
        if (path.size != maxOf(1, packet.hopCount)) return false
        if (path.size != path.distinct().size) return false
        if (path.any { !MeshIdPolicy.isValid(it) }) return false
        if (path.contains(packet.destinationNodeId)) return false
        return true
    }

    private fun packetPath(packet: MeshPacket): Set<String> = packetPathList(packet).toSet()

    private fun packetPathList(packet: MeshPacket): List<String> {
        val path = packet.payload.optJSONArray(MeshPacket.MESH_PATH_KEY) ?: return emptyList()
        val ids = mutableListOf<String>()
        for (i in 0 until path.length()) {
            ids.add(path.optString(i).trim())
        }
        return ids
    }
}
