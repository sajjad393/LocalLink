package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshSeenPacketTrackerTest {
    @Test
    fun dropsDuplicateOnlyForSameSourceAndPacketId() {
        val tracker = MeshSeenPacketTracker(maxEntries = 4, retentionMs = 1_000L)
        assertTrue(tracker.markSeen("A", "p1", now = 1_000L))
        assertFalse(tracker.markSeen("A", "p1", now = 1_001L))
        assertTrue(tracker.markSeen("B", "p1", now = 1_001L))
        assertTrue(tracker.markSeen("A", "p2", now = 1_001L))
        assertEquals(3, tracker.size())
    }

    @Test
    fun expiresOldEntriesAndStaysBounded() {
        val tracker = MeshSeenPacketTracker(maxEntries = 2, retentionMs = 100L)
        assertTrue(tracker.markSeen("A", "p1", now = 1_000L))
        assertTrue(tracker.markSeen("A", "p2", now = 1_001L))
        assertTrue(tracker.markSeen("A", "p3", now = 1_002L))
        assertTrue(tracker.size() <= 2)
        tracker.cleanup(1_200L)
        assertEquals(0, tracker.size())
    }

    @Test
    fun staleAndFutureRestoreEntriesAreRejected() {
        val tracker = MeshSeenPacketTracker(maxEntries = 4, retentionMs = 1_000L)
        assertFalse(tracker.restore("A", "old", seenAt = 1_000L, now = 2_001L))
        assertFalse(tracker.restore("A", "future", seenAt = 2_002L, now = 2_001L))
        assertTrue(tracker.restore("A", "fresh", seenAt = 1_500L, now = 2_001L))
    }

    @Test
    fun capacityEvictionNotifiesPersistenceLayer() {
        val evicted = mutableListOf<String>()
        val tracker = MeshSeenPacketTracker(
            maxEntries = 2,
            retentionMs = 10_000L,
            onEvicted = { key, _ -> evicted += key },
        )
        assertTrue(tracker.markSeen("A", "p1", 1_000L))
        assertTrue(tracker.markSeen("A", "p2", 1_001L))
        assertTrue(tracker.markSeen("A", "p3", 1_002L))
        assertEquals(2, tracker.size())
        assertTrue(evicted.contains(tracker.keyFor("A", "p1")))
    }

    @Test
    fun concurrentSamePacketStillAdmitsOnlyOnce() {
        val tracker = MeshSeenPacketTracker(maxEntries = 100, retentionMs = 10_000L)
        val threads = (0 until 16).map { Thread { tracker.markSeen("A", "same", 1_000L) }.also { it.start() } }
        threads.forEach(Thread::join)
        assertEquals(1, tracker.size())
        assertFalse(tracker.markSeen("A", "same", 1_001L))
    }
}
