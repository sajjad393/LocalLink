package com.sajjad.locallink.mesh

import java.security.SecureRandom

/**
 * Bundle 157: one shared Wi-Fi Direct group for all nearby LocalLink phones.
 *
 * The decisions (join / create / merge / new host) are made in Dart next to
 * the 155 rules, so there is only one "brain". This file holds the pure
 * native pieces: group names and passwords, and the guards that keep a
 * group member from being pulled away.
 */
object NearbyGroupPolicy {
    /** Android requires `DIRECT-` + 2 letters/digits; ours add `LL-` + 6. */
    const val NAME_PREFIX = "DIRECT-LL-"
    const val PASSPHRASE_LENGTH = 16
    private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    private val namePattern = Regex("^DIRECT-[A-Za-z0-9]{2}.*$")
    private val passPattern = Regex("^[\\x21-\\x7e]{8,63}$")

    fun validNetworkName(name: String?): Boolean {
        if (name == null || !namePattern.matches(name)) return false
        if (name.toByteArray(Charsets.UTF_8).size > 32) return false
        return name.none { it.code < 0x20 || it == ',' }
    }

    fun validPassphrase(pass: String?): Boolean = pass != null && passPattern.matches(pass)

    /** Bundle 224 (A1): how long after our own old-way create (Android < 10)
     *  the group that forms counts as ours. */
    const val LEGACY_OWN_WINDOW_MS = 60_000L

    /**
     * Bundle 224 (A1): is this Wi-Fi Direct group a LinkUp group? A
     * `DIRECT-LL-` name, or this phone's own old-way group (Android < 10
     * picks the name). Realme Share / XShare / system groups (for example
     * `DIRECT-44-realme C71`, `DIRECT-N7-XSHARE-5G-DGJP8`) are not.
     * [validNetworkName] is unchanged (join and friend code use it).
     */
    fun isLinkUpGroup(name: String?, legacyOwn: Boolean): Boolean {
        if (!validNetworkName(name)) return false
        return name!!.startsWith(NAME_PREFIX) || legacyOwn
    }

    /** Bundle 224 (A2): is [name] our own old-way group? It is when it is the
     *  name we remembered, or the first group formed within 60 s of our
     *  old-way create (then the caller remembers its name). */
    fun legacyOwn(name: String?, ownName: String?, createdAt: Long, now: Long): Boolean {
        if (name.isNullOrEmpty()) return false
        if (ownName != null && name == ownName) return true
        return createdAt > 0L && now >= createdAt && now - createdAt <= LEGACY_OWN_WINDOW_MS
    }

    /** A fresh group name: `DIRECT-LL-` + 6 random characters. */
    fun newNetworkName(random: SecureRandom = SecureRandom()): String =
        NAME_PREFIX + randomText(6, random)

    /** A fresh password for every new group. */
    fun newPassphrase(random: SecureRandom = SecureRandom()): String =
        randomText(PASSPHRASE_LENGTH, random)

    private fun randomText(length: Int, random: SecureRandom): String {
        val out = StringBuilder(length)
        repeat(length) { out.append(ALPHABET[random.nextInt(ALPHABET.length)]) }
        return out.toString()
    }

    /**
     * May this phone start a create/join right now?
     * - A member never leaves its group unless the user asked (Pair tap).
     * - A host only leaves when it was told to (merge into a bigger group).
     */
    fun mayChangeGroup(groupFormed: Boolean, groupOwner: Boolean, leave: Boolean): Boolean =
        !groupFormed || leave

    /** Relay links allowed per transport (156 used 3 for everything). */
    fun maxRelayLinks(transportName: String): Int = when (transportName) {
        MeshTransportPolicy.WIFI_DIRECT -> NearbyTagPolicy.GROUP_SOFT_LIMIT + 1
        // Bundle 161: a hotspot holds non-contacts too (sealed packets only).
        MeshTransportPolicy.LOCAL_NET -> LocalNetPolicy.MAX_RELAY_LINKS
        else -> MeshRelayPolicy.MAX_RELAY_LINKS
    }
}
