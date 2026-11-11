package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 260 (A6): a leftover LinkUp group is closed once at start. */
class Group260Test {
    @Test
    fun onlyOurOwnHostedNearbyGroupCloses() {
        assertTrue(LeftoverGroupPolicy.shouldClose(true, true, "DIRECT-LL-bMieHf"))
        assertFalse(LeftoverGroupPolicy.shouldClose(true, false, "DIRECT-LL-bMieHf"))
        assertFalse(LeftoverGroupPolicy.shouldClose(false, true, "DIRECT-LL-bMieHf"))
        assertFalse(LeftoverGroupPolicy.shouldClose(true, true, "DIRECT-xy-RealmeShare"))
        assertFalse(LeftoverGroupPolicy.shouldClose(true, true, null))
        assertFalse(LeftoverGroupPolicy.shouldClose(true, true, ""))
    }

    @Test
    fun logLine() {
        assertEquals(
            "NEARBY group leftover_closed grp=DIRECT-LL-bMieHf members=2",
            LeftoverGroupPolicy.line("DIRECT-LL-bMieHf", 2, true),
        )
        assertEquals(
            "NEARBY group leftover_closed grp=- members=0 ok=n",
            LeftoverGroupPolicy.line(null, 0, false),
        )
    }

    @Test
    fun radioChecksOnceAndKeepsForeignGroups() {
        val src = File("main/kotlin/com/sajjad/locallink/NearbyRadio.kt").readText()
        assertTrue(src.contains("@Volatile private var leftoverChecked = false"))
        assertTrue(src.contains("closeLeftoverGroup(a, m, ch) // Bundle 260 (A6)"))
        val body = src.substringAfter("private fun closeLeftoverGroup").substringBefore("private fun reinit")
        assertTrue(body.contains("if (leftoverChecked) return"))
        assertTrue(body.contains("tags?.foreign == true"))
        assertTrue(body.contains("LeftoverGroupPolicy.shouldClose(true, g.isGroupOwner, name)"))
        assertTrue(body.contains("m.removeGroup(ch"))
    }
}
