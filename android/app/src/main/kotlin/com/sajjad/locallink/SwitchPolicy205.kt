package com.sajjad.locallink

/**
 * Bundle 205: rules for smooth switching between Wi-Fi, Wi-Fi Direct, Mesh
 * and Online. Pure, so they are easy to check.
 */

/**
 * Bundle 205 (P1): the real way a direct link goes.
 *
 * A link found by the LAN beacons is called `lan`, but inside a Wi-Fi Direct
 * group the beacons run on the group's own network (192.168.49.x, interface
 * `p2p-*`). That is phone to phone, not a router: it is Wi-Fi Direct. A
 * linked group / LocalLink hotspot (`local_net`) is phone to phone too.
 */
object LinkKindPolicy {
    const val P2P_PREFIX = "192.168.49."

    /** Wait this long after a link was made before an "not connected" note
     *  may close Wi-Fi Direct links (a late, stale note closed a fresh link). */
    const val STALE_DISCONNECT_GUARD_MS = 5_000L

    fun onP2pNetwork(remoteAddress: String?, localIface: String? = null): Boolean {
        val addr = remoteAddress?.trim()?.removePrefix("/").orEmpty()
        if (addr.startsWith(P2P_PREFIX)) return true
        return localIface?.trim()?.lowercase()?.startsWith("p2p") == true
    }

    /** `lan` | `wifi_direct` | other transport names unchanged. */
    fun pathKind(transport: String?, remoteAddress: String?, localIface: String? = null): String {
        val t = transport?.trim()?.lowercase().orEmpty()
        return when (t) {
            "lan" -> if (onP2pNetwork(remoteAddress, localIface)) "wifi_direct" else "lan"
            "local_net" -> "wifi_direct"
            else -> t
        }
    }

    /** A "Wi-Fi Direct not connected" note may close the Wi-Fi Direct links
     *  only when no Wi-Fi Direct link was made in the last 5 s. */
    fun mayCloseOnDisconnect(lastLinkAt: Long, now: Long): Boolean =
        lastLinkAt <= 0L || now - lastLinkAt >= STALE_DISCONNECT_GUARD_MS

    /** My Wi-Fi (router) went off: a router link can't live on. Links inside
     *  a Wi-Fi Direct group stay. */
    fun dropOnWifiDown(transport: String?, remoteAddress: String?): Boolean =
        transport?.trim()?.lowercase() == "lan" && !onP2pNetwork(remoteAddress)

    fun fixedLine(peer: String, was: String, now: String): String =
        "LINK_KIND_FIXED peer=${peer.takeLast(8)} was=$was now=$now"
}

/**
 * Bundle 205 (P3): only a real router (or a phone hotspot) counts as
 * "on Wi-Fi". Some phones list their own Wi-Fi Direct group as a restricted
 * Wi-Fi network - that gave a false `router_back` (logs 21:09:50).
 */
object RouterNetworkPolicy {
    fun isRouter(
        wifiTransport: Boolean,
        notRestricted: Boolean,
        iface: String?,
        ownedByLocalNet: Boolean,
        ipv4: List<String> = emptyList(),
    ): Boolean {
        if (!wifiTransport || !notRestricted || ownedByLocalNet) return false
        if (iface?.trim()?.lowercase()?.startsWith("p2p") == true) return false
        if (ipv4.any { it.trim().removePrefix("/").startsWith(LinkKindPolicy.P2P_PREFIX) }) return false
        return true
    }
}

/**
 * Bundle 205 (P2): keep the phone awake for a short time after a nearby
 * link broke, so the search, the friend group and the queue run with the
 * app closed and the screen off (logs: the ZTE slept 2.5 min and 5 min).
 *
 * At most [HOLD_MS] per break, ended at once when a link is back. After a
 * hold that found nobody, no new hold for [REST_MS] (battery). Never at 10%
 * battery or less unless charging.
 */
object ReconnectWakePolicy {
    const val HOLD_MS = 5 * 60_000L
    const val REST_MS = 10 * 60_000L
    const val STOP_BATTERY = 10

    fun mayStart(now: Long, holding: Boolean, lastTimeoutAt: Long, batteryLevel: Int, charging: Boolean): Boolean {
        if (holding) return false
        if (!charging && batteryLevel in 0..STOP_BATTERY) return false
        if (lastTimeoutAt > 0L && now - lastTimeoutAt < REST_MS) return false
        return true
    }

    fun onLine(why: String) = "RECONNECT_WAKE on why=$why hold_s=${HOLD_MS / 1000}"
    fun offLine(why: String, heldMs: Long) = "RECONNECT_WAKE off why=$why after_s=${(heldMs / 1000).coerceAtLeast(0)}"
    fun skipLine(why: String, reason: String) = "RECONNECT_WAKE skip why=$why reason=$reason"

    fun skipReason(now: Long, holding: Boolean, lastTimeoutAt: Long, batteryLevel: Int, charging: Boolean): String = when {
        holding -> "holding"
        !charging && batteryLevel in 0..STOP_BATTERY -> "battery"
        lastTimeoutAt > 0L && now - lastTimeoutAt < REST_MS -> "rest"
        else -> "none"
    }
}
