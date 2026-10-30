package com.sajjad.locallink.mesh

import com.sajjad.locallink.DirectFileTransferPolicy
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Link165Test {
    private val linkKey = ByteArray(32) { (it * 7 + 3).toByte() }
    private val otherKey = ByteArray(32) { (it * 5 + 1).toByte() }

    @Test
    fun `a file packet opens only for its receiver with the shared key`() {
        val plain = "{\"type\":\"direct_file_chunk\",\"chunk_index\":3}".toByteArray()
        val k = FileSeal.key(linkKey, "ali", "sara")
        val (nonce, ct) = FileSeal.seal(k, "ali", "sara", plain)
        assertArrayEquals(plain, FileSeal.open(FileSeal.key(linkKey, "ali", "sara"), "ali", "sara", nonce, ct))
        // A relay without the key can't open it.
        assertNull(FileSeal.open(FileSeal.key(otherKey, "ali", "sara"), "ali", "sara", nonce, ct))
        // Turned around or sent to someone else: doesn't open.
        assertNull(FileSeal.open(k, "sara", "ali", nonce, ct))
        assertNull(FileSeal.open(k, "ali", "omar", nonce, ct))
        // Changed on the way: doesn't open.
        val bad = ct.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertNull(FileSeal.open(k, "ali", "sara", nonce, bad))
    }

    @Test
    fun `each direction has its own key and every packet a new nonce`() {
        val ab = FileSeal.key(linkKey, "ali", "sara")
        val ba = FileSeal.key(linkKey, "sara", "ali")
        assertFalse(ab.contentEquals(ba))
        assertEquals(32, ab.size)
        val n1 = FileSeal.seal(ab, "ali", "sara", "x".toByteArray()).first
        val n2 = FileSeal.seal(ab, "ali", "sara", "x".toByteArray()).first
        assertFalse(n1.contentEquals(n2))
    }

    @Test
    fun `all file packet types can travel locked, nothing else`() {
        for (t in listOf("direct_file_chunk", "direct_file_progress", "direct_file_ack", "direct_file_resume_request", "direct_file_cancel", "direct_file_restart")) {
            assertTrue(t, FileSeal.isFileType(t))
        }
        assertFalse(FileSeal.isFileType("direct_message"))
        assertFalse(FileSeal.isFileType(MeshRelayPolicy.SEALED_FILE))
        assertFalse(FileSeal.isFileType(null))
    }

    @Test
    fun `a non-contact phone carries locked files but never plain ones`() {
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED_FILE))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "direct_file_chunk"))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "direct_file_ack"))
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_CONTACT, MeshRelayPolicy.SEALED_FILE))
        // Not mixed up with chat (held briefly) or voice.
        assertFalse(MeshRelayPolicy.isSealed(MeshRelayPolicy.SEALED_FILE))
        assertFalse(MeshRelayPolicy.isSealedVoice(MeshRelayPolicy.SEALED_FILE))
    }

    @Test
    fun `locked file packets go on only to phones that understand them`() {
        assertFalse(FileSealPolicy.canSendOnward(MeshRelayPolicy.SEALED_FILE, MeshRelayPolicy.TRUST_RELAY, peerFileSeal = false))
        assertTrue(FileSealPolicy.canSendOnward(MeshRelayPolicy.SEALED_FILE, MeshRelayPolicy.TRUST_RELAY, peerFileSeal = true))
        assertTrue(FileSealPolicy.canSendOnward(MeshRelayPolicy.SEALED_FILE, MeshRelayPolicy.TRUST_CONTACT, peerFileSeal = false))
        assertTrue(FileSealPolicy.canSendOnward(MeshRelayPolicy.SEALED, MeshRelayPolicy.TRUST_RELAY, peerFileSeal = false))
    }

    @Test
    fun `lock when the other phone can open it or plain would be refused`() {
        assertFalse(FileSealPolicy.useSeal(haveKey = false, knownCapable = true, nextHopIsRelay = true, flip = false))
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = true, nextHopIsRelay = false, flip = false))
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = false, nextHopIsRelay = true, flip = false))
        // Older phone, direct or contact route: plain as before.
        assertFalse(FileSealPolicy.useSeal(haveKey = true, knownCapable = false, nextHopIsRelay = false, flip = false))
        // Stuck: try the other way.
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = false, nextHopIsRelay = false, flip = true))
        assertFalse(FileSealPolicy.useSeal(haveKey = true, knownCapable = true, nextHopIsRelay = false, flip = true))
        // Plain can never pass a non-contact phone, so no flip there.
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = true, nextHopIsRelay = true, flip = true))
        // Answers follow the way the last file packet came.
        assertFalse(FileSealPolicy.useSeal(haveKey = true, knownCapable = true, nextHopIsRelay = false, flip = false, replyLikeLast = false))
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = false, nextHopIsRelay = false, flip = false, replyLikeLast = true))
        assertTrue(FileSealPolicy.useSeal(haveKey = true, knownCapable = true, nextHopIsRelay = true, flip = false, replyLikeLast = false))
        assertTrue("direct_file_ack" in FileSealPolicy.REPLY_TYPES)
        assertFalse("direct_file_chunk" in FileSealPolicy.REPLY_TYPES)
    }

    @Test
    fun `a stuck transfer switches between plain and locked every 2 stalls`() {
        val tries = (0..9).map { FileSealPolicy.flipFor(it) }
        assertEquals(listOf(false, false, true, true, false, false, true, true, false, false), tries)
    }

    @Test
    fun `only my own locked file packets wait in the queue`() {
        assertTrue(FileSealPolicy.storeForwardable(MeshRelayPolicy.SEALED_FILE, "me", "me"))
        assertFalse(FileSealPolicy.storeForwardable(MeshRelayPolicy.SEALED_FILE, "ali", "me"))
        assertFalse(FileSealPolicy.storeForwardable(MeshRelayPolicy.SEALED_FILE, "me", null))
        assertFalse(FileSealPolicy.storeForwardable("direct_message", "me", "me"))
    }

    @Test
    fun `file budget drops over the limit and never pauses`() {
        val b = MeshRelayFileBudget(maxBytesPerPeer = 1000, maxBytesTotal = 1500)
        assertTrue(b.allow("r1", 600, now = 0L))
        assertFalse(b.allow("r1", 600, now = 10L))
        assertTrue(b.allow("r1", 400, now = 20L))
        // Total for all neighbours.
        assertTrue(b.allow("r2", 400, now = 30L))
        assertFalse(b.allow("r2", 200, now = 40L))
        // Next minute: open again (no pause).
        assertTrue(b.allow("r1", 900, now = 60_001L))
        assertTrue(b.shouldNoteFull("r1", now = 70_000L))
        assertFalse(b.shouldNoteFull("r1", now = 80_000L))
    }

    @Test
    fun `a locked chunk still fits the 256 KB line limit`() {
        val chunk = DirectFileTransferPolicy.CHUNK_SIZE
        // data base64 inside JSON, then sealed (+16 tag) and base64 again.
        val innerJson = (chunk + 2) / 3 * 4 + 1024
        val sealed = (innerJson + 16 + 2) / 3 * 4
        assertTrue("sealed=$sealed", sealed + 4096 < 256 * 1024)
        val k = FileSeal.key(linkKey, "a", "b")
        val big = ByteArray(innerJson) { 'x'.code.toByte() }
        val (n, ct) = FileSeal.seal(k, "a", "b", big)
        assertNotNull(FileSeal.open(k, "a", "b", n, ct))
    }
}
