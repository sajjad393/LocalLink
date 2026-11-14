package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 307 (TODO_307 C1/C2): the Get chat request card on the phone. */
class ChatRequest307Test {
    private fun src(path: String): String =
        listOf("main/$path", "src/main/$path", "app/src/main/$path")
            .map { File(it) }
            .first { it.exists() }
            .readText()

    @Test
    fun `running steps are ongoing and promoted, Sent has no number yet`() {
        val sent = ChatRequestNotifier307.plan("sent", 4, buzz = false)
        assertTrue(sent.ongoing)
        assertTrue(sent.promoted)
        assertTrue(sent.indeterminate)
        assertFalse(sent.alert)
        for (step in listOf("reached", "coming")) {
            val p = ChatRequestNotifier307.plan(step, 50, buzz = false)
            assertTrue(step, p.ongoing)
            assertTrue(step, p.promoted)
            assertFalse(step, p.indeterminate)
            assertEquals(step, 50, p.progress)
            assertEquals(0L, p.timeoutMs)
            assertEquals(ChatRequestNotifier307.CHANNEL_ID, p.channel)
            assertFalse(p.openButton)
        }
        // Unknown steps draw as Sent; the bar never leaves 0-100.
        assertEquals("sent", ChatRequestNotifier307.plan("??", 400, false).step)
        assertEquals(100, ChatRequestNotifier307.plan("coming", 400, false).progress)
        assertEquals(0, ChatRequestNotifier307.plan("coming", -5, false).progress)
    }

    @Test
    fun `Ready is not ongoing, has Open chat, and buzzes only when asked`() {
        val ready = ChatRequestNotifier307.plan("ready", 80, buzz = true)
        assertFalse(ready.ongoing)
        assertFalse(ready.promoted)
        assertEquals(100, ready.progress)
        assertTrue(ready.openButton)
        assertTrue(ready.readyPointGreen)
        assertTrue(ready.alert)
        assertEquals(ChatRequestNotifier307.READY_CHANNEL_ID, ready.channel)
        val again = ChatRequestNotifier307.plan("ready", 100, buzz = false)
        assertFalse(again.alert)
        assertEquals(ChatRequestNotifier307.CHANNEL_ID, again.channel)
        assertNotEquals(ChatRequestNotifier307.CHANNEL_ID, ChatRequestNotifier307.READY_CHANNEL_ID)
    }

    @Test
    fun `No messages is grey, not ongoing, and goes away after 10 s`() {
        val empty = ChatRequestNotifier307.plan("empty", 66, buzz = true)
        assertFalse(empty.ongoing)
        assertFalse(empty.promoted)
        assertTrue(empty.grey)
        assertFalse(empty.alert)
        assertEquals(10_000L, empty.timeoutMs)
    }

    @Test
    fun `API 36+ uses the Live Update path and older phones the plain bar`() {
        assertTrue(ChatRequestNotifier307.useProgressStyle(36))
        assertTrue(ChatRequestNotifier307.useProgressStyle(37))
        assertFalse(ChatRequestNotifier307.useProgressStyle(35))
        assertFalse(ChatRequestNotifier307.useProgressStyle(24))
        assertEquals(listOf(33, 66, 100), ChatRequestNotifier307.POINTS)
    }

    @Test
    fun `one group, stable ids, own tag`() {
        assertEquals("linkup_chat_requests", ChatRequestNotifier307.GROUP_KEY)
        assertEquals("locallink_chat_requests_v1", ChatRequestNotifier307.CHANNEL_ID)
        val a = ChatRequestNotifier307.notificationId("611d9a")
        assertEquals(a, ChatRequestNotifier307.notificationId(" 611d9a "))
        assertNotEquals(a, ChatRequestNotifier307.notificationId("611d9b"))
        assertTrue(a > 0)
        assertTrue(ChatRequestNotifier307.notificationId("") > 0)
        assertNotEquals(ChatRequestNotifier307.TAG, ChatRequestNotifier307.SUMMARY_TAG)
        assertNotEquals(ChatRequestNotifier307.requestCode("x", 0), ChatRequestNotifier307.requestCode("x", 1))
        assertEquals("K", ChatRequestNotifier307.initialOf("@kiran"))
        assertEquals("?", ChatRequestNotifier307.initialOf(" "))
        assertEquals(ChatRequestNotifier307.colorOf("ayesha"), ChatRequestNotifier307.colorOf("ayesha"))
    }

    @Test
    fun `wired on both channels, the tap reaches Dart, normal permission only`() {
        val main = src("kotlin/com/sajjad/locallink/MainActivity.kt")
        val bg = src("kotlin/com/sajjad/locallink/BackgroundChannels.kt")
        for (s in listOf(main, bg)) {
            assertTrue(s.contains("\"showChatRequest\" -> { ChatRequestNotifier307.show("))
            assertTrue(s.contains("\"cancelChatRequest\" ->"))
            assertTrue(s.contains("\"cancelAllChatRequests\" -> { ChatRequestNotifier307.cancelAll("))
        }
        assertTrue(main.contains("action == ChatRequestNotifier307.TAP_ACTION"))
        val manifest = src("AndroidManifest.xml")
        assertTrue(manifest.contains("android.permission.POST_PROMOTED_NOTIFICATIONS"))
        val card = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        // The summary is never promoted; no custom views; not colorized (Live Update rules).
        assertFalse(card.contains("RemoteViews"))
        assertFalse(card.contains("setColorized(true)"))
        assertTrue(card.contains("setGroupSummary(true)"))
        assertTrue(card.contains("if (plan.promoted) b.extras.putBoolean(EXTRA_PROMOTED, true)"))
    }
}
