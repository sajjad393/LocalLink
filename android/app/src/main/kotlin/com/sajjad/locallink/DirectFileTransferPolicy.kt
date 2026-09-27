package com.sajjad.locallink

/** Central resource and lifecycle policy for resumable direct file transfers. */
internal object DirectFileTransferPolicy {
    const val MAX_DIRECT_FILE_SIZE = 50L * 1024L * 1024L
    const val CHUNK_SIZE = 48 * 1024
    const val MAX_ACTIVE_INCOMING_TRANSFERS = 8
    const val MAX_ACTIVE_OUTGOING_TRANSFERS = 8
    const val MAX_ACTIVE_TRANSFER_BYTES = 256L * 1024L * 1024L
    const val IDLE_TIMEOUT_MS = 10L * 60L * 1000L
    const val MAX_RETRY_ATTEMPTS = 8
    const val COMPLETION_MARKER_RETENTION_MS = 24L * 60L * 60L * 1000L

    fun expectedChunks(size: Long): Int {
        require(size in 0L..MAX_DIRECT_FILE_SIZE)
        if (size == 0L) return 1
        return ((size + CHUNK_SIZE - 1L) / CHUNK_SIZE).toInt()
    }

    fun validTransferSize(size: Long): Boolean = size in 0L..MAX_DIRECT_FILE_SIZE

    fun activeBytes(sizes: Collection<Long>): Long = sizes.sumOf { it.coerceAtLeast(0L) }
}
