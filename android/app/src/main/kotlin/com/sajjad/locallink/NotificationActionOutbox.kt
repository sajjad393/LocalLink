package com.sajjad.locallink

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bundle 162 (4.1): Reply / Mark read tapped on a notification while the app
 * screen is closed. Android 12+ blocks opening the app from a notification
 * button, and the chat code (which locks messages end to end) lives in the
 * app, so the action is saved here and handed to the app the next time it
 * starts. Nothing is lost.
 */
object NotificationActionOutbox {
    private const val PREFS = "locallink_notification_outbox"
    private const val KEY = "pending_v1"

    /** Never keep more than this many (oldest dropped). */
    const val MAX_PENDING = 50

    /** Older than this is dropped (the chat moved on). */
    const val MAX_AGE_MS = 7L * 24L * 60L * 60L * 1000L

    @Synchronized
    fun add(context: Context, event: Map<String, Any?>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = decode(prefs.getString(KEY, null))
        val item = JSONObject()
        for ((k, v) in event) if (v != null) item.put(k, v)
        item.put("saved_at", System.currentTimeMillis())
        list.add(item)
        prefs.edit().putString(KEY, encode(trim(list, System.currentTimeMillis()))).apply()
    }

    /** Returns everything saved and clears it. */
    @Synchronized
    fun takeAll(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        prefs.edit().remove(KEY).apply()
        return trim(decode(raw), System.currentTimeMillis()).map { toMap(it) }
    }

    @Synchronized
    fun count(context: Context): Int =
        decode(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)).size

    // ------------------------------------------------------------ pure parts

    fun trim(list: List<JSONObject>, now: Long): List<JSONObject> =
        list.filter { now - it.optLong("saved_at", now) <= MAX_AGE_MS }.takeLast(MAX_PENDING)

    fun decode(raw: String?): MutableList<JSONObject> {
        if (raw.isNullOrBlank()) return mutableListOf()
        return try {
            val arr = JSONArray(raw)
            MutableList(arr.length()) { arr.getJSONObject(it) }
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    fun encode(list: List<JSONObject>): String {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        return arr.toString()
    }

    fun toMap(o: JSONObject): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        val keys = o.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            if (k == "saved_at") continue
            out[k] = o.opt(k)
        }
        return out
    }
}
