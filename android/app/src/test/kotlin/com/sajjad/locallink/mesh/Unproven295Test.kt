package com.sajjad.locallink.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 295 (G1): the way a call proved dead is not taken back for 15 s. */
class Unproven295Test {
    private val friend = "android-c891ac8ded16a834"
    private val ayesha = "android-9e62fd63d5d181c0"
    private val tecno = "android-a8fe80749654237e"

    @Test
    fun sameNextHopIsHeld15sOthersAreNot() {
        val u = MeshUnproven295()
        u.hold(friend, listOf(ayesha), 1_000L)
        assertTrue(u.blocks(friend, ayesha, 1_000L))
        assertTrue(u.blocks(friend, ayesha, 15_999L))
        assertFalse("another phone may bring a way", u.blocks(friend, tecno, 2_000L))
        assertFalse("other friends are not touched", u.blocks(tecno, ayesha, 2_000L))
        assertFalse("15 s later the advert counts again", u.blocks(friend, ayesha, 16_000L))
        assertFalse(u.isHeld(friend, 16_000L))
    }

    @Test
    fun proofFromTheFriendEndsTheHold() {
        val u = MeshUnproven295()
        u.hold(friend, listOf(ayesha, tecno), 0L)
        assertTrue(u.isHeld(friend, 1L))
        assertTrue(u.proven(friend))
        assertFalse(u.blocks(friend, ayesha, 1L))
        assertFalse(u.blocks(friend, tecno, 1L))
        assertFalse("nothing to clear twice", u.proven(friend))
    }

    @Test
    fun nothingHeldForEmptyOrSelfHop() {
        val u = MeshUnproven295()
        u.hold(friend, emptyList(), 0L)
        u.hold(friend, listOf(friend), 0L)
        assertFalse(u.isHeld(friend, 1L))
        assertFalse(u.blocks(friend, friend, 1L))
    }

    @Test
    fun serviceUsesTheHoldForAdvertsAnswersAndProof() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(src.contains("if (unproven295.blocks(destination, peerId, now)) continue"))
        assertTrue(src.contains("if (unproven295.blocks(target, peerId, now)) {"))
        assertTrue(src.contains("if (unproven295.proven(packet.sourceNodeId))"))
        assertTrue(src.contains("if (unproven295.proven(connection.peerId))"))
        assertTrue("a direct link is kept", src.contains("Log.i(\"ROUTES\", \"unproven dest=\${destination.take(8)} kept=direct\")"))
    }
}
