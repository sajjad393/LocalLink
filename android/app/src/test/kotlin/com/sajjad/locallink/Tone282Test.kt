package com.sajjad.locallink

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Bundle 282: the owner's AOSP tones under the same file names + message channel v5. */
class Tone282Test {
    private fun raw(name: String): File {
        // Gradle runs these tests in android/app/src (build.gradle workingDir), like the other source tests.
        return listOf("main/res/raw/$name", "src/main/res/raw/$name", "app/src/main/res/raw/$name")
            .map { File(it) }
            .firstOrNull { it.exists() } ?: File("main/res/raw/$name")
    }

    private fun le16(b: ByteArray, at: Int) = (b[at].toInt() and 0xff) or ((b[at + 1].toInt() and 0xff) shl 8)

    private fun le32(b: ByteArray, at: Int) = le16(b, at) or (le16(b, at + 2) shl 16)

    @Test
    fun `message channel is v5 and the old v4 is only deleted`() {
        assertEquals("locallink_messages_v5", LocalLinkNotificationManager.MESSAGE_CHANNEL_ID)
        assertEquals("locallink_messages_v4", LocalLinkNotificationManager.OLD_MESSAGE_CHANNEL_ID)
        assertNotEquals(
            LocalLinkNotificationManager.MESSAGE_CHANNEL_ID,
            LocalLinkNotificationManager.OLD_MESSAGE_CHANNEL_ID,
        )
    }

    @Test
    fun `the four new tones are mono 16-bit 44100 wav files`() {
        val minSeconds = mapOf(
            "locallink_ringtone.wav" to 10.0,
            "locallink_message.wav" to 1.0,
            "message_received.wav" to 0.5,
            "message_sent.wav" to 0.3,
        )
        for ((name, min) in minSeconds) {
            val b = raw(name).readBytes()
            assertEquals(name, "RIFF", String(b, 0, 4, Charsets.US_ASCII))
            assertEquals(name, "WAVE", String(b, 8, 4, Charsets.US_ASCII))
            assertEquals(name, 1, le16(b, 22)) // mono
            assertEquals(name, 44100, le32(b, 24))
            assertEquals(name, 16, le16(b, 34))
            val seconds = (b.size - 44) / 2.0 / 44100
            assertTrue("$name $seconds s", seconds >= min)
        }
    }

    @Test
    fun `outgoing ringback is unchanged`() {
        val b = raw("locallink_ringback.wav").readBytes()
        assertEquals(22050, le32(b, 24))
    }
}
