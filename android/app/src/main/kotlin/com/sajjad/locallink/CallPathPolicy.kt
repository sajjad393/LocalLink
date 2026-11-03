package com.sajjad.locallink

/**
 * Bundle 192 (logs only): which way the call voice travels.
 *
 * `CALL_PATH call=<id> at=start|change path=<p> hops=<n> via=<id6> udp=y|n`
 * - path: lan (same Wi-Fi router), wifi_direct (phone to phone),
 *   local_net (another phone's group/hotspot joined as Wi-Fi),
 *   mesh (through another phone), none (no way right now).
 * - hops: 1 = straight to the other phone, 2+ = through middle phones.
 * - via: the next phone when the voice goes through a middle phone.
 * - udp: the fast way (y) or the steady way through the link (n).
 */
object CallPathPolicy {
    const val CHECK_EVERY_MS = 2_000L

    data class Path(val kind: String, val hops: Int, val via: String, val udp: Boolean)

    /** Path word from the direct link's transport name, or the relay route. */
    // Bundle 205 (P1, L2): a `lan` link inside a Wi-Fi Direct group
    // (192.168.49.x) is Wi-Fi Direct, not a router.
    fun kind(directTransport: String?, hasRoute: Boolean, remoteAddress: String? = null): String = when (directTransport?.trim()?.lowercase()) {
        "lan" -> if (LinkKindPolicy.onP2pNetwork(remoteAddress)) "wifi_direct" else "lan"
        "wifi_direct" -> "wifi_direct"
        "local_net" -> "local_net"
        null, "" -> if (hasRoute) "mesh" else "none"
        else -> directTransport.trim().lowercase()
    }

    fun shortId(id: String?): String = id?.trim()?.takeIf { it.isNotEmpty() }?.takeLast(6) ?: "-"

    /** A new line is due only when something a reader cares about changed. */
    fun changed(old: Path?, new: Path): Boolean = old == null || old != new

    fun line(callId: String, moment: String, p: Path): String =
        "CALL_PATH call=$callId at=$moment path=${p.kind} hops=${p.hops} via=${p.via} udp=${if (p.udp) "y" else "n"}"

    /** Path changes away from a direct link are worth a `!` in the log file. */
    fun warn(old: Path?, new: Path): Boolean =
        old != null && (new.kind == "none" || (old.hops <= 1 && new.hops > 1))
}

/**
 * Bundle 192 (logs only): the Wi-Fi Direct link around a call.
 *
 * `WD_LINK at=<moment> group=y|n role=owner|client members=<n> freq=<MHz> band=2.4|5|6|-`
 * - moment: call_start, call_end, drop_in_call (link lost while a call is on),
 *   up_in_call (link came back while a call is on).
 * - members: phones joined to this owner (owner only, else -).
 */
object WdLinkPolicy {
    fun band(freqMhz: Int): String = when (freqMhz) {
        in 2400..2500 -> "2.4"
        in 4900..5900 -> "5"
        in 5925..7125 -> "6"
        else -> "-"
    }

    fun line(moment: String, formed: Boolean, owner: Boolean, members: Int, freqMhz: Int): String {
        if (!formed) return "WD_LINK at=$moment group=n"
        val role = if (owner) "owner" else "client"
        val m = if (owner && members >= 0) members.toString() else "-"
        val f = if (freqMhz > 0) freqMhz.toString() else "-"
        return "WD_LINK at=$moment group=y role=$role members=$m freq=$f band=${band(freqMhz)}"
    }

    /** Moment word for a group change during a call, or null when not worth a line. */
    fun changeInCall(inCall: Boolean, wasFormed: Boolean?, nowFormed: Boolean): String? = when {
        !inCall || wasFormed == null || wasFormed == nowFormed -> null
        nowFormed -> "up_in_call"
        else -> "drop_in_call"
    }
}
