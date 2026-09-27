package com.sajjad.locallink.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshFinalRecipientPolicyTest {
    @Test
    fun onlyFinalNodeCanConsumePacketLocally() {
        assertFalse(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "B", "B"))
        assertFalse(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "C", "C"))
        assertTrue(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "D", "D"))
        assertTrue(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", null, "D"))
    }

    @Test
    fun relayCannotMasqueradeAsFinalRecipient() {
        assertFalse(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "C", "B"))
        assertFalse(MeshFinalRecipientPolicy.isFinalRecipient("A", "D", "B", "D"))
        assertFalse(MeshFinalRecipientPolicy.isFinalRecipient("A", "A", null, "A"))
    }
}
