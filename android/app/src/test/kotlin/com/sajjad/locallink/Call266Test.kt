package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 266: voice through the server (B2) and the quick link switch in calls (C). */
class Call266Test {
    private fun src(name: String) = File("main/kotlin/com/sajjad/locallink/$name").readText()

    @Test fun packAndUnpackRoundTrip() {
        val nonce = ByteArray(12) { it.toByte() }
        val cipher = ByteArray(300) { (it * 7).toByte() }
        val bytes = CallServerVoice266.packBytes("abc123", nonce, cipher)
        assertNotNull(bytes)
        val piece = CallServerVoice266.unpackBytes(bytes)!!
        assertEquals("abc123", piece.stream)
        assertArrayEquals(nonce, piece.nonce)
        assertArrayEquals(cipher, piece.cipher)
    }

    @Test fun tooBigOrBadPiecesAreRefused() {
        val nonce = ByteArray(12)
        // 1 + 6 + 12 + 1031 = 1050 bytes -> 1400 base64 chars: the largest allowed.
        assertNotNull(CallServerVoice266.packBytes("abc123", nonce, ByteArray(1031)))
        assertNull(CallServerVoice266.packBytes("abc123", nonce, ByteArray(1032)))
        assertEquals(1400, CallServerVoice266.b64Len(1050))
        assertEquals(1404, CallServerVoice266.b64Len(1051))
        assertNull(CallServerVoice266.packBytes("", nonce, ByteArray(40)))
        assertNull(CallServerVoice266.packBytes("abc", ByteArray(11), ByteArray(40)))
        assertNull(CallServerVoice266.packBytes("abc", nonce, ByteArray(16)))
        assertNull(CallServerVoice266.unpackBytes(null))
        assertNull(CallServerVoice266.unpackBytes(ByteArray(0)))
        assertNull(CallServerVoice266.unpackBytes(byteArrayOf(3, 1, 2, 3, 4)))
        assertNull(CallServerVoice266.unpackBytes(ByteArray(1100)))
    }

    @Test fun neverPlainVoiceToTheServer() {
        val s = src("LocalLinkTransportService.kt")
        val send = s.substring(s.indexOf("private fun sendServerVoice("), s.indexOf("private fun serverLine()"))
        assertTrue(send.contains("CallServerVoice266.packBytes(voiceStream, nonce, cipher)"))
        assertFalse(send.contains("audio_payload"))
        // Only the sealed piece goes; the server branch sits after the sealed send.
        val audio = s.substring(s.indexOf("private fun sendAudioPacket("), s.indexOf("private fun sendUdp("))
        assertTrue(audio.indexOf("sendServerVoice(sealedNonce, sealedCipher)") > audio.indexOf("CallVoiceSeal.seal("))
        assertTrue(audio.indexOf("sendServerVoice(sealedNonce, sealedCipher)") < audio.indexOf("plainFallbacks.incrementAndGet()"))
        // Incoming pieces open with the call key and use the locked path.
        val inn = s.substring(s.indexOf("private fun serverVoiceInInternal("), s.indexOf("private fun callLinkCheck266("))
        assertTrue(inn.contains("CallVoiceSeal.open(key, senderId, selfId"))
        assertTrue(inn.contains("handleIncomingCallMediaPayload(inner, senderId, 1, locked = true)"))
        assertTrue(inn.contains("senderId != current.peerId"))
    }

    @Test fun mainActivityBatchesPieces() {
        val s = src("MainActivity.kt")
        assertTrue(s.contains("\"locallink/call_voice_server\""))
        assertTrue(s.contains("handler.postDelayed(flush, 40L)"))
        assertTrue(s.contains("\"server_voice\" ->"))
        assertTrue(s.contains("\"server_voice_in\" ->"))
    }

    @Test fun pathWordServer() {
        assertEquals("server", CallPathPolicy.kind(null, false, null, true))
        assertEquals("mesh", CallPathPolicy.kind(null, true, null, true))
        assertEquals("lan", CallPathPolicy.kind("lan", false, "192.168.1.4", true))
        assertEquals("none", CallPathPolicy.kind(null, false))
    }

    @Test fun switchWhenQuietAndOtherLinkAnswers() {
        val now = 100_000L
        assertTrue(CallLinkSwitch266.shouldProbe(now, now - 2_600, now - 2_600, 1, 0L))
        val probeAt = now
        assertEquals(0, CallLinkSwitch266.pickAnswered(probeAt, listOf(probeAt + 300)))
        assertEquals(1, CallLinkSwitch266.pickAnswered(probeAt, listOf(probeAt - 10, probeAt + 200)))
        assertEquals(0, CallLinkSwitch266.pickAnswered(probeAt, listOf(probeAt + 100, probeAt + 400)))
    }

    @Test fun staySilentLinks() {
        val probeAt = 50_000L
        assertEquals(-1, CallLinkSwitch266.pickAnswered(probeAt, listOf(probeAt - 1)))
        assertEquals(-1, CallLinkSwitch266.pickAnswered(probeAt, listOf(probeAt + 1_200)))
        assertFalse(CallLinkSwitch266.probeOver(probeAt, probeAt + 1_400))
        assertTrue(CallLinkSwitch266.probeOver(probeAt, probeAt + 1_600))
    }

    @Test fun neverSwitchOutsideACallOrWhileVoiceFlows() {
        val now = 100_000L
        assertFalse(CallLinkSwitch266.shouldProbe(now, now - 3_000, now - 3_000, 1, 0L, callLive = false))
        assertFalse(CallLinkSwitch266.shouldProbe(now, now - 100, now - 3_000, 1, 0L))
        assertFalse(CallLinkSwitch266.shouldProbe(now, now - 3_000, now - 100, 1, 0L))
        assertFalse(CallLinkSwitch266.shouldProbe(now, now - 3_000, now - 3_000, 0, 0L))
        // Before the first voice arrived: never.
        assertFalse(CallLinkSwitch266.shouldProbe(now, 0L, now - 3_000, 1, 0L))
        // One probe per 2.5 s.
        assertFalse(CallLinkSwitch266.shouldProbe(now, now - 3_000, now - 3_000, 1, now - 1_000))
    }

    @Test fun oldLinkBackIsUsedAgain() {
        val switchedAt = 10_000L
        assertFalse(CallLinkSwitch266.backToOld(switchedAt, switchedAt + 500))
        assertTrue(CallLinkSwitch266.backToOld(switchedAt, switchedAt + 1_500))
        assertFalse(CallLinkSwitch266.backToOld(0L, 99_999L))
        val s = src("LocalLinkTransportService.kt")
        assertTrue(s.contains("CallLinkSwitch266.line(session.callId, linkWord266(active), linkWord266(old), 0L) + \" why=back\""))
        // The probe pings go out on their own thread, never on the speaker thread.
        assertTrue(s.contains("\"call-link-probe\""))
        assertEquals("CALL_LINK_SWITCH call=c1 from=lan to=wifi_direct quiet_ms=2600", CallLinkSwitch266.line("c1", "lan", "wifi_direct", 2600))
    }

    @Test fun serverLogLine() {
        assertEquals("VOICE_SERVER call=c1 tx=5 rx=4 big=0 on=y", CallServerVoice266.line("c1", 5, 4, 0, true))
    }
}
