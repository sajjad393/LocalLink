package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 177: closed-app Nearby limits (pure rules only). */
class Nearby177Test {
    @Test
    fun `closed app may search join and start groups`() {
        for (m in listOf("discoverPeers", "getNearbyTags", "connectionInfo", "setNearbyWanted",
            "createNearbyGroup", "joinNearbyGroup", "setNearbyIdentity", "disconnect")) {
            assertTrue(m, NearbyBackgroundPolicy.isAllowed(m))
        }
    }

    @Test
    fun `pop-up connect hotspot and linked groups need the open app`() {
        for (m in listOf("connect", "requestEnable", "startLocalHotspot", "joinLocalNet",
            "setNearbyBridge", "setNearbyLinkTarget", "unknown")) {
            assertFalse(m, NearbyBackgroundPolicy.isAllowed(m))
        }
    }

    @Test
    fun `battery stop level is 10`() {
        assertEquals(10, NearbyBackgroundPolicy.BATTERY_STOP_LEVEL)
    }

    @Test
    fun `at most 3 channel re-setups in 10 minutes`() {
        val now = 100_000_000L
        val times = mutableListOf(now - 1_000L, now - 2_000L, now - 3_000L)
        assertEquals(3, NearbyBackgroundPolicy.recentReinits(times, now))
        assertFalse(NearbyBackgroundPolicy.mayReinit(3))
        assertTrue(NearbyBackgroundPolicy.mayReinit(2))
        val old = mutableListOf(now - NearbyBackgroundPolicy.REINIT_WINDOW_MS, now - 1_000L)
        assertEquals(1, NearbyBackgroundPolicy.recentReinits(old, now))
        val future = mutableListOf(now + 5_000L)
        assertEquals(0, NearbyBackgroundPolicy.recentReinits(future, now))
    }
}
