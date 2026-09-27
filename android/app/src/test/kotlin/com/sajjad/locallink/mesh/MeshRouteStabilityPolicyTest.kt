package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRouteStabilityPolicyTest {
    private fun route(nextHop: String, hopCount: Int = 2, expiry: Long = Long.MAX_VALUE) =
        MeshRoute("D", nextHop, hopCount, expiry, 1L, 1L, listOf("A", nextHop, "D"))

    @Test
    fun repeatedNextHopChangesTriggerHoldDown() {
        val policy = MeshRouteStabilityPolicy(flapWindowMs = 1_000L, maxChangesBeforeHoldDown = 3, holdDownMs = 500L)
        val current = route("B")
        val first = policy.beforeChange("D", current, route("C"), 1_000L)
        assertTrue(first.accepted)
        policy.recordAcceptedChange("D", "B", "C", 1_000L)
        policy.recordAcceptedChange("D", "C", "B", 1_100L)
        policy.recordAcceptedChange("D", "B", "C", 1_200L)
        val held = policy.beforeChange("D", route("C"), route("B"), 1_300L)
        assertFalse(held.accepted)
        assertEquals("route_hold_down", held.reason)
        assertTrue(policy.beforeChange("D", route("C"), route("B"), 1_801L).accepted)
    }

    @Test
    fun nearExpiryAllowsFastReplacementWithoutTreatingItAsFlapping() {
        val policy = MeshRouteStabilityPolicy(staleGraceMs = 5_000L)
        assertTrue(policy.beforeChange("D", route("B", expiry = 1_004L), route("C"), 1_000L).accepted)
    }
}
