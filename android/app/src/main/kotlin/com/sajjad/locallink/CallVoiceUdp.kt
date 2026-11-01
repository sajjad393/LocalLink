package com.sajjad.locallink

import org.json.JSONObject

/**
 * Bundle 184 (E3, E4): call voice by UDP on the same Wi-Fi.
 *
 * Over TCP one late piece holds back every piece behind it, and then they all
 * arrive at once (the "bunches" in the 2026-11-01 logs, lost=0). UDP lets a
 * late piece be late alone.
 *
 * - Only locked voice (159 call key) goes by UDP: every datagram is AES-GCM
 *   sealed with the call key, bound to sender, receiver and stream. A packet
 *   from anyone else simply doesn't open.
 * - Only to a friend this phone has a direct link with (same Wi-Fi or Wi-Fi
 *   Direct). Calls through another phone keep the old path.
 * - Each phone sends a small locked "probe" every 0.5 s. Every voice piece
 *   says `ur=1` when this phone got UDP from the friend in the last 1.5 s.
 *   A phone sends by UDP only while the friend says `ur=1` (seen in the last
 *   1 s); otherwise - older app, blocked port, Wi-Fi that drops UDP - voice
 *   stays on today's TCP path by itself.
 * - Each UDP piece also carries the piece before it (`pa`), so one lost
 *   piece is fully recovered.
 * - A datagram bigger than [MAX_DATAGRAM] (plain PCM voice) goes by TCP.
 */
object CallVoiceUdp {
    const val PORT = 8992
    const val TYPE = "lv1"
    const val MAX_DATAGRAM = 1_400
    const val PROBE_EVERY_MS = 500L
    /** "I get your UDP" stays true this long after the last UDP piece. */
    const val RX_FRESH_MS = 1_500L
    /** The friend's `ur=1` counts this long. */
    const val PEER_OK_FRESH_MS = 1_000L
    /** A learned friend address (from its UDP) is used this long. */
    const val ADDRESS_FRESH_MS = 3_000L
    const val PROBE_TYPE = "call_udp_probe"

    data class Datagram(val sender: String, val recipient: String, val stream: String, val nonce: String, val cipher: String)

    fun encode(sender: String, recipient: String, stream: String, nonceB64: String, cipherB64: String): ByteArray =
        JSONObject().put("t", TYPE).put("s", sender).put("r", recipient).put("vs", stream)
            .put("n", nonceB64).put("c", cipherB64).toString().toByteArray(Charsets.UTF_8)

    /** Null for anything that isn't a well-formed voice datagram. */
    fun decode(bytes: ByteArray, length: Int = bytes.size): Datagram? {
        if (length <= 0 || length > 4_096) return null
        val json = try { JSONObject(String(bytes, 0, length, Charsets.UTF_8)) } catch (_: Exception) { return null }
        if (json.optString("t") != TYPE) return null
        val d = Datagram(json.optString("s").trim(), json.optString("r").trim(), json.optString("vs").trim(), json.optString("n").trim(), json.optString("c").trim())
        if (d.sender.isEmpty() || d.recipient.isEmpty() || d.stream.isEmpty() || d.nonce.isEmpty() || d.cipher.isEmpty()) return null
        if (d.sender.length > 128 || d.recipient.length > 128 || d.stream.length > 64) return null
        return d
    }
}

/**
 * Bundle 184: the UDP state of one call. Thread-safe (volatile fields; each
 * is written by one thread).
 */
class CallVoiceUdpState {
    @Volatile var lastRxAt = 0L
        private set
    @Volatile var peerOkAt = 0L
        private set
    @Volatile var learnedHost: String? = null
        private set
    @Volatile var learnedPort = 0
        private set
    @Volatile var learnedAt = 0L
        private set
    @Volatile private var lastProbeAt = 0L
    @Volatile var switches = 0
        private set
    @Volatile private var lastMode = false

    @Volatile private var lastMediaSeq = -1L
    @Volatile private var lastProbeStamp = 0L

    /**
     * A locked voice piece came by UDP. Only a NEWER piece moves the address
     * or keeps `ur=1` alive, so a replayed old datagram (someone on the Wi-Fi
     * sending it again from another address) changes nothing. False = old.
     */
    fun onUdpMedia(host: String?, port: Int, seq: Long, now: Long): Boolean {
        if (seq <= lastMediaSeq) return false
        lastMediaSeq = seq
        onUdpReceived(host, port, now)
        return true
    }

    /** Same for a probe; its time stamp must be newer than the last one. */
    fun onUdpProbe(host: String?, port: Int, stamp: Long, now: Long): Boolean {
        if (stamp <= lastProbeStamp) return false
        lastProbeStamp = stamp
        onUdpReceived(host, port, now)
        return true
    }

    /** A valid (opened, new) UDP packet from the friend arrived from host:port. */
    fun onUdpReceived(host: String?, port: Int, now: Long) {
        lastRxAt = now
        if (!host.isNullOrBlank() && port in 1..65_535) {
            learnedHost = host
            learnedPort = port
            learnedAt = now
        }
    }

    /** The friend's `ur` flag from any voice piece or probe (TCP or UDP). */
    fun onPeerFlag(ur: Boolean, now: Long) {
        if (ur) peerOkAt = now
    }

    /** True = our pieces should carry `ur=1`. */
    fun receivingUdp(now: Long): Boolean = lastRxAt > 0L && now - lastRxAt in 0..CallVoiceUdp.RX_FRESH_MS

    /** Where to send: the learned address if fresh, else the direct link's address. */
    fun target(linkHost: String?, now: Long): Pair<String, Int>? {
        val host = learnedHost
        if (host != null && now - learnedAt in 0..CallVoiceUdp.ADDRESS_FRESH_MS) return host to learnedPort
        if (linkHost.isNullOrBlank()) return null
        return linkHost to CallVoiceUdp.PORT
    }

    /** True = send this voice piece by UDP. */
    fun useUdp(haveTarget: Boolean, now: Long): Boolean {
        val on = haveTarget && peerOkAt > 0L && now - peerOkAt in 0..CallVoiceUdp.PEER_OK_FRESH_MS
        if (on != lastMode) {
            lastMode = on
            switches++
        }
        return on
    }

    /** True when a probe should go out now (and marks it sent). */
    fun probeDue(now: Long): Boolean {
        if (now - lastProbeAt in 0 until CallVoiceUdp.PROBE_EVERY_MS) return false
        lastProbeAt = now
        return true
    }
}

/**
 * Bundle 184 (E1): Nearby (Wi-Fi Direct) searching pauses while a voice call
 * is live - a search makes the Wi-Fi radio leave the router's channel for a
 * moment, which the 2026-11-01 logs showed during the call. It may search
 * again [RESUME_AFTER_MS] after the call ends. The small LAN "I'm here"
 * beacons are not touched.
 */
object CallNearbyPause {
    const val RESUME_AFTER_MS = 2_000L
    @Volatile private var live = false
    @Volatile private var endedAt = 0L
    @Volatile private var lastLogAt = 0L

    fun callStarted() { live = true }

    /** Bundle 185 (A3): the freeze watcher also watches during calls. */
    fun inCall(): Boolean = live

    fun callEnded(now: Long = System.currentTimeMillis()) {
        if (!live) return
        live = false
        endedAt = now
    }

    fun searchAllowed(now: Long = System.currentTimeMillis()): Boolean =
        !live && (endedAt == 0L || now - endedAt !in 0 until RESUME_AFTER_MS)

    /** One "paused" log line per 30 s at most. */
    fun logDue(now: Long = System.currentTimeMillis()): Boolean {
        if (now - lastLogAt in 0 until 30_000L) return false
        lastLogAt = now
        return true
    }

    /** Tests only. */
    fun resetForTest() { live = false; endedAt = 0L; lastLogAt = 0L }
}
