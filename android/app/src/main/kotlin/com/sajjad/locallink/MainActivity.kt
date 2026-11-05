package com.sajjad.locallink

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import android.net.wifi.p2p.WifiP2pConfig
import com.sajjad.locallink.mesh.NearbyGroupPolicy
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.view.Surface
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.media.MediaRecorder
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val EXTRA_CALL_ACTION_CONSUMED = "call_action_consumed"
        @Volatile private var activeInstance: MainActivity? = null
        /** Bundle 169 (4.3): the app screen exists. */
        fun isOpen(): Boolean = activeInstance != null

        fun dispatchNotificationAction(intent: Intent): Boolean {
            val activity = activeInstance ?: return false
            activity.runOnUiThread { activity.dispatchCallNotificationIntent(intent, "receiver") }
            return true
        }

        /**
         * Bundle 151: message Reply / Mark-read from the notification receiver.
         * (The call entry above sent these to the CALL handler, which dropped
         * them.) Call actions keep using [dispatchNotificationAction].
         */
        fun dispatchMessageNotificationAction(intent: Intent): Boolean {
            val activity = activeInstance ?: return false
            activity.runOnUiThread { activity.dispatchNotificationIntent(intent) }
            return true
        }

        /** Bundle 177 (7.8): friend Remove / Block for the open app (false = closed). */
        fun dispatchFriendAction(event: Map<String, Any?>): Boolean {
            val activity = activeInstance ?: return false
            activity.runOnUiThread {
                val sink = activity.notificationEventSink
                if (sink != null) sink.success(event) else activity.pendingNotificationActions.add(event)
            }
            return true
        }

        private const val EXTRA_MESSAGE_ACTION_CONSUMED = "message_notification_action_consumed"
        // Bundle G6: invite link waiting for Dart ("take").
        private const val EXTRA_JOIN_LINK_CONSUMED = "join_link_consumed"
        @Volatile private var pendingJoinLink: String? = null
    }

    private val channelName = "locallink/files"
    private val voiceNotesChannelName = "locallink/voice_notes"
    private val wifiChannelName = "locallink/wifi_direct"
    private val wifiEventsName = "locallink/wifi_direct_events"
    private val transportChannelName = "locallink/wifi_direct_transport"
    private val transportEventsName = "locallink/wifi_direct_transport_events"
    private val callMediaChannelName = "locallink/call_media"
    private val callRingtoneChannelName = "locallink/call_ringtone"
    private val callNotificationChannelName = "locallink/call_notifications"
    private val callNotificationEventsName = "locallink/call_notification_actions"
    private val wifiRadioChannelName = "locallink/wifi_radio"
    private val requestCode = 4931
    private val wifiPermissionRequestCode = 7742
    private var pendingResult: MethodChannel.Result? = null
    private var pendingWifiPermissionResult: MethodChannel.Result? = null
    private var voiceRecorder: MediaRecorder? = null
    private var voiceRecordingPath: String? = null
    private var voicePlayer: MediaPlayer? = null
    // Bundle 177: this screen's Nearby event sink (NearbyRadio owns Nearby).
    private var wifiEventSink: EventChannel.EventSink? = null
    private val backgroundLocationRequestCode = 7815
    private var transportEventSink: EventChannel.EventSink? = null
    private var localVideoTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null
    private var remoteVideoTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null
    private var localVideoSurface: Surface? = null
    private var remoteVideoSurface: Surface? = null
    private var callNotificationEventSink: EventChannel.EventSink? = null
    private val pendingCallNotificationActions = mutableListOf<Map<String, Any>>()
    private var notificationEventSink: EventChannel.EventSink? = null
    private val pendingNotificationActions = mutableListOf<Map<String, Any?>>()
    // Bundle 147: chat video picture-in-picture (never during calls).
    private val chatVideoPip by lazy { ChatVideoPip(this) }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Bundle 169 (4.3): the app is opened - the after-reboot background
        // engine stops first, so only one engine runs the app at a time.
        BackgroundEngine.stop("app_opened")
        super.onCreate(savedInstanceState)
        LinkUpLogFile.start(this) // Bundle 180: last hour of logs
        // Bundle 185 (A): how long Android took to get here, why LinkUp
        // stopped last time, what it may do now, and a 2-minute freeze watch.
        if (Build.VERSION.SDK_INT >= 24) {
            val sinceStart = android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime()
            android.util.Log.i(AppHealthPolicy.TAG, "APP_OPEN since_process_start_ms=$sinceStart")
        }
        AppHealth.logExitsOnce(this)
        AppHealth.logKeepAlive(this, "open")
        AppHealth.appOpened()
        activeInstance = this
        BackgroundEngine.markAppOpened(this)
        // Bundle 164 (4.3): the app is open - the reboot notice is not needed.
        LocalLinkNotificationManager.cancelBootReconnect(this)
        // Bundle 175 (5): 15-minute health check (KEEP: scheduled once).
        // Bundle 185 (D4): off the main thread - WorkManager's first start
        // reads its database, and the main thread also runs Dart now.
        val appCtx = applicationContext
        Thread({ BackgroundHealth.schedule(appCtx) }, "linkup-health-schedule").apply { isDaemon = true }.start()
        // Bundle 124: the once-per-install battery-exemption dialog that used
        // to fire here slapped first-time users on TOP of the register/login
        // screen with zero context. The dashboard permission sequencer
        // (Bundle 121, step "background") now owns that ask through the same
        // official system dialog, with recoverable re-asks. OEM killers
        // (ZTE SuperKiller etc.) still honor the exemption once granted.
    }

    // Bundle 145: first frame (JPEG, <= maxPx), length and display size of a chat
    // video, read from the app's own temporary decrypted view copy. Off the UI thread.
    /** Bundle 164 (4.4): 9x9 brightness samples of a frame. */
    private fun isDarkFrame(b: android.graphics.Bitmap): Boolean {
        if (b.width <= 0 || b.height <= 0) return true
        val lumas = IntArray(81)
        var i = 0
        for (y in 0 until 9) for (x in 0 until 9) {
            val px = b.getPixel(((x * 2 + 1) * b.width / 18).coerceIn(0, b.width - 1), ((y * 2 + 1) * b.height / 18).coerceIn(0, b.height - 1))
            lumas[i++] = VideoFramePolicy.luma(px)
        }
        return VideoFramePolicy.isMostlyDark(lumas)
    }

    /** Bundle 197b: run a media helper off the UI thread, answer on it. */
    private fun mediaBg(result: MethodChannel.Result, work: () -> Any?) {
        Thread({
            val out = try { Result.success(work()) } catch (e: Exception) { Result.failure<Any?>(e) }
            runOnUiThread {
                out.fold({ result.success(it) }, { result.error("MEDIA_STORAGE_FAILED", it.message ?: it.javaClass.simpleName, null) })
            }
        }, "linkup-media").start()
    }

    private fun readVideoInfo(path: String?, maxPx: Int, result: MethodChannel.Result) {
        val file = path?.let { File(it) }
        val dataDir = try { File(applicationInfo.dataDir).canonicalPath } catch (_: Exception) { "" }
        if (file == null || !file.isFile || dataDir.isEmpty() ||
            !file.canonicalPath.startsWith(dataDir + File.separator)) {
            result.error("VIDEO_INFO_FAILED", "invalid file", null)
            return
        }
        val bound = maxPx.coerceIn(64, 1280)
        Thread({
            val retriever = android.media.MediaMetadataRetriever()
            val out: Map<String, Any>? = try {
                retriever.setDataSource(file.absolutePath)
                val duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                val rawW = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                val rawH = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                val rotation = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                fun frameAt(us: Long): android.graphics.Bitmap? = try {
                    if (Build.VERSION.SDK_INT >= 27)
                        retriever.getScaledFrameAtTime(us, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, bound, bound)
                    else retriever.getFrameAtTime(us, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                } catch (_: Exception) { null }
                var frame: android.graphics.Bitmap? = frameAt(0L)
                // Bundle 164 (4.4): no first frame, or a black one - try 1 s
                // and a quarter in. Keep the first frame if nothing is better.
                if (frame == null || isDarkFrame(frame)) {
                    for (us in VideoFramePolicy.retryTimesUs(duration)) {
                        val next = frameAt(us) ?: continue
                        if (!isDarkFrame(next)) {
                            frame?.recycle()
                            frame = next
                            break
                        }
                        if (frame == null) frame = next else next.recycle()
                    }
                }
                val f0 = frame
                if (f0 != null && (f0.width > bound || f0.height > bound)) {
                    val scale = bound.toFloat() / maxOf(f0.width, f0.height)
                    val scaled = android.graphics.Bitmap.createScaledBitmap(f0,
                        maxOf(1, (f0.width * scale).toInt()), maxOf(1, (f0.height * scale).toInt()), true)
                    if (scaled !== f0) f0.recycle()
                    frame = scaled
                }
                // Frames come out already rotated; without one, swap for 90/270.
                val quarter = rotation == 90 || rotation == 270
                val f = frame
                val displayW = f?.width ?: if (quarter) rawH else rawW
                val displayH = f?.height ?: if (quarter) rawW else rawH
                val bytes = if (f != null) {
                    val os = java.io.ByteArrayOutputStream()
                    f.compress(android.graphics.Bitmap.CompressFormat.JPEG, 78, os)
                    f.recycle()
                    os.toByteArray()
                } else ByteArray(0)
                mapOf("duration_ms" to duration, "width" to rawW, "height" to rawH, "rotation" to rotation,
                    "display_width" to displayW, "display_height" to displayH, "thumbnail" to bytes)
            } catch (_: Exception) {
                null
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
            runOnUiThread {
                if (out == null) result.error("VIDEO_INFO_FAILED", "unreadable video", null) else result.success(out)
            }
        }, "locallink-video-info").start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Bundle 149: run the one-time Opus self-test early, in the background,
        // so the first call never waits for it.
        // Bundle 185 (D1): not during the start - it used 0.9 s of CPU on the
        // ZTE right while the first screen was drawing. 20 s later, or at once
        // when a call needs it (CallOpusCodec.usable() runs it then).
        CallOpusCodec.selfTestLater(this)
        chatVideoPip.register(flutterEngine.dartExecutor.binaryMessenger) // Bundle 147
        registerLogChannel(this, flutterEngine.dartExecutor.binaryMessenger) // Bundle 180
        // Stable per-device identity survives app reinstall/data-clear (resets
        // only on factory reset or signing-key change). Used to re-bind this
        // physical phone to its existing device row and to restore the account.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/device").setMethodCallHandler { call, result ->
            if (call.method == "androidId") {
                try {
                    result.success(android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: "")
                } catch (e: Exception) {
                    result.success("")
                }
            } else if (call.method == "stallOverlap") {
                // Bundle 187 (A2): was the screen frozen while a slow storage step ran?
                result.success(AppHealth.stallOverlap((call.argument<Number>("window_ms") ?: 0).toLong()))
            } else {
                result.notImplemented()
            }
        }
        // Bundle 210: Share LinkUp (hotspot + APK info, its own channel).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AppShareNative.CHANNEL).setMethodCallHandler { call, result ->
            AppShareNative.handle(this, call, result)
        }
        // Bundle 177 (2): Nearby lives in NearbyRadio (application context), so
        // closing this screen no longer stops it. Same channel, same answers.
        NearbyRadio.ensure(this)
        NearbyRadio.logState(this, "open")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiChannelName).setMethodCallHandler { call, result ->
            // The permission dialog needs this screen; everything else is NearbyRadio.
            if (call.method == "requestEnable") requestWifiPermission(result)
            else NearbyRadio.handle(call, result, null)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, wifiEventsName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { wifiEventSink = events; NearbyRadio.attach(events) }
            override fun onCancel(arguments: Any?) { NearbyRadio.detach(wifiEventSink); wifiEventSink = null }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, transportChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> configureTransport(call, result)
                    "ensureTransportReady" -> {
                        val id = call.argument<String>("device_id")?.trim().orEmpty()
                        if (id.isEmpty()) { result.error("INVALID_DEVICE", "device_id is required", null); return@setMethodCallHandler }
                        val peers = stringList(call.argument<List<*>>("known_peers"))
                        // Bundle 117: transport bootstrap opens sockets and encrypts
                        // transport state — it must never run on the UI thread.
                        // Its synchronous main-thread run was the receiver-side ANR
                        // when a user accepted an incoming pair dialog.
                        Thread({
                            try {
                                LocalLinkTransportService.ensureReady(this@MainActivity, id, peers)
                                runOnUiThread { result.success(null) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("TRANSPORT_ERROR", error.message, null) }
                            }
                        }, "locallink-ensure-transport").start()
                    }
                    "updateKnownPeers" -> {
                        val peers = stringList(call.argument<List<*>>("known_peers"))
                        // Bundle 117: roster push rewrites encrypted transport
                        // state (AES) — off the UI thread.
                        Thread({
                            LocalLinkTransportService.updateKnownPeers(this@MainActivity, peers)
                            runOnUiThread { result.success(null) }
                        }, "locallink-known-peers").start()
                    }
                    // Bundle 164 (5.8): strict mode switch (saved natively too,
                    // so the service uses it after a reboot).
                    "setStrictLinkCheck" -> {
                        val on = call.argument<Boolean>("on") == true
                        Thread({
                            LocalLinkTransportService.setStrictLinkCheck(this@MainActivity, on)
                            runOnUiThread { result.success(null) }
                        }, "locallink-strict").start()
                    }
                    // Bundle 156: blocked people are never used as relays.
                    "updateBlockedPeers" -> {
                        val blocked = stringList(call.argument<List<*>>("blocked_peers"))
                        Thread({
                            LocalLinkTransportService.updateBlockedPeers(blocked)
                            runOnUiThread { result.success(null) }
                        }, "locallink-blocked-peers").start()
                    }
                    // Bundle 160: per-contact link keys (signed device id).
                    "updateLinkKeys" -> {
                        val json = call.argument<String>("link_keys").orEmpty()
                        Thread({
                            val stored = LocalLinkTransportService.updateLinkKeys(json)
                            runOnUiThread { result.success(stored) }
                        }, "locallink-link-keys").start()
                    }
                    // Bundle G7: file lock keys for group members who are not friends.
                    "updatePeerFileKeys" -> {
                        val json = call.argument<String>("peer_file_keys").orEmpty()
                        Thread({
                            val stored = LocalLinkTransportService.updatePeerFileKeys(json)
                            runOnUiThread { result.success(stored) }
                        }, "locallink-peer-file-keys").start()
                    }
                    "sendPairPayload" -> {
                        val target = call.argument<String>("target").orEmpty()
                        val pairKind = call.argument<String>("pair").orEmpty()
                        val body = call.argument<String>("body").orEmpty()
                        LocalLinkTransportService.sendPairPayload(target, pairKind, body) { ok, error ->
                            runOnUiThread { if (ok) result.success(null) else result.error("PAIR_SEND_FAILED", error, null) }
                        }
                    }
                    "send" -> {
                        val targetId = call.argument<String>("recipient_id")?.trim().orEmpty()
                        val payload = mapToPayload(call.argument<Map<*, *>>("payload"))
                        // Bundle 117: socket writes can stall for seconds when a peer
                        // link is half-dead — that stall on the UI thread froze the
                        // whole app during the message flush loop. Background it.
                        Thread({
                            val ok = LocalLinkTransportService.send(targetId, payload)
                            runOnUiThread { if (ok) result.success(null) else result.error("PEER_UNAVAILABLE", "peer is not connected", null) }
                        }, "locallink-send").start()
                    }
                    "broadcast" -> {
                        val payload = mapToPayload(call.argument<Map<*, *>>("payload"))
                        // Bundle 117: same UI-thread socket-stall risk as "send".
                        Thread({
                            val ok = LocalLinkTransportService.broadcast(payload)
                            runOnUiThread { if (ok) result.success(null) else result.error("BROADCAST_FAILED", "no direct peer is connected", null) }
                        }, "locallink-broadcast").start()
                    }
                    "sendFile" -> sendFileTransport(call, result)
                    "cancelFile" -> { LocalLinkTransportService.cancelFile(call.argument<String>("file_id")?.trim().orEmpty()); result.success(null) }
                    "allowFile" -> { LocalLinkTransportService.allowFile(call.argument<String>("file_id")?.trim().orEmpty()); result.success(null) }
                    "topology" -> Thread({
                        try {
                            val topology = LocalLinkTransportService.topology()
                            runOnUiThread { result.success(topology) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "TOPOLOGY_FAILED",
                                    error.message ?: "Could not read local transport topology",
                                    null,
                                )
                            }
                        }
                    }, "locallink-topology").start()
                    "flushQueue" -> Thread({ LocalLinkTransportService.flushQueue(); runOnUiThread { result.success(null) } }, "locallink-flush").start() // Bundle 117: off UI thread
                    "resume" -> { NearbyRadio.requestConnectionInfo(); result.success(null) }
                    "clearStorage" -> { LocalLinkTransportService.clearStorage(); result.success(null) }
                    "stop" -> { LocalLinkTransportService.stop(this); NearbyRadio.shutdown("logout"); result.success(null) } // Bundle 177 (2.8): only Log out stops Nearby
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("TRANSPORT_ERROR", e.message, null) }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, transportEventsName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                transportEventSink = events
                LocalLinkTransportService.setEventListener(object : LocalLinkTransportService.EventListener {
                    override fun onTransportEvent(type: String, data: Map<String, Any?>) { runOnUiThread { transportEventSink?.success(data) } }
                })
            }
            override fun onCancel(arguments: Any?) {
                transportEventSink = null
                LocalLinkTransportService.setEventListener(null)
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiRadioChannelName).setMethodCallHandler { call, result ->
            try {
                val wifi = getSystemService(Context.WIFI_SERVICE) as WifiManager
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val managed = dpm.isDeviceOwnerApp(packageName)
                when (call.method) {
                    "status" -> result.success(mapOf(
                        "supported" to packageManager.hasSystemFeature("android.hardware.wifi"),
                        "enabled" to wifi.isWifiEnabled,
                        "managed_device" to managed,
                        "can_control" to managed
                    ))
                    // Bundle 159: the Wi-Fi off card opens the Wi-Fi panel
                    // (Android 10+) or the Wi-Fi settings screen.
                    "open_settings" -> {
                        val action = if (Build.VERSION.SDK_INT >= 29) android.provider.Settings.Panel.ACTION_WIFI else android.provider.Settings.ACTION_WIFI_SETTINGS
                        try {
                            startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } catch (_: Exception) { result.success(false) }
                        }
                    }
                    "enforce" -> {
                        if (!managed) {
                            result.success(mapOf("supported" to true, "enabled" to wifi.isWifiEnabled, "managed_device" to false, "can_control" to false))
                        } else {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            val component = ComponentName(this, LocalLinkDeviceAdminReceiver::class.java)
                            dpm.setGlobalSetting(component, android.provider.Settings.Global.WIFI_ON, if (enabled) "1" else "0")
                            result.success(mapOf("supported" to true, "enabled" to wifi.isWifiEnabled, "managed_device" to true, "can_control" to true))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("WIFI_POLICY_SECURITY", e.message, null)
            } catch (e: Exception) {
                result.error("WIFI_POLICY_ERROR", e.message, null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callRingtoneChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        CallRingtoneManager.start(this)
                        result.success(null)
                    }
                    "stop" -> {
                        CallRingtoneManager.stop()
                        result.success(null)
                    }
                    "ringback_start" -> {
                        CallRingtoneManager.startRingback(this)
                        result.success(null)
                    }
                    "ringback_stop" -> {
                        CallRingtoneManager.stopRingback()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("RINGTONE_ERROR", e.message, null)
            }
        }

        CallNotificationManager.initialize(this)
        // Bundle 176 (3): ringing call hand-over between engines.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CallHandover.CHANNEL).setMethodCallHandler { call, result -> CallHandover.handle(call, result) }

        // Bundle 140: "Keep LocalLink running" — battery-exemption status /
        // system dialog, and OEM autostart deep links (HiOS/MIUI/ColorOS/…).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/background").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "batteryExempted" -> result.success(powerManager().isIgnoringBatteryOptimizations(packageName))
                    "requestBatteryExemption" -> {
                        if (!powerManager().isIgnoringBatteryOptimizations(packageName)) {
                            startActivity(Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(null)
                    }
                    "openVendorSettings" -> result.success(openVendorBackgroundSettings())
                    // Bundle 163 (5.6): brand help screen.
                    "deviceBrand" -> result.success("${android.os.Build.MANUFACTURER} ${android.os.Build.BRAND}")
                    "openBrandSettings" -> result.success(openBrandBackgroundSettings(call.argument<String>("brand").orEmpty()))
                    "keepAliveStart" -> { BackgroundHealth.setEnabled(this, true); LocalLinkTransportService.start(this); result.success(null) }
                    // Bundle 175 (10): the STATUS card.
                    "backgroundStatus" -> result.success(mapOf(
                        "running" to LocalLinkTransportService.isRunning(),
                        "notifications" to LocalLinkNotificationManager.notificationsEnabled(this),
                        "battery_exempt" to powerManager().isIgnoringBatteryOptimizations(packageName),
                        "last_denied" to (LocalLinkTransportService.lastForegroundDenied() ?: BackgroundHealth.lastDenied(this)),
                        "enabled" to BackgroundHealth.isEnabled(this),
                        // Bundle 177 (10.1): Nearby while closed (admin_off is added by Dart).
                        "nearby" to NearbyRadio.statusWord(this),
                        // Bundle 179 (3.4, 3.5): ok / category_off / lockscreen_off / permission / app_off.
                        "call_alerts" to CallNotificationManager.alertState(this),
                    ))
                    // Bundle 179 (3.4, 3.5): STATUS "Call alerts off" / "Lock-screen calls off" tap.
                    "openCallAlertSettings" -> {
                        CallNotificationManager.openAlertSettings(this, call.argument<String>("state").orEmpty())
                        result.success(null)
                    }
                    // Bundle 177 (9.2): Android 10-12 need "Location: All the time"
                    // for Nearby with no screen. Asked once, by the user's tap only.
                    "backgroundLocationNeeded" -> result.success(
                        android.os.Build.VERSION.SDK_INT in 29..32 &&
                            NearbyRadio.hasPermission(this) &&
                            !NearbyRadio.hasBackgroundLocation(this)
                    )
                    "requestBackgroundLocation" -> {
                        if (android.os.Build.VERSION.SDK_INT in 29..32 && NearbyRadio.hasPermission(this)) {
                            requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), backgroundLocationRequestCode)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("background", error.message, null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callNotificationChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermission" -> {
                        CallNotificationManager.requestNotificationPermission(this)
                        result.success(null)
                    }
                    "showIncoming" -> {
                        val callId = call.argument<String>("call_id")?.trim().orEmpty()
                        val callerId = call.argument<String>("caller_id")?.trim().orEmpty()
                        val callerName = call.argument<String>("caller_name")?.trim().orEmpty()
                        if (callId.isEmpty() || callerId.isEmpty()) {
                            result.error("INVALID_CALL_NOTIFICATION", "call_id and caller_id are required", null)
                            return@setMethodCallHandler
                        }
                        CallNotificationManager.showIncoming(this, callId, callerId, callerName)
                        result.success(null)
                    }
                    "cancelIncoming", "cancelAll" -> {
                        CallNotificationManager.cancelAll(this)
                        result.success(null)
                    }
                    // Bundle 179 (2): the saved notification Accept (or null).
                    "acceptedCall" -> result.success(CallAcceptMemory.peek(this))
                    "clearAcceptedCall" -> {
                        CallAcceptMemory.clear(this, call.argument<String>("call_id"))
                        result.success(null)
                    }
                    // Bundle 146: Dart keeps the call UI above the lock screen
                    // while a call is live and releases it when the call ends.
                    "setCallLockScreen" -> {
                        setCallLockScreen(
                            call.argument<Boolean>("show") == true,
                            call.argument<Boolean>("turn_screen_on") == true,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("CALL_NOTIFICATION_ERROR", e.message, null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, callNotificationEventsName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                callNotificationEventSink = events
                val queued = pendingCallNotificationActions.toList()
                pendingCallNotificationActions.clear()
                queued.forEach { events?.success(it) }
            }
            override fun onCancel(arguments: Any?) { callNotificationEventSink = null }
        })

        LocalLinkNotificationManager.initialize(this)
        // Bundle 101: native-dialog-only status/request plumbing for the Dart
        // permission sequencer (mic -> nearby -> notifications).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/permissions").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "granted" -> result.success(mapOf("granted" to gateIsGranted(call.argument<String>("name")?.trim().orEmpty())))
                    "request" -> { gateRequest(call.argument<String>("name")?.trim().orEmpty()); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("PERMISSIONS_SEQ", e.message, null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/notifications").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> { LocalLinkNotificationManager.initialize(this); result.success(null) }
                    "requestPermission" -> { LocalLinkNotificationManager.requestNotificationPermission(this); result.success(null) }
                    "notificationsEnabled" -> result.success(LocalLinkNotificationManager.notificationsEnabled(this))
                    "openSettings" -> { LocalLinkNotificationManager.openSettings(this); result.success(null) }
                    "showMessage" -> {
                        val notificationId = call.argument<Int>("notification_id") ?: 0
                        val conversationType = call.argument<String>("conversation_type")?.trim().orEmpty()
                        val conversationId = call.argument<String>("conversation_id")?.trim().orEmpty()
                        val messageId = call.argument<String>("message_id")?.trim().orEmpty()
                        val senderId = call.argument<String>("sender_id")?.trim().orEmpty()
                        val recipientId = call.argument<String>("recipient_id")?.trim().orEmpty()
                        val title = call.argument<String>("title")?.trim().orEmpty()
                        val body = call.argument<String>("body")?.trim().orEmpty()
                        if (notificationId <= 0 || conversationType.isEmpty() || conversationId.isEmpty() || messageId.isEmpty() || senderId.isEmpty() || recipientId.isEmpty()) {
                            result.error("INVALID_NOTIFICATION", "notification identity is incomplete", null)
                            return@setMethodCallHandler
                        }
                        LocalLinkNotificationManager.showMessage(
                            this,
                            notificationId,
                            conversationType,
                            conversationId,
                            messageId,
                            senderId,
                            recipientId,
                            title,
                            body,
                            call.argument<String>("summary")?.trim().orEmpty(),
                            call.argument<String>("public_title")?.trim().orEmpty(),
                            call.argument<String>("public_body")?.trim().orEmpty(),
                            call.argument<String>("initials")?.trim().orEmpty(),
                            call.argument<String>("avatar_path")?.trim(),
                            call.argument<String>("image_path")?.trim(),
                            call.argument<String>("attachment_id")?.trim(),
                            call.argument<Int>("unread_count") ?: 1,
                            call.argument<Boolean>("silent") == true,
                            call.argument<Int>("visibility") ?: 0,
                        )
                        result.success(null)
                    }
                    "showSummary" -> {
                        val notificationId = call.argument<Int>("notification_id") ?: 0
                        val conversationType = call.argument<String>("conversation_type")?.trim().orEmpty()
                        val conversationId = call.argument<String>("conversation_id")?.trim().orEmpty()
                        if (notificationId <= 0 || conversationType !in setOf("direct", "group") || conversationId.isEmpty()) {
                            result.error("INVALID_NOTIFICATION_SUMMARY", "summary identity is incomplete", null)
                            return@setMethodCallHandler
                        }
                        LocalLinkNotificationManager.showSummary(
                            this,
                            notificationId,
                            conversationType,
                            conversationId,
                            call.argument<String>("title")?.trim().orEmpty(),
                            call.argument<String>("body")?.trim().orEmpty(),
                            call.argument<Boolean>("silent") == true,
                            call.argument<Int>("visibility") ?: 0,
                        )
                        result.success(null)
                    }
                    // Bundle 177 (7.8): "X added you as a friend".
                    "showFriendAdded" -> {
                        LocalLinkNotificationManager.showFriendAdded(
                            this,
                            call.argument<Int>("notification_id") ?: 0,
                            call.argument<String>("user_id")?.trim().orEmpty(),
                            call.argument<String>("device_id")?.trim().orEmpty(),
                            call.argument<String>("recipient_id")?.trim().orEmpty(),
                            call.argument<String>("name")?.trim().orEmpty(),
                        )
                        result.success(null)
                    }
                    // Bundle 196 (12b): "Ali wants to add you" / "accepted".
                    "showFriendRequest" -> {
                        LocalLinkNotificationManager.showFriendRequest(
                            this,
                            call.argument<Int>("notification_id") ?: 0,
                            call.argument<String>("user_id")?.trim().orEmpty(),
                            call.argument<String>("device_id")?.trim().orEmpty(),
                            call.argument<String>("recipient_id")?.trim().orEmpty(),
                            call.argument<String>("name")?.trim().orEmpty(),
                        )
                        result.success(null)
                    }
                    "showFriendAccepted" -> {
                        LocalLinkNotificationManager.showFriendAccepted(
                            this,
                            call.argument<Int>("notification_id") ?: 0,
                            call.argument<String>("device_id")?.trim().orEmpty(),
                            call.argument<String>("recipient_id")?.trim().orEmpty(),
                            call.argument<String>("name")?.trim().orEmpty(),
                        )
                        result.success(null)
                    }
                    "cancelFriend" -> {
                        LocalLinkNotificationManager.cancelFriend(this, call.argument<Int>("notification_id") ?: 0)
                        result.success(null)
                    }
                    "showSystem" -> {
                        val notificationId = call.argument<Int>("notification_id") ?: 0
                        LocalLinkNotificationManager.showSystem(
                            this,
                            notificationId,
                            call.argument<String>("title")?.trim().orEmpty(),
                            call.argument<String>("body")?.trim().orEmpty(),
                            call.argument<Boolean>("silent") == true,
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        LocalLinkNotificationManager.cancel(this, call.argument<Int>("notification_id") ?: 0)
                        result.success(null)
                    }
                    "cancelMessages" -> { LocalLinkNotificationManager.cancelMessages(this); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NOTIFICATION_ERROR", e.message, null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/notification_actions").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                notificationEventSink = events
                val queued = pendingNotificationActions.toList()
                pendingNotificationActions.clear()
                queued.forEach { events?.success(it) }
                // Bundle 162 (4.1): Reply / Mark read saved while the app was closed.
                val saved = NotificationActionOutbox.takeAll(this@MainActivity)
                if (saved.isNotEmpty()) {
                    android.util.Log.i("LocalLinkNotify", "NOTIFICATION_ACTIONS_RESTORED count=${saved.size}")
                    LocalLinkNotificationManager.cancelReplySaved(this@MainActivity)
                }
                saved.forEach { events?.success(it) }
            }
            override fun onCancel(arguments: Any?) { notificationEventSink = null }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/call_audio").setMethodCallHandler { call, result ->
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                when (call.method) {
                    "setSpeakerphoneOn" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        // Bundle 186 (C1): the audio mode switch is slow on some
                        // phones (Unisoc): it runs on the call audio thread now,
                        // so the screen and Dart never wait for it.
                        CallAudioThread.run("route speaker=$enabled", { applyCallRoute(audioManager, enabled) }) { error ->
                            if (error == null) result.success(null)
                            else result.error("CALL_AUDIO_ERROR", error.message ?: error.javaClass.simpleName, null)
                        }
                    }
                    // Bundle 143: in-call phone behaviour, driven by the Dart session.
                    "setCallUi" -> {
                        val inCall = call.argument<Boolean>("in_call") == true
                        val proximity = call.argument<Boolean>("proximity") == true
                        volumeControlStream = if (inCall) android.media.AudioManager.STREAM_VOICE_CALL
                            else android.media.AudioManager.USE_DEFAULT_STREAM_TYPE
                        setCallProximity(inCall && proximity)
                        result.success(null)
                    }
                    "clearCommunicationDevice" -> {
                        // Bundle 143: call over — always hand screen + volume keys back.
                        setCallProximity(false)
                        volumeControlStream = android.media.AudioManager.USE_DEFAULT_STREAM_TYPE
                        // Bundle 186 (C1): the audio part on the call audio thread,
                        // after any speaker change / media stop still queued there.
                        CallAudioThread.run("route clear", {
                            if (android.os.Build.VERSION.SDK_INT >= 31) audioManager.clearCommunicationDevice()
                            @Suppress("DEPRECATION") audioManager.isSpeakerphoneOn = false
                            audioManager.mode = android.media.AudioManager.MODE_NORMAL
                        }) { _ -> result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("CALL_AUDIO_ERROR", e.message, null) }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callMediaChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val callId = call.argument<String>("call_id")?.trim().orEmpty()
                        val peerId = call.argument<String>("peer_id")?.trim().orEmpty()
                        val codec = call.argument<String>("codec")?.trim()?.lowercase().orEmpty()
                        if (callId.isEmpty() || peerId.isEmpty()) {
                            result.error("INVALID_CALL_MEDIA", "call_id and peer_id are required", null)
                            return@setMethodCallHandler
                        }
                        // Call media was the ONLY audio path that never checked the mic:
                        // on a fresh install (or after an app-data wipe) AudioRecord threw
                        // a bare SecurityException here and the accept died as a generic
                        // "Call failed". Ask with rationale like the other media permissions;
                        // the user grants it once and the next Answer connects normally.
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            requestWithRationale(arrayOf(Manifest.permission.RECORD_AUDIO), 7812, "Microphone access", "LinkUp needs the microphone so the other person can hear you on calls. Allow it, then answer the call again.")
                            result.error("PERMISSION", "Call audio: microphone permission needed. Allow it on the prompt, then answer the call again.", null)
                            return@setMethodCallHandler
                        }
                        // Bundle 159: per-call voice key (memory only, never logged).
                        val voiceKey = call.argument<String>("voice_key")
                        // Bundle 186 (C2): mic + speaker start on the call audio
                        // thread (was ~0.5 s on the main thread = frozen screen).
                        CallAudioThread.run("media_start", { LocalLinkTransportService.startCallMedia(callId, peerId, codec, voiceKey) }) { error ->
                            if (error == null) result.success(null)
                            else result.error("CALL_MEDIA_ERROR", error.message ?: error.javaClass.simpleName, null)
                        }
                    }
                    "stop" -> {
                        val stopId = call.argument<String>("call_id")?.trim().orEmpty()
                        // Bundle 186 (C2): same thread, so a stop never overtakes its start.
                        CallAudioThread.run("media_stop", { LocalLinkTransportService.stopCallMedia(stopId) }) { _ -> result.success(null) }
                    }
                    "mute" -> {
                        LocalLinkTransportService.setCallMediaMuted(call.argument<String>("call_id")?.trim().orEmpty(), call.argument<Boolean>("muted") == true)
                        result.success(null)
                    }
                    "stats" -> result.success(LocalLinkTransportService.callMediaStats(call.argument<String>("call_id")?.trim().orEmpty()))
                    // Bundle 149: offer opus2 only when this phone passed the Opus
                    // self-test (tone comes back loud and at the right pitch).
                    // The test runs once, off the main thread; PCM is always offered.
                    "supported_codecs" -> Thread {
                        val codecs = if (CallOpusCodec.usable()) listOf(CallOpus2Format.CODEC, CallOpus2Format.PCM) else listOf(CallOpus2Format.PCM)
                        runOnUiThread { try { result.success(codecs) } catch (_: Throwable) {} }
                    }.apply { name = "locallink-opus-selftest"; isDaemon = true }.start()
                    "video_start" -> {
                        val callId = call.argument<String>("call_id")?.trim().orEmpty()
                        val peerId = call.argument<String>("peer_id")?.trim().orEmpty()
                        if (callId.isEmpty() || peerId.isEmpty()) {
                            result.error("INVALID_CALL_VIDEO", "call_id and peer_id are required", null)
                            return@setMethodCallHandler
                        }
                        // Camera is never requested anywhere else in the app, so a
                        // freshly installed phone used to die here with a bare
                        // permission failure. Ask at tap time (same pattern as the
                        // voice-note mic request at 7812); the error text carries
                        // the next step because the dialog is not blocking.
                        if (call.argument<Boolean>("enable_camera") != false &&
                            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                            requestWithRationale(arrayOf(Manifest.permission.CAMERA), 7813, "Camera access", "LinkUp needs the camera so the other person can see you on video calls. Allow it, then tap video again.")
                            result.error("CALL_MEDIA_ERROR", "Call video: camera permission needed. Allow it on the prompt, then tap video again.", null)
                            return@setMethodCallHandler
                        }
                        ensureCallVideoTextures()
                        LocalLinkTransportService.startCallVideo(callId, peerId, call.argument<Boolean>("enable_camera") != false)
                        result.success(mapOf(
                            "local_texture_id" to localVideoTextureEntry!!.id(),
                            "remote_texture_id" to remoteVideoTextureEntry!!.id(),
                            "rotation" to LocalLinkTransportService.callVideoRotation(callId),
                        ))
                    }
                    "video_stop" -> {
                        LocalLinkTransportService.stopCallVideo(call.argument<String>("call_id")?.trim().orEmpty())
                        releaseCallVideoTextures()
                        result.success(null)
                    }
                    "video_enabled" -> {
                        val videoEnabledArg = call.argument<Boolean>("enabled") != false
                        if (videoEnabledArg && checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                            requestWithRationale(arrayOf(Manifest.permission.CAMERA), 7813, "Camera access", "LinkUp needs the camera so the other person can see you on video calls. Allow it, then tap video again.")
                            result.error("CALL_MEDIA_ERROR", "Call video: camera permission needed. Allow it on the prompt, then tap video again.", null)
                            return@setMethodCallHandler
                        }
                        LocalLinkTransportService.setCallVideoEnabled(call.argument<String>("call_id")?.trim().orEmpty(), videoEnabledArg)
                        result.success(null)
                    }
                    "video_switch_camera" -> {
                        LocalLinkTransportService.switchCallCamera(call.argument<String>("call_id")?.trim().orEmpty())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("CALL_MEDIA_ERROR", e.message, null) }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceNotesChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "record_start" -> startVoiceRecording(result)
                    "amplitude" -> result.success(voiceRecorder?.let { r -> try { r.maxAmplitude } catch (_: Exception) { 0 } } ?: 0)
                    "record_stop" -> stopVoiceRecording(result)
                    "record_cancel" -> { cancelVoiceRecording(); result.success(null) }
                    // Bundle 181: pause / continue = parts, joined into one file.
                    "join" -> joinVoiceParts(call.argument<List<*>>("paths"), call.argument<Boolean>("delete_parts") != false, result)
                    "play" -> playVoiceNote(call.argument<String>("path"), result)
                    "pause" -> { voicePlayer?.pause(); result.success(null) }
                    "stop" -> { voicePlayer?.stop(); voicePlayer?.release(); voicePlayer = null; result.success(null) }
                    // Bundle 145: chat video thumbnail + length + display size.
                    "video_info" -> readVideoInfo(call.argument<String>("path"), call.argument<Int>("max_px") ?: 480, result)
                    // Bundle 197b: media storage (small pictures, storage, Gallery links, Save to phone).
                    "make_thumb" -> mediaBg(result) { MediaStorageNative.makeThumb(this, call.argument<String>("in") ?: "", call.argument<String>("out") ?: "", call.argument<Boolean>("video") == true, call.argument<Int>("max_px") ?: MediaStoragePolicy.THUMB_PX) }
                    "storage_stats" -> mediaBg(result) { MediaStorageNative.storageStats() }
                    "uri_alive" -> mediaBg(result) { MediaStorageNative.uriAlive(this, call.argument<String>("uri") ?: "") }
                    "release_uris" -> mediaBg(result) { MediaStorageNative.releaseLinks(this, call.argument<List<*>>("uris")?.mapNotNull { it?.toString() } ?: emptyList()) }
                    "link_count" -> mediaBg(result) { MediaStorageNative.linkCount(this) }
                    "restore_from_uri" -> mediaBg(result) { MediaStorageNative.restoreFromUri(this, call.argument<String>("uri") ?: "", call.argument<String>("out") ?: "") }
                    "save_to_phone" -> mediaBg(result) { MediaStorageNative.saveToPhone(this, call.argument<String>("path") ?: "", call.argument<String>("name") ?: "", call.argument<String>("mime") ?: "application/octet-stream") }
                    "saved_alive" -> mediaBg(result) { MediaStorageNative.savedAlive(this, call.argument<String>("uri") ?: "") }
                    "open_uri" -> mediaBg(result) { MediaStorageNative.openUri(this, call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: "") }
                    "sdk_int" -> result.success(Build.VERSION.SDK_INT)
                    // Bundle 198: short in-app sounds (false = could not play).
                    "tone" -> result.success(UiSounds.play(this, call.argument<String>("name") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("VOICE_NOTE_ERROR", e.message, null) }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> {
                    if (pendingResult != null) { result.error("PICKER_BUSY", "A file picker is already open", null); return@setMethodCallHandler }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mimeType") ?: "*/*"
                        if (call.argument<Boolean>("allowMultiple") == true) putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    startActivityForResult(intent, requestCode)
                }
                else -> result.notImplemented()
            }
        }

        // Bundle G6: group invite links (linkup://join/<token>).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/join_link").setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    val link = pendingJoinLink
                    pendingJoinLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }

        dispatchCallNotificationIntent(intent, "activity")
        dispatchNotificationIntent(intent)
        captureJoinLink(intent)
    }

    /** Bundle G6: keep a tapped linkup://join/<token> link until Dart takes it. */
    private fun captureJoinLink(intent: Intent?) {
        val safe = intent ?: return
        if (safe.action != Intent.ACTION_VIEW) return
        val data = safe.data ?: return
        if (data.scheme != "linkup" || data.host != "join") return
        if ((safe.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        if (safe.getBooleanExtra(EXTRA_JOIN_LINK_CONSUMED, false)) return
        safe.putExtra(EXTRA_JOIN_LINK_CONSUMED, true)
        pendingJoinLink = data.toString().take(200)
        android.util.Log.i(AppHealthPolicy.TAG, "GROUP_LINK_INTENT")
    }

    private fun ensureCallVideoTextures() {
        if (localVideoTextureEntry == null) localVideoTextureEntry = flutterEngine?.renderer?.createSurfaceTexture()
        if (remoteVideoTextureEntry == null) remoteVideoTextureEntry = flutterEngine?.renderer?.createSurfaceTexture()
        val local = localVideoTextureEntry ?: throw IllegalStateException("Unable to allocate local video texture")
        val remote = remoteVideoTextureEntry ?: throw IllegalStateException("Unable to allocate remote video texture")
        local.surfaceTexture().setDefaultBufferSize(640, 360)
        remote.surfaceTexture().setDefaultBufferSize(640, 360)
        localVideoSurface?.release()
        remoteVideoSurface?.release()
        localVideoSurface = Surface(local.surfaceTexture())
        remoteVideoSurface = Surface(remote.surfaceTexture())
        LocalLinkTransportService.configureCallVideoSurfaces(localVideoSurface!!, remoteVideoSurface!!)
    }

    private fun releaseCallVideoTextures() {
        LocalLinkTransportService.clearCallVideoSurfaces()
        localVideoSurface?.release()
        remoteVideoSurface?.release()
        localVideoSurface = null
        remoteVideoSurface = null
        localVideoTextureEntry?.release()
        remoteVideoTextureEntry?.release()
        localVideoTextureEntry = null
        remoteVideoTextureEntry = null
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            // Bundle 181: voice-note wording (it talked about calls before).
            requestWithRationale(arrayOf(Manifest.permission.RECORD_AUDIO), 7812, "Microphone access", "LinkUp needs the microphone to record voice notes. Allow it, then hold the mic again.")
            result.error("PERMISSION", "Microphone permission is required", null)
            return
        }
        if (voiceRecorder != null) { result.error("RECORDING_ACTIVE", "A voice note is already recording", null); return }
        val file = File(cacheDir, "voice_${UUID.randomUUID()}.m4a")
        // Bundle 181: MediaRecorder(Context) exists only on Android 12+; the
        // old constructor keeps voice notes working on Android 7-11.
        val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()
        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setAudioSamplingRate(44100)
        recorder.setAudioEncodingBitRate(96000)
        recorder.setOutputFile(file.absolutePath)
        recorder.prepare()
        recorder.start()
        voiceRecorder = recorder
        voiceRecordingPath = file.absolutePath
        result.success(mapOf("path" to file.absolutePath, "name" to file.name, "size" to 0))
    }

    private fun stopVoiceRecording(result: MethodChannel.Result) {
        val recorder = voiceRecorder ?: run { result.error("NO_RECORDING", "No voice note is recording", null); return }
        val path = voiceRecordingPath
        // Bundle 181: a very short part makes stop() throw - report TOO_SHORT.
        val ok = try { recorder.stop(); true } catch (_: RuntimeException) { false } finally { try { recorder.release() } catch (_: Exception) {}; voiceRecorder = null; voiceRecordingPath = null }
        val file = path?.let { File(it) } ?: throw IllegalStateException("Voice recording path is unavailable")
        if (!ok || !file.exists() || file.length() <= 0L) { file.delete(); result.error("TOO_SHORT", "Voice recording is too short", null); return }
        result.success(mapOf("path" to file.absolutePath, "name" to file.name, "size" to file.length().toInt()))
    }

    private fun joinVoiceParts(paths: List<*>?, deleteParts: Boolean, result: MethodChannel.Result) {
        val list = paths?.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } } ?: emptyList()
        if (list.isEmpty()) { result.error("NO_PARTS", "No voice note parts", null); return }
        Thread {
            val out = try { VoiceNoteJoiner.join(list, cacheDir, deleteParts) } catch (_: Exception) { null }
            runOnUiThread {
                if (out == null || !out.exists()) result.error("JOIN_FAILED", "Voice note parts could not be joined", null)
                else result.success(mapOf("path" to out.absolutePath, "name" to out.name, "size" to out.length().toInt()))
            }
        }.apply { name = "linkup-voice-join"; isDaemon = true }.start()
    }

    private fun cancelVoiceRecording() {
        val recorder = voiceRecorder
        val path = voiceRecordingPath
        try { recorder?.stop() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        voiceRecorder = null
        voiceRecordingPath = null
        if (!path.isNullOrEmpty()) File(path).delete()
    }

    private fun playVoiceNote(path: String?, result: MethodChannel.Result) {
        val target = path?.trim().orEmpty()
        if (target.isEmpty() || !File(target).exists()) { result.error("AUDIO_FILE", "Voice note is unavailable", null); return }
        voicePlayer?.stop(); voicePlayer?.release()
        val player = MediaPlayer()
        player.setDataSource(target)
        player.setOnCompletionListener { it.release(); if (voicePlayer === it) voicePlayer = null }
        player.prepare()
        player.start()
        voicePlayer = player
        result.success(player.duration)
    }

    private fun configureTransport(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("device_id")?.trim().orEmpty()
        if (id.isEmpty()) { result.error("INVALID_DEVICE", "device_id is required", null); return }
        val peers = stringList(call.argument<List<*>>("known_peers"))
        LocalLinkTransportService.configure(this, id, call.argument<Boolean>("connected") == true, call.argument<Boolean>("group_owner") == true, call.argument<String>("group_owner_address")?.trim(), peers)
        result.success(null)
    }

    private fun sendFileTransport(call: MethodCall, result: MethodChannel.Result) {
        val target=call.argument<String>("recipient_id")?.trim().orEmpty(); val path=call.argument<String>("file_path")?.trim().orEmpty(); val fileId=call.argument<String>("file_id")?.trim().orEmpty(); val messageId=call.argument<String>("message_id")?.trim().orEmpty(); val name=call.argument<String>("file_name")?.trim() ?: "attachment"; val type=call.argument<String>("content_type")?.trim() ?: "application/octet-stream"
        if(target.isEmpty()||path.isEmpty()||fileId.isEmpty()||messageId.isEmpty()){result.error("INVALID_FILE","recipient_id, file_path, file_id and message_id are required",null);return}
        LocalLinkTransportService.sendFile(target,path,fileId,messageId,name,type){ok,error->runOnUiThread{if(ok)result.success(null) else result.error("FILE_SEND_FAILED",error,null)}}
    }

    private fun stringList(values: List<*>?): List<String> = values?.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } } ?: emptyList()
    private fun mapToPayload(values: Map<*, *>?): Map<String, Any?> = buildMap { values?.forEach { (k,v) -> if(k!=null&&v!=null) put(k.toString(),v) } }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchCallNotificationIntent(intent, "activity")
        dispatchNotificationIntent(intent)
        captureJoinLink(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Bundle 101: mic (7812) / camera (7813) denials re-enter Dart's
        // 10-minute re-ask loop — no settings-recovery dialog here.
        if (requestCode == 7812 || requestCode == 7813) return
        // Bundle 177 (9.5): the screen re-reads the state on resume.
        if (requestCode == backgroundLocationRequestCode) {
            NearbyRadio.logState(this, "bg_location_answer")
            return
        }
        if (requestCode != wifiPermissionRequestCode) return

        val result = pendingWifiPermissionResult
        pendingWifiPermissionResult = null

        if (hasWifiPermission()) {
            result?.success(null)
            NearbyRadio.requestPeers()
            NearbyRadio.requestConnectionInfo()
        } else {
            result?.error(
                "PERMISSION_DENIED",
                "Nearby Wi-Fi permission is required for Wi-Fi Direct",
                null,
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != this.requestCode) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(null); return }
        try {
            val uris=mutableListOf<Uri>(); data.clipData?.let{clip->for(i in 0 until clip.itemCount)uris.add(clip.getItemAt(i).uri)}; if(uris.isEmpty()&&data.data!=null)uris.add(data.data!!)
            // Bundle 197b: keep a link to the picked file (sender's Gallery copy).
            result.success(uris.map{u->val m=copyToCache(u).toMutableMap(); if(MediaStorageNative.keepLink(this,u)) m["source_uri"]=u.toString(); m})
        } catch(e:Exception){result.error("PICK_FAILED",e.message,null)}
    }

    fun clearCallLockScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    fun setCallLockScreen(show: Boolean, turnScreenOn: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(show)
            setTurnScreenOn(turnScreenOn)
        }
    }

    private fun dispatchCallNotificationIntent(intent: Intent?, source: String = "activity") {
        val safeIntent = intent ?: return
        val action = when (safeIntent.action) {
            CallNotificationManager.ACTION_OPEN -> "open"
            CallNotificationManager.ACTION_ACCEPT -> "accept"
            CallNotificationManager.ACTION_REJECT -> "reject"
            else -> return
        }
        // Bundle 146: each call intent is handled ONCE. onCreate re-runs on a
        // recreated activity with the same intent, and the old receiver path
        // plus onNewIntent could both forward the same Accept.
        if (safeIntent.getBooleanExtra(EXTRA_CALL_ACTION_CONSUMED, false)) return
        // Reopening from Recents replays the original launch intent; an old
        // Accept must not be applied (or reported as unavailable) again.
        if ((safeIntent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        safeIntent.putExtra(EXTRA_CALL_ACTION_CONSUMED, true)
        val callId = safeIntent.getStringExtra(CallNotificationManager.EXTRA_CALL_ID)?.trim().orEmpty()
        val callerId = safeIntent.getStringExtra(CallNotificationManager.EXTRA_CALLER_ID)?.trim().orEmpty()
        android.util.Log.i("LocalLinkCall", "CALL_NOTIFICATION_ACTION action=$action source=$source call=$callId engine=${callNotificationEventSink != null}")
        // Bundle 179 (2.1): remember the Accept for 60 s. The queued event
        // below is lost if this screen is rebuilt (slow phones like ZTE);
        // the app then reads this and still answers with ONE tap.
        if (action == "accept") CallAcceptMemory.save(this, callId, callerId)
        else if (action == "reject") CallAcceptMemory.clear(this, callId)
        if (action == "open" || action == "accept") {
            // Show over the lock screen right away; Dart keeps it while the
            // call is live and releases it when the call ends.
            setCallLockScreen(true, true)
        }
        if (action == "open") return
        if (callId.isBlank() || callerId.isBlank()) return
        val event = mapOf(
            "action" to action,
            "call_id" to callId,
            "caller_id" to callerId,
        )
        val sink = callNotificationEventSink
        if (sink != null) sink.success(event) else pendingCallNotificationActions.add(event)
    }

    // Bundle 143: proximity screen-off during earpiece voice calls. The OS
    // turns the display off while the sensor is covered (phone at the ear)
    // and back on when uncovered; touches are ignored while it is off.
    private var proximityWakeLock: android.os.PowerManager.WakeLock? = null

    /** Bundle 143 + 186 (C1): call audio mode + earpiece/speaker. Runs on the call audio thread. */
    private fun applyCallRoute(audioManager: android.media.AudioManager, enabled: Boolean) {
        audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            val devices = audioManager.availableCommunicationDevices
            val speaker = devices.firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            val bt = devices.firstOrNull {
                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
            // Bundle 143: speaker OFF used to pick Bluetooth only —
            // with no headset nothing was selected and audio stayed
            // on the loudspeaker. Fall back to the earpiece.
            val earpiece = devices.firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
            val target = if (enabled) speaker else (bt ?: earpiece)
            if (target != null) audioManager.setCommunicationDevice(target)
            else if (!enabled) audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION") audioManager.isSpeakerphoneOn = enabled
        }
    }

    private fun setCallProximity(enabled: Boolean) {
        try {
            val pm = powerManager()
            if (enabled) {
                if (!pm.isWakeLockLevelSupported(android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
                val lock = proximityWakeLock ?: pm.newWakeLock(
                    android.os.PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "locallink:call_proximity",
                ).also {
                    it.setReferenceCounted(false)
                    proximityWakeLock = it
                }
                // Hard cap so a lost "call ended" can never pin the sensor forever.
                if (!lock.isHeld) lock.acquire(4 * 60 * 60 * 1000L)
            } else {
                proximityWakeLock?.let {
                    // Wait for the phone to leave the ear before lighting the screen.
                    if (it.isHeld) it.release(android.os.PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
                }
            }
        } catch (_: Exception) {
            // Sensor/wakelock quirks on some ROMs must never break a call.
        }
    }

    // Bundle 140: background keep-alive helpers (see "locallink/background").
    private fun powerManager(): android.os.PowerManager =
        getSystemService(Context.POWER_SERVICE) as android.os.PowerManager

    /** Bundle 163 (5.6): the brand's own page, else the app's info page. */
    private fun openBrandBackgroundSettings(brand: String): String {
        for ((pkg, cls) in VendorBackgroundIntents.candidates(brand)) {
            try {
                startActivity(Intent().setComponent(ComponentName(pkg, cls)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                android.util.Log.i("LocalLinkBackground", "BRAND_SETTINGS_OPENED brand=$brand page=$cls")
                return "vendor"
            } catch (_: Exception) {}
        }
        // Bundle 185 (B2): the brand's power manager app (ZTE MyOS).
        for (pkg in VendorBackgroundIntents.launchPackages(brand)) {
            try {
                val launch = packageManager.getLaunchIntentForPackage(pkg) ?: continue
                startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                android.util.Log.i("LocalLinkBackground", "BRAND_SETTINGS_OPENED brand=$brand page=$pkg")
                return "vendor"
            } catch (_: Exception) {}
        }
        return try {
            startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            android.util.Log.i("LocalLinkBackground", "BRAND_SETTINGS_OPENED brand=$brand page=app_info")
            "app_settings"
        } catch (_: Exception) {
            "none"
        }
    }

    private fun openVendorBackgroundSettings(): String {
        val candidates = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.appautostart.AutoStartActivity"),
            ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.FunctionActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        )
        for (c in candidates) {
            try {
                startActivity(Intent().setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return "vendor"
            } catch (_: Exception) {}
        }
        try {
            startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return "battery"
        } catch (_: Exception) {}
        startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return "app_settings"
    }

    private fun dispatchNotificationIntent(intent: Intent?) {
        val safeIntent = intent ?: return

        // Bundle 146: call actions (open/accept/reject) are handled only by
        // dispatchCallNotificationIntent, so an Accept reaches Dart once.
        if (safeIntent.action == CallNotificationManager.ACTION_ACCEPT ||
            safeIntent.action == CallNotificationManager.ACTION_REJECT ||
            safeIntent.action == CallNotificationManager.ACTION_OPEN) return

        val action = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_ACTION)?.trim().orEmpty()
        val nativeAction = when (safeIntent.action) {
            LocalLinkNotificationManager.ACTION_OPEN -> "open"
            LocalLinkNotificationManager.ACTION_REPLY -> "reply"
            LocalLinkNotificationManager.ACTION_MARK_READ -> "mark_read"
            else -> ""
        }
        if (action.isBlank() || action != nativeAction) return
        // Bundle 151: handle each tap once (a recreated activity replays its
        // intent; reopening from Recents replays the old launch intent).
        if (safeIntent.getBooleanExtra(EXTRA_MESSAGE_ACTION_CONSUMED, false)) return
        if ((safeIntent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        safeIntent.putExtra(EXTRA_MESSAGE_ACTION_CONSUMED, true)
        val conversationType = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_TYPE)?.trim().orEmpty()
        val conversationId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_ID)?.trim().orEmpty()
        val messageId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_MESSAGE_ID)?.trim().orEmpty()
        val senderId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_SENDER_ID)?.trim().orEmpty()
        val recipientId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_RECIPIENT_ID)?.trim().orEmpty()
        val notificationId = safeIntent.getIntExtra(LocalLinkNotificationManager.EXTRA_NOTIFICATION_ID, 0)
        if (conversationType !in setOf("direct", "group") || conversationId.isBlank() || notificationId <= 0) return
        // Bundle 151: a bundle tap ("open") has no message id - open the chat
        // only. Reply / Mark-read always need the exact message.
        if (action != "open" && (messageId.isBlank() || senderId.isBlank() || recipientId.isBlank())) return
        android.util.Log.i("LocalLinkNotify", "NOTIFICATION_TAP action=$action type=$conversationType summary=${messageId.isBlank()} engine=${notificationEventSink != null}")
        val event = mutableMapOf<String, Any?>(
            "action" to action,
            "notification_id" to notificationId,
            "conversation_type" to conversationType,
            "conversation_id" to conversationId,
            "message_id" to messageId,
            "sender_id" to senderId,
            "recipient_id" to recipientId,
        )
        safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_ATTACHMENT_ID)?.takeIf { it.isNotBlank() }?.let { event["attachment_id"] = it }
        safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_REPLY_TEXT)?.takeIf { it.isNotBlank() }?.let { event["reply_text"] = it }
        val sink = notificationEventSink
        if (sink != null) sink.success(event) else pendingNotificationActions.add(event)
    }

    private fun requestWifiPermission(result: MethodChannel.Result) {
        if (hasWifiPermission()) {
            result.success(null)
            NearbyRadio.requestPeers()
            NearbyRadio.requestConnectionInfo()
            return
        }

        if (pendingWifiPermissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "A Wi-Fi permission request is already in progress", null)
            return
        }

        val permissions = if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else if (Build.VERSION.SDK_INT >= 23) {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            emptyArray()
        }

        if (permissions.isEmpty()) {
            result.success(null)
            return
        }

        pendingWifiPermissionResult = result
        requestWithRationale(permissions, wifiPermissionRequestCode, "Nearby device access", "LinkUp uses Wi-Fi Direct to call and chat with nearby phones without internet. Allow nearby-device access to continue.")
    }
    /** Bundle 101: direct native-dialog runtime permission flow; denials are
     * settled by the Dart-side sequencer's 10-minute re-ask loop. */


    // Bundle 101 sequencer helpers ==========================================
    private fun gateIsGranted(name: String): Boolean = when (name) {
        "microphone" -> checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        "nearby" -> hasWifiPermission()
        "notifications" -> LocalLinkNotificationManager.notificationsEnabled(this)
        // Bundle 121: battery-optimization exemption ("always run in background").
        "background" -> isBatteryUnrestricted()
        else -> false
    }

    private fun gateRequest(name: String) {
        when (name) {
            "microphone" -> requestWithRationale(arrayOf(Manifest.permission.RECORD_AUDIO), 7812, "", "")
            "nearby" -> if (!hasWifiPermission()) requestWithRationale(if (android.os.Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), wifiPermissionRequestCode, "", "")
            "notifications" -> LocalLinkNotificationManager.requestNotificationPermission(this)
            // Bundle 121: the Dart sequencer owns re-ask pacing, so this entry
            // point deliberately skips the once-per-install shared-pref flag
            // that the onCreate prompt uses.
            "background" -> requestBatteryOptimizationExemption()
        }
    }

    // Bundle 121: gate-facing battery helpers. Bundle 124 removed the old
    // once-per-install onCreate prompt entirely — this sequencer entry is now
    // the single, recoverable ask for the exemption.
    private fun isBatteryUnrestricted():Boolean{if(android.os.Build.VERSION.SDK_INT<23)return true;val pm=getSystemService(Context.POWER_SERVICE) as android.os.PowerManager;return pm.isIgnoringBatteryOptimizations(packageName)}
    private fun requestBatteryOptimizationExemption(){if(isBatteryUnrestricted())return;try{startActivity(Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,android.net.Uri.parse("package:$packageName")))}catch(_:Exception){try{startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))}catch(_:Exception){}}}

    // Bundle 101: no pre-info/rationale dialogs anywhere — fire the one
    // native system dialog directly (signature kept; call sites untouched).
    @Suppress("UNUSED_PARAMETER")
    private fun requestWithRationale(permissions: Array<String>, requestCode: Int, title: String, rationale: String) {
        requestPermissions(permissions, requestCode)
    }

    // Bundle 177 (2): Nearby (Wi-Fi Direct) moved to NearbyRadio (one owner for the app).
    private fun hasWifiPermission():Boolean=NearbyRadio.hasPermission(this)

    private fun copyToCache(uri: Uri): Map<String,Any>{
        val resolver=contentResolver; val name=queryName(uri)?:"attachment"; val mime=resolver.getType(uri)?:"application/octet-stream"; val safeName=name.replace(Regex("[^A-Za-z0-9._-]"),"_"); val pickDir=File(filesDir,"locallink_picks").apply{mkdirs()}; val outFile=File(pickDir,"locallink_${UUID.randomUUID()}_$safeName"); resolver.openInputStream(uri).use{input->requireNotNull(input){"Could not open selected file"};FileOutputStream(outFile).use{output->input.copyTo(output)}}; return mapOf("path" to outFile.absolutePath,"name" to name,"content_type" to mime,"size" to outFile.length())
    }
    private fun queryName(uri:Uri):String?{var cursor:Cursor?=null;return try{cursor=contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null);if(cursor!=null&&cursor.moveToFirst())cursor.getString(0)else uri.lastPathSegment}finally{cursor?.close()}}

    // Bundle 185 (A2): the screen went behind another app (Home, Share, a call app).
    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) AppHealth.logKeepAlive(this, "background")
    }

    // Bundle 185 (B1): Android asks for memory. Flutter drops its picture
    // cache by itself; the app side drops its own caches (memory_trim.dart).
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        AppHealth.onTrim(level)
    }

    // Bundle 147: Home pressed while a chat video plays (Android 8-11).
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        chatVideoPip.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        chatVideoPip.onModeChanged(isInPictureInPictureMode, lifecycle)
    }

    override fun onDestroy(){
        chatVideoPip.dispose() // Bundle 147
        // Bundle 177 (1, 2.7): Nearby keeps running when the screen closes
        // (only Log out stops it); log what survives.
        NearbyRadio.logState(this, if (isChangingConfigurations) "rotate" else "close")
        NearbyRadio.detach(wifiEventSink)
        wifiEventSink = null
        setCallProximity(false) // Bundle 143
        if (activeInstance === this) activeInstance = null
        callNotificationEventSink = null
        pendingCallNotificationActions.clear()
        notificationEventSink = null
        pendingNotificationActions.clear()
        releaseCallVideoTextures()
        try { voiceRecorder?.stop() } catch (_: Exception) {}
        try { voiceRecorder?.release() } catch (_: Exception) {}
        voiceRecorder = null
        voiceRecordingPath?.let { File(it).delete() }
        voiceRecordingPath = null
        try { voicePlayer?.stop() } catch (_: Exception) {}
        try { voicePlayer?.release() } catch (_: Exception) {}
        voicePlayer = null
        LocalLinkTransportService.setEventListener(null)
        transportEventSink=null
        pendingWifiPermissionResult = null
        val keepsRunning = !isChangingConfigurations
        super.onDestroy()
        // Bundle 175 (3): the screen is gone (Back exit / swipe) and its
        // engine with it. The no-screen engine takes over so messages and
        // notifications keep working. Short delay: the old engine finishes first.
        if (keepsRunning) BackgroundEngine.startNoScreen(applicationContext, if (isFinishing) "app_closed" else "screen_destroyed", 800L)
    }
}
