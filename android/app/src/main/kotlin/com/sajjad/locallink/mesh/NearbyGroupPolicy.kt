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
    fun maxRelayLinks(transportName: String): Int =
        if (transportName == MeshTransportPolicy.WIFI_DIRECT) NearbyTagPolicy.GROUP_SOFT_LIMIT + 1
        else MeshRelayPolicy.MAX_RELAY_LINKS
}
