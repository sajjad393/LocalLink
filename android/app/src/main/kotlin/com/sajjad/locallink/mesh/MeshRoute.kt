package com.sajjad.locallink.mesh

/** Canonical routing-table entry. */
enum class MeshRouteState {
    /** Route has been observed/discovered but is not yet eligible for forwarding. */
    DISCOVERED,
    /** Route is validated, live, and eligible for forwarding. */
    ACTIVE,
    /** Route has aged out or its transport is no longer trusted; it is not usable. */
    STALE,
    /** Route was explicitly invalidated after a failed hop or failed validation. */
    INVALID,
    /** Route is temporarily held while an alternate route is being established. */
    RECOVERING,
    /** Route has been removed from the table and must never be selected. */
    REMOVED,
    /** Compatibility/diagnostic state for time-expired snapshots. */
    EXPIRED,
}

data class MeshRoute(
    val destinationNodeId: String,
    val nextHopNodeId: String,
    val hopCount: Int,
    val expiresAt: Long,
    val lastSeenAt: Long,
    val routeVersion: Long = lastSeenAt,
    val path: List<String> = emptyList(),
    val state: MeshRouteState = MeshRouteState.ACTIVE,
) {
    /** Compatibility alias for older routing code. */
    val nextHop: String get() = nextHopNodeId
    /** Compatibility alias for older routing code. */
    val cost: Int get() = hopCount
    /** Route age at the moment it is queried. */
    val ageMs: Long get() = (System.currentTimeMillis() - lastSeenAt).coerceAtLeast(0L)

    fun refreshed(now: Long): MeshRoute = copy(
        expiresAt = now.coerceAtLeast(lastSeenAt) + (expiresAt - lastSeenAt).coerceAtLeast(1L),
        lastSeenAt = now,
        state = MeshRouteState.ACTIVE,
    )

    fun invalidated(): MeshRoute = copy(state = MeshRouteState.INVALID)
}
