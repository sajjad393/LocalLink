package com.sajjad.locallink

/**
 * Bundle 201 (A3, logs only): the Wi-Fi Direct group was there and now is
 * gone. One line says if this phone was the host or a member, if Wi-Fi Direct
 * is still on, and what Android last said about the link.
 */
object WdGroupLost {
    /** True only for "was formed" -> "not formed". */
    fun lost(prevFormed: Boolean?, nowFormed: Boolean): Boolean = prevFormed == true && !nowFormed

    fun detail(state: String?, reason: String?, extra: String?): String =
        "state=${clean(state)} reason=${clean(reason)} extra=${clean(extra)}"

    fun line(wasOwner: Boolean, p2pOn: Boolean, detail: String): String =
        "WD_GROUP_LOST was=${if (wasOwner) "host" else "member"} p2p=${if (p2pOn) "on" else "off"} $detail"

    /** Bundle 205 (P6): the line with a best guess of who ended the group. */
    fun line(wasOwner: Boolean, p2pOn: Boolean, detail: String, why: String): String =
        "${line(wasOwner, p2pOn, detail)} why=$why"

    /**
     * Bundle 205 (P6, L9): who ended the group (best guess):
     * `p2p_off` (Wi-Fi Direct switched off), `self` (this phone left / closed
     * it), `after_search` (a search started shortly before), `app_close`
     * (the app screen closed shortly before), else `other_or_system`.
     */
    fun why(now: Long, p2pOn: Boolean, selfChangeAt: Long, searchAt: Long, appCloseAt: Long): String = when {
        !p2pOn -> "p2p_off"
        selfChangeAt > 0L && now - selfChangeAt in 0..15_000L -> "self"
        searchAt > 0L && now - searchAt in 0..20_000L -> "after_search"
        appCloseAt > 0L && now - appCloseAt in 0..15_000L -> "app_close"
        else -> "other_or_system"
    }

    private fun clean(v: String?): String {
        val t = v?.trim().orEmpty()
        if (t.isEmpty()) return "-"
        return t.replace(Regex("\\s+"), "_").take(40)
    }
}
