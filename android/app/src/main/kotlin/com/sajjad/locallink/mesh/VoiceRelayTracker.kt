package com.sajjad.locallink.mesh

/**
 * Bundle 167 (5.5): is someone else's voice call passing through this phone?
 *
 * In a Wi-Fi Direct group every member talks through the host, so a call
 * between two members passes through the host even when the host itself is
 * not in a call. The app uses this to keep the host from closing or moving
 * its group under that call (group merge, D3).
 *
 * - [onForward] for each voice frame passed on; true = tell the app "on"
 *   (first frame, then again every [refreshMs] so the app never times out);
 * - [onTick] from the maintenance loop; true = tell the app "off" (no voice
 *   for [idleMs]).
 */
class VoiceRelayTracker(
    private val idleMs: Long = IDLE_MS,
    private val refreshMs: Long = REFRESH_MS,
) {
    companion object {
        const val IDLE_MS = 8_000L
        const val REFRESH_MS = 10_000L
    }

    private var lastFrameAt = 0L
    private var lastOnSentAt = 0L
    private var active = false

    @Synchronized
    fun onForward(now: Long): Boolean {
        lastFrameAt = now
        if (!active || now - lastOnSentAt >= refreshMs) {
            active = true
            lastOnSentAt = now
            return true
        }
        return false
    }

    @Synchronized
    fun onTick(now: Long): Boolean {
        if (!active || now - lastFrameAt < idleMs) return false
        active = false
        lastOnSentAt = 0L
        return true
    }

    @Synchronized
    fun isActive(now: Long): Boolean = active && now - lastFrameAt < idleMs
}
