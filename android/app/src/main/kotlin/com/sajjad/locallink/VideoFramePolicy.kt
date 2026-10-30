package com.sajjad.locallink

/**
 * Bundle 164 (4.4): some videos give no first frame on Android 12+, or a
 * black one (fade-in, screen recordings). Then the thumbnail is taken again
 * at 1 s and at a quarter of the video. Pure rules so they can be tested.
 */
object VideoFramePolicy {
    /** Brightness (0-255) above which a sample counts as "not black". */
    const val LIT_LUMA = 32
    /** A frame is black when fewer than this share of samples is lit. */
    const val MIN_LIT_SHARE = 0.05

    fun luma(argb: Int): Int {
        val r = (argb shr 16) and 0xff
        val g = (argb shr 8) and 0xff
        val b = argb and 0xff
        return (r * 299 + g * 587 + b * 114) / 1000
    }

    fun isMostlyDark(lumas: IntArray): Boolean {
        if (lumas.isEmpty()) return true
        val lit = lumas.count { it > LIT_LUMA }
        return lit < lumas.size * MIN_LIT_SHARE
    }

    /** When to try again, in microseconds (inside the video only). */
    fun retryTimesUs(durationMs: Long): List<Long> {
        val endUs = durationMs * 1000L
        val raw = listOf(1_000_000L, endUs / 4)
        return raw.filter { it > 0 && (durationMs <= 0 || it < endUs) }.distinct()
    }
}
