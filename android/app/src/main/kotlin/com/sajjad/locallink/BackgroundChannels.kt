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
 * - Wi-Fi Direct answers "not available" (groups without Wi-Fi need the open
 *   app), so the transport runs on Local Wi-Fi only until the app is opened;
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
    private val transportListener = object : LocalLinkTransportService.EventListener {
        override fun onTransportEvent(type: String, data: Map<String, Any?>) {
            main.post { transportSink?.success(data) }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "locallink/device").setMethodCallHandler { call, result ->
            if (call.method == "androidId") {
                val id = try {
                    android.provider.Settings.Secure.getString(context.contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: ""
                } catch (_: Exception) { "" }
                result.success(id)
            } else result.notImplemented()
        }

        MethodChannel(messenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(context.packageManager.hasSystemFeature("android.hardware.wifi.direct"))
                // Wi-Fi Direct needs the open app: Local Wi-Fi only in the background.
                "hasPermission", "isEnabled" -> result.success(false)
                "getPeers", "getNearbyTags" -> result.success(emptyList<Map<String, Any?>>())
                "localNetStatus" -> result.success(emptyMap<String, Any?>())
                "connectionInfo" -> result.success(mapOf(
                    "connected" to false, "groupOwner" to false, "groupOwnerAddress" to null,
                    "wifiNetwork" to false, "sdk" to Build.VERSION.SDK_INT,
                ))
                "setNearbyIdentity", "setNearbyWanted", "setNearbyBridge", "setNearbyInCall",
                "setNearbyLinkTarget", "leaveLocalNet", "dispose" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, WIFI_EVENTS).setStreamHandler(QuietStream)

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
        EventChannel(messenger, "locallink/notification_actions").setStreamHandler(QuietStream)

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
        LocalLinkTransportService.clearEventListenerIf(transportListener)
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

    /** A stream the Dart side may listen to; it just never sends anything. */
    private object QuietStream : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}
        override fun onCancel(arguments: Any?) {}
    }

    companion object {
        private const val TAG = "LocalLinkBoot"
        const val WIFI_CHANNEL = "locallink/wifi_direct"
        const val WIFI_EVENTS = "locallink/wifi_direct_events"
        const val TRANSPORT_CHANNEL = "locallink/wifi_direct_transport"
        const val TRANSPORT_EVENTS = "locallink/wifi_direct_transport_events"
    }
}
