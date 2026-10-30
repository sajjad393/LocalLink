package com.sajjad.locallink

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Bundle 149: pure (Android-free) helpers for the `opus2` call codec, so they
 * can be checked on a plain JVM.
 *
 * Why 142-145 Opus failed and what this fixes:
 *  - the decoder got no Opus setup data (csd-0/1/2) -> it crashed (silence);
 *  - Android's Opus decoder always outputs 48 kHz, which was played on the
 *    16 kHz call track -> 3x slow, deep "tiger" voice. [toMono16k] converts
 *    whatever the decoder reports back to 16 kHz mono.
 */
object CallOpus2Format {
    const val CODEC = "opus2"
    const val PCM = "pcm_s16le"
    const val CALL_RATE = 16_000

    /** Opus decoder delay at 48 kHz (6.5 ms), the libopus default. */
    const val PRE_SKIP_SAMPLES = 312
    const val SEEK_PREROLL_NS = 80_000_000L

    /** RFC 7845 identification header ("OpusHead"), 19 bytes, little-endian. */
    fun opusHead(channels: Int = 1, inputRate: Int = CALL_RATE, preSkip: Int = PRE_SKIP_SAMPLES): ByteArray {
        val b = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN)
        b.put("OpusHead".toByteArray(Charsets.US_ASCII))
        b.put(1.toByte())                 // version
        b.put(channels.toByte())          // channel count
        b.putShort(preSkip.toShort())     // pre-skip (48 kHz samples)
        b.putInt(inputRate)               // original input rate (info only)
        b.putShort(0)                     // output gain
        b.put(0.toByte())                 // mapping family 0 (mono/stereo)
        return b.array()
    }

    /** csd-1 / csd-2: a 64-bit nanosecond value in native byte order. */
    fun nanosCsd(nanos: Long, order: ByteOrder = ByteOrder.nativeOrder()): ByteArray =
        ByteBuffer.allocate(8).order(order).putLong(nanos).array()

    fun preSkipNanos(preSkip: Int = PRE_SKIP_SAMPLES): Long = preSkip * 1_000_000_000L / 48_000L

    /**
     * 16-bit little-endian PCM at [rate] Hz with [channels] channels ->
     * 16 kHz mono. Exact multiples (48 k, 32 k) average each group of samples
     * (a light low-pass, enough for 8 kHz speech); other rates interpolate.
     */
    fun toMono16k(pcm: ByteArray, length: Int, rate: Int, channels: Int): ByteArray {
        val ch = channels.coerceAtLeast(1)
        val frames = (length.coerceAtMost(pcm.size)) / (2 * ch)
        if (frames <= 0 || rate <= 0) return ByteArray(0)
        val mono = IntArray(frames)
        for (i in 0 until frames) {
            var sum = 0
            for (c in 0 until ch) {
                val o = (i * ch + c) * 2
                sum += ((pcm[o + 1].toInt() shl 8) or (pcm[o].toInt() and 0xff)).toShort().toInt()
            }
            mono[i] = sum / ch
        }
        val out: IntArray = when {
            rate == CALL_RATE -> mono
            rate % CALL_RATE == 0 -> {
                val f = rate / CALL_RATE
                IntArray(frames / f) { i ->
                    var s = 0
                    for (k in 0 until f) s += mono[i * f + k]
                    s / f
                }
            }
            else -> {
                val n = (frames.toLong() * CALL_RATE / rate).toInt()
                IntArray(n) { i ->
                    val pos = i.toDouble() * rate / CALL_RATE
                    val a = pos.toInt().coerceAtMost(frames - 1)
                    val b = (a + 1).coerceAtMost(frames - 1)
                    val t = pos - a
                    (mono[a] * (1 - t) + mono[b] * t).toInt()
                }
            }
        }
        val bytes = ByteArray(out.size * 2)
        for (i in out.indices) {
            val v = out[i].coerceIn(-32768, 32767)
            bytes[i * 2] = (v and 0xff).toByte()
            bytes[i * 2 + 1] = ((v shr 8) and 0xff).toByte()
        }
        return bytes
    }

    /** 20 ms of a sine at 16 kHz mono (self-test input). */
    fun sineFrame(index: Int, hz: Double = 440.0, amplitude: Int = 9000, frameSamples: Int = 320): ByteArray {
        val out = ByteArray(frameSamples * 2)
        for (i in 0 until frameSamples) {
            val n = index * frameSamples + i
            val v = (amplitude * Math.sin(2 * Math.PI * hz * n / CALL_RATE)).toInt()
            out[i * 2] = (v and 0xff).toByte()
            out[i * 2 + 1] = ((v shr 8) and 0xff).toByte()
        }
        return out
    }

    /** Pitch (Hz) of 16 kHz mono PCM by rising zero crossings. */
    fun estimateHz(pcm16k: ByteArray): Double {
        val n = pcm16k.size / 2
        if (n < 2) return 0.0
        var crossings = 0
        var prev = sample(pcm16k, 0)
        for (i in 1 until n) {
            val cur = sample(pcm16k, i)
            if (prev < 0 && cur >= 0) crossings++
            prev = cur
        }
        return crossings * CALL_RATE.toDouble() / n
    }

    /** Root-mean-square level of 16-bit PCM. */
    fun rms(pcm: ByteArray): Double {
        val n = pcm.size / 2
        if (n == 0) return 0.0
        var acc = 0.0
        for (i in 0 until n) { val s = sample(pcm, i).toDouble(); acc += s * s }
        return Math.sqrt(acc / n)
    }

    private fun sample(pcm: ByteArray, i: Int): Int =
        ((pcm[i * 2 + 1].toInt() shl 8) or (pcm[i * 2].toInt() and 0xff)).toShort().toInt()
}
