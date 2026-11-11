package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 262: (A) Wi-Fi Direct groups on 2.4 GHz, (B1) the off/on line,
 *  (B3) the stuck-busy channel reset. */
class Band262Test {
    private val main = File("main/kotlin/com/sajjad/locallink")
    private val radio get() = File(main, "NearbyRadio.kt").readText()

    @Test fun `2_4 GHz from Android 10 and the same value as Android`() {
        assertTrue(GroupBand262.wants(29))
        assertTrue(GroupBand262.wants(35))
        assertFalse(GroupBand262.wants(28))
        assertEquals(android.net.wifi.p2p.WifiP2pConfig.GROUP_OWNER_BAND_2GHZ, GroupBand262.BAND_2GHZ)
        assertEquals(android.net.wifi.p2p.WifiP2pManager.BUSY, GroupBand262.REASON_BUSY)
    }

    @Test fun `a refused band gets one try without it, busy does not`() {
        assertTrue(GroupBand262.mayRetry(true, 0))
        assertTrue(GroupBand262.mayRetry(true, 1))
        assertFalse(GroupBand262.mayRetry(true, 2))
        assertFalse(GroupBand262.mayRetry(false, 0))
        assertEquals("group create grp=DIRECT-ab band=2.4", GroupBand262.createLine("DIRECT-ab", true))
        assertEquals("group create retry no_band reason=0", GroupBand262.retryLine("group create", 0))
    }

    @Test fun `both group builders ask for 2_4 GHz, the password is never logged`() {
        val r = radio
        val fn = r.substringAfter("private fun createGroup262(").substringBefore("// Bundle 200 (B): `go`")
        assertTrue(fn.contains("setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_2GHZ)"))
        assertTrue(fn.contains("GroupBand262.mayRetry(withBand, reason)"))
        assertTrue(fn.contains("m.createGroup(ch, config(false), done)"))
        assertFalse(fn.contains("\$pass"))
        val shared = r.substringAfter("private fun createNearbyGroup(").substringBefore("private fun createFriendGroup(")
        assertTrue(shared.contains("createGroup262(m, ch, name, NearbyGroupPolicy.newPassphrase(), \"group create\", listener)"))
        val friend = r.substringAfter("private fun createFriendGroup(").substringBefore("private fun joinNearbyGroup(")
        assertTrue(friend.contains("createGroup262(m, ch, name!!, key!!, \"WD_FRIEND_OPEN\", listener)"))
        // Only the band helper builds a group config now (joins are unchanged).
        assertEquals(0, Regex("val config = WifiP2pConfig.Builder\\(\\)").findAll(r).count())
        // The join guard count of bundle 189 is unchanged.
        assertEquals(5, Regex("lastGroupChangeAt = System.currentTimeMillis\\(\\)").findAll(r).count())
    }

    @Test fun `off and on lines`() {
        assertNull(P2pState262.line(null, true, 0L, 1000L))
        assertEquals("WD_P2P state=off first=1", P2pState262.line(null, false, 0L, 1000L))
        assertNull(P2pState262.line(true, true, 0L, 1000L))
        assertEquals("WD_P2P state=off", P2pState262.line(true, false, 0L, 1000L))
        assertEquals("WD_P2P state=on off_s=42", P2pState262.line(false, true, 1_000L, 43_000L))
        assertEquals("WD_P2P state=on off_s=-1", P2pState262.line(false, true, 0L, 43_000L))
        val r = radio
        assertTrue(r.contains("P2pState262.line(lastP2p262, p2pEnabled, p2pOffAt262, nowMs)"))
        // An engine that attaches hears the state again.
        val attach = r.substringAfter("fun attach(events").substringBefore("fun detach(")
        assertTrue(attach.contains("emit(mapOf(\"type\" to \"state\", \"enabled\" to it))"))
    }

    @Test fun `three busy answers in 90 s while on`() {
        val t = ArrayList<Long>()
        assertFalse(Busy262.add(t, 0L, true))
        assertFalse(Busy262.add(t, 20_000L, true))
        assertTrue(Busy262.add(t, 40_000L, true))
        t.clear()
        assertFalse(Busy262.add(t, 0L, true))
        assertFalse(Busy262.add(t, 50_000L, true))
        assertFalse(Busy262.add(t, 100_000L, true)) // the first is too old
        assertTrue(Busy262.add(t, 120_000L, true))
        assertFalse(Busy262.add(t, 130_000L, false)) // off: busy is normal
        assertTrue(t.isEmpty())
        val r = radio
        val fn = r.substringAfter("private fun noteBusy262(").substringBefore("/** Bundle 262 (A)")
        assertTrue(fn.contains("NearbyBackgroundPolicy.mayReinit(n)"))
        assertTrue(fn.contains("reinit(it)"))
        assertTrue(r.contains("Log.w(TAG, \"group join failed reason=\$reason\"); noteBusy262(reason)"))
    }
}
