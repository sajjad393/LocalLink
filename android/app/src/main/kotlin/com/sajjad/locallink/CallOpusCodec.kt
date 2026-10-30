package com.sajjad.locallink

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * Bundle 149: Opus voice for calls, sent on the wire as codec `opus2`.
 *
 * Fixes against the 142-145 adapter (which is why it has a new codec name and
 * older builds never pick it):
 *  1. Encoder output is DRAINED (zero, one or more packets per input) and the
 *     codec-config buffers (OpusHead etc.) are never sent as audio.
 *  2. The decoder gets csd-0 (OpusHead), csd-1 (pre-skip) and csd-2 (seek
 *     pre-roll); without them Android's decoder fails (the silent caller).
 *  3. The decoder's real output rate/channels are read from its output format
 *     (Android always gives 48 kHz) and converted to 16 kHz mono for the call
 *     track, so no more slow "tiger" voice.
 *  4. [usable] runs a one-time self-test: a 440 Hz tone must come back loud
 *     AND at ~440 Hz. Any failure -> the phone simply offers PCM only.
 */
object CallOpusCodec {
    const val MIME = "audio/opus"
    private const val TAG = "LocalLinkCall"
    private const val RATE = CallOpus2Format.CALL_RATE
    const val BITRATE = 24_000

    @Volatile private var selfTest: Boolean? = null

    /** True when this phone can encode AND decode opus2 correctly. Cached. */
    fun usable(): Boolean {
        selfTest?.let { return it }
        synchronized(this) {
            selfTest?.let { return it }
            val started = System.currentTimeMillis()
            var detail = ""
            val ok = try {
                runSelfTest { detail = it }
            } catch (t: Throwable) {
                detail = "error=${t.javaClass.simpleName}"
                false
            }
            selfTest = ok
            Log.i(TAG, "CALL_OPUS_SELFTEST ok=$ok $detail ms=${System.currentTimeMillis() - started} sdk=${Build.VERSION.SDK_INT}")
            return ok
        }
    }

    fun isSupported(sampleRate: Int = RATE, channels: Int = 1): Boolean {
        // MediaCodec only ships an Opus ENCODER from Android 10.
        if (Build.VERSION.SDK_INT < 29) return false
        if (sampleRate !in setOf(8000, 12000, 16000, 24000, 48000) || channels !in 1..2) return false
        return try {
            val encoder = findCodec(MIME, true) ?: return false
            val decoder = findCodec(MIME, false) ?: return false
            val encAudio = encoder.getCapabilitiesForType(MIME).audioCapabilities ?: return false
            decoder.getCapabilitiesForType(MIME).audioCapabilities ?: return false
            encAudio.isSampleRateSupported(sampleRate) && channels <= encAudio.maxInputChannelCount
        } catch (_: Throwable) {
            false
        }
    }

    private fun runSelfTest(report: (String) -> Unit): Boolean {
        if (!isSupported()) { report("reason=unsupported"); return false }
        val encoder = createEncoder()
        val decoder = try { createDecoder() } catch (t: Throwable) { encoder.close(); throw t }
        try {
            val decoded = ByteArrayOutputStream()
            var packets = 0
            for (i in 0 until 25) { // 500 ms of tone
                for (packet in encoder.encode(CallOpus2Format.sineFrame(i))) {
                    packets++
                    decoder.decode(packet)?.let { decoded.write(it) }
                }
            }
            val pcm = decoded.toByteArray()
            // Skip the first 100 ms (codec warm-up) before measuring.
            val skip = minOf(pcm.size, RATE / 10 * 2)
            val body = pcm.copyOfRange(skip, pcm.size)
            val hz = CallOpus2Format.estimateHz(body)
            val level = CallOpus2Format.rms(body)
            report("packets=$packets out_ms=${pcm.size / 32} hz=${hz.toInt()} rms=${level.toInt()} dec_rate=${decoder.outputRate} dec_ch=${decoder.outputChannels}")
            return packets >= 10 && body.size >= RATE / 10 * 2 && level > 1500.0 && hz in 380.0..500.0
        } finally {
            encoder.close()
            decoder.close()
        }
    }

    fun createEncoder(bitrate: Int = BITRATE): Encoder {
        val codec = MediaCodec.createEncoderByType(MIME)
        try {
            val format = MediaFormat.createAudioFormat(MIME, RATE, 1).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, RATE * 2) // up to 1 s
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (t: Throwable) {
            try { codec.release() } catch (_: Throwable) {}
            throw t
        }
        return Encoder(codec)
    }

    fun createDecoder(): Decoder {
        val codec = MediaCodec.createDecoderByType(MIME)
        try {
            val format = MediaFormat.createAudioFormat(MIME, 48_000, 1).apply {
                setByteBuffer("csd-0", ByteBuffer.wrap(CallOpus2Format.opusHead()))
                setByteBuffer("csd-1", ByteBuffer.wrap(CallOpus2Format.nanosCsd(CallOpus2Format.preSkipNanos())))
                setByteBuffer("csd-2", ByteBuffer.wrap(CallOpus2Format.nanosCsd(CallOpus2Format.SEEK_PREROLL_NS)))
            }
            codec.configure(format, null, null, 0)
            codec.start()
        } catch (t: Throwable) {
            try { codec.release() } catch (_: Throwable) {}
            throw t
        }
        return Decoder(codec)
    }

    /** Not thread-safe: used only by the call capture thread. */
    class Encoder(private val codec: MediaCodec) {
        private var ptsUs = 0L
        private val info = MediaCodec.BufferInfo()

        /** 16 kHz mono PCM in -> zero or more Opus packets out. */
        fun encode(pcm: ByteArray): List<ByteArray> {
            val out = ArrayList<ByteArray>(2)
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) {
                val input = codec.getInputBuffer(index)
                if (input == null || input.capacity() < pcm.size) {
                    codec.queueInputBuffer(index, 0, 0, ptsUs, 0)
                } else {
                    input.clear()
                    input.put(pcm)
                    codec.queueInputBuffer(index, 0, pcm.size, ptsUs, 0)
                    ptsUs += pcm.size / 2 * 1_000_000L / RATE
                }
            }
            drain(out, firstWaitUs = 5_000)
            return out
        }

        private fun drain(out: MutableList<ByteArray>, firstWaitUs: Long) {
            var wait = firstWaitUs
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, wait)
                wait = 0
                when {
                    idx >= 0 -> {
                        val isConfig = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                        if (!isConfig && info.size > 0) {
                            codec.getOutputBuffer(idx)?.let { buf ->
                                val bytes = ByteArray(info.size)
                                buf.position(info.offset)
                                buf.limit(info.offset + info.size)
                                buf.get(bytes)
                                out.add(bytes)
                            }
                        }
                        codec.releaseOutputBuffer(idx, false)
                    }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> continue
                    @Suppress("DEPRECATION")
                    idx == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> continue
                    else -> return // INFO_TRY_AGAIN_LATER
                }
            }
        }

        fun close() {
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
        }
    }

    /** Not thread-safe: used only by the call playback thread. */
    class Decoder(private val codec: MediaCodec) {
        private var ptsUs = 0L
        private val info = MediaCodec.BufferInfo()
        @Volatile var outputRate = 48_000; private set
        @Volatile var outputChannels = 1; private set
        private var floatOutput = false

        /** One Opus packet in -> 16 kHz mono PCM out (may be empty at start). */
        fun decode(packet: ByteArray): ByteArray? {
            val index = codec.dequeueInputBuffer(10_000)
            if (index < 0) return null
            val input = codec.getInputBuffer(index) ?: return null
            input.clear()
            if (input.capacity() < packet.size) {
                codec.queueInputBuffer(index, 0, 0, ptsUs, 0)
                return null
            }
            input.put(packet)
            codec.queueInputBuffer(index, 0, packet.size, ptsUs, 0)
            ptsUs += 20_000L
            val raw = ByteArrayOutputStream()
            var wait = 10_000L
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, wait)
                wait = 0
                when {
                    idx >= 0 -> {
                        if (info.size > 0 && (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                            codec.getOutputBuffer(idx)?.let { buf ->
                                val bytes = ByteArray(info.size)
                                buf.position(info.offset)
                                buf.limit(info.offset + info.size)
                                buf.get(bytes)
                                raw.write(bytes)
                            }
                        }
                        codec.releaseOutputBuffer(idx, false)
                    }
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> readFormat(codec.outputFormat)
                    @Suppress("DEPRECATION")
                    idx == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> continue
                    else -> break
                }
            }
            if (floatOutput) return null // never seen on Android's Opus decoder
            val bytes = raw.toByteArray()
            return CallOpus2Format.toMono16k(bytes, bytes.size, outputRate, outputChannels)
        }

        private fun readFormat(format: MediaFormat) {
            if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) outputRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) outputChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            floatOutput = Build.VERSION.SDK_INT >= 24 &&
                format.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                format.getInteger(MediaFormat.KEY_PCM_ENCODING) != AudioFormat.ENCODING_PCM_16BIT
        }

        fun close() {
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
        }
    }

    private fun findCodec(mime: String, encoder: Boolean): MediaCodecInfo? =
        android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS)
            .codecInfos
            .firstOrNull { it.isEncoder == encoder && it.supportedTypes.any { type -> type.equals(mime, true) } }
}
