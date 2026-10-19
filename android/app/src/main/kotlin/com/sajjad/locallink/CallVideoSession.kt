package com.sajjad.locallink

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.display.DisplayManager
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Base64
import android.view.Display
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

/**
 * Native camera/video endpoint for a LocalLink call.
 *
 * Camera -> MediaCodec(H.264) -> Base64 wire payload -> MeshRouter callback.
 * MeshRouter callback -> Base64 decode -> MediaCodec(H.264 decoder) -> Flutter SurfaceTexture.
 *
 * Application-level video encryption/decryption is intentionally disabled;
 * transport security remains provided by the LocalLink mesh transport.
 */
class CallVideoSession(
    private val context: Context,
    val callId: String,
    val peerId: String,
    private val previewSurface: Surface,
    private val remoteSurface: Surface,
    private val sendPacket: (JSONObject) -> Boolean,
    private val event: (String, Map<String, Any?>) -> Unit,
    private val cameraInitiallyOn: Boolean = true,
) {
    companion object {
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val WIDTH = 640
        private const val HEIGHT = 360
        private const val FPS = 20
        private const val BITRATE = 550_000
        private const val I_FRAME_INTERVAL_SEC = 2
        private const val MAX_PACKET_BYTES = 110 * 1024
    }

    private val running = AtomicBoolean(false)
    private val enabled = AtomicBoolean(cameraInitiallyOn)
    private val sequence = AtomicLong(0)
    private val sentFrames = AtomicLong(0)
    private val receivedFrames = AtomicLong(0)
    private val droppedFrames = AtomicLong(0)
    private val sentBytes = AtomicLong(0)
    private val receivedBytes = AtomicLong(0)
    private val keyframes = AtomicLong(0)

    private var encoder: MediaCodec? = null
    private var decoder: MediaCodec? = null
    private var encoderInputSurface: Surface? = null
    private var camera: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var cameraId: String? = null
    // Sensor->display rotation for the OPEN camera (0/90/180/270). Signaled to
    // the peer inside call_video_config so both sides can undo the stretch.
    @Volatile private var rotationDeg = 0
    private var frontFacing = true
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var encoderThread: Thread? = null
    private var codecConfig0: ByteArray? = null
    private var codecConfig1: ByteArray? = null
    private var decoderConfigured = false

    fun start() {
        if (!running.compareAndSet(false, true)) return
        try {
            if (enabled.get()) {
                require(context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    "Call video: camera permission not granted on this phone."
                }
            }
            // Receive-only sessions (peer turned their camera on first) must NOT
            // build the encoder: a device that only displays video does not need
            // one, and low-end handsets can fail encoder setup even though their
            // decoder is fine. The encoder is created lazily in setEnabled(true).
            if (enabled.get()) {
                ensureEncoder()
                startCameraThread()
                chooseCamera(front = frontFacing)
            }
            event("call_video_started", mapOf("call_id" to callId, "peer_id" to peerId, "width" to WIDTH, "height" to HEIGHT, "fps" to FPS))
            // Tell the peer whether our camera is actually streaming so their
            // UI can render the video area (or the avatar fallback) without
            // waiting for a frame — WhatsApp-style switch-to-video sync.
            sendVideoState(enabled.get())
        } catch (e: Exception) {
            stop()
            // Prefix every failure with "Call video:" so the app's error mapper
            // shows the phone-specific reason instead of the generic toast.
            val message = e.message?.takeIf { it.isNotBlank() } ?: e.javaClass.simpleName
            throw IllegalStateException(if (message.startsWith("Call video:")) message else "Call video: $message")
        }
    }

    /** Creates the encoder on demand (idempotent). */
    private fun ensureEncoder() {
        if (encoder != null) return
        configureEncoder()
        encoderThread = Thread({ encoderLoop() }, "LocalLink-video-encoder").also { it.start() }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        closeCamera()
        encoderThread?.interrupt()
        encoderThread = null
        try { encoder?.stop() } catch (_: Exception) {}
        try { encoder?.release() } catch (_: Exception) {}
        encoder = null
        encoderInputSurface?.release()
        encoderInputSurface = null
        try { decoder?.stop() } catch (_: Exception) {}
        try { decoder?.release() } catch (_: Exception) {}
        decoder = null
        decoderConfigured = false
        codecConfig0 = null
        codecConfig1 = null
        cameraThread?.quitSafely()
        cameraThread = null
        cameraHandler = null
        event("call_video_stopped", mapOf("call_id" to callId, "peer_id" to peerId))
    }

    fun setEnabled(value: Boolean) {
        if (enabled.get() == value && running.get()) { sendVideoState(value); return }
        enabled.set(value)
        if (!value) {
            closeCamera()
        } else if (running.get()) {
            // Turning the camera on mid-call can hit the same device-specific
            // failures as start(); surface the reason instead of dying silently.
            try {
                require(context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    "Call video: camera permission not granted on this phone."
                }
                ensureEncoder()
                if (cameraThread == null) startCameraThread()
                chooseCamera(frontFacing)
            } catch (e: Exception) {
                enabled.set(false)
                sendVideoState(false)
                event("call_video_error", mapOf("call_id" to callId, "peer_id" to peerId, "error" to (e.message ?: e.javaClass.simpleName)))
                return
            }
        }
        event("call_video_enabled", mapOf("call_id" to callId, "peer_id" to peerId, "enabled" to value))
        sendVideoState(value)
    }

    /** Lightweight camera on/off heartbeat for the peer's UI. */
    private fun sendVideoState(on: Boolean) {
        val packet = JSONObject()
            .put("type", "call_video_state")
            .put("sender_id", transportSender())
            .put("recipient_id", peerId)
            .put("call_id", callId)
            .put("timestamp_ms", System.currentTimeMillis())
            .put("enabled", on)
        runCatching { sendPacket(packet) }
    }

    fun switchCamera() {
        if (!running.get()) return
        frontFacing = !frontFacing
        chooseCamera(frontFacing)
    }

    fun stats(): Map<String, Any?> = mapOf(
        "call_id" to callId,
        "peer_id" to peerId,
        "video_enabled" to enabled.get(),
        "width" to WIDTH,
        "height" to HEIGHT,
        "fps" to FPS,
        "bitrate" to BITRATE,
        "sent_frames" to sentFrames.get(),
        "received_frames" to receivedFrames.get(),
        "dropped_frames" to droppedFrames.get(),
        "sent_bytes" to sentBytes.get(),
        "received_bytes" to receivedBytes.get(),
        "keyframes" to keyframes.get(),
        "decoder_configured" to decoderConfigured,
        "camera_facing" to if (frontFacing) "front" else "back",
    )

    fun onIncomingConfig(encoded: String, width: Int, height: Int, sourceId: String, destinationId: String): Boolean {
        if (!running.get() || encoded.isBlank()) return false
        return try {
            val plain = Base64.decode(encoded, Base64.DEFAULT)
            val json = JSONObject(String(plain, Charsets.UTF_8))
            val encoded0 = json.optString("csd_0").trim()
            val encoded1 = json.optString("csd_1").trim()
            if (encoded0.isBlank() || encoded1.isBlank()) return false
            val csd0 = Base64.decode(encoded0, Base64.DEFAULT)
            val csd1 = Base64.decode(encoded1, Base64.DEFAULT)
            if (csd0.isEmpty() || csd1.isEmpty()) return false
            configureDecoder(csd0, csd1, width, height)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun onIncomingFrame(sequenceNumber: Long, timestampMs: Long, encoded: String, sourceId: String, destinationId: String): Boolean {
        if (!running.get() || encoded.isBlank()) return false
        return try {
            if (!decoderConfigured) return false
            val data = Base64.decode(encoded, Base64.DEFAULT)
            val codec = decoder ?: return false
            val inputIndex = codec.dequeueInputBuffer(5_000)
            if (inputIndex < 0) { droppedFrames.incrementAndGet(); return false }
            val input = codec.getInputBuffer(inputIndex) ?: return false
            input.clear()
            if (data.size > input.remaining()) { droppedFrames.incrementAndGet(); return false }
            input.put(data)
            codec.queueInputBuffer(inputIndex, 0, data.size, timestampMs * 1000L, 0)
            drainDecoder(codec)
            receivedFrames.incrementAndGet()
            receivedBytes.addAndGet(data.size.toLong())
            true
        } catch (_: Exception) {
            droppedFrames.incrementAndGet()
            false
        }
    }

    private fun configureEncoder() {
        val format = MediaFormat.createVideoFormat(MIME, WIDTH, HEIGHT).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfoCompat.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL_SEC)
            if (Build.VERSION.SDK_INT >= 21) setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfoCompat.BITRATE_MODE_VBR)
        }
        val codec = try {
            MediaCodec.createEncoderByType(MIME)
        } catch (e: Exception) {
            throw IllegalStateException("Call video: this phone has no H.264 video encoder.")
        }
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (e: Exception) {
            runCatching { codec.release() }
            val detail = (e as? MediaCodec.CodecException)?.diagnosticInfo?.takeIf { it.isNotBlank() }
                ?: e.message ?: e.javaClass.simpleName
            throw IllegalStateException("Call video: H.264 encoder rejected 640x360 ($detail).")
        }
        encoder = codec
        encoderInputSurface = codec.createInputSurface()
        codec.start()
    }

    fun rotationDegrees(): Int = rotationDeg

    private fun startCameraThread() {
        val thread = HandlerThread("LocalLink-video-camera").also { it.start() }
        cameraThread = thread
        cameraHandler = Handler(thread.looper)
    }

    private fun chooseCamera(front: Boolean) {
        closeCamera()
        if (!running.get() || !enabled.get()) return
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val selected = manager.cameraIdList.firstOrNull { id ->
            val facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
            if (front) facing == CameraCharacteristics.LENS_FACING_FRONT
            else facing == CameraCharacteristics.LENS_FACING_BACK
        } ?: manager.cameraIdList.firstOrNull() ?: throw IllegalStateException("No camera is available")
        cameraId = selected
        // Rotate math per the Camera2 SENSOR_ORIENTATION contract: the sensor
        // buffer is written unrotated into every stream surface, so a portrait
        // phone otherwise ships a sideways+stretched image.
        val sensorOrientation = manager.getCameraCharacteristics(selected)
            .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        val displayRotation = try {
            ((context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
                .getDisplay(Display.DEFAULT_DISPLAY)?.rotation ?: 0) * 90
        } catch (_: Exception) { 0 }
        rotationDeg = if (front) (sensorOrientation + displayRotation) % 360
                      else (sensorOrientation - displayRotation + 360) % 360
        manager.openCamera(selected, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                if (!running.get() || !enabled.get()) { device.close(); return }
                camera = device
                createCaptureSession(device)
            }
            override fun onDisconnected(device: CameraDevice) { device.close(); camera = null }
            override fun onError(device: CameraDevice, error: Int) { device.close(); camera = null; event("call_video_camera_error", mapOf("call_id" to callId, "error" to error)) }
        }, cameraHandler)
    }

    private fun createCaptureSession(device: CameraDevice) {
        val preview = previewSurface
        val input = encoderInputSurface ?: return
        try {
            device.createCaptureSession(listOf(preview, input), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (!running.get() || !enabled.get()) { session.close(); return }
                    captureSession = session
                    val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                        addTarget(preview)
                        addTarget(input)
                        set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                        set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                    }
                    try { session.setRepeatingRequest(builder.build(), null, cameraHandler) } catch (_: Exception) {}
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    session.close()
                    event("call_video_camera_error", mapOf("call_id" to callId, "reason" to "capture_session_failed"))
                }
            }, cameraHandler)
        } catch (e: Exception) {
            event("call_video_camera_error", mapOf("call_id" to callId, "reason" to (e.message ?: "capture_session_error")))
        }
    }

    private fun closeCamera() {
        try { captureSession?.stopRepeating() } catch (_: Exception) {}
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null
        try { camera?.close() } catch (_: Exception) {}
        camera = null
    }

    private fun encoderLoop() {
        val codec = encoder ?: return
        val info = MediaCodec.BufferInfo()
        while (running.get()) {
            try {
                when (val index = codec.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> sendCodecConfig(codec.outputFormat)
                    else -> if (index >= 0) {
                        val buffer = codec.getOutputBuffer(index)
                        if (buffer != null && info.size > 0) {
                            val data = ByteArray(info.size)
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            buffer.get(data)
                            if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                                sendCodecConfigFromBuffer(data)
                            } else {
                                val keyFrame = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
                                if (keyFrame) keyframes.incrementAndGet()
                                sendVideoFrame(data, info.presentationTimeUs / 1000L, keyFrame)
                            }
                        }
                        codec.releaseOutputBuffer(index, false)
                    }
                }
            } catch (_: InterruptedException) { break } catch (_: Exception) { if (!running.get()) break }
        }
    }

    private fun sendCodecConfig(format: MediaFormat) {
        val c0 = bufferBytes(format.getByteBuffer("csd-0"))
        val c1 = bufferBytes(format.getByteBuffer("csd-1"))
        if (c0 == null || c1 == null || c0.isEmpty() || c1.isEmpty()) return
        sendCodecConfig(c0, c1)
    }

    private fun sendCodecConfigFromBuffer(data: ByteArray) {
        val (c0, c1) = splitConfig(data) ?: return
        sendCodecConfig(c0, c1)
    }

    private fun sendCodecConfig(c0: ByteArray, c1: ByteArray) {
        codecConfig0 = c0
        codecConfig1 = c1
        val encoded = Base64.encodeToString(
            JSONObject().put("csd_0", Base64.encodeToString(c0, Base64.NO_WRAP)).put("csd_1", Base64.encodeToString(c1, Base64.NO_WRAP)).toString().toByteArray(Charsets.UTF_8),
            Base64.NO_WRAP,
        )
        val packet = JSONObject()
            .put("type", "call_video_config")
            .put("sender_id", transportSender())
            .put("recipient_id", peerId)
            .put("call_id", callId)
            .put("width", WIDTH)
            .put("height", HEIGHT)
            .put("rotation", rotationDeg)
            .put("config", encoded)
        if (sendPacket(packet)) event("call_video_config_sent", mapOf("call_id" to callId, "peer_id" to peerId))
    }

    private fun sendVideoFrame(data: ByteArray, timestampMs: Long, keyFrame: Boolean) {
        if (!enabled.get()) return
        val seq = sequence.getAndIncrement()
        val encoded = Base64.encodeToString(data, Base64.NO_WRAP)
        if (encoded.toByteArray(Charsets.UTF_8).size > MAX_PACKET_BYTES) { droppedFrames.incrementAndGet(); return }
        val packet = JSONObject()
            .put("type", "call_video_frame")
            .put("sender_id", transportSender())
            .put("recipient_id", peerId)
            .put("call_id", callId)
            .put("sequence", seq)
            .put("timestamp_ms", timestampMs)
            .put("key_frame", keyFrame)
            .put("video", encoded)
        if (sendPacket(packet)) {
            sentFrames.incrementAndGet()
            sentBytes.addAndGet(data.size.toLong())
        } else droppedFrames.incrementAndGet()
    }

    private fun configureDecoder(csd0: ByteArray, csd1: ByteArray, width: Int, height: Int) {
        if (decoderConfigured) return
        val format = MediaFormat.createVideoFormat(MIME, width.coerceAtLeast(2), height.coerceAtLeast(2)).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(csd0))
            setByteBuffer("csd-1", ByteBuffer.wrap(csd1))
            if (Build.VERSION.SDK_INT >= 21) setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, maxOf(csd0.size + csd1.size, 256 * 1024))
        }
        val codec = MediaCodec.createDecoderByType(MIME)
        codec.configure(format, remoteSurface, null, 0)
        decoder = codec
        codec.start()
        decoderConfigured = true
    }

    private fun drainDecoder(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        var count = 0
        while (count < 4) {
            val index = codec.dequeueOutputBuffer(info, 0)
            if (index < 0) break
            codec.releaseOutputBuffer(index, true)
            count++
        }
    }

    private fun transportSender(): String = LocalLinkTransportService.currentDeviceId() ?: ""

    private fun bufferBytes(buffer: ByteBuffer?): ByteArray? {
        if (buffer == null) return null
        val duplicate = buffer.duplicate()
        val out = ByteArray(duplicate.remaining())
        duplicate.get(out)
        return out
    }

    private fun splitConfig(data: ByteArray): Pair<ByteArray, ByteArray>? {
        val nals = mutableListOf<ByteArray>()
        var start = 0
        var i = 0
        fun addRange(a: Int, b: Int) {
            if (b > a) nals.add(data.copyOfRange(a, b))
        }
        while (i + 3 < data.size) {
            val four = i + 4 <= data.size && data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()
            val three = data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()
            if (four || three) {
                addRange(start, i)
                i += if (four) 4 else 3
                start = i
            } else i++
        }
        addRange(start, data.size)
        val filtered = nals.filter { it.isNotEmpty() }
        val sps = filtered.firstOrNull { (it[0].toInt() and 0x1F) == 7 } ?: return null
        val pps = filtered.firstOrNull { (it[0].toInt() and 0x1F) == 8 } ?: return null
        return sps to pps
    }

    object MediaCodecInfoCompat {
        const val COLOR_FormatSurface = 0x7F000789
        const val BITRATE_MODE_VBR = 1
    }
}
