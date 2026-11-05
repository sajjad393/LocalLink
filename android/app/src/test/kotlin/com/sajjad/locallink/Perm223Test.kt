package com.sajjad.locallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 223 (I): one queue for every permission pop-up. */
class Perm223Test {
    private val main = File("main/kotlin/com/sajjad/locallink")
    private fun src(name: String) = File(main, name).readText()

    private fun ask(name: String, code: Int) = PermissionQueue.Ask(name, arrayOf("android.permission.$name"), code)

    @Test fun `223-21 a second ask waits while one pop-up is open`() {
        val fired = mutableListOf<String>()
        val logs = mutableListOf<String>()
        val q = PermissionQueue(fire = { fired.add(it.name) }, log = { logs.add(it) })
        q.ask(ask("RECORD_AUDIO", 7812))
        q.ask(ask("NEARBY", 7742))
        assertEquals(listOf("RECORD_AUDIO"), fired)
        assertEquals(1, q.queued)
        assertTrue(logs.contains("PERM_QUEUED name=NEARBY behind=RECORD_AUDIO"))
        q.answered(7812, true)
        assertEquals(listOf("RECORD_AUDIO", "NEARBY"), fired)
        assertTrue(logs.contains("PERM_ANSWER name=RECORD_AUDIO granted=y"))
        q.answered(7742, false)
        assertTrue(logs.contains("PERM_ANSWER name=NEARBY granted=n"))
        assertNull(q.open)
    }

    @Test fun `223-21 the same ask twice is kept once`() {
        val fired = mutableListOf<String>()
        val q = PermissionQueue(fire = { fired.add(it.name) })
        q.ask(ask("A", 1))
        q.ask(ask("B", 2))
        q.ask(ask("B", 2))
        q.ask(ask("A", 1))
        assertEquals(1, q.queued)
        q.answered(1, true)
        q.answered(2, true)
        assertEquals(listOf("A", "B"), fired)
    }

    @Test fun `223-21 an answer for another code does not move the queue`() {
        val fired = mutableListOf<String>()
        val q = PermissionQueue(fire = { fired.add(it.name) })
        q.ask(ask("A", 1))
        q.ask(ask("B", 2))
        assertNull(q.answered(99, true))
        assertEquals(listOf("A"), fired)
    }

    @Test fun `223-22 a pop-up with no answer for 60 s is treated as gone`() {
        var t = 0L
        val fired = mutableListOf<String>()
        val logs = mutableListOf<String>()
        val q = PermissionQueue(fire = { fired.add(it.name) }, log = { logs.add(it) }, now = { t })
        q.ask(ask("A", 1))
        t = PermissionQueue.STUCK_MS + 1
        q.ask(ask("B", 2))
        assertEquals(listOf("A", "B"), fired)
        assertTrue(logs.contains("PERM_ANSWER name=A granted=timeout"))
    }

    @Test fun `223-22 a fire that throws does not block the next ask`() {
        val fired = mutableListOf<String>()
        val q = PermissionQueue(fire = { if (it.name == "A") throw IllegalStateException("x") else fired.add(it.name) })
        q.ask(ask("A", 1))
        q.ask(ask("B", 2))
        assertEquals(listOf("B"), fired)
    }

    @Test fun `223-23 reset drops everything`() {
        val q = PermissionQueue(fire = {})
        q.ask(ask("A", 1))
        q.ask(ask("B", 2))
        q.reset()
        assertNull(q.open)
        assertEquals(0, q.queued)
    }

    @Test fun `223-23 source only fireAsk calls Android`() {
        val all = main.walkTopDown().filter { it.name.endsWith(".kt") }.flatMap { f ->
            f.readLines().filter { l -> val t = l.trim(); !t.startsWith("*") && !t.startsWith("//") && t.contains("requestPermissions(") }
                .map { "${f.name}:${it.trim()}" }
        }.toList()
        assertEquals(listOf("MainActivity.kt:requestPermissions(a.permissions, a.code)"), all)
        val m = src("MainActivity.kt")
        assertTrue(m.contains("permQueue.answered(requestCode"))
        assertTrue(m.contains("askPermissions(permName(requestCode), permissions, requestCode)"))
    }
}
