package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 223 (K): LAN beacon back-off while the network is unreachable. */
class LanBeacon223Test {
    @Test fun `223-27 unreachable error pauses 15 s and is reported once`() {
        val b = MeshTransportPolicy.LanBeaconBackoff()
        assertTrue("first error is reported", b.onError(true))
        assertTrue(b.paused)
        assertEquals(15_000L, b.nextDelayMs(3_000L))
        assertFalse("second error is quiet", b.onError(true))
        assertFalse(b.onError(true))
    }

    @Test fun `223-27 a good send brings the normal tier back`() {
        val b = MeshTransportPolicy.LanBeaconBackoff()
        b.onError(true)
        assertTrue("resumed is logged once", b.onOk())
        assertFalse(b.onOk())
        assertEquals(3_000L, b.nextDelayMs(3_000L))
        assertTrue("a new outage is reported again", b.onError(true))
    }

    @Test fun `223-27 other errors are still reported every time and do not pause`() {
        val b = MeshTransportPolicy.LanBeaconBackoff()
        assertTrue(b.onError(false))
        assertTrue(b.onError(false))
        assertFalse(b.paused)
    }

    @Test fun `223-27 unreachable text`() {
        assertTrue(MeshTransportPolicy.isUnreachable("sendto failed: ENETUNREACH (Network is unreachable)"))
        assertTrue(MeshTransportPolicy.isUnreachable("Network is unreachable"))
        assertFalse(MeshTransportPolicy.isUnreachable("Permission denied"))
        assertFalse(MeshTransportPolicy.isUnreachable(null))
    }

    @Test fun `223-27 source the service uses the back-off`() {
        val s = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(s.contains("lanBackoff.nextDelayMs(MeshTransportPolicy.jitteredBeaconMs(phones, Math.random()))"))
        assertTrue(s.contains("if (!lanBackoff.onError(unreachable)) return"))
        assertTrue(s.contains("LAN_BEACON paused why=no_network"))
        assertTrue(s.contains("LAN_BEACON resumed why=net_change"))
    }
}
