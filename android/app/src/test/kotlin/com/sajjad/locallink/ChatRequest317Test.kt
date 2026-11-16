package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 317 (TODO_317 G7 / F): the files card after "Chat ready" + the seen-packet load. */
class ChatRequest317Test {
    private fun src(path: String): String =
        listOf("main/$path", "src/main/$path", "app/src/main/$path")
            .map { File(it) }
            .first { it.exists() }
            .readText()

    @Test
    fun `files steps - coming and waiting stay on, done is silent and goes on tap`() {
        val files = ChatRequestNotifier307.plan("files", 40, buzz = false)
        assertTrue(files.files)
        assertTrue(files.ongoing)
        assertTrue(files.promoted)
        assertFalse(files.openButton) // Bundle 321 (N1): no buttons
        assertFalse(files.stopButton)
        assertFalse(files.alert)
        assertEquals(40, files.progress)
        assertEquals(ChatRequestNotifier307.CHANNEL_ID, files.channel)
        val wait = ChatRequestNotifier307.plan("files_wait", 40, buzz = false)
        assertTrue(wait.ongoing)
        assertTrue(wait.compatSliding)
        assertFalse(wait.stopButton)
        val done = ChatRequestNotifier307.plan("files_done", 10, buzz = false)
        assertFalse(done.ongoing)
        assertFalse(done.promoted)
        assertFalse(done.alert)
        assertFalse(done.stopButton)
        assertEquals(100, done.progress)
    }

    @Test
    fun `waiting more than 30 min can be swiped away`() {
        val swipe = ChatRequestNotifier307.plan("files_wait", 40, buzz = false, swipe = true)
        assertFalse(swipe.ongoing)
        assertFalse(swipe.promoted)
        assertTrue(ChatRequestNotifier307.plan("files", 40, buzz = false, swipe = true).ongoing)
    }

    @Test
    fun `only one buzz - the first post when Ready never buzzed`() {
        val first = ChatRequestNotifier307.plan("files", 0, buzz = true)
        assertTrue(first.alert)
        assertEquals(ChatRequestNotifier307.READY_CHANNEL_ID, first.channel)
        for (step in listOf("files", "files_wait", "files_done")) {
            assertFalse(step, ChatRequestNotifier307.plan(step, 50, buzz = false).alert)
        }
    }

    @Test
    fun `colours - blue coming, orange waiting, green done`() {
        assertEquals(ChatRequestNotifier307.BLUE, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("files", 5, false)))
        assertEquals(ChatRequestNotifier307.ORANGE, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("files_wait", 5, false)))
        assertEquals(ChatRequestNotifier307.GREEN, ChatRequestNotifier307.trackerColor(ChatRequestNotifier307.plan("files_done", 5, false)))
    }

    @Test
    fun `trip segments - one per 8 MB trip, max 7, they add up to 100`() {
        assertEquals(listOf(100), ChatRequestNotifier307.tripSegments(0))
        assertEquals(listOf(33, 33, 34), ChatRequestNotifier307.tripSegments(3))
        assertEquals(7, ChatRequestNotifier307.tripSegments(20).size)
        for (n in 1..9) assertEquals(100, ChatRequestNotifier307.tripSegments(n).sum())
    }

    @Test
    fun `regression - the 307 and 314 steps are unchanged`() {
        val ready = ChatRequestNotifier307.plan("ready", 100, buzz = true)
        assertTrue(ready.alert)
        assertFalse(ready.files)
        assertFalse(ready.stopButton)
        assertTrue(ChatRequestNotifier307.plan("coming", 50, false).ongoing)
        assertFalse(ChatRequestNotifier307.plan("coming", 50, false).files)
        assertEquals("sent", ChatRequestNotifier307.plan("??", 0, false).step)
    }

    @Test
    fun `source - photo tracker, no Stop button (321 N1), done auto-cancels`() {
        val s = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        assertTrue(s.contains("R.drawable.ic_req317_file"))
        assertFalse(s.contains("tapIntent(context, STOP_PREFIX + id)"))
        assertFalse(s.contains("addAction("))
        assertTrue(s.contains(".setAutoCancel(plan.step == \"ready\" || plan.step == \"files_done\")"))
        assertTrue(src("res/drawable/ic_req317_file.xml").contains("android:viewportWidth=\"24\""))
    }

    @Test
    fun `F - seen packets load off the main thread, mesh packets wait for them`() {
        val s = src("kotlin/com/sajjad/locallink/LocalLinkTransportService.kt")
        assertTrue(s.contains("private fun restoreDurableState(){startSeenLoad317();restoreIncomingTransfers();restoreOutgoingTransfers()}"))
        assertTrue(s.contains("try{loadSeenMeshPackets()}catch(_:Throwable){}finally{seenLoaded317.countDown()}"))
        assertTrue(s.contains("if (!ephemeral) awaitSeenLoad317() // Bundle 317 (F)"))
        val i = s.indexOf("if (!ephemeral) awaitSeenLoad317()")
        assertTrue(i > 0 && i < s.indexOf("val firstSeen = tracker.markSeen(source, id, now)"))
    }
}
