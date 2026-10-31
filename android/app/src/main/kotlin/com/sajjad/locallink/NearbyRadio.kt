package com.sajjad.locallink

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.sajjad.locallink.mesh.NearbyGroupPolicy
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bundle 177 (2): the ONE owner of Nearby (Wi-Fi Direct) for the whole app.
 *
 * Moved out of MainActivity (not copied): the Wi-Fi Direct manager + channel,
 * its receiver, the nearby tags (155) and Local Net (161). It lives on the
 * application context, so closing the screen no longer stops Nearby; the
 * engine that is alive (app screen or the no-screen engine) attaches to its
 * events. Only Log out stops it ([shutdown]).
 *
 * Silent connections only (177, Q6): the old pop-up connect ("Accept
 * invitation?") is refused with SILENT_ONLY.
 *
 * Everything runs on the main looper. Never throws.
 */
object NearbyRadio {
    const val TAG = "NEARBY"
    const val CHANNEL = "locallink/wifi_direct"
    const val EVENTS = "locallink/wifi_direct_events"

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var app: Context? = null
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    @Volatile private var p2pEnabled = false
    private var peers: List<WifiP2pDevice> = emptyList()
    @Volatile var tags: NearbyTagManager? = null
        private set
    @Volatile var localNet: LocalNetManager? = null
        private set
    private var receiverOn = false
    private var sink: EventChannel.EventSink? = null
    private val reinitAt = ArrayList<Long>()
    // Re-applied to a new tag manager after a lost channel.
    private var lastWanted: List<String>? = null
    private var lastInCall = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    p2pEnabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    emit(mapOf("type" to "state", "enabled" to p2pEnabled))
                    if (!p2pEnabled) {
                        // Wi-Fi Direct is an optional transport. Disabling it must not
                        // tear down the LAN mesh or the background transport service.
                        LocalLinkTransportService.updateConnection(context, false, false, null)
                    } else {
                        requestConnectionInfo()
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> { requestPeers(); tags?.onPeersChanged() }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> requestConnectionInfo()
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> emit(mapOf("type" to "device_changed"))
            }
        }
    }

    private val channelListener = WifiP2pManager.ChannelListener {
        // Android dropped our Wi-Fi Direct channel: set it up again, but
        // never in a loop (177, 2.9).
        main.post {
            val now = SystemClock.elapsedRealtime()
            val n = NearbyBackgroundPolicy.recentReinits(reinitAt, now)
            if (!NearbyBackgroundPolicy.mayReinit(n)) {
                Log.w(TAG, "NEARBY_CHANNEL_REINIT skipped n=$n")
                return@post
            }
            reinitAt.add(now)
            Log.w(TAG, "NEARBY_CHANNEL_REINIT n=${n + 1}")
            main.postDelayed({ app?.let { reinit(it) } }, NearbyBackgroundPolicy.REINIT_DELAY_MS)
        }
    }

    /** Sets Nearby up once (safe to call again). False = no Wi-Fi Direct. */
    @Synchronized
    fun ensure(context: Context): Boolean {
        if (manager != null && channel != null) return true
        val a = context.applicationContext
        app = a
        val m = a.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager ?: return false
        return try {
            val ch = m.initialize(a, Looper.getMainLooper(), channelListener) ?: return false
            manager = m
            channel = ch
            tags = NearbyTagManager(a, m, ch, { hasPermission(a) }, onWifi = { onWifiNetwork(a) }) { event -> emit(event) }
            lastWanted?.let { tags?.setWanted(it) }
            if (lastInCall) tags?.setInCall(true)
            // Bundle 161: linked groups + LocalLink hotspot (tests, off by default).
            localNet = LocalNetManager.bind(a, { tags }) { event -> emit(event) }
            registerReceiver(a)
            Log.i(TAG, "NEARBY_RADIO_READY perm=${hasPermission(a)}")
            true
        } catch (e: Exception) {
            Log.w(TAG, "NEARBY_RADIO_FAILED ${e.message}")
            false
        }
    }

    private fun reinit(context: Context) {
        synchronized(this) {
            try { if (Build.VERSION.SDK_INT >= 27) channel?.close() } catch (_: Exception) {}
            channel = null
            manager = null
            tags = null
        }
        ensure(context)
        requestPeers()
        requestConnectionInfo()
    }

    /** Only Log out stops Nearby (177, 2.8). */
    @Synchronized
    fun shutdown(reason: String) {
        val a = app ?: return
        Log.i(TAG, "NEARBY_RADIO_STOP reason=$reason")
        if (receiverOn) { try { a.unregisterReceiver(receiver) } catch (_: Exception) {}; receiverOn = false }
        try { localNet?.dispose() } catch (_: Exception) {}
        localNet = null
        try { if (Build.VERSION.SDK_INT >= 27) channel?.close() } catch (_: Exception) {}
        channel = null
        manager = null
        tags = null
        sink = null
    }

    /** The engine that is alive gets the events (the last one attached). */
    fun attach(events: EventChannel.EventSink?) {
        sink = events
        requestPeers()
        requestConnectionInfo()
    }

    fun detach(events: EventChannel.EventSink?) {
        if (sink === events) sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        val send = { try { sink?.success(event) } catch (_: Exception) {} }
        if (Looper.myLooper() == Looper.getMainLooper()) send() else main.post { send() }
    }

    private fun registerReceiver(context: Context) {
        if (receiverOn) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
        receiverOn = true
    }

    fun hasPermission(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 33) context.checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) == PackageManager.PERMISSION_GRANTED
        else context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** 177 (Q4): Android 10-12 search with no screen needs "All the time". */
    fun hasBackgroundLocation(context: Context): Boolean =
        Build.VERSION.SDK_INT !in 29..32 ||
            context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** (charging, level 0-100 or -1). Never throws. */
    fun battery(context: Context): Pair<Boolean, Int> = try {
        val i: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = i?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = i?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val charging = plugged != 0 || status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        charging to (if (level >= 0 && scale > 0) level * 100 / scale else -1)
    } catch (_: Exception) {
        false to -1
    }

    /** 177 (10.1): one word for the STATUS card line. */
    fun statusWord(context: Context): String {
        if (!context.packageManager.hasSystemFeature("android.hardware.wifi.direct")) return "unsupported"
        if (!hasPermission(context)) return "no_permission"
        if (!hasBackgroundLocation(context)) return "no_location"
        val (charging, level) = battery(context)
        if (!charging && level in 0..NearbyBackgroundPolicy.BATTERY_STOP_LEVEL) return "battery_low"
        return "on"
    }

    /** 177 (1): what survives when the screen closes / opens (log only). */
    fun logState(context: Context, moment: String) {
        val a = context.applicationContext
        val perm = hasPermission(a)
        val m = manager
        val ch = channel
        if (!perm || m == null || ch == null) {
            Log.i(TAG, "NEARBY_BG_STATE when=$moment group=? perm=${yn(perm)} loc=${yn(hasBackgroundLocation(a))} receiver=${yn(receiverOn)} radio=${yn(m != null)}")
            return
        }
        try {
            m.requestConnectionInfo(ch) { info ->
                Log.i(TAG, "NEARBY_BG_STATE when=$moment group=${yn(info?.groupFormed == true)} owner=${yn(info?.isGroupOwner == true)} perm=y loc=${yn(hasBackgroundLocation(a))} receiver=${yn(receiverOn)} engine=${yn(sink != null)}")
            }
        } catch (_: Exception) {}
    }

    private fun yn(b: Boolean) = if (b) "y" else "n"

    /** One handler for `locallink/wifi_direct`. [allowed] null = the open app. */
    fun handle(call: MethodCall, result: MethodChannel.Result, allowed: Set<String>?) {
        val a = app
        if (a == null || (manager == null && call.method != "isSupported" && call.method != "hasPermission")) {
            when (call.method) {
                "getPeers", "getNearbyTags" -> result.success(emptyList<Map<String, Any?>>())
                "localNetStatus" -> result.success(emptyMap<String, Any?>())
                "dispose", "setNearbyWanted", "setNearbyInCall" -> result.success(null)
                else -> result.error("WIFI_DIRECT", "Wi-Fi Direct is not available", null)
            }
            return
        }
        if (allowed != null && call.method !in allowed) {
            result.error("APP_REQUIRED", "Open LocalLink for this", null)
            return
        }
        val m = manager
        val ch = channel
        when (call.method) {
            "isSupported" -> result.success(a.packageManager.hasSystemFeature("android.hardware.wifi.direct"))
            "hasPermission" -> result.success(hasPermission(a))
            "isEnabled" -> {
                if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
                result.success(p2pEnabled)
            }
            "discoverPeers" -> discoverPeers(result)
            "getPeers" -> result.success(peers.map { peerMap(it) })
            // 177 (Q6): the old pop-up connect is gone. Silent group joins only.
            "connect" -> {
                Log.i(TAG, "silent_only_refused method=connect")
                result.error("SILENT_ONLY", "Only silent nearby connections are used", null)
            }
            // Bundle 155: identity tag (short hash of the device id) + current tags.
            "setNearbyIdentity" -> {
                if (tags?.setIdentity(call.argument<String>("id")) == true) result.success(null)
                else result.error("INVALID_TAG_ID", "A valid nearby tag id is required", null)
            }
            "getNearbyTags" -> result.success(tags?.snapshot() ?: emptyList<Map<String, Any>>())
            // Bundle 157: one shared group (create / join without pop-ups).
            "setNearbyWanted" -> { val ids = call.argument<List<String>>("ids"); lastWanted = ids; tags?.setWanted(ids); result.success(null) }
            "setNearbyBridge" -> { tags?.setBridge(call.argument<Boolean>("on") ?: false); result.success(null) }
            // Bundle 167 (5.5): a voice call goes on here.
            "setNearbyInCall" -> { val on = call.argument<Boolean>("on") ?: false; lastInCall = on; tags?.setInCall(on); result.success(null) }
            // Bundle 161: linked groups + LocalLink hotspot (null = started, else a reason).
            "joinLocalNet" -> result.success(localNet?.join(
                call.argument<String>("kind").orEmpty(), call.argument<String>("ssid").orEmpty(),
                call.argument<String>("key").orEmpty(), call.argument<String>("v6")))
            "leaveLocalNet" -> { localNet?.leave(call.argument<String>("reason") ?: "app"); result.success(null) }
            "startLocalHotspot" -> result.success(if (hasPermission(a)) localNet?.startHotspot() else "permission")
            "stopLocalHotspot" -> { localNet?.stopHotspot(call.argument<String>("reason") ?: "app"); result.success(null) }
            "setNearbyLinkTarget" -> { tags?.setLinkTarget(call.argument<String>("id")); result.success(null) }
            "localNetStatus" -> result.success(localNet?.status() ?: emptyMap<String, Any?>())
            "createNearbyGroup" -> createNearbyGroup(result)
            "joinNearbyGroup" -> joinNearbyGroup(call.argument<String>("name"), call.argument<String>("key"), call.argument<String>("address"), call.argument<Boolean>("leave") ?: false, result)
            "cancelConnect" -> if (m != null && ch != null) m.cancelConnect(ch, actionResult(result)) else result.success(null)
            "disconnect" -> if (m != null && ch != null) m.removeGroup(ch, actionResult(result)) else result.success(null)
            "connectionInfo" -> connectionInfo(result)
            // 177 (2.6): closing a screen never stops Nearby any more.
            "dispose" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun actionResult(result: MethodChannel.Result) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() { result.success(null) }
        override fun onFailure(reason: Int) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
    }

    fun requestPeers() {
        val a = app ?: return
        val m = manager ?: return
        val ch = channel ?: return
        if (!hasPermission(a)) return
        try {
            m.requestPeers(ch) { list: WifiP2pDeviceList? ->
                peers = list?.deviceList?.toList() ?: emptyList()
                emit(mapOf("type" to "peers", "peers" to peers.map { peerMap(it) }))
            }
        } catch (_: Exception) {}
    }

    private fun connectionMap(a: Context, info: WifiP2pInfo?): Map<String, Any?> {
        val connected = info?.groupFormed == true
        val (charging, level) = battery(a)
        return mapOf(
            "connected" to connected,
            "groupOwner" to (info?.isGroupOwner == true),
            "groupOwnerAddress" to if (connected) info?.groupOwnerAddress?.hostAddress else null,
            "wifiNetwork" to onWifiNetwork(a),
            "sdk" to Build.VERSION.SDK_INT,
            // 177 (4.3): battery rules for the search.
            "batteryLevel" to level,
            "charging" to charging,
        )
    }

    fun requestConnectionInfo() {
        val a = app ?: return
        val m = manager ?: return
        val ch = channel ?: return
        if (!hasPermission(a)) return
        try {
            m.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
                val connected = info?.groupFormed == true
                val owner = info?.isGroupOwner == true
                val address = if (connected) info?.groupOwnerAddress?.hostAddress else null
                emit(mapOf("type" to "connection", "connection" to connectionMap(a, info)))
                tags?.onConnection(connected, owner)
                LocalLinkTransportService.resume(a, connected, owner, address)
            }
        } catch (_: Exception) {}
    }

    private fun discoverPeers(result: MethodChannel.Result) {
        val a = app ?: return result.success(null)
        val m = manager ?: return result.success(null)
        val ch = channel ?: return result.success(null)
        if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
        m.discoverPeers(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                result.success(null)
                // Bundle 155: also look for LocalLink tags (who is who).
                tags?.scheduleDiscovery()
            }
            override fun onFailure(reason: Int) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
        })
    }

    private fun connectionInfo(result: MethodChannel.Result) {
        val a = app ?: return result.success(null)
        val m = manager ?: return result.success(null)
        val ch = channel ?: return result.success(null)
        if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
        m.requestConnectionInfo(ch) { info -> result.success(connectionMap(a, info)) }
    }

    /** Bundle 157: on a normal Wi-Fi network (router or hotspot)? Wi-Fi Direct
     *  groups and the linked group / LocalLink hotspot are not counted. */
    fun onWifiNetwork(context: Context): Boolean = try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        @Suppress("DEPRECATION")
        cm.allNetworks.any { n -> localNet?.owns(n) != true && cm.getNetworkCapabilities(n)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true }
    } catch (_: Exception) { false }

    /** Bundle 157: start a new shared group and become its host. Android 10+
     *  gets a fresh name + password (published in the tag, so others join
     *  without a pop-up); older phones let Android pick them. Never while
     *  already in a group. */
    private fun createNearbyGroup(result: MethodChannel.Result) {
        val a = app ?: return result.success(null)
        val m = manager ?: return result.success(null)
        val ch = channel ?: return result.success(null)
        if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
        m.requestConnectionInfo(ch) { info ->
            if (info?.groupFormed == true) {
                Log.i(TAG, "group create skipped reason=already_in_group host=${info.isGroupOwner}")
                result.error("IN_GROUP", "This phone is already in a nearby group", null)
                return@requestConnectionInfo
            }
            val listener = object : WifiP2pManager.ActionListener {
                override fun onSuccess() { Log.i(TAG, "group create ok"); result.success(null) }
                override fun onFailure(reason: Int) { Log.w(TAG, "group create failed reason=$reason"); result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
            }
            try {
                if (Build.VERSION.SDK_INT >= 29) {
                    val name = NearbyGroupPolicy.newNetworkName()
                    val config = WifiP2pConfig.Builder().setNetworkName(name).setPassphrase(NearbyGroupPolicy.newPassphrase()).enablePersistentMode(false).build()
                    Log.i(TAG, "group create grp=$name")
                    m.createGroup(ch, config, listener)
                } else {
                    Log.i(TAG, "group create legacy")
                    m.createGroup(ch, listener)
                }
            } catch (e: Exception) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: ${e.message}", null) }
        }
    }

    /** Bundle 157: join a nearby shared group with its name + password, like a
     *  normal Wi-Fi network (Android 10+, no pop-up). 177 (Q6): the classic
     *  connect (one pop-up on the other phone) is gone - SILENT_ONLY. A phone
     *  in a group never leaves it unless [leave]. */
    private fun joinNearbyGroup(name: String?, key: String?, address: String?, leave: Boolean, result: MethodChannel.Result) {
        val a = app ?: return result.success(null)
        val m = manager ?: return result.success(null)
        val ch = channel ?: return result.success(null)
        if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
        val credentials = Build.VERSION.SDK_INT >= 29 && NearbyGroupPolicy.validNetworkName(name) && NearbyGroupPolicy.validPassphrase(key)
        if (!credentials) {
            Log.i(TAG, "silent_only_refused method=join target=${address?.trim().orEmpty()} sdk=${Build.VERSION.SDK_INT}")
            result.error("SILENT_ONLY", "A silent join needs Android 10+ and the group password", null)
            return
        }
        m.requestConnectionInfo(ch) { info ->
            val formed = info?.groupFormed == true
            val owner = info?.isGroupOwner == true
            if (!NearbyGroupPolicy.mayChangeGroup(formed, owner, leave)) {
                Log.i(TAG, "group join skipped reason=member_keeps_group host=$owner")
                result.error("IN_GROUP_AS_MEMBER", "This phone stays in its current nearby group", null)
                return@requestConnectionInfo
            }
            val doJoin = {
                val listener = object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { Log.i(TAG, "group join requested"); result.success(null) }
                    override fun onFailure(reason: Int) { Log.w(TAG, "group join failed reason=$reason"); result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
                }
                try {
                    Log.i(TAG, "group join grp=$name mode=password")
                    m.connect(ch, WifiP2pConfig.Builder().setNetworkName(name!!).setPassphrase(key!!).enablePersistentMode(false).build(), listener)
                } catch (e: Exception) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: ${e.message}", null) }
            }
            if (formed) {
                Log.i(TAG, "group leave before join host=$owner")
                m.removeGroup(ch, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { main.postDelayed({ doJoin() }, 1500L) }
                    override fun onFailure(reason: Int) { main.postDelayed({ doJoin() }, 1500L) }
                })
            } else doJoin()
        }
    }

    private fun peerMap(device: WifiP2pDevice) = mapOf("name" to device.deviceName, "address" to device.deviceAddress, "status" to device.status)
}
