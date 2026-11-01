package com.sajjad.locallink

/**
 * Bundle 185 (D1): the Opus self-test answer is kept per phone build + app
 * build, so it does not run again on every start (0.9 s of CPU on the ZTE).
 */
object OpusSelfTestMemory {
    /** "ok|<phone build>|<app build>" -> true/false, or null when it is from another build. */
    fun savedResult(saved: String?, key: String): Boolean? {
        if (saved.isNullOrEmpty()) return null
        val ok = saved.substringBefore('|')
        if (saved.substringAfter('|', "") != key) return null
        return when (ok) { "ok" -> true; "no" -> false; else -> null }
    }

    fun savedValue(ok: Boolean, key: String): String = (if (ok) "ok" else "no") + "|" + key
}
