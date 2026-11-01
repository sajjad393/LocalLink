package com.sajjad.locallink

import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor

/**
 * Bundle 191 (A): turns on the phone's own echo cancel and noise reduction
 * for the call microphone, when the phone offers them. Every step is
 * guarded: a failure here never stops the call. Release before the
 * microphone is released.
 */
class CallMicEffects private constructor(
    private var echo: AcousticEchoCanceler?,
    private var noise: NoiseSuppressor?,
    val echoResult: CallMicEffectsPolicy.Result,
    val noiseResult: CallMicEffectsPolicy.Result,
) {
    fun release() {
        try { echo?.release() } catch (_: Throwable) {}
        try { noise?.release() } catch (_: Throwable) {}
        echo = null
        noise = null
    }

    companion object {
        fun attach(sessionId: Int): CallMicEffects {
            var echo: AcousticEchoCanceler? = null
            var noise: NoiseSuppressor? = null
            val echoResult = try {
                val available = AcousticEchoCanceler.isAvailable()
                if (available) echo = AcousticEchoCanceler.create(sessionId)
                val wasOn = try { echo?.enabled == true } catch (_: Throwable) { false }
                if (echo != null && !wasOn) { try { echo?.enabled = true } catch (_: Throwable) {} }
                val isOn = try { echo?.enabled == true } catch (_: Throwable) { false }
                CallMicEffectsPolicy.result(available, echo != null, wasOn, isOn, false)
            } catch (_: Throwable) {
                try { echo?.release() } catch (_: Throwable) {}
                echo = null
                CallMicEffectsPolicy.Result.FAIL
            }
            val noiseResult = try {
                val available = NoiseSuppressor.isAvailable()
                if (available) noise = NoiseSuppressor.create(sessionId)
                val wasOn = try { noise?.enabled == true } catch (_: Throwable) { false }
                if (noise != null && !wasOn) { try { noise?.enabled = true } catch (_: Throwable) {} }
                val isOn = try { noise?.enabled == true } catch (_: Throwable) { false }
                CallMicEffectsPolicy.result(available, noise != null, wasOn, isOn, false)
            } catch (_: Throwable) {
                try { noise?.release() } catch (_: Throwable) {}
                noise = null
                CallMicEffectsPolicy.Result.FAIL
            }
            return CallMicEffects(echo, noise, echoResult, noiseResult)
        }
    }
}
