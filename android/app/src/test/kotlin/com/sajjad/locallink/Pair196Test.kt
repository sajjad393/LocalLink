package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 196 (12b): pair kind "wait" (private profile - ask first). */
class Pair196Test {
    @Test
    fun `request accept and wait are allowed`() {
        assertTrue(PairKind.valid("request"))
        assertTrue(PairKind.valid("accept"))
        assertTrue(PairKind.valid("wait"))
        assertEquals("wait", PairKind.WAIT)
    }

    @Test
    fun `anything else is dropped`() {
        assertFalse(PairKind.valid(""))
        assertFalse(PairKind.valid(null))
        assertFalse(PairKind.valid("decline"))
        assertFalse(PairKind.valid("WAIT"))
        assertFalse(PairKind.valid("wait "))
    }
}
