package com.sajjad.locallink

/**
 * Bundle 175 (4): Wi-Fi up/down and internet on/off, seen from inside the
 * transport service. A local network is not the internet: Wi-Fi with no
 * internet (or a phone hotspot without data) is still good for nearby links.
 * Changes are debounced so a flapping network acts once.
 */
object NetworkChangePolicy {
    /** [wifiKey] names the Wi-Fi network(s): a router change is a new Wi-Fi. */
    data class Snapshot(val wifi: Boolean, val internet: Boolean, val wifiKey: String = "")
    data class Action(val wifiUp: Boolean, val wifiDown: Boolean, val internetChanged: Boolean) {
        val any: Boolean get() = wifiUp || wifiDown || internetChanged
    }

    const val DEBOUNCE_MS = 2_000L

    /** The first snapshot is only the starting point (null action). */
    fun decide(previous: Snapshot?, next: Snapshot): Action? {
        if (previous == null) return null
        val action = Action(
            wifiUp = next.wifi && (!previous.wifi || previous.wifiKey != next.wifiKey),
            wifiDown = previous.wifi && !next.wifi,
            internetChanged = previous.internet != next.internet,
        )
        return if (action.any) action else null
    }
}
