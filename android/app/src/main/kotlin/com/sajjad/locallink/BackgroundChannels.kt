package com.sajjad.locallink

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bundle 169 (4.3): the channels the background engine needs, with no screen.
 *
 * - transport (Local Wi-Fi + mesh), its events, the device id;
 * - message notifications;
 * - Nearby (Wi-Fi Direct) through NearbyRadio with an allowed list (177);
 * - notification taps / Reply stay in the 162 outbox for the app.
 *
 * Same channel names and arguments as MainActivity, so the Dart code is the same.
 */
class BackgroundChannels(
    private val context: Context,
    private val onStop: (String) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var transportSink: EventChannel.EventSink? = null
    // Bundle 176: Reject on the call notification while the app is closed.
    private var callActionSink: EventChannel.EventSink? = null
    private var notificationSink: EventChannel.EventSink? = null
    @Volatile private var ringing = false
    // Bundle 177: this engine's Nearby event sink.
    private var nearbySink: EventChannel.EventSink? = null
    private val transportListener = object : LocalLinkTransportService.EventListener {
        override fun onTransportEvent(type: String, data: Map<String, Any?>) {
            main.post { transportSink?.success(data) }
        }
    }

    fun register(messenger: BinaryMessenger) {
        registerLogChannel(context, messenger) // Bundle 180
        MethodChannel(messenger, "locallink/device").setMethodCallHandler { call, result ->
            if (call.method == "androidId") {
                val id = try {
                    android.provider.Settings.Secure.getString(context.contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: ""
                } catch (_: Exception) { "" }
                result.success(id)
            } else result.notImplemented()
        }

        // Bundle 177 (3): the real Nearby (one owner, NearbyRadio) with an
        // allowed list only - no pop-ups, no hotspot / linked-group tests.
        NearbyRadio.ensure(context)
        NearbyRadio.logState(context, "bg_start")
        MethodChannel(messenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            NearbyRadio.handle(call, result, NearbyBackgroundPolicy.BG_ALLOWED)
        }
        EventChannel(messenger, WIFI_EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { nearbySink = events; NearbyRadio.attach(events) }
            override fun onCancel(arguments: Any?) { NearbyRadio.detach(nearbySink); nearbySink = null }
        })

        MethodChannel(messenger, TRANSPORT_CHANNEL).setMethodCallHandler { call, result ->
            try { handleTransport(call, result) } catch (e: Exception) {
                result.error("TRANSPORT_ERROR", e.message, null)
            }
        }
        EventChannel(messenger, TRANSPORT_EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                transportSink = events
                LocalLinkTransportService.setEventListener(transportListener)
            }
            override fun onCancel(arguments: Any?) {
                transportSink = null
                LocalLinkTransportService.clearEventListenerIf(transportListener)
            }
        })

        MethodChannel(messenger, "locallink/notifications").setMethodCallHandler { call, result ->
            try { handleNotification(call, result) } catch (e: Exception) {
                result.error("NOTIFICATION_ERROR", e.message, null)
            }
        }
        // Bundle 177 (7.8): friend Remove / Block reach this engine too.
        EventChannel(messenger, "locallink/notification_actions").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { notificationSink = events }
            override fun onCancel(arguments: Any?) { notificationSink = null }
        })

        // Bundle 176 (1, 2): incoming calls ring with no screen. Same channel
        // names as MainActivity; the call itself is answered in the app
        // (Accept opens it and the ringing call is handed over).
        MethodChannel(messenger, "locallink/call_notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "showIncoming" -> {
                    val callId = call.argument<String>("call_id")?.trim().orEmpty()
                    val callerId = call.argument<String>("caller_id")?.trim().orEmpty()
                    if (callId.isEmpty() || callerId.isEmpty()) {
                        result.error("INVALID_CALL_NOTIFICATION", "call_id and caller_id are required", null)
                    } else {
                        CallNotificationManager.showIncoming(context, callId, callerId, call.argument<String>("caller_name")?.trim().orEmpty())
                        Log.i(TAG, "BG_CALL_RINGING call=$callId")
                        result.success(null)
                    }
                }
                "cancelIncoming", "cancelAll" -> { CallNotificationManager.cancelIncoming(context); result.success(null) }
                // Lock screen / permission need the open app.
                "setCallLockScreen", "requestPermission" -> result.success(null)
                // Bundle 179 (2): Accept always opens the app; nothing saved here.
                "acceptedCall", "clearAcceptedCall" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "locallink/call_notification_actions").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { callActionSink = events }
            override fun onCancel(arguments: Any?) { callActionSink = null }
        })
        MethodChannel(messenger, "locallink/call_ringtone").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { ringing = true; CallRingtoneManager.start(context); result.success(null) }
                "stop" -> { ringing = false; CallRingtoneManager.stop(); result.success(null) }
                // Outgoing calls are only made from the open app.
                "ringback_start", "ringback_stop" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        // Speaker / call screen settings belong to the open app.
        MethodChannel(messenger, "locallink/call_audio").setMethodCallHandler { _, result -> result.success(null) }
        MethodChannel(messenger, "locallink/call_media").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported_codecs" -> Thread {
                    val codecs = if (CallOpusCodec.usable()) listOf(CallOpus2Format.CODEC, CallOpus2Format.PCM) else listOf(CallOpus2Format.PCM)
                    main.post { try { result.success(codecs) } catch (_: Throwable) {} }
                }.apply { name = "locallink-bg-opus-selftest"; isDaemon = true }.start()
                "stop", "video_stop" -> result.success(null)
                else -> result.error("APP_REQUIRED", "calls are answered in the open app", null)
            }
        }
        MethodChannel(messenger, CallHandover.CHANNEL).setMethodCallHandler { call, result -> CallHandover.handle(call, result) }

        MethodChannel(messenger, "locallink/background_engine").setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    Log.i(TAG, "BOOT_ENGINE_READY failed=${call.argument<String>("detail").orEmpty()}")
                    result.success(null)
                }
                "idle" -> {
                    val reason = call.argument<String>("detail").orEmpty()
                    Log.i(TAG, "BOOT_ENGINE_IDLE reason=$reason")
                    result.success(null)
                    // Never destroy the engine inside its own call.
                    main.post { onStop("idle_$reason") }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The engine is going away: never leave the transport talking to it. */
    fun release() {
        transportSink = null
        callActionSink = null
        notificationSink = null
        // Bundle 177 (3.4): only stop listening - never leave the group,
        // clear the tag or stop the search (the app engine takes over).
        NearbyRadio.detach(nearbySink)
        nearbySink = null
        LocalLinkTransportService.clearEventListenerIf(transportListener)
        // Bundle 176 (5): never leave the ringtone playing without an engine.
        // The app engine starts it again if the call still rings.
        if (ringing) { ringing = false; CallRingtoneManager.stop() }
    }

    /** Bundle 176 (4): a call notification action for this engine. False = nobody listens. */
    fun dispatchCallAction(event: Map<String, Any?>): Boolean {
        val sink = callActionSink ?: return false
        main.post { try { sink.success(event) } catch (_: Exception) {} }
        return true
    }

    /** Bundle 177 (7.8): a friend notification action. False = nobody listens. */
    fun dispatchNotificationAction(event: Map<String, Any?>): Boolean {
        val sink = notificationSink ?: return false
        main.post { try { sink.success(event) } catch (_: Exception) {} }
        return true
    }

    private fun handleTransport(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val id = call.argument<String>("device_id")?.trim().orEmpty()
                if (id.isEmpty()) { result.error("INVALID_DEVICE", "device_id is required", null); return }
                LocalLinkTransportService.configure(
                    context, id,
                    call.argument<Boolean>("connected") == true,
                    call.argument<Boolean>("group_owner") == true,
                    call.argument<String>("group_owner_address")?.trim(),
                    stringList(call.argument<List<*>>("known_peers")),
                )
                result.success(null)
            }
            "ensureTransportReady" -> {
                val id = call.argument<String>("device_id")?.trim().orEmpty()
                if (id.isEmpty()) { result.error("INVALID_DEVICE", "device_id is required", null); return }
                val peers = stringList(call.argument<List<*>>("known_peers"))
                background("ensure-transport", result) { LocalLinkTransportService.ensureReady(context, id, peers); null }
            }
            "updateKnownPeers" -> {
                val peers = stringList(call.argument<List<*>>("known_peers"))
                background("known-peers", result) { LocalLinkTransportService.updateKnownPeers(context, peers); null }
            }
            "setStrictLinkCheck" -> {
                val on = call.argument<Boolean>("on") == true
                background("strict", result) { LocalLinkTransportService.setStrictLinkCheck(context, on); null }
            }
            "updateBlockedPeers" -> {
                val blocked = stringList(call.argument<List<*>>("blocked_peers"))
                background("blocked-peers", result) { LocalLinkTransportService.updateBlockedPeers(blocked); null }
            }
            "updateLinkKeys" -> {
                val json = call.argument<String>("link_keys").orEmpty()
                background("link-keys", result) { LocalLinkTransportService.updateLinkKeys(json) }
            }
            "send" -> {
                val target = call.argument<String>("recipient_id")?.trim().orEmpty()
                val payload = mapToPayload(call.argument<Map<*, *>>("payload"))
                Thread({
                    val ok = LocalLinkTransportService.send(target, payload)
                    main.post { if (ok) result.success(null) else result.error("PEER_UNAVAILABLE", "peer is not connected", null) }
                }, "locallink-bg-send").start()
            }
            "broadcast" -> {
                val payload = mapToPayload(call.argument<Map<*, *>>("payload"))
                Thread({
                    val ok = LocalLinkTransportService.broadcast(payload)
                    main.post { if (ok) result.success(null) else result.error("BROADCAST_FAILED", "no direct peer is connected", null) }
                }, "locallink-bg-broadcast").start()
            }
            "sendFile" -> {
                val target = call.argument<String>("recipient_id")?.trim().orEmpty()
                val path = call.argument<String>("file_path")?.trim().orEmpty()
                val fileId = call.argument<String>("file_id")?.trim().orEmpty()
                val messageId = call.argument<String>("message_id")?.trim().orEmpty()
                val name = call.argument<String>("file_name")?.trim() ?: "attachment"
                val type = call.argument<String>("content_type")?.trim() ?: "application/octet-stream"
                if (target.isEmpty() || path.isEmpty() || fileId.isEmpty() || messageId.isEmpty()) {
                    result.error("INVALID_FILE", "recipient_id, file_path, file_id and message_id are required", null)
                    return
                }
                LocalLinkTransportService.sendFile(target, path, fileId, messageId, name, type) { ok, error ->
                    main.post { if (ok) result.success(null) else result.error("FILE_SEND_FAILED", error, null) }
                }
            }
            "cancelFile" -> {
                LocalLinkTransportService.cancelFile(call.argument<String>("file_id")?.trim().orEmpty())
                result.success(null)
            }
            "allowFile" -> {
                LocalLinkTransportService.allowFile(call.argument<String>("file_id")?.trim().orEmpty())
                result.success(null)
            }
            "topology" -> background("topology", result) { LocalLinkTransportService.topology() }
            "flushQueue" -> background("flush", result) { LocalLinkTransportService.flushQueue(); null }
            // No Wi-Fi Direct in the background: nothing to re-read.
            "resume" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun handleNotification(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> { LocalLinkNotificationManager.initialize(context); result.success(null) }
            "notificationsEnabled" -> result.success(LocalLinkNotificationManager.notificationsEnabled(context))
            // No screen to ask from: the app asks when it is opened.
            "requestPermission", "openSettings" -> result.success(null)
            "showMessage" -> {
                val notificationId = call.argument<Int>("notification_id") ?: 0
                val conversationType = call.argument<String>("conversation_type")?.trim().orEmpty()
                val conversationId = call.argument<String>("conversation_id")?.trim().orEmpty()
                val messageId = call.argument<String>("message_id")?.trim().orEmpty()
                val senderId = call.argument<String>("sender_id")?.trim().orEmpty()
                val recipientId = call.argument<String>("recipient_id")?.trim().orEmpty()
                if (notificationId <= 0 || conversationType.isEmpty() || conversationId.isEmpty() || messageId.isEmpty() || senderId.isEmpty() || recipientId.isEmpty()) {
                    result.error("INVALID_NOTIFICATION", "notification identity is incomplete", null)
                    return
                }
                LocalLinkNotificationManager.showMessage(
                    context,
                    notificationId,
                    conversationType,
                    conversationId,
                    messageId,
                    senderId,
                    recipientId,
                    call.argument<String>("title")?.trim().orEmpty(),
                    call.argument<String>("body")?.trim().orEmpty(),
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
                    return
                }
                LocalLinkNotificationManager.showSummary(
                    context,
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
                LocalLinkNotificationManager.showSystem(
                    context,
                    call.argument<Int>("notification_id") ?: 0,
                    call.argument<String>("title")?.trim().orEmpty(),
                    call.argument<String>("body")?.trim().orEmpty(),
                    call.argument<Boolean>("silent") == true,
                )
                result.success(null)
            }
            "cancel" -> {
                LocalLinkNotificationManager.cancel(context, call.argument<Int>("notification_id") ?: 0)
                result.success(null)
            }
            "cancelMessages" -> { LocalLinkNotificationManager.cancelMessages(context); result.success(null) }
            "showFriendAdded" -> { showFriendAdded(call); result.success(null) }
            else -> result.notImplemented()
        }
    }

    /** Socket and disk work never runs on the main thread (same rule as Bundle 117). */
    private fun background(name: String, result: MethodChannel.Result, work: () -> Any?) {
        Thread({
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("TRANSPORT_ERROR", e.message, null) }
            }
        }, "locallink-bg-$name").start()
    }

    private fun stringList(values: List<*>?): List<String> =
        values?.mapNotNull { it?.toString()?.trim()?.ifEmpty { null } } ?: emptyList()

    private fun mapToPayload(values: Map<*, *>?): Map<String, Any?> =
        buildMap { values?.forEach { (k, v) -> if (k != null && v != null) put(k.toString(), v) } }

    private fun showFriendAdded(call: MethodCall) = LocalLinkNotificationManager.showFriendAdded(
        context,
        call.argument<Int>("notification_id") ?: 0,
        call.argument<String>("user_id")?.trim().orEmpty(),
        call.argument<String>("device_id")?.trim().orEmpty(),
        call.argument<String>("recipient_id")?.trim().orEmpty(),
        call.argument<String>("name")?.trim().orEmpty(),
    )

    companion object {
        private const val TAG = "LocalLinkBoot"
        const val WIFI_CHANNEL = "locallink/wifi_direct"
        const val WIFI_EVENTS = "locallink/wifi_direct_events"
        const val TRANSPORT_CHANNEL = "locallink/wifi_direct_transport"
        const val TRANSPORT_EVENTS = "locallink/wifi_direct_transport_events"
    }
}
