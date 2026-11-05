package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshBlockPolicy
import com.sajjad.locallink.mesh.MeshOneStep
import com.sajjad.locallink.mesh.MeshRelayPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 212: blocked phones stay mesh nodes; admin block frames go one step. */
class Block212Test {
    @Test
    fun `frame names match the app`() {
        assertEquals("admin_block_digest", MeshOneStep.ADMIN_BLOCK_DIGEST)
        assertEquals("admin_block_records", MeshOneStep.ADMIN_BLOCK_RECORDS)
        assertEquals("admin_block_got", MeshOneStep.ADMIN_BLOCK_GOT)
    }

    @Test
    fun `one-step types include names and admin frames only`() {
        assertTrue(MeshOneStep.isOneStep(MeshRelayPolicy.NAME_QUESTION))
        assertTrue(MeshOneStep.isOneStep(MeshRelayPolicy.NAME_ANSWER))
        assertTrue(MeshOneStep.isOneStep("admin_block_records"))
        assertFalse(MeshOneStep.isOneStep("direct_message"))
        assertFalse(MeshOneStep.isOneStep(MeshRelayPolicy.SEALED))
        assertFalse(MeshOneStep.isOneStep(null))
        assertTrue(MeshOneStep.isOneStepIn("admin_block_digest", "bilal", "me", "bilal", "me"))
        assertFalse(MeshOneStep.isOneStepIn("admin_block_digest", "safeer", "me", "bilal", "me"))
        assertFalse(MeshOneStep.isOneStepIn("admin_block_digest", "bilal", "other", "bilal", "me"))
        assertTrue(MeshOneStep.canSendOneStep("admin_block_got", "me", "bilal", "bilal", "me"))
        assertFalse(MeshOneStep.canSendOneStep("admin_block_got", "me", "safeer", "bilal", "me"))
    }

    @Test
    fun `blocked peer gets a relay link, never a contact link`() {
        assertEquals(MeshRelayPolicy.TRUST_RELAY,
            MeshBlockPolicy.trust("ali", isContact = true, isBlocked = true, peerOffersRelay = true, relayLinks = 0))
        assertEquals(MeshRelayPolicy.TRUST_RELAY,
            MeshBlockPolicy.trust("ali", isContact = false, isBlocked = true, peerOffersRelay = true, relayLinks = 0))
        assertNull(MeshBlockPolicy.trust("ali", isContact = true, isBlocked = true, peerOffersRelay = true, relayLinks = 0, isPaused = true))
        assertNull(MeshBlockPolicy.trust("ali", isContact = true, isBlocked = true, peerOffersRelay = false, relayLinks = 0))
        assertEquals(MeshRelayPolicy.TRUST_CONTACT,
            MeshBlockPolicy.trust("bilal", isContact = true, isBlocked = false, peerOffersRelay = false, relayLinks = 0))
        // The old rule is not changed (Link164Test / MeshRelayPolicyTest).
        assertNull(MeshRelayPolicy.trustFor("ali", isContact = true, isBlocked = true, peerOffersRelay = true, relayLinks = 0))
    }

    @Test
    fun `only contact links to a blocked peer are closed`() {
        assertTrue(MeshBlockPolicy.closeLink(MeshRelayPolicy.TRUST_CONTACT, true))
        assertFalse(MeshBlockPolicy.closeLink(MeshRelayPolicy.TRUST_RELAY, true))
        assertFalse(MeshBlockPolicy.closeLink(MeshRelayPolicy.TRUST_CONTACT, false))
    }

    @Test
    fun `first hop drops packets from or to a blocked person`() {
        val blocked = setOf("ali")
        assertTrue(MeshBlockPolicy.dropAtFirstHop(MeshRelayPolicy.SEALED, "ali", "zte", blocked))
        assertTrue(MeshBlockPolicy.dropAtFirstHop(MeshRelayPolicy.SEALED, "realme", "ali", blocked))
        assertFalse(MeshBlockPolicy.dropAtFirstHop(MeshRelayPolicy.SEALED, "realme", "zte", blocked))
        assertFalse(MeshBlockPolicy.dropAtFirstHop("admin_block_records", "ali", "me", blocked))
        assertFalse(MeshBlockPolicy.dropAtFirstHop(MeshRelayPolicy.SEALED, "ali", "zte", emptySet()))
    }

    @Test
    fun `blocked next hop carries sealed packets only`() {
        assertTrue(MeshBlockPolicy.canUseNextHop(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED, false))
        assertFalse(MeshBlockPolicy.canUseNextHop(MeshRelayPolicy.TRUST_RELAY, "direct_message", false))
        assertTrue(MeshBlockPolicy.canUseNextHop(MeshRelayPolicy.TRUST_RELAY, "admin_block_records", true))
    }

    @Test
    fun `service uses the 212 rules`() {
        val name = "LocalLinkTransportService.kt"
        val s = listOf("main/kotlin/com/sajjad/locallink/$name", "src/main/kotlin/com/sajjad/locallink/$name",
            "app/src/main/kotlin/com/sajjad/locallink/$name", "android/app/src/main/kotlin/com/sajjad/locallink/$name")
            .map { File(it) }.first { it.exists() }.readText()
        assertTrue(s.contains("MeshBlockPolicy.trust("))
        assertTrue(s.contains("MeshBlockPolicy.dropAtFirstHop("))
        assertTrue(s.contains("MeshOneStep.isOneStep(p.optString(\"type\"))"))
        assertFalse(s.contains("exitCause = \"relay_blocked\""))
    }
}
