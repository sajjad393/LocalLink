package com.sajjad.locallink

/**
 * Bundle 191 (A): the phone's own echo cancel and noise reduction on the
 * call microphone. Pure words for the `CALL_MIC_EFFECTS` log line, so a
 * phone log shows whether the phone has these tools and whether they ran.
 *
 * Words in the line:
 * - none: this phone does not offer the tool.
 * - already: the phone had it on by itself (voice call mode).
 * - on: LinkUp turned it on.
 * - off: offered, but it would not turn on.
 * - fail: Android threw an error (the call still goes on).
 */
object CallMicEffectsPolicy {
    enum class Result(val word: String) {
        NONE("none"),
        ALREADY("already"),
        ON("on"),
        OFF("off"),
        FAIL("fail"),
    }

    /** Result from what Android said. [error] wins over everything. */
    fun result(available: Boolean, created: Boolean, wasOn: Boolean, isOn: Boolean, error: Boolean): Result = when {
        error -> Result.FAIL
        !available -> Result.NONE
        !created -> Result.FAIL
        wasOn && isOn -> Result.ALREADY
        isOn -> Result.ON
        else -> Result.OFF
    }

    /** True when the echo cancel is working on this call. */
    fun echoCancelWorking(echo: Result): Boolean = echo == Result.ON || echo == Result.ALREADY

    fun line(callId: String, echo: Result, noise: Result, session: Int): String =
        "CALL_MIC_EFFECTS call=$callId echo_cancel=${echo.word} noise_cut=${noise.word} session=$session"

    /** Warn (`!` in the log file) when the echo cancel is not working. */
    fun warn(echo: Result): Boolean = !echoCancelWorking(echo)
}
