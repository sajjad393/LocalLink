package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 321 (N1-N3, USER PICK B): one line, no buttons, the same bar on every Android. */
class ChatRequest321Test {
    private fun src(path: String): String =
        listOf("main/$path", "src/main/$path", "app/src/main/$path")
            .map { File(it) }
            .first { it.exists() }
            .readText()

    private val n = ChatRequestNotifier307

    @Test
    fun `fills from Dart - one per file, kept inside 0-100, junk dropped`() {
        assertEquals(listOf(100, 40, 0), n.fills321("100,40,0"))
        assertEquals(listOf(100, 0), n.fills321(" 120 , x, -3"))
        assertEquals(emptyList<Int>(), n.fills321(""))
    }

    @Test
    fun `one segment per file, at most 10, adding up to 100`() {
        assertEquals(listOf(100), n.segments321(0))
        assertEquals(7, n.segments321(7).size)
        assertEquals(n.MAX_SEGMENTS_321, n.segments321(40).size)
        for (k in 1..15) assertEquals(100, n.segments321(k).sum())
    }

    @Test
    fun `green points at the end of each file that is in - the last 4, never 0 or 100`() {
        assertEquals(listOf(14, 28), n.points321(listOf(100, 100, 30, 0, 0, 0, 0)))
        assertEquals(emptyList<Int>(), n.points321(listOf(40, 0, 0)))
        assertEquals(emptyList<Int>(), n.points321(listOf(100)))
        val many = n.points321(List(9) { 100 } + listOf(0))
        assertEquals(n.MAX_POINTS_321, many.size)
        assertTrue(many.all { it in 1..99 })
        assertEquals(listOf(50), n.points321(listOf(100, 100)))
    }

    @Test
    fun `files card - pieces, blue, photo tracker, sender letter, green points`() {
        val bar = n.bar321(n.plan("files", 25, false), "100,100,50,0", "photo", "ayesha", 25)
        assertTrue(bar.show)
        assertEquals(4, bar.segments.size)
        assertEquals(listOf(25, 50), bar.points)
        assertEquals(62, bar.progress)
        assertEquals(n.BLUE, bar.color)
        assertEquals(n.GREEN, bar.pointColor)
        assertEquals("photo", bar.tracker)
        assertEquals("A", bar.startLetter)
        assertEquals("video", n.bar321(n.plan("files", 5, false), "0", "video", "", 0).tracker)
        assertEquals("voice", n.bar321(n.plan("files", 5, false), "0", "voice", "", 0).tracker)
        assertEquals("", n.bar321(n.plan("files", 5, false), "0", "", "", 0).startLetter)
    }

    @Test
    fun `waiting = orange + hourglass, done, Ready, Up to date and ended = no bar`() {
        val wait = n.bar321(n.plan("files_wait", 30, false), "100,0", "photo", "kiran", 30)
        assertEquals(n.ORANGE, wait.color)
        assertEquals("wait", wait.tracker)
        assertEquals("wait", n.bar321(n.plan("reached", 33, false), "", "", "", 33).tracker)
        assertEquals("ring", n.bar321(n.plan("coming", 70, false), "", "", "", 70).tracker)
        for (step in listOf("files_done", "ready", "up_to_date", "empty", "cancelled")) {
            assertFalse(step, n.bar321(n.plan(step, 100, false), "100", "photo", "x", 100).show)
        }
    }

    @Test
    fun `the check at the end of the line is found (drawn green)`() {
        assertEquals(10, n.checkAt321("Pricesess \u2713"))
        assertEquals(-1, n.checkAt321("ayesha & kiran \u00b7 3/7"))
        assertEquals(-1, n.checkAt321(""))
    }

    @Test
    fun `no buttons and no text line on any step`() {
        for (step in listOf("sent", "reached", "coming", "ready", "up_to_date", "files", "files_wait", "files_done", "empty")) {
            val p = n.plan(step, 50, false)
            assertFalse(step, p.openButton)
            assertFalse(step, p.stopButton)
        }
        val card = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        val compat = src("kotlin/com/sajjad/locallink/ChatCard321.kt")
        for (s in listOf(card, compat)) {
            assertFalse(s.contains("addAction("))
            assertFalse(s.contains("setContentText(text)")) // only the "3 chats" summary has lines
        }
    }

    @Test
    fun `Android 16 keeps Live Update rules - custom views only in the Android 15 card`() {
        val card = src("kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt")
        assertFalse(card.contains("RemoteViews"))
        assertTrue(card.contains("ChatCard321.build(context, plan, title, picture, whenMs, open, bar)"))
        assertTrue(card.contains("if (Build.VERSION.SDK_INT >= 36) {"))
        val compat = src("kotlin/com/sajjad/locallink/ChatCard321.kt")
        assertTrue(compat.contains("RemoteViews(context.packageName, R.layout.notif321_card)"))
        assertTrue(compat.contains(".setAutoCancel(plan.step == \"ready\" || plan.step == \"files_done\")"))
        assertTrue(compat.contains(".setGroup(ChatRequestNotifier307.GROUP_KEY)"))
        val layout = src("res/layout/notif321_card.xml")
        for (id in listOf("n321_title", "n321_bar", "n321_pic")) assertTrue(id, layout.contains("@+id/$id"))
        for (name in listOf("ic_req321_video", "ic_req321_mic", "ic_req321_wait", "ic_req321_doc")) {
            val xml = src("res/drawable/$name.xml")
            assertTrue(name, xml.contains("android:viewportWidth=\"24\"") && xml.contains("android:viewportHeight=\"24\""))
        }
    }

    @Test
    fun `regression - colours, channels and the one buzz are unchanged`() {
        assertEquals(0xFF209DEB.toInt(), n.BLUE)
        assertEquals(0xFF22C55E.toInt(), n.GREEN)
        assertEquals(0xFFF59E0B.toInt(), n.ORANGE)
        assertTrue(n.plan("ready", 100, true).alert)
        assertFalse(n.plan("files", 50, false).alert)
        assertEquals(n.READY_CHANNEL_ID, n.plan("ready", 100, true).channel)
        assertEquals(listOf(33, 66), n.bar321(n.plan("sent", 4, false), "", "", "", 4).points)
    }
}
