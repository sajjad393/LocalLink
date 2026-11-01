package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import com.sajjad.locallink.CallMicEffectsPolicy.Result as R

class Mic191Test {

    @Test fun phone_without_the_tool_says_none() {
        assertEquals(R.NONE, CallMicEffectsPolicy.result(available = false, created = false, wasOn = false, isOn = false, error = false))
    }

    @Test fun tool_offered_but_not_created_is_fail() {
        assertEquals(R.FAIL, CallMicEffectsPolicy.result(available = true, created = false, wasOn = false, isOn = false, error = false))
    }

    @Test fun phone_had_it_on_already() {
        assertEquals(R.ALREADY, CallMicEffectsPolicy.result(available = true, created = true, wasOn = true, isOn = true, error = false))
    }

    @Test fun linkup_turned_it_on() {
        assertEquals(R.ON, CallMicEffectsPolicy.result(available = true, created = true, wasOn = false, isOn = true, error = false))
    }

    @Test fun would_not_turn_on_is_off() {
        assertEquals(R.OFF, CallMicEffectsPolicy.result(available = true, created = true, wasOn = false, isOn = false, error = false))
    }

    @Test fun error_wins() {
        assertEquals(R.FAIL, CallMicEffectsPolicy.result(available = true, created = true, wasOn = true, isOn = true, error = true))
    }

    @Test fun warn_only_when_echo_cancel_not_working() {
        assertFalse(CallMicEffectsPolicy.warn(R.ON))
        assertFalse(CallMicEffectsPolicy.warn(R.ALREADY))
        assertTrue(CallMicEffectsPolicy.warn(R.NONE))
        assertTrue(CallMicEffectsPolicy.warn(R.OFF))
        assertTrue(CallMicEffectsPolicy.warn(R.FAIL))
    }

    @Test fun log_line_words() {
        assertEquals(
            "CALL_MIC_EFFECTS call=call-1 echo_cancel=on noise_cut=none session=42",
            CallMicEffectsPolicy.line("call-1", R.ON, R.NONE, 42),
        )
    }
}
