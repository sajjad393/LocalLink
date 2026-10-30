package com.sajjad.locallink

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.sajjad.locallink.mesh.LocalNetPolicy
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Bundle 161 (tests, off by default): a second Wi-Fi network for LocalLink.
 *
 * - [join]: join another nearby group, or a LocalLink hotspot, as a normal
 *   Wi-Fi user (Android 10+). Android shows its own "Connect?" box. The
 *   network has no internet and never becomes the phone's main network, so
 *   the server connection and mobile data keep working. Once it is up, the
 *   transport service dials one LocalLink link over it.
 * - [startHotspot]: start an Android local-only hotspot (no internet) and
 *   put its name + password in the nearby tag.
 *
 * Everything reports to Dart as `local_net` / `hotspot` events and logs under
 * `LOCAL_NET`. Never throws.
 */
class LocalNetManager private constructor(
    private val context: Context,
    @Volatile private var tags: () -> NearbyTagManager?,
    @Volatile private var emit: (Map<String, Any?>) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var callback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var network: Network? = null
    private var joinKind: String? = null
    private var joinSsid: String? = null
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null
    private var hotspotStarting = false

    init {
        LocalLinkTransportService.localNetListener = { event -> main.post { emit(event) } }
    }

    fun supported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    // ------------------------------------------------------------- join

    /** Join [ssid] with [key]; [v6] = the other host's address (groups). */
    fun join(kind: String, ssid: String, key: String, v6: String?): String? {
        if (!LocalNetPolicy.validKind(kind)) return "bad_kind"
        if (!LocalNetPolicy.validSsid(ssid) || !LocalNetPolicy.validKey(key)) return "bad_network"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            sendState("failed", kind, mapOf("reason" to "unsupported_os"))
            return "unsupported_os"
        }
        if (callback != null && joinSsid == ssid) return null
        leave("switch_network")
        joinKind = kind
        joinSsid = ssid
        return try {
            val specifier = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)
                .setWpa2Passphrase(key)
                .build()
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .setNetworkSpecifier(specifier)
                .build()
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = onJoined(kind, network, v6)
                override fun onUnavailable() {
                    main.post {
                        if (callback !== this) return@post
                        Log.i(TAG, "join unavailable kind=$kind (declined or not found)")
                        clearRequest()
                        sendState("failed", kind, mapOf("reason" to "unavailable"))
                    }
                }
                override fun onLost(network: Network) {
                    main.post {
                        if (callback !== this) return@post
                        Log.i(TAG, "network lost kind=$kind")
                        LocalLinkTransportService.closeLocalNet("network_lost")
                        clearRequest()
                        sendState("left", kind, mapOf("reason" to "network_lost"))
                    }
                }
            }
            callback = cb
            connectivity.requestNetwork(request, cb, LocalNetPolicy.JOIN_TIMEOUT_MS)
            Log.i(TAG, "join requested kind=$kind")
            sendState("joining", kind)
            null
        } catch (e: Exception) {
            Log.w(TAG, "join failed kind=$kind error=${e.message}")
            clearRequest()
            sendState("failed", kind, mapOf("reason" to "request_failed"))
            "request_failed"
        }
    }

    /** The joined network is not "on Wi-Fi" for the rest of the app. */
    fun owns(other: Network): Boolean = network == other

    private fun onJoined(kind: String, network: Network, v6: String?) {
        this.network = network
        val props: LinkProperties? = try { connectivity.getLinkProperties(network) } catch (_: Exception) { null }
        val gateway = props?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
        val dhcp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) props?.dhcpServerAddress?.hostAddress else null
        val targets = LocalNetPolicy.candidates(
            if (kind == LocalNetPolicy.KIND_GROUP) v6 else null, gateway, dhcp, ownAddresses())
        Log.i(TAG, "joined kind=$kind targets=${targets.size} iface=${props?.interfaceName ?: "-"}")
        if (targets.isEmpty()) {
            main.post { sendState("failed", kind, mapOf("reason" to "no_address")) }
            return
        }
        if (!LocalLinkTransportService.connectLocalNet(network, kind, targets, props?.interfaceName)) {
            main.post { sendState("failed", kind, mapOf("reason" to "service_not_running")) }
        }
    }

    private fun ownAddresses(): Set<String> = try {
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            .flatMap { it.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .mapNotNull { it.hostAddress }
            .toSet()
    } catch (_: Exception) {
        emptySet()
    }

    fun leave(reason: String) {
        if (callback == null) return
        val kind = joinKind
        LocalLinkTransportService.closeLocalNet(reason)
        clearRequest()
        Log.i(TAG, "leave kind=$kind reason=$reason")
        sendState("left", kind, mapOf("reason" to reason))
    }

    private fun clearRequest() {
        val cb = callback ?: return
        callback = null
        network = null
        joinKind = null
        joinSsid = null
        try { connectivity.unregisterNetworkCallback(cb) } catch (_: Exception) {}
    }

    // ---------------------------------------------------------- hotspot

    @Suppress("DEPRECATION")
    fun startHotspot(): String? {
        if (hotspot != null || hotspotStarting) return null
        hotspotStarting = true
        return try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspotStarting = false
                    hotspot = reservation
                    var ssid: String? = null
                    var key: String? = null
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val cfg = reservation.softApConfiguration
                        ssid = LocalNetPolicy.unquote(cfg.ssid)
                        key = cfg.passphrase
                    } else {
                        val cfg = reservation.wifiConfiguration
                        ssid = LocalNetPolicy.unquote(cfg?.SSID)
                        key = LocalNetPolicy.unquote(cfg?.preSharedKey)
                    }
                    val usable = LocalNetPolicy.validSsid(ssid) && LocalNetPolicy.validKey(key)
                    Log.i(TAG, "hotspot on usable=$usable")
                    if (usable) tags()?.setHotspot(ssid, key)
                    sendHotspot(if (usable) "on" else "failed", if (usable) null else "no_name")
                    if (!usable) stopHotspot("no_name")
                }

                override fun onStopped() {
                    hotspotStarting = false
                    hotspot = null
                    tags()?.setHotspot(null, null)
                    Log.i(TAG, "hotspot stopped by Android")
                    sendHotspot("off", "stopped")
                }

                override fun onFailed(reason: Int) {
                    hotspotStarting = false
                    hotspot = null
                    val why = LocalNetPolicy.hotspotFailure(reason)
                    Log.i(TAG, "hotspot failed reason=$why")
                    sendHotspot("failed", why)
                }
            }, main)
            Log.i(TAG, "hotspot start requested")
            null
        } catch (e: SecurityException) {
            hotspotStarting = false
            Log.w(TAG, "hotspot denied: ${e.message}")
            sendHotspot("failed", "permission")
            "permission"
        } catch (e: Exception) {
            hotspotStarting = false
            Log.w(TAG, "hotspot error: ${e.message}")
            sendHotspot("failed", "error")
            "error"
        }
    }

    fun stopHotspot(reason: String) {
        val r = hotspot ?: return
        hotspot = null
        try { r.close() } catch (_: Exception) {}
        tags()?.setHotspot(null, null)
        Log.i(TAG, "hotspot off reason=$reason")
        sendHotspot("off", reason)
    }

    fun hotspotOn(): Boolean = hotspot != null

    fun status(): Map<String, Any?> = mapOf(
        "supported" to supported(),
        "joining_kind" to joinKind,
        "hotspot" to (hotspot != null),
    ) + LocalLinkTransportService.localNetStatus()

    fun dispose() {
        leave("app_closed")
        stopHotspot("app_closed")
        LocalLinkTransportService.localNetListener = null
        if (shared === this) shared = null
    }

    private fun sendState(state: String, kind: String?, extra: Map<String, Any?> = emptyMap()) {
        emit(mapOf("type" to "local_net", "state" to state, "kind" to kind) + extra)
    }

    private fun sendHotspot(state: String, reason: String?) {
        emit(mapOf("type" to "hotspot", "state" to state, "reason" to reason))
    }

    companion object {
        const val TAG = "LOCAL_NET"
        @Volatile private var shared: LocalNetManager? = null

        /** One per app process; a re-created screen (rotation) just re-binds,
         *  so a joined network is not dropped (and Android doesn't ask again). */
        fun bind(context: Context, tags: () -> NearbyTagManager?, emit: (Map<String, Any?>) -> Unit): LocalNetManager {
            val existing = shared
            if (existing != null) {
                existing.tags = tags
                existing.emit = emit
                LocalLinkTransportService.localNetListener = { event -> existing.main.post { existing.emit(event) } }
                return existing
            }
            return LocalNetManager(context.applicationContext, tags, emit).also { shared = it }
        }
    }
}
