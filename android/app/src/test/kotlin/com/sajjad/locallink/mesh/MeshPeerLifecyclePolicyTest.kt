package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshPeerLifecyclePolicyTest {
    @Test
    fun connectedPeerCannotRegressToDiscovery() {
        assertFalse(MeshPeerLifecyclePolicy.canTransition(MeshPeerState.CONNECTED, MeshPeerState.DISCOVERED))
        assertTrue(MeshPeerLifecyclePolicy.canTransition(MeshPeerState.CONNECTED, MeshPeerState.AVAILABLE))
        assertTrue(MeshPeerLifecyclePolicy.canTransition(MeshPeerState.DISCONNECTED, MeshPeerState.DISCOVERED))
    }

    @Test
    fun registryKeepsLivePeerWhenLanBeaconArrivesAfterConnection() {
        val registry = MeshPeerRegistry()
        registry.connected("peer-a", MeshTransportPolicy.WIFI_DIRECT, 1_000L)
        registry.discovered("peer-a", MeshTransportPolicy.LAN, 1_100L)
        val snapshot = registry.get("peer-a")!!
        assertEquals(MeshPeerState.CONNECTED, snapshot.state)
        assertEquals(MeshTransportPolicy.WIFI_DIRECT, snapshot.transport)
        assertEquals(1_100L, snapshot.lastSeenAt)
    }

    @Test
    fun olderObservationCannotOverwriteNewerLifecycleState() {
        val registry = MeshPeerRegistry()
        registry.connected("peer-a", MeshTransportPolicy.LAN, 2_000L)
        registry.failed("peer-a", MeshTransportPolicy.LAN, 1_500L)
        val snapshot = registry.get("peer-a")!!
        assertEquals(MeshPeerState.CONNECTED, snapshot.state)
        assertEquals(2_000L, snapshot.lastSeenAt)
    }
}
