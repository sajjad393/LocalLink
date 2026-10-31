package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class QueueLifetime172Test {
    private val now = 1_000_000L
    private val normal = now + MeshLimits.MAX_PACKET_AGE_MS

    @Test fun `own call invite leaves the queue after 60 s`() {
        assertEquals(now + 60_000L, MeshQueueLifetimePolicy.expiresAt(now, normal, 60_000L, ownPacket = true))
    }

    @Test fun `no hint keeps the normal lifetime`() {
        assertEquals(normal, MeshQueueLifetimePolicy.expiresAt(now, normal, 0L, ownPacket = true))
    }

    @Test fun `packets passed on for others ignore the hint`() {
        assertEquals(normal, MeshQueueLifetimePolicy.expiresAt(now, normal, 60_000L, ownPacket = false))
    }

    @Test fun `the hint never makes the wait longer`() {
        val shortNormal = now + 30_000L
        assertEquals(shortNormal, MeshQueueLifetimePolicy.expiresAt(now, shortNormal, 60_000L, ownPacket = true))
    }

    @Test fun `tiny hints are raised to 5 s`() {
        assertEquals(now + 5_000L, MeshQueueLifetimePolicy.expiresAt(now, normal, 10L, ownPacket = true))
    }
}
