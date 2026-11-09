package com.sajjad.locallink

/**
 * Bundle 226 (B2): pure rules for the tiny Bluetooth LE signal (no Android
 * types, unit-tested in BlePacket226Test / BleRate226Test / BleMode226Test).
 *
 * Bluetooth only says "I'm here / I want you"; chats, files and calls still
 * go over Wi-Fi. The packet is LinkUp's own service data (not iBeacon /
 * Eddystone, so `neverForLocation` does not filter it), 10 bytes:
 *
 *  byte 0    : version (high 4 bits = 1) + flags (host, member, searching
 *              now, on router)
 *  bytes 1-4 : my short id (the same 8 hex the Wi-Fi Direct tag shows)
 *  bytes 5-8 : wanted friend's short id (0 = nobody)
 *  byte 9    : bit 0 = wants for a call, bit 1 = I host OUR pair group now,
 *              bits 2-7 = a counter (new value = state changed)
 *
 * No name, no password, no account data.
 */
object NearbyBlePolicy {
    const val SERVICE_UUID = "f65feee8-2b78-4140-ad0a-4dad883a03ef"
    const val VERSION = 1
    const val PACKET_LEN = 10

    const val F_HOST = 0x1
    const val F_MEMBER = 0x2
    const val F_SEARCHING = 0x4
    const val F_ROUTER = 0x8
    const val W_CALL = 0x1
    const val W_PAIR_HOST = 0x2

    /** Android: at most 5 scan starts per 30 s per app. */
    const val SCAN_STARTS_MAX = 5
    const val SCAN_WINDOW_MS = 30_000L
    /** Android downgrades a scan that runs 30 min: restart it every 25 min. */
    const val SCAN_RESTART_MS = 25 * 60_000L
    /** 3 failed starts in a row -> the Bluetooth part rests 10 min. */
    const val FAILS_TO_REST = 3
    const val REST_MS = 10 * 60_000L
    /** Urgent modes (call / searching now) last at most this long per ask. */
    const val URGENT_MAX_MS = 60_000L
    /** Up to 3 wanted friends take turns in the advert. */
    const val ROTATE_MS = 5_000L
    const val MAX_WANTED = 3
    /** `ble_seen` to Dart at most once per phone per 2 s (sooner if changed). */
    const val SEEN_EVERY_MS = 2_000L
    /** `BLE_SEEN` log line at most once per phone per minute. */
    const val LOG_EVERY_MS = 60_000L

    data class Packet(
        val id8: String,
        val wanted8: String? = null,
        val host: Boolean = false,
        val member: Boolean = false,
        val searching: Boolean = false,
        val onRouter: Boolean = false,
        val call: Boolean = false,
        val pairHost: Boolean = false,
        val counter: Int = 0,
    )

    /** One wanted friend from Dart. */
    data class Wanted(val id8: String, val call: Boolean, val pairHost: Boolean)

    private val HEX8 = Regex("^[0-9a-f]{8}$")

    fun validId(id: String?): Boolean = id != null && HEX8.matches(id) && id != "00000000"

    /** Null when [p] can't be sent (bad id). */
    fun encode(p: Packet): ByteArray? {
        if (!validId(p.id8)) return null
        val wanted = p.wanted8?.takeIf { validId(it) }
        val out = ByteArray(PACKET_LEN)
        var flags = 0
        if (p.host) flags = flags or F_HOST
        if (p.member) flags = flags or F_MEMBER
        if (p.searching) flags = flags or F_SEARCHING
        if (p.onRouter) flags = flags or F_ROUTER
        out[0] = ((VERSION shl 4) or flags).toByte()
        putHex(out, 1, p.id8)
        if (wanted != null) putHex(out, 5, wanted)
        var last = (p.counter and 0x3f) shl 2
        if (wanted != null && p.call) last = last or W_CALL
        if (wanted != null && p.pairHost) last = last or W_PAIR_HOST
        out[9] = last.toByte()
        return out
    }

    /** Null for anything that is not a LinkUp v1 packet. Never throws. */
    fun decode(bytes: ByteArray?): Packet? {
        if (bytes == null || bytes.size < PACKET_LEN) return null
        val b0 = bytes[0].toInt() and 0xff
        if (b0 shr 4 != VERSION) return null
        val id = hex(bytes, 1)
        if (!validId(id)) return null
        val wantedRaw = hex(bytes, 5)
        val wanted = if (validId(wantedRaw)) wantedRaw else null
        val last = bytes[9].toInt() and 0xff
        return Packet(
            id8 = id,
            wanted8 = wanted,
            host = b0 and F_HOST != 0,
            member = b0 and F_MEMBER != 0,
            searching = b0 and F_SEARCHING != 0,
            onRouter = b0 and F_ROUTER != 0,
            call = wanted != null && last and W_CALL != 0,
            pairHost = wanted != null && last and W_PAIR_HOST != 0,
            counter = last shr 2,
        )
    }

    private fun putHex(out: ByteArray, at: Int, hex8: String) {
        for (i in 0 until 4) out[at + i] = hex8.substring(i * 2, i * 2 + 2).toInt(16).toByte()
    }

    private fun hex(b: ByteArray, at: Int): String {
        val sb = StringBuilder(8)
        for (i in 0 until 4) {
            val v = b[at + i].toInt() and 0xff
            sb.append("0123456789abcdef"[v shr 4]).append("0123456789abcdef"[v and 0xf])
        }
        return sb.toString()
    }

    /** Which wanted friend the advert shows now (they take turns every 5 s). */
    fun pick(wanted: List<Wanted>, now: Long): Wanted? {
        if (wanted.isEmpty()) return null
        val n = wanted.size.coerceAtMost(MAX_WANTED)
        val i = ((now / ROTATE_MS) % n).toInt().let { if (it < 0) 0 else it }
        return wanted[i]
    }

    // ---------------------------------------------------------------- modes

    /** "off" | "low_power" | "balanced" | "low_latency". A live call stops
     *  the scan (budget phones share one antenna for Wi-Fi and Bluetooth). */
    fun scanMode(inCall: Boolean, urgent: Boolean, foreground: Boolean): String = when {
        inCall -> "off"
        urgent -> "low_latency"
        foreground -> "balanced"
        else -> "low_power"
    }

    fun advMode(urgent: Boolean, inCall: Boolean): String =
        if (urgent && !inCall) "low_latency" else "low_power"

    /** Urgent only while the last urgent ask is younger than 60 s. */
    fun urgentNow(urgentSince: Long, now: Long): Boolean =
        urgentSince > 0L && now - urgentSince in 0 until URGENT_MAX_MS

    /** One word for Dart (`ble_state`). */
    fun stateWord(
        sdk: Int,
        hasBle: Boolean,
        enabled: Boolean,
        scanPermission: Boolean,
        advertisePermission: Boolean,
        canAdvertise: Boolean,
    ): String = when {
        sdk < 29 || !hasBle -> "unsupported"
        !scanPermission -> "no_permission"
        !enabled -> "off"
        !advertisePermission || !canAdvertise -> "scan_only"
        else -> "on"
    }

    // ----------------------------------------------------------- rate limits

    /** Drops starts older than 30 s; true = one more scan start is allowed. */
    fun scanStartAllowed(starts: MutableList<Long>, now: Long): Boolean {
        starts.removeAll { now - it >= SCAN_WINDOW_MS || it > now }
        return starts.size < SCAN_STARTS_MAX
    }

    /** How long until the next start is allowed (0 = now). */
    fun scanWaitMs(starts: List<Long>, now: Long): Long {
        val live = starts.filter { now - it in 0 until SCAN_WINDOW_MS }.sorted()
        if (live.size < SCAN_STARTS_MAX) return 0L
        return (live[live.size - SCAN_STARTS_MAX] + SCAN_WINDOW_MS - now).coerceAtLeast(1L)
    }

    fun restartDue(scanStartedAt: Long, now: Long): Boolean =
        scanStartedAt > 0L && now - scanStartedAt >= SCAN_RESTART_MS

    /** 3 failures in a row -> rest 10 min (never loops). */
    class Fails {
        var row = 0
            private set
        var restUntil = 0L
            private set

        /** True when this failure starts a rest. */
        fun failed(now: Long): Boolean {
            row += 1
            if (row >= FAILS_TO_REST) {
                row = 0
                restUntil = now + REST_MS
                return true
            }
            return false
        }

        fun ok() { row = 0 }

        fun resting(now: Long): Boolean = now < restUntil
    }

    /** `ble_seen` / `BLE_SEEN` pacing per phone. */
    class SeenGate {
        private val lastEmit = HashMap<String, Long>()
        private val lastPacket = HashMap<String, Packet>()
        private val lastLog = HashMap<String, Long>()

        fun shouldEmit(p: Packet, now: Long): Boolean {
            trim()
            val changed = lastPacket[p.id8]?.copy(counter = 0) != p.copy(counter = 0)
            val at = lastEmit[p.id8]
            if (!changed && at != null && now - at in 0 until SEEN_EVERY_MS) return false
            lastEmit[p.id8] = now
            lastPacket[p.id8] = p
            return true
        }

        fun shouldLog(id8: String, now: Long): Boolean {
            val at = lastLog[id8]
            if (at != null && now - at in 0 until LOG_EVERY_MS) return false
            lastLog[id8] = now
            return true
        }

        private fun trim() {
            if (lastEmit.size > 64) { lastEmit.clear(); lastPacket.clear() }
            if (lastLog.size > 64) lastLog.clear()
        }
    }
}
