package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 224 (A): Realme Share / XShare Wi-Fi Direct groups were treated as LinkUp groups. */
class Foreign224Test {
    private val key = "Abcdefgh23456789"

    @Test fun `224-A1 which groups are LinkUp groups`() {
        assertTrue(NearbyGroupPolicy.isLinkUpGroup("DIRECT-LL-abc123", false))
        assertFalse(NearbyGroupPolicy.isLinkUpGroup("DIRECT-44-realme C71", false))
        assertFalse(NearbyGroupPolicy.isLinkUpGroup("DIRECT-N7-XSHARE-5G-DGJP8", false))
        assertFalse(NearbyGroupPolicy.isLinkUpGroup("DIRECT-L1-XSHARE-5G-LWHD2", false))
        assertTrue("our own old-way group", NearbyGroupPolicy.isLinkUpGroup("DIRECT-xy-Galaxy J5", true))
        assertFalse("not a Wi-Fi Direct name", NearbyGroupPolicy.isLinkUpGroup("HomeWifi", true))
        assertFalse(NearbyGroupPolicy.isLinkUpGroup(null, true))
        assertTrue("validNetworkName is unchanged", NearbyGroupPolicy.validNetworkName("DIRECT-44-realme C71"))
    }

    @Test fun `224-A2 own old-way group - remembered name or the 60 s window`() {
        val t = 1_000_000L
        assertTrue(NearbyGroupPolicy.legacyOwn("DIRECT-xy-J5", null, t, t + 5_000L))
        assertTrue(NearbyGroupPolicy.legacyOwn("DIRECT-xy-J5", null, t, t + 60_000L))
        assertFalse(NearbyGroupPolicy.legacyOwn("DIRECT-xy-J5", null, t, t + 60_001L))
        assertFalse("never created the old way", NearbyGroupPolicy.legacyOwn("DIRECT-44-realme C71", null, 0L, t))
        assertTrue("remembered", NearbyGroupPolicy.legacyOwn("DIRECT-xy-J5", "DIRECT-xy-J5", 0L, t))
        assertFalse(NearbyGroupPolicy.legacyOwn("DIRECT-44-realme C71", "DIRECT-xy-J5", 0L, t))
    }

    @Test fun `224-A4 publish - a LinkUp group as before, lg=1 only for an own old-way group`() {
        val ll = NearbyTagPolicy.encode("0123456789abcdef", true, false, 1, "DIRECT-LL-abc123", key)
        assertEquals("DIRECT-LL-abc123", ll["g"]); assertEquals(key, ll["k"]); assertNull(ll["lg"])
        val legacy = NearbyTagPolicy.encode("0123456789abcdef", true, false, 1, "DIRECT-xy-J5", key, legacyGroup = true)
        assertEquals("1", legacy["lg"])
        val llFlag = NearbyTagPolicy.encode("0123456789abcdef", true, false, 1, "DIRECT-LL-abc123", key, legacyGroup = true)
        assertNull("a DIRECT-LL- name never needs lg", llFlag["lg"])
    }

    @Test fun `224-A4 foreign group - no name and no password in the tag`() {
        // NearbyTagManager passes null name / key and host=0 m=0 for a foreign group.
        val txt = NearbyTagPolicy.encode("0123456789abcdef", false, false, 0, null, null)
        assertNull(txt["g"]); assertNull(txt["k"]); assertEquals("0", txt["host"]); assertEquals("0", txt["m"])
        val src = File("main/kotlin/com/sajjad/locallink/NearbyTagManager.kt").readText()
        assertTrue(src.contains("val host = this.host && !foreign"))
        assertTrue(src.contains("val member = this.member && !foreign"))
        assertTrue(src.contains("WD_FOREIGN_GROUP on grp="))
        assertTrue(src.contains("WD_FOREIGN_GROUP off grp="))
        assertTrue(src.contains("\"foreign\" to foreign"))
    }

    @Test fun `224-A4 decode - a foreign group from a 223 phone can't be joined`() {
        val txt = mapOf("v" to "1", "id" to "0123456789abcdef", "host" to "1", "m" to "0", "n" to "1",
            "g" to "DIRECT-44-realme C71", "k" to key)
        val tag = NearbyTagPolicy.decode("x._locallink._tcp.local.", txt, "aa:bb:cc:dd:ee:ff", 1L)!!
        assertEquals("the phone is still seen", "0123456789abcdef", tag["id"])
        assertNull(tag["group"]); assertNull(tag["key"])
    }

    @Test fun `224-A4 decode - DIRECT-LL- and lg=1 groups are kept`() {
        val ll = mapOf("v" to "1", "id" to "0123456789abcdef", "host" to "1", "g" to "DIRECT-LL-abc123", "k" to key)
        val t1 = NearbyTagPolicy.decode(null, ll, "aa:bb:cc:dd:ee:ff", 1L)!!
        assertEquals("DIRECT-LL-abc123", t1["group"]); assertEquals(key, t1["key"])
        val lg = mapOf("v" to "1", "id" to "0123456789abcdef", "host" to "1", "g" to "DIRECT-xy-J5", "k" to key, "lg" to "1")
        val t2 = NearbyTagPolicy.decode(null, lg, "aa:bb:cc:dd:ee:ff", 1L)!!
        assertEquals("DIRECT-xy-J5", t2["group"]); assertEquals(key, t2["key"])
    }

    @Test fun `224-A D1 - never close or leave a foreign group`() {
        val src = File("main/kotlin/com/sajjad/locallink/NearbyRadio.kt").readText()
        assertTrue(src.contains("WD_FOREIGN_GROUP keep why=disconnect"))
        assertTrue(src.contains("WD_FOREIGN_GROUP keep why=join"))
        val join = src.substringAfter("private fun joinNearbyGroup(")
        assertTrue("checked before the leave", join.indexOf("keep why=join") < join.indexOf("group leave before join"))
    }
}
