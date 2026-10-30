package com.sajjad.locallink.mesh

/**
 * Bundle 161 (rest of plan 160.2): the smaller map on group members.
 *
 * A phone that is only a member of a nearby group (its one link is to the
 * group host, no Local Wi-Fi or other links) does not need the whole map:
 * the host knows it. Such a "compact" member keeps:
 * - its own group (routes from the host up to [GROUP_HOPS] steps),
 * - its contacts (so their status stays true: Nearby),
 * - every route learned from any other neighbour.
 * Everything else goes to the host (the default route), including call
 * sound and file parts, because the host knows the way.
 *
 * A phone that is a host, a bridge, on Local Wi-Fi or on a linked network
 * keeps the full map as before. When a member stops being compact it asks
 * the host for the full list once.
 */
object MeshTwoLevelMap {
    /** Host (1) + the phones linked to the host (2). */
    const val GROUP_HOPS = 2

    fun isCompactMember(groupOwner: Boolean, hostLinkUp: Boolean, otherLinks: Int): Boolean =
        !groupOwner && hostLinkUp && otherLinks == 0

    /** Keep a route learned from [fromPeer]? [hopCount] counts from this phone. */
    fun keep(compact: Boolean, fromHost: Boolean, hopCount: Int, isContact: Boolean): Boolean =
        !compact || !fromHost || hopCount <= GROUP_HOPS || isContact

    /** A compact member sends everything without a route to its host. */
    fun defaultForAll(compact: Boolean): Boolean = compact

    /** Asking neighbours "who can reach X?" is pointless for a compact member
     *  (its only neighbour is the host, which already gets the packet). */
    fun skipLookup(compact: Boolean): Boolean = compact

    /** Became a full-map phone again: ask the host for everything. */
    fun needsFullAgain(wasCompact: Boolean, compact: Boolean): Boolean = wasCompact && !compact
}
