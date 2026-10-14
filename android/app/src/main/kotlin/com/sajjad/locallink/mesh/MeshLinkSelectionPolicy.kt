package com.sajjad.locallink.mesh

/**
 * Chooses the single ACTIVE transport link for a peer when several physical
 * links exist (LAN and Wi-Fi Direct connections to the same device may be
 * alive simultaneously).
 *
 * The ordering is a strict total order, so the result is deterministic and
 * cannot oscillate between equal candidates:
 *   1. higher transport priority (LAN > Wi-Fi Direct — [MeshTransportPolicy]),
 *   2. more recently seen link,
 *   3. transport name (lexicographic) as a stable final tie-break.
 *
 * Links that are not selected are NOT closed by this decision and remain hot
 * standbys; the service only uses the returned connection as the active one.
 * LAN return therefore promotes automatically, and WFD-only operation is a
 * pure fallback state, with no user-visible switching ceremony.
 */
object MeshLinkSelectionPolicy {

    /**
     * Returns the connection to use right now, or null when empty.
     * [transportName] and [lastSeen] project the two ordering fields from
     * a caller's connection type, keeping this policy usable by both the
     * service (PeerConnection) and tests (plain records).
     */
    fun <T> selectActive(
        candidates: Collection<T>,
        transportName: (T) -> String,
        lastSeen: (T) -> Long,
    ): T? = candidates.minWithOrNull(
        compareByDescending<T> { MeshTransportPolicy.transportPriority(transportName(it)) }
            .thenByDescending { lastSeen(it) }
            .thenBy { transportName(it) },
    )
}
