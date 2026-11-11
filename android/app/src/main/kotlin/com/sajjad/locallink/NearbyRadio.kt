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
    private const val CALL_LOG_TAG = "LocalLinkCall"

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
    // Bundle 189 (A): when a nearby group create/join was last asked for.
    @Volatile private var lastGroupChangeAt = 0L
    // Bundle 200 (C): the WD_PEERS line, only when the list changed (or 60 s).
    private var lastPeersLine = ""
    private var lastPeersLogAt = 0L
    /** Bundle 192: last known Wi-Fi Direct group state (null = not seen yet). */
    @Volatile private var lastFormed: Boolean? = null
    // Bundle 201 (A3): host/member and Android's last word on the link.
    @Volatile private var lastOwner = false
    @Volatile private var lastConnDetail = WdGroupLost.detail(null, null, null)
    // Bundle 205 (P6): when the app screen last closed (for WD_GROUP_LOST why=).
    @Volatile private var lastAppCloseAt = 0L
    // Bundle 262 (B1): last Wi-Fi Direct on/off seen (null = not yet) and when it went off.
    @Volatile private var lastP2p262: Boolean? = null
    @Volatile private var p2pOffAt262 = 0L
    // Bundle 262 (B3): recent "busy" answers to a join / create (main thread only).
    private val busyAt262 = ArrayList<Long>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    p2pEnabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    // Bundle 262 (B1): one line when the phone turns Wi-Fi Direct off / on.
                    val nowMs = SystemClock.elapsedRealtime()
                    P2pState262.line(lastP2p262, p2pEnabled, p2pOffAt262, nowMs)?.let { Log.i(TAG, it) }
                    if (lastP2p262 != false && !p2pEnabled) p2pOffAt262 = nowMs
                    if (p2pEnabled) busyAt262.clear()
                    lastP2p262 = p2pEnabled
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
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    // Bundle 201 (A3): keep what Android said (logs only).
                    try {
                        @Suppress("DEPRECATION")
                        val ni = intent.getParcelableExtra<android.net.NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                        @Suppress("DEPRECATION")
                        if (ni != null) lastConnDetail = WdGroupLost.detail(ni.detailedState?.name, ni.reason, ni.extraInfo)
                    } catch (_: Exception) {}
                    requestConnectionInfo()
                }
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
            tags = NearbyTagManager(a, m, ch, { hasPermission(a) }, onWifi = { onWifiNetwork(a) }, peerCount = { peers.size },
                refreshPeers = { main.post { requestPeers() } }) { event -> emit(event) }
            lastWanted?.let { tags?.setWanted(it) }
            if (lastInCall) tags?.setInCall(true)
            // Bundle 161: linked groups + LocalLink hotspot (tests, off by default).
            localNet = LocalNetManager.bind(a, { tags }) { event -> emit(event) }
            registerReceiver(a)
            // Bundle 226 (B3): Bluetooth LE finds friends (Android 10+).
            NearbyBle.start(a) { event -> emit(event) }
            Log.i(TAG, "NEARBY_RADIO_READY perm=${hasPermission(a)}")
            closeLeftoverGroup(a, m, ch) // Bundle 260 (A6)
            true
        } catch (e: Exception) {
            Log.w(TAG, "NEARBY_RADIO_FAILED ${e.message}")
            false
        }
    }

    /** Bundle 260 (A6): checked once per app process. */
    @Volatile private var leftoverChecked = false

    /** Bundle 260 (A6): a LinkUp group this phone still hosts from before the
     *  app died (force stop) is closed once at start - its members can then
     *  join a group whose app runs. */
    private fun closeLeftoverGroup(a: Context, m: WifiP2pManager, ch: WifiP2pManager.Channel) {
        if (leftoverChecked) return
        leftoverChecked = true
        if (!hasPermission(a)) return
        try {
            m.requestGroupInfo(ch) { g ->
                try {
                    val name = g?.networkName
                    val members = g?.clientList?.size ?: 0
                    if (g == null || tags?.foreign == true ||
                        !LeftoverGroupPolicy.shouldClose(true, g.isGroupOwner, name)) return@requestGroupInfo
                    m.removeGroup(ch, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() { Log.i(TAG, LeftoverGroupPolicy.line(name, members, true)) }
                        override fun onFailure(reason: Int) { Log.w(TAG, LeftoverGroupPolicy.line(name, members, false)) }
                    })
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
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
        NearbyBle.stop(reason) // Bundle 226
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
        // Bundle 262 (B2): the engine that attaches learns if Wi-Fi Direct is off.
        lastP2p262?.let { emit(mapOf("type" to "state", "enabled" to it)) }
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
        if (moment == "close") lastAppCloseAt = System.currentTimeMillis()
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
                "dispose", "setNearbyWanted", "setNearbyInCall", "setBleWanted" -> result.success(null)
                "bleStatus" -> result.success(if (a != null) NearbyBle.status(a) else mapOf("state" to "unsupported", "sdk" to Build.VERSION.SDK_INT))
                else -> result.error("WIFI_DIRECT", "Wi-Fi Direct is not available", null)
            }
            return
        }
        if (allowed != null && call.method !in allowed) {
            result.error("APP_REQUIRED", "Open LinkUp for this", null)
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
            // Bundle 210: the mesh test switch is one hotspot owner; Share LinkUp is the other.
            "startLocalHotspot" -> result.success(if (hasPermission(a)) localNet?.startHotspot(AppSharePolicy.OWNER_MESH, null) else "permission")
            "stopLocalHotspot" -> { localNet?.stopHotspot(AppSharePolicy.OWNER_MESH, call.argument<String>("reason") ?: "app"); result.success(null) }
            "setNearbyLinkTarget" -> { tags?.setLinkTarget(call.argument<String>("id")); result.success(null) }
            "localNetStatus" -> result.success(localNet?.status() ?: emptyMap<String, Any?>())
            "createNearbyGroup" -> createNearbyGroup(result)
            // Bundle 200 (B): the friend backup group (name + password from the pair's link key).
            "createFriendGroup" -> createFriendGroup(call.argument<String>("name"), call.argument<String>("key"), result)
            "joinNearbyGroup" -> joinNearbyGroup(call.argument<String>("name"), call.argument<String>("key"), call.argument<String>("address"), call.argument<Boolean>("leave") ?: false, result)
            "cancelConnect" -> if (m != null && ch != null) m.cancelConnect(ch, actionResult(result)) else result.success(null)
            // Bundle 224 (A, D1): never close a group LinkUp did not make.
            "disconnect" -> if (tags?.foreign == true) {
                Log.i(TAG, "WD_FOREIGN_GROUP keep why=disconnect")
                result.success(null)
            } else if (m != null && ch != null) {
                lastGroupChangeAt = System.currentTimeMillis() // Bundle 205 (P6): this phone closed it
                m.removeGroup(ch, actionResult(result))
            } else result.success(null)
            "connectionInfo" -> connectionInfo(result)
            // Bundle 226 (B3): Bluetooth LE state + what this phone advertises.
            "bleStatus" -> result.success(NearbyBle.status(a))
            "setBleWanted" -> { NearbyBle.setWanted(call.arguments as? Map<*, *>); result.success(null) }
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
                logPeers()
                emit(mapOf("type" to "peers", "peers" to peers.map { peerMap(it) }))
            }
        } catch (_: Exception) {}
    }

    /** Bundle 200 (C): `WD_PEERS n=2 list=realme C71/3/go,ZTE/3` (name, status,
     *  go = it hosts a group). Only when it changed, or once a minute. */
    private fun logPeers() {
        try {
            val line = SearchWindowPolicy.peersLine(peers.map { Triple(it.deviceName ?: "?", it.status, it.isGroupOwner) })
            val now = System.currentTimeMillis()
            if (line == lastPeersLine && now - lastPeersLogAt < 60_000L) return
            lastPeersLine = line
            lastPeersLogAt = now
            Log.i(TAG, "WD_PEERS $line")
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
                // Bundle 201 (A3, logs only): the group went away.
                try {
                    if (WdGroupLost.lost(lastFormed, connected)) {
                        // Bundle 205 (P6): plus a best guess of who ended it.
                        val why = WdGroupLost.why(System.currentTimeMillis(), p2pEnabled, lastGroupChangeAt, tags?.lastWindowAt ?: 0L, lastAppCloseAt)
                        Log.i(TAG, WdGroupLost.line(lastOwner, p2pEnabled, lastConnDetail, why))
                    }
                    if (connected) lastOwner = owner
                } catch (_: Exception) {}
                // Bundle 192 (logs only): Wi-Fi Direct link lost / back during a call.
                try {
                    val change = WdLinkPolicy.changeInCall(CallNearbyPause.inCall(), lastFormed, connected)
                    lastFormed = connected
                    if (change == "drop_in_call") Log.w(CALL_LOG_TAG, WdLinkPolicy.line(change, false, false, -1, -1))
                    else if (change != null) logLinkNow(change)
                } catch (_: Exception) {}
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
        // Bundle 184 (E1): a search makes the Wi-Fi leave the router's channel
        // for a moment - not during a voice call (voice broke up).
        if (!CallNearbyPause.searchAllowed()) {
            if (CallNearbyPause.logDue()) Log.i(TAG, "search paused call")
            result.success(null)
            return
        }
        // Bundle 200 (A): one search window at a time - a new peer discovery
        // would cut the tag search that runs now.
        if (tags?.searchWindowOpen() == true) {
            result.success(null)
            return
        }
        m.discoverPeers(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                result.success(null)
                // Bundle 155: also look for LocalLink tags (who is who).
                tags?.scheduleDiscovery()
            }
            override fun onFailure(reason: Int) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
        })
    }

    /** Bundle 189 (A): call voice started - stop a search that is already
     *  running (one started while ringing kept going ~2 min into the call).
     *  Any thread; the work runs on the main looper. Never throws. */
    fun stopSearchForCall() {
        NearbyBle.onCallVoice(true) // Bundle 226: no Bluetooth scan during call voice
        main.post {
            try { stopSearchNow() } catch (_: Exception) {}
        }
    }

    private fun stopSearchNow() {
        val m = manager
        val ch = channel
        if (m == null || ch == null) {
            Log.i(CALL_LOG_TAG, CallSearchStop.line("none", "none"))
            return
        }
        val clearServices = { peers: String ->
            try {
                m.clearServiceRequests(ch, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { Log.i(CALL_LOG_TAG, CallSearchStop.line(peers, CallSearchStop.result(true))) }
                    override fun onFailure(reason: Int) { Log.i(CALL_LOG_TAG, CallSearchStop.line(peers, CallSearchStop.result(false, reason))) }
                })
            } catch (_: Exception) {
                Log.i(CALL_LOG_TAG, CallSearchStop.line(peers, "error"))
            }
        }
        if (CallSearchStop.peersAction(System.currentTimeMillis(), lastGroupChangeAt) != "stop") {
            clearServices("skip_joining")
            return
        }
        try {
            m.stopPeerDiscovery(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() { clearServices(CallSearchStop.result(true)) }
                override fun onFailure(reason: Int) { clearServices(CallSearchStop.result(false, reason)) }
            })
        } catch (_: Exception) {
            clearServices("error")
        }
    }

    /** Bundle 192 (logs only): one `WD_LINK` line (call start / end).
     *  Any thread; the work runs on the main looper. Never throws. */
    fun logLinkForCall(moment: String) {
        main.post {
            try { logLinkNow(moment) } catch (_: Exception) {}
        }
    }

    private fun logLinkNow(moment: String) {
        val a = app
        val m = manager
        val ch = channel
        if (a == null || m == null || ch == null || !hasPermission(a)) {
            Log.i(CALL_LOG_TAG, "WD_LINK at=$moment group=- reason=no_radio")
            return
        }
        try {
            m.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
                val formed = info?.groupFormed == true
                val owner = info?.isGroupOwner == true
                if (!formed) {
                    Log.i(CALL_LOG_TAG, WdLinkPolicy.line(moment, false, false, -1, -1))
                    return@requestConnectionInfo
                }
                try {
                    m.requestGroupInfo(ch) { g ->
                        val members = if (owner) g?.clientList?.size ?: 0 else -1
                        val freq = if (Build.VERSION.SDK_INT >= 29) (g?.frequency ?: -1) else -1
                        Log.i(CALL_LOG_TAG, WdLinkPolicy.line(moment, true, owner, members, freq))
                    }
                } catch (_: Exception) {
                    Log.i(CALL_LOG_TAG, WdLinkPolicy.line(moment, true, owner, -1, -1))
                }
            }
        } catch (_: Exception) {
            Log.i(CALL_LOG_TAG, "WD_LINK at=$moment group=- reason=error")
        }
    }

    /** Bundle 184 (E1): look for nearby tags again shortly after a call. */
    fun resumeAfterCall() {
        NearbyBle.onCallVoice(false) // Bundle 226
        main.postDelayed({
            if (CallNearbyPause.searchAllowed()) tags?.scheduleDiscovery(0L)
        }, CallNearbyPause.RESUME_AFTER_MS + 200L)
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
        // Bundle 205 (P3, L8): only a real router / hotspot counts. Some
        // phones list their own Wi-Fi Direct group as a restricted Wi-Fi
        // network (false router_back at 21:09:50, right after hosting).
        @Suppress("DEPRECATION")
        cm.allNetworks.any { n ->
            val caps = cm.getNetworkCapabilities(n)
            val lp = try { cm.getLinkProperties(n) } catch (_: Exception) { null }
            RouterNetworkPolicy.isRouter(
                wifiTransport = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true,
                notRestricted = caps?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED) == true,
                iface = lp?.interfaceName,
                ownedByLocalNet = localNet?.owns(n) == true,
                ipv4 = lp?.linkAddresses?.mapNotNull { la -> (la.address as? java.net.Inet4Address)?.hostAddress }.orEmpty(),
            )
        }
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
                override fun onSuccess() { Log.i(TAG, "group create ok"); noteBusy262(-1); result.success(null) }
                override fun onFailure(reason: Int) { Log.w(TAG, "group create failed reason=$reason"); noteBusy262(reason); result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
            }
            try {
                lastGroupChangeAt = System.currentTimeMillis() // Bundle 189 (A)
                if (Build.VERSION.SDK_INT >= 29) {
                    val name = NearbyGroupPolicy.newNetworkName()
                    // Bundle 262 (A): on 2.4 GHz (a 2.4-only phone can't see 5 GHz).
                    Log.i(TAG, GroupBand262.createLine(name, GroupBand262.wants(Build.VERSION.SDK_INT)))
                    createGroup262(m, ch, name, NearbyGroupPolicy.newPassphrase(), "group create", listener)
                } else {
                    Log.i(TAG, "group create legacy")
                    // Bundle 224 (A2): the group that forms next is ours.
                    tags?.legacyCreatedAt = System.currentTimeMillis()
                    m.createGroup(ch, listener)
                }
            } catch (e: Exception) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: ${e.message}", null) }
        }
    }

    /** Bundle 200 (B): host the friend backup group. Name + password come from
     *  Dart (made from the pair's link key, so only the friend can work them
     *  out). Android 10+, never while already in a group. The password is
     *  never logged. */
    private fun createFriendGroup(name: String?, key: String?, result: MethodChannel.Result) {
        val a = app ?: return result.success(null)
        val m = manager ?: return result.success(null)
        val ch = channel ?: return result.success(null)
        if (!hasPermission(a)) { result.error("PERMISSION", "Nearby Wi-Fi permission is required", null); return }
        if (Build.VERSION.SDK_INT < 29 || !NearbyGroupPolicy.validNetworkName(name) || !NearbyGroupPolicy.validPassphrase(key)) {
            Log.i(TAG, "WD_FRIEND_OPEN skipped reason=invalid sdk=${Build.VERSION.SDK_INT}")
            result.error("INVALID", "A friend group needs Android 10+ and a valid name", null)
            return
        }
        m.requestConnectionInfo(ch) { info ->
            if (info?.groupFormed == true) {
                Log.i(TAG, "WD_FRIEND_OPEN skipped reason=already_in_group host=${info.isGroupOwner}")
                result.error("IN_GROUP", "This phone is already in a nearby group", null)
                return@requestConnectionInfo
            }
            val listener = object : WifiP2pManager.ActionListener {
                override fun onSuccess() { Log.i(TAG, "WD_FRIEND_OPEN ok grp=$name"); result.success(null) }
                override fun onFailure(reason: Int) { Log.w(TAG, "WD_FRIEND_OPEN failed reason=$reason"); result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
            }
            try {
                lastGroupChangeAt = System.currentTimeMillis()
                // Bundle 262 (A): on 2.4 GHz, like the shared group.
                createGroup262(m, ch, name!!, key!!, "WD_FRIEND_OPEN", listener)
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
                    override fun onSuccess() { Log.i(TAG, "group join requested"); noteBusy262(-1); result.success(null) }
                    override fun onFailure(reason: Int) { Log.w(TAG, "group join failed reason=$reason"); noteBusy262(reason); result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: $reason", null) }
                }
                try {
                    lastGroupChangeAt = System.currentTimeMillis() // Bundle 189 (A)
                    Log.i(TAG, "group join grp=$name mode=password")
                    tags?.noteJoining(name) // Bundle 224 (A2)
                    m.connect(ch, WifiP2pConfig.Builder().setNetworkName(name!!).setPassphrase(key!!).enablePersistentMode(false).build(), listener)
                } catch (e: Exception) { result.error("WIFI_DIRECT", "Wi-Fi Direct operation failed: ${e.message}", null) }
            }
            // Bundle 224 (A, D1): never leave a group LinkUp did not make.
            if (formed && tags?.foreign == true) {
                Log.i(TAG, "WD_FOREIGN_GROUP keep why=join")
                result.error("IN_GROUP_FOREIGN", "This phone is in another app's Wi-Fi Direct group", null)
                return@requestConnectionInfo
            }
            if (formed) {
                lastGroupChangeAt = System.currentTimeMillis() // Bundle 189 (A)
                Log.i(TAG, "group leave before join host=$owner")
                m.removeGroup(ch, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { main.postDelayed({ doJoin() }, 1500L) }
                    override fun onFailure(reason: Int) { main.postDelayed({ doJoin() }, 1500L) }
                })
            } else doJoin()
        }
    }

    /** Bundle 262 (B3): Wi-Fi Direct answers "busy" to every join while the
     *  phone says it is ON (TECNO 19:54-19:57, every 20 s). 3 busy answers
     *  within 90 s with no success between -> the channel is made again with
     *  the same limit as a dropped channel (3 per 10 min). -1 = a success. */
    private fun noteBusy262(reason: Int) {
        main.post {
            val now = SystemClock.elapsedRealtime()
            if (reason != GroupBand262.REASON_BUSY) {
                if (reason < 0) busyAt262.clear()
                return@post
            }
            if (!Busy262.add(busyAt262, now, p2pEnabled)) return@post
            busyAt262.clear()
            val n = NearbyBackgroundPolicy.recentReinits(reinitAt, now)
            if (!NearbyBackgroundPolicy.mayReinit(n)) {
                Log.w(TAG, "WD_BUSY_REINIT skipped n=$n")
                return@post
            }
            reinitAt.add(now)
            Log.w(TAG, "WD_BUSY_REINIT n=${Busy262.COUNT}")
            main.postDelayed({ app?.let { reinit(it) } }, NearbyBackgroundPolicy.REINIT_DELAY_MS)
        }
    }

    /** Bundle 262 (A): makes a group on 2.4 GHz so every phone can hear and
     *  join it (the ZTE Blade A35 has 2.4 GHz only; with the router off the
     *  C71 picked 5745 MHz and the ZTE never saw it). A phone that refuses
     *  the band gets one more try without it. The password is never logged. */
    @androidx.annotation.RequiresApi(29)
    private fun createGroup262(m: WifiP2pManager, ch: WifiP2pManager.Channel, name: String, pass: String,
                               what: String, done: WifiP2pManager.ActionListener) {
        fun config(band: Boolean): WifiP2pConfig {
            val b = WifiP2pConfig.Builder().setNetworkName(name).setPassphrase(pass).enablePersistentMode(false)
            if (band) b.setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_2GHZ)
            return b.build()
        }
        val withBand = GroupBand262.wants(Build.VERSION.SDK_INT)
        val first = try { config(withBand) } catch (_: Exception) { config(false) }
        m.createGroup(ch, first, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = done.onSuccess()
            override fun onFailure(reason: Int) {
                if (!GroupBand262.mayRetry(withBand, reason)) { done.onFailure(reason); return }
                Log.w(TAG, GroupBand262.retryLine(what, reason))
                try { m.createGroup(ch, config(false), done) } catch (_: Exception) { done.onFailure(reason) }
            }
        })
    }

    // Bundle 200 (B): `go` = that phone hosts a Wi-Fi Direct group now.
    private fun peerMap(device: WifiP2pDevice) = mapOf("name" to device.deviceName, "address" to device.deviceAddress, "status" to device.status, "go" to device.isGroupOwner)
}
