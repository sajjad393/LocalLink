package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Locks the active-link ordering used for LAN -> Wi-Fi Direct switching. */
class MeshLinkSelectionPolicyTest {

    private data class C(val name: String, val seen: Long)

    private fun pick(links: List<C>): C? =
        MeshLinkSelectionPolicy.selectActive(links, { it.name }, { it.seen })

    @Test
    fun lanAlwaysWinsOverWifiDirectRegardlessOfRecency() {
        // A very fresh Wi-Fi Direct link must NOT displace an older LAN link.
        val lan = C("lan", 1_000L)
        val wfd = C("wifi_direct", 999_000_000L)
        assertEquals("lan", pick(listOf(lan, wfd))!!.name)
        assertEquals("lan", pick(listOf(wfd, lan))!!.name)
    }

    @Test
    fun withinSameTransportNewestLinkWins() {
        val stale = C("wifi_direct", 1_000L)
        val fresh = C("wifi_direct", 2_000L)
        assertEquals(2_000L, pick(listOf(stale, fresh))!!.seen)
    }

    @Test
    fun fullTieBreaksByTransportNameForStability() {
        val a = (0..99).map { pick(listOf(C("lan", 5), C("wifi_direct", 5))) }
        assertTrue(a.all { it!!.name == "lan" }) // lan > wifi_direct by priority
        val b = pick(listOf(C("lan", 5)))
        assertEquals("lan", b!!.name)
    }

    @Test
    fun emptyCandidateSetRetriesNothing() {
        assertNull(pick(emptyList()))
    }

    @Test
    fun selectionIsDeterministicAcrossInputOrderings() {
        val links = listOf(
            C("wifi_direct", 100L),
            C("lan", 90L),
            C("wifi_direct", 200L),
        )
        val winner = pick(links)!!
        for (permutation in listOf(links, links.reversed(), links.shuffled(links))) {
            val selected = pick(permutation)
            assertEquals(winner.name, selected!!.name)
            assertEquals(winner.seen, selected.seen)
        }
        assertEquals("lan", winner.name) // LAN priority beats fresher WFD
    }

    @Test
    fun unknownTransportRanksBelowKnownOnes() {
        // isSupportedTransport gates registration upstream; if an unknown
        // name ever shows up in a set of live links it must not win.
        val unknown = C("bluetooth", 9_999_999L)
        val wfd = C("wifi_direct", 1L)
        assertEquals("wifi_direct", pick(listOf(unknown, wfd))!!.name)
    }

    private fun <T> List<T>.shuffled(seedList: List<T>): List<T> = drop(1) + take(1)
}
