package com.sajjad.locallink

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/** Bundle 175 (4): see [NetworkChangePolicy]. One watcher, inside the transport service. */
class ServiceNetworkWatcher(
    context: Context,
    private val onChange: (NetworkChangePolicy.Snapshot, NetworkChangePolicy.Action) -> Unit,
) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val wifiNetworks = ConcurrentHashMap.newKeySet<Network>()
    @Volatile private var internet = false
    private var last: NetworkChangePolicy.Snapshot? = null
    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var defaultCallback: ConnectivityManager.NetworkCallback? = null

    val snapshot: NetworkChangePolicy.Snapshot
        get() = NetworkChangePolicy.Snapshot(
            wifiNetworks.isNotEmpty(), internet,
            wifiNetworks.map { it.toString() }.sorted().joinToString(","),
        )

    private val emit = Runnable {
        val now = snapshot
        val action = NetworkChangePolicy.decide(last, now)
        if (last == null) Log.i(TAG, "NET_START wifi=${now.wifi} internet=${now.internet}")
        last = now
        if (action != null) onChange(now, action)
    }

    /** Registers once. Safe to call again. */
    fun start() {
        if (wifiCallback != null || connectivity == null) return
        val wifi = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { wifiNetworks.add(network); schedule() }
            override fun onLost(network: Network) { wifiNetworks.remove(network); schedule() }
        }
        val default = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val ok = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                if (ok != internet) { internet = ok; schedule() }
            }
            override fun onLost(network: Network) { if (internet) { internet = false; schedule() } }
        }
        try {
            // No INTERNET capability needed: local-only Wi-Fi counts as Wi-Fi.
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            connectivity.registerNetworkCallback(request, wifi)
            wifiCallback = wifi
            connectivity.registerDefaultNetworkCallback(default)
            defaultCallback = default
            schedule()
        } catch (e: Exception) {
            Log.w(TAG, "NET_WATCH_FAILED reason=${e.javaClass.simpleName}")
            stop()
        }
    }

    fun stop() {
        handler.removeCallbacks(emit)
        wifiCallback?.let { try { connectivity?.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        defaultCallback?.let { try { connectivity?.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        wifiCallback = null
        defaultCallback = null
        wifiNetworks.clear()
        last = null
    }

    private fun schedule() {
        handler.removeCallbacks(emit)
        handler.postDelayed(emit, NetworkChangePolicy.DEBOUNCE_MS)
    }

    companion object { const val TAG = "LocalLinkBoot" }
}
