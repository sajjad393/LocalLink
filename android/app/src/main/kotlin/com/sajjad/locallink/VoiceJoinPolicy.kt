package com.sajjad.locallink

/**
 * Bundle 181: rules for joining voice note parts (pause / continue) into one
 * file. Pure, unit-tested. Each part starts right after the previous one ends
 * (last sample + one AAC frame), so there is no gap and no overlap.
 */
object VoiceJoinPolicy {
    /** One AAC frame (1024 samples) in microseconds. */
    fun frameUs(sampleRate: Int): Long = if (sampleRate <= 0) 23_220L else 1024L * 1_000_000L / sampleRate

    /** Where the next part starts, in microseconds. */
    fun nextOffsetUs(prevOffsetUs: Long, prevLastSampleUs: Long, frameUs: Long): Long =
        prevOffsetUs + maxOf(0L, prevLastSampleUs) + maxOf(1L, frameUs)

    /** Time of one sample in the joined file (never before the part start). */
    fun sampleTimeUs(offsetUs: Long, sampleUs: Long): Long = offsetUs + maxOf(0L, sampleUs)

    /** Parts that exist and are not empty, in the given order. */
    fun usableParts(parts: List<Pair<String, Long>>): List<String> =
        parts.filter { it.first.isNotBlank() && it.second > 0L }.map { it.first }
}
