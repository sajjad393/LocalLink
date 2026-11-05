package com.sajjad.locallink

import com.sajjad.locallink.mesh.MeshBlockPolicy
import com.sajjad.locallink.mesh.MeshOneStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 213: version rule + "get the new LinkUp" frames go one step. */
class Version213Test {
    @Test
    fun `frame names match the app`() {
        assertEquals("version_digest", MeshOneStep.VERSION_DIGEST)
        assertEquals("version_rule", MeshOneStep.VERSION_RULE)
        assertEquals("app_update_request", MeshOneStep.APP_UPDATE_REQUEST)
        assertEquals("app_update_answer", MeshOneStep.APP_UPDATE_ANSWER)
        assertEquals("app_update_offer", MeshOneStep.APP_UPDATE_OFFER)
    }

    @Test
    fun `version frames are one step and pass a dropped phone`() {
        for (t in listOf("version_digest", "version_rule", "app_update_request", "app_update_answer", "app_update_offer")) {
            assertTrue(MeshOneStep.isOneStep(t))
            assertTrue(MeshOneStep.isOneStepIn(t, "ali", "me", "ali", "me"))
            assertFalse(MeshOneStep.isOneStepIn(t, "ali", "me", "bilal", "me"))
            assertFalse(MeshBlockPolicy.dropAtFirstHop(t, "ali", "me", setOf("ali")))
        }
        assertFalse(MeshOneStep.isOneStep("version_other"))
        assertTrue(MeshBlockPolicy.dropAtFirstHop("direct_message", "ali", "me", setOf("ali")))
    }
}
