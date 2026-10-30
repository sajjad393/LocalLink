package com.sajjad.locallink.mesh

/**
 * Bundle 158: which route to try first (plan 158.2 + 158.3).
 *
 * Order, strictly:
 *  1. PROVEN routes before new ones (make-before-break): a route whose next
 *     hop has answered a ping on its current link has carried a packet both
 *     ways. A brand-new route is used only after that, or when nothing proven
 *     is left (better than the outbox).
 *  2. fewest hops (a direct link is 1 hop, so direct always beats relayed),
 *  3. LAN next hop before Wi-Fi Direct next hop (same hop count),
 *  4. the route table's own order (newest version, newest seen, id).
 *
 * The old route is never thrown away when a better one appears: the table
 * keeps up to [MeshLimits.MAX_ROUTES_PER_DESTINATION] routes, and the router
 * fails over to the next one at once when a send fails, before the outbox.
 */
object MeshRouteChoicePolicy {
    const val RANK_LAN = 0
    const val RANK_WIFI_DIRECT = 1
    const val RANK_UNKNOWN = 2

    /** Link rank of a next hop from its active transport name. */
    fun linkRank(transportName: String?): Int = when (transportName) {
        MeshTransportPolicy.LAN -> RANK_LAN
        MeshTransportPolicy.WIFI_DIRECT -> RANK_WIFI_DIRECT
        // Bundle 161: a linked group / hotspot link ranks like Wi-Fi Direct.
        MeshTransportPolicy.LOCAL_NET -> RANK_WIFI_DIRECT
        else -> RANK_UNKNOWN
    }

    /**
     * A link is proven once a pong arrived after it was connected (the ping
     * went out and the answer came back on this link).
     */
    fun linkProven(connectedAt: Long, lastPongAt: Long): Boolean = lastPongAt > connectedAt

    /** [routes] must already be in the route table's order. Stable. */
    fun order(
        routes: List<MeshRoute>,
        linkRank: (String) -> Int = { RANK_UNKNOWN },
        proven: (MeshRoute) -> Boolean = { true },
    ): List<MeshRoute> {
        if (routes.size < 2) return routes
        val indexed = routes.withIndex().map { (i, r) -> Triple(r, i, proven(r)) }
        return indexed.sortedWith(
            compareBy<Triple<MeshRoute, Int, Boolean>> { if (it.third) 0 else 1 }
                .thenBy { it.first.hopCount }
                .thenBy { linkRank(it.first.nextHopNodeId) }
                .thenBy { it.second },
        ).map { it.first }
    }
}
