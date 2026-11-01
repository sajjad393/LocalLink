package com.sajjad.locallink

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Bundle 181: joins voice note parts (one per pause) into ONE .m4a file
 * without re-encoding (the parts all come from the same recorder settings).
 */
object VoiceNoteJoiner {
    /** Returns the joined file, the single part itself, or null on failure. */
    fun join(paths: List<String>, outDir: File, deleteParts: Boolean): File? {
        val parts = VoiceJoinPolicy.usableParts(paths.map { it to File(it).let { f -> if (f.exists()) f.length() else 0L } })
        if (parts.isEmpty()) return null
        if (parts.size == 1) {
            if (deleteParts) paths.filter { it != parts[0] }.forEach { try { File(it).delete() } catch (_: Exception) {} }
            return File(parts[0])
        }
        val out = File(outDir, "voice_${java.util.UUID.randomUUID()}.m4a")
        var muxer: MediaMuxer? = null
        var started = false
        try {
            val mx = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mx
            var track = -1
            var offset = 0L
            var frame = VoiceJoinPolicy.frameUs(44_100)
            val buf = ByteBuffer.allocate(512 * 1024)
            val info = MediaCodec.BufferInfo()
            for (p in parts) {
                val ex = MediaExtractor()
                try {
                    ex.setDataSource(p)
                    val idx = (0 until ex.trackCount).firstOrNull {
                        ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                    } ?: continue
                    ex.selectTrack(idx)
                    if (track < 0) {
                        val fmt = ex.getTrackFormat(idx)
                        track = mx.addTrack(fmt)
                        mx.start(); started = true
                        if (fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)) frame = VoiceJoinPolicy.frameUs(fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE))
                    }
                    var last = 0L
                    while (true) {
                        buf.clear()
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) break
                        info.offset = 0
                        info.size = n
                        info.presentationTimeUs = VoiceJoinPolicy.sampleTimeUs(offset, ex.sampleTime)
                        info.flags = if ((ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                        mx.writeSampleData(track, buf, info)
                        last = maxOf(last, ex.sampleTime)
                        ex.advance()
                    }
                    offset = VoiceJoinPolicy.nextOffsetUs(offset, last, frame)
                } finally {
                    try { ex.release() } catch (_: Exception) {}
                }
            }
            if (!started) { out.delete(); return null }
            mx.stop(); started = false
            if (deleteParts) paths.forEach { try { File(it).delete() } catch (_: Exception) {} }
            return out
        } catch (e: Exception) {
            android.util.Log.w("LocalLinkVoice", "VOICE_JOIN_FAILED parts=${parts.size} error=${e.message}")
            out.delete()
            return null
        } finally {
            try { if (started) muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }
    }
}
