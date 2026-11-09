package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 226 (B3): Android's scan limits and the failure rest. */
class BleRate226Test {
    @Test
    fun `5 scan starts per 30 s`() {
        val starts = ArrayList<Long>()
        for (i in 0 until 5) {
            assertTrue(NearbyBlePolicy.scanStartAllowed(starts, 1_000L + i))
            starts.add(1_000L + i)
        }
        assertFalse(NearbyBlePolicy.scanStartAllowed(starts, 2_000L))
        assertEquals(29_000L, NearbyBlePolicy.scanWaitMs(starts, 2_000L))
        assertTrue(NearbyBlePolicy.scanStartAllowed(starts, 31_000L))
        assertEquals(4, starts.size)
    }

    @Test
    fun `wait is 0 when a start is allowed`() {
        assertEquals(0L, NearbyBlePolicy.scanWaitMs(listOf(1L, 2L), 3L))
    }

    @Test
    fun `restart the scan every 25 min`() {
        assertFalse(NearbyBlePolicy.restartDue(0L, 99_999_999L))
        assertFalse(NearbyBlePolicy.restartDue(1_000L, 1_000L + 24 * 60_000L))
        assertTrue(NearbyBlePolicy.restartDue(1_000L, 1_000L + 25 * 60_000L))
    }

    @Test
    fun `3 failures in a row rest 10 min, a success resets`() {
        val f = NearbyBlePolicy.Fails()
        assertFalse(f.failed(0))
        f.ok()
        assertFalse(f.failed(1))
        assertFalse(f.failed(2))
        assertTrue(f.failed(3))
        assertTrue(f.resting(3 + 9 * 60_000L))
        assertFalse(f.resting(3 + 10 * 60_000L))
        assertEquals(0, f.row)
    }

    @Test
    fun `seen events at most once per phone per 2 s unless changed`() {
        val g = NearbyBlePolicy.SeenGate()
        val p = NearbyBlePolicy.Packet(id8 = "1a2b3c4d")
        assertTrue(g.shouldEmit(p, 0))
        assertFalse(g.shouldEmit(p.copy(counter = 9), 1_000))
        assertTrue(g.shouldEmit(p.copy(host = true), 1_100))
        assertTrue(g.shouldEmit(p.copy(host = true), 3_200))
        assertTrue(g.shouldLog("1a2b3c4d", 0))
        assertFalse(g.shouldLog("1a2b3c4d", 59_000))
        assertTrue(g.shouldLog("1a2b3c4d", 60_000))
    }
}
