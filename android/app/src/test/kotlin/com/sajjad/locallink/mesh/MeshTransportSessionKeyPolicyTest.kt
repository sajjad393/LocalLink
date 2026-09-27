package com.sajjad.locallink.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshTransportSessionKeyPolicyTest {
    @Test
    fun sameInputsProduceSameEpochKey() {
        val a = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", 10L)
        val b = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", 10L)
        assertArrayEquals(a, b)
    }

    @Test
    fun changingEpochOrPeerChangesSessionKey() {
        val base = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", 10L)
        val nextEpoch = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "B", 11L)
        val otherPeer = MeshTransportSessionKeyPolicy.deriveKey("shared", "A", "C", 10L)
        assertFalse(base.contentEquals(nextEpoch))
        assertFalse(base.contentEquals(otherPeer))
        assertEquals(10L, MeshTransportSessionKeyPolicy.currentEpoch(MeshTransportSessionKeyPolicy.ROTATION_MS * 10 + 1))
    }

    @Test
    fun adjacentEpochsProvideGraceDuringRotation() {
        val now = MeshTransportSessionKeyPolicy.ROTATION_MS * 10 + 5L
        val accepted = MeshTransportSessionKeyPolicy.acceptedEpochs(now)
        assertTrue(accepted.contains(9L))
        assertTrue(accepted.contains(10L))
        assertTrue(accepted.contains(11L))
    }
}
