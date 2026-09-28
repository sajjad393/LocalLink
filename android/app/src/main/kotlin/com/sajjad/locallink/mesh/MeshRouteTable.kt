package com.sajjad.locallink.mesh

import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe routing-table boundary.
 *
 * Route entries are accepted only after structural validation. A destination may
 * have several next-hop candidates so failed routes can be replaced without
 * throwing away healthy alternates.
 */
class MeshRouteTable(
    private val localNodeId: () -> String? = { null },
) {
    private val routes = ConcurrentHashMap<String, ConcurrentHashMap<String, MeshRoute>>()
    private val mutationLock = Any()

    operator fun get(destinationNodeId: String): MeshRoute? = bestRoute(destinationNodeId)

    /** Compatibility setter: replaces all routes for a destination with one validated route. */
    operator fun set(destinationNodeId: String, route: MeshRoute) {
        require(route.destinationNodeId == destinationNodeId) { "route destination mismatch" }
        check(validateRoute(route, destinationNodeId)) { "invalid route" }
        synchronized(mutationLock) {
            val previous = routes.remove(destinationNodeId)
            val accepted = upsert(destinationNodeId, route)
            if (!accepted) {
                if (previous != null) routes[destinationNodeId] = previous
                error("route table capacity or route version rejected route")
            }
        }
    }

    /**
     * Upserts a validated route. For the same destination/next-hop, route versions
     * are monotonic. An equal-version but different topology is rejected rather
     * than allowing a stale advertisement to mutate an existing route in-place.
     */
    fun upsert(destinationNodeId: String, route: MeshRoute): Boolean = synchronized(mutationLock) {
        if (!validateRoute(route, destinationNodeId)) return false
        val existingDestination = routes[destinationNodeId]
        if (existingDestination == null && routes.size >= MeshLimits.MAX_ROUTE_TABLE_DESTINATIONS) return false
        val destinationRoutes = existingDestination ?: ConcurrentHashMap<String, MeshRoute>().also { routes[destinationNodeId] = it }
        val existing = destinationRoutes[route.nextHopNodeId]
        if (existing != null) {
            if (existing.state == MeshRouteState.REMOVED) return false
            if (existing.routeVersion > route.routeVersion) return false
            if (existing.routeVersion == route.routeVersion) {
                if (!sameTopology(existing, route)) return false
                destinationRoutes[route.nextHopNodeId] = existing.copy(
                    lastSeenAt = maxOf(existing.lastSeenAt, route.lastSeenAt),
                    expiresAt = maxOf(existing.expiresAt, route.expiresAt),
                    state = MeshRouteState.ACTIVE,
                )
                return false
            }
        }
        if (existing == null) {
            val routesViaNextHop = routes.values.sumOf { candidates ->
                candidates.values.count { it.nextHopNodeId == route.nextHopNodeId && it.state != MeshRouteState.REMOVED }
            }
            if (routesViaNextHop >= MeshLimits.MAX_ROUTES_PER_NEXT_HOP) return false
        }
        if (existing == null && destinationRoutes.size >= MeshLimits.MAX_ROUTES_PER_DESTINATION) {
            val worst = destinationRoutes.values.maxWithOrNull(
                compareBy<MeshRoute> { it.hopCount }
                    .thenBy { it.routeVersion }
                    .thenBy { it.lastSeenAt }
                    .thenByDescending { it.nextHopNodeId },
            ) ?: return false
            if (compareRoutesForSelection(route, worst) >= 0) return false
            destinationRoutes.remove(worst.nextHopNodeId, worst)
        }
        destinationRoutes[route.nextHopNodeId] = route.copy(state = MeshRouteState.ACTIVE)
        true
    }

    fun bestRoute(
        destinationNodeId: String,
        excludedNextHops: Set<String> = emptySet(),
        forbiddenNodes: Set<String> = emptySet(),
        now: Long = System.currentTimeMillis(),
    ): MeshRoute? = routes[destinationNodeId]
        ?.values
        ?.asSequence()
        ?.filter { it.state == MeshRouteState.ACTIVE && it.expiresAt > now }
        ?.filter { it.nextHopNodeId !in excludedNextHops }
        ?.filter { route -> route.path.drop(1).none(forbiddenNodes::contains) }
        ?.minWithOrNull(
            compareBy<MeshRoute> { it.hopCount }
                .thenByDescending { it.routeVersion }
                .thenByDescending { it.lastSeenAt }
                .thenBy { it.nextHopNodeId },
        )

    fun allFor(destinationNodeId: String, now: Long = System.currentTimeMillis()): List<MeshRoute> = routes[destinationNodeId]
        ?.values
        ?.filter { it.state == MeshRouteState.ACTIVE && it.expiresAt > now }
        ?.sortedWith(
            compareBy<MeshRoute> { it.hopCount }
                .thenByDescending { it.routeVersion }
                .thenByDescending { it.lastSeenAt }
                .thenBy { it.nextHopNodeId },
        )
        ?: emptyList()

    fun remove(destinationNodeId: String): List<MeshRoute> {
        val existing = routes.remove(destinationNodeId)?.values?.toList() ?: emptyList()
        return existing.map { it.copy(state = MeshRouteState.REMOVED) }
    }

    /** Removes only routes to a destination that use the specified next hop. */
    fun remove(destinationNodeId: String, nextHopNodeId: String): List<MeshRoute> {
        val destinationRoutes = routes[destinationNodeId] ?: return emptyList()
        val removed = destinationRoutes.remove(nextHopNodeId)?.let { listOf(it.copy(state = MeshRouteState.REMOVED)) } ?: emptyList()
        if (destinationRoutes.isEmpty()) routes.remove(destinationNodeId, destinationRoutes)
        return removed
    }

    /** Removes all routes that rely on the provided next-hop peer. */
    fun removeVia(nextHopNodeId: String): List<String> {
        if (!MeshIdPolicy.isValid(nextHopNodeId)) return emptyList()
        val affected = mutableListOf<String>()
        for ((destination, destinationRoutes) in routes.entries) {
            val removed = destinationRoutes.remove(nextHopNodeId)
            if (removed != null) {
                affected.add(destination)
                if (destinationRoutes.isEmpty()) routes.remove(destination, destinationRoutes)
            }
        }
        return affected
    }

    fun invalidateVia(nextHopNodeId: String): List<String> = transitionVia(nextHopNodeId, MeshRouteState.INVALID)

    fun markStaleVia(nextHopNodeId: String): List<String> = transitionVia(nextHopNodeId, MeshRouteState.STALE)

    fun markRecoveringVia(nextHopNodeId: String): List<String> = transitionVia(nextHopNodeId, MeshRouteState.RECOVERING)

    fun markRecovering(destinationNodeId: String, nextHopNodeId: String? = null): Boolean {
        val destinationRoutes = routes[destinationNodeId] ?: return false
        var changed = false
        for ((hop, route) in destinationRoutes.entries) {
            if (nextHopNodeId != null && hop != nextHopNodeId) continue
            if (route.state != MeshRouteState.RECOVERING) {
                destinationRoutes[hop] = route.copy(state = MeshRouteState.RECOVERING)
                changed = true
            }
        }
        return changed
    }

    fun clear() = synchronized(mutationLock) { routes.clear() }

    fun all(): Map<String, List<MeshRoute>> = routes.mapValues { it.value.values.toList() }

    val keys: Set<String> get() = routes.keys

    val entries: MutableSet<MutableMap.MutableEntry<String, MeshRoute>>
        get() = routes.keys.mapNotNull { destination ->
            val best = bestRoute(destination) ?: return@mapNotNull null
            java.util.AbstractMap.SimpleEntry(destination, best)
        }.toMutableSet()

    fun snapshot(now: Long = System.currentTimeMillis()): List<Map<String, Any?>> = routes.entries
        .flatMap { (_, destinationRoutes) ->
            destinationRoutes.values.map { route ->
                mapOf(
                    "destination" to route.destinationNodeId,
                    "next_hop" to route.nextHopNodeId,
                    "cost" to route.hopCount,
                    "hop_count" to route.hopCount,
                    "route_version" to route.routeVersion,
                    "last_seen_at" to route.lastSeenAt,
                    "age_ms" to (now - route.lastSeenAt).coerceAtLeast(0L),
                    "expires_at" to route.expiresAt,
                    "path" to route.path,
                    "state" to when {
                        route.state != MeshRouteState.ACTIVE -> route.state.name
                        route.expiresAt > now -> MeshRouteState.ACTIVE.name
                        else -> MeshRouteState.EXPIRED.name
                    },
                )
            }
        }
        .sortedWith(compareBy<Map<String, Any?>> { it["destination"].toString() }.thenBy { it["cost"] as Int }.thenBy { it["next_hop"].toString() })

    /**
     * Ages out routes without treating the next-hop failure as an application
     * delivery failure. Expired/unavailable routes become STALE first and are
     * then removed from the active table, while healthy alternates remain.
     */
    fun prune(now: Long, isNextHopAvailable: (String) -> Boolean): List<String> {
        val affected = mutableListOf<String>()
        for ((destination, destinationRoutes) in routes.entries) {
            val staleHops = destinationRoutes.values
                .filter { it.state != MeshRouteState.ACTIVE || it.expiresAt <= now || !isNextHopAvailable(it.nextHopNodeId) }
                .map { it.nextHopNodeId }
            if (staleHops.isNotEmpty()) {
                staleHops.forEach { hop ->
                    destinationRoutes[hop]?.let { destinationRoutes[hop] = it.copy(state = MeshRouteState.STALE) }
                    destinationRoutes.remove(hop)
                }
                affected.add(destination)
            }
            if (destinationRoutes.isEmpty()) routes.remove(destination, destinationRoutes)
        }
        return affected.distinct()
    }

    private fun validateRoute(route: MeshRoute, destinationNodeId: String): Boolean {
        if (!MeshIdPolicy.isValid(destinationNodeId) || route.destinationNodeId != destinationNodeId) return false
        if (!MeshIdPolicy.isValid(route.nextHopNodeId)) return false
        if (route.nextHopNodeId == destinationNodeId && route.hopCount != 1) return false
        if (route.hopCount !in 1..MeshLimits.MAX_HOPS) return false
        if (route.expiresAt <= route.lastSeenAt || route.lastSeenAt <= 0L) return false
        if (route.expiresAt <= System.currentTimeMillis()) return false
        if (route.routeVersion <= 0L) return false
        val path = route.path
        if (path.size != route.hopCount + 1) return false
        if (path.firstOrNull() == null || path.lastOrNull() != destinationNodeId) return false
        if (path.distinct().size != path.size) return false
        if (path.any { !MeshIdPolicy.isValid(it) }) return false
        if (path[1] != route.nextHopNodeId) return false
        val local = localNodeId()?.trim().orEmpty()
        if (local.isNotEmpty() && path.first() != local) return false
        if (path.contains(local) && local.isNotEmpty() && path.first() != local) return false
        return true
    }

    private fun compareRoutesForSelection(a: MeshRoute, b: MeshRoute): Int =
        compareBy<MeshRoute> { it.hopCount }
            .thenByDescending { it.routeVersion }
            .thenByDescending { it.lastSeenAt }
            .thenBy { it.nextHopNodeId }
            .compare(a, b)

    private fun sameTopology(a: MeshRoute, b: MeshRoute): Boolean =
        a.destinationNodeId == b.destinationNodeId &&
            a.nextHopNodeId == b.nextHopNodeId &&
            a.hopCount == b.hopCount &&
            a.path == b.path

    private fun transitionVia(nextHopNodeId: String, state: MeshRouteState): List<String> {
        if (!MeshIdPolicy.isValid(nextHopNodeId)) return emptyList()
        val affected = mutableListOf<String>()
        for ((destination, destinationRoutes) in routes.entries) {
            val existing = destinationRoutes[nextHopNodeId] ?: continue
            destinationRoutes[nextHopNodeId] = existing.copy(state = state)
            affected.add(destination)
        }
        return affected
    }
}
