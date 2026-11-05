package com.sajjad.locallink

/**
 * Bundle 210: "Share LinkUp" (give the app to a nearby phone over a local
 * hotspot, no internet). Pure functions only, so they can be checked alone.
 */
object AppSharePolicy {
    const val OWNER_MESH = "mesh"
    const val OWNER_SHARE = "share"

    /** How long Android may take to start the hotspot. */
    const val START_TIMEOUT_MS = 15_000L
    /** After the hotspot is on, how long we look for its new address. */
    const val ADDRESS_WAIT_MS = 3_000L
    const val ADDRESS_STEP_MS = 250L

    /** Interface names phones use for their own hotspot / tethering. */
    private val HOTSPOT_HINTS = listOf("ap", "swlan", "softap", "wlan1", "wlan2", "wigig", "rndis")

    /** True when the app was installed in parts (can't be shared as one file). */
    fun isSplit(splits: Array<String>?): Boolean = !splits.isNullOrEmpty()

    /** Android's LocalOnlyHotspot failure code / our words → one reason word. */
    fun reasonFor(failure: String?): String = when (failure) {
        null, "" -> "error"
        "incompatible_mode" -> "own_hotspot"
        "tethering_disallowed" -> "blocked"
        "no_channel", "generic" -> "couldnt_start"
        "permission", "location_off", "wifi_off", "timeout", "stopped", "no_name", "no_radio" -> failure
        else -> if (failure.startsWith("error")) "couldnt_start" else failure
    }

    /** SoftApConfiguration security type → Wi-Fi QR type word. */
    fun qrType(securityType: Int?): String = when (securityType) {
        null -> "WPA"
        0 -> "nopass"     // SECURITY_TYPE_OPEN
        1, 2 -> "WPA"     // WPA2_PSK, WPA3_SAE_TRANSITION
        3 -> "SAE"        // WPA3_SAE
        4, 5 -> "nopass"  // WPA3_OWE_TRANSITION, WPA3_OWE (no password)
        else -> "WPA"
    }

    fun looksLikeHotspot(iface: String): Boolean {
        val n = iface.lowercase()
        if (n == "wlan0" || n.startsWith("rmnet") || n.startsWith("lo") || n.startsWith("p2p") || n.startsWith("dummy")) return false
        return HOTSPOT_HINTS.any { n.startsWith(it) }
    }

    fun isPrivateV4(ip: String): Boolean {
        val p = ip.split('.').mapNotNull { it.toIntOrNull() }
        if (p.size != 4) return false
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && p[1] in 16..31)
    }

    /**
     * The hotspot address: (1) a private address that is new since before the
     * start, (2) a private address on a hotspot-looking interface, else null.
     * Wi-Fi Direct group addresses (`p2p*`, 192.168.49.x) never count.
     */
    fun pickHotspotIp(before: Map<String, String>, after: Map<String, String>): String? {
        fun ok(iface: String, ip: String) = isPrivateV4(ip) && !iface.lowercase().startsWith("p2p") &&
            !ip.startsWith("192.168.49.") && iface.lowercase() != "wlan0"
        val fresh = after.filter { (iface, ip) -> ok(iface, ip) && before[iface] != ip }
        fresh.entries.firstOrNull { looksLikeHotspot(it.key) }?.let { return it.value }
        fresh.entries.firstOrNull()?.let { return it.value }
        return after.entries.firstOrNull { ok(it.key, it.value) && looksLikeHotspot(it.key) }?.value
    }
}

/**
 * Bundle 210: who wants the local hotspot on. Mesh (test switch) and Share can
 * both use the same one; it closes only when nobody wants it.
 */
class HotspotOwners {
    private val set = linkedSetOf<String>()

    /** True if [owner] was not there before. */
    @Synchronized fun add(owner: String): Boolean = set.add(owner)
    /** True if [owner] was there. */
    @Synchronized fun remove(owner: String): Boolean = set.remove(owner)
    @Synchronized fun has(owner: String): Boolean = owner in set
    @Synchronized fun isEmpty(): Boolean = set.isEmpty()
    @Synchronized fun list(): List<String> = set.toList()
    /** Empties the set and returns who was in it. */
    @Synchronized fun clear(): List<String> { val l = set.toList(); set.clear(); return l }
}
