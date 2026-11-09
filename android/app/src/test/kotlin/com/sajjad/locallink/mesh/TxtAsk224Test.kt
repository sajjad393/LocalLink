package com.sajjad.locallink.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 224 (D1): one TXT ask per window was often lost (02:11:37). */
class TxtAsk224Test {
    @Test fun `224-D1 up to 3 asks, 4 s apart, until the TXT comes`() {
        assertEquals(3, TxtAskPolicy.MAX_TRIES)
        assertEquals(4_000L, TxtAskPolicy.GAP_MS)
        assertTrue(TxtAskPolicy.shouldAsk(1, 0L, 4_000L, false))
        assertTrue(TxtAskPolicy.shouldAsk(2, 4_000L, 8_000L, false))
        assertFalse("3 asks is the limit", TxtAskPolicy.shouldAsk(3, 8_000L, 12_000L, false))
        assertFalse("the TXT came", TxtAskPolicy.shouldAsk(1, 0L, 4_000L, true))
        assertFalse("too soon", TxtAskPolicy.shouldAsk(1, 0L, 2_000L, false))
    }

    @Test fun `224-D1 busy stops the extra asks`() {
        assertTrue(TxtAskPolicy.stopOnFailure(2))
        assertFalse(TxtAskPolicy.stopOnFailure(0))
    }

    @Test fun `224-D1 the re-ask only runs the search again (no new request, no window change)`() {
        val s = File("main/kotlin/com/sajjad/locallink/NearbyTagManager.kt").readText()
        val body = s.substringAfter("private fun reAskTxt(").substringBefore("/** Q16:")
        assertTrue(body.contains("if (seq != windowSeq || !searchWindowOpen()) return"))
        assertTrue(body.contains("manager.discoverServices(channel"))
        assertFalse(body.contains("addServiceRequest"))
        assertFalse("the failure never feeds the window retry rules", body.contains("onDiscoverFailed("))
        assertTrue(s.contains("WD_TAG txt_ask from=\$address try=\$tryNo"))
    }
}
