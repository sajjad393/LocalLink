package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 175: background service rules (inbox, network, health, no-screen engine). */
class Background175Test {
    private fun msg(sender: String, payload: String) = mapOf<String, Any?>("type" to "message", "sender_id" to sender, "payload" to payload)

    @Test fun `inbox keeps messages in order and empties on drain`() {
        val box = EventInbox()
        assertTrue(box.add("message", msg("a", "1"), 0L))
        assertTrue(box.add("file_received", mapOf("transfer_id" to "t1", "message_id" to "m1"), 1L))
        assertTrue(box.add("message", msg("b", "2"), 2L))
        val out = box.drain(3L)
        assertEquals(listOf("message", "file_received", "message"), out.map { it.type })
        assertEquals("1", out[0].data["payload"])
        assertEquals(0, box.size)
        assertTrue(box.drain(4L).isEmpty())
    }

    @Test fun `inbox ignores route noise and repeats`() {
        val box = EventInbox()
        assertFalse(box.add("route_changed", emptyMap(), 0L))
        assertFalse(box.add("state", emptyMap(), 0L))
        assertFalse(box.add("network_changed", emptyMap(), 0L))
        assertTrue(box.add("message", msg("a", "same"), 0L))
        assertFalse(box.add("message", msg("a", "same"), 1L))
        assertTrue(box.add("message", msg("b", "same"), 1L))
        assertEquals(2, box.size)
    }

    @Test fun `inbox drops events older than ten minutes`() {
        val box = EventInbox()
        box.add("message", msg("a", "old"), 0L)
        box.add("message", msg("a", "new"), EventInbox.MAX_AGE_MS)
        val out = box.drain(EventInbox.MAX_AGE_MS + 1L)
        assertEquals(listOf("new"), out.map { it.data["payload"] })
        assertEquals(1, box.dropped)
    }

    @Test fun `inbox keeps only the newest when full`() {
        val box = EventInbox(maxItems = 3)
        for (i in 1..5) box.add("message", msg("a", "$i"), i.toLong())
        assertEquals(listOf("3", "4", "5"), box.drain(6L).map { it.data["payload"] })
        assertEquals(2, box.dropped)
    }

    @Test fun `first network snapshot is only the start`() {
        assertNull(NetworkChangePolicy.decide(null, NetworkChangePolicy.Snapshot(true, true, "100")))
    }

    @Test fun `wifi back, wifi gone, internet change and router change`() {
        val off = NetworkChangePolicy.Snapshot(false, false, "")
        val home = NetworkChangePolicy.Snapshot(true, true, "100")
        val noNet = NetworkChangePolicy.Snapshot(true, false, "100")
        val other = NetworkChangePolicy.Snapshot(true, true, "101")
        val up = NetworkChangePolicy.decide(off, home)!!
        assertTrue(up.wifiUp); assertFalse(up.wifiDown); assertTrue(up.internetChanged)
        val down = NetworkChangePolicy.decide(home, off)!!
        assertTrue(down.wifiDown); assertFalse(down.wifiUp)
        // Wi-Fi without internet is still Wi-Fi: no LAN restart, only the internet flag.
        val lost = NetworkChangePolicy.decide(home, noNet)!!
        assertFalse(lost.wifiUp); assertFalse(lost.wifiDown); assertTrue(lost.internetChanged)
        assertTrue(NetworkChangePolicy.decide(home, other)!!.wifiUp)
        assertNull(NetworkChangePolicy.decide(home, home))
    }

    @Test fun `health check rules`() {
        assertEquals(HealthPolicy.Action.NOTHING, HealthPolicy.decide(enabled = false, serviceRunning = false, appOpen = false))
        assertEquals(HealthPolicy.Action.RESTART, HealthPolicy.decide(enabled = true, serviceRunning = false, appOpen = false))
        assertEquals(HealthPolicy.Action.RESTART, HealthPolicy.decide(enabled = true, serviceRunning = false, appOpen = true))
        assertEquals(HealthPolicy.Action.ENGINE, HealthPolicy.decide(enabled = true, serviceRunning = true, appOpen = false))
        assertEquals(HealthPolicy.Action.NOTHING, HealthPolicy.decide(enabled = true, serviceRunning = true, appOpen = true))
    }

    private fun skip(
        enabled: Boolean = true, service: Boolean = true, open: Boolean = false, running: Boolean = false,
        opened: Long = 77L, current: Long = 77L, idle: Boolean = false,
    ) = BackgroundEnginePolicy.noScreenSkipReason(enabled, service, open, running, opened, current, idle)

    @Test fun `no-screen engine starts only when it should`() {
        assertNull(skip())
        assertEquals("background_off", skip(enabled = false))
        assertEquals("app_open", skip(open = true))
        assertEquals("running", skip(running = true))
        assertEquals("service_not_running", skip(service = false))
        assertEquals("never_opened", skip(opened = 0L))
        assertEquals("new_version_not_opened", skip(opened = 76L))
        assertEquals("idle_recently", skip(idle = true))
    }
}
