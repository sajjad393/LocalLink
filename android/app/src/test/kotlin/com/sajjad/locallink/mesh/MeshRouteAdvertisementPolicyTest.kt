package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRouteAdvertisementPolicyTest {
    @Test
    fun rejectsReplayAndOutOfOrderWithinSameSession() {
        val policy = MeshRouteAdvertisementPolicy(maxAdvertisementsPerWindow = 10)
        assertTrue(policy.evaluate("B", "session-1", 1L, 1_000L, 0, 1_000L).accepted)
        assertFalse(policy.evaluate("B", "session-1", 1L, 1_001L, 0, 1_001L).accepted)
        assertFalse(policy.evaluate("B", "session-1", 0L, 1_002L, 0, 1_002L).accepted)
    }

    @Test
    fun oldSessionCannotBeReplayedAfterPeerRotatesSession() {
        val policy = MeshRouteAdvertisementPolicy(maxAdvertisementsPerWindow = 10)
        assertTrue(policy.evaluate("B", "session-a", 1L, 1_000L, 0, 1_000L).accepted)
        assertTrue(policy.evaluate("B", "session-b", 1L, 1_001L, 0, 1_001L).accepted)
        val replay = policy.evaluate("B", "session-a", 99L, 1_002L, 0, 1_002L)
        assertFalse(replay.accepted)
        assertEquals("old_session_replay", replay.reason)
    }

    @Test
    fun rateLimitsAControlPlaneFlood() {
        val policy = MeshRouteAdvertisementPolicy(maxAdvertisementsPerWindow = 2, windowMs = 100L)
        assertTrue(policy.evaluate("B", "session-1", 1L, 1_000L, 0, 1_000L).accepted)
        assertTrue(policy.evaluate("B", "session-1", 2L, 1_001L, 0, 1_001L).accepted)
        val rejected = policy.evaluate("B", "session-1", 3L, 1_002L, 0, 1_002L)
        assertFalse(rejected.accepted)
        assertEquals("rate_limited", rejected.reason)
        assertTrue(policy.evaluate("B", "session-1", 3L, 1_101L, 0, 1_101L).accepted)
    }

    @Test
    fun rejectsStaleFutureAndOversizedAdvertisements() {
        val policy = MeshRouteAdvertisementPolicy(maxRoutesPerAdvertisement = 2, maxAdvertisementsPerWindow = 10)
        assertEquals("stale_advertisement", policy.evaluate("B", "session-1", 1L, 1_000L, 0, 100_000L).reason)
        assertEquals("future_advertisement", policy.evaluate("B", "session-1", 1L, 100_006L, 0, 100_000L).reason)
        assertEquals("route_count_exceeded", policy.evaluate("B", "session-1", 1L, 100_000L, 3, 100_000L).reason)
    }
}
