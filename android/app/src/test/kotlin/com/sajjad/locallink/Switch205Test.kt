package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 205: smooth switching rules (labels, wake, router, search, logs). */
class Switch205Test {
    @Test
    fun lanInsideWifiDirectGroupIsWifiDirect() {
        assertEquals("wifi_direct", LinkKindPolicy.pathKind("lan", "192.168.49.1"))
        assertEquals("wifi_direct", LinkKindPolicy.pathKind("lan", "/192.168.49.23"))
        assertEquals("wifi_direct", LinkKindPolicy.pathKind("lan", "fe80::1", "p2p-wlan0-0"))
        assertEquals("lan", LinkKindPolicy.pathKind("lan", "192.168.1.7"))
        assertEquals("lan", LinkKindPolicy.pathKind("lan", null))
        assertEquals("wifi_direct", LinkKindPolicy.pathKind("local_net", "10.0.0.2"))
        assertEquals("wifi_direct", LinkKindPolicy.pathKind("wifi_direct", "192.168.49.1"))
        assertEquals(
            "LINK_KIND_FIXED peer=26da19f3 was=lan now=wifi_direct",
            LinkKindPolicy.fixedLine("android-5bb3430f26da19f3", "lan", "wifi_direct"),
        )
    }

    @Test
    fun staleDisconnectNoteKeepsAFreshLink() {
        assertTrue(LinkKindPolicy.mayCloseOnDisconnect(0L, 1_000L))
        assertFalse(LinkKindPolicy.mayCloseOnDisconnect(10_000L, 10_024L))
        assertFalse(LinkKindPolicy.mayCloseOnDisconnect(10_000L, 14_999L))
        assertTrue(LinkKindPolicy.mayCloseOnDisconnect(10_000L, 15_000L))
    }

    @Test
    fun wifiOffDropsRouterLinksOnly() {
        assertTrue(LinkKindPolicy.dropOnWifiDown("lan", "192.168.1.7"))
        assertFalse(LinkKindPolicy.dropOnWifiDown("lan", "192.168.49.1"))
        assertFalse(LinkKindPolicy.dropOnWifiDown("wifi_direct", "192.168.49.1"))
        assertFalse(LinkKindPolicy.dropOnWifiDown("local_net", "10.0.0.2"))
    }

    @Test
    fun callPathKindUsesTheAddress() {
        assertEquals("wifi_direct", CallPathPolicy.kind("lan", false, "192.168.49.1"))
        assertEquals("lan", CallPathPolicy.kind("lan", false, "192.168.1.7"))
        assertEquals("lan", CallPathPolicy.kind("lan", false))
    }

    @Test
    fun onlyARealRouterCountsAsWifi() {
        assertTrue(RouterNetworkPolicy.isRouter(true, true, "wlan0", false, listOf("192.168.1.7")))
        // The own Wi-Fi Direct group listed as a restricted Wi-Fi network.
        assertFalse(RouterNetworkPolicy.isRouter(true, false, "wlan0", false))
        assertFalse(RouterNetworkPolicy.isRouter(true, true, "p2p-wlan0-0", false))
        assertFalse(RouterNetworkPolicy.isRouter(true, true, "wlan1", false, listOf("192.168.49.1")))
        assertFalse(RouterNetworkPolicy.isRouter(true, true, "wlan0", true))
        assertFalse(RouterNetworkPolicy.isRouter(false, true, "rmnet0", false))
    }

    @Test
    fun reconnectWakeLimits() {
        val now = 100_000_000L
        assertTrue(ReconnectWakePolicy.mayStart(now, false, 0L, 50, false))
        assertFalse(ReconnectWakePolicy.mayStart(now, true, 0L, 50, false))
        assertFalse(ReconnectWakePolicy.mayStart(now, false, 0L, 10, false))
        assertTrue(ReconnectWakePolicy.mayStart(now, false, 0L, 10, true))
        assertTrue(ReconnectWakePolicy.mayStart(now, false, 0L, -1, false))
        assertFalse(ReconnectWakePolicy.mayStart(now, false, now - 9 * 60_000L, 50, false))
        assertTrue(ReconnectWakePolicy.mayStart(now, false, now - 10 * 60_000L, 50, false))
        assertEquals(5 * 60_000L, ReconnectWakePolicy.HOLD_MS)
        assertEquals("rest", ReconnectWakePolicy.skipReason(now, false, now - 1_000L, 50, false))
        assertEquals("battery", ReconnectWakePolicy.skipReason(now, false, 0L, 5, false))
        assertEquals("RECONNECT_WAKE on why=link_died hold_s=300", ReconnectWakePolicy.onLine("link_died"))
        assertEquals("RECONNECT_WAKE off why=linked after_s=12", ReconnectWakePolicy.offLine("linked", 12_400L))
    }

    @Test
    fun noPeersSearchWhileLinked() {
        assertTrue(SearchWindowPolicy.peersWindowAllowed(member = false, host = false, members = 0))
        assertTrue(SearchWindowPolicy.peersWindowAllowed(member = false, host = true, members = 0))
        assertFalse(SearchWindowPolicy.peersWindowAllowed(member = false, host = true, members = 1))
        assertFalse(SearchWindowPolicy.peersWindowAllowed(member = true, host = false, members = 0))
    }

    @Test
    fun groupLostSaysWhy() {
        val now = 1_000_000L
        assertEquals("p2p_off", WdGroupLost.why(now, false, 0L, 0L, 0L))
        assertEquals("self", WdGroupLost.why(now, true, now - 3_000L, now - 1_000L, 0L))
        assertEquals("after_search", WdGroupLost.why(now, true, now - 60_000L, now - 7_000L, 0L))
        assertEquals("app_close", WdGroupLost.why(now, true, 0L, now - 60_000L, now - 2_000L))
        assertEquals("other_or_system", WdGroupLost.why(now, true, 0L, now - 60_000L, now - 60_000L))
        val d = WdGroupLost.detail("DISCONNECTED", null, null)
        assertEquals("WD_GROUP_LOST was=member p2p=on $d why=after_search",
            WdGroupLost.line(false, true, d, "after_search"))
        // The old line stays the same.
        assertEquals("WD_GROUP_LOST was=host p2p=on $d", WdGroupLost.line(true, true, d))
    }
}
