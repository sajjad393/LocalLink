package com.sajjad.locallink

import com.sajjad.locallink.mesh.RelayVoiceHealth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Path192Test {
    // ---------------- CALL_PATH ----------------

    @Test fun path_words() {
        assertEquals("lan", CallPathPolicy.kind("lan", false))
        assertEquals("wifi_direct", CallPathPolicy.kind("wifi_direct", true))
        assertEquals("local_net", CallPathPolicy.kind("local_net", false))
        assertEquals("mesh", CallPathPolicy.kind(null, true))
        assertEquals("none", CallPathPolicy.kind(null, false))
        assertEquals("none", CallPathPolicy.kind("", false))
    }

    @Test fun path_line() {
        val p = CallPathPolicy.Path("mesh", 2, "abc123", false)
        assertEquals("CALL_PATH call=c1 at=start path=mesh hops=2 via=abc123 udp=n", CallPathPolicy.line("c1", "start", p))
    }

    @Test fun change_only_when_different() {
        val a = CallPathPolicy.Path("lan", 1, "-", true)
        assertTrue(CallPathPolicy.changed(null, a))
        assertFalse(CallPathPolicy.changed(a, a.copy()))
        assertTrue(CallPathPolicy.changed(a, a.copy(udp = false)))
    }

    @Test fun warn_when_direct_goes_through_a_middle_phone_or_lost() {
        val direct = CallPathPolicy.Path("wifi_direct", 1, "-", true)
        assertFalse(CallPathPolicy.warn(null, direct))
        assertTrue(CallPathPolicy.warn(direct, CallPathPolicy.Path("mesh", 2, "x", false)))
        assertTrue(CallPathPolicy.warn(direct, CallPathPolicy.Path("none", 0, "-", false)))
        assertFalse(CallPathPolicy.warn(direct, direct.copy(udp = false)))
    }

    @Test fun short_id() {
        assertEquals("16a834", CallPathPolicy.shortId("android-c891ac8ded16a834"))
        assertEquals("-", CallPathPolicy.shortId(null))
    }

    // ---------------- WD_LINK ----------------

    @Test fun wd_band() {
        assertEquals("2.4", WdLinkPolicy.band(2437))
        assertEquals("5", WdLinkPolicy.band(5180))
        assertEquals("-", WdLinkPolicy.band(-1))
    }

    @Test fun wd_lines() {
        assertEquals("WD_LINK at=call_start group=n", WdLinkPolicy.line("call_start", false, false, -1, -1))
        assertEquals("WD_LINK at=call_start group=y role=owner members=1 freq=2437 band=2.4", WdLinkPolicy.line("call_start", true, true, 1, 2437))
        assertEquals("WD_LINK at=call_end group=y role=client members=- freq=- band=-", WdLinkPolicy.line("call_end", true, false, -1, -1))
    }

    @Test fun wd_change_in_call() {
        assertNull(WdLinkPolicy.changeInCall(false, true, false))
        assertNull(WdLinkPolicy.changeInCall(true, null, false))
        assertNull(WdLinkPolicy.changeInCall(true, true, true))
        assertEquals("drop_in_call", WdLinkPolicy.changeInCall(true, true, false))
        assertEquals("up_in_call", WdLinkPolicy.changeInCall(true, false, true))
    }

    // ---------------- RELAY_VOICE_HEALTH ----------------

    @Test fun relay_line_every_10s() {
        val h = RelayVoiceHealth()
        var line: String? = null
        var t = 1_000L
        for (i in 0 until 600) { // 12 s of 20 ms pieces
            val l = h.onPassed("0123456789abcdef", "android-aaaaaa111111", "android-bbbbbb222222", t)
            if (l != null && line == null) line = l
            t += 20
        }
        assertNotNull(line)
        assertTrue(line!!, line.startsWith("RELAY_VOICE_HEALTH stream=abcdef src=111111 dst=222222 passed=501 per_s=50 dropped=0 gap_max_ms=20 at=run"))
    }

    @Test fun relay_drops_and_gap() {
        val h = RelayVoiceHealth()
        h.onPassed("s1", "a", "b", 0L)
        h.onPassed("s1", "a", "b", 400L)
        h.onDropped("s1", "a", "b", 500L)
        val l = h.onPassed("s1", "a", "b", 10_000L)
        assertNotNull(l)
        assertTrue(l!!, l.contains(" passed=3 ") && l.contains(" dropped=1 ") && l.contains(" gap_max_ms=9600 "))
    }

    @Test fun relay_end_line_after_idle() {
        val h = RelayVoiceHealth()
        h.onPassed("s1", "a", "b", 1_000L)
        assertTrue(h.tick(5_000L).isEmpty())
        val end = h.tick(9_500L)
        assertEquals(1, end.size)
        assertTrue(end[0], end[0].endsWith(" at=end"))
        assertEquals(0, h.activeStreams())
    }

    @Test fun relay_stream_cap() {
        val h = RelayVoiceHealth(maxStreams = 2)
        h.onPassed("s1", "a", "b", 0L); h.onPassed("s2", "a", "b", 0L); h.onPassed("s3", "a", "b", 0L)
        assertEquals(2, h.activeStreams())
    }

    // ---------------- health line ----------------

    @Test fun health_line_has_hops_and_via() {
        val line = CallVoiceHealth.line("CALL_VOICE_HEALTH", "c1", CallVoiceHealth.Snapshot(arrived = 10, played = 10), CallVoiceHealth.Now(link = "relay", hopsRx = 2, via = "abc123"))
        assertTrue(line, line.endsWith(" hops_rx=2 via=abc123"))
        val none = CallVoiceHealth.line("CALL_VOICE_HEALTH", "c1", CallVoiceHealth.Snapshot(), CallVoiceHealth.Now())
        assertTrue(none, none.endsWith(" hops_rx=- via=-"))
    }

    // ---------------- wiring ----------------

    private fun source(name: String): String {
        val candidates = listOf("main/kotlin/com/sajjad/locallink/$name", "src/main/kotlin/com/sajjad/locallink/$name", "app/src/main/kotlin/com/sajjad/locallink/$name", "android/app/src/main/kotlin/com/sajjad/locallink/$name")
        return candidates.map { java.io.File(it) }.first { it.exists() }.readText()
    }

    @Test fun wiring_in_service_and_radio() {
        val s = source("LocalLinkTransportService.kt")
        assertTrue(s.contains("session.notePath(\"start\", true)"))
        assertTrue(s.contains("notePath(\"end\", true)"))
        assertTrue(s.contains("NearbyRadio.logLinkForCall(\"call_start\")"))
        assertTrue(s.contains("NearbyRadio.logLinkForCall(\"call_end\")"))
        assertTrue(s.contains("relayVoiceHealth.onPassed("))
        assertTrue(s.contains("relayVoiceHealth.tick(now)"))
        assertTrue(s.contains("current.lastRxHops = hopCount"))
        val r = source("NearbyRadio.kt")
        assertTrue(r.contains("WdLinkPolicy.changeInCall(CallNearbyPause.inCall(), lastFormed, connected)"))
    }
}
