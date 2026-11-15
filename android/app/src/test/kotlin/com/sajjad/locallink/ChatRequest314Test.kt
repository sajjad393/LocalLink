package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 314 (TODO_314 Issue 3, pick B): the Get chat card like the inner card. */
class ChatRequest314Test {
    private fun src(path: String): String =
        listOf("main/$path", "src/main/$path", "app/src/main/$path")
            .map { File(it) }
            .first { it.exists() }
            .readText()

    @Test
    fun `Sent and Reached rock, Coming Ready and ended cards do not`() {
        assertTrue(ChatRequestNotifier307.plan("sent", 4, false).rock)
        assertTrue(ChatRequestNotifier307.plan("reached", 33, false).rock)
        for (step in listOf("coming", "ready", "empty", "cancelled")) {
            assertFalse(step, ChatRequestNotifier307.plan(step, 50, false).rock)
        }
    }

    @Test
    fun `the tracker rocks 4 each way from its step and never leaves the track`() {
        assertEquals(33, ChatRequestNotifier307.rockProgress(33, 0))
        assertEquals(37, ChatRequestNotifier307.rockProgress(33, 1))
        assertEquals(29, ChatRequestNotifier307.rockProgress(33, 2))
        assertEquals(37, ChatRequestNotifier307.rockProgress(33, 3))
        assertEquals(8, ChatRequestNotifier307.rockProgress(4, 1))
        assertEquals(0, ChatRequestNotifier307.rockProgress(4, 2))
        assertEquals(100, ChatRequestNotifier307.rockProgress(98, 1))
        assertEquals(4, ChatRequestNotifier307.ROCK_STEP)
        assertEquals(3_000L, ChatRequestNotifier307.ROCK_EVERY_MS)
    }

    @Test
    fun `rocking only on Android 16+, only before rock_until (10 min)`() {
        val sent = ChatRequestNotifier307.plan("sent", 4, false)
        val now = 1_000_000L
        assertTrue(ChatRequestNotifier307.shouldRock(36, sent, now + 1, now))
        assertFalse(ChatRequestNotifier307.shouldRock(36, sent, now, now))
        assertFalse(ChatRequestNotifier307.shouldRock(36, sent, 0, now))
        assertFalse(ChatRequestNotifier307.shouldRock(35, sent, now + 600_000, now))
        val coming = ChatRequestNotifier307.plan("coming", 70, false)
        assertFalse(ChatRequestNotifier307.shouldRock(36, coming, now + 600_000, now))
    }

    @Test
    fun `Android 15 and older keep the sliding line while waiting, a filled bar once parts come`() {
        assertTrue(ChatRequestNotifier307.plan("sent", 4, false).compatSliding)
        assertTrue(ChatRequestNotifier307.plan("reached", 33, false).compatSliding)
        assertFalse(ChatRequestNotifier307.plan("coming", 70, false).compatSliding)
        val card = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        assertTrue(card.contains("b.setProgress(100, plan.progress, plan.compatSliding)"))
    }

    @Test
    fun `the tracker ring has the step colour of the card`() {
        assertEquals(ChatRequestNotifier307.ORANGE, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("sent", 4, false)))
        assertEquals(ChatRequestNotifier307.ORANGE, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("reached", 33, false)))
        assertEquals(ChatRequestNotifier307.BLUE, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("coming", 70, false)))
        assertEquals(ChatRequestNotifier307.GREEN, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("ready", 100, false)))
        assertEquals(ChatRequestNotifier307.GREY, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("empty", 66, false)))
    }

    @Test
    fun `bubble start, check end, ring tracker, no custom views, timers stop on cancel`() {
        val card = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        assertTrue(card.contains("setProgressStartIcon(Icon.createWithResource(context, R.drawable.ic_req314_start))"))
        assertTrue(card.contains("setProgressEndIcon(Icon.createWithResource(context, R.drawable.ic_req314_end))"))
        assertTrue(card.contains("R.drawable.ic_req314_tracker"))
        assertTrue(card.contains(".setProgressIndeterminate(false)"))
        assertFalse(card.contains("RemoteViews"))
        assertFalse(card.contains("setColorized(true)"))
        // The rock posts are silent: the first post alone may sound.
        assertTrue(card.contains("startRock(context, id, args + (\"buzz\" to false), until)"))
        assertTrue(card.contains("stopRock(requestId.trim())"))
        assertTrue(card.contains("stopAllRocks()"))
        for (name in listOf("ic_req314_start", "ic_req314_end", "ic_req314_tracker")) {
            val xml = src("res/drawable/$name.xml")
            assertTrue(name, xml.contains("android:viewportWidth=\"24\"") && xml.contains("android:viewportHeight=\"24\""))
        }
    }
}
