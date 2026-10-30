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
    private var lastDiscoveryAt = 0L
    private var lastPublished = ""
    private var listenersSet = false
    private var discoveryScheduled = false
    // Bundle 159: battery care (`pwr=1` + a rough drain estimate in the log).
    private var batteryMarkAt = 0L
    private var batteryMarkLevel = -1
    @Volatile private var charging = false

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

    /** Bundle 158: advertise (or stop advertising) `br=1`. */
    fun setBridge(on: Boolean) {
        if (on == bridge) return
        bridge = on
        Log.i(TAG, "bridge ${if (on) "on" else "off"}")
        publish()
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
        val txt = NearbyTagPolicy.encode(id, host, member, members, groupName, groupKey, wanted, bridge, charging, wifi)
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
                override fun onSuccess() { Log.i(TAG, "tag published host=${txt["host"]} m=${txt["m"]} n=${txt["n"]} full=${txt["full"]} grp=${txt["g"] ?: "-"} key=${if (txt.containsKey("k")) 1 else 0} w=${txt["w"]?.split(",")?.size ?: 0} br=${txt["br"] ?: "0"} pwr=${txt["pwr"] ?: "0"} wf=${txt["wf"] ?: "0"}") }
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

    /** Runs a tag search shortly after a peer discovery started (some phones
     *  answer BUSY when both start in the same instant). */
    fun scheduleDiscovery(delayMs: Long = 1_500L) {
        if (discoveryScheduled) return
        discoveryScheduled = true
        main.postDelayed({
            discoveryScheduled = false
            discover()
        }, delayMs)
    }

    /** Bundle 157: a new phone appeared nearby — look at its tag soon
     *  (at most once every 8 s). */
    fun onPeersChanged() {
        if (System.currentTimeMillis() - lastDiscoveryAt < 8_000L) return
        scheduleDiscovery()
    }

    private fun discover() {
        if (!hasPermission()) return
        lastDiscoveryAt = System.currentTimeMillis()
        publish()
        try {
            if (!listenersSet) {
                manager.setDnsSdResponseListeners(channel,
                    { _, _, _ -> },
                    { fullDomainName, txt, device -> onTxt(fullDomainName, txt, device?.deviceAddress) })
                listenersSet = true
            }
            val request = WifiP2pDnsSdServiceRequest.newInstance(NearbyTagPolicy.SERVICE_TYPE)
            manager.clearServiceRequests(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = addRequest(request)
                override fun onFailure(reason: Int) = addRequest(request)
            })
        } catch (e: SecurityException) {
            Log.w(TAG, "tag search denied: ${e.message}")
        }
    }

    private fun addRequest(request: WifiP2pDnsSdServiceRequest) {
        try {
            manager.addServiceRequest(channel, request, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    try {
                        manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { Log.d(TAG, "tag search started") }
                            override fun onFailure(reason: Int) { Log.w(TAG, "tag search failed reason=$reason") }
                        })
                    } catch (e: SecurityException) {
                        Log.w(TAG, "tag search denied: ${e.message}")
                    }
                }
                override fun onFailure(reason: Int) { Log.w(TAG, "tag request failed reason=$reason") }
            })
        } catch (e: SecurityException) {
            Log.w(TAG, "tag request denied: ${e.message}")
        }
    }

    private fun onTxt(fullDomainName: String?, txt: Map<String, String>?, address: String?) {
        val now = System.currentTimeMillis()
        val tag = NearbyTagPolicy.decode(fullDomainName, txt, address, now) ?: return
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
