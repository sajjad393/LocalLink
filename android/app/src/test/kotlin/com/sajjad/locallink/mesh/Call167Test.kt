package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Call167Test {
    @Test
    fun `voice passing through - on once, refreshed every 10 s, off after 8 s idle`() {
        val t = VoiceRelayTracker()
        assertTrue(t.onForward(0L))
        assertFalse(t.onForward(20L))
        assertFalse(t.onTick(5_000L))
        assertTrue(t.isActive(5_000L))
        assertTrue("refresh", t.onForward(10_000L))
        assertFalse(t.onTick(17_000L))
        assertTrue(t.onTick(18_000L))
        assertFalse(t.isActive(18_000L))
        assertFalse("off only once", t.onTick(30_000L))
        assertTrue("on again", t.onForward(31_000L))
    }

    @Test
    fun `call flag goes in the nearby tag and comes back out`() {
        val txt = NearbyTagPolicy.encode("0123456789abcdef", host = false, member = true, members = 0, inCall = true)
        assertEquals("1", txt["call"])
        val tag = NearbyTagPolicy.decode(null, txt, "aa:bb:cc:dd:ee:ff", 1L)!!
        assertEquals(true, tag["in_call"])
        val plain = NearbyTagPolicy.encode("0123456789abcdef", host = false, member = false, members = 0)
        assertNull(plain["call"])
        assertNull(NearbyTagPolicy.decode(null, plain, "aa:bb:cc:dd:ee:ff", 1L)!!["in_call"])
    }
}
