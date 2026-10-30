package com.sajjad.locallink.mesh

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Bundle 165 (5.1): photos, videos and files through any LocalLink phone.
 *
 * File packets (chunks, progress, acks, resume, cancel, restart) used to be
 * plain, so a phone that is not a contact (a relay link, 156) refused them.
 * Now the whole file packet can travel locked inside one packet type,
 * [MeshRelayPolicy.SEALED_FILE]:
 * - key = HMAC-SHA256(the 160 link key both contacts share,
 *   "llf1|sender|receiver") — one key per direction, never sent;
 * - AES-256-GCM, a new 12-byte nonce for every packet;
 * - the extra data (AAD) binds it to sender and receiver, so it can't be
 *   turned around or sent to someone else.
 * A phone in the middle sees only "sealed_f", the two ids and the size. It
 * can't tell a chunk from an ack, and can't read or change the file.
 */
object FileSeal {
    const val NONCE_BYTES = 12
    private const val TAG_BITS = 128
    private const val VERSION = "llf1"
    private val random = SecureRandom()

    /** File packet types that may travel locked. */
    val FILE_TYPES: Set<String> = setOf(
        "direct_file_chunk",
        "direct_file_progress",
        "direct_file_ack",
        "direct_file_resume_request",
        "direct_file_cancel",
        "direct_file_restart",
    )

    fun isFileType(type: String?): Boolean = type != null && type in FILE_TYPES

    /** The per-direction key. Both phones work it out from the shared link key. */
    fun key(linkKey: ByteArray, senderId: String, recipientId: String): ByteArray {
        require(linkKey.size == 32) { "bad link key" }
        val m = Mac.getInstance("HmacSHA256")
        m.init(SecretKeySpec(linkKey, "HmacSHA256"))
        return m.doFinal("$VERSION|$senderId|$recipientId".toByteArray(Charsets.UTF_8))
    }

    private fun aad(senderId: String, recipientId: String): ByteArray =
        "$VERSION|$senderId|$recipientId|${MeshRelayPolicy.SEALED_FILE}".toByteArray(Charsets.UTF_8)

    /** Returns nonce to cipher text. */
    fun seal(key: ByteArray, senderId: String, recipientId: String, plain: ByteArray): Pair<ByteArray, ByteArray> {
        require(key.size == 32) { "bad file key" }
        val nonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        c.updateAAD(aad(senderId, recipientId))
        return nonce to c.doFinal(plain)
    }

    /** Null when it doesn't open (wrong key, changed, other direction). */
    fun open(key: ByteArray, senderId: String, recipientId: String, nonce: ByteArray, cipherText: ByteArray): ByteArray? {
        if (key.size != 32 || nonce.size != NONCE_BYTES || cipherText.size <= TAG_BITS / 8) return null
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            c.updateAAD(aad(senderId, recipientId))
            c.doFinal(cipherText)
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Bundle 165: when to lock a file packet.
 *
 * Older phones (164 and before) can't open "sealed_f", so a file to them must
 * stay plain. A phone is known able when it said so ("sf":1 in its hello or in
 * a plain file packet) or sent us a locked file packet.
 */
object FileSealPolicy {
    /** Stalled resend rounds before the other way is tried. */
    const val SWITCH_AFTER_STALLS = 2

    /** Max phones remembered as able. */
    const val MAX_KNOWN = 500

    /**
     * Lock this file packet?
     * - no shared link key = can't lock (plain, as before);
     * - the next hop is a non-contact phone = plain would be refused there;
     * - known able = locked (works through any phone), else plain;
     * - [flip]: a stuck transfer tries the other way for a while (the other
     *   phone may be older than we think, or its key may have changed).
     */
    fun useSeal(haveKey: Boolean, knownCapable: Boolean, nextHopIsRelay: Boolean, flip: Boolean, replyLikeLast: Boolean? = null): Boolean {
        if (!haveKey) return false
        if (nextHopIsRelay) return true
        // The receiving side answers (progress, ack, restart) the same way the
        // last file packet came, so a sender that went back to plain is
        // answered plain.
        if (replyLikeLast != null) return replyLikeLast
        return knownCapable != flip
    }

    /** Packets the receiving phone sends back to the file sender. */
    val REPLY_TYPES: Set<String> = setOf("direct_file_progress", "direct_file_ack", "direct_file_restart")

    /**
     * A transfer that is stuck switches between plain and locked every
     * [SWITCH_AFTER_STALLS] resend rounds (0-1 plain, 2-3 locked, 4-5 plain...).
     * Plain may be refused by a non-contact phone on the way; locked may not
     * open on an older phone. One of them gets through.
     */
    fun flipFor(stalls: Int): Boolean =
        stalls >= SWITCH_AFTER_STALLS && (stalls / SWITCH_AFTER_STALLS) % 2 == 1

    /** My own locked file packets may wait for a route like plain chunks;
     *  someone else's are never stored here (resend covers a loss). */
    fun storeForwardable(type: String, sourceId: String, selfId: String?): Boolean =
        type == MeshRelayPolicy.SEALED_FILE && selfId != null && sourceId == selfId

    /** Pass a locked file packet to a next phone only if it understands it
     *  (a contact link carries anything, as before). */
    fun canSendOnward(type: String, trust: String, peerFileSeal: Boolean): Boolean =
        type != MeshRelayPolicy.SEALED_FILE || trust == MeshRelayPolicy.TRUST_CONTACT || peerFileSeal
}

/**
 * Bundle 165: how many locked file bytes a phone passes on for others.
 *
 * A photo is hundreds of packets — far over the 156 relay flood limit, which
 * would pause the relay for 10 minutes. Locked file packets get their own
 * budget instead: over it the packet is dropped (the sender's resend gets it
 * through later), and the link is never paused for files.
 */
class MeshRelayFileBudget(
    private val maxBytesPerPeer: Long = MAX_BYTES_PER_PEER,
    private val maxBytesTotal: Long = MAX_BYTES_TOTAL,
    private val windowMs: Long = 60_000L,
) {
    companion object {
        /** About 3 Mbit/s from one neighbour. */
        const val MAX_BYTES_PER_PEER: Long = 24L * 1024L * 1024L
        /** All neighbours together. */
        const val MAX_BYTES_TOTAL: Long = 48L * 1024L * 1024L
    }

    private class Window(var startedAt: Long, var bytes: Long)

    private val perPeer = ConcurrentHashMap<String, Window>()
    private var total = Window(0L, 0L)
    private val fullNoticeAt = ConcurrentHashMap<String, Long>()

    @Synchronized
    fun allow(peerId: String, bytes: Int, now: Long = System.currentTimeMillis()): Boolean {
        val b = bytes.coerceAtLeast(0).toLong()
        if (now - total.startedAt >= windowMs) total = Window(now, 0L)
        val w = perPeer[peerId]?.takeIf { now - it.startedAt < windowMs } ?: Window(now, 0L).also { perPeer[peerId] = it }
        if (w.bytes + b > maxBytesPerPeer || total.bytes + b > maxBytesTotal) return false
        w.bytes += b
        total.bytes += b
        if (perPeer.size > 64) perPeer.entries.removeIf { now - it.value.startedAt >= windowMs }
        return true
    }

    /** True at most once a minute per peer (one log line when full). */
    fun shouldNoteFull(peerId: String, now: Long = System.currentTimeMillis()): Boolean {
        val last = fullNoticeAt[peerId] ?: 0L
        if (now - last < windowMs) return false
        fullNoticeAt[peerId] = now
        return true
    }
}
