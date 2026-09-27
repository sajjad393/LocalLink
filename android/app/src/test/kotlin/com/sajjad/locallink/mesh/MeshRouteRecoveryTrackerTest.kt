package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshRouteRecoveryTrackerTest {
    @Test
    fun disconnectMarksAffectedDestinationsAndReconnectClearsThem() {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 60_000L)
        val affected = tracker.markPeerLost("B", listOf("C", "D", "C", ""), 1_000L)
        assertEquals(listOf("C", "D"), affected)
        assertEquals(2, tracker.snapshot().size)
        val recovery = tracker.markRecovered("C")
        assertEquals("B", recovery!!.failedNextHopNodeId)
        assertNull(tracker.markRecovered("C"))
        assertEquals(listOf("D"), tracker.pendingForPeer("B").map { it.destinationNodeId })
    }

    @Test
    fun removingOneNextHopKeepsOtherRoutesForSameDestination() {
        val table = MeshRouteTable()
        val expiry = Long.MAX_VALUE
        assertTrue(table.upsert("D", MeshRoute("D", "B", 2, expiry, 1L, 1L, listOf("A", "B", "D"))))
        assertTrue(table.upsert("D", MeshRoute("D", "C", 3, expiry, 1L, 2L, listOf("A", "C", "X", "D"))))
        assertEquals(1, table.remove("D", "B").size)
        assertEquals("C", table["D"]!!.nextHopNodeId)
        assertEquals(1, table.allFor("D").size)
    }

    @Test
    fun staleRecoveryEntriesExpireWithoutAffectingNewEntries() {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 10_000L)
        tracker.markPeerLost("B", listOf("C"), 1_000L)
        tracker.markPeerLost("E", listOf("F"), 9_000L)
        val expired = tracker.prune(11_001L)
        assertEquals(listOf("C"), expired.map { it.destinationNodeId })
        assertEquals(listOf("F"), tracker.snapshot().map { it["destination_id"] })
        assertTrue(tracker.pendingForPeer("B").isEmpty())
    }
    @Test
    fun repeatedPeerLossUpdatesNeverExceedGlobalCapacity() {
        val tracker = MeshRouteRecoveryTracker(retentionMs = 60_000L, maxEntries = 3)
        tracker.markPeerLost("B", listOf("D1", "D2", "D3"), 1_000L)
        tracker.markPeerLost("B", listOf("D4", "D5"), 1_001L)

        assertEquals(3, tracker.size())
        assertEquals(listOf("D3", "D4", "D5"), tracker.snapshot().map { it["destination_id"] })
    }

}
