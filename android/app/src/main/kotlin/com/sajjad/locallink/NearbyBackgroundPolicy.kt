package com.sajjad.locallink

/**
 * Bundle 177: pure rules for Nearby while LocalLink is closed (no Android
 * types, unit-tested in Nearby177Test).
 *
 * The search speed itself (3 min / 10 min under 20% / stop at 10%) is decided
 * in Dart (`NearbySearchCadence`); here are only the closed-app limits.
 */
object NearbyBackgroundPolicy {
    /** What the no-screen engine may ask the Wi-Fi Direct owner (3.2). */
    val BG_ALLOWED: Set<String> = setOf(
        "isSupported", "hasPermission", "isEnabled",
        "discoverPeers", "getPeers", "getNearbyTags", "connectionInfo",
        "setNearbyIdentity", "setNearbyWanted", "setNearbyInCall",
        // Q3: a closed phone can join AND start a group (both silent).
        "createNearbyGroup", "joinNearbyGroup",
        // Leaving / stopping is always silent and saves battery (an empty
        // group nobody joined closes itself).
        "disconnect", "cancelConnect", "leaveLocalNet", "stopLocalHotspot",
        "localNetStatus", "dispose",
    )

    /** Everything else (pop-ups, hotspot, linked groups) needs the open app. */
    fun isAllowed(method: String): Boolean = method in BG_ALLOWED

    /** 10% or less and not charging: no search (Q2). */
    const val BATTERY_STOP_LEVEL = 10

    /** Lost Wi-Fi Direct channel: at most 3 new setups per 10 minutes. */
    const val REINIT_MAX = 3
    const val REINIT_WINDOW_MS = 10 * 60 * 1000L
    const val REINIT_DELAY_MS = 5_000L

    /** Drops setups older than the window from [times]; returns how many are left. */
    fun recentReinits(times: MutableList<Long>, now: Long): Int {
        times.removeAll { now - it >= REINIT_WINDOW_MS || it > now }
        return times.size
    }

    fun mayReinit(recent: Int): Boolean = recent < REINIT_MAX
}
