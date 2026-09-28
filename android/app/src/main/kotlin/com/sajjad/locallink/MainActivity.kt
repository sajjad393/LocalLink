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
        @Volatile private var activeInstance: MainActivity? = null

        fun dispatchNotificationAction(intent: Intent): Boolean {
            val activity = activeInstance ?: return false
            activity.runOnUiThread { activity.dispatchNotificationIntent(intent) }
            return true
        }
    }

    private val channelName = "locallink/files"
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
    private var pendingResult: MethodChannel.Result? = null
    private lateinit var wifiManager: WifiP2pManager
    private lateinit var wifiChannel: WifiP2pManager.Channel
    private var wifiP2pEnabled = false
    private var wifiEventSink: EventChannel.EventSink? = null
    private var transportEventSink: EventChannel.EventSink? = null
    private var localVideoTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null
    private var remoteVideoTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null
    private var localVideoSurface: Surface? = null
    private var remoteVideoSurface: Surface? = null
    private var peerDevices: List<WifiP2pDevice> = emptyList()
    private var wifiReceiverRegistered = false
    private var callNotificationEventSink: EventChannel.EventSink? = null
    private val pendingCallNotificationActions = mutableListOf<Map<String, Any>>()
    private var notificationEventSink: EventChannel.EventSink? = null
    private val pendingNotificationActions = mutableListOf<Map<String, Any?>>()

    private val wifiReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    wifiP2pEnabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    wifiEventSink?.success(mapOf("type" to "state", "enabled" to wifiP2pEnabled))
                    if (!wifiP2pEnabled) {
                        // Wi-Fi Direct is an optional transport. Disabling it must not
                        // tear down the LAN mesh or the background transport service.
                        LocalLinkTransportService.updateConnection(context, false, false, null)
                    } else {
                        requestConnectionInfo()
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> requestPeers()
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> requestConnectionInfo()
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> wifiEventSink?.success(mapOf("type" to "device_changed"))
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiManager = getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
        wifiChannel = wifiManager.initialize(this, mainLooper, null)
        registerWifiReceiver()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, wifiChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(packageManager.hasSystemFeature("android.hardware.wifi.direct"))
                "isEnabled" -> {
                    if (!hasWifiPermission()) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return@setMethodCallHandler }
                    result.success(wifiP2pEnabled)
                }
                "requestEnable" -> { requestWifiPermission(); result.success(null) }
                "discoverPeers" -> discoverPeers(result)
                "getPeers" -> result.success(peerDevices.map { peerMap(it) })
                "connect" -> connectPeer(call.argument<String>("address"), result)
                "cancelConnect" -> wifiManager.cancelConnect(wifiChannel, actionResult(result))
                "disconnect" -> wifiManager.removeGroup(wifiChannel, actionResult(result))
                "connectionInfo" -> connectionInfo(result)
                "dispose" -> { unregisterWifiReceiver(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, wifiEventsName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { wifiEventSink = events; requestPeers(); requestConnectionInfo() }
            override fun onCancel(arguments: Any?) { wifiEventSink = null }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, transportChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> configureTransport(call, result)
                    "updatePeerKeys" -> { LocalLinkTransportService.updatePeerKeys(this, mapOfStrings(call.argument<Map<*, *>>("peer_keys"))); result.success(null) }
                    "send" -> {
                        val ok = LocalLinkTransportService.send(call.argument<String>("recipient_id")?.trim().orEmpty(), mapToPayload(call.argument<Map<*, *>>("payload")))
                        if (ok) result.success(null) else result.error("PEER_UNAVAILABLE", "peer is not connected", null)
                    }
                    "broadcast" -> {
                        val ok = LocalLinkTransportService.broadcast(mapToPayload(call.argument<Map<*, *>>("payload")))
                        if (ok) result.success(null) else result.error("BROADCAST_FAILED", "no direct peer is connected", null)
                    }
                    "sendFile" -> sendFileTransport(call, result)
                    "cancelFile" -> { LocalLinkTransportService.cancelFile(call.argument<String>("file_id")?.trim().orEmpty()); result.success(null) }
                    "topology" -> result.success(LocalLinkTransportService.topology())
                    "flushQueue" -> { LocalLinkTransportService.flushQueue(); result.success(null) }
                    "resume" -> { requestConnectionInfo(); result.success(null) }
                    "clearStorage" -> { LocalLinkTransportService.clearStorage(); result.success(null) }
                    "stop" -> { LocalLinkTransportService.stop(this); result.success(null) }
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
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("RINGTONE_ERROR", e.message, null)
            }
        }

        CallNotificationManager.initialize(this)
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
            }
            override fun onCancel(arguments: Any?) { notificationEventSink = null }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locallink/call_audio").setMethodCallHandler { call, result ->
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                when (call.method) {
                    "setSpeakerphoneOn" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        audioManager.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                        if (android.os.Build.VERSION.SDK_INT >= 31) {
                            val devices = audioManager.availableCommunicationDevices
                            val speaker = devices.firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                            val bt = devices.firstOrNull {
                                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                    it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                            }
                            val target = if (enabled) speaker else bt
                            if (target != null) audioManager.setCommunicationDevice(target)
                        } else {
                            @Suppress("DEPRECATION") audioManager.isSpeakerphoneOn = enabled
                        }
                        result.success(null)
                    }
                    "clearCommunicationDevice" -> {
                        if (android.os.Build.VERSION.SDK_INT >= 31) audioManager.clearCommunicationDevice()
                        @Suppress("DEPRECATION") audioManager.isSpeakerphoneOn = false
                        audioManager.mode = android.media.AudioManager.MODE_NORMAL
                        result.success(null)
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
                        val mediaKey = call.argument<String>("media_key")?.trim().orEmpty()
                        val codec = call.argument<String>("codec")?.trim()?.lowercase().orEmpty()
                        if (callId.isEmpty() || peerId.isEmpty() || mediaKey.isEmpty()) {
                            result.error("INVALID_CALL_MEDIA", "call_id, peer_id and media_key are required", null)
                            return@setMethodCallHandler
                        }
                        LocalLinkTransportService.startCallMedia(callId, peerId, mediaKey, codec)
                        result.success(null)
                    }
                    "stop" -> {
                        LocalLinkTransportService.stopCallMedia(call.argument<String>("call_id")?.trim().orEmpty())
                        result.success(null)
                    }
                    "mute" -> {
                        LocalLinkTransportService.setCallMediaMuted(call.argument<String>("call_id")?.trim().orEmpty(), call.argument<Boolean>("muted") == true)
                        result.success(null)
                    }
                    "stats" -> result.success(LocalLinkTransportService.callMediaStats(call.argument<String>("call_id")?.trim().orEmpty()))
                    "supported_codecs" -> result.success(listOf("pcm_s16le") + if (CallOpusCodec.isSupported(16_000, 1)) listOf("opus") else emptyList())
                    "video_start" -> {
                        val callId = call.argument<String>("call_id")?.trim().orEmpty()
                        val peerId = call.argument<String>("peer_id")?.trim().orEmpty()
                        val mediaKey = call.argument<String>("media_key")?.trim().orEmpty()
                        if (callId.isEmpty() || peerId.isEmpty() || mediaKey.isEmpty()) {
                            result.error("INVALID_CALL_VIDEO", "call_id, peer_id and media_key are required", null)
                            return@setMethodCallHandler
                        }
                        ensureCallVideoTextures()
                        LocalLinkTransportService.startCallVideo(callId, peerId, mediaKey)
                        result.success(mapOf(
                            "local_texture_id" to localVideoTextureEntry!!.id(),
                            "remote_texture_id" to remoteVideoTextureEntry!!.id(),
                        ))
                    }
                    "video_stop" -> {
                        LocalLinkTransportService.stopCallVideo(call.argument<String>("call_id")?.trim().orEmpty())
                        releaseCallVideoTextures()
                        result.success(null)
                    }
                    "video_enabled" -> {
                        LocalLinkTransportService.setCallVideoEnabled(call.argument<String>("call_id")?.trim().orEmpty(), call.argument<Boolean>("enabled") != false)
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

        dispatchCallNotificationIntent(intent)
        dispatchNotificationIntent(intent)
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

    private fun configureTransport(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("device_id")?.trim().orEmpty()
        if (id.isEmpty()) { result.error("INVALID_DEVICE", "device_id is required", null); return }
        val keys = mapOfStrings(call.argument<Map<*, *>>("peer_keys"))
        LocalLinkTransportService.configure(this, id, call.argument<Boolean>("connected") == true, call.argument<Boolean>("group_owner") == true, call.argument<String>("group_owner_address")?.trim(), keys)
        result.success(null)
    }

    private fun sendFileTransport(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        val target=call.argument<String>("recipient_id")?.trim().orEmpty(); val path=call.argument<String>("file_path")?.trim().orEmpty(); val fileId=call.argument<String>("file_id")?.trim().orEmpty(); val messageId=call.argument<String>("message_id")?.trim().orEmpty(); val name=call.argument<String>("file_name")?.trim() ?: "attachment"; val type=call.argument<String>("content_type")?.trim() ?: "application/octet-stream"
        if(target.isEmpty()||path.isEmpty()||fileId.isEmpty()||messageId.isEmpty()){result.error("INVALID_FILE","recipient_id, file_path, file_id and message_id are required",null);return}
        LocalLinkTransportService.sendFile(target,path,fileId,messageId,name,type){ok,error->runOnUiThread{if(ok)result.success(null) else result.error("FILE_SEND_FAILED",error,null)}}
    }

    private fun mapOfStrings(values: Map<*, *>?): Map<String, String> = buildMap { values?.forEach { (k,v) -> val key=k?.toString()?.trim(); val value=v?.toString()?.trim(); if(!key.isNullOrEmpty()&&!value.isNullOrEmpty()) put(key,value) } }
    private fun mapToPayload(values: Map<*, *>?): Map<String, Any?> = buildMap { values?.forEach { (k,v) -> if(k!=null&&v!=null) put(k.toString(),v) } }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchCallNotificationIntent(intent)
        dispatchNotificationIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != this.requestCode) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(null); return }
        try {
            val uris=mutableListOf<Uri>(); data.clipData?.let{clip->for(i in 0 until clip.itemCount)uris.add(clip.getItemAt(i).uri)}; if(uris.isEmpty()&&data.data!=null)uris.add(data.data!!)
            result.success(uris.map{copyToCache(it)})
        } catch(e:Exception){result.error("PICK_FAILED",e.message,null)}
    }

    fun clearCallLockScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    private fun dispatchCallNotificationIntent(intent: Intent?) {
        val safeIntent = intent ?: return
        val action = when (safeIntent.action) {
            CallNotificationManager.ACTION_OPEN -> "open"
            CallNotificationManager.ACTION_ACCEPT -> "accept"
            CallNotificationManager.ACTION_REJECT -> "reject"
            else -> safeIntent.getStringExtra(CallNotificationManager.EXTRA_ACTION)?.trim().orEmpty()
        }
        if (action.isBlank()) return
        if (Build.VERSION.SDK_INT >= 27 && action == "open") {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            return
        }
        if (action != "accept" && action != "reject") return
        val callId = safeIntent.getStringExtra(CallNotificationManager.EXTRA_CALL_ID)?.trim().orEmpty()
        val callerId = safeIntent.getStringExtra(CallNotificationManager.EXTRA_CALLER_ID)?.trim().orEmpty()
        if (callId.isBlank() || callerId.isBlank()) return
        val event = mapOf(
            "action" to action,
            "call_id" to callId,
            "caller_id" to callerId,
        )
        val sink = callNotificationEventSink
        if (sink != null) sink.success(event) else pendingCallNotificationActions.add(event)
    }

    private fun dispatchNotificationIntent(intent: Intent?) {
        val safeIntent = intent ?: return
        val action = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_ACTION)?.trim().orEmpty()
        val nativeAction = when (safeIntent.action) {
            LocalLinkNotificationManager.ACTION_OPEN -> "open"
            LocalLinkNotificationManager.ACTION_REPLY -> "reply"
            LocalLinkNotificationManager.ACTION_MARK_READ -> "mark_read"
            else -> ""
        }
        if (action.isBlank() || action != nativeAction) return
        val conversationType = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_TYPE)?.trim().orEmpty()
        val conversationId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_CONVERSATION_ID)?.trim().orEmpty()
        val messageId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_MESSAGE_ID)?.trim().orEmpty()
        val senderId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_SENDER_ID)?.trim().orEmpty()
        val recipientId = safeIntent.getStringExtra(LocalLinkNotificationManager.EXTRA_RECIPIENT_ID)?.trim().orEmpty()
        val notificationId = safeIntent.getIntExtra(LocalLinkNotificationManager.EXTRA_NOTIFICATION_ID, 0)
        if (conversationType !in setOf("direct", "group") || conversationId.isBlank() || messageId.isBlank() || senderId.isBlank() || recipientId.isBlank() || notificationId <= 0) return
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

    private fun requestWifiPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            val permissions=buildList{if(!hasWifiPermission())add(Manifest.permission.NEARBY_WIFI_DEVICES)}
            if(permissions.isNotEmpty())requestPermissions(permissions.toTypedArray(),7742)
        } else if(android.os.Build.VERSION.SDK_INT>=23&&!hasWifiPermission())requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),7742)
    }
    private fun hasWifiPermission():Boolean=if(android.os.Build.VERSION.SDK_INT>=33)checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)==PackageManager.PERMISSION_GRANTED else checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED
    private fun registerWifiReceiver(){if(wifiReceiverRegistered)return;val filter=IntentFilter().apply{addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION);addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION);addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION);addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)};if(Build.VERSION.SDK_INT>=33)registerReceiver(wifiReceiver,filter,Context.RECEIVER_NOT_EXPORTED)else registerReceiver(wifiReceiver,filter);wifiReceiverRegistered=true}
    private fun unregisterWifiReceiver(){if(!wifiReceiverRegistered)return;try{unregisterReceiver(wifiReceiver)}catch(_:Exception){};wifiReceiverRegistered=false}
    private fun actionResult(result: MethodChannel.Result)=object:WifiP2pManager.ActionListener{override fun onSuccess(){result.success(null)}override fun onFailure(reason:Int){result.error("WIFI_DIRECT","Wi-Fi Direct operation failed: $reason",null)}}
    private fun requestPeers(){if(!hasWifiPermission())return;wifiManager.requestPeers(wifiChannel){list:WifiP2pDeviceList->peerDevices=list.deviceList.toList();wifiEventSink?.success(mapOf("type" to "peers","peers" to peerDevices.map{peerMap(it)}))}}
    private fun requestConnectionInfo(){if(!hasWifiPermission())return;wifiManager.requestConnectionInfo(wifiChannel){info:WifiP2pInfo->val connected=info.groupFormed;val address=if(connected)info.groupOwnerAddress?.hostAddress else null;wifiEventSink?.success(mapOf("type" to "connection","connection" to mapOf("connected" to connected,"groupOwner" to info.isGroupOwner,"groupOwnerAddress" to address)));LocalLinkTransportService.resume(this,connected,info.isGroupOwner,address)}}
    private fun peerMap(device:WifiP2pDevice)=mapOf("name" to device.deviceName,"address" to device.deviceAddress,"status" to device.status)
    private fun discoverPeers(result:MethodChannel.Result){if(!hasWifiPermission()){result.error("PERMISSION","Nearby Wi-Fi permission is required",null);return};wifiManager.discoverPeers(wifiChannel,actionResult(result))}
    private fun connectPeer(address:String?,result:MethodChannel.Result){
        if(!hasWifiPermission()){result.error("PERMISSION","Nearby Wi-Fi permission is required",null);return}
        val normalized=address?.trim().orEmpty()
        if(!Regex("(?i)^[0-9a-f]{2}(:[0-9a-f]{2}){5}$").matches(normalized)){result.error("INVALID_ADDRESS","A valid Wi-Fi Direct device address is required",null);return}
        wifiManager.connect(wifiChannel,WifiP2pConfig().apply{deviceAddress=normalized;groupOwnerIntent=50},actionResult(result))
    }
    private fun connectionInfo(result:MethodChannel.Result){if(!hasWifiPermission()){result.error("PERMISSION","Nearby Wi-Fi permission is required",null);return};wifiManager.requestConnectionInfo(wifiChannel){info->result.success(mapOf("connected" to info.groupFormed,"groupOwner" to info.isGroupOwner,"groupOwnerAddress" to if(info.groupFormed)info.groupOwnerAddress?.hostAddress else null))}}

    private fun copyToCache(uri: Uri): Map<String,Any>{
        val resolver=contentResolver; val name=queryName(uri)?:"attachment"; val mime=resolver.getType(uri)?:"application/octet-stream"; val safeName=name.replace(Regex("[^A-Za-z0-9._-]"),"_"); val pickDir=File(filesDir,"locallink_picks").apply{mkdirs()}; val outFile=File(pickDir,"locallink_${UUID.randomUUID()}_$safeName"); resolver.openInputStream(uri).use{input->requireNotNull(input){"Could not open selected file"};FileOutputStream(outFile).use{output->input.copyTo(output)}}; return mapOf("path" to outFile.absolutePath,"name" to name,"content_type" to mime,"size" to outFile.length())
    }
    private fun queryName(uri:Uri):String?{var cursor:Cursor?=null;return try{cursor=contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null);if(cursor!=null&&cursor.moveToFirst())cursor.getString(0)else uri.lastPathSegment}finally{cursor?.close()}}

    override fun onDestroy(){
        if (activeInstance === this) activeInstance = null
        callNotificationEventSink = null
        pendingCallNotificationActions.clear()
        notificationEventSink = null
        pendingNotificationActions.clear()
        releaseCallVideoTextures()
        LocalLinkTransportService.setEventListener(null)
        transportEventSink=null
        unregisterWifiReceiver()
        super.onDestroy()
    }
}
