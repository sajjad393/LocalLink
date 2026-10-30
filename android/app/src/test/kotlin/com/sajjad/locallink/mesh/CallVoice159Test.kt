package com.sajjad.locallink.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CallVoice159Test {
    private val key = ByteArray(32) { it.toByte() }
    private val otherKey = ByteArray(32) { (it + 1).toByte() }
    private val frame = "{\"type\":\"call_media\",\"sequence\":7}".toByteArray()

    @Test
    fun `a locked frame opens with the call key`() {
        val stream = CallVoiceSeal.streamId(key)
        val (nonce, cipher) = CallVoiceSeal.seal(key, "a", "b", stream, frame)
        assertArrayEquals(frame, CallVoiceSeal.open(key, "a", "b", stream, nonce, cipher))
    }

    @Test
    fun `the relay sees no sound, the frame is not readable`() {
        val stream = CallVoiceSeal.streamId(key)
        val (_, cipher) = CallVoiceSeal.seal(key, "a", "b", stream, frame)
        assertFalse(String(cipher, Charsets.ISO_8859_1).contains("call_media"))
    }

    @Test
    fun `wrong key, other direction or changed bytes are rejected`() {
        val stream = CallVoiceSeal.streamId(key)
        val (nonce, cipher) = CallVoiceSeal.seal(key, "a", "b", stream, frame)
        assertNull(CallVoiceSeal.open(otherKey, "a", "b", stream, nonce, cipher))
        assertNull(CallVoiceSeal.open(key, "b", "a", stream, nonce, cipher))
        assertNull(CallVoiceSeal.open(key, "a", "b", "0000000000000000", nonce, cipher))
        val bent = cipher.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertNull(CallVoiceSeal.open(key, "a", "b", stream, nonce, bent))
        assertNull(CallVoiceSeal.open(ByteArray(16), "a", "b", stream, nonce, cipher))
    }

    @Test
    fun `each frame gets a new nonce`() {
        val stream = CallVoiceSeal.streamId(key)
        val one = CallVoiceSeal.seal(key, "a", "b", stream, frame)
        val two = CallVoiceSeal.seal(key, "a", "b", stream, frame)
        assertFalse(one.first.contentEquals(two.first))
    }

    @Test
    fun `stream id is 16 hex, same for both phones, differs per call`() {
        val s = CallVoiceSeal.streamId(key)
        assertEquals(16, s.length)
        assertTrue(s.all { it in '0'..'9' || it in 'a'..'f' })
        assertEquals(s, CallVoiceSeal.streamId(key.copyOf()))
        assertNotEquals(s, CallVoiceSeal.streamId(otherKey))
    }

    @Test
    fun `a relay passes on at most 2 calls`() {
        val b = MeshRelayVoiceBudget()
        assertTrue(b.allow("aaaaaaaaaaaaaaaa", 0))
        assertTrue(b.allow("bbbbbbbbbbbbbbbb", 0))
        assertFalse(b.allow("cccccccccccccccc", 0))
        assertTrue(b.allow("aaaaaaaaaaaaaaaa", 10))
        assertEquals(2, b.activeStreams(10))
    }

    @Test
    fun `a silent call frees its place after 5 s`() {
        val b = MeshRelayVoiceBudget()
        assertTrue(b.allow("aaaaaaaaaaaaaaaa", 0))
        assertTrue(b.allow("bbbbbbbbbbbbbbbb", 0))
        assertTrue(b.knows("aaaaaaaaaaaaaaaa", 1_000))
        assertTrue(b.allow("bbbbbbbbbbbbbbbb", 4_000))
        assertFalse(b.knows("aaaaaaaaaaaaaaaa", 6_000))
        assertTrue(b.allow("cccccccccccccccc", 6_000))
    }

    @Test
    fun `a call over 160 frames a second is cut, never paused`() {
        val b = MeshRelayVoiceBudget()
        repeat(160) { assertTrue(b.allow("aaaaaaaaaaaaaaaa", 100)) }
        assertFalse(b.allow("aaaaaaaaaaaaaaaa", 200))
        assertTrue(b.allow("aaaaaaaaaaaaaaaa", 1_200))
    }

    @Test
    fun `bad stream ids are refused`() {
        val b = MeshRelayVoiceBudget()
        assertFalse(b.allow("", 0))
        assertFalse(b.allow(null, 0))
        assertFalse(b.allow("xyz", 0))
        assertFalse(b.allow("aaaaaaaaaaaaaaaaaa", 0))
    }

    @Test
    fun `relay links carry locked voice, never plain voice`() {
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, MeshRelayPolicy.SEALED_VOICE))
        assertFalse(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_RELAY, "call_media"))
        assertTrue(MeshRelayPolicy.canCarry(MeshRelayPolicy.TRUST_CONTACT, MeshRelayPolicy.SEALED_VOICE))
        assertFalse(MeshRelayPolicy.isSealed(MeshRelayPolicy.SEALED_VOICE))
    }

    @Test
    fun `locked voice is a valid mesh type`() {
        assertTrue(MeshIdPolicy.isValidType(MeshRelayPolicy.SEALED_VOICE))
    }

    @Test
    fun `a phone on a charger says pwr=1, older tags read as not charging`() {
        val id = "0123456789abcdef"
        val on = NearbyTagPolicy.encode(id, host = true, member = false, members = 1, charging = true)
        assertEquals("1", on["pwr"])
        val tag = NearbyTagPolicy.decode(null, on, "aa:bb:cc:dd:ee:ff", 5L)!!
        assertEquals(true, tag["charging"])
        val off = NearbyTagPolicy.encode(id, host = true, member = false, members = 1)
        assertFalse(off.containsKey("pwr"))
        assertFalse(NearbyTagPolicy.decode(null, off, "aa:bb:cc:dd:ee:ff", 5L)!!.containsKey("charging"))
    }
}
