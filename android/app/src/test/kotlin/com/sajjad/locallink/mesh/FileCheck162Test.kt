package com.sajjad.locallink.mesh

import com.sajjad.locallink.DirectFileTransferPolicy
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** Bundle 162 (4.5): a file that fails its check is sent again once, then fails. */
class FileCheck162Test {
    @Test fun `first failed check restarts, the second gives up`() {
        assertEquals("restart", DirectFileTransferPolicy.onHashMismatch(0))
        assertEquals("give_up", DirectFileTransferPolicy.onHashMismatch(1))
        assertEquals("give_up", DirectFileTransferPolicy.onHashMismatch(5))
        assertEquals(1, DirectFileTransferPolicy.MAX_HASH_RESTARTS)
    }

    @Test fun `a restart makes the sender send every chunk again`() {
        val acked = booleanArrayOf(true, true, false, true)
        val sent = longArrayOf(10L, 20L, 30L, 40L)
        DirectFileTransferPolicy.resetForRestart(acked, sent)
        assertArrayEquals(BooleanArray(4), acked)
        assertArrayEquals(LongArray(4), sent)
    }
}
