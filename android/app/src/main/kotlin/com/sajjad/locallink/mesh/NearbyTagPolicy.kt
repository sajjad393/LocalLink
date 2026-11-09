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
 * Bundle 161 adds (all optional, older phones ignore them):
 *
 *   v6=<host's IPv6 link-local>  hs=<hotspot name>  hk=<hotspot password>
 *   lt=<short id of the group this phone links to>
 *
 * - `v6`: a host's own address inside its group, so a phone that is itself
 *   a host can still reach it from the other group (both use 192.168.49.1).
 * - `hs` / `hk`: this phone runs a LocalLink hotspot (test setting).
 * - `lt`: this phone links its group to another group (test setting), so a
 *   second phone doesn't link the same two groups.
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
        // Bundle 161: linked groups + LocalLink hotspot (tests).
        v6: String? = null,
        hotspotSsid: String? = null,
        hotspotKey: String? = null,
        linkTarget: String? = null,
        // Bundle 167 (5.5): a voice call is going on here (it goes first as
        // the new host when the old host leaves).
        inCall: Boolean = false,
        // Bundle 224 (A4): our own old-way group (Android < 10, no `DIRECT-LL-` name).
        legacyGroup: Boolean = false,
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
        if (txt.containsKey("g") && legacyGroup && !groupName!!.startsWith(NearbyGroupPolicy.NAME_PREFIX)) txt["lg"] = "1"
        val w = cleanWanted(wanted)
        if (w.isNotEmpty()) txt["w"] = w.joinToString(",")
        if (bridge && (host || member)) txt["br"] = "1"
        if (charging) txt["pwr"] = "1"
        if (wifi) txt["wf"] = "1"
        if (host && LocalNetPolicy.validV6(v6)) txt["v6"] = v6!!
        if (LocalNetPolicy.validSsid(hotspotSsid) && LocalNetPolicy.validKey(hotspotKey)) {
            txt["hs"] = hotspotSsid!!
            txt["hk"] = hotspotKey!!
        }
        if ((host || member) && LocalNetPolicy.validLinkId(linkTarget)) txt["lt"] = linkTarget!!
        if (inCall) txt["call"] = "1"
        return txt
    }

    // ---------------------------------------------------------------- 223 (F)
    // Android sends a service in 2 parts: the name (PTR) and the details
    // (TXT). On the Realme C71 / ZTE A35 the TXT never arrived (`heard=0` in
    // every window), and the name was always the plain INSTANCE_NAME, which says nothing.
    // Now the published name carries a short tag: `LinkUp-<id 8>-<flags>`
    // (flags: h = host, m = member, w = wants a link; n = none). The service
    // type `_locallink._tcp` stays (older phones search for it and never read
    // the name). A name tag has NO group name / password, so it only fills
    // the nearby list (never a silent group join).

    const val NAME_PREFIX = "LinkUp-"
    /** No TXT this long after a PTR -> one exact TXT request for that phone. */
    const val TXT_ASK_AFTER_MS = 2_000L
    /** An unchanged name tag goes to Dart again after this long (Q16). */
    const val NAME_REEMIT_MS = 30_000L
    private val namePattern = Regex("^LinkUp-([0-9a-f]{8})-([hmwn]{1,3})$")

    fun encodeName(id: String, host: Boolean, member: Boolean, wantsLink: Boolean): String {
        val short = id.trim().lowercase().take(WANTED_ID_LENGTH)
        val flags = buildString {
            if (host) append('h')
            if (member && !host) append('m')
            if (wantsLink) append('w')
        }.ifEmpty { "n" }
        return "$NAME_PREFIX$short-$flags"
    }

    /** True for an old phone's plain name (222 and before). */
    fun isOldName(name: String?): Boolean = name?.trim() == INSTANCE_NAME

    /** A LinkUp service name: the new name tag or the old plain name. */
    fun isLinkUpName(name: String?): Boolean = isOldName(name) || decodeNameParts(name) != null

    private fun decodeNameParts(name: String?): Pair<String, String>? {
        val m = namePattern.matchEntire(name?.trim() ?: return null) ?: return null
        val id = m.groupValues[1]
        val flags = m.groupValues[2]
        if (flags.contains('n') && flags.length > 1) return null
        if (flags.toSet().size != flags.length) return null
        if (flags.contains('h') && flags.contains('m')) return null
        return id to flags
    }

    /** A name tag -> a small tag map (`from_name`=true, no group / key), else null. */
    fun decodeName(instanceName: String?, address: String?, now: Long): Map<String, Any>? {
        if (address.isNullOrBlank()) return null
        val (id, flags) = decodeNameParts(instanceName) ?: return null
        val host = flags.contains('h')
        return linkedMapOf(
            "address" to address.trim().lowercase(),
            "id" to id,
            "host" to host,
            "member" to (flags.contains('m') && !host),
            "members" to 0,
            "full" to false,
            "seen_at" to now,
            "gv" to true,
            "from_name" to true,
            "wants_link" to flags.contains('w'),
        )
    }

    fun tagIsStale(tag: Map<String, Any>?, now: Long): Boolean =
        tag == null || now - ((tag["seen_at"] as? Long) ?: 0L) > TAG_MAX_AGE_MS

    /**
     * Q16: should this name tag replace [prev] and go to Dart? A fresh full
     * (TXT) tag always wins; a changed name tag goes at once; an unchanged
     * one again after [NAME_REEMIT_MS] (so Dart's "seen" time stays fresh).
     */
    fun nameShouldEmit(prev: Map<String, Any>?, next: Map<String, Any>, now: Long): Boolean {
        if (prev == null || tagIsStale(prev, now)) return true
        if (prev["from_name"] != true) return false
        if (prev["id"] != next["id"] || prev["host"] != next["host"] ||
            prev["member"] != next["member"] || prev["wants_link"] != next["wants_link"]) return true
        return now - ((prev["seen_at"] as? Long) ?: 0L) >= NAME_REEMIT_MS
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
        // Bundle 224 (A4): only a LinkUp group can be joined - a `DIRECT-LL-`
        // name, or an old-way group marked `lg=1`. A Realme Share / XShare
        // group (also from a phone still on 223) is dropped; the phone itself
        // is still seen.
        val linkUpGroup = (host || member) && NearbyGroupPolicy.validNetworkName(group) &&
            (group!!.startsWith(NearbyGroupPolicy.NAME_PREFIX) || txt["lg"] == "1")
        if (linkUpGroup) tag["group"] = group!!
        val key = txt["k"]
        if (linkUpGroup && host && NearbyGroupPolicy.validPassphrase(key)) tag["key"] = key!!
        val wanted = cleanWanted(txt["w"]?.split(","))
        if (wanted.isNotEmpty()) tag["wanted"] = wanted
        // Bundle 158: the group's bridge (only meaningful in a group).
        if (txt["br"] == "1" && (host || member)) tag["bridge"] = true
        // Bundle 159: on a charger.
        if (txt["pwr"] == "1") tag["charging"] = true
        // Bundle 160: on a normal Wi-Fi network.
        if (txt["wf"] == "1") tag["wifi"] = true
        // Bundle 161: linked groups + LocalLink hotspot.
        val v6 = txt["v6"]?.trim()?.lowercase()
        if (host && LocalNetPolicy.validV6(v6)) tag["v6"] = v6!!
        val hs = txt["hs"]
        val hk = txt["hk"]
        if (LocalNetPolicy.validSsid(hs) && LocalNetPolicy.validKey(hk)) {
            tag["hotspot_ssid"] = hs!!
            tag["hotspot_key"] = hk!!
        }
        val lt = txt["lt"]?.trim()?.lowercase()
        if ((host || member) && LocalNetPolicy.validLinkId(lt)) tag["link_target"] = lt!!
        // Bundle 167: a voice call is going on there.
        if (txt["call"] == "1") tag["in_call"] = true
        return tag
    }
}

/**
 * Bundle 224 (D1): asking a phone for its tag details (TXT) once was not
 * enough - on 2026-11-07 02:11:37 the one ask got no answer and the join
 * waited for the next search (35 s). Ask up to 3 times, 4 s apart, in the
 * same search window. The search timing itself is unchanged.
 */
object TxtAskPolicy {
    const val MAX_TRIES = 3
    const val GAP_MS = 4_000L
    /** WifiP2pManager.BUSY */
    const val REASON_BUSY = 2

    fun shouldAsk(triesDone: Int, lastAskAt: Long, now: Long, txtSeen: Boolean): Boolean =
        !txtSeen && triesDone < MAX_TRIES && (now - lastAskAt >= GAP_MS - 50L || now < lastAskAt)

    /** BUSY = the radio is busy: no more extra asks in this window. */
    fun stopOnFailure(reason: Int): Boolean = reason == REASON_BUSY
}
