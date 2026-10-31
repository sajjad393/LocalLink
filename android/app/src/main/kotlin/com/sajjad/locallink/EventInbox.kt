package com.sajjad.locallink

/**
 * Bundle 175 (2): nearby events that arrive while no app engine listens
 * (app swiped away, Back exit, restart after a kill). Before 175 they were
 * dropped. They wait here (max [maxItems], max [maxAgeMs]) and go to the next
 * listener in arrival order. Pure Kotlin: unit tested on the JVM.
 */
class EventInbox(
    private val maxItems: Int = MAX_ITEMS,
    private val maxAgeMs: Long = MAX_AGE_MS,
) {
    data class Item(val type: String, val data: Map<String, Any?>, val key: String, val at: Long)

    private val items = ArrayDeque<Item>()
    private val keys = HashSet<String>()
    var dropped = 0
        private set

    val size: Int get() = items.size

    /** False when the event is not kept (type, repeat). */
    fun add(type: String, data: Map<String, Any?>, now: Long): Boolean {
        if (!keeps(type)) return false
        prune(now)
        val key = keyFor(type, data)
        if (!keys.add(key)) return false
        items.addLast(Item(type, data, key, now))
        while (items.size > maxItems) {
            keys.remove(items.removeFirst().key)
            dropped++
        }
        return true
    }

    /** Everything still fresh, oldest first; the inbox is empty afterwards. */
    fun drain(now: Long): List<Item> {
        prune(now)
        val out = items.toList()
        items.clear()
        keys.clear()
        return out
    }

    private fun prune(now: Long) {
        while (items.isNotEmpty() && now - items.first().at > maxAgeMs) {
            keys.remove(items.removeFirst().key)
            dropped++
        }
    }

    companion object {
        const val MAX_ITEMS = 500
        const val MAX_AGE_MS = 10 * 60_000L

        /** Only events that carry something for the user (chat, acks, call signals, files). */
        val KEPT_TYPES = setOf("message", "file_received", "file_cancelled", "file_failed")

        fun keeps(type: String): Boolean = type in KEPT_TYPES

        fun keyFor(type: String, data: Map<String, Any?>): String = when (type) {
            "message" -> "m|${data["sender_id"]}|${data["payload"]?.toString()?.hashCode()}|${data["payload"]?.toString()?.length}"
            else -> "$type|${data["transfer_id"] ?: data["file_id"]}|${data["message_id"]}"
        }
    }
}
