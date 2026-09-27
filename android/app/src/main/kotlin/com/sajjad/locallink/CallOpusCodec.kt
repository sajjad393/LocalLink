package com.sajjad.locallink

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat

/**
 * Lightweight Opus codec adapter using Android MediaCodec. It deliberately
 * exposes capability detection so the call signaling layer can negotiate Opus
 * and fall back to PCM on devices without a compatible codec.
 */
object CallOpusCodec {
    const val MIME = "audio/opus"

    fun isSupported(sampleRate: Int, channels: Int = 1): Boolean {
        if (sampleRate !in setOf(8000, 12000, 16000, 24000, 48000) || channels !in 1..2) return false
        return try {
            val encoder = MediaCodecListCompat.findCodec(MIME, true) ?: return false
            val decoder = MediaCodecListCompat.findCodec(MIME, false) ?: return false
            val encAudio = encoder.getCapabilitiesForType(MIME).audioCapabilities ?: return false
            val decAudio = decoder.getCapabilitiesForType(MIME).audioCapabilities ?: return false
            encAudio.isSampleRateSupported(sampleRate) &&
                decAudio.isSampleRateSupported(sampleRate) &&
                channels <= encAudio.maxInputChannelCount
        } catch (_: Throwable) {
            false
        }
    }

    fun createEncoder(sampleRate: Int, channels: Int, bitrate: Int): Encoder {
        val codec = MediaCodec.createEncoderByType(MIME)
        val format = MediaFormat.createAudioFormat(MIME, sampleRate, channels).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, sampleRate * channels * 2 / 5)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        return Encoder(codec, sampleRate * channels * 2)
    }

    fun createDecoder(sampleRate: Int, channels: Int): Decoder {
        val codec = MediaCodec.createDecoderByType(MIME)
        codec.configure(MediaFormat.createAudioFormat(MIME, sampleRate, channels), null, null, 0)
        codec.start()
        return Decoder(codec)
    }

    class Encoder(private val codec: MediaCodec, private val maxInput: Int) {
        fun encode(pcm: ByteArray): ByteArray? {
            val index = codec.dequeueInputBuffer(20_000)
            if (index < 0) return null
            val input = codec.getInputBuffer(index) ?: return null
            input.clear()
            if (pcm.size > maxInput) return null
            input.put(pcm)
            codec.queueInputBuffer(index, 0, pcm.size, 0L, 0)
            val info = MediaCodec.BufferInfo()
            val outputIndex = codec.dequeueOutputBuffer(info, 20_000)
            if (outputIndex < 0) return null
            val output = codec.getOutputBuffer(outputIndex) ?: run {
                codec.releaseOutputBuffer(outputIndex, false)
                return null
            }
            val bytes = ByteArray(info.size)
            output.position(info.offset)
            output.limit(info.offset + info.size)
            output.get(bytes)
            codec.releaseOutputBuffer(outputIndex, false)
            return bytes
        }

        fun close() {
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
        }
    }

    class Decoder(private val codec: MediaCodec) {
        fun decode(encoded: ByteArray): ByteArray? {
            val index = codec.dequeueInputBuffer(20_000)
            if (index < 0) return null
            val input = codec.getInputBuffer(index) ?: return null
            input.clear()
            input.put(encoded)
            codec.queueInputBuffer(index, 0, encoded.size, 0L, 0)
            val info = MediaCodec.BufferInfo()
            val outputIndex = codec.dequeueOutputBuffer(info, 20_000)
            if (outputIndex < 0) return null
            val output = codec.getOutputBuffer(outputIndex) ?: run {
                codec.releaseOutputBuffer(outputIndex, false)
                return null
            }
            val bytes = ByteArray(info.size)
            output.position(info.offset)
            output.limit(info.offset + info.size)
            output.get(bytes)
            codec.releaseOutputBuffer(outputIndex, false)
            return bytes
        }

        fun close() {
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
        }
    }

    private object MediaCodecListCompat {
        fun findCodec(mime: String, encoder: Boolean): MediaCodecInfo? =
            android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS)
                .codecInfos
                .firstOrNull { it.isEncoder == encoder && it.supportedTypes.any { type -> type.equals(mime, true) } }
    }
}
