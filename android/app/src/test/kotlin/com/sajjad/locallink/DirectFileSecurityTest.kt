package com.sajjad.locallink

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectFileSecurityTest {
    private fun context(fileId: String = "file-1", fileName: String = "photo.jpg") =
        DirectFileSecurity.FileChunkContext("transfer-1", "A", "D", fileId, "message-1", fileName, "image/jpeg", 5, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 1)

    @Test fun differentFilesDeriveDifferentKeys() {
        val a = DirectFileSecurity.deriveFileKey("shared-peer-secret", context(fileId = "file-1"))
        val b = DirectFileSecurity.deriveFileKey("shared-peer-secret", context(fileId = "file-2"))
        assertNotEquals(a.toList(), b.toList())
    }

    @Test fun metadataChangeBreaksChunkDecryption() {
        val c = context()
        val key = DirectFileSecurity.deriveFileKey("shared-peer-secret", c)
        val aad = DirectFileSecurity.chunkAad(c, 0)
        val encrypted = DirectFileSecurity.encryptChunk("hello".toByteArray(), key, aad)
        assertArrayEquals("hello".toByteArray(), DirectFileSecurity.decryptChunk(encrypted, key, aad))
        val changed = DirectFileSecurity.chunkAad(context(fileName = "changed.bin"), 0)
        assertNull(DirectFileSecurity.decryptChunk(encrypted, key, changed))
    }

    @Test fun authenticationBindsChunkIndexAndCiphertext() {
        val c = context()
        val key = DirectFileSecurity.deriveFileKey("shared-peer-secret", c)
        val aad = DirectFileSecurity.chunkAad(c, 0)
        val encrypted = DirectFileSecurity.encryptChunk("hello".toByteArray(), key, aad)
        val tag = DirectFileSecurity.authTag(key, aad, encrypted)
        val changedTag = DirectFileSecurity.authTag(key, DirectFileSecurity.chunkAad(c, 1), encrypted)
        assertTrue(tag.length == 64)
        assertNotEquals(tag, changedTag)
    }
}
