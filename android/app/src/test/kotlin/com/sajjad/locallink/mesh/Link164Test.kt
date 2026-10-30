package com.sajjad.locallink.mesh

import com.sajjad.locallink.VideoFramePolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Link164Test {
    @Test
    fun `a blocked contact is refused, an unblocked contact still connects`() {
        assertNull(MeshRelayPolicy.trustFor("bilal", isContact = true, isBlocked = true, peerOffersRelay = true, relayLinks = 0))
        assertEquals(MeshRelayPolicy.TRUST_CONTACT, MeshRelayPolicy.trustFor("bilal", isContact = true, isBlocked = false, peerOffersRelay = false, relayLinks = 0))
    }

    @Test
    fun `strict mode refuses only unchecked contact links`() {
        val legacy = MeshLinkAuth.decide(haveKeys = true, peerOffers = false, matched = false, macOk = false, verifiedBefore = false)
        assertEquals(MeshLinkAuth.Verdict.LEGACY, legacy.verdict)
        val strict = MeshLinkAuth.applyStrict(legacy, strict = true, isContact = true)
        assertEquals(MeshLinkAuth.Verdict.REJECT, strict.verdict)
        assertEquals("strict_unchecked", strict.reason)
        // No key yet for that contact: also unchecked.
        val noKey = MeshLinkAuth.decide(haveKeys = false, peerOffers = true, matched = false, macOk = false, verifiedBefore = false)
        assertEquals(MeshLinkAuth.Verdict.REJECT, MeshLinkAuth.applyStrict(noKey, strict = true, isContact = true).verdict)
        // Off = unchanged.
        assertEquals(legacy, MeshLinkAuth.applyStrict(legacy, strict = false, isContact = true))
        // Strangers (relay links) are never id-checked: unchanged.
        assertEquals(MeshLinkAuth.Verdict.LEGACY, MeshLinkAuth.applyStrict(noKey, strict = true, isContact = false).verdict)
        // A checked contact passes.
        val ok = MeshLinkAuth.decide(haveKeys = true, peerOffers = true, matched = true, macOk = true, verifiedBefore = false)
        assertEquals(MeshLinkAuth.Verdict.VERIFIED, MeshLinkAuth.applyStrict(ok, strict = true, isContact = true).verdict)
    }

    @Test
    fun `video frame - black detection and retry times`() {
        assertTrue(VideoFramePolicy.isMostlyDark(IntArray(81) { 5 }))
        assertTrue(VideoFramePolicy.isMostlyDark(IntArray(0)))
        assertFalse(VideoFramePolicy.isMostlyDark(IntArray(81) { if (it < 10) 200 else 0 }))
        assertEquals(255, VideoFramePolicy.luma(0xFFFFFFFF.toInt()))
        assertEquals(0, VideoFramePolicy.luma(0xFF000000.toInt()))
        assertEquals(listOf(1_000_000L, 2_500_000L), VideoFramePolicy.retryTimesUs(10_000))
        // Very short video: only a quarter in (1 s is past the end).
        assertEquals(listOf(200_000L), VideoFramePolicy.retryTimesUs(800))
        // Unknown length: try 1 s.
        assertEquals(listOf(1_000_000L), VideoFramePolicy.retryTimesUs(0))
    }
}
