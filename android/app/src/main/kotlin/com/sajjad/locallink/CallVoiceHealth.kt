package com.sajjad.locallink

/**
 * Bundle 184 (A): exact voice counters, so a phone log proves where sound
 * went. One `CALL_VOICE_HEALTH` line every 10 s and one `CALL_VOICE_SUMMARY`
 * at the end. Logged as a warning (`!` in the log file) when less than 95 %
 * of the voice that arrived was played.
 *
 * Words in the line:
 * - arrived / played: 20 ms pieces that came / were heard.
 * - cut_talk: speech removed (only after a long freeze) - should be 0.
 * - cut_quiet: quiet pieces merged to catch up (not heard).
 * - squeezed: one pitch period taken out of speech to catch up.
 * - hidden: slots filled with repeated sound (lost or late pieces).
 * - lost / late: pieces that never came / came after their time.
 * - empty: Android's own "speaker ran out" count.
 * - rebuffer: line ran dry and was filled again (a short pause).
 * - buffer_ms / target_ms: line now / what the line aims for.
 * - gap_max_ms / bursts: longest wait between pieces / waits over 100 ms.
 * - played % counts merged quiet pieces as fine (only silence was removed).
 */
object CallVoiceHealth {
    const val LOG_EVERY_MS = 10_000L
    const val WARN_BELOW_PERCENT = 95

    data class Snapshot(
        val arrived: Long = 0,
        val played: Long = 0,
        val playedTalking: Long = 0,
        val arrivedTalking: Long = 0,
        val cutTalking: Long = 0,
        val cutQuiet: Long = 0,
        val squeezed: Long = 0,
        val concealed: Long = 0,
        val lost: Long = 0,
        val late: Long = 0,
        val overflow: Long = 0,
        val rebuffers: Long = 0,
        val underruns: Long = 0,
        val decoderEmpty: Long = 0,
        val micErrors: Long = 0,
        val txDropped: Long = 0,
        val encoderBursts: Long = 0,
        val udpTx: Long = 0,
        val tcpTx: Long = 0,
        val udpRx: Long = 0,
        val tcpRx: Long = 0,
        val recovered: Long = 0,
    ) {
        operator fun minus(o: Snapshot) = Snapshot(
            arrived - o.arrived, played - o.played, playedTalking - o.playedTalking, arrivedTalking - o.arrivedTalking,
            cutTalking - o.cutTalking, cutQuiet - o.cutQuiet, squeezed - o.squeezed, concealed - o.concealed,
            lost - o.lost, late - o.late, overflow - o.overflow, rebuffers - o.rebuffers,
            underruns - o.underruns, decoderEmpty - o.decoderEmpty, micErrors - o.micErrors,
            txDropped - o.txDropped, encoderBursts - o.encoderBursts, udpTx - o.udpTx, tcpTx - o.tcpTx,
            udpRx - o.udpRx, tcpRx - o.tcpRx, recovered - o.recovered,
        )
    }

    /** Live numbers that are not totals (taken at the moment of the line). */
    data class Now(
        val bufferMs: Int = 0,
        val targetMs: Int = 0,
        val maxGapMs: Long = 0,
        val bursts: Long = 0,
        val decodeMaxMs: Long = 0,
        val writeMaxMs: Long = 0,
        val speakerMs: Int = 0,
        val link: String = "-",
        val screenOn: Boolean? = null,
        val output: String = "-",
        val wifiLock: Boolean = false,
        val udp: Boolean = false,
    )

    fun playedPercent(s: Snapshot): Int {
        val heard = s.played + s.cutQuiet
        // Pieces that came too late count as arrived but not played.
        val came = s.arrived + s.late
        if (came <= 0L) return 100
        return ((heard * 100L) / came).toInt().coerceIn(0, 100)
    }

    fun warn(s: Snapshot): Boolean = s.arrived >= 50L && playedPercent(s) < WARN_BELOW_PERCENT

    fun line(tag: String, callId: String, s: Snapshot, n: Now): String = buildString {
        append(tag).append(" call=").append(callId)
        append(" played=").append(playedPercent(s)).append('%')
        append(" arrived=").append(s.arrived)
        append(" cut_talk=").append(s.cutTalking)
        append(" cut_quiet=").append(s.cutQuiet)
        append(" squeezed=").append(s.squeezed)
        append(" hidden=").append(s.concealed)
        append(" lost=").append(s.lost)
        append(" recovered=").append(s.recovered)
        append(" late=").append(s.late)
        append(" full=").append(s.overflow)
        append(" empty=").append(s.underruns)
        append(" rebuffer=").append(s.rebuffers)
        append(" dec_empty=").append(s.decoderEmpty)
        append(" buffer_ms=").append(n.bufferMs)
        append(" target_ms=").append(n.targetMs)
        append(" speaker_ms=").append(n.speakerMs)
        append(" gap_max_ms=").append(n.maxGapMs)
        append(" bursts=").append(n.bursts)
        append(" dec_max_ms=").append(n.decodeMaxMs)
        append(" write_max_ms=").append(n.writeMaxMs)
        append(" mic_err=").append(s.micErrors)
        append(" tx_drop=").append(s.txDropped)
        append(" enc_burst=").append(s.encoderBursts)
        append(" udp=").append(if (n.udp) 1 else 0)
        append(" udp_tx=").append(s.udpTx)
        append(" tcp_tx=").append(s.tcpTx)
        append(" udp_rx=").append(s.udpRx)
        append(" tcp_rx=").append(s.tcpRx)
        append(" link=").append(n.link)
        append(" screen=").append(when (n.screenOn) { true -> "on"; false -> "off"; null -> "-" })
        append(" out=").append(n.output)
        append(" wifi_lock=").append(if (n.wifiLock) 1 else 0)
    }
}

/**
 * Bundle 189 (B): call sound facts, log only (ZTE "voice breaks" check):
 * call volume, where the sound really goes, battery, battery saver, mic
 * mute and audio mode. One `CALL_SOUND_STATE` line when something changes,
 * at most one per 10 s health tick, else once a minute, plus one at the end.
 */
object CallSoundState {
    const val EVERY_MS = 60_000L

    data class State(
        val volume: Int = -1,
        val volumeMax: Int = -1,
        val output: String = "-",
        val batteryPercent: Int = -1,
        val charging: Boolean? = null,
        val saver: Boolean? = null,
        val micMuted: Boolean? = null,
        val mode: Int = -99,
    )

    /** Battery moves in steps of 5 % so it does not log every tick. */
    fun key(s: State): String =
        "${s.volume}|${s.volumeMax}|${s.output}|${s.saver}|${s.charging}|${s.micMuted}|${s.mode}|" +
            (if (s.batteryPercent < 0) -1 else s.batteryPercent / 5)

    fun due(now: Long, lastAt: Long, lastKey: String?, s: State): Boolean =
        lastKey == null || key(s) != lastKey || now - lastAt !in 0 until EVERY_MS

    fun modeName(mode: Int): String = when (mode) {
        0 -> "normal"
        1 -> "ringtone"
        2 -> "in_call"
        3 -> "communication"
        -99 -> "-"
        else -> "other_$mode"
    }

    private fun yn(b: Boolean?) = when (b) { true -> "y"; false -> "n"; null -> "-" }

    fun line(callId: String, s: State, moment: String): String = buildString {
        append("CALL_SOUND_STATE call=").append(callId)
        append(" at=").append(moment)
        append(" vol=").append(if (s.volume < 0) "-" else s.volume.toString())
        append('/').append(if (s.volumeMax < 0) "-" else s.volumeMax.toString())
        append(" out=").append(s.output)
        append(" battery=").append(if (s.batteryPercent < 0) "-" else "${s.batteryPercent}%")
        append(" charging=").append(yn(s.charging))
        append(" saver=").append(yn(s.saver))
        append(" mic_mute=").append(yn(s.micMuted))
        append(" mode=").append(modeName(s.mode))
    }
}
