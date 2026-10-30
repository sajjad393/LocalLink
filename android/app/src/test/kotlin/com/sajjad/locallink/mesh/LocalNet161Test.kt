package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 161: linked groups, LocalLink hotspot, smaller map on members. */
class LocalNet161Test {

    // ------------------------------------------------ names, keys, addresses

    @Test fun `hotspot names and passwords are checked`() {
        assertTrue(LocalNetPolicy.validSsid("AndroidShare_1234"))
        assertTrue(LocalNetPolicy.validSsid("DIRECT-LL-abc123"))
        assertFalse(LocalNetPolicy.validSsid(""))
        assertFalse(LocalNetPolicy.validSsid("a,b"))
        assertFalse(LocalNetPolicy.validSsid(" padded "))
        assertFalse(LocalNetPolicy.validSsid("x".repeat(33)))
        assertTrue(LocalNetPolicy.validKey("pass1234"))
        assertFalse(LocalNetPolicy.validKey("short"))
        assertFalse(LocalNetPolicy.validKey("has space 123"))
        assertFalse(LocalNetPolicy.validKey("x".repeat(64)))
        assertEquals("Net", LocalNetPolicy.unquote("\"Net\""))
        assertEquals("Net", LocalNetPolicy.unquote("Net"))
        assertNull(LocalNetPolicy.unquote(null))
    }

    @Test fun `only IPv6 link-local addresses are used from the tag`() {
        assertTrue(LocalNetPolicy.validV6("fe80::1"))
        assertTrue(LocalNetPolicy.validV6("fe80::a1b2:c3ff:fed4:e5f6"))
        assertTrue(LocalNetPolicy.validV6("fe80:0000:0000:0000:1234:5678:9abc:def0"))
        assertFalse(LocalNetPolicy.validV6("2001:db8::1"))
        assertFalse(LocalNetPolicy.validV6("fe80::1%p2p-wlan0-0"))
        assertFalse(LocalNetPolicy.validV6("fe80:::1"))
        assertFalse(LocalNetPolicy.validV6(null))
    }

    @Test fun `dial order is the other host's IPv6 first, never an address this phone owns`() {
        // A member of group B: 192.168.49.1 is group A's host there.
        assertEquals(listOf("fe80::1", "192.168.49.1"),
            LocalNetPolicy.candidates("fe80::1", "192.168.49.1", "192.168.49.1", setOf("192.168.49.23")))
        // A HOST of group B owns 192.168.49.1 itself: only IPv6 is left.
        assertEquals(listOf("fe80::1"),
            LocalNetPolicy.candidates("fe80::1", "192.168.49.1", null, setOf("192.168.49.1")))
        // ... and without the other host's IPv6 there is nothing to dial.
        assertTrue(LocalNetPolicy.candidates(null, "192.168.49.1", null, setOf("192.168.49.1")).isEmpty())
        // Hotspot: gateway, then the DHCP server if different.
        assertEquals(listOf("192.168.43.1", "192.168.43.2"),
            LocalNetPolicy.candidates(null, "/192.168.43.1", "192.168.43.2", emptySet()))
        assertTrue(LocalNetPolicy.candidates("bad", "0.0.0.0", "999.1.1.1", emptySet()).isEmpty())
    }

    @Test fun `a dropped link is retried only while the network is there`() {
        assertTrue(LocalNetPolicy.shouldRetry(networkAvailable = true, retries = 1, left = false))
        assertFalse(LocalNetPolicy.shouldRetry(networkAvailable = true, retries = LocalNetPolicy.MAX_RETRIES, left = false))
        assertFalse(LocalNetPolicy.shouldRetry(networkAvailable = false, retries = 0, left = false))
        assertFalse(LocalNetPolicy.shouldRetry(networkAvailable = true, retries = 0, left = true))
        assertEquals("no_channel", LocalNetPolicy.hotspotFailure(1))
        assertEquals("incompatible_mode", LocalNetPolicy.hotspotFailure(3))
        assertEquals("error_9", LocalNetPolicy.hotspotFailure(9))
    }

    @Test fun `the new link type is supported and ranked between Local Wi-Fi and Wi-Fi Direct`() {
        assertTrue(MeshTransportPolicy.isSupportedTransport(MeshTransportPolicy.LOCAL_NET))
        assertTrue(MeshTransportPolicy.transportPriority(MeshTransportPolicy.LAN) >
            MeshTransportPolicy.transportPriority(MeshTransportPolicy.LOCAL_NET))
        assertTrue(MeshTransportPolicy.transportPriority(MeshTransportPolicy.LOCAL_NET) >
            MeshTransportPolicy.transportPriority(MeshTransportPolicy.WIFI_DIRECT))
        assertEquals(MeshRouteChoicePolicy.RANK_WIFI_DIRECT, MeshRouteChoicePolicy.linkRank(MeshTransportPolicy.LOCAL_NET))
        assertEquals(LocalNetPolicy.MAX_RELAY_LINKS, NearbyGroupPolicy.maxRelayLinks(MeshTransportPolicy.LOCAL_NET))
        assertEquals(MeshRelayPolicy.MAX_RELAY_LINKS, NearbyGroupPolicy.maxRelayLinks(MeshTransportPolicy.LAN))
        assertEquals(8991, MeshTransportPolicy.LOCAL_NET_PORT)
    }

    // ------------------------------------------------------------- tags

    @Test fun `tags carry the host address, the hotspot and the link target`() {
        val txt = NearbyTagPolicy.encode("1111111111111111", host = true, member = false, members = 3,
            groupName = "DIRECT-LL-abc123", groupKey = "pass12345678",
            v6 = "fe80::1", hotspotSsid = "AndroidShare_1", hotspotKey = "hotpass99", linkTarget = "a1b2c3d4")
        assertEquals("fe80::1", txt["v6"])
        assertEquals("AndroidShare_1", txt["hs"])
        assertEquals("hotpass99", txt["hk"])
        assertEquals("a1b2c3d4", txt["lt"])
        val tag = NearbyTagPolicy.decode(null, txt, "aa:bb:cc:dd:ee:01", 5L)!!
        assertEquals("fe80::1", tag["v6"])
        assertEquals("AndroidShare_1", tag["hotspot_ssid"])
        assertEquals("hotpass99", tag["hotspot_key"])
        assertEquals("a1b2c3d4", tag["link_target"])
    }

    @Test fun `bad or out of place tag values are dropped`() {
        // A member never publishes v6; no group = no link target; a hotspot
        // needs both name and password.
        val txt = NearbyTagPolicy.encode("2222222222222222", host = false, member = false, members = 0,
            v6 = "fe80::1", hotspotSsid = "OnlyName", hotspotKey = null, linkTarget = "a1b2c3d4")
        assertFalse(txt.containsKey("v6"))
        assertFalse(txt.containsKey("hs"))
        assertFalse(txt.containsKey("lt"))
        val forged = mapOf("v" to "1", "id" to "3333333333333333", "host" to "0", "m" to "1",
            "g" to "DIRECT-LL-abc123", "v6" to "fe80::9", "hs" to "a,b", "hk" to "pass1234", "lt" to "XYZ")
        val tag = NearbyTagPolicy.decode(null, forged, "aa:bb:cc:dd:ee:02", 1L)!!
        assertFalse(tag.containsKey("v6"))
        assertFalse(tag.containsKey("hotspot_ssid"))
        assertFalse(tag.containsKey("link_target"))
        // A 160 tag still decodes the same.
        val old = NearbyTagPolicy.decode(null, mapOf("v" to "1", "id" to "4444444444444444", "host" to "1"), "aa:bb", 1L)!!
        assertFalse(old.containsKey("hotspot_ssid"))
    }

    // ------------------------------------------------------- 3.3 smaller map

    @Test fun `only a member with one link to its host is compact`() {
        assertTrue(MeshTwoLevelMap.isCompactMember(groupOwner = false, hostLinkUp = true, otherLinks = 0))
        assertFalse(MeshTwoLevelMap.isCompactMember(groupOwner = true, hostLinkUp = false, otherLinks = 0))
        assertFalse(MeshTwoLevelMap.isCompactMember(groupOwner = false, hostLinkUp = true, otherLinks = 1)) // bridge / LAN / linked
        assertFalse(MeshTwoLevelMap.isCompactMember(groupOwner = false, hostLinkUp = false, otherLinks = 0))
        assertTrue(MeshTwoLevelMap.needsFullAgain(wasCompact = true, compact = false))
        assertFalse(MeshTwoLevelMap.needsFullAgain(wasCompact = false, compact = false))
    }

    @Test fun `a compact member keeps its group and contacts and drops far strangers`() {
        assertTrue(MeshTwoLevelMap.keep(compact = true, fromHost = true, hopCount = 2, isContact = false))
        assertTrue(MeshTwoLevelMap.keep(compact = true, fromHost = true, hopCount = 6, isContact = true))
        assertFalse(MeshTwoLevelMap.keep(compact = true, fromHost = true, hopCount = 3, isContact = false))
        assertTrue(MeshTwoLevelMap.keep(compact = true, fromHost = false, hopCount = 5, isContact = false))
        assertTrue(MeshTwoLevelMap.keep(compact = false, fromHost = true, hopCount = 7, isContact = false))
        // 300 people behind the host, 5 of them contacts: 7 group + 5 contacts kept.
        val kept = (1..300).count { i ->
            val hops = if (i <= 7) 2 else 3 + (i % 5)
            MeshTwoLevelMap.keep(true, true, hops, isContact = i in 100..104)
        }
        assertEquals(12, kept)
        assertTrue(MeshTwoLevelMap.defaultForAll(true))
        assertTrue(MeshTwoLevelMap.skipLookup(true))
        assertFalse(MeshTwoLevelMap.defaultForAll(false))
    }

    // --------------------------------------- simulation: 4 groups, no router

    /**
     * 4 Wi-Fi Direct groups of 8 (host + 7), no router. One member of each
     * group links to the next group's host (3.1). Hosts and link phones keep
     * the full map; the other members are compact (3.3) and send anything
     * outside their group to their host. Every phone must reach every other
     * phone within 8 hops, without loops.
     */
    @Test fun `32 phones in 4 linked groups all reach each other within 8 hops`() {
        val groups = 4
        val edges = HashMap<String, MutableSet<String>>()
        fun link(a: String, b: String) {
            edges.getOrPut(a) { mutableSetOf() } += b
            edges.getOrPut(b) { mutableSetOf() } += a
        }
        val hosts = (0 until groups).map { "h$it" }
        val linkers = mutableSetOf<String>()
        for (g in 0 until groups) for (m in 1..7) link("h$g", "m$g-$m")
        for (g in 0 until groups - 1) { link("m$g-1", "h${g + 1}"); linkers += "m$g-1" }
        val nodes = edges.keys.toList()
        assertEquals(32, nodes.size)
        // Shortest next hop for full-map phones (BFS from each destination).
        fun nextHop(from: String, to: String): String? {
            val prev = HashMap<String, String>()
            val queue = ArrayDeque(listOf(to)); val seen = mutableSetOf(to)
            while (queue.isNotEmpty()) {
                val n = queue.removeFirst()
                for (x in edges[n].orEmpty()) if (seen.add(x)) { prev[x] = n; queue.addLast(x) }
            }
            return prev[from]
        }
        fun hostOf(member: String) = "h" + member.substring(1).substringBefore('-')
        for (src in nodes) for (dst in nodes) {
            if (src == dst) continue
            var at = src
            var hops = 0
            val path = mutableSetOf(src)
            while (at != dst) {
                val compact = at.startsWith("m") && at !in linkers &&
                    MeshTwoLevelMap.isCompactMember(groupOwner = false, hostLinkUp = true, otherLinks = 0)
                val sameGroup = at.startsWith("m") && dst != hostOf(at) && edges[hostOf(at)]!!.contains(dst)
                at = when {
                    !compact -> nextHop(at, dst)!!
                    dst in edges[at]!! -> dst
                    sameGroup -> hostOf(at)               // group route (2 hops)
                    else -> hostOf(at)                    // default route to the host
                }
                hops++
                assertTrue("loop $src->$dst at $at", path.add(at))
            }
            assertTrue("$src->$dst took $hops hops", hops <= MeshLimits.MAX_HOPS)
        }
        assertTrue(hosts.all { it in edges })
    }
}
