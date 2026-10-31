package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 176: the ringing call hand-over slot. */
class CallHandover176Test {
    @Test fun `parked invite is taken once`() {
        val slot = CallHandoverSlot()
        assertTrue(slot.park("c1", "{\"call_id\":\"c1\"}", 1_000L))
        assertEquals("c1", slot.parkedCallId(2_000L))
        assertEquals("{\"call_id\":\"c1\"}", slot.take(2_000L))
        assertNull(slot.take(2_001L))
    }

    @Test fun `old invite is not handed over`() {
        val slot = CallHandoverSlot()
        slot.park("c1", "{}x", 0L)
        assertNull(slot.take(CallHandoverSlot.MAX_AGE_MS + 1L))
    }

    @Test fun `clear removes only that call`() {
        val slot = CallHandoverSlot()
        slot.park("c1", "{a}", 0L)
        slot.clear("other")
        assertEquals("c1", slot.parkedCallId(1L))
        slot.clear("c1")
        assertNull(slot.take(1L))
    }

    @Test fun `a newer call replaces the older one`() {
        val slot = CallHandoverSlot()
        slot.park("c1", "{1}", 0L)
        slot.park("c2", "{2}", 5L)
        assertEquals("{2}", slot.take(6L))
    }

    @Test fun `bad input is refused`() {
        val slot = CallHandoverSlot()
        assertFalse(slot.park("", "{}", 0L))
        assertFalse(slot.park("c1", "", 0L))
        assertFalse(slot.park("c1", "x".repeat(CallHandoverSlot.MAX_JSON + 1), 0L))
        assertFalse(slot.park("x".repeat(129), "{}", 0L))
        assertNull(slot.take(1L))
    }
}
