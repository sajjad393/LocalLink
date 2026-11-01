package com.sajjad.locallink

/**
 * Bundle 179 (1): voice delay rules. Pure, unit-tested.
 *
 * Before 179 the sound could wait in four places that never drained
 * (microphone buffer 160 ms, a send that blocked the microphone, a 240 ms
 * receive line and a 240 ms speaker buffer), so after one network hiccup the
 * call stayed about 1 s late. Now every line is short, and when one grows
 * the OLDEST sound is skipped so the call catches up (a tiny gap instead of
 * late sound - how normal phone calls behave).
 */
object CallAudioLatencyPolicy {
    const val FRAME_MS = 20

    /** Receive line: aim 60 ms, never more than 120 ms. */
    const val RX_TARGET_FRAMES = 3
    const val RX_MAX_FRAMES = 6

    /** Speaker (AudioTrack) buffer: about 80 ms (was 12 frames = 240 ms). */
    const val SPEAKER_BUFFER_FRAMES = 4

    /** Sending line: max 60 ms; a stuck network drops the oldest sound. */
    const val TX_MAX_FRAMES = 3

    /** Microphone (AudioRecord) buffer: about 80 ms (was 8 frames = 160 ms). */
    const val MIC_BUFFER_FRAMES = 4

    /** One CALL_AUDIO_DELAY log line per this period. */
    const val LOG_EVERY_MS = 10_000L

    /**
     * How many of the oldest frames to skip so the receive line is back at
     * the target. 0 while the line is short enough.
     */
    fun rxFramesToSkip(queued: Int): Int =
        if (queued > RX_MAX_FRAMES) queued - RX_TARGET_FRAMES else 0

    /** How many of the oldest frames to drop before adding one to the sending line. */
    fun txFramesToDrop(queued: Int): Int =
        if (queued >= TX_MAX_FRAMES) queued - TX_MAX_FRAMES + 1 else 0

    fun speakerBufferBytes(minBytes: Int, frameBytes: Int): Int =
        maxOf(minBytes, frameBytes * SPEAKER_BUFFER_FRAMES)

    fun micBufferBytes(minBytes: Int, frameBytes: Int): Int =
        maxOf(minBytes, frameBytes * MIC_BUFFER_FRAMES)

    fun queueMs(frames: Int): Int = if (frames <= 0) 0 else frames * FRAME_MS

    /**
     * Sound handed to the speaker but not heard yet, in ms (log only).
     * Odd numbers (head ahead of what we wrote, bad rate) give 0.
     */
    fun speakerBacklogMs(writtenSamples: Long, playedSamples: Long, sampleRate: Int): Int {
        if (sampleRate <= 0) return 0
        val backlog = writtenSamples - playedSamples
        if (backlog <= 0) return 0
        return (backlog * 1000L / sampleRate).coerceAtMost(60_000L).toInt()
    }

    /** True when a new log line is due. */
    fun logDue(nowMs: Long, lastLogMs: Long): Boolean =
        lastLogMs <= 0L || nowMs - lastLogMs >= LOG_EVERY_MS || nowMs < lastLogMs

    fun delayLogLine(callId: String, rxQueueMs: Int, speakerMs: Int, txQueueMs: Int, skipped: Long): String =
        "CALL_AUDIO_DELAY call=$callId rx_queue_ms=$rxQueueMs speaker_ms=$speakerMs tx_queue_ms=$txQueueMs skipped=$skipped"
}

/**
 * Bundle 179 (1.6): files wait while a voice call is live, so a big file
 * never fights the voice on the same link. Messages are not touched.
 *
 * A paused file is kept alive: after [MAX_PAUSE_MS] it sends anyway (the
 * other phone forgets a half-received file after 10 minutes of silence).
 */
object CallFilePausePolicy {
    const val MAX_PAUSE_MS = 8L * 60L * 1000L

    /** Wait for the call to end before the file restarts. */
    const val RESUME_DELAY_MS = 1_500L

    /** [pausedAtMs] = when this file was paused (null = not paused yet, -1 = limit reached). */
    fun shouldPause(callLive: Boolean, pausedAtMs: Long?, nowMs: Long): Boolean {
        if (!callLive) return false
        if (pausedAtMs == null) return true
        if (pausedAtMs < 0L) return false // limit reached during this call
        if (nowMs < pausedAtMs) return true
        return nowMs - pausedAtMs < MAX_PAUSE_MS
    }
}
