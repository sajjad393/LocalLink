package com.sajjad.locallink.mesh

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Bundle 160: signed device id on the link hello.
 *
 * Before, a phone said "I am X" and nothing checked it. Now two contacts
 * prove it to each other: both phones already hold a shared secret per
 * contact (X25519 of their identity keys -> HKDF, computed in Dart and pushed
 * here as a "link key"). Each side adds a fresh random number (nonce) and an
 * HMAC over both ids and both nonces. Only the real contact can make it.
 *
 * Rules:
 *  * both sides have a key  -> the HMAC is required (wrong = link refused);
 *  * an older phone / no shared key -> the old way, logged (LINK_AUTH legacy);
 *  * a contact that passed once must always pass (no silent downgrade);
 *  * strangers (relay links) have no key: old way, sealed packets only.
 *
 * Key ids are the short ids from the message seal (base64url of 8 bytes).
 * A link key offer is "<myKeyId>.<theirKeyId>".
 */
object MeshLinkAuth {
    const val VERSION = 1
    const val MAX_KEYS_PER_PEER = 3
    const val MAX_PEERS = 1024
    private val kidPattern = Regex("^[A-Za-z0-9_-]{8,24}$")
    private val noncePattern = Regex("^[0-9a-f]{32}$")
    private val keyPattern = Regex("^[0-9a-f]{64}$")
    private val random = SecureRandom()

    class LinkKey(val ownKid: String, val peerKid: String, val key: ByteArray) {
        val offer: String get() = "$ownKid.$peerKid"
    }

    enum class Verdict { VERIFIED, LEGACY, REJECT }
    data class Decision(val verdict: Verdict, val reason: String)

    fun validKid(kid: String?): Boolean = kid != null && kidPattern.matches(kid)
    fun validNonce(n: String?): Boolean = n != null && noncePattern.matches(n)

    /** Parses one entry pushed from Dart: own kid, peer kid, 32-byte key (hex). */
    fun parse(ownKid: String?, peerKid: String?, keyHex: String?): LinkKey? {
        if (!validKid(ownKid) || !validKid(peerKid)) return null
        val hex = keyHex?.trim()?.lowercase() ?: return null
        if (!keyPattern.matches(hex)) return null
        val bytes = ByteArray(32) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
        return LinkKey(ownKid!!, peerKid!!, bytes)
    }

    fun newNonce(): String {
        val b = ByteArray(16)
        random.nextBytes(b)
        return hex(b)
    }

    /** My offers for the other phone ("myKid.theirKid"). */
    fun offers(mine: List<LinkKey>): List<String> = mine.take(MAX_KEYS_PER_PEER).map { it.offer }

    /**
     * Their offers are "theirKid.myKid" from their side; the matching key of
     * mine has ownKid == their peerKid and peerKid == their ownKid.
     */
    fun match(mine: List<LinkKey>, theirOffers: List<String>): LinkKey? {
        for (offer in theirOffers.take(MAX_KEYS_PER_PEER)) {
            val parts = offer.split('.')
            if (parts.size != 2 || !validKid(parts[0]) || !validKid(parts[1])) continue
            mine.firstOrNull { it.ownKid == parts[1] && it.peerKid == parts[0] }?.let { return it }
        }
        return null
    }

    /** [role] "c" = the phone that dialled, "s" = the phone that answered. */
    fun mac(key: ByteArray, role: String, clientId: String, serverId: String, clientNonce: String, serverNonce: String): String {
        val m = Mac.getInstance("HmacSHA256")
        m.init(SecretKeySpec(key, "HmacSHA256"))
        return hex(m.doFinal("lk$VERSION|$role|$clientId|$serverId|$clientNonce|$serverNonce".toByteArray(Charsets.UTF_8)))
    }

    fun verify(key: ByteArray, role: String, clientId: String, serverId: String, clientNonce: String, serverNonce: String, given: String?): Boolean {
        if (given == null || given.length != 64) return false
        val expected = mac(key, role, clientId, serverId, clientNonce, serverNonce)
        return MessageDigest.isEqual(expected.toByteArray(Charsets.US_ASCII), given.lowercase().toByteArray(Charsets.US_ASCII))
    }

    /**
     * [haveKeys] this phone holds a link key for the peer; [peerOffers] the
     * peer took part (new app, sent offers/MAC); [matched] a shared key was
     * found; [macOk] its HMAC checked out; [verifiedBefore] it passed once.
     */
    fun decide(haveKeys: Boolean, peerOffers: Boolean, matched: Boolean, macOk: Boolean, verifiedBefore: Boolean): Decision {
        if (!haveKeys) return Decision(Verdict.LEGACY, "no_local_key")
        if (peerOffers && matched) {
            return if (macOk) Decision(Verdict.VERIFIED, "mac_ok") else Decision(Verdict.REJECT, "bad_mac")
        }
        if (verifiedBefore) return Decision(Verdict.REJECT, "auth_required")
        return Decision(Verdict.LEGACY, if (peerOffers) "no_shared_key" else "old_phone")
    }

    /**
     * Bundle 164 (5.8): strict mode (a setting, off by default). A contact
     * link that is not id-checked (older app, or no shared key yet) is
     * refused. Relay links (strangers) are never id-checked and stay as they
     * are: they only carry sealed packets.
     */
    fun applyStrict(decision: Decision, strict: Boolean, isContact: Boolean): Decision {
        if (!strict || !isContact || decision.verdict != Verdict.LEGACY) return decision
        return Decision(Verdict.REJECT, "strict_unchecked")
    }

    private fun hex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }
}
