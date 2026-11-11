package com.sajjad.locallink

/**
 * Bundle 266 (B2): one locked voice piece for the server relay (bundle 251).
 *
 * Bytes = len(vs) | vs | nonce(12) | cipher (AES-GCM, the call key).
 * The app sends them as base64 in `call_voice.voice`; the server never opens
 * them, it only passes them to the other phone of a connected call. Pieces
 * bigger than the server limit (1400 base64 chars) are not sent (PCM voice
 * is too big; opus2 fits). Never plain voice.
 */
object CallServerVoice266 {
    const val MAX_B64 = 1400
    const val NONCE_BYTES = 12
    /** GCM tag (16) + at least one byte. */
    const val MIN_CIPHER = 17
    const val LOG_EVERY_MS = 30_000L
    /** The path word `server` while a piece went out this recently. */
    const val PATH_FRESH_MS = 3_000L

    class Piece(val stream: String, val nonce: ByteArray, val cipher: ByteArray)

    /** Length of [n] bytes as padded base64. */
    fun b64Len(n: Int): Int = ((n + 2) / 3) * 4

    /** The bytes to send, or null when the piece is bad or too big. */
    fun packBytes(stream: String, nonce: ByteArray, cipher: ByteArray): ByteArray? {
        val vs = stream.toByteArray(Charsets.UTF_8)
        if (vs.isEmpty() || vs.size > 255 || nonce.size != NONCE_BYTES || cipher.size < MIN_CIPHER) return null
        val total = 1 + vs.size + nonce.size + cipher.size
        if (b64Len(total) > MAX_B64) return null
        val out = ByteArray(total)
        out[0] = vs.size.toByte()
        System.arraycopy(vs, 0, out, 1, vs.size)
        System.arraycopy(nonce, 0, out, 1 + vs.size, nonce.size)
        System.arraycopy(cipher, 0, out, 1 + vs.size + nonce.size, cipher.size)
        return out
    }

    /** The piece inside [raw], or null when it is not a valid piece. */
    fun unpackBytes(raw: ByteArray?): Piece? {
        if (raw == null || raw.isEmpty() || b64Len(raw.size) > MAX_B64) return null
        val n = raw[0].toInt() and 0xFF
        if (n == 0 || raw.size < 1 + n + NONCE_BYTES + MIN_CIPHER) return null
        val vs = String(raw, 1, n, Charsets.UTF_8)
        val nonce = raw.copyOfRange(1 + n, 1 + n + NONCE_BYTES)
        val cipher = raw.copyOfRange(1 + n + NONCE_BYTES, raw.size)
        return Piece(vs, nonce, cipher)
    }

    /** `VOICE_SERVER call=<id> tx=<n> rx=<n> big=<n> on=y|n` (every 30 s and at the end). */
    fun line(callId: String, tx: Long, rx: Long, big: Long, on: Boolean): String =
        "VOICE_SERVER call=$callId tx=$tx rx=$rx big=$big on=${if (on) "y" else "n"}"
}

/**
 * Bundle 266 (C): no long gap when the link changes during a call.
 *
 * Only while a call with this friend is live: no voice from the friend for
 * 2.5 s and the active link had no line for 2.5 s -> one ping on the other
 * link(s) to the same friend; the first one that answers within 1 s becomes
 * the active link. The old link is not closed (the 15 s rule still decides).
 * When the old link talks again it is used again.
 */
object CallLinkSwitch266 {
    const val QUIET_MS = 2_500L
    const val ANSWER_MS = 1_000L
    const val CHECK_MS = 500L

    /** Time to ping the other links? Never before the first voice arrived. */
    fun shouldProbe(now: Long, lastVoiceRxAt: Long, activeLastSeenAt: Long, otherLinks: Int, lastProbeAt: Long, callLive: Boolean = true): Boolean =
        callLive && otherLinks > 0 && lastVoiceRxAt > 0L &&
            now - lastVoiceRxAt >= QUIET_MS &&
            now - activeLastSeenAt >= QUIET_MS &&
            now - lastProbeAt >= QUIET_MS

    /** Index of the other link that answered the ping in time (the first one), or -1. */
    fun pickAnswered(probeAt: Long, otherLastSeen: List<Long>): Int {
        if (probeAt <= 0L) return -1
        var best = -1
        var bestAt = Long.MAX_VALUE
        otherLastSeen.forEachIndexed { i, at ->
            if (at >= probeAt && at - probeAt <= ANSWER_MS && at < bestAt) {
                best = i
                bestAt = at
            }
        }
        return best
    }

    /** The probe is over (no answer in time). */
    fun probeOver(probeAt: Long, now: Long): Boolean = probeAt > 0L && now - probeAt > ANSWER_MS + CHECK_MS

    /** The link we left talked again after the switch (not a late line): use it again. */
    fun backToOld(switchedAt: Long, oldLastSeenAt: Long): Boolean = switchedAt > 0L && oldLastSeenAt - switchedAt > ANSWER_MS

    fun line(callId: String, from: String, to: String, quietMs: Long): String =
        "CALL_LINK_SWITCH call=$callId from=$from to=$to quiet_ms=$quietMs"
}

/** Bundle 266 (B2): one quiet thread opens the pieces that came through the server, in order. */
object CallServerVoiceIn266 {
    private val worker = java.util.concurrent.Executors.newSingleThreadExecutor { r ->
        Thread(r, "call-server-voice-in").apply { isDaemon = true }
    }

    fun run(block: () -> Unit) {
        try { worker.execute { try { block() } catch (_: Throwable) {} } } catch (_: Throwable) {}
    }
}
