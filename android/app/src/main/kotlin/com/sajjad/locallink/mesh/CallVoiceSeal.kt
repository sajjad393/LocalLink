package com.sajjad.locallink.mesh

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Bundle 159: locked call voice.
 *
 * The caller makes a new random 32-byte key for each call and sends it inside
 * the locked (156) call invite. Each 20 ms voice frame is locked with it
 * (AES-256-GCM, new 12-byte nonce per frame). Phones in the middle see only a
 * random stream id and cipher text, so they can pass the call on but can't
 * hear it. The key lives only in memory for the call.
 *
 * The extra data (AAD) binds a frame to its sender, receiver and stream, so a
 * frame can't be replayed in another direction or another call.
 */
object CallVoiceSeal {
    const val KEY_BYTES = 32
    const val NONCE_BYTES = 12
    private const val TAG_BITS = 128
    private val random = SecureRandom()

    fun validKey(key: ByteArray?): Boolean = key != null && key.size == KEY_BYTES

    /** Public stream id (16 hex) both call phones derive from the key. */
    fun streamId(key: ByteArray): String {
        val d = MessageDigest.getInstance("SHA-256")
        d.update("locallink-voice-stream-v1".toByteArray(Charsets.UTF_8))
        d.update(key)
        return d.digest().take(8).joinToString("") { "%02x".format(it) }
    }

    private fun aad(source: String, destination: String, stream: String): ByteArray =
        "v1|$source|$destination|$stream".toByteArray(Charsets.UTF_8)

    /** Returns nonce to cipher text. */
    fun seal(key: ByteArray, source: String, destination: String, stream: String, plain: ByteArray): Pair<ByteArray, ByteArray> {
        require(validKey(key)) { "bad voice key" }
        val nonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        c.updateAAD(aad(source, destination, stream))
        return nonce to c.doFinal(plain)
    }

    /** Null when the frame doesn't open with this key (wrong key, changed, other direction). */
    fun open(key: ByteArray, source: String, destination: String, stream: String, nonce: ByteArray, cipherText: ByteArray): ByteArray? {
        if (!validKey(key) || nonce.size != NONCE_BYTES || cipherText.size <= TAG_BITS / 8) return null
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            c.updateAAD(aad(source, destination, stream))
            c.doFinal(cipherText)
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Bundle 159: how much locked voice a phone passes on for others.
 *
 * One call is about 50 frames a second each way — far above the 156 relay
 * flood limit (600 a minute), which would pause the relay. Locked voice gets
 * its own budget instead:
 * - at most [maxStreams] calls at a time (a call's two directions share one
 *   stream id);
 * - at most [maxPerSecond] frames a second per call;
 * - over budget = that frame is dropped (late sound is useless anyway); the
 *   link is never paused for voice.
 * A call that sends nothing for [idleMs] frees its place.
 */
class MeshRelayVoiceBudget(
    private val maxStreams: Int = MAX_STREAMS,
    private val maxPerSecond: Int = MAX_PER_SECOND,
    private val idleMs: Long = IDLE_MS,
) {
    companion object {
        const val MAX_STREAMS = 2
        const val MAX_PER_SECOND = 160
        const val IDLE_MS = 5_000L
        private val streamPattern = Regex("^[0-9a-f]{16}$")
    }

    private class Stream(var lastAt: Long, var secondStart: Long, var count: Int)

    private val streams = ConcurrentHashMap<String, Stream>()

    @Synchronized
    fun allow(streamId: String?, now: Long = System.currentTimeMillis()): Boolean {
        val id = streamId?.trim()?.lowercase().orEmpty()
        if (!streamPattern.matches(id)) return false
        streams.entries.removeIf { now - it.value.lastAt > idleMs }
        val s = streams[id]
        if (s == null) {
            if (streams.size >= maxStreams) return false
            streams[id] = Stream(now, now, 1)
            return true
        }
        s.lastAt = now
        if (now - s.secondStart >= 1_000L) {
            s.secondStart = now
            s.count = 0
        }
        if (s.count >= maxPerSecond) return false
        s.count++
        return true
    }

    /** True when [streamId] is a call this phone is already passing on. */
    fun knows(streamId: String?, now: Long = System.currentTimeMillis()): Boolean {
        val s = streams[streamId?.trim()?.lowercase().orEmpty()] ?: return false
        return now - s.lastAt <= idleMs
    }

    fun activeStreams(now: Long = System.currentTimeMillis()): Int =
        streams.values.count { now - it.lastAt <= idleMs }
}
