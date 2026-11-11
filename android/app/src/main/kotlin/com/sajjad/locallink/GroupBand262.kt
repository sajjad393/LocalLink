package com.sajjad.locallink

/**
 * Bundle 262 (A): Wi-Fi Direct groups on 2.4 GHz.
 *
 * With the router on, Android puts a new group on the router's channel
 * (2422 MHz on 11 Nov). With the router off it picked 5745 MHz on the C71,
 * and the ZTE Blade A35 (Wi-Fi b/g/n = 2.4 GHz only) never saw that group:
 * every ZTE join timed out while it joined the TECNO's 2.4 GHz group at once.
 * `WifiP2pConfig.Builder.setGroupOperatingBand` (Android 10+) asks for 2.4 GHz.
 * A phone that refuses the band gets one more try without it, so no phone
 * loses Wi-Fi Direct. Voice and chat need far less than 2.4 GHz gives.
 */
object GroupBand262 {
    /** Same value as `WifiP2pConfig.GROUP_OWNER_BAND_2GHZ`. */
    const val BAND_2GHZ = 1

    /** `WifiP2pManager.BUSY`: busy has nothing to do with the band. */
    const val REASON_BUSY = 2

    /** Ask for 2.4 GHz (the builder needs Android 10+). */
    fun wants(sdk: Int): Boolean = sdk >= 29

    /** A create that failed WITH the band is tried once more without it
     *  (not when Wi-Fi Direct was only busy). */
    fun mayRetry(withBand: Boolean, reason: Int): Boolean = withBand && reason != REASON_BUSY

    fun createLine(name: String, band: Boolean): String =
        "group create grp=$name band=${if (band) "2.4" else "any"}"

    fun retryLine(what: String, reason: Int): String = "$what retry no_band reason=$reason"
}

/** Bundle 262 (B1): the log line when the phone turns Wi-Fi Direct off / on. */
object P2pState262 {
    /** null when nothing changed. [prev] null = the first report since start
     *  (only an OFF is worth a line then). [offAtMs] = when it went off. */
    fun line(prev: Boolean?, now: Boolean, offAtMs: Long, nowMs: Long): String? = when {
        prev == now -> null
        prev == null -> if (now) null else "WD_P2P state=off first=1"
        !now -> "WD_P2P state=off"
        else -> "WD_P2P state=on off_s=${if (offAtMs > 0 && nowMs >= offAtMs) (nowMs - offAtMs) / 1000 else -1}"
    }
}

/** Bundle 262 (B3): "busy" answers that mean Wi-Fi Direct is stuck. */
object Busy262 {
    const val COUNT = 3
    const val WINDOW_MS = 90_000L

    /** Keeps [now] and returns true when [COUNT] busy answers fell within
     *  [WINDOW_MS] while Wi-Fi Direct is ON (while it is off, busy is normal). */
    fun add(times: MutableList<Long>, now: Long, p2pOn: Boolean): Boolean {
        if (!p2pOn) {
            times.clear()
            return false
        }
        times.removeAll { now - it >= WINDOW_MS || it > now }
        times.add(now)
        return times.size >= COUNT
    }
}
