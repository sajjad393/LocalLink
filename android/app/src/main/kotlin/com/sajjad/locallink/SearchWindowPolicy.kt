package com.sajjad.locallink

/**
 * Bundle 200 (A): rules for one Wi-Fi Direct tag search window. Pure, so it
 * is easy to check. A window runs 20 s and is never restarted while it runs.
 */
object SearchWindowPolicy {
    const val WINDOW_MS = 20_000L
    const val BUSY_RETRY_MS = 3_000L
    const val RANDOM_OFFSET_MS = 3_000L
    /** A "peers changed" event starts a window at most this often. */
    const val PEERS_GAP_MS = 25_000L

    /** WifiP2pManager failure codes. */
    const val BUSY = 2
    const val NO_SERVICE_REQUESTS = 3

    enum class Retry { NONE, LATER, RESET }

    fun isOpen(startedAt: Long, now: Long): Boolean =
        startedAt > 0L && now >= startedAt && now - startedAt < WINDOW_MS

    fun onFailure(reason: Int, retried: Boolean, fixed: Boolean): Retry = when {
        reason == BUSY && !retried -> Retry.LATER
        reason == NO_SERVICE_REQUESTS && !fixed -> Retry.RESET
        else -> Retry.NONE
    }

    /** `n=2 list=realme C71/3/go,ZTE/3` (at most 6 names, 20 letters each). */
    fun peersLine(peers: List<Triple<String, Int, Boolean>>): String {
        val list = peers.take(6).joinToString(",") { (name, status, go) ->
            val clean = name.replace(Regex("[,\\s]+"), " ").trim().take(20)
            "$clean/$status" + if (go) "/go" else ""
        }
        return "n=${peers.size} list=${list.ifEmpty { "-" }}"
    }
}
