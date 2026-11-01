package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 189: (A) stop a running Nearby search when call voice starts;
 *  (B) CALL_SOUND_STATE log line. */
class Call189Test {
    private val main = File("main/kotlin/com/sajjad/locallink")

    @Test fun `search is stopped unless a group join was just asked for`() {
        val now = 1_000_000L
        assertEquals("stop", CallSearchStop.peersAction(now, 0L))
        assertEquals("skip_joining", CallSearchStop.peersAction(now, now - 5_000L))
        assertEquals("skip_joining", CallSearchStop.peersAction(now, now))
        assertEquals("stop", CallSearchStop.peersAction(now, now - CallSearchStop.JOIN_GUARD_MS))
        // A clock that jumped back never blocks the stop.
        assertEquals("stop", CallSearchStop.peersAction(now, now + 60_000L))
    }

    @Test fun `stop line is short and plain`() {
        assertEquals("CALL_NEARBY_STOP peers=ok services=ok",
            CallSearchStop.line(CallSearchStop.result(true), CallSearchStop.result(true)))
        assertEquals("CALL_NEARBY_STOP peers=fail_2 services=ok",
            CallSearchStop.line(CallSearchStop.result(false, 2), "ok"))
    }

    @Test fun `stop runs after the call pause is set, on the main looper`() {
        val service = File(main, "LocalLinkTransportService.kt").readText()
        val started = service.indexOf("CallNearbyPause.callStarted()")
        val stop = service.indexOf("NearbyRadio.stopSearchForCall()")
        assertTrue(started > 0 && stop > started)
        val radio = File(main, "NearbyRadio.kt").readText()
        val fn = radio.substringAfter("fun stopSearchForCall()").substringBefore("private fun stopSearchNow")
        assertTrue(fn.contains("main.post"))
        assertTrue(radio.contains("m.stopPeerDiscovery(ch"))
        assertTrue(radio.contains("m.clearServiceRequests(ch"))
        // The join guard is set where a group is created / joined / left.
        assertEquals(3, Regex("lastGroupChangeAt = System.currentTimeMillis\\(\\)").findAll(radio).count())
    }

    @Test fun `sound line shows volume output battery saver`() {
        val s = CallSoundState.State(volume = 3, volumeMax = 7, output = "ear", batteryPercent = 15,
            charging = false, saver = true, micMuted = false, mode = 3)
        assertEquals("CALL_SOUND_STATE call=c1 at=call vol=3/7 out=ear battery=15% charging=n saver=y mic_mute=n mode=communication",
            CallSoundState.line("c1", s, "call"))
        assertEquals("CALL_SOUND_STATE call=c1 at=end vol=-/- out=- battery=- charging=- saver=- mic_mute=- mode=-",
            CallSoundState.line("c1", CallSoundState.State(), "end"))
    }

    @Test fun `sound line is written on change or once a minute`() {
        val s = CallSoundState.State(volume = 3, volumeMax = 7, output = "speaker", batteryPercent = 15, mode = 3)
        val key = CallSoundState.key(s)
        assertTrue(CallSoundState.due(0L, 0L, null, s))
        assertFalse(CallSoundState.due(10_000L, 0L, key, s))
        assertTrue(CallSoundState.due(10_000L, 0L, key, s.copy(output = "ear")))
        assertTrue(CallSoundState.due(10_000L, 0L, key, s.copy(volume = 2)))
        assertTrue(CallSoundState.due(10_000L, 0L, key, s.copy(saver = true)))
        // Battery 15 -> 14 % is a new 5 % step; 15 -> 16 is not.
        assertTrue(CallSoundState.due(10_000L, 0L, key, s.copy(batteryPercent = 14)))
        assertFalse(CallSoundState.due(10_000L, 0L, key, s.copy(batteryPercent = 16)))
        assertTrue(CallSoundState.due(CallSoundState.EVERY_MS, 0L, key, s))
    }

    @Test fun `sound reads never run on the speaker thread`() {
        val service = File(main, "LocalLinkTransportService.kt").readText()
        val fn = service.substringAfter("private fun noteSoundState(").substringBefore("private fun outputName(")
        assertTrue(fn.contains("Thread({"))
        assertTrue(fn.contains("\"linkup-sound-state\").start()"))
        assertTrue(service.contains("noteSoundState(\"call\", false)"))
        assertTrue(service.contains("noteSoundState(\"end\", true)"))
    }
}
