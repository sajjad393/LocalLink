package com.sajjad.locallink

import java.util.TreeMap
import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * Bundle 184 (B): the waiting line on the listening phone. Plain Kotlin, no
 * Android parts, so the whole thing is unit-tested with simulated networks.
 *
 * The 179 line played sound the moment it arrived and cut everything above
 * 120 ms at once. On a phone whose Wi-Fi naps (screen off) the sound arrives
 * in bunches: the speaker ran empty, then the bunch was cut. In the
 * 2026-11-01 logs only 43-56 % of the voice that arrived was played.
 *
 * Now:
 * - The line size follows how bunchy the arrivals were in the last 3 s
 *   (60 ms .. 300 ms, Q1). It grows at once and shrinks slowly.
 * - Playing starts (and starts again after a long break) only when the line
 *   holds the target. No dribbling.
 * - Catching up never cuts words: only when the line stayed fuller than
 *   needed for 2 s. Two quiet pieces become one (5 ms fade); in speech one
 *   pitch period is taken out of two pieces (sounds the same, ~10 % faster).
 *   Only above 500 ms (a long freeze) are old pieces dropped.
 * - Missing sound is hidden: the last pitch period is repeated softer
 *   (-3, -8, -100 dB) for at most 60 ms, then silence; real sound fades back in.
 *
 * Every call to [pull] gives the sound for the next speaker slot (normally
 * 20 ms; a squeezed slot is shorter). Not thread-safe: the caller locks.
 */
class CallJitterBuffer(
    private val minTarget: Int = MIN_TARGET_FRAMES,
    private val maxTarget: Int = MAX_TARGET_FRAMES,
    private val hardMax: Int = HARD_MAX_FRAMES,
) {
    companion object {
        const val FRAME_MS = 20
        const val FRAME_SAMPLES = 320
        /** 60 ms: never less than this in the line before playing. */
        const val MIN_TARGET_FRAMES = 3
        /** 80 ms until enough arrivals were measured. */
        const val START_TARGET_FRAMES = 4
        /** 300 ms: the biggest line we aim for (Q1). */
        const val MAX_TARGET_FRAMES = 15
        /** 500 ms: above this old sound is dropped (long freeze only). */
        const val HARD_MAX_FRAMES = 25
        /** 1 s: nothing more is kept. */
        const val MAX_STORED = 50
        /** At most 60 ms of hidden (repeated) sound in a row. */
        const val CONCEAL_MAX = 3
        const val DELAY_WINDOW = 150
        const val LEVEL_WINDOW = 100
        const val RECALC_EVERY = 25
        const val SHRINK_EVERY_PULLS = 250
        /** Line must be this full for 2 s before catching up. */
        const val CATCH_UP_MIN_LEVEL = 2
        /** Talking may only be cut (not squeezed) this far above the target. */
        const val TALK_CUT_OVER = 10
        const val FADE = 64
        const val QUIET_RMS = 300.0
        const val QUIET_SHARE = 0.12
        const val MIN_LAG = 40
        const val MAX_LAG = 240
        const val PERIODIC_CORR = 0.5
        /** A stream that went this far backwards / forwards is a new stream. */
        const val RESET_JUMP = 400L
        const val RESET_LATE_RUN = 25
        private val CONCEAL_GAINS = doubleArrayOf(1.0, 0.7, 0.4, 0.0)
    }

    enum class Kind { NORMAL, SQUEEZED, CONCEALED, SILENCE }

    class Out(val pcm: ShortArray, val kind: Kind)

    /** Totals since the start (the caller takes window differences). */
    class Counters {
        var arrived = 0L
        var played = 0L
        var squeezed = 0L
        var cutQuiet = 0L
        var cutTalking = 0L
        var late = 0L
        var duplicate = 0L
        var overflow = 0L
        var concealed = 0L
        var lost = 0L
        var rebuffers = 0L
        var silence = 0L
        var resets = 0L
        var bursts = 0L
        var maxGapMs = 0L
        var playedTalking = 0L
        var arrivedTalking = 0L
    }

    val counters = Counters()

    private val frames = TreeMap<Long, ShortArray>()
    private var nextSeq = -1L
    private var playing = false
    private var fadeInNext = true
    private var lateRun = 0

    // Hidden sound.
    private var concealRun = 0
    private var concealLag = 160
    private var concealPos = 0
    private val history = ShortArray(FRAME_SAMPLES * 3)
    private var historyLen = 0

    // Arrival delay (how bunchy the network is).
    private val delays = LongArray(DELAY_WINDOW)
    private var delayCount = 0
    private var delayIndex = 0
    private var sinceRecalc = 0
    private var lastArrivalMs = 0L
    var target = START_TARGET_FRAMES
        private set
    private var pullsSinceShrink = 0

    // Line level at each pull (catch up only if it never ran low).
    private val levels = IntArray(LEVEL_WINDOW)
    private var levelCount = 0
    private var levelIndex = 0
    private var pulls = 0L
    private var lastSqueezePull = -10L
    private var speechRms = 1_000.0

    val stored: Int get() = frames.size
    val isPlaying: Boolean get() = playing
    val targetMs: Int get() = target * FRAME_MS
    val storedMs: Int get() = frames.size * FRAME_MS

    /** True when this sequence would be dropped as too late (skip decoding it). */
    fun isLate(seq: Long): Boolean = nextSeq >= 0 && seq < nextSeq && nextSeq - seq < RESET_JUMP

    /**
     * One decoded 20 ms piece arrived. [arrivalMs] = when the network handed
     * it over (not when it was decoded). False = not kept (late / twice).
     */
    fun insert(seq: Long, pcm: ShortArray, arrivalMs: Long): Boolean {
        if (nextSeq >= 0) {
            val jumpBack = seq < nextSeq && nextSeq - seq >= RESET_JUMP
            val jumpForward = seq >= nextSeq + RESET_JUMP
            if (jumpForward) {
                // The other phone's numbers jumped far ahead: start over.
                resetStream()
            } else if (jumpBack) {
                // Far behind many times in a row = the other phone restarted
                // its voice (numbers began again at 0).
                if (++lateRun >= RESET_LATE_RUN) resetStream() else {
                    counters.late++
                    return false
                }
            }
        }
        if (nextSeq >= 0 && seq < nextSeq) {
            counters.late++
            return false
        }
        lateRun = 0
        if (frames.containsKey(seq)) {
            counters.duplicate++
            return false
        }
        if (frames.size >= MAX_STORED) {
            frames.pollFirstEntry()
            counters.overflow++
        }
        frames[seq] = pcm
        counters.arrived++
        if (!isQuiet(pcm)) counters.arrivedTalking++
        if (lastArrivalMs > 0L) {
            val gap = arrivalMs - lastArrivalMs
            if (gap > counters.maxGapMs) counters.maxGapMs = gap
            if (gap > 100L) counters.bursts++
        }
        lastArrivalMs = arrivalMs
        noteDelay(arrivalMs - seq * FRAME_MS)
        return true
    }

    /** Sound for the next speaker slot. Never null, never empty. */
    fun pull(): Out {
        pulls++
        pullsSinceShrink++
        if (!playing) {
            if (frames.isEmpty() || frames.size < target) {
                counters.silence++
                return silence()
            }
            playing = true
            nextSeq = frames.firstKey()
            fadeInNext = true
            concealRun = 0
        }
        val level = frames.size
        noteLevel(level)
        if (level > hardMax) dropOldestTo(target)
        var cur = frames.remove(nextSeq)
        if (cur == null) {
            if (frames.isNotEmpty()) {
                // A gap: these pieces never came (lost). Hide one slot, or jump
                // straight to the next real piece after a long gap.
                val gap = frames.firstKey() - nextSeq
                if (gap > CONCEAL_MAX || concealRun >= CONCEAL_MAX) {
                    counters.lost += gap
                    if (concealRun == 0) fadeInNext = true
                    nextSeq = frames.firstKey()
                    cur = frames.remove(nextSeq)!!
                } else {
                    counters.lost++
                    nextSeq++
                    return conceal()
                }
            } else {
                // Line is empty: stretch the sound a little while waiting.
                if (concealRun < CONCEAL_MAX) return conceal()
                playing = false
                counters.rebuffers++
                counters.silence++
                concealRun = 0
                fadeInNext = true
                return silence()
            }
        }
        nextSeq++
        val catchUp = (minLevel() >= CATCH_UP_MIN_LEVEL && level > target) || level > target + TALK_CUT_OVER
        if (catchUp && pulls - lastSqueezePull >= 2) {
            val next = frames[nextSeq]
            if (next != null) {
                val squeezed = squeeze(cur, next, allowTalkCut = level > target + TALK_CUT_OVER)
                if (squeezed != null) {
                    frames.remove(nextSeq)
                    nextSeq++
                    lastSqueezePull = pulls
                    return squeezed
                }
            }
        }
        return playReal(cur, Kind.NORMAL, 1, if (isQuiet(cur)) 0 else 1)
    }

    // ---- inside ----

    private fun resetStream() {
        frames.clear()
        nextSeq = -1L
        playing = false
        fadeInNext = true
        concealRun = 0
        lateRun = 0
        delayCount = 0
        delayIndex = 0
        levelCount = 0
        levelIndex = 0
        lastArrivalMs = 0L
        counters.resets++
    }

    private fun dropOldestTo(keep: Int) {
        while (frames.size > keep) {
            val e = frames.pollFirstEntry() ?: break
            if (isQuiet(e.value)) counters.cutQuiet++ else counters.cutTalking++
        }
        frames.firstEntry()?.let { nextSeq = it.key }
        fadeInNext = true
    }

    private fun noteDelay(d: Long) {
        delays[delayIndex] = d
        delayIndex = (delayIndex + 1) % DELAY_WINDOW
        if (delayCount < DELAY_WINDOW) delayCount++
        if (++sinceRecalc < RECALC_EVERY || delayCount < RECALC_EVERY) return
        sinceRecalc = 0
        val sorted = delays.copyOf(delayCount).also { it.sort() }
        val p95 = sorted[((delayCount - 1) * 95) / 100]
        val spread = (p95 - sorted[0]).coerceAtLeast(0L)
        val wanted = (ceil(spread / FRAME_MS.toDouble()).toInt() + 1).coerceIn(minTarget, maxTarget)
        if (wanted > target) {
            target = wanted
            pullsSinceShrink = 0
        } else if (wanted < target && pullsSinceShrink >= SHRINK_EVERY_PULLS) {
            target--
            pullsSinceShrink = 0
        }
    }

    private fun noteLevel(level: Int) {
        levels[levelIndex] = level
        levelIndex = (levelIndex + 1) % LEVEL_WINDOW
        if (levelCount < LEVEL_WINDOW) levelCount++
    }

    private fun minLevel(): Int {
        if (levelCount < LEVEL_WINDOW) return 0
        var m = Int.MAX_VALUE
        for (i in 0 until levelCount) if (levels[i] < m) m = levels[i]
        return m
    }

    fun isQuiet(pcm: ShortArray): Boolean {
        val r = rms(pcm, 0, pcm.size)
        return r < QUIET_RMS || r < speechRms * QUIET_SHARE
    }

    /** Two pieces in, one shorter slot out; null = keep them as they are. */
    private fun squeeze(a: ShortArray, b: ShortArray, allowTalkCut: Boolean): Out? {
        val quietA = isQuiet(a)
        val quietB = isQuiet(b)
        if (quietA && quietB) {
            counters.cutQuiet++
            return playReal(crossfade(a, b), Kind.SQUEEZED, 1, 0)
        }
        val block = ShortArray(a.size + b.size)
        a.copyInto(block)
        b.copyInto(block, a.size)
        val (lag, corr) = bestLag(block)
        if (corr >= PERIODIC_CORR || quietA || quietB) {
            counters.squeezed++
            val talking = (if (quietA) 0 else 1) + (if (quietB) 0 else 1)
            return playReal(removePeriod(block, lag), Kind.SQUEEZED, 2, talking)
        }
        if (!allowTalkCut) return null
        counters.cutTalking++
        return playReal(crossfade(a, b), Kind.SQUEEZED, 1, 1)
    }

    private fun playReal(pcm: ShortArray, kind: Kind, framesUsed: Int, talking: Int): Out {
        val out = pcm.copyOf()
        val n = minOf(FADE, out.size)
        if (concealRun > 0 && historyLen >= MAX_LAG + 160) {
            // Coming back from hidden sound: blend the repeat into the real sound.
            val g = CONCEAL_GAINS[concealRun.coerceAtMost(CONCEAL_MAX)]
            for (i in 0 until n) {
                val w = i / n.toDouble()
                val rep = periodSample(concealPos + i) * g
                out[i] = clip(out[i] * w + rep * (1 - w))
            }
        } else if (fadeInNext) {
            for (i in 0 until n) out[i] = clip(out[i] * (i / n.toDouble()))
        }
        concealRun = 0
        fadeInNext = false
        counters.played += framesUsed
        counters.playedTalking += talking
        val r = rms(pcm, 0, pcm.size)
        speechRms = if (r > speechRms) r else maxOf(1_000.0, speechRms * 0.999)
        remember(out)
        return Out(out, kind)
    }

    private fun conceal(): Out {
        if (historyLen < MAX_LAG + 160) {
            concealRun++
            counters.concealed++
            fadeInNext = true
            return silence()
        }
        if (concealRun == 0) {
            concealLag = lagOfHistory()
            concealPos = 0
        }
        val g0 = CONCEAL_GAINS[concealRun]
        val g1 = CONCEAL_GAINS[concealRun + 1]
        val out = ShortArray(FRAME_SAMPLES)
        for (i in 0 until FRAME_SAMPLES) {
            val g = g0 + (g1 - g0) * (i / FRAME_SAMPLES.toDouble())
            out[i] = clip(periodSample(concealPos + i) * g)
        }
        concealPos += FRAME_SAMPLES
        concealRun++
        counters.concealed++
        return Out(out, Kind.CONCEALED)
    }

    private fun periodSample(k: Int): Double {
        val lag = concealLag.coerceIn(1, historyLen)
        return history[historyLen - lag + (k % lag)].toDouble()
    }

    private fun remember(pcm: ShortArray) {
        if (pcm.size >= history.size) {
            pcm.copyInto(history, 0, pcm.size - history.size, pcm.size)
            historyLen = history.size
            return
        }
        val keep = minOf(historyLen, history.size - pcm.size)
        history.copyInto(history, 0, historyLen - keep, historyLen)
        pcm.copyInto(history, keep)
        historyLen = keep + pcm.size
    }

    private fun lagOfHistory(): Int {
        val n = 160
        val end = historyLen
        var best = 160
        var bestCorr = -1.0
        for (lag in MIN_LAG..MAX_LAG) {
            if (end - n - lag < 0) break
            val c = corr(history, end - n, history, end - n - lag, n)
            if (c > bestCorr) { bestCorr = c; best = lag }
        }
        return if (bestCorr >= 0.3) best else 160
    }

    /** Best pitch period in a 40 ms block, and how alike the periods are (0..1). */
    fun bestLag(block: ShortArray): Pair<Int, Double> {
        val n = block.size - MAX_LAG
        var best = MIN_LAG
        var bestCorr = -1.0
        if (n <= 0) return best to 0.0
        for (lag in MIN_LAG..MAX_LAG) {
            val c = corr(block, 0, block, lag, n)
            if (c > bestCorr) { bestCorr = c; best = lag }
        }
        return best to bestCorr
    }

    private fun corr(a: ShortArray, ao: Int, b: ShortArray, bo: Int, n: Int): Double {
        var ab = 0.0; var aa = 0.0; var bb = 0.0
        for (i in 0 until n) {
            val x = a[ao + i].toDouble(); val y = b[bo + i].toDouble()
            ab += x * y; aa += x * x; bb += y * y
        }
        if (aa <= 0.0 || bb <= 0.0) return 0.0
        return ab / sqrt(aa * bb)
    }

    /** Takes one period out: the two copies are blended over [lag] samples. */
    fun removePeriod(block: ShortArray, lag: Int): ShortArray {
        val out = ShortArray(block.size - lag)
        for (i in 0 until lag) {
            val w = i / lag.toDouble()
            out[i] = clip(block[i] * (1 - w) + block[i + lag] * w)
        }
        for (j in lag until out.size) out[j] = block[j + lag]
        return out
    }

    private fun crossfade(a: ShortArray, b: ShortArray): ShortArray {
        val out = ShortArray(a.size)
        for (i in a.indices) {
            val w = i / a.size.toDouble()
            out[i] = clip(a[i] * (1 - w) + b.getOrElse(i) { 0 } * w)
        }
        return out
    }

    private fun silence() = Out(ShortArray(FRAME_SAMPLES), Kind.SILENCE)

    private fun clip(v: Double): Short = v.coerceIn(-32768.0, 32767.0).toInt().toShort()

    private fun rms(pcm: ShortArray, from: Int, to: Int): Double {
        if (to <= from) return 0.0
        var s = 0.0
        for (i in from until to) { val v = pcm[i].toDouble(); s += v * v }
        return sqrt(s / (to - from))
    }
}

/** Bundle 184: little-endian 16-bit PCM <-> samples. */
object CallPcm {
    fun toShorts(bytes: ByteArray, length: Int = bytes.size): ShortArray {
        val n = length / 2
        val out = ShortArray(n)
        for (i in 0 until n) out[i] = ((bytes[2 * i].toInt() and 0xFF) or (bytes[2 * i + 1].toInt() shl 8)).toShort()
        return out
    }

    fun toBytes(samples: ShortArray): ByteArray {
        val out = ByteArray(samples.size * 2)
        for (i in samples.indices) {
            val v = samples[i].toInt()
            out[2 * i] = (v and 0xFF).toByte()
            out[2 * i + 1] = (v shr 8).toByte()
        }
        return out
    }
}
