package com.sajjad.locallink

/**
 * Bundle 179 (2): "call X was accepted on the notification" is remembered
 * for [KEEP_MS] so ONE Accept connects the call even when a slow phone
 * rebuilds the screen or the call only arrives in the app later. Pure.
 */
object CallAcceptPolicy {
    const val KEEP_MS = 60_000L

    fun valid(savedAtMs: Long, nowMs: Long): Boolean =
        savedAtMs > 0L && nowMs >= savedAtMs && nowMs - savedAtMs <= KEEP_MS

    fun remainingMs(savedAtMs: Long, nowMs: Long): Long =
        if (valid(savedAtMs, nowMs)) KEEP_MS - (nowMs - savedAtMs) else 0L

    /** Only the same call from the same caller is answered. */
    fun matches(savedCallId: String, savedCallerId: String, callId: String, callerId: String): Boolean =
        savedCallId.isNotBlank() && savedCallerId.isNotBlank() &&
            savedCallId == callId && savedCallerId == callerId
}
