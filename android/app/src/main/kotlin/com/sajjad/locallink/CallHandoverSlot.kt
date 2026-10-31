package com.sajjad.locallink

/**
 * Bundle 176 (3): the ringing call invite, handed from one app engine to the
 * next (no-screen engine -> app when it opens, or app -> no-screen engine when
 * it is swiped away while ringing). The caller stops re-sending its invite once
 * it hears "ringing", so without this the opened app would never see the call.
 *
 * Memory only (never written to disk: it can hold the call's voice key).
 * Expires after [MAX_AGE_MS] (the ring time). Pure Kotlin: unit tested.
 */
class CallHandoverSlot(private val maxAgeMs: Long = MAX_AGE_MS) {
    private var callId: String? = null
    private var invite: String? = null
    private var at = 0L

    @Synchronized
    fun park(id: String, json: String, now: Long): Boolean {
        if (id.isBlank() || id.length > 128 || json.isBlank() || json.length > MAX_JSON) return false
        callId = id; invite = json; at = now
        return true
    }

    /** The invite if still fresh; the slot is empty afterwards. */
    @Synchronized
    fun take(now: Long): String? {
        val out = if (invite != null && now - at <= maxAgeMs) invite else null
        callId = null; invite = null; at = 0L
        return out
    }

    @Synchronized
    fun clear(id: String) {
        if (id.isBlank() || id == callId) { callId = null; invite = null; at = 0L }
    }

    @Synchronized
    fun parkedCallId(now: Long): String? = if (invite != null && now - at <= maxAgeMs) callId else null

    companion object {
        const val MAX_AGE_MS = 60_000L
        const val MAX_JSON = 16_384
    }
}
