package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshRelayPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 195c: the name question / answer goes one step only. */
class Name195Test {
    private val q = MeshRelayPolicy.NAME_QUESTION
    private val a = MeshRelayPolicy.NAME_ANSWER

    @Test
    fun `type names match the app`() {
        assertEquals("DIRECTORY_NAME_QUESTION", q)
        assertEquals("DIRECTORY_NAME_ANSWER", a)
        assertTrue(MeshRelayPolicy.isNameQuestion(q))
        assertTrue(MeshRelayPolicy.isNameQuestion(a))
        assertFalse(MeshRelayPolicy.isNameQuestion("DIRECTORY_SYNC_REQUEST"))
        assertFalse(MeshRelayPolicy.isNameQuestion(null))
    }

    @Test
    fun `received - only straight from the linked phone and for me`() {
        assertTrue(MeshRelayPolicy.isOneStepName(q, "bilal", "me", "bilal", "me"))
        // passed on by someone else
        assertFalse(MeshRelayPolicy.isOneStepName(q, "safeer", "me", "bilal", "me"))
        // for another phone (would be passed on)
        assertFalse(MeshRelayPolicy.isOneStepName(a, "bilal", "safeer", "bilal", "me"))
        assertFalse(MeshRelayPolicy.isOneStepName(q, "bilal", "", "bilal", ""))
        assertFalse(MeshRelayPolicy.isOneStepName("direct_message", "bilal", "me", "bilal", "me"))
    }

    @Test
    fun `sent - only from me to the phone on this link`() {
        assertTrue(MeshRelayPolicy.canSendOneStepName(a, "me", "bilal", "bilal", "me"))
        assertFalse(MeshRelayPolicy.canSendOneStepName(a, "me", "safeer", "bilal", "me"))
        assertFalse(MeshRelayPolicy.canSendOneStepName(a, "safeer", "bilal", "bilal", "me"))
        assertFalse(MeshRelayPolicy.canSendOneStepName("direct_message", "me", "bilal", "bilal", "me"))
    }

    @Test
    fun `relay links still refuse other plain packets`() {
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "direct_message"))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "CONTACT_EDGE"))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, q)) // only via the one-step rule
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED))
    }
}
