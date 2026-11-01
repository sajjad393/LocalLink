package com.sajjad.locallink

import android.content.Context
import android.util.Log

/**
 * Bundle 179 (2.1): the notification Accept, kept for 60 s in a small private
 * file (survives the screen being rebuilt and the app engine restarting).
 * The app reads it, answers the matching ringing call once, then clears it.
 */
object CallAcceptMemory {
    private const val PREFS = "locallink_call_accept"
    private const val KEY_CALL = "call_id"
    private const val KEY_CALLER = "caller_id"
    private const val KEY_AT = "saved_at"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(context: Context, callId: String, callerId: String) {
        if (callId.isBlank() || callerId.isBlank()) return
        try {
            prefs(context).edit()
                .putString(KEY_CALL, callId)
                .putString(KEY_CALLER, callerId)
                .putLong(KEY_AT, System.currentTimeMillis())
                .commit()
            Log.i("LocalLinkCall", "CALL_ACCEPT_SAVED call=$callId")
        } catch (_: Exception) {}
    }

    /** The saved Accept while it is still fresh, else null (an old one is removed). */
    fun peek(context: Context): Map<String, Any>? {
        return try {
            val p = prefs(context)
            val callId = p.getString(KEY_CALL, null).orEmpty()
            val callerId = p.getString(KEY_CALLER, null).orEmpty()
            val at = p.getLong(KEY_AT, 0L)
            if (callId.isBlank() || callerId.isBlank()) return null
            val now = System.currentTimeMillis()
            if (!CallAcceptPolicy.valid(at, now)) {
                Log.i("LocalLinkCall", "CALL_ACCEPT_EXPIRED call=$callId where=native")
                p.edit().clear().commit()
                return null
            }
            mapOf("call_id" to callId, "caller_id" to callerId, "remaining_ms" to CallAcceptPolicy.remainingMs(at, now))
        } catch (_: Exception) { null }
    }

    /** Forget it ([callId] blank = whatever is saved). */
    fun clear(context: Context, callId: String?) {
        try {
            val p = prefs(context)
            val saved = p.getString(KEY_CALL, null) ?: return
            if (callId.isNullOrBlank() || callId == saved) p.edit().clear().commit()
        } catch (_: Exception) {}
    }
}
