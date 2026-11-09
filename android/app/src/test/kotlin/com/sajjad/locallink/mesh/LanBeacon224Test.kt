package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import com.sajjad.locallink.mesh.MeshTransportPolicy.BeaconOutcome as O

/** Bundle 224 (B): one bad address stopped the beacon to all of them. */
class LanBeacon224Test {
    @Test fun `224-B1 one address works - not paused`() {
        assertEquals(O.OK, MeshTransportPolicy.beaconOutcome(1, 1, 0))
        assertEquals(O.OK, MeshTransportPolicy.beaconOutcome(1, 0, 2))
    }

    @Test fun `224-B1 every address unreachable - paused as in 223`() {
        assertEquals(O.PAUSE, MeshTransportPolicy.beaconOutcome(0, 2, 0))
        assertEquals(O.PAUSE, MeshTransportPolicy.beaconOutcome(0, 1, 0))
    }

    @Test fun `224-B1 other error - reported, no pause`() {
        assertEquals(O.REPORT, MeshTransportPolicy.beaconOutcome(0, 0, 1))
        assertEquals(O.REPORT, MeshTransportPolicy.beaconOutcome(0, 3, 1))
        assertEquals("no address at all is the same as before", O.OK, MeshTransportPolicy.beaconOutcome(0, 0, 0))
    }

    @Test fun `224-B2 a new group or a new role sends a beacon now`() {
        assertTrue(MeshTransportPolicy.wdGroupChanged(null, null, true, false))
        assertTrue(MeshTransportPolicy.wdGroupChanged(false, false, true, true))
        assertTrue("role changed", MeshTransportPolicy.wdGroupChanged(true, false, true, true))
        assertFalse("same group again", MeshTransportPolicy.wdGroupChanged(true, true, true, true))
        assertFalse("group gone", MeshTransportPolicy.wdGroupChanged(true, true, false, false))
    }

    @Test fun `224-B the send loop catches per address`() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        val body = src.substringAfter("private fun broadcastLanBeacon(").substringBefore("private fun lanBroadcastAddresses(")
        val loop = body.substringAfter("addresses.forEach { destination ->").substringBefore("when (MeshTransportPolicy.beaconOutcome(")
        assertTrue("try is inside the loop", loop.contains("try {") && loop.contains("socket.send("))
        assertTrue(src.contains("LAN_BEACON resumed why=wd_group"))
    }
}
