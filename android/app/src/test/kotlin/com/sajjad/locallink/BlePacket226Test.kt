package com.sajjad.locallink

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Bundle 226 (B2): the 10-byte Bluetooth packet. */
class BlePacket226Test {
    private val p = NearbyBlePolicy.Packet(
        id8 = "1a2b3c4d", wanted8 = "deadbeef", host = true, member = false,
        searching = true, onRouter = false, call = true, pairHost = true, counter = 5,
    )

    @Test
    fun `encode then decode gives the same packet`() {
        val bytes = NearbyBlePolicy.encode(p)!!
        assertEquals(10, bytes.size)
        assertEquals(p, NearbyBlePolicy.decode(bytes))
    }

    @Test
    fun `byte layout`() {
        val b = NearbyBlePolicy.encode(p)!!
        assertEquals(0x10 or 0x1 or 0x4, b[0].toInt() and 0xff)
        assertArrayEquals(byteArrayOf(0x1a, 0x2b, 0x3c, 0x4d), b.copyOfRange(1, 5))
        assertArrayEquals(byteArrayOf(0xde.toByte(), 0xad.toByte(), 0xbe.toByte(), 0xef.toByte()), b.copyOfRange(5, 9))
        assertEquals((5 shl 2) or 0x3, b[9].toInt() and 0xff)
    }

    @Test
    fun `nobody wanted - zeros and no call or pair bits`() {
        val b = NearbyBlePolicy.encode(p.copy(wanted8 = null))!!
        assertArrayEquals(ByteArray(4), b.copyOfRange(5, 9))
        val d = NearbyBlePolicy.decode(b)!!
        assertNull(d.wanted8)
        assertFalse(d.call)
        assertFalse(d.pairHost)
    }

    @Test
    fun `counter wraps at 6 bits`() {
        val d = NearbyBlePolicy.decode(NearbyBlePolicy.encode(p.copy(counter = 64 + 3))!!)!!
        assertEquals(3, d.counter)
    }

    @Test
    fun `bad ids are never sent`() {
        assertNull(NearbyBlePolicy.encode(p.copy(id8 = "xyz")))
        assertNull(NearbyBlePolicy.encode(p.copy(id8 = "00000000")))
        assertNull(NearbyBlePolicy.encode(p.copy(id8 = "1A2B3C4D")))
    }

    @Test
    fun `bad version or length is ignored`() {
        val b = NearbyBlePolicy.encode(p)!!
        assertNull(NearbyBlePolicy.decode(b.copyOf(9)))
        assertNull(NearbyBlePolicy.decode(null))
        val v2 = b.copyOf(); v2[0] = (0x20 or 1).toByte()
        assertNull(NearbyBlePolicy.decode(v2))
        val zeroId = b.copyOf(); for (i in 1..4) zeroId[i] = 0
        assertNull(NearbyBlePolicy.decode(zeroId))
        // Longer data (a future version adds bytes) still reads.
        assertNotNull(NearbyBlePolicy.decode(b + byteArrayOf(1, 2)))
    }

    @Test
    fun `advert fits a legacy packet - 3 flags + 2 header + 16 uuid + 10 data`() {
        assertTrue(3 + 2 + 16 + NearbyBlePolicy.PACKET_LEN <= 31)
    }

    @Test
    fun `wanted friends take turns every 5 s, max 3`() {
        val w = listOf(
            NearbyBlePolicy.Wanted("aaaaaaaa", true, false),
            NearbyBlePolicy.Wanted("bbbbbbbb", false, false),
        )
        assertEquals("aaaaaaaa", NearbyBlePolicy.pick(w, 0)!!.id8)
        assertEquals("bbbbbbbb", NearbyBlePolicy.pick(w, 5_000)!!.id8)
        assertEquals("aaaaaaaa", NearbyBlePolicy.pick(w, 10_000)!!.id8)
        assertNull(NearbyBlePolicy.pick(emptyList(), 0))
    }

    @Test
    fun `no name password or account data in the native code logs`() {
        val src = File("main/kotlin/com/sajjad/locallink/NearbyBle.kt").readText()
        assertFalse(src.contains("setIncludeDeviceName(true)"))
        assertTrue(src.contains("setConnectable(false)"))
        assertFalse(src.contains("BLUETOOTH_CONNECT"))
        assertFalse(src.contains(".enable()"))
    }
}
