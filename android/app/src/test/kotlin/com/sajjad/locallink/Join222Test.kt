package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshBlockPolicy
import com.sajjad.locallink.mesh.MeshOneStep
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 222: the account_join frame goes one step, like the 220/221 frames. */
class Join222Test {
    @Test
    fun accountJoinIsOneStep() {
        assertTrue(MeshOneStep.isOneStep("account_join"))
        assertTrue(MeshOneStep.isAccountJoin(MeshOneStep.ACCOUNT_JOIN))
        assertFalse(MeshOneStep.isAccountJoin("account_join_other"))
        assertFalse(MeshOneStep.isOneStep("account_join_other"))
    }

    @Test
    fun notDroppedForBlockedPeople() {
        assertFalse(MeshBlockPolicy.dropAtFirstHop("account_join", "a", "b", setOf("a", "b")))
    }

    @Test
    fun onlyStraightToTheLinkedPhone() {
        assertTrue(MeshOneStep.canSendOneStep("account_join", "me", "peer", "peer", "me"))
        assertFalse(MeshOneStep.canSendOneStep("account_join", "me", "other", "peer", "me"))
    }
}
