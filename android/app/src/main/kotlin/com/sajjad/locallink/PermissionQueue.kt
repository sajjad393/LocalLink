package com.sajjad.locallink

/**
 * Bundle 223 (I): ONE queue for every runtime-permission pop-up.
 *
 * Android DROPS a second requestPermissions() while a pop-up is open
 * ("Can request only one set of permissions at a time", ZTE 07:47:36).
 * Every ask goes through here: the first one fires at once, later ones wait
 * and fire after the answer, so none is lost. Pure Kotlin (JVM tests).
 *
 * Logs: PERM_ASK name=.. code=.., PERM_QUEUED name=.. behind=..,
 * PERM_ANSWER name=.. granted=y|n|timeout.
 */
class PermissionQueue(
    private val fire: (Ask) -> Unit,
    private val log: (String) -> Unit = {},
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    class Ask(val name: String, val permissions: Array<String>, val code: Int)

    private val waiting = ArrayDeque<Ask>()
    private var openedAt = 0L

    /** The pop-up on screen now, or null. */
    var open: Ask? = null
        private set

    val queued: Int get() = waiting.size

    /** Asks now, or after the pop-up that is open. The same ask twice is kept once. */
    fun ask(a: Ask) {
        val current = open
        if (current != null && now() - openedAt > STUCK_MS) {
            // No answer came (screen rebuilt, Android lost it): move on.
            log("PERM_ANSWER name=${current.name} granted=timeout")
            open = null
        }
        val showing = open
        if (showing == null) {
            fireNow(a)
            return
        }
        if (same(showing, a) || waiting.any { same(it, a) }) return
        waiting.addLast(a)
        log("PERM_QUEUED name=${a.name} behind=${showing.name}")
    }

    /** Android answered [code]. Returns the ask it belonged to (or null). */
    fun answered(code: Int, granted: Boolean): Ask? {
        val a = open ?: return null
        if (a.code != code) return null
        log("PERM_ANSWER name=${a.name} granted=${if (granted) "y" else "n"}")
        open = null
        val next = waiting.removeFirstOrNull()
        if (next != null) fireNow(next)
        return a
    }

    /** The screen is gone: nothing can be answered any more. */
    fun reset() {
        open = null
        waiting.clear()
    }

    private fun fireNow(a: Ask) {
        open = a
        openedAt = now()
        log("PERM_ASK name=${a.name} code=${a.code}")
        try {
            fire(a)
        } catch (e: Exception) {
            log("PERM_ANSWER name=${a.name} granted=n error=${e.javaClass.simpleName}")
            open = null
            val next = waiting.removeFirstOrNull()
            if (next != null) fireNow(next)
        }
    }

    private fun same(x: Ask, y: Ask) = x.code == y.code && x.permissions.contentEquals(y.permissions)

    companion object {
        /** No answer in this long = the pop-up is treated as gone. */
        const val STUCK_MS = 60_000L

        /** How long the Dart gate waits for one answer at most. */
        const val GATE_LIMIT_MS = 60_000L
    }
}
