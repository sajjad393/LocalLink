package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshBlockPolicy
import com.sajjad.locallink.mesh.MeshOneStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 220: admin action cards go one step on every link (also strangers and blocked phones). */
class Admin220Test {
    @Test
    fun `frame names match the app`() {
        assertEquals("admin_act_digest", MeshOneStep.ADMIN_ACT_DIGEST)
        assertEquals("admin_act_cards", MeshOneStep.ADMIN_ACT_CARDS)
        assertEquals("admin_act_done", MeshOneStep.ADMIN_ACT_DONE)
    }

    @Test
    fun `action frames are one step and pass a blocked phone`() {
        for (t in listOf("admin_act_digest", "admin_act_cards", "admin_act_done")) {
            assertTrue(MeshOneStep.isOneStep(t))
            assertTrue(MeshOneStep.isAdminAction(t))
            assertTrue(MeshOneStep.isOneStepIn(t, "ali", "me", "ali", "me"))
            assertFalse(MeshOneStep.isOneStepIn(t, "ali", "me", "bilal", "me"))
            assertTrue(MeshOneStep.canSendOneStep(t, "me", "ali", "ali", "me"))
            assertFalse(MeshBlockPolicy.dropAtFirstHop(t, "ali", "me", setOf("ali")))
        }
        assertFalse(MeshOneStep.isOneStep("admin_act_other"))
        assertFalse(MeshOneStep.isAdminAction("admin_badge_digest"))
    }
}
