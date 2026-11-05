package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshBlockPolicy
import com.sajjad.locallink.mesh.MeshOneStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 214: admin crown cards go one step (also past blocked phones). */
class Admin214Test {
    @Test
    fun `frame names match the app`() {
        assertEquals("admin_badge_digest", MeshOneStep.ADMIN_BADGE_DIGEST)
        assertEquals("admin_badge_records", MeshOneStep.ADMIN_BADGE_RECORDS)
    }

    @Test
    fun `badge frames are one step and pass a blocked phone`() {
        for (t in listOf("admin_badge_digest", "admin_badge_records")) {
            assertTrue(MeshOneStep.isOneStep(t))
            assertTrue(MeshOneStep.isAdminBadge(t))
            assertTrue(MeshOneStep.isOneStepIn(t, "ali", "me", "ali", "me"))
            assertFalse(MeshOneStep.isOneStepIn(t, "ali", "me", "bilal", "me"))
            assertTrue(MeshOneStep.canSendOneStep(t, "me", "ali", "ali", "me"))
            assertFalse(MeshBlockPolicy.dropAtFirstHop(t, "ali", "me", setOf("ali")))
        }
        assertFalse(MeshOneStep.isOneStep("admin_badge_other"))
        assertTrue(MeshBlockPolicy.dropAtFirstHop("direct_message", "ali", "me", setOf("ali")))
    }
}
