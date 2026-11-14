package com.sajjad.locallink

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.SystemClock
import android.util.Log
import java.nio.ByteOrder

/**
 * Bundle 303 (G): what a voice note sounds like, for the bars in the voice
 * bubble (like WhatsApp). Decodes the .m4a (AAC) with Android's own decoder,
 * off the UI thread, and returns the loudest sample (0..32767) of each of
 * [buckets] equal time slices plus the length in ms. Built-in Android only.
 */
object VoiceWaveNative {
    private const val TAG = "LocalLinkVoiceWave"
    private const val TIME_LIMIT_MS = 25_000L
    private const val TIMEOUT_US = 10_000L

    fun read(path: String, buckets: Int): Map<String, Any> {
        val n = buckets.coerceIn(8, 400)
        val started = SystemClock.elapsedRealtime()
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i; format = f; break
                }
            }
            if (track < 0 || format == null) return fallback(path, "no_audio_track")
            extractor.selectTrack(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            val dec = MediaCodec.createDecoderByType(mime)
            codec = dec
            dec.configure(format, null, null, 0)
            dec.start()
            // One loudest sample per decoded chunk, with its time.
            val chunkPeaks = ArrayList<Int>(4096)
            val chunkTimes = ArrayList<Long>(4096)
            var floatPcm = false
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var lastUs = 0L
            while (!outputDone) {
                if (SystemClock.elapsedRealtime() - started > TIME_LIMIT_MS) {
                    Log.w(TAG, "VOICE_WAVE time limit, chunks=${chunkPeaks.size}")
                    return fallback(path, "time_limit")
                }
                if (!inputDone) {
                    val inIndex = dec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buf = dec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = dec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val of = dec.outputFormat
                    floatPcm = of.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        of.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (outIndex >= 0) {
                    if (info.size > 0) {
                        val out = dec.getOutputBuffer(outIndex)!!
                        out.position(info.offset)
                        out.limit(info.offset + info.size)
                        out.order(ByteOrder.LITTLE_ENDIAN)
                        var peak = 0
                        if (floatPcm) {
                            val fb = out.asFloatBuffer()
                            while (fb.hasRemaining()) {
                                val v = (Math.abs(fb.get()) * 32767f).toInt()
                                if (v > peak) peak = v
                            }
                        } else {
                            val sb = out.asShortBuffer()
                            while (sb.hasRemaining()) {
                                val v = Math.abs(sb.get().toInt())
                                if (v > peak) peak = v
                            }
                        }
                        chunkPeaks.add(peak.coerceAtMost(32767))
                        chunkTimes.add(info.presentationTimeUs)
                        if (info.presentationTimeUs > lastUs) lastUs = info.presentationTimeUs
                    }
                    dec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
            val totalUs = maxOf(durationUs, lastUs, 1L)
            val peaks = IntArray(n)
            for (i in chunkPeaks.indices) {
                val b = ((chunkTimes[i].coerceAtLeast(0L) * n) / totalUs).toInt().coerceIn(0, n - 1)
                if (chunkPeaks[i] > peaks[b]) peaks[b] = chunkPeaks[i]
            }
            // Slices with no chunk (very short notes): copy the one before.
            for (i in 1 until n) if (peaks[i] == 0 && peaks[i - 1] > 0 && chunkPeaks.size < n) peaks[i] = peaks[i - 1]
            val ms = totalUs / 1000
            Log.i(TAG, "VOICE_WAVE ok ms=$ms chunks=${chunkPeaks.size} took=${SystemClock.elapsedRealtime() - started}")
            return mapOf("duration_ms" to ms.toInt(), "peaks" to peaks.toList())
        } catch (e: Exception) {
            Log.w(TAG, "VOICE_WAVE failed: ${e.javaClass.simpleName} ${e.message}")
            return fallback(path, "error")
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    /** Length only (no bars) when the sound can't be read. */
    private fun fallback(path: String, why: String): Map<String, Any> {
        var ms = 0
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            ms = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toIntOrNull() ?: 0
        } catch (_: Exception) {
        } finally {
            try { r.release() } catch (_: Exception) {}
        }
        Log.w(TAG, "VOICE_WAVE fallback why=$why ms=$ms")
        return mapOf("duration_ms" to ms, "peaks" to emptyList<Int>())
    }
}
