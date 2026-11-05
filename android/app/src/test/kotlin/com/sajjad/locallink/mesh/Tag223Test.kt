package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 223 (F): Wi-Fi Direct name tags + the exact TXT ask. */
class Tag223Test {
    private val main = File("main/kotlin/com/sajjad/locallink")
    private val id = "1a2b3c4d5e6f7a8b"

    @Test fun `223-16 name tag encodes and decodes`() {
        assertEquals("LinkUp-1a2b3c4d-n", NearbyTagPolicy.encodeName(id, false, false, false))
        assertEquals("LinkUp-1a2b3c4d-hw", NearbyTagPolicy.encodeName(id, true, true, true))
        assertEquals("LinkUp-1a2b3c4d-m", NearbyTagPolicy.encodeName(id, false, true, false))
        val name = NearbyTagPolicy.encodeName(id, true, false, true)
        assertTrue(name.length < 63)
        val t = NearbyTagPolicy.decodeName(name, "AA:BB:CC:DD:EE:FF", 5L)
        assertNotNull(t)
        assertEquals("aa:bb:cc:dd:ee:ff", t!!["address"])
        assertEquals("1a2b3c4d", t["id"])
        assertEquals(true, t["host"])
        assertEquals(false, t["member"])
        assertEquals(true, t["wants_link"])
        assertEquals(true, t["from_name"])
        assertEquals(5L, t["seen_at"])
        assertFalse("no group from a name", t.containsKey("group"))
        assertFalse("no password from a name", t.containsKey("key"))
        // The id passes the Dart / Kotlin tag id check (8..32 hex).
        assertTrue(NearbyTagPolicy.validId(t["id"] as String))
    }

    @Test fun `223-16 bad names give null`() {
        for (bad in listOf(null, "", "LinkUp-", "LinkUp-1a2b3c4d", "LinkUp-1A2B3C4D-h", "LinkUp-1a2b3c4-h",
            "LinkUp-1a2b3c4d-x", "LinkUp-1a2b3c4d-hh", "LinkUp-1a2b3c4d-hm", "LinkUp-1a2b3c4d-nw", "Other-1a2b3c4d-h")) {
            assertNull(bad, NearbyTagPolicy.decodeName(bad, "aa:bb", 1L))
        }
        assertNull(NearbyTagPolicy.decodeName("LinkUp-1a2b3c4d-h", null, 1L))
        assertNull(NearbyTagPolicy.decodeName("LinkUp-1a2b3c4d-h", " ", 1L))
    }

    @Test fun `223-17 an old phone's plain name is still a LinkUp service`() {
        assertTrue(NearbyTagPolicy.isOldName(NearbyTagPolicy.INSTANCE_NAME))
        assertTrue(NearbyTagPolicy.isLinkUpName(NearbyTagPolicy.INSTANCE_NAME))
        assertTrue(NearbyTagPolicy.isLinkUpName("LinkUp-1a2b3c4d-n"))
        assertFalse(NearbyTagPolicy.isLinkUpName("SomePrinter"))
        assertNull("no tag from the old name", NearbyTagPolicy.decodeName(NearbyTagPolicy.INSTANCE_NAME, "aa:bb", 1L))
        // The TXT tag format and the service type are unchanged.
        assertEquals("_locallink._tcp", NearbyTagPolicy.SERVICE_TYPE)
        val txt = NearbyTagPolicy.encode(id, host = true, member = false, members = 2)
        val full = NearbyTagPolicy.decode("x._locallink._tcp.local.", txt, "aa:bb", 1L)
        assertEquals(id, full!!["id"])
        assertFalse(full.containsKey("from_name"))
    }

    @Test fun `223-18b a full tag wins and name tags refresh every 30 s`() {
        val now = 1_000_000L
        val name = NearbyTagPolicy.decodeName("LinkUp-1a2b3c4d-n", "aa:bb", now)!!
        assertTrue(NearbyTagPolicy.nameShouldEmit(null, name, now))
        val full = NearbyTagPolicy.decode(null, NearbyTagPolicy.encode(id, false, false, 0), "aa:bb", now)!!
        assertFalse("fresh full tag wins", NearbyTagPolicy.nameShouldEmit(full, name, now + 1_000))
        assertTrue("stale full tag is replaced",
            NearbyTagPolicy.nameShouldEmit(full, name, now + NearbyTagPolicy.TAG_MAX_AGE_MS + 1))
        assertFalse("same name tag soon after", NearbyTagPolicy.nameShouldEmit(name, name, now + 5_000))
        assertTrue("again after 30 s", NearbyTagPolicy.nameShouldEmit(name, name, now + NearbyTagPolicy.NAME_REEMIT_MS))
        val host = NearbyTagPolicy.decodeName("LinkUp-1a2b3c4d-h", "aa:bb", now + 5_000)!!
        assertTrue("changed flags at once", NearbyTagPolicy.nameShouldEmit(name, host, now + 5_000))
        assertTrue(NearbyTagPolicy.tagIsStale(name, now + NearbyTagPolicy.TAG_MAX_AGE_MS + 1))
        assertFalse(NearbyTagPolicy.tagIsStale(name, now + 1))
    }

    @Test fun `223-18 source a PTR without TXT leads to one exact TXT request`() {
        val s = File(main, "NearbyTagManager.kt").readText()
        assertEquals(2_000L, NearbyTagPolicy.TXT_ASK_AFTER_MS)
        assertTrue(s.contains("main.postDelayed({ askTxt(seq, name, addr) }, NearbyTagPolicy.TXT_ASK_AFTER_MS)"))
        assertTrue(s.contains("if (address in txtFrom || !txtAsked.add(address)) return"))
        assertTrue(s.contains("WifiP2pDnsSdServiceRequest.newInstance(instanceName, NearbyTagPolicy.SERVICE_TYPE)"))
        assertTrue(s.contains("WD_TAG txt_ask from="))
        assertTrue(s.contains("address?.trim()?.lowercase()?.let { txtFrom.add(it) }"))
        // Asked sets are per window.
        assertTrue(s.contains("txtFrom.clear()") && s.contains("txtAsked.clear()"))
        // Published name carries the tag; the type stays.
        assertTrue(s.contains("val name = NearbyTagPolicy.encodeName(id, host, member, wanted.isNotEmpty())"))
        assertTrue(s.contains("name, NearbyTagPolicy.SERVICE_TYPE, txt)"))
        assertTrue(s.contains("WD_TAG from_name id="))
        // Name tags never count as "heard" (the deaf-window backup must still run).
        assertTrue(s.contains("heard=\$windowHeard linkup=\$windowLinkUp names=\$windowNames"))
        assertFalse(Regex("windowHeard \\+= 1[^\\n]*\\n[^\\n]*from_name").containsMatchIn(s))
        // Q16: one stale rule for both kinds.
        assertEquals(2, Regex("dropStale\\(now\\)").findAll(s).count())
    }
}
