package com.sajjad.locallink

import org.junit.Assert.*
import org.junit.Test

class DirectFileTransferPolicyTest {
    @Test fun expectedChunkBoundaries() {
        assertEquals(1, DirectFileTransferPolicy.expectedChunks(0))
        assertEquals(1, DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.CHUNK_SIZE.toLong()))
        assertEquals(2, DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.CHUNK_SIZE.toLong() + 1))
        assertEquals(
            ((DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE + DirectFileTransferPolicy.CHUNK_SIZE - 1) / DirectFileTransferPolicy.CHUNK_SIZE).toInt(),
            DirectFileTransferPolicy.expectedChunks(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE),
        )
    }

    @Test fun sizeAndActiveByteBudget() {
        assertTrue(DirectFileTransferPolicy.validTransferSize(0))
        assertTrue(DirectFileTransferPolicy.validTransferSize(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE))
        assertFalse(DirectFileTransferPolicy.validTransferSize(-1))
        assertFalse(DirectFileTransferPolicy.validTransferSize(DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE + 1))
        assertEquals(6L, DirectFileTransferPolicy.activeBytes(listOf(1L, 2L, 3L)))
    }

    @Test fun concurrentPolicyBoundsAreFinite() {
        assertTrue(DirectFileTransferPolicy.MAX_ACTIVE_INCOMING_TRANSFERS < 32)
        assertTrue(DirectFileTransferPolicy.MAX_ACTIVE_OUTGOING_TRANSFERS <= 8)
        assertTrue(DirectFileTransferPolicy.MAX_RETRY_ATTEMPTS in 3..16)
    }
}
