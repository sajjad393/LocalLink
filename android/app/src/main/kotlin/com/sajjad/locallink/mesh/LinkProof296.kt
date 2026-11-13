package com.sajjad.locallink.mesh

/**
 * Bundle 296 (H1): is a link proven right now (for the maps only)?
 *
 * Proven = our own ping got its pong back in the last [PROOF_MS], or bulk
 * data (a file chunk, a big locked message) came in on it in that time (a
 * busy link may answer pings late). The 15 s rule that closes a link does
 * not change; routing does not read this.
 */
object LinkProof296 {
    const val PROOF_MS: Long = 10_000L

    /** A line at least this long counts as bulk data coming in. */
    const val BULK_LINE_CHARS: Int = 4096

    fun proven(nowMs: Long, connectedAt: Long, lastPongAt: Long, lastBulkInAt: Long): Boolean {
        val pong = lastPongAt > connectedAt && nowMs - lastPongAt in 0..PROOF_MS
        val bulk = lastBulkInAt > 0L && nowMs - lastBulkInAt in 0..PROOF_MS
        return pong || bulk
    }

    /** Last own pong on this link, or 0 when none came yet. */
    fun lastPong(connectedAt: Long, lastPongAt: Long): Long = if (lastPongAt > connectedAt) lastPongAt else 0L
}
