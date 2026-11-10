package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Bundle 257: friends locked out of Wi-Fi Direct / Local Wi-Fi.
 * 10 Nov logs: 1352 `LINK_AUTH reject reason=auth_required` in 1 h on the
 * TECNO, 141 on the Note - a friend that passed once and had no shared key
 * any more (reinstall, new keys, account moved) was refused for good.
 */
class Link257Test {
    private fun key(own: String, peer: String, hex: String = "11") =
        MeshLinkAuth.parse(own, peer, hex.repeat(32))!!

    @Test fun `257-A1 passed before + no shared key = the old way (rekey), not refused`() {
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.LEGACY, "rekey"), MeshLinkAuth.decide(true, false, false, false, true))
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.LEGACY, "rekey"), MeshLinkAuth.decide(true, true, false, false, true))
    }

    @Test fun `257-A1 a wrong MAC with a matching key is still refused`() {
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.REJECT, "bad_mac"), MeshLinkAuth.decide(true, true, true, false, true))
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.REJECT, "bad_mac"), MeshLinkAuth.decide(true, true, true, false, false))
        assertEquals(MeshLinkAuth.Verdict.VERIFIED, MeshLinkAuth.decide(true, true, true, true, true).verdict)
    }

    @Test fun `257-A1 strict mode still refuses a rekey contact link`() {
        val d = MeshLinkAuth.decide(true, true, false, false, true)
        assertEquals(MeshLinkAuth.Decision(MeshLinkAuth.Verdict.REJECT, "strict_unchecked"), MeshLinkAuth.applyStrict(d, true, true))
        assertEquals(d, MeshLinkAuth.applyStrict(d, false, true))
        assertEquals(d, MeshLinkAuth.applyStrict(d, true, false))
    }

    @Test fun `257-A2 changed or gone keys are found, same keys are not`() {
        val a1 = key("AAAAAAAAAAA", "BBBBBBBBBBB")
        val a2 = key("AAAAAAAAAAA", "CCCCCCCCCCC")
        val b1 = key("AAAAAAAAAAA", "DDDDDDDDDDD")
        val old = mapOf("alice" to listOf(a1), "bob" to listOf(b1), "carol" to listOf(a1))
        val new = mapOf("alice" to listOf(a2), "bob" to listOf(key("AAAAAAAAAAA", "DDDDDDDDDDD", "22")), "dave" to listOf(a1))
        // alice: other key id; carol: gone; bob: same offer (key ids) = unchanged; dave: new (nothing to drop).
        assertEquals(setOf("alice", "carol"), MeshLinkAuth.changedPeers(old, new))
        assertTrue(MeshLinkAuth.changedPeers(emptyMap(), new).isEmpty())
        assertTrue(MeshLinkAuth.changedPeers(old, old).isEmpty())
    }

    @Test fun `257-A2 A4 A5 service wiring (source)`() {
        val src = File("main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt").readText()
        assertTrue(src.contains("resetVerifiedFor257(MeshLinkAuth.changedPeers(HashMap(linkKeys), parsed), parsed)"))
        assertTrue(src.contains("\"verified_reset peer=\${peer.takeLast(8)} why=\$why\""))
        // A4: refused links count as quick drops.
        assertTrue(src.contains("if (transportName != MeshTransportPolicy.LAN) noteLinkEnded(peerId, 0L)"))
        assertTrue(src.contains("// (answering stays allowed - Bundle 224).\n            noteLinkEnded(peer, 0L)"))
        // A5: no LINK_AUTH line prints the start of the id any more.
        assertFalse(Regex("\"LINK_AUTH\",\\s*\"[^\"]*peer=\\$\\{[a-zA-Z.]+\\.take\\(8\\)\\}").containsMatchIn(src))
        assertTrue(src.contains("\"reject peer=\${peer.takeLast(8)} side=\$side reason=\${decision.reason}\""))
    }
}
