package com.sajjad.locallink.mesh

/**
 * Bundle 155: "who is who" tags on Wi-Fi Direct (DNS-SD TXT record).
 *
 * Android's Wi-Fi Direct peer list only shows a phone model name and a MAC
 * address, so the app could not tell WHICH LocalLink person a nearby phone
 * is. Every LocalLink phone now advertises a tiny TXT record:
 *
 *   v=1  id=<short hash of the device id>  host=0|1  m=0|1  n=<members>  full=0|1
 *
 * - `id` is a hash (never the raw device id). The real identity is still
 *   proven by the authenticated transport handshake after connecting.
 * - `host=1`: this phone is the group host (group owner).
 * - `m=1`: this phone is a MEMBER of someone else's group (others must not
 *   pull it away — that would break its routes).
 * - `n`: members in the host's group; `full=1` at the soft limit.
 *
 * Pure functions only, so the rules are easy to check.
 */
object NearbyTagPolicy {
    const val SERVICE_TYPE = "_locallink._tcp"
    const val INSTANCE_NAME = "LocalLink"
    const val VERSION = "1"
    /** D9: soft limit of members per host. Never kick anyone above it. */
    const val GROUP_SOFT_LIMIT = 8
    /** Tags not refreshed for this long are dropped. */
    const val TAG_MAX_AGE_MS = 5L * 60L * 1000L

    private val idPattern = Regex("^[0-9a-f]{8,32}$")

    fun validId(id: String?): Boolean = id != null && idPattern.matches(id)

    fun encode(id: String, host: Boolean, member: Boolean, members: Int): Map<String, String> {
        val n = members.coerceIn(0, 64)
        return linkedMapOf(
            "v" to VERSION,
            "id" to id,
            "host" to if (host) "1" else "0",
            "m" to if (member && !host) "1" else "0",
            "n" to (if (host) n else 0).toString(),
            "full" to if (host && n >= GROUP_SOFT_LIMIT) "1" else "0",
        )
    }

    /** Returns null for anything that is not a valid LocalLink v1 tag. */
    fun decode(fullDomainName: String?, txt: Map<String, String>?, address: String?, now: Long): Map<String, Any>? {
        if (txt == null || address.isNullOrBlank()) return null
        if (fullDomainName != null && !fullDomainName.lowercase().contains(SERVICE_TYPE)) return null
        if (txt["v"] != VERSION) return null
        val id = txt["id"]?.trim()?.lowercase()
        if (!validId(id)) return null
        val n = txt["n"]?.toIntOrNull()?.coerceIn(0, 64) ?: 0
        return mapOf(
            "address" to address.trim().lowercase(),
            "id" to id!!,
            "host" to (txt["host"] == "1"),
            "member" to (txt["m"] == "1"),
            "members" to n,
            "full" to (txt["full"] == "1"),
            "seen_at" to now,
        )
    }
}
