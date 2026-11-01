package com.sajjad.locallink.mesh

/**
 * Bundle 192 (logs only): someone else's call passing through this phone.
 *
 * One `RELAY_VOICE_HEALTH` line per call stream every 10 s while it runs,
 * and one with `at=end` after 8 s with no voice. Never the sound itself.
 *
 * `RELAY_VOICE_HEALTH stream=<6> src=<6> dst=<6> passed=<n> per_s=<n> dropped=<n> gap_max_ms=<n> at=run|end`
 * - passed: voice pieces passed on in this window (about 50 a second is normal).
 * - dropped: pieces that could not go on (call budget full / no way onward).
 * - gap_max_ms: longest wait between two pieces passed on.
 */
class RelayVoiceHealth(
    private val logEveryMs: Long = LOG_EVERY_MS,
    private val idleMs: Long = IDLE_MS,
    private val maxStreams: Int = MAX_STREAMS,
) {
    companion object {
        const val LOG_EVERY_MS = 10_000L
        const val IDLE_MS = 8_000L
        const val MAX_STREAMS = 8
        fun short(id: String?): String = id?.trim()?.takeIf { it.isNotEmpty() }?.takeLast(6) ?: "-"
    }

    private class Stream(
        var src: String,
        var dst: String,
        var windowStart: Long,
        var lastAt: Long,
        var passed: Long = 0,
        var dropped: Long = 0,
        var gapMax: Long = 0,
    )

    private val streams = LinkedHashMap<String, Stream>()

    private fun lineFor(key: String, s: Stream, now: Long, moment: String): String {
        val secs = ((now - s.windowStart).coerceAtLeast(1L) + 999L) / 1000L
        return "RELAY_VOICE_HEALTH stream=${short(key)} src=${short(s.src)} dst=${short(s.dst)} " +
            "passed=${s.passed} per_s=${s.passed / secs} dropped=${s.dropped} gap_max_ms=${s.gapMax} at=$moment"
    }

    private fun streamFor(key: String, src: String, dst: String, now: Long): Stream {
        streams[key]?.let { return it }
        if (streams.size >= maxStreams) streams.remove(streams.keys.first())
        return Stream(src, dst, now, 0L).also { streams[key] = it }
    }

    /** A voice piece was passed on. Returns a line when 10 s are up. */
    @Synchronized
    fun onPassed(stream: String, src: String, dst: String, now: Long): String? {
        val key = stream.ifBlank { "$src>$dst" }
        val s = streamFor(key, src, dst, now)
        if (s.lastAt > 0L) { val gap = now - s.lastAt; if (gap > s.gapMax) s.gapMax = gap }
        s.lastAt = now
        s.passed++
        return dueLine(key, s, now)
    }

    /** A voice piece could not go on. Returns a line when 10 s are up. */
    @Synchronized
    fun onDropped(stream: String, src: String, dst: String, now: Long): String? {
        val key = stream.ifBlank { "$src>$dst" }
        val s = streamFor(key, src, dst, now)
        s.dropped++
        return dueLine(key, s, now)
    }

    private fun dueLine(key: String, s: Stream, now: Long): String? {
        if (now - s.windowStart < logEveryMs) return null
        val line = lineFor(key, s, now, "run")
        s.windowStart = now; s.passed = 0; s.dropped = 0; s.gapMax = 0
        return line
    }

    /** From the maintenance loop: `at=end` lines for streams with no voice for 8 s. */
    @Synchronized
    fun tick(now: Long): List<String> {
        val out = ArrayList<String>()
        val it = streams.entries.iterator()
        while (it.hasNext()) {
            val (key, s) = it.next()
            val last = if (s.lastAt > 0L) s.lastAt else s.windowStart
            if (now - last >= idleMs) {
                out.add(lineFor(key, s, last.coerceAtLeast(s.windowStart + 1), "end"))
                it.remove()
            }
        }
        return out
    }

    @Synchronized
    fun activeStreams(): Int = streams.size
}
