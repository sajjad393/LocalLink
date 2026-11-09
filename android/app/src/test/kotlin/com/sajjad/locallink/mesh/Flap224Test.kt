package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 224 (E): quick reconnect loop (153 links in 10 min, each < 0.1 s). */
class Flap224Test {
    private val p = "android-6a40e775a0caa5a7"

    private fun drops(g: MeshDialFlapGuard, at: Long): Long {
        g.onLinkEnded(p, 100L, at)
        g.onLinkEnded(p, 100L, at + 2_000L)
        return g.onLinkEnded(p, 100L, at + 4_000L)
    }

    @Test fun `224-E 2 quick drops - still dials`() {
        val g = MeshDialFlapGuard()
        assertEquals(0L, g.onLinkEnded(p, 100L, 0L))
        assertEquals(0L, g.onLinkEnded(p, 100L, 2_000L))
        assertTrue(g.mayDial(p, 3_000L))
    }

    @Test fun `224-E 3 quick drops - hold 30, 60, 120, 300, 300`() {
        val g = MeshDialFlapGuard()
        var t = 0L
        for (want in listOf(30_000L, 60_000L, 120_000L, 300_000L, 300_000L)) {
            assertEquals(want, drops(g, t))
            assertFalse(g.mayDial(p, t + 4_001L))
            assertTrue(g.mayDial(p, t + 4_000L + want))
            t += 4_000L + want + 1_000L
        }
    }

    @Test fun `224-E free is reported once after the hold`() {
        val g = MeshDialFlapGuard()
        drops(g, 0L)
        assertFalse(g.takeFreed(p, 10_000L))
        assertTrue(g.takeFreed(p, 40_000L))
        assertFalse(g.takeFreed(p, 41_000L))
    }

    @Test fun `224-E drops spread over more than 2 min never hold`() {
        val g = MeshDialFlapGuard()
        assertEquals(0L, g.onLinkEnded(p, 100L, 0L))
        assertEquals(0L, g.onLinkEnded(p, 100L, 70_000L))
        assertEquals(0L, g.onLinkEnded(p, 100L, 140_001L))
        assertTrue(g.mayDial(p, 140_002L))
    }

    @Test fun `224-E a 60 s link resets the peer`() {
        val g = MeshDialFlapGuard()
        drops(g, 0L)
        g.onLinkEnded(p, 60_000L, 100_000L)
        assertTrue(g.mayDial(p, 100_001L))
        assertEquals("back to the first step", 30_000L, drops(g, 200_000L))
    }

    @Test fun `224-E network change and Pair tap reset`() {
        val g = MeshDialFlapGuard()
        drops(g, 0L)
        g.resetAll()
        assertTrue(g.mayDial(p, 5_000L))
        drops(g, 10_000L)
        g.reset(p)
        assertTrue(g.mayDial(p, 15_000L))
    }

    @Test fun `224-E normal links are never held`() {
        val g = MeshDialFlapGuard()
        var t = 0L
        repeat(20) { assertEquals(0L, g.onLinkEnded(p, 30_000L, t)); t += 31_000L }
        assertTrue(g.mayDial(p, t))
        assertTrue("unknown peer", g.mayDial("android-x", 0L))
    }

    @Test fun `224-E wired into the dial paths, WD redial is delayed not dropped`() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(src.contains("if (mayDialLanContact(nodeId, now) && flapAllows(nodeId, now)) connectLanPeer(nodeId, host, port)"))
        assertTrue(src.contains("flapAllows(nodeId, now) && shouldDialRelay(self, nodeId, now)"))
        assertTrue(src.contains("}, 1_000L + held)"))
        assertTrue(src.contains("flapGuard.resetAll() // Bundle 224 (E1)"))
        assertTrue(src.contains("flapGuard.reset(target)"))
        assertTrue("a replaced duplicate is not a drop",
            src.contains("if (transportPeers[connection.peerId] == null) noteLinkEnded(connection.peerId,"))
    }
}
