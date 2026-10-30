package com.sajjad.locallink.mesh

/**
 * Bundle 161 (plan 160.5 + 160.6): links over a second Wi-Fi network.
 *
 * 1. **Linked groups.** A phone in nearby group B also joins nearby group A
 *    as a normal Wi-Fi user (Android 10+, `WifiNetworkSpecifier`) and opens
 *    one LocalLink link to group A's host. Both groups use `192.168.49.x`, so
 *    the socket is made by that Wi-Fi network (`Network.socketFactory`). A
 *    phone that is itself a host owns `192.168.49.1`, so it can only reach
 *    the other host by its IPv6 link-local address (`v6` in the host's tag).
 * 2. **LocalLink hotspot.** One phone starts an Android local-only hotspot
 *    (no internet) and puts its name + password in its nearby tag. Others
 *    join it the same way and link to the hotspot phone.
 *
 * Both are tests (off by default). Android shows its own "Connect to this
 * network?" box each time a phone joins. Pure functions only.
 */
object LocalNetPolicy {
    const val KIND_GROUP = "group"
    const val KIND_HOTSPOT = "hotspot"

    /** Max non-contact (sealed only) links over local networks. */
    const val MAX_RELAY_LINKS = 10
    /** How long Android may take to join (the user may need to tap OK). */
    const val JOIN_TIMEOUT_MS = 45_000
    /** A dropped link is tried again while the network is still there. */
    const val RETRY_MS = 5_000L
    const val MAX_RETRIES = 6

    private val ssidPattern = Regex("^[\\x20-\\x7e]{1,32}$")
    private val keyPattern = Regex("^[\\x21-\\x7e]{8,63}$")
    private val v6Pattern = Regex("^fe80:[0-9a-f:]{2,34}$")
    private val ipv4Pattern = Regex("^(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(\\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])){3}$")
    private val linkIdPattern = Regex("^[0-9a-f]{8}$")

    fun validKind(kind: String?): Boolean = kind == KIND_GROUP || kind == KIND_HOTSPOT

    /** Printable ASCII, no commas (the TXT record uses them), max 32. */
    fun validSsid(ssid: String?): Boolean =
        ssid != null && ssidPattern.matches(ssid) && !ssid.contains(',') && ssid.trim() == ssid

    fun validKey(key: String?): Boolean = key != null && keyPattern.matches(key) && !key.contains(',')

    /** An IPv6 link-local address without scope (`fe80::1:2:3:4`). */
    fun validV6(addr: String?): Boolean {
        if (addr == null || !v6Pattern.matches(addr)) return false
        if (addr.count { it == ':' } > 7) return false
        return !addr.contains(":::")
    }

    fun validIpv4(addr: String?): Boolean = addr != null && ipv4Pattern.matches(addr)

    /** `lt` in the tag: the short id of the group this phone links to. */
    fun validLinkId(id: String?): Boolean = id != null && linkIdPattern.matches(id)

    /** Android sometimes wraps SSIDs and keys in quotes. */
    fun unquote(text: String?): String? {
        val t = text?.trim() ?: return null
        return if (t.length >= 2 && t.startsWith("\"") && t.endsWith("\"")) t.substring(1, t.length - 1) else t
    }

    /**
     * Where to dial, best first: the IPv6 link-local of the other host (works
     * even when both phones are hosts), then the network's gateway and DHCP
     * server. An address this phone owns itself is skipped (it would only
     * reach its own server).
     */
    fun candidates(v6: String?, gateway: String?, dhcpServer: String?, ownAddresses: Set<String>): List<String> {
        val out = LinkedHashSet<String>()
        if (validV6(v6)) out += v6!!.lowercase()
        for (a in listOf(gateway, dhcpServer)) {
            val clean = a?.trim()?.removePrefix("/") ?: continue
            if (validIpv4(clean) && clean != "0.0.0.0" && clean !in ownAddresses) out += clean
        }
        return out.toList()
    }

    /** Retry a dropped link? Only while the network is still there. */
    fun shouldRetry(networkAvailable: Boolean, retries: Int, left: Boolean): Boolean =
        networkAvailable && !left && retries < MAX_RETRIES

    /** Android's local-only hotspot failure codes, as short log words. */
    fun hotspotFailure(reason: Int): String = when (reason) {
        1 -> "no_channel"
        2 -> "generic"
        3 -> "incompatible_mode"
        4 -> "tethering_disallowed"
        else -> "error_$reason"
    }
}
