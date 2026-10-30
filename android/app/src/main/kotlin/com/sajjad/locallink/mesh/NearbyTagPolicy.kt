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
 * Bundle 157 (one shared group) adds optional keys; 155 phones ignore them:
 *
 *   gv=1  g=<group network name>  k=<group password, host only>  w=<wanted ids>
 *
 * - `gv=1`: this app joins shared groups by itself (no pop-ups).
 * - `g`: the Wi-Fi Direct group this phone hosts or is a member of.
 * - `k`: the host's group password, so others join without a pop-up
 *   (Android 10+). Joining the radio group alone gives no access: every link
 *   still needs the authenticated handshake, and messages are sealed (156).
 * - `w`: up to 3 short ids (first 8 hex chars) of people this phone wants in
 *   its group (a Pair tap, or contacts with messages waiting).
 *
 * Bundle 158 adds `br=1`: this phone is the group's BRIDGE (it is also on a
 * normal Wi-Fi network and passes messages between the two). Only sent by a
 * phone in a group; older phones ignore it.
 *
 * Bundle 159 adds `pwr=1`: this phone is on a charger, so on a tie it is
 * preferred as host or bridge (battery care). Older phones ignore it.
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

    /** Bundle 157: max people in the `w` (wanted) list. */
    const val MAX_WANTED = 3
    const val WANTED_ID_LENGTH = 8
    private val wantedPattern = Regex("^[0-9a-f]{8}$")

    fun encode(
        id: String,
        host: Boolean,
        member: Boolean,
        members: Int,
        groupName: String? = null,
        groupKey: String? = null,
        wanted: List<String> = emptyList(),
        bridge: Boolean = false,
        charging: Boolean = false,
        // Bundle 160: on a normal Wi-Fi network (blocked Wi-Fi check).
        wifi: Boolean = false,
    ): Map<String, String> {
        val n = members.coerceIn(0, 64)
        val txt = linkedMapOf(
            "v" to VERSION,
            "id" to id,
            "host" to if (host) "1" else "0",
            "m" to if (member && !host) "1" else "0",
            "n" to (if (host) n else 0).toString(),
            "full" to if (host && n >= GROUP_SOFT_LIMIT) "1" else "0",
            "gv" to "1",
        )
        if ((host || member) && NearbyGroupPolicy.validNetworkName(groupName)) txt["g"] = groupName!!
        if (host && NearbyGroupPolicy.validPassphrase(groupKey)) txt["k"] = groupKey!!
        val w = cleanWanted(wanted)
        if (w.isNotEmpty()) txt["w"] = w.joinToString(",")
        if (bridge && (host || member)) txt["br"] = "1"
        if (charging) txt["pwr"] = "1"
        if (wifi) txt["wf"] = "1"
        return txt
    }

    fun cleanWanted(wanted: List<String>?): List<String> = (wanted ?: emptyList())
        .map { it.trim().lowercase().take(WANTED_ID_LENGTH) }
        .filter { wantedPattern.matches(it) }
        .distinct()
        .take(MAX_WANTED)

    /** Returns null for anything that is not a valid LocalLink v1 tag. */
    fun decode(fullDomainName: String?, txt: Map<String, String>?, address: String?, now: Long): Map<String, Any>? {
        if (txt == null || address.isNullOrBlank()) return null
        if (fullDomainName != null && !fullDomainName.lowercase().contains(SERVICE_TYPE)) return null
        if (txt["v"] != VERSION) return null
        val id = txt["id"]?.trim()?.lowercase()
        if (!validId(id)) return null
        val n = txt["n"]?.toIntOrNull()?.coerceIn(0, 64) ?: 0
        val host = txt["host"] == "1"
        val member = txt["m"] == "1"
        val tag = linkedMapOf<String, Any>(
            "address" to address.trim().lowercase(),
            "id" to id!!,
            "host" to host,
            "member" to member,
            "members" to n,
            "full" to (txt["full"] == "1"),
            "seen_at" to now,
            // Bundle 157 (optional keys).
            "gv" to (txt["gv"] == "1"),
        )
        val group = txt["g"]
        if ((host || member) && NearbyGroupPolicy.validNetworkName(group)) tag["group"] = group!!
        val key = txt["k"]
        if (host && NearbyGroupPolicy.validPassphrase(key)) tag["key"] = key!!
        val wanted = cleanWanted(txt["w"]?.split(","))
        if (wanted.isNotEmpty()) tag["wanted"] = wanted
        // Bundle 158: the group's bridge (only meaningful in a group).
        if (txt["br"] == "1" && (host || member)) tag["bridge"] = true
        // Bundle 159: on a charger.
        if (txt["pwr"] == "1") tag["charging"] = true
        // Bundle 160: on a normal Wi-Fi network.
        if (txt["wf"] == "1") tag["wifi"] = true
        return tag
    }
}
