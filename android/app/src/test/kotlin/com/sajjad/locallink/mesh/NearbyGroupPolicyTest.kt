package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 157: one shared group — tag format, names, passwords, guards. */
class NearbyGroupPolicyTest {
    private val id = "0123456789abcdef"

    @Test fun `a fresh group name and password every time, valid for Android`() {
        val n1 = NearbyGroupPolicy.newNetworkName()
        val n2 = NearbyGroupPolicy.newNetworkName()
        assertTrue(n1.startsWith("DIRECT-LL-"))
        assertTrue(NearbyGroupPolicy.validNetworkName(n1))
        assertNotEquals(n1, n2)
        val p = NearbyGroupPolicy.newPassphrase()
        assertEquals(16, p.length)
        assertTrue(NearbyGroupPolicy.validPassphrase(p))
        assertNotEquals(p, NearbyGroupPolicy.newPassphrase())
    }

    @Test fun `names and passwords are checked`() {
        assertTrue(NearbyGroupPolicy.validNetworkName("DIRECT-a1-Galaxy S10"))
        assertFalse(NearbyGroupPolicy.validNetworkName("MyWifi"))
        assertFalse(NearbyGroupPolicy.validNetworkName("DIRECT-LL-" + "x".repeat(30)))
        assertFalse(NearbyGroupPolicy.validPassphrase("short"))
        assertFalse(NearbyGroupPolicy.validPassphrase(null))
        assertTrue(NearbyGroupPolicy.validPassphrase("abcd1234"))
    }

    @Test fun `host tag carries name, password and wanted ids`() {
        val txt = NearbyTagPolicy.encode(id, host = true, member = false, members = 2,
            groupName = "DIRECT-LL-abc123", groupKey = "Secret1234567890",
            wanted = listOf("aaaaaaaabbbb", "AAAAAAAA", "zzzz", "cccccccc", "dddddddd", "eeeeeeee"))
        assertEquals("1", txt["gv"])
        assertEquals("DIRECT-LL-abc123", txt["g"])
        assertEquals("Secret1234567890", txt["k"])
        assertEquals("aaaaaaaa,cccccccc,dddddddd", txt["w"])
        val tag = NearbyTagPolicy.decode("LocalLink._locallink._tcp.local.", txt, "AA:BB:CC:DD:EE:01", 5L)!!
        assertEquals(true, tag["gv"])
        assertEquals("DIRECT-LL-abc123", tag["group"])
        assertEquals("Secret1234567890", tag["key"])
        assertEquals(listOf("aaaaaaaa", "cccccccc", "dddddddd"), tag["wanted"])
    }

    @Test fun `a member never publishes the password and a free phone no group`() {
        val member = NearbyTagPolicy.encode(id, host = false, member = true, members = 0,
            groupName = "DIRECT-LL-abc123", groupKey = "Secret1234567890")
        assertEquals("DIRECT-LL-abc123", member["g"])
        assertNull(member["k"])
        val free = NearbyTagPolicy.encode(id, host = false, member = false, members = 0,
            groupName = "DIRECT-LL-abc123", groupKey = "Secret1234567890")
        assertNull(free["g"])
        assertNull(free["k"])
        // A tag that claims a password without being host is ignored.
        val forged = NearbyTagPolicy.decode(null, member + ("k" to "Secret1234567890"), "aa:bb:cc:dd:ee:02", 1L)!!
        assertFalse(forged.containsKey("key"))
    }

    @Test fun `155 tags still decode (no group keys)`() {
        val old = mapOf("v" to "1", "id" to id, "host" to "1", "m" to "0", "n" to "1", "full" to "0")
        val tag = NearbyTagPolicy.decode(null, old, "aa:bb:cc:dd:ee:03", 1L)!!
        assertEquals(false, tag["gv"])
        assertFalse(tag.containsKey("group"))
        assertEquals(true, tag["host"])
    }

    @Test fun `a phone in a group only changes group when told to leave`() {
        assertTrue(NearbyGroupPolicy.mayChangeGroup(groupFormed = false, groupOwner = false, leave = false))
        assertFalse(NearbyGroupPolicy.mayChangeGroup(groupFormed = true, groupOwner = false, leave = false))
        assertFalse(NearbyGroupPolicy.mayChangeGroup(groupFormed = true, groupOwner = true, leave = false))
        assertTrue(NearbyGroupPolicy.mayChangeGroup(groupFormed = true, groupOwner = false, leave = true))
    }

    @Test fun `a group host can take all its members as relay links`() {
        assertEquals(NearbyTagPolicy.GROUP_SOFT_LIMIT + 1, NearbyGroupPolicy.maxRelayLinks(MeshTransportPolicy.WIFI_DIRECT))
        assertEquals(MeshRelayPolicy.MAX_RELAY_LINKS, NearbyGroupPolicy.maxRelayLinks(MeshTransportPolicy.LAN))
    }
}
