package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 223 (E): share step 2 finds the hotspot address on wlan0 too. */
class Share223Test {
    private val main = File("main/kotlin/com/sajjad/locallink")

    @Test fun `223-15 wlan0 with a new address is picked (single radio)`() {
        val before = mapOf("wlan0" to "192.168.1.20")
        val after = mapOf("wlan0" to "192.168.43.1")
        assertEquals("192.168.43.1", AppSharePolicy.pickHotspotIp(before, after, null))
        // Wi-Fi was off before: wlan0 appears with the hotspot address.
        assertEquals("10.20.30.1", AppSharePolicy.pickHotspotIp(emptyMap(), mapOf("wlan0" to "10.20.30.1"), null))
    }

    @Test fun `223-15 wlan0 on a router (address unchanged) is skipped`() {
        val m = mapOf("wlan0" to "192.168.1.20")
        assertNull(AppSharePolicy.pickHotspotIp(m, m, "192.168.1.20"))
        // A router address that ends in .1 is still the router.
        val r = mapOf("wlan0" to "192.168.0.1")
        assertNull(AppSharePolicy.pickHotspotIp(r, r, "192.168.0.1"))
    }

    @Test fun `223-15 wlan0 x-x-x-1 with no router counts even if unchanged`() {
        val m = mapOf("wlan0" to "192.168.43.1")
        assertEquals("192.168.43.1", AppSharePolicy.pickHotspotIp(m, m, null))
        assertNull(AppSharePolicy.pickHotspotIp(mapOf("wlan0" to "192.168.43.7"), mapOf("wlan0" to "192.168.43.7"), null))
    }

    @Test fun `223-15 a router joined during the wait is not the hotspot`() {
        assertNull(AppSharePolicy.pickHotspotIp(emptyMap(), mapOf("wlan0" to "192.168.1.9"), "192.168.1.9"))
    }

    @Test fun `223-15 a real hotspot interface still wins over wlan0`() {
        val before = mapOf("wlan0" to "192.168.1.20")
        val after = mapOf("wlan0" to "192.168.1.21", "ap0" to "10.164.88.1")
        assertEquals("10.164.88.1", AppSharePolicy.pickHotspotIp(before, after, null))
        // Wi-Fi Direct never counts.
        assertNull(AppSharePolicy.pickHotspotIp(emptyMap(), mapOf("p2p-wlan0-0" to "192.168.49.1"), null))
    }

    @Test fun `223-15 Android waits 3 s (the app looks on to 10 s) and the logs`() {
        assertEquals(3_000L, AppSharePolicy.ADDRESS_WAIT_MS)
        assertEquals("wlan0=1.2.3.4,ap0=10.0.0.1", AppSharePolicy.listForLog(linkedMapOf("wlan0" to "1.2.3.4", "ap0" to "10.0.0.1")))
        assertEquals("none", AppSharePolicy.listForLog(emptyMap()))
        val s = File(main, "AppShareNative.kt").readText()
        assertTrue(s.contains("addr ms=\$ms found=\${ip ?: \"none\"} list=\${AppSharePolicy.listForLog(now)}"))
        assertTrue(s.contains("AppSharePolicy.pickHotspotIp(before, now, wifiIp(context))"))
        // The start limit no longer stops a hotspot that is up and looking.
        assertTrue(s.contains("if (!done.get() && !hotspotUp.get())"))
        assertFalse(s.contains("AppSharePolicy.pickHotspotIp(before, now)\n"))
    }
}
