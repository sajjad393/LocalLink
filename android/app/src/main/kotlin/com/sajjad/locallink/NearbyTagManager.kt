package com.sajjad.locallink

import android.content.Context
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
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
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val tags = ConcurrentHashMap<String, Map<String, Any>>()
    private var tagId: String? = null
    private var host = false
    private var member = false
    private var members = 0
    private var lastPublished = ""
    private var listenersSet = false
    private var discoveryScheduled = false

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
        if (!host) {
            members = 0
            publish()
            return
        }
        if (!hasPermission()) return
        try {
            manager.requestGroupInfo(channel) { group ->
                members = group?.clientList?.size ?: 0
                publish()
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "group info denied: ${e.message}")
            publish()
        }
    }

    fun publish(force: Boolean = false) {
        val id = tagId ?: return
        if (!hasPermission()) return
        val txt = NearbyTagPolicy.encode(id, host, member, members)
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
                override fun onSuccess() { Log.i(TAG, "tag published host=${txt["host"]} m=${txt["m"]} n=${txt["n"]} full=${txt["full"]}") }
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

    private fun discover() {
        if (!hasPermission()) return
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
        Log.i(TAG, "tag found id=${tag["id"]} addr=${tag["address"]} host=${tag["host"]} m=${tag["member"]} n=${tag["members"]}")
        emit(mapOf("type" to "services", "peers" to tags.values.toList()))
    }

    fun snapshot(): List<Map<String, Any>> = tags.values.toList()

    companion object {
        const val TAG = "NEARBY"
        private const val PREFS = "locallink_nearby_tag"
        private const val KEY_ID = "tag_id"
    }
}
