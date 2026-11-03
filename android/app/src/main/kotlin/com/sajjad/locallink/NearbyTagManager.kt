package com.sajjad.locallink

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.sajjad.locallink.mesh.LocalNetPolicy
import com.sajjad.locallink.mesh.NearbyGroupPolicy
import com.sajjad.locallink.mesh.NearbyTagPolicy
import java.util.concurrent.ConcurrentHashMap

/**
 * Bundle 155: advertises this phone's LocalLink tag over Wi-Fi Direct
 * service discovery (DNS-SD) and collects the tags of nearby phones, so Dart
 * can map "Wi-Fi Direct address ↔ LocalLink person".
 *
 * Everything runs on the main looper (WifiP2pManager callbacks do too).
 * Failures are logged under the NEARBY tag and never throw.
 */
class NearbyTagManager(
    private val context: Context,
    private val manager: WifiP2pManager,
    private val channel: WifiP2pManager.Channel,
    private val hasPermission: () -> Boolean,
    /** Bundle 160: on a normal Wi-Fi network (published as `wf=1`). */
    private val onWifi: () -> Boolean = { false },
    /** Bundle 200 (C): how many Wi-Fi Direct peers are seen (for the log). */
    private val peerCount: () -> Int = { 0 },
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val tags = ConcurrentHashMap<String, Map<String, Any>>()
    private var tagId: String? = null
    private var host = false
    private var member = false
    private var members = 0
    // Bundle 157: the shared group this phone is in, and who it wants in it.
    private var groupName: String? = null
    private var groupKey: String? = null
    private var ownerAddress: String? = null
    private var wanted: List<String> = emptyList()
    // Bundle 158: this phone bridges its group and a normal Wi-Fi network.
    private var bridge = false
    // Bundle 161: LocalLink hotspot (name + password) and linked group.
    private var hotspotSsid: String? = null
    private var hotspotKey: String? = null
    private var linkTarget: String? = null
    private var lastDiscoveryAt = 0L
    private var lastPublished = ""
    private var listenersSet = false
    private var discoveryScheduled = false
    // Bundle 159: battery care (`pwr=1` + a rough drain estimate in the log).
    private var batteryMarkAt = 0L
    private var batteryMarkLevel = -1
    @Volatile private var charging = false
    // Bundle 167 (5.5): a voice call goes on (or through) this phone.
    @Volatile private var inCall = false
    // Bundle 200 (A): one tag search window at a time. A new start never
    // cancels a running window (the old code restarted every ~5 s, so no
    // tag ever arrived).
    @Volatile private var windowStartedAt = 0L
    private var windowSeq = 0
    private var windowWhy = ""
    private var windowHeard = 0
    private var windowLinkUp = 0
    private var windowRetried = false
    private var windowFixed = false

    /** Bundle 159: (charging, level 0-100 or -1). Never throws. */
    private fun batteryState(): Pair<Boolean, Int> = try {
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

    /** Bundle 159: logs the whole-phone battery drop per hour (an estimate)
     *  every 30 min while not charging, so testers can check the 3%/hour aim. */
    private fun noteBattery(charging: Boolean, level: Int, now: Long) {
        if (charging || level < 0) { batteryMarkAt = 0L; batteryMarkLevel = -1; return }
        if (batteryMarkAt == 0L || batteryMarkLevel < 0) { batteryMarkAt = now; batteryMarkLevel = level; return }
        val ms = now - batteryMarkAt
        if (ms < 30L * 60L * 1000L) return
        val perHour = (batteryMarkLevel - level).coerceAtLeast(0) * 3_600_000.0 / ms
        val role = if (host) "host" else if (member) "member" else "none"
        Log.i(TAG, "battery estimate drop_per_hour=${"%.1f".format(perHour)} level=$level role=$role bridge=$bridge")
        batteryMarkAt = now
        batteryMarkLevel = level
    }

    init {
        tagId = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ID, null)?.takeIf { NearbyTagPolicy.validId(it) }
    }

    /** Dart sends the short hash of this phone's device id once per start. */
    fun setIdentity(id: String?): Boolean {
        val clean = id?.trim()?.lowercase()
        if (!NearbyTagPolicy.validId(clean)) return false
        tagId = clean
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_ID, clean).apply()
        publish(force = true)
        return true
    }

    /** Called with every connection-info update. */
    fun onConnection(groupFormed: Boolean, groupOwner: Boolean) {
        host = groupFormed && groupOwner
        member = groupFormed && !groupOwner
        if (!groupFormed) {
            members = 0
            groupName = null
            groupKey = null
            ownerAddress = null
            publish()
            emitGroup()
            return
        }
        if (!hasPermission()) return
        try {
            // Bundle 157: the host publishes its group name + password (read
            // back from Android, so it also works for groups made the old way);
            // a member publishes only the name.
            manager.requestGroupInfo(channel) { group ->
                members = if (host) group?.clientList?.size ?: 0 else 0
                groupName = group?.networkName?.takeIf { NearbyGroupPolicy.validNetworkName(it) }
                groupKey = if (host) group?.passphrase?.takeIf { NearbyGroupPolicy.validPassphrase(it) } else null
                ownerAddress = group?.owner?.deviceAddress
                publish()
                emitGroup()
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "group info denied: ${e.message}")
            publish()
            emitGroup()
        }
    }

    /** Bundle 157: up to 3 short ids of people this phone wants in its group. */
    fun setWanted(ids: List<String>?) {
        val clean = NearbyTagPolicy.cleanWanted(ids)
        if (clean == wanted) return
        wanted = clean
        publish()
    }

    /** Bundle 167 (5.5): advertise (or stop advertising) `call=1`. */
    fun setInCall(on: Boolean) {
        if (on == inCall) return
        inCall = on
        Log.i(TAG, "call tag ${if (on) "on" else "off"}")
        publish()
    }

    /** Bundle 158: advertise (or stop advertising) `br=1`. */
    fun setBridge(on: Boolean) {
        if (on == bridge) return
        bridge = on
        Log.i(TAG, "bridge ${if (on) "on" else "off"}")
        publish()
    }

    /** Bundle 161: advertise (or clear) this phone's LocalLink hotspot. */
    fun setHotspot(ssid: String?, key: String?) {
        val s = ssid?.takeIf { LocalNetPolicy.validSsid(it) }
        val k = key?.takeIf { LocalNetPolicy.validKey(it) }
        val on = s != null && k != null
        if ((if (on) s else null) == hotspotSsid && (if (on) k else null) == hotspotKey) return
        hotspotSsid = if (on) s else null
        hotspotKey = if (on) k else null
        Log.i(TAG, "hotspot tag ${if (on) "on" else "off"}")
        publish()
    }

    /** Bundle 161: the short id of the group this phone links to (or null). */
    fun setLinkTarget(id: String?) {
        val clean = id?.trim()?.lowercase()?.takeIf { LocalNetPolicy.validLinkId(it) }
        if (clean == linkTarget) return
        linkTarget = clean
        Log.i(TAG, "link tag ${clean ?: "off"}")
        publish()
    }

    /** Bundle 161: the host's IPv6 link-local inside its group (`p2p-…`). */
    private fun groupV6(): String? {
        if (!host) return null
        return try {
            val names = java.net.NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
                .filter { it.isUp && it.name.startsWith("p2p-") }
            names.asSequence()
                .flatMap { it.inetAddresses.toList().asSequence() }
                .filterIsInstance<java.net.Inet6Address>()
                .filter { it.isLinkLocalAddress }
                .map { (it.hostAddress ?: "").substringBefore('%').lowercase() }
                .firstOrNull { LocalNetPolicy.validV6(it) }
        } catch (_: Exception) {
            null
        }
    }

    private fun emitGroup() {
        val role = if (host) "host" else if (member) "member" else "none"
        Log.i(TAG, "group state role=$role members=$members grp=${groupName ?: "-"}")
        emit(mapOf(
            "type" to "my_group",
            "role" to role,
            "name" to groupName,
            "members" to members,
            "owner_address" to ownerAddress,
            // Bundle 159: on a charger (preferred as host/bridge on a tie).
            "charging" to charging,
        ))
    }

    fun publish(force: Boolean = false) {
        val id = tagId ?: return
        if (!hasPermission()) return
        val (nowCharging, level) = batteryState()
        noteBattery(nowCharging, level, System.currentTimeMillis())
        if (nowCharging != charging) {
            charging = nowCharging
            Log.i(TAG, "charger ${if (nowCharging) "on" else "off"}")
            emitGroup()
        }
        val wifi = try { onWifi() } catch (_: Exception) { false }
        val txt = NearbyTagPolicy.encode(id, host, member, members, groupName, groupKey, wanted, bridge, charging, wifi,
            v6 = groupV6(), hotspotSsid = hotspotSsid, hotspotKey = hotspotKey, linkTarget = linkTarget, inCall = inCall)
        val signature = txt.toString()
        if (!force && signature == lastPublished) return
        lastPublished = signature
        val info = WifiP2pDnsSdServiceInfo.newInstance(
            NearbyTagPolicy.INSTANCE_NAME, NearbyTagPolicy.SERVICE_TYPE, txt)
        try {
            manager.clearLocalServices(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = addService(info, txt)
                override fun onFailure(reason: Int) = addService(info, txt)
            })
        } catch (e: SecurityException) {
            lastPublished = ""
            Log.w(TAG, "tag publish denied: ${e.message}")
        }
    }

    private fun addService(info: WifiP2pDnsSdServiceInfo, txt: Map<String, String>) {
        try {
            manager.addLocalService(channel, info, object : WifiP2pManager.ActionListener {
                override fun onSuccess() { Log.i(TAG, "tag published host=${txt["host"]} m=${txt["m"]} n=${txt["n"]} full=${txt["full"]} grp=${txt["g"] ?: "-"} key=${if (txt.containsKey("k")) 1 else 0} w=${txt["w"]?.split(",")?.size ?: 0} br=${txt["br"] ?: "0"} pwr=${txt["pwr"] ?: "0"} wf=${txt["wf"] ?: "0"} v6=${if (txt.containsKey("v6")) 1 else 0} hs=${if (txt.containsKey("hs")) 1 else 0} lt=${txt["lt"] ?: "-"} call=${txt["call"] ?: "0"}") }
                override fun onFailure(reason: Int) {
                    lastPublished = ""
                    Log.w(TAG, "tag publish failed reason=$reason")
                }
            })
        } catch (e: SecurityException) {
            lastPublished = ""
            Log.w(TAG, "tag publish denied: ${e.message}")
        }
    }

    /** Bundle 200 (A): a tag search window is running now. */
    fun searchWindowOpen(now: Long = System.currentTimeMillis()): Boolean =
        SearchWindowPolicy.isOpen(windowStartedAt, now)

    /** Runs a tag search shortly after a peer discovery started (some phones
     *  answer BUSY when both start in the same instant). Bundle 200 (A): never
     *  while a window runs; a random 0-3 s offset so two phones don't start in
     *  the same instant every time. */
    fun scheduleDiscovery(delayMs: Long = 1_500L, why: String = "dart") {
        if (discoveryScheduled || searchWindowOpen()) return
        discoveryScheduled = true
        main.postDelayed({
            discoveryScheduled = false
            discover(why)
        }, delayMs + (Math.random() * SearchWindowPolicy.RANDOM_OFFSET_MS).toLong())
    }

    /** Bundle 157: a new phone appeared nearby — look at its tag soon.
     *  Bundle 200 (A): at most one window per [SearchWindowPolicy.PEERS_GAP_MS]
     *  (was every 8 s, which cut the running window). */
    fun onPeersChanged() {
        val now = System.currentTimeMillis()
        if (searchWindowOpen(now) || now - lastDiscoveryAt < SearchWindowPolicy.PEERS_GAP_MS) return
        scheduleDiscovery(why = "peers")
    }

    private fun discover(why: String = "dart") {
        if (!hasPermission()) return
        // Bundle 184 (E1): no tag search during a voice call.
        if (!CallNearbyPause.searchAllowed()) {
            if (CallNearbyPause.logDue()) Log.i(TAG, "tag search paused call")
            return
        }
        val now = System.currentTimeMillis()
        if (searchWindowOpen(now)) return
        lastDiscoveryAt = now
        openWindow(now, why)
        publish()
        try {
            if (!listenersSet) {
                manager.setDnsSdResponseListeners(channel,
                    { _, _, _ -> },
                    { fullDomainName, txt, device -> onTxt(fullDomainName, txt, device?.deviceAddress) })
                listenersSet = true
            }
            startRequest(windowSeq)
        } catch (e: SecurityException) {
            Log.w(TAG, "tag search denied: ${e.message}")
        }
    }

    /** Bundle 200 (A/C): start a 20 s window and log its end once. */
    private fun openWindow(now: Long, why: String) {
        windowStartedAt = now
        windowSeq += 1
        windowWhy = why
        windowHeard = 0
        windowLinkUp = 0
        windowRetried = false
        windowFixed = false
        val seq = windowSeq
        Log.i(TAG, "WD_SEARCH start window=${SearchWindowPolicy.WINDOW_MS / 1000}s why=$why peers=${safePeerCount()}")
        main.postDelayed({
            if (seq == windowSeq) {
                Log.i(TAG, "WD_SEARCH end why=$windowWhy heard=$windowHeard linkup=$windowLinkUp peers=${safePeerCount()}")
            }
        }, SearchWindowPolicy.WINDOW_MS)
    }

    private fun safePeerCount(): Int = try { peerCount() } catch (_: Exception) { 0 }

    private fun startRequest(seq: Int) {
        val request = WifiP2pDnsSdServiceRequest.newInstance(NearbyTagPolicy.SERVICE_TYPE)
        try {
            manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = addRequest(request, seq)
                override fun onFailure(reason: Int) = addRequest(request, seq)
            })
        } catch (e: SecurityException) {
            Log.w(TAG, "tag search denied: ${e.message}")
        }
    }

    private fun addRequest(request: WifiP2pDnsSdServiceRequest, seq: Int) {
        try {
            manager.addServiceRequest(channel, request, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = discoverServices(seq)
                override fun onFailure(reason: Int) {
                    Log.w(TAG, "WD_TAG_FAIL step=request reason=$reason")
                }
            })
        } catch (e: SecurityException) {
            Log.w(TAG, "tag request denied: ${e.message}")
        }
    }

    private fun discoverServices(seq: Int) {
        try {
            manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() { Log.d(TAG, "tag search started") }
                override fun onFailure(reason: Int) {
                    Log.w(TAG, "WD_TAG_FAIL step=discover reason=$reason")
                    onDiscoverFailed(seq, reason)
                }
            })
        } catch (e: SecurityException) {
            Log.w(TAG, "tag search denied: ${e.message}")
        }
    }

    /** Bundle 200 (A): BUSY -> one retry 3 s later inside the same window;
     *  NO_SERVICE_REQUESTS -> stop peer discovery, clear, add again (once). */
    private fun onDiscoverFailed(seq: Int, reason: Int) {
        if (seq != windowSeq) return
        when (SearchWindowPolicy.onFailure(reason, windowRetried, windowFixed)) {
            SearchWindowPolicy.Retry.LATER -> {
                windowRetried = true
                main.postDelayed({
                    if (seq == windowSeq && searchWindowOpen()) discoverServices(seq)
                }, SearchWindowPolicy.BUSY_RETRY_MS)
            }
            SearchWindowPolicy.Retry.RESET -> {
                windowFixed = true
                try {
                    manager.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() = startRequest(seq)
                        override fun onFailure(reason: Int) = startRequest(seq)
                    })
                } catch (e: SecurityException) {
                    Log.w(TAG, "tag search denied: ${e.message}")
                }
            }
            SearchWindowPolicy.Retry.NONE -> Unit
        }
    }

    private fun onTxt(fullDomainName: String?, txt: Map<String, String>?, address: String?) {
        val now = System.currentTimeMillis()
        windowHeard += 1
        val tag = NearbyTagPolicy.decode(fullDomainName, txt, address, now) ?: return
        windowLinkUp += 1
        tags[tag["address"] as String] = tag
        tags.entries.removeIf { now - ((it.value["seen_at"] as? Long) ?: 0L) > NearbyTagPolicy.TAG_MAX_AGE_MS }
        Log.i(TAG, "tag found id=${tag["id"]} addr=${tag["address"]} host=${tag["host"]} m=${tag["member"]} n=${tag["members"]} grp=${tag["group"] ?: "-"} key=${if (tag.containsKey("key")) 1 else 0}")
        emit(mapOf("type" to "services", "peers" to tags.values.toList()))
    }

    fun snapshot(): List<Map<String, Any>> = tags.values.toList()

    companion object {
        const val TAG = "NEARBY"
        private const val PREFS = "locallink_nearby_tag"
        private const val KEY_ID = "tag_id"
    }
}
