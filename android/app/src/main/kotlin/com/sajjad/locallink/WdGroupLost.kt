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

    private fun clean(v: String?): String {
        val t = v?.trim().orEmpty()
        if (t.isEmpty()) return "-"
        return t.replace(Regex("\\s+"), "_").take(40)
    }
}
